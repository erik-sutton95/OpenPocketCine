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
    fun leadingInsetFloorsAtTheIslandLaneAndStacksTransientBars() {
        // why to (cutout, transient bar, expected leading inset)
        val cases = listOf(
            // Punch-hole that resolves to a zero inset: the floor alone carves the iPhone-parity left lane.
            "zero cutout floors at the island lane" to Triple(0f, 0f, IOS_ISLAND_LANE_DP),
            "cutout wider than the lane wins" to Triple(70f, 0f, 70f),
            // Reverse-landscape nav bar on the leading edge stacks on the floored cutout.
            "transient bar adds its lane on top of the floor" to Triple(0f, 48f, IOS_ISLAND_LANE_DP + 48f),
            "transient bar overlapping the cutout only adds the excess" to Triple(70f, 80f, 80f),
            "transient bar narrower than the cutout adds nothing" to Triple(70f, 40f, 70f),
        )
        for ((why, case) in cases) {
            val (cutout, bar, expected) = case
            assertEquals(expected, monitorLeadingInsetDp(cutout, bar), why)
        }
    }

    @Test
    fun bottomInsetKeepsPortraitRailAboveGestureAreaAndLandscapePhysical() {
        // (raw inset, portrait, expected)
        val cases = listOf(
            Triple(0f, true, PORTRAIT_SYSTEM_RAIL_BOTTOM_INSET_DP),
            Triple(42f, true, 42f),
            Triple(0f, false, 0f),
            Triple(42f, false, 42f),
        )
        for ((raw, portrait, expected) in cases) {
            assertEquals(expected, monitorBottomInsetDp(rawInsetDp = raw, isPortrait = portrait), "raw=$raw portrait=$portrait")
        }
    }

    @Test
    fun chromeScaleFloorsOnCompactPhonesLerpsMidSizeAndIsIdentityOnProMax() {
        // (viewport short side, expected scale)
        val cases = listOf(
            360f to CHROME_SCALE_MIN,
            320f to CHROME_SCALE_MIN,
            CHROME_SCALE_REFERENCE_DP to 1f,
            440f to 1f,
            430f to 1f,
            410f to 410f / CHROME_SCALE_REFERENCE_DP,
        )
        for ((width, expected) in cases) {
            assertEquals(expected, monitorChromeScale(width), 0.001f, "width=$width")
        }
        val mid = monitorChromeScale(410f)
        assertTrue(mid > CHROME_SCALE_MIN)
        assertTrue(mid < 1f)
    }
}

