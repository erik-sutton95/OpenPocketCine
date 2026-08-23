package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LiveViewPresentTimingTest {
    @Test
    fun ptsUsesWallClockSoFiftyPIsNotPacedAtThirty() {
        val t0 = 2_000_000_000L
        val first = LiveViewPresentTiming.ptsUs(t0, lastPtsUs = 0L)
        assertEquals(2_000_000L, first)
        val twentyMsLater = LiveViewPresentTiming.ptsUs(t0 + 20_000_000L, first)
        assertEquals(2_020_000L, twentyMsLater)
        assertEquals(20_000L, twentyMsLater - first)
        assertTrue(twentyMsLater - first < 33_333L)
    }

    @Test
    fun ptsStaysStrictlyIncreasingOnATiedClock() {
        val now = 5_000_000_000L
        val first = LiveViewPresentTiming.ptsUs(now, 0L)
        val second = LiveViewPresentTiming.ptsUs(now, first)
        assertEquals(first + 1L, second)
    }

    @Test
    fun pFramesDoNotBlockIngestButIdrMayWait() {
        assertEquals(0L, LiveViewPresentTiming.inputWaitUs(false))
        assertEquals(50_000L, LiveViewPresentTiming.inputWaitUs(true))
    }
}
