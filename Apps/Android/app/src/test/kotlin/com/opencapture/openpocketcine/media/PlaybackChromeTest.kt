package com.opencapture.openpocketcine.media

import com.opencapture.openpocketcine.GlassTier
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.OpcIcon
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

    @Test
    fun flatPlaybackUsesDarkenedBarsAndFullDoesNot() {
        assertTrue(PlaybackChromeMetrics.usesDarkenedBars(GlassTier.FLAT))
        assertFalse(PlaybackChromeMetrics.usesDarkenedBars(GlassTier.FULL))
        assertEquals(0.72f, LiveDesign.playbackScrim.alpha, 0.01f)
        assertTrue(LiveDesign.playbackScrim.alpha > LiveDesign.chromePlate.alpha)
        assertEquals(120f, PlaybackChromeMetrics.topScrimDp, 0.01f)
        assertEquals(200f, PlaybackChromeMetrics.bottomScrimDp, 0.01f)
    }

    @Test
    fun viewAssistIconIsNotTheFullscreenIcon() {
        assertEquals(OpcIcon.MAXIMIZE, PlaybackChromeMetrics.hideChromeIcon)
        assertEquals(OpcIcon.MINIMIZE, PlaybackChromeMetrics.showChromeIcon)
        assertEquals(OpcIcon.MONITOR, PlaybackChromeMetrics.viewAssistIcon)
        assertEquals(80L, PlaybackChromeMetrics.SAMPLE_MS)
        assertEquals(480f, PlaybackChromeMetrics.SAMPLE_MAX_SIDE, 0.01f)
        assertTrue(PlaybackChromeMetrics.viewAssistIcon != PlaybackChromeMetrics.hideChromeIcon)
        assertTrue(PlaybackChromeMetrics.viewAssistIcon != PlaybackChromeMetrics.showChromeIcon)
    }

    @Test
    fun argbPackIsRgbaByteOrder() {
        val packed = argb8888ToRgba(intArrayOf(0xFF112233.toInt()))
        assertEquals(0x11, packed[0].toInt() and 0xFF)
        assertEquals(0x22, packed[1].toInt() and 0xFF)
        assertEquals(0x33, packed[2].toInt() and 0xFF)
        assertEquals(0xFF, packed[3].toInt() and 0xFF)
    }

    @Test
    fun identityLookLeavesPixelsAlone() {
        val px = intArrayOf(0xFF8090A0.toInt())
        applyPlaybackLookPixels(px, 1, 1, com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan.IDENTITY)
        assertEquals(0xFF8090A0.toInt(), px[0])
    }

    @Test
    fun identityPlanHasNoPlaybackLook() {
        assertFalse(com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan.IDENTITY.hasPlaybackLook)
        assertTrue(
            com.opencapture.openpocketcine.feed.PlaybackLookEffect(
                com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan.IDENTITY,
            ).isNoOp(3840, 2160),
        )
    }

    @Test
    fun playbackPanelIsDenseEnoughToRead() {
        assertEquals(0.82f, LiveDesign.playbackPanel.alpha, 0.01f)
        assertTrue(LiveDesign.playbackPanel.alpha > LiveDesign.scopePlate.alpha)
        assertTrue(LiveDesign.playbackPanel.alpha < LiveDesign.sheetPlate.alpha)
    }

    @Test
    fun playbackLookKeyIgnoresScopeToggles() {
        val identity = com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan.IDENTITY
        assertEquals(identity.playbackLookKey, identity.playbackLookKey)
        assertFalse(identity.hasPlaybackLook)
    }

    @Test
    fun zebraHighlightPaintsHotPixels() {
        val plan =
            com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan(
                lutCube = null,
                falseColorPaint = null,
                falseColorWeight = null,
                peaking = false,
                peakingColor = floatArrayOf(1f, 0f, 0f),
                peakingRatioThreshold = 2.1f,
                peakingNoiseGate = 0.001f,
                zebraHighlightOn = true,
                zebraHighlightCode = 0.5f,
                zebraHighlightColor = floatArrayOf(1f, 1f, 1f),
                zebraMidtoneOn = false,
                zebraMidtoneCode = 0.5f,
                zebraMidtoneHalf = 0.02f,
                zebraMidtoneColor = floatArrayOf(1f, 0.72f, 0.2f),
                splitComparison = false,
                splitVertical = true,
            )
        val hot = intArrayOf(0xFFFFFFFF.toInt())
        applyPlaybackLookPixels(hot, 1, 1, plan)
        assertEquals(0xFFFFFFFF.toInt(), hot[0])
        val cool = intArrayOf(0xFF101010.toInt())
        applyPlaybackLookPixels(cool, 1, 1, plan)
        assertEquals(0xFF101010.toInt(), cool[0])
    }
}
