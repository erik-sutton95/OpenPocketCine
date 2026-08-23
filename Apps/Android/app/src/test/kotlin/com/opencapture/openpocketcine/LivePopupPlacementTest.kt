package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LivePopupPlacementTest {
    @Test
    fun topPickerAnchorsUnderChipLikeOpenZCine() {
        LiveChromeMetrics.scale = 1f
        assertEquals(340f, LiveChromeMetrics.TOP_PICKER_WIDTH, 0.05f)
        assertEquals(8f, LiveChromeMetrics.TOP_PICKER_GAP, 0.05f)

        val width = LiveChromeMetrics.TOP_PICKER_WIDTH
        val viewportW = 874f
        val viewportH = 402f
        val cell = ChromeRect(220f, 14f, 90f, 34f)
        val leading =
            LiveTopPickerPlacement.leadingX(cellMidX = cell.midX, width = width, viewportWidth = viewportW)
        val top =
            LiveTopPickerPlacement.topY(cellMaxY = cell.maxY, panelHeight = 280f, viewportHeight = viewportH)
        assertEquals(cell.midX - width / 2f, leading, 0.05f)
        assertEquals(cell.maxY + 8f, top, 0.05f)

        val leftLeading =
            LiveTopPickerPlacement.leadingX(cellMidX = 40f, width = width, viewportWidth = viewportW)
        assertEquals(8f, leftLeading, 0.05f)
        val rightLeading =
            LiveTopPickerPlacement.leadingX(cellMidX = 850f, width = width, viewportWidth = viewportW)
        assertEquals(viewportW - width - 8f, rightLeading, 0.05f)

        val islandLeading =
            LiveTopPickerPlacement.leadingX(
                cellMidX = 40f,
                width = width,
                viewportWidth = viewportW,
                safeLeading = 59f,
            )
        assertEquals(59f + 4f, islandLeading, 0.05f)

        val rec =
            LivePopupPlacement.topPicker(
                cell = cell,
                panelHeight = LiveChromeMetrics.DRUM_PICKER_HEIGHT + LiveChromeMetrics.PICKER_MODE_BAR_HEIGHT,
                viewportWidth = viewportW,
                viewportHeight = viewportH,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
            )
        val color =
            LivePopupPlacement.topPicker(
                cell = cell,
                panelHeight = LiveChromeMetrics.DRUM_PICKER_HEIGHT,
                viewportWidth = viewportW,
                viewportHeight = viewportH,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
            )
        assertEquals(cell.maxY + 8f, rec.y, 0.05f)
        assertEquals(cell.maxY + 8f, color.y, 0.05f)
        assertTrue(rec.maxHeight > LiveChromeMetrics.DRUM_PICKER_HEIGHT + LiveChromeMetrics.PICKER_MODE_BAR_HEIGHT)
        assertTrue(LiveSheet.FORMAT.isTopPicker)
        assertTrue(LiveSheet.COLOR.isTopPicker)
        assertTrue(!LiveSheet.ISO.isTopPicker)
        assertEquals(340f, rec.width, 0.05f)

        val withBarFloor =
            LivePopupPlacement.topPicker(
                cell = cell,
                panelHeight = LiveChromeMetrics.DRUM_PICKER_HEIGHT,
                viewportWidth = viewportW,
                viewportHeight = viewportH,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                floorY = 330f,
            )
        assertEquals(cell.maxY + 8f, withBarFloor.y, 0.05f)
        assertEquals(340f, withBarFloor.width, 0.05f)
    }

    @Test
    fun topPickerStaysUnderChipWhenPanelTallerThanWell() {
        LiveChromeMetrics.scale = 1f
        val cell = ChromeRect(220f, 14f, 90f, 34f)
        val box =
            LivePopupPlacement.topPicker(
                cell = cell,
                panelHeight = 400f,
                viewportWidth = 874f,
                viewportHeight = 360f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 0f,
                safeBottom = 0f,
                floorY = 300f,
            )
        assertEquals(cell.maxY + 8f, box.y, 0.05f)
        assertEquals(300f - (cell.maxY + 8f), box.maxHeight, 0.05f)
        assertTrue(CaptureLists.topPickerDrumHeight(box.maxHeight, hasTabs = true) <= 176f)
        assertTrue(CaptureLists.topPickerDrumHeight(box.maxHeight, hasTabs = true) >= 104f)
    }

    @Test
    fun capturePickerParksAboveBarOnTile() {
        LiveChromeMetrics.scale = 1f
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
        val tile = ChromeRect(layout.capture.midX - 40f, layout.capture.minY, 80f, 58f)
        val box =
            LivePopupPlacement.capturePicker(
                tile = tile,
                bar = layout.capture,
                panelHeight = 280f,
                viewportWidth = layout.viewportWidth,
                viewportHeight = layout.viewportHeight,
                safeLeading = layout.safeLeading,
                safeTrailing = layout.safeTrailing,
                safeTop = layout.safeTop,
                safeBottom = layout.safeBottom,
            )
        assertEquals(420f, box.width, 0.05f)
        assertEquals(layout.capture.minY - 10f, box.y + 280f, 0.05f)
        assertEquals(tile.midX, box.x + box.width / 2f, 1.0f)
        assertTrue(box.x >= 59f + 4f)
        assertTrue(box.y + minOf(280f, box.maxHeight) <= layout.capture.minY - 10f + 0.05f)
    }

    @Test
    fun capturePickerHeightFollowsContentNotSharedWell() {
        LiveChromeMetrics.scale = 1f
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
        val tile = ChromeRect(layout.capture.midX - 40f, layout.capture.minY, 80f, 58f)
        val shutter =
            LivePopupPlacement.capturePicker(
                tile = tile,
                bar = layout.capture,
                panelHeight = LiveChromeMetrics.DRUM_PICKER_HEIGHT,
                viewportWidth = layout.viewportWidth,
                viewportHeight = layout.viewportHeight,
                safeLeading = layout.safeLeading,
                safeTrailing = layout.safeTrailing,
                safeTop = layout.safeTop,
                safeBottom = layout.safeBottom,
            )
        val withTabs =
            LivePopupPlacement.capturePicker(
                tile = tile,
                bar = layout.capture,
                panelHeight = LiveChromeMetrics.DRUM_PICKER_HEIGHT + LiveChromeMetrics.PICKER_MODE_BAR_HEIGHT,
                viewportWidth = layout.viewportWidth,
                viewportHeight = layout.viewportHeight,
                safeLeading = layout.safeLeading,
                safeTrailing = layout.safeTrailing,
                safeTop = layout.safeTop,
                safeBottom = layout.safeBottom,
            )
        assertEquals(
            layout.capture.minY - 10f,
            shutter.y + LiveChromeMetrics.DRUM_PICKER_HEIGHT,
            0.05f,
        )
        assertEquals(
            layout.capture.minY - 10f,
            withTabs.y + LiveChromeMetrics.DRUM_PICKER_HEIGHT + LiveChromeMetrics.PICKER_MODE_BAR_HEIGHT,
            0.05f,
        )
        assertTrue(withTabs.maxHeight > LiveChromeMetrics.DRUM_PICKER_HEIGHT)
        assertTrue(shutter.y > withTabs.y)
        assertTrue(kotlin.math.abs(shutter.y - withTabs.y) > 0.05f)
    }

    @Test
    fun capturePickerDoesNotGoFullBleed() {
        LiveChromeMetrics.scale = 1f
        val box =
            LivePopupPlacement.capturePicker(
                tile = ChromeRect(0f, 0f, 0f, 0f),
                bar = ChromeRect(20f, 700f, 800f, 58f),
                panelHeight = 500f,
                viewportWidth = 390f,
                viewportHeight = 844f,
                safeLeading = 0f,
                safeTrailing = 0f,
                safeTop = 59f,
                safeBottom = 34f,
            )
        assertTrue(box.width <= 420f)
        assertTrue(box.width < 390f)
        assertTrue(box.y >= 59f + 4f)
        assertTrue(box.y + minOf(500f, box.maxHeight) <= 700f - 10f + 0.05f)
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