/** Golden pins from iOS `LiveMonitorLayoutTests.testAuditorPhonePinsLeadingIsland`. */
class LiveMonitorLayoutTest {
    @Test
    fun portraitOnFeedChromeMatchesSharedFloorAcrossFitAndFill() {
        LiveChromeMetrics.scale = 1f
        for ((w, h, top) in listOf(Triple(393f, 852f, 59f), Triple(744f, 1133f, 0f))) {
            val isTablet = minOf(w, h) >= 600f
            val fitZones = portraitZones(w, h, top, 34f, clean = false, fill = false,
                assistToolbarHeight = 0f, feedAspectRatio = 16f / 9f)
            val fillZones = portraitZones(w, h, top, 34f, clean = false, fill = true,
                assistToolbarHeight = 0f, feedAspectRatio = 16f / 9f)
            val floor = fitZones.assistToolbar.minY
            assertEquals(fillZones.assistToolbar.minY, floor, 0.01f)
            val fitCluster = portraitOnFeedControls(w, floor, showGimbalButton = true)
            val fillCluster = portraitOnFeedControls(w, fillZones.assistToolbar.minY, showGimbalButton = true)
            assertEquals(fitCluster.stick.minX, fillCluster.stick.minX, 0.05f)
            assertEquals(fitCluster.stick.minY, fillCluster.stick.minY, 0.05f)
            assertEquals(fitCluster, fillCluster)
            assertTrue(fitCluster.zoom.maxX < fitCluster.controls.minX)
            assertEquals(fitCluster.zoom.minY, fitCluster.controls.minY, 0.05f)
            assertEquals(portraitAspectToggle(w, floor), portraitAspectToggle(w, fillZones.assistToolbar.minY))
            assertEquals(portraitAssistToolbar(floor, isTablet),
                portraitAssistToolbar(fillZones.assistToolbar.minY, isTablet))
            assertEquals(floor - 16f - com.opencapture.monitorui.MonitorLayoutPolicy.STICK_SIDE, fitCluster.stick.minY, 0.05f)
            assertEquals(w - 16f, fitCluster.stick.maxX, 0.05f)
            assertEquals(w / 2f, portraitAspectToggle(w, floor).midX, 0.05f)
        }
        val fit = portraitZones(440f, 956f, 62f, 34f, clean = false, fill = false,
            assistToolbarHeight = 0f, feedAspectRatio = 16f / 9f)
        val cluster = portraitOnFeedControls(440f, fit.assistToolbar.minY, showGimbalButton = true)
        val toggle = portraitAspectToggle(440f, fit.assistToolbar.minY)
        val rail = portraitAssistToolbar(fit.assistToolbar.minY, false)
        assertTrue(fit.feed.maxY <= cluster.stick.minY + 0.05f)
        assertTrue(fit.feed.maxY <= toggle.minY + 0.05f)
        assertTrue(fit.feed.maxY <= rail.minY + 0.05f)
        LiveChromeMetrics.scale = 1f
    }

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
    fun monitorPictureCentersBetweenCornerRails() {
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
        assertEquals((874f - 402f * 16f / 9f) / 2f, layout.feed.minX, 0.05f)
        assertEquals(0f, layout.feed.minY, 0.05f)
        assertEquals(402f, layout.feed.height, 0.05f)
        assertEquals(402f * 16f / 9f, layout.feed.width, 0.05f)
        assertEquals(874f - layout.feed.minX, layout.feed.maxX, 0.2f)
        assertEquals(14f, layout.lock.minX, 0.05f)
        assertTrue(layout.lock.maxX <= layout.feed.minX + 0.05f, "lock sits in the black lane left of the feed")
        assertTrue(layout.record.minX > layout.feed.maxX - 0.5f, "record sits in the black lane")

        val cutoutFree =
            LiveMonitorLayout.fit(
                viewportWidth = 874f,
                viewportHeight = 402f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
            )
        assertEquals(874f / 2f, cutoutFree.feed.midX, 0.05f)
        assertTrue(cutoutFree.lock.maxX < cutoutFree.feed.minX, "cutout-free phone also centers the picture")
    }

