package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FeedPresentPolicyTest {
    @Test
    fun workingRasterCapsOriginalsAndKeepsAspect() {
        assertEquals(1280 to 720, FeedPresentPolicy.workingSize(1280, 720))
        assertEquals(1440 to 810, FeedPresentPolicy.workingSize(3840, 2160))
        assertEquals(1440 to 810, FeedPresentPolicy.workingSize(2688, 1512))
        assertEquals(1440 to 2560, FeedPresentPolicy.workingSize(2160, 3840))
        assertEquals(1440 to 1080, FeedPresentPolicy.workingSize(1440, 1080))
        assertEquals(0.25f, FeedPresentPolicy.downsampleSpread(3840, 1440))
        assertEquals(0f, FeedPresentPolicy.downsampleSpread(1920, 1440))
        assertEquals(0f, FeedPresentPolicy.downsampleSpread(1280, 1280))
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
    fun duplicateTimestampSkipsUnknownZero() {
        assertFalse(FeedPresentPolicy.isDuplicateFrameTime(0, 0))
        assertFalse(FeedPresentPolicy.isDuplicateFrameTime(1_000, 0))
        assertFalse(FeedPresentPolicy.isDuplicateFrameTime(0, 1_000))
        assertTrue(FeedPresentPolicy.isDuplicateFrameTime(1_000, 1_000))
        assertFalse(FeedPresentPolicy.isDuplicateFrameTime(2_000, 1_000))
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
