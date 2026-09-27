package com.opencapture.openpocketcine.media

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ConformPreviewTest {
    @Test
    fun speedIsTargetOverCaptureAndStretchesDuration() {
        for ((capture, target, speed) in listOf(Triple(60.0, 24.0, 0.4), Triple(120.0, 24.0, 0.2))) {
            assertEquals(speed, ConformPreview.speed(capture, target), "$capture to $target")
        }
        assertEquals("60 → 24 fps · 40%", ConformPreview.label(60.0, 24.0))
        val availability = ConformPreview.availability(ConformPreview.Source(captureRate = 120.0))
        assertEquals(ConformPreview.targetRates, availability.targets)
        val speed = ConformPreview.speed(60.0, 24.0)
        assertEquals(15.0, ConformPreview.conformedDuration(6.0, speed))
        assertEquals("0:15", MediaClipFormatting.durationLabel(ConformPreview.conformedDuration(6.0, speed)))
    }

    @Test
    fun onlySlowerTargets() {
        val thirty = ConformPreview.availability(ConformPreview.Source(captureRate = 30.0))
        assertEquals(listOf(23.976, 24.0, 25.0), thirty.targets)
        val twentyFour = ConformPreview.availability(ConformPreview.Source(captureRate = 24.0))
        assertEquals(ConformPreview.Availability.NotHighFrameRate, twentyFour)
        assertFalse(twentyFour.isAvailable)
    }

    @Test
    fun refusalsExplainWhy() {
        assertEquals(
            ConformPreview.Availability.UnknownRate,
            ConformPreview.availability(ConformPreview.Source()),
        )
        assertEquals(
            ConformPreview.Availability.VariableRate,
            ConformPreview.availability(
                ConformPreview.Source(captureRate = 120.0, isVariableFrameRate = true),
            ),
        )
        assertEquals(
            ConformPreview.Availability.AlreadyConformed,
            ConformPreview.availability(
                ConformPreview.Source(captureRate = 120.0, isAlreadyConformed = true),
            ),
        )
        for (source in listOf(
            ConformPreview.Source(),
            ConformPreview.Source(captureRate = 120.0, isVariableFrameRate = true),
            ConformPreview.Source(captureRate = 120.0, isAlreadyConformed = true),
            ConformPreview.Source(captureRate = 24.0),
        )) {
            assertNotNull(ConformPreview.availability(source).unavailableReason)
        }
    }

    @Test
    fun frameTapRestartsAtEnd() {
        assertEquals(
            PlaybackFrameTap.RESTART_PLAYBACK,
            PlaybackFrameTap.action(chromeVisible = true, reachedEnd = true),
        )
        assertEquals(
            PlaybackFrameTap.TOGGLE_TRANSPORT,
            PlaybackFrameTap.action(chromeVisible = true, reachedEnd = false),
        )
    }

    @Test
    fun aspectFitCentersTheRaster() {
        val rect =
            PlaybackVideoLayout.aspectFitRect(
                PlaybackVideoLayout.Size(16f, 9f),
                PlaybackVideoLayout.Rect(0f, 0f, 320f, 320f),
            )
        assertEquals(320f, rect.width, 0.01f)
        assertEquals(180f, rect.height, 0.01f)
        assertEquals(160f, rect.midY, 0.01f)
        assertEquals(0f, rect.minX, 0.01f)
        assertEquals(320f, rect.maxX, 0.01f)
    }

    @Test
    fun fiftyFpsOffersHalfSpeedAtTwentyFive() {
        val source = ConformPreview.probeLocal(nominalFrameRate = 50.0)
        val availability = ConformPreview.availability(source)
        assertEquals(50.0, source.captureRate)
        assertTrue(availability.targets.contains(25.0))
        assertEquals(0.5, ConformPreview.speed(50.0, 25.0))
        assertEquals("25 fps · 50%", ConformPreview.targetLabel(50.0, 25.0))
        assertEquals("Conform 50 fps to", ConformPreview.menuHeader(50.0))
    }

    @Test
    fun probeResolvesFiftyFpsWithoutReportingVariableRate() {
        val cases =
            listOf(
                "listed rate when the asset is silent" to ConformPreview.probeLocal(listedRate = 50.0),
                "min duration when nominal is zero" to
                    ConformPreview.probeLocal(nominalFrameRate = 0.0, minFrameDurationSeconds = 1.0 / 50.0),
                "timescale artifact is not variable rate" to
                    ConformPreview.probeLocal(nominalFrameRate = 50.0, minFrameDurationSeconds = 1.0 / 1000.0),
                "50 versus 25 is high frame rate, not VFR" to
                    ConformPreview.probeLocal(nominalFrameRate = 25.0, minFrameDurationSeconds = 1.0 / 50.0),
            )
        for ((name, source) in cases) {
            assertEquals(50.0, source.captureRate, name)
            assertFalse(source.isVariableFrameRate, name)
        }
        assertTrue(ConformPreview.availability(cases[0].second).targets.contains(25.0))
    }

    @Test
    fun listedResolutionBecomesTheFeedRaster() {
        assertEquals(
            PlaybackVideoLayout.Size(3840f, 2160f),
            PlaybackVideoLayout.sizeFromResolution("3840x2160"),
        )
        assertEquals(
            PlaybackVideoLayout.Size(1080f, 1920f),
            PlaybackVideoLayout.sizeFromResolution("1080×1920"),
        )
        assertNull(PlaybackVideoLayout.sizeFromResolution(null))
        assertNull(PlaybackVideoLayout.sizeFromResolution("n/a"))
    }

    @Test
    fun letterboxedFeedIsSmallerThanTheScreen() {
        val screen = PlaybackVideoLayout.Rect(0f, 0f, 844f, 390f)
        val feed =
            PlaybackVideoLayout.aspectFitRect(
                PlaybackVideoLayout.Size(3840f, 2160f),
                screen,
            )
        assertTrue(feed.height <= screen.height + 0.01f)
        assertTrue(feed.width < screen.width - 1f)
        assertEquals(screen.midY, feed.midY, 0.01f)
        assertEquals(16f / 9f, feed.width / feed.height, 0.01f)
    }
}
