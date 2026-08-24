package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
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
    fun compactPhoneChromeScaleFloorsAtTheMinimum() {
        assertEquals(CHROME_SCALE_MIN, monitorChromeScale(360f), 0.001f)
        assertEquals(CHROME_SCALE_MIN, monitorChromeScale(320f), 0.001f)
    }

    @Test
    fun proMaxClassChromeScaleStaysIdentity() {
        assertEquals(1f, monitorChromeScale(CHROME_SCALE_REFERENCE_DP), 0.001f)
        assertEquals(1f, monitorChromeScale(440f), 0.001f)
        assertEquals(1f, monitorChromeScale(430f), 0.001f)
    }

    @Test
    fun midSizePhoneChromeScaleLerps() {
        val scale = monitorChromeScale(410f)
        assertTrue(scale > CHROME_SCALE_MIN)
        assertTrue(scale < 1f)
        assertEquals(410f / CHROME_SCALE_REFERENCE_DP, scale, 0.001f)
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
    fun portraitFillCropsSixteenNineToTheWellCenter() {
        val well = ChromeRect(0f, 95f, 390f, 390f * 16f / 9f)
        val content = portraitFillCropContent(well)
        assertEquals(well.height, content.height, 0.05f)
        assertEquals(well.height * 16f / 9f, content.width, 0.05f)
        assertEquals(well.midX, content.midX, 0.05f)
        assertEquals(well.minY, content.minY, 0.05f)
        assertTrue(content.minX < well.minX)
        assertTrue(content.maxX > well.maxX)
        assertEquals(16f / 9f, content.width / content.height, 0.001f)
    }

    @Test
    fun portraitFillWellOnAPhoneIsTallerThanCinema() {
        val zones =
            portraitZones(
                viewportWidth = 390f,
                viewportHeight = 844f,
                safeTop = 59f,
                safeBottom = 34f,
                clean = false,
                fill = true,
                assistToolbarHeight = 0f,
            )
        assertTrue(zones.feed.height > zones.feed.width * 9f / 16f - 0.5f)
        val content = portraitFillCropContent(zones.feed)
        assertEquals(16f / 9f, content.width / content.height, 0.001f)
        assertEquals(zones.feed.midX, content.midX, 0.05f)
        assertTrue(content.width - zones.feed.width > 1f)
    }

    @Test
    fun verticalPocketPicturePillarsInTheCinemaWell() {
        val cinema =
            LiveMonitorLayout.fit(
                viewportWidth = 874f,
                viewportHeight = 402f,
                safeLeading = 59f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
            )
        val vertical =
            LiveMonitorLayout.fit(
                viewportWidth = 874f,
                viewportHeight = 402f,
                safeLeading = 59f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
                pictureAspect = 9f / 16f,
            )
        assertEquals(cinema.feed.minX, vertical.feed.minX, 0.05f)
        assertEquals(cinema.feed.width, vertical.feed.width, 0.05f)
        assertEquals(cinema.record.midX, vertical.record.midX, 0.05f)
        assertEquals(402f, vertical.picture.height, 0.05f)
        assertEquals(402f * 9f / 16f, vertical.picture.width, 0.5f)
        assertEquals(874f / 2f, vertical.picture.midX, 2f)
        assertTrue(vertical.picture.minX > vertical.feed.minX)
        assertTrue(vertical.picture.maxX < vertical.feed.maxX)
        assertEquals(cinema.zoomButton.minX, vertical.zoomButton.minX, 0.05f)
        assertTrue(vertical.zoomButton.maxX > vertical.picture.maxX)
        assertTrue(vertical.gimbalStick.maxX > vertical.picture.maxX)
    }

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

    @Test
    fun compactPhoneShiftsFeedLeftSoTheRailClearsThePicture() {
        // S25-class 780×360 at compact chrome scale: leftover 140, island 59.
        // 8 dp past the scaled rail nudges the well a few dp left of 59.
        val layout =
            LiveMonitorLayout.fit(
                viewportWidth = 780f,
                viewportHeight = 360f,
                safeLeading = IOS_ISLAND_LANE_DP,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
                chromeScale = CHROME_SCALE_MIN,
            )
        val remaining = 780f - 360f * 16f / 9f
        val expectedX = minOf(IOS_ISLAND_LANE_DP, remaining - LiveChromeMetrics.RAIL_W - 8f)
        assertEquals(expectedX, layout.feed.minX, 0.05f)
        assertTrue(layout.feed.minX < IOS_ISLAND_LANE_DP - 0.5f)
        assertEquals(360f, layout.feed.height, 0.05f)
        assertTrue(layout.record.minX >= layout.feed.maxX - 0.5f, "record does not overlap the feed")
        assertTrue(layout.settings.minX >= layout.feed.maxX - 0.5f, "settings does not overlap the feed")
        assertTrue(layout.media.minX >= layout.feed.maxX - 0.5f, "media does not overlap the feed")
        assertTrue(layout.disp.minX >= layout.feed.maxX - 0.5f, "DISP does not overlap the feed")
        assertTrue(layout.rail.maxX <= 780f + 0.5f, "rail stays on screen")
        assertTrue(layout.lock.maxX <= layout.feed.minX + 0.05f, "lock still sits left of the feed")
    }

    @Test
    fun compactChromeScaleShrinksGimbalStickWithTheRail() {
        LiveChromeMetrics.scale = CHROME_SCALE_MIN
        assertEquals(LiveDesign.GIMBAL_STICK_DP * CHROME_SCALE_MIN, LiveChromeMetrics.STICK, 0.01f)
        assertEquals(LiveDesign.GIMBAL_KNOB_DP * CHROME_SCALE_MIN, LiveChromeMetrics.KNOB, 0.01f)
        assertEquals(LiveDesign.RECORD_SIZE_DP * CHROME_SCALE_MIN, LiveChromeMetrics.RECORD, 0.01f)
        val layout =
            LiveMonitorLayout.fit(
                viewportWidth = 780f,
                viewportHeight = 360f,
                safeLeading = IOS_ISLAND_LANE_DP,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
                chromeScale = CHROME_SCALE_MIN,
            )
        assertEquals(LiveChromeMetrics.STICK, layout.gimbalStick.width, 0.05f)
        assertEquals(LiveChromeMetrics.STICK, layout.gimbalStick.height, 0.05f)
        LiveChromeMetrics.scale = 1f
        assertEquals(LiveDesign.GIMBAL_STICK_DP, LiveChromeMetrics.STICK, 0.01f)
    }

    @Test
    fun bottomBandGrowsAssistWhenCaptureHugsTheTrailingEdge() {
        LiveChromeMetrics.scale = 1f
        val split = bottomBarSplit(barsWidth = 840f, gap = 12f, captureHug = 512f)
        assertEquals(512f, split.captureWidth, 0.05f)
        assertEquals(840f - 12f - 512f, split.assistWidth, 0.05f)
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
        assertEquals(LiveChromeMetrics.BOTTOM_GAP, layout.capture.minX - layout.assist.maxX, 0.05f)
        assertEquals(LiveChromeMetrics.CAPTURE_HUG, layout.capture.width, 0.05f)
        assertTrue(layout.assist.width > (840f - 12f) / 3f + 1f)
    }

    @Test
    fun gimbalStickStaysOnCanvasOnIPadMiniLandscape() {
        LiveChromeMetrics.scale = 1f
        val layout =
            LiveMonitorLayout.fit(
                viewportWidth = 1133f,
                viewportHeight = 744f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
            )
        assertTrue(layout.isWidthConstrained)
        assertGimbalStickOnCanvas(layout)

        val clean =
            LiveMonitorLayout.fit(
                viewportWidth = 1133f,
                viewportHeight = 744f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = false,
            )
        assertTrue(clean.isWidthConstrained)
        assertGimbalStickOnCanvas(clean)
    }

    @Test
    fun gimbalStickStaysOnCanvasOnIPadA16Landscape() {
        LiveChromeMetrics.scale = 1f
        val layout =
            LiveMonitorLayout.fit(
                viewportWidth = 1180f,
                viewportHeight = 820f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
            )
        assertTrue(layout.isWidthConstrained)
        assertGimbalStickOnCanvas(layout)
    }

    @Test
    fun bottomBandKeepsTheThirdsSplitWhenCaptureFits() {
        val split = bottomBarSplit(barsWidth = 600f, gap = 12f, captureHug = 800f)
        assertEquals((600f - 12f) / 3f, split.assistWidth, 0.05f)
        assertEquals((600f - 12f) * 2f / 3f, split.captureWidth, 0.05f)
    }
}

