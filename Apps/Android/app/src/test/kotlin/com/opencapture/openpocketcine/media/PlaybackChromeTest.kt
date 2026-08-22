package com.opencapture.openpocketcine.media

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private const val ENCODING_PCM_16BIT = 2
private const val ENCODING_PCM_FLOAT = 4

class PlaybackChromeTest {
    @Test
    fun pinchAtCenterDoesNotOffset() {
        val zoom =
            AnchoredPinchZoom().pinchChanged(
                magnification = 2f,
                startAnchorX = 0.5f,
                startAnchorY = 0.5f,
                width = 100f,
                height = 100f,
            )
        assertEquals(2f, zoom.scale, 0.001f)
        assertEquals(0f, zoom.offsetX, 0.001f)
        assertEquals(0f, zoom.offsetY, 0.001f)
        assertTrue(zoom.isZoomed)
    }

    @Test
    fun pinchAtCornerKeepsThePointUnderTheFinger() {
        val zoom =
            AnchoredPinchZoom().pinchChanged(
                magnification = 2f,
                startAnchorX = 0f,
                startAnchorY = 0f,
                width = 100f,
                height = 100f,
            )
        assertEquals(2f, zoom.scale, 0.001f)
        assertEquals(50f, zoom.offsetX, 0.001f)
        assertEquals(50f, zoom.offsetY, 0.001f)
    }

    @Test
    fun pinchClampsAtFourAndNeverBelowOne() {
        val up =
            AnchoredPinchZoom().pinchChanged(
                magnification = 8f,
                startAnchorX = 0.5f,
                startAnchorY = 0.5f,
                width = 200f,
                height = 100f,
            )
        assertEquals(AnchoredPinchZoom.MAX_SCALE, up.scale, 0.001f)
        val down =
            AnchoredPinchZoom().pinchChanged(
                magnification = 0.2f,
                startAnchorX = 0.5f,
                startAnchorY = 0.5f,
                width = 200f,
                height = 100f,
            )
        assertEquals(1f, down.scale, 0.001f)
        assertFalse(down.isZoomed)
    }

    @Test
    fun endGestureBelowThresholdResets() {
        val zoomed =
            AnchoredPinchZoom().pinchChanged(
                magnification = 1.03f,
                startAnchorX = 0.5f,
                startAnchorY = 0.5f,
                width = 100f,
                height = 100f,
            )
        val ended = zoomed.endGesture(100f, 100f)
        assertEquals(1f, ended.scale, 0.001f)
        assertFalse(ended.isZoomed)
    }

    @Test
    fun panOnlyAppliesWhileZoomedAndClampsOnEnd() {
        val idle = AnchoredPinchZoom().panChanged(40f, -10f)
        assertEquals(0f, idle.offsetX, 0.001f)
        val zoomed =
            AnchoredPinchZoom()
                .pinchChanged(2f, 0.5f, 0.5f, 100f, 100f)
                .endGesture(100f, 100f)
                .panChanged(400f, 400f)
                .endGesture(100f, 100f)
        // scale 2 on 100×100 → max offset 50
        assertEquals(50f, zoomed.offsetX, 0.001f)
        assertEquals(50f, zoomed.offsetY, 0.001f)
    }

    @Test
    fun chromeSwipeHidesOnDownAndShowsOnUp() {
        assertEquals(PlaybackChromeSwipe.HIDE, PlaybackChromeSwipe.classify(0f, 50f))
        assertEquals(PlaybackChromeSwipe.SHOW, PlaybackChromeSwipe.classify(0f, -50f))
        assertEquals(PlaybackChromeSwipe.NONE, PlaybackChromeSwipe.classify(0f, 30f))
        assertEquals(PlaybackChromeSwipe.NONE, PlaybackChromeSwipe.classify(80f, 50f))
        assertEquals(PlaybackChromeSwipe.NONE, PlaybackChromeSwipe.classify(4f, 10f))
    }

    @Test
    fun frameScrubMapsHorizontalDeltaOntoDuration() {
        assertEquals(
            5f,
            PlaybackFrameScrub.timeAfterDelta(
                originSeconds = 0f,
                deltaPx = 50f,
                videoWidthPx = 100f,
                durationSeconds = 10f,
            ),
            0.001f,
        )
        assertEquals(
            0f,
            PlaybackFrameScrub.timeAfterDelta(-5f, -100f, 100f, 10f),
            0.001f,
        )
        assertEquals(
            10f,
            PlaybackFrameScrub.timeAfterDelta(8f, 100f, 100f, 10f),
            0.001f,
        )
        assertEquals(350L, PlaybackFrameScrub.LONG_PRESS_MS)
    }

