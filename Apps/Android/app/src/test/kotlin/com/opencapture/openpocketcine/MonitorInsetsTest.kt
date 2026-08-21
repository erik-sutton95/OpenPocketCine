package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Pure-JVM check of the zone-map leading-inset derivation: the display cutout
 * floored at the synthesized iPhone island lane, plus any transient
 * system-bar lane on the same edge. Copied from OpenZCine `MonitorInsetsTest`.
 */
class MonitorInsetsTest {
    @Test
    fun zeroCutoutFloorsAtTheIslandLane() {
        // Punch-hole that resolves to a zero inset — the floor alone must
        // carve the iPhone-parity left lane.
        assertEquals(IOS_ISLAND_LANE_DP, monitorLeadingInsetDp(0f, 0f))
    }

    @Test
    fun cutoutWiderThanTheLaneWins() {
        assertEquals(70f, monitorLeadingInsetDp(70f, 0f))
    }

    @Test
    fun transientBarAddsItsLaneOnTopOfTheFloor() {
        // Reverse-landscape nav bar on the leading edge: the bar lane stacks
        // on the floored cutout so the feed clears the overlay.
        assertEquals(IOS_ISLAND_LANE_DP + 48f, monitorLeadingInsetDp(0f, 48f))
    }

    @Test
    fun transientBarOverlappingTheCutoutOnlyAddsTheExcess() {
        assertEquals(80f, monitorLeadingInsetDp(70f, 80f))
    }

    @Test
    fun transientBarNarrowerThanTheCutoutAddsNothing() {
        assertEquals(70f, monitorLeadingInsetDp(70f, 40f))
    }

    @Test
    fun portraitBottomInsetKeepsTheSystemRailAboveTheGestureArea() {
        assertEquals(
            PORTRAIT_SYSTEM_RAIL_BOTTOM_INSET_DP,
            monitorBottomInsetDp(rawInsetDp = 0f, isPortrait = true),
        )
        assertEquals(42f, monitorBottomInsetDp(rawInsetDp = 42f, isPortrait = true))
    }

    @Test
    fun landscapeBottomInsetRemainsThePhysicalInset() {
        assertEquals(0f, monitorBottomInsetDp(rawInsetDp = 0f, isPortrait = false))
        assertEquals(42f, monitorBottomInsetDp(rawInsetDp = 42f, isPortrait = false))
    }
}

/** Golden pins from iOS `LiveMonitorLayoutTests.testAuditorPhonePinsLeadingIsland`. */
class LiveMonitorLayoutTest {
    @Test
    fun auditorPhonePinsLeadingIsland() {
        val layout =
            LiveMonitorLayout.fit(
                viewportWidth = 874f,
                viewportHeight = 402f,
                safeLeading = 59f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
            )
        assertEquals(59f, layout.feed.minX, 0.05f)
        assertEquals(0f, layout.feed.minY, 0.05f)
        assertEquals(402f, layout.feed.height, 0.05f)
        assertEquals(402f * 16f / 9f, layout.feed.width, 0.05f)
        assertEquals(773.7f, layout.feed.maxX, 0.2f)
        assertEquals(16f, layout.lock.minX, 0.05f)
        assertTrue(layout.lock.maxX <= layout.feed.minX + 0.05f, "lock sits in the black lane left of the feed")
        assertTrue(layout.record.minX > layout.feed.maxX - 0.5f, "record sits in the black lane")
    }

    @Test
    fun adapterZeroCutoutFeedsTheIslandLaneIntoTheLayout() {
        val leading = monitorLeadingInsetDp(cutoutDp = 0f, transientBarDp = 0f)
        val layout =
            LiveMonitorLayout.fit(
                viewportWidth = 874f,
                viewportHeight = 402f,
                safeLeading = leading,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
            )
        assertEquals(59f, layout.feed.minX, 0.05f)
        assertEquals(16f, layout.lock.minX, 0.05f)
    }

    @Test
    fun rawZeroLeadingWouldParkTheFeedUnderTheLock() {
        val layout =
            LiveMonitorLayout.fit(
                viewportWidth = 874f,
                viewportHeight = 402f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
            )
        assertEquals(0f, layout.feed.minX, 0.05f)
        assertTrue(layout.lock.minX > layout.feed.minX, "without the island floor the lock overlaps the picture")
    }
}

private fun assertEquals(expected: Float, actual: Float, delta: Float) {
    kotlin.test.assertEquals(expected, actual, delta)
}
