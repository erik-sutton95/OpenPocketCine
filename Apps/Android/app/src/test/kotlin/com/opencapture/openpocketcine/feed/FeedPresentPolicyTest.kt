package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FeedPresentPolicyTest {
    @Test
    fun freezeThresholdIsTwoSeconds() {
        assertEquals(2.0, FeedPresentPolicy.FREEZE_THRESHOLD_SECONDS)
        assertEquals(1440, FeedPresentPolicy.MAX_WORKING_WIDTH)
    }

    @Test
    fun shouldRenderRequiresVisibleEnabledDrawable() {
        assertTrue(FeedPresentPolicy.shouldRender(true, true, false, true))
        assertFalse(FeedPresentPolicy.shouldRender(false, true, false, true))
        assertFalse(FeedPresentPolicy.shouldRender(true, false, false, true))
        assertFalse(FeedPresentPolicy.shouldRender(true, true, true, true))
        assertFalse(FeedPresentPolicy.shouldRender(true, true, false, false))
    }

    @Test
    fun overlayMayScheduleBakeWhileHidden() {
        assertTrue(FeedPresentPolicy.shouldScheduleBake(true, true))
        assertFalse(FeedPresentPolicy.shouldScheduleBake(false, true))
        assertFalse(FeedPresentPolicy.shouldScheduleBake(true, false))
    }

    @Test
    fun duplicateTimestampSkipsUnknownZero() {
        assertFalse(FeedPresentPolicy.isDuplicateFrameTime(0, 0))
        assertFalse(FeedPresentPolicy.isDuplicateFrameTime(1_000, 0))
        assertFalse(FeedPresentPolicy.isDuplicateFrameTime(0, 1_000))
        assertTrue(FeedPresentPolicy.isDuplicateFrameTime(1_000, 1_000))
        assertFalse(FeedPresentPolicy.isDuplicateFrameTime(2_000, 1_000))
    }

    @Test
    fun freezeIsAgeNotMissingClock() {
        assertFalse(FeedPresentPolicy.isFrozen(null))
        assertFalse(FeedPresentPolicy.isFrozen(1.9))
        assertTrue(FeedPresentPolicy.isFrozen(2.0))
        assertTrue(FeedPresentPolicy.isFrozen(8.0))
    }

    @Test
    fun overlayBakeDoesNotStealReplaceOwnership() {
        assertFalse(FeedPresentPolicy.replaceOwnsPicture(true, true))
        assertFalse(FeedPresentPolicy.replaceOwnsPicture(false, false))
        assertTrue(FeedPresentPolicy.replaceOwnsPicture(true, false))
    }

    @Test
    fun unhideBeforeReplaceBakeOnly() {
        assertTrue(FeedPresentPolicy.unhideMetalBeforeBake(false))
        assertFalse(FeedPresentPolicy.unhideMetalBeforeBake(true))
    }

    @Test
    fun monitorGradePrefersProxy() {
        assertTrue(FeedPresentPolicy.preferProxyForMonitorGrade(true))
        assertFalse(FeedPresentPolicy.preferProxyForMonitorGrade(false))
    }

    @Test
    fun flushIsDisconnectOrFailedLayerWithReplacement() {
        assertTrue(FeedPresentPolicy.shouldFlushDisplayedImage(true, false, false))
        assertFalse(FeedPresentPolicy.shouldFlushDisplayedImage(false, false, false))
        assertFalse(FeedPresentPolicy.shouldFlushDisplayedImage(false, true, false))
        assertTrue(FeedPresentPolicy.shouldFlushDisplayedImage(false, true, true))
    }

    @Test
    fun serialGateRefusesOverlap() {
        val gate = SerialSessionGate()
        assertTrue(gate.begin())
        assertFalse(gate.begin())
        assertTrue(gate.inFlight)
        gate.end()
        assertTrue(gate.begin())
        gate.end()
        assertFalse(gate.inFlight)
    }
}
