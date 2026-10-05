package com.opencapture.openpocketcine

import com.opencapture.monitorui.portraitZones
import com.opencapture.monitorui.livePortraitReadoutFrame
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
}
