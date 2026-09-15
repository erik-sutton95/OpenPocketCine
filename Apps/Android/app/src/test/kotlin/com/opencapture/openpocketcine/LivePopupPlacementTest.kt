package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LivePopupPlacementTest {
    @Test fun actualPortraitReadoutEdgeAnchorsBothTapAndHoldAcrossFeedLayouts() {
        for ((width, height) in listOf(400f to 800f, 800f to 1100f)) {
            for (fill in listOf(false, true)) for (aspect in listOf(16f / 9f, 9f / 16f)) {
                val zones = portraitZones(width, height, 44f, 34f, clean = false,
                    fill = fill, assistToolbarHeight = 0f, feedAspectRatio = aspect)
                val layout = LiveMonitorLayout.fit(width, height, safeLeading = 0f, safeTrailing = 0f,
                    safeTop = 44f, safeBottom = 34f, showsBottomBars = true)
                val row = livePortraitReadoutFrame(layout, zones)
                val full = LivePopupPlacement.topCapturePanel(220f, width, height,
                    0f, 0f, 44f, 34f, row.maxY, zones.systemBar.minY)
                val compact = com.opencapture.monitorui.MonitorLayoutPolicy.topPanel(128f, width, height,
                    0f, 0f, 44f, 34f, row.maxY, zones.systemBar.minY)
                assertEquals(row.maxY + 6f, full.y, .001f)
                assertEquals(full.y, compact.y, .001f)
                assertEquals(full.x, compact.x, .001f)
                assertEquals(full.width, compact.width, .001f)
            }
        }
    }

    @Test
    fun cameraValuesStayOnTheBottomCenterAnchor() {
        assertTrue(!LiveSheet.FOCUS.isTopAnchored)
        val panel = LivePopupPlacement.bottomCapturePanel(190f, 874f, 402f, 59f, 0f, 0f, 0f)
        assertEquals(437f, panel.x + panel.width / 2f, .001f)
        assertEquals(402f, panel.y + 190f, .001f)
        assertEquals(480f, panel.width)
        val withToolbarFloor = LivePopupPlacement.bottomCapturePanel(
            190f, 874f, 402f, 59f, 0f, 0f, 0f, floorY = 237f,
        )
        assertEquals(panel, withToolbarFloor, "Landscape drawers must not be raised above the assist toolbar")
    }

    @Test
    fun recordingCategoriesHangFromTheLandscapeTopEdge() {
        assertTrue(LiveSheet.FORMAT.isTopAnchored)
        assertTrue(LiveSheet.COLOR.isTopAnchored)
        assertTrue(LiveSheet.MODE.isTopAnchored)
        assertTrue(!LiveSheet.EXPO.isTopAnchored)
        val panel = LivePopupPlacement.topCapturePanel(190f, 874f, 402f, 59f, 0f, 0f, 0f)
        assertEquals(437f, panel.x + panel.width / 2f, .001f)
        assertEquals(0f, panel.y, .001f)
        assertEquals(480f, panel.width)
    }

    @Test
    fun portraitRecordingCategoriesSitBelowTheInfoBar() {
        val panel = LivePopupPlacement.topCapturePanel(
            190f, 393f, 852f, 0f, 0f, 59f, 34f, ceilingY = 80f, floorY = 736f)
        assertEquals(86f, panel.y, .001f)
        assertEquals(393f / 2f, panel.x + panel.width / 2f, .001f)
        assertEquals(365f, panel.width)
    }

    @Test
    fun assistOptionsParksAboveToolbarTrailingToIcon() {
        LiveChromeMetrics.scale = 1f
        val toolbar = ChromeRect(12f, 720f, 360f, 58f)
        val icon = ChromeRect(280f, 724f, 48f, 50f)
        val box =
            LivePopupPlacement.assistOptions(
                icon = icon,
                toolbar = toolbar,
                preferredWidth = 400f,
                panelHeight = 280f,
                viewportWidth = 390f,
                viewportHeight = 844f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 59f,
                safeBottom = 34f,
            )
        assertTrue(box.width <= 400f)
        assertTrue(box.y + minOf(280f, box.maxHeight) <= toolbar.minY - 10f + 0.05f)
        assertTrue(box.y >= 12f)
        assertTrue(box.x + box.width <= icon.maxX + 0.5f || box.x >= 16f)
    }

    @Test
    fun assistOptionsStaysBelowTopDeckCeiling() {
        LiveChromeMetrics.scale = 1f
        val toolbar = ChromeRect(12f, 320f, 360f, 58f)
        val icon = ChromeRect(12f, 324f, 48f, 50f)
        val topDeckBottom = 92f
        val box =
            LivePopupPlacement.assistOptions(
                icon = icon,
                toolbar = toolbar,
                preferredWidth = 400f,
                panelHeight = 400f,
                viewportWidth = 844f,
                viewportHeight = 390f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                ceilingY = topDeckBottom + 8f,
            )
        assertTrue(box.y >= topDeckBottom + 8f - 0.05f, "capture pickers stay under STBY / TC")
        assertTrue(box.y + box.maxHeight <= toolbar.minY - 10f + 0.05f)
    }

    @Test
    fun assistOptionsMayReachTopMargin() {
        LiveChromeMetrics.scale = 1f
        val toolbar = ChromeRect(12f, 320f, 360f, 58f)
        val icon = ChromeRect(12f, 324f, 48f, 50f)
        val box =
            LivePopupPlacement.assistOptions(
                icon = icon,
                toolbar = toolbar,
                preferredWidth = 400f,
                panelHeight = 400f,
                viewportWidth = 844f,
                viewportHeight = 390f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                ceilingY = 0f,
            )
        assertEquals(LivePopupPlacement.ASSIST_MARGIN, box.y, 0.05f)
        assertTrue(box.maxHeight > 200f)
        assertTrue(box.y + box.maxHeight <= toolbar.minY - 10f + 0.05f)
    }

    @Test
    fun assistOptionsKeyboardZeroMatchesPark() {
        LiveChromeMetrics.scale = 1f
        val toolbar = ChromeRect(12f, 720f, 360f, 58f)
        val icon = ChromeRect(280f, 724f, 48f, 50f)
        val parked =
            LivePopupPlacement.assistOptions(
                icon = icon,
                toolbar = toolbar,
                preferredWidth = 400f,
                panelHeight = 280f,
                viewportWidth = 390f,
                viewportHeight = 844f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 59f,
                safeBottom = 34f,
            )
        val zero =
            LivePopupPlacement.assistOptions(
                icon = icon,
                toolbar = toolbar,
                preferredWidth = 400f,
                panelHeight = 280f,
                viewportWidth = 390f,
                viewportHeight = 844f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 59f,
                safeBottom = 34f,
                keyboardHeight = 0f,
            )
        assertEquals(parked, zero)
    }

    @Test
    fun assistOptionsLiftsAboveKeyboardInPortrait() {
        LiveChromeMetrics.scale = 1f
        val toolbar = ChromeRect(12f, 720f, 360f, 58f)
        val icon = ChromeRect(280f, 724f, 48f, 50f)
        val parked =
            LivePopupPlacement.assistOptions(
                icon = icon,
                toolbar = toolbar,
                preferredWidth = 400f,
                panelHeight = 280f,
                viewportWidth = 390f,
                viewportHeight = 844f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 59f,
                safeBottom = 34f,
            )
        val keyboard = 336f
        val lifted =
            LivePopupPlacement.assistOptions(
                icon = icon,
                toolbar = toolbar,
                preferredWidth = 400f,
                panelHeight = 280f,
                viewportWidth = 390f,
                viewportHeight = 844f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 59f,
                safeBottom = 34f,
                keyboardHeight = keyboard,
            )
        val keyboardTop = 844f - keyboard
        val parkedBottom = parked.y + minOf(280f, parked.maxHeight)
        val liftedBottom = lifted.y + minOf(280f, lifted.maxHeight)
        assertTrue(parkedBottom > keyboardTop, "parked zebra card sits under the number pad")
        assertTrue(liftedBottom <= keyboardTop - LiveChromeMetrics.POPUP_GAP + 0.05f)
        assertTrue(lifted.y < parked.y)
    }

    @Test
    fun assistOptionsLiftsAboveKeyboardInLandscape() {
        LiveChromeMetrics.scale = 1f
        val toolbar = ChromeRect(16f, 330f, 276f, 58f)
        val icon = ChromeRect(80f, 330f, 48f, 58f)
        val keyboard = 240f
        val lifted =
            LivePopupPlacement.assistOptions(
                icon = icon,
                toolbar = toolbar,
                preferredWidth = 400f,
                panelHeight = 220f,
                viewportWidth = 874f,
                viewportHeight = 402f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                ceilingY = 68f,
                keyboardHeight = keyboard,
            )
        val keyboardTop = 402f - keyboard
        assertTrue(lifted.y >= 68f - 0.05f)
        assertTrue(
            lifted.y + minOf(220f, lifted.maxHeight) <=
                keyboardTop - LiveChromeMetrics.POPUP_GAP + 0.05f,
        )
    }

    @Test
    fun topStatusChipsArePerCellNotOneStatusBar() {
        assertEquals(
            listOf(
                PocketDispSection.REC_READOUT,
                PocketDispSection.TIMECODE,
                PocketDispSection.FORMAT,
                PocketDispSection.COLOR,
                PocketDispSection.STORAGE,
                PocketDispSection.FPS,
            ),
            TOP_STATUS_CHIPS,
        )
    }
}