private fun assertGimbalStickOnCanvas(layout: LiveMonitorLayout) {
    val stick = layout.gimbalStick
    val inset = LiveChromeMetrics.STICK_INSET
    assertEquals(LiveChromeMetrics.STICK, stick.width, 0.05f)
    assertTrue(stick.minX >= layout.feed.minX)
    assertTrue(stick.minY >= layout.feed.minY)
    assertTrue(stick.maxY <= layout.viewportHeight - inset + 0.05f)
    assertTrue(stick.maxX <= layout.viewportWidth + 0.05f)
    assertTrue(stick.maxY <= layout.feed.maxY + 0.05f)
    assertFalse(stick.intersects(layout.zoomButton.inset(-1f, -1f)), "gimbal stick stays clear of the zoom chip")
    assertFalse(stick.intersects(layout.record.inset(-1f, -1f)), "gimbal stick stays clear of record")
    val zoom = layout.zoomButton
    val gap = LiveChromeMetrics.STICK_GAP
    assertEquals(stick.maxX, zoom.maxX, 0.2f)
    assertEquals(stick.minY - gap, zoom.maxY, 0.2f)
    assertFalse(zoom.intersects(layout.record.inset(-1f, -1f)), "zoom stays in the gimbal cluster, not on record")
    if (layout.isWidthConstrained) {
        assertEquals(layout.feed.maxX - inset, stick.maxX, 0.5f)
        if (layout.record.width > 1f && layout.record.midX >= layout.feed.midX) {
            assertTrue(stick.maxY + gap <= layout.record.minY + 0.05f)
        }
    }
    if (layout.showsBottomBars) {
        assertTrue(stick.maxY <= layout.capture.minY + 0.05f)
    }
}

private fun assertEquals(expected: Float, actual: Float, delta: Float) {
    kotlin.test.assertEquals(expected, actual, delta)
}