    @Test
    fun ballisticsAttackInstantlyAndDecayAtTwentySixDbPerSecond() {
        val loud = AudioMeterBallistics.step(AudioMeterChannel.Silent, peakLinear = 1.0, dt = 0.04)
        assertEquals(0.0, loud.levelDB, 1e-9)
        assertEquals(0.0, loud.peakDB, 1e-9)
        val next = AudioMeterBallistics.step(loud, peakLinear = 0.0, dt = 0.5)
        assertEquals(-AudioMeterBallistics.LEVEL_DECAY_PER_SECOND * 0.5, next.levelDB, 1e-9)
        assertEquals(0.0, next.peakDB, 1e-9)
        assertEquals(0.5, next.peakAge, 1e-9)
    }

    @Test
    fun peakHoldThenFalls() {
        var channel = AudioMeterBallistics.step(AudioMeterChannel.Silent, peakLinear = 1.0, dt = 0.04)
        channel = AudioMeterBallistics.step(channel, peakLinear = 0.0, dt = 1.0)
        assertEquals(0.0, channel.peakDB, 1e-9)
        channel = AudioMeterBallistics.step(channel, peakLinear = 0.0, dt = 1.0)
        assertTrue(channel.peakAge > AudioMeterBallistics.PEAK_HOLD_SECONDS)
        assertTrue(channel.peakDB < 0.0)
        assertEquals(AudioMeterBallistics.FLOOR_DB, AudioMeterBallistics.decibels(fromLinear = 0.0), 1e-9)
        assertEquals(0.0, AudioMeterBallistics.decibels(fromLinear = 1.0), 1e-9)
        assertTrue(abs(AudioMeterBallistics.decibels(fromLinear = 0.5) - (-6.0206)) < 0.01)
    }

    @Test
    fun pcmFloatAndInt16PeaksMatchIosMaxMagnitude() {
        val floatBuf =
            ByteBuffer.allocate(4 * 4).order(ByteOrder.LITTLE_ENDIAN).apply {
                asFloatBuffer().put(floatArrayOf(0.25f, -0.5f, 1f, 0.1f))
                rewind()
            }
        val floatPeaks = PlaybackPcmPeaks.ingest(floatBuf, ENCODING_PCM_FLOAT, 2)
        assertEquals(1f, floatPeaks.first, 0.001f)
        assertEquals(0.5f, floatPeaks.second, 0.001f)

        val pcm16 =
            ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).apply {
                asShortBuffer().put(shortArrayOf(32767, 16384, 0, -8192))
                rewind()
            }
        val intPeaks = PlaybackPcmPeaks.ingest(pcm16, ENCODING_PCM_16BIT, 2)
        assertEquals(1f, intPeaks.first, 0.02f)
        assertEquals(0.5f, intPeaks.second, 0.02f)

        val mono =
            ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).apply {
                asFloatBuffer().put(floatArrayOf(0.4f, -0.8f))
                rewind()
            }
        val monoPeaks = PlaybackPcmPeaks.ingest(mono, ENCODING_PCM_FLOAT, 1)
        assertEquals(0.8f, monoPeaks.first, 0.001f)
        assertEquals(0.8f, monoPeaks.second, 0.001f)
    }

    @Test
    fun metersMuteWhileConformingAndKeepPeaksOtherwise() {
        val box = AudioLevelTapBox()
        box.ingest(0.9f, 0.4f)
        assertEquals(0f to 0f, box.peaksForMeters(conforming = true))
        box.ingest(0.7f, 0.2f)
        val live = box.peaksForMeters(conforming = false)
        assertEquals(0.7f, live.first, 0.001f)
        assertEquals(0.2f, live.second, 0.001f)
    }

    @Test
    fun transportRowFitsNarrowestPhoneLikeIos() {
        val needed = PlaybackChromeMetrics.transportRowWidth()
        val usable = PlaybackChromeMetrics.narrowestScreenWidth - PlaybackChromeMetrics.chromeHorizontalPadding * 2
        assertTrue(needed <= usable, "needed=$needed usable=$usable")
    }
}