    @Test
    fun compactPhoneRetainsCenteredPictureAndAlignedCornerRail() {
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
        assertEquals(390f, layout.feed.midX, 0.05f)
        assertEquals(360f, layout.feed.height, 0.05f)
        assertEquals(layout.record.midX, layout.settings.midX, 0.05f)
        assertEquals(layout.record.midX, layout.media.midX, 0.05f)
        assertEquals(layout.record.midX, layout.disp.midX, 0.05f)
        assertTrue(layout.rail.maxX <= 780f)
        assertTrue(layout.lock.maxX <= layout.feed.minX + 0.05f)

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
    fun cameraValuesHaveSymmetricInsetsAndIndependentAssistCluster() {
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
        assertEquals(layout.capture.minX, layout.viewportWidth - layout.capture.maxX, 0.05f)
        assertTrue(layout.capture.minX > layout.assist.maxX)
        assertEquals(44f, layout.capture.height, 0.05f)
        val phoneSide = com.opencapture.monitorui.MonitorLayoutPolicy.systemButtonSize(false)
        assertEquals(phoneSide * 2f + 8f + com.opencapture.monitorui.MonitorLayoutPolicy.ASSIST_SPACING, layout.assist.height, 0.05f)
        assertEquals(phoneSide + com.opencapture.monitorui.MonitorLayoutPolicy.ASSIST_HORIZONTAL_INSETS,
            layout.assist.width, 0.05f)

    }

    @Test
    fun gimbalStickStaysOnCanvasOnWidthConstrainedTablets() {
        LiveChromeMetrics.scale = 1f
        // label to (width, height, showsBottomBars)
        val cases = listOf(
            "iPad mini landscape" to Triple(1133f, 744f, true),
            "iPad mini landscape clean" to Triple(1133f, 744f, false),
            "iPad A16 landscape" to Triple(1180f, 820f, true),
        )
        for ((label, case) in cases) {
            val (width, height, bars) = case
            val layout =
                LiveMonitorLayout.fit(
                    viewportWidth = width,
                    viewportHeight = height,
                    safeLeading = 0f,
                    safeTrailing = 0f,
                    safeTop = 0f,
                    safeBottom = 0f,
                    showsBottomBars = bars,
                )
            assertTrue(layout.isWidthConstrained, label)
            assertGimbalStickOnCanvas(layout)
        }
    }

    @Test
    fun cutoutPhoneDropsLockSettingsAndMediaByTwoAndAHalfPercentHudHeight() {
        LiveChromeMetrics.scale = 1f
        val se =
            LiveMonitorLayout.fit(
                viewportWidth = 667f,
                viewportHeight = 375f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
                hasDisplayCutout = false,
            )
        val cutout =
            LiveMonitorLayout.fit(
                viewportWidth = 852f,
                viewportHeight = 393f,
                safeLeading = 59f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                showsBottomBars = true,
                hasDisplayCutout = true,
            )
        val drop = 393f * 0.025f
        assertEquals(se.settings.midY, se.lock.midY, 0.05f)
        assertEquals(52f, se.settings.minY, 0.05f)
        assertEquals(cutout.settings.midY, cutout.lock.midY, 0.05f)
        assertEquals(8f + drop, cutout.settings.minY, 0.05f)
        assertEquals(cutout.settings.minY, cutout.media.minY - 48f - 8f, 0.05f)
        assertEquals(cutout.lock.width, cutout.settings.width, 0.05f)
        assertEquals(cutout.lock.width, cutout.media.width, 0.05f)
        assertEquals(48f, cutout.lock.width, 0.05f)
        assertEquals(22f, cutout.topDeck.midY, 0.05f)
        LiveChromeMetrics.scale = 1f
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
    if (layout.viewportWidth >= layout.viewportHeight) {
        assertTrue(stick.maxX + inset <= layout.record.minX + 0.5f,
            "gimbal cluster parks leading of the entire record/DISP rail")
        assertFalse(stick.intersects(layout.disp), "gimbal stick stays clear of DISP")
        assertFalse(zoom.intersects(layout.disp), "zoom stays clear of DISP")
        assertFalse(layout.topDeck.intersects(layout.settings), "readouts stay clear of settings")
        assertFalse(layout.topDeck.intersects(layout.media), "readouts stay clear of media")
        assertTrue(layout.assist.maxY <= layout.viewportHeight - 7.5f)
        if (minOf(layout.viewportWidth, layout.viewportHeight) >= 600f) {
            val tabletSide = com.opencapture.monitorui.MonitorLayoutPolicy.systemButtonSize(true)
            assertEquals(tabletSide * 2f + 8f + com.opencapture.monitorui.MonitorLayoutPolicy.ASSIST_SPACING, layout.assist.height, 0.05f)
            assertEquals(tabletSide + com.opencapture.monitorui.MonitorLayoutPolicy.ASSIST_HORIZONTAL_INSETS,
                layout.assist.width, 0.05f)
            assertEquals(84f, layout.record.width, .05f)
        }
    }
    if (layout.showsBottomBars) {
        assertTrue(stick.maxY <= layout.capture.minY + 0.05f)
    }
}

private fun assertEquals(expected: Float, actual: Float, delta: Float) {
    kotlin.test.assertEquals(expected, actual, delta)
}
