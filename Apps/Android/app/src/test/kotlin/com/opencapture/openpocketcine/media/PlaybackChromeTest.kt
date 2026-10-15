package com.opencapture.openpocketcine.media

import com.opencapture.monitorui.MonitorPlaybackChromeSwipe
import com.opencapture.monitorui.MonitorPlaybackFrameScrub
import com.opencapture.opencine.media.MonitorAudioMeterBallistics
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.media.MonitorAudioMeterChannel
import com.opencapture.monitorui.MonitorPlaybackZoom


class PlaybackChromeTest {
    @Test
    fun pinchAtCenterDoesNotOffset() {
        val zoom =
            MonitorPlaybackZoom().pinchChanged(
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
            MonitorPlaybackZoom().pinchChanged(
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
            MonitorPlaybackZoom().pinchChanged(
                magnification = 8f,
                startAnchorX = 0.5f,
                startAnchorY = 0.5f,
                width = 200f,
                height = 100f,
            )
        assertEquals(MonitorPlaybackZoom.MAX_SCALE, up.scale, 0.001f)
        val down =
            MonitorPlaybackZoom().pinchChanged(
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
            MonitorPlaybackZoom().pinchChanged(
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
        val idle = MonitorPlaybackZoom().panChanged(40f, -10f)
        assertEquals(0f, idle.offsetX, 0.001f)
        val zoomed =
            MonitorPlaybackZoom()
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
        assertEquals(MonitorPlaybackChromeSwipe.HIDE, MonitorPlaybackChromeSwipe.classify(0f, 50f))
        assertEquals(MonitorPlaybackChromeSwipe.SHOW, MonitorPlaybackChromeSwipe.classify(0f, -50f))
        assertEquals(MonitorPlaybackChromeSwipe.NONE, MonitorPlaybackChromeSwipe.classify(0f, 30f))
        assertEquals(MonitorPlaybackChromeSwipe.NONE, MonitorPlaybackChromeSwipe.classify(80f, 50f))
        assertEquals(MonitorPlaybackChromeSwipe.NONE, MonitorPlaybackChromeSwipe.classify(4f, 10f))
    }

    @Test
    fun frameScrubMapsHorizontalDeltaOntoDuration() {
        assertEquals(
            5f,
            MonitorPlaybackFrameScrub.timeAfterDelta(
                originSeconds = 0f,
                deltaPx = 50f,
                videoWidthPx = 100f,
                durationSeconds = 10f,
            ),
            0.001f,
        )
        assertEquals(
            0f,
            MonitorPlaybackFrameScrub.timeAfterDelta(-5f, -100f, 100f, 10f),
            0.001f,
        )
        assertEquals(
            10f,
            MonitorPlaybackFrameScrub.timeAfterDelta(8f, 100f, 100f, 10f),
            0.001f,
        )
        assertEquals(350L, MonitorPlaybackFrameScrub.LONG_PRESS_MS)
    }

    @Test
    fun ballisticsAttackInstantlyAndDecayAtTwentySixDbPerSecond() {
        val loud = MonitorAudioMeterBallistics.step(MonitorAudioMeterChannel.Silent, peakLinear = 1.0, dt = 0.04)
        assertEquals(0.0, loud.levelDB, 1e-9)
        assertEquals(0.0, loud.peakDB, 1e-9)
        val next = MonitorAudioMeterBallistics.step(loud, peakLinear = 0.0, dt = 0.5)
        assertEquals(-MonitorAudioMeterBallistics.LEVEL_DECAY_PER_SECOND * 0.5, next.levelDB, 1e-9)
        assertEquals(0.0, next.peakDB, 1e-9)
        assertEquals(0.5, next.peakAge, 1e-9)
    }

    @Test
    fun peakHoldThenFalls() {
        var channel = MonitorAudioMeterBallistics.step(MonitorAudioMeterChannel.Silent, peakLinear = 1.0, dt = 0.04)
        channel = MonitorAudioMeterBallistics.step(channel, peakLinear = 0.0, dt = 1.0)
        assertEquals(0.0, channel.peakDB, 1e-9)
        channel = MonitorAudioMeterBallistics.step(channel, peakLinear = 0.0, dt = 1.0)
        assertTrue(channel.peakAge > MonitorAudioMeterBallistics.PEAK_HOLD_SECONDS)
        assertTrue(channel.peakDB < 0.0)
        assertEquals(MonitorAudioMeterBallistics.FLOOR_DB, MonitorAudioMeterBallistics.decibels(fromLinear = 0.0), 1e-9)
        assertEquals(0.0, MonitorAudioMeterBallistics.decibels(fromLinear = 1.0), 1e-9)
        assertTrue(abs(MonitorAudioMeterBallistics.decibels(fromLinear = 0.5) - (-6.0206)) < 0.01)
    }

    @Test
    fun identityPlanIsANoOpPlaybackLook() {
        val identity = FeedEffectsRenderPlan.IDENTITY
        assertFalse(identity.hasPlaybackLook)
        assertTrue(com.opencapture.openpocketcine.feed.PlaybackLookEffect(identity).isNoOp(3840, 2160))
    }
}
