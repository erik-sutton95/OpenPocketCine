package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MonitorFeedbackPolicyTest {
    @Test fun compactCaptureFits128WithTheFull86PointDrumInEveryPlacement() {
        for (fromTop in listOf(false, true)) for (portrait in listOf(false, true)) {
            val top = MonitorLayoutPolicy.captureTopPadding(fromTop, portrait, compact = true)
            val bottom = MonitorLayoutPolicy.compactCaptureBottomPadding(top)
            assertEquals(128f, top + MonitorLayoutPolicy.CAPTURE_HEADER_HEIGHT +
                MonitorLayoutPolicy.CAPTURE_STACK_GAP + MonitorLayoutPolicy.CAPTURE_DRUM_HEIGHT + bottom)
            assertTrue(bottom >= 0f)
        }
        assertEquals(16f, MonitorLayoutPolicy.captureTopPadding(true, false, compact = false),
            "Landscape details retain their approved top padding")
    }

    @Test fun quickPointerOwnershipRejectsOtherTilesAndLateReleases() {
        val owner = MonitorQuickGestureOwner()
        val iso = requireNotNull(owner.acquire("ISO"))
        owner.setActive(iso, true)
        assertEquals(null, owner.acquire("WB"))
        owner.release(iso)
        val wb = requireNotNull(owner.acquire("WB"))
        owner.setActive(wb, true)
        owner.release(iso)
        assertEquals("WB", owner.active)
        owner.release(wb)
        val nextISO = requireNotNull(owner.acquire("ISO"))
        owner.setActive(nextISO, true)
        owner.release(iso)
        assertEquals("ISO", owner.active)
        assertEquals(null, owner.acquire("ISO"))
    }

    @Test fun unchangedDragNeverCommitsAnUnknownVisualSeat() {
        assertFalse(MonitorDrumSelection.changedDetent(0f, .49f))
        assertFalse(MonitorDrumSelection.changedDetent(0f, 0f))
        assertTrue(MonitorDrumSelection.changedDetent(0f, .51f))
        assertFalse(MonitorDrumSelection.changedDetent(0f, Float.NaN))
    }

    @Test fun proShortcutsPartitionOnlyDeclaredStopsAndRespectRestrictedModes() {
        assertEquals(MonitorZoomTapStops(listOf(1.0, 3.0), listOf(6.0, 12.0)),
            MonitorZoomTapStops.from(listOf(1.0, 3.0, 6.0, 12.0), listOf(6.0, 12.0)))
        assertEquals(MonitorZoomTapStops(listOf(1.0, 3.0), emptyList()),
            MonitorZoomTapStops.from(listOf(1.0, 3.0), listOf(6.0, 12.0)))
        assertEquals(MonitorZoomTapStops(listOf(1.0, 2.0, 4.0), emptyList()),
            MonitorZoomTapStops.from(listOf(1.0, 2.0, 4.0)))
        assertEquals(listOf(1.0), MonitorZoomTapStops.from(listOf(1.0, Double.NaN, -2.0)).singleTap)
        assertEquals(3.0, MonitorZoomTapStops.from(listOf(1.0, 3.0, 6.0, 12.0), listOf(6.0, 12.0)).next(1.0))
        assertEquals(6.0, MonitorZoomTapStops.from(listOf(1.0, 3.0, 6.0, 12.0), listOf(6.0, 12.0)).next(1.0, extended = true))
        assertEquals("WIDE", MonitorZoomCaption.label(1.0, listOf(1.0, 3.0, 6.0, 12.0)))
        assertEquals("TELE", MonitorZoomCaption.label(3.0, listOf(1.0, 3.0, 6.0, 12.0)))
        assertEquals("DIGITAL · SOFT", MonitorZoomCaption.label(6.0, listOf(1.0, 3.0, 6.0, 12.0)))
        assertEquals("DIGITAL CROP", MonitorZoomCaption.label(2.0, listOf(1.0, 2.0, 4.0)))
        assertFalse(MonitorZoomCaption.isDigital(1.0, listOf(1.0, 3.0)))
        assertFalse(MonitorZoomCaption.isDigital(3.0, listOf(1.0, 3.0)))
        assertTrue(MonitorZoomCaption.isDigital(6.0, listOf(1.0, 3.0)))
        assertTrue(MonitorZoomCaption.isDigital(12.0, listOf(1.0, 3.0)))
    }

    @Test fun allCapturePanelsShareCenterAndBottomWithinSafeBounds() {
        for ((w, h) in listOf(667f to 375f, 874f to 402f, 402f to 874f, 1366f to 1024f)) {
            for (safe in listOf(0f, 59f)) for (panelHeight in listOf(160f, 245f, 900f)) {
                val floor = if (h > w) h - 116f else null
                val panel = MonitorLayoutPolicy.bottomPanel(panelHeight, w, h, safe, 0f, 0f, 0f, floor)
                assertEquals(w / 2f, panel.x + panel.width / 2f, .001f)
                assertTrue(panel.width <= if (minOf(w, h) >= 600f) 620f else 480f)
                assertTrue(panel.x >= maxOf(14f, safe + 4f))
                assertTrue(panel.y >= 14f)
                assertEquals(floor?.minus(12f) ?: h, panel.y + minOf(panelHeight, panel.maxHeight), .001f)
            }
        }
    }

    @Test fun topCapturePanelsShareCenterAndHangFromTheTopEdge() {
        for ((w, h) in listOf(667f to 375f, 874f to 402f, 402f to 874f, 1366f to 1024f)) {
            val floor = if (h > w) h - 116f else null
            val ceiling = if (h > w) 80f else null
            val panel = MonitorLayoutPolicy.topPanel(190f, w, h, 0f, 0f, 0f, 0f, ceiling, floor)
            assertEquals(w / 2f, panel.x + panel.width / 2f, .001f)
            assertEquals(if (h > w) 86f else 0f, panel.y, .001f)
            assertTrue(panel.width <= if (minOf(w, h) >= 600f) 620f else 480f)
        }
    }

    @Test fun portraitTimecodeFollowsTheIndependentStatusRow() {
        assertEquals(51f, MonitorLayoutPolicy.portraitReadoutTop(false, 59f, 51f, 10f))
        assertEquals(0f, MonitorLayoutPolicy.portraitReadoutTop(false, 0f, 0f, 10f))
        assertEquals(51f, MonitorLayoutPolicy.portraitReadoutTop(false, 59f, 51f, 200f))
        assertEquals(16f, MonitorLayoutPolicy.portraitReadoutTop(true, 24f, 16f, 200f))
    }

    @Test fun readoutTypeMatchesApprovedPhoneAndTabletValues() {
        assertEquals(16f, MonitorLayoutPolicy.readoutValueSize(false))
        assertEquals(18f, MonitorLayoutPolicy.readoutValueSize(true))
        assertEquals(9f, MonitorLayoutPolicy.READOUT_LABEL_SIZE)
        assertEquals(1.26f, MonitorLayoutPolicy.READOUT_LABEL_TRACKING)
        assertEquals(19f, MonitorLayoutPolicy.cameraPageTitleSize(false))
        assertEquals(24f, MonitorLayoutPolicy.cameraPageTitleSize(true))
        assertEquals(13f, MonitorLayoutPolicy.CAMERA_CARD_CORNER)
        assertEquals(12f, MonitorLayoutPolicy.DISP_SIZE)
        assertEquals(0.48f, MonitorLayoutPolicy.DISP_TRACKING)
        assertEquals(8f, MonitorLayoutPolicy.SETTINGS_TITLE_CONTENT_GAP)
        assertEquals(128f, MonitorLayoutPolicy.COMPACT_CAPTURE_HEIGHT)
        assertEquals(1f, MonitorLayoutPolicy.compactCaptureBottomPadding(11f))
        assertEquals(0f, MonitorLayoutPolicy.compactCaptureBottomPadding(16f))
        assertTrue(MonitorLayoutPolicy.showsRecordingCategoryTabs(true, false))
        assertTrue(!MonitorLayoutPolicy.showsRecordingCategoryTabs(false, false))
        assertTrue(!MonitorLayoutPolicy.showsRecordingCategoryTabs(true, true))
        assertTrue(MonitorLayoutPolicy.showsCaptureGrabber(false, false))
        assertTrue(!MonitorLayoutPolicy.showsCaptureGrabber(false, true))
        assertTrue(!MonitorLayoutPolicy.showsCaptureGrabber(true, false))
        assertEquals(16f, MonitorLayoutPolicy.capturePanelTopCorner(false, true))
        assertEquals(16f, MonitorLayoutPolicy.capturePanelBottomCorner(false, true))
        assertEquals(16f, MonitorLayoutPolicy.capturePanelTopCorner(false, false))
        assertEquals(0f, MonitorLayoutPolicy.capturePanelBottomCorner(false, false))
        assertEquals(16f, MonitorLayoutPolicy.capturePanelTopCorner(true, true))
        assertEquals(16f, MonitorLayoutPolicy.capturePanelBottomCorner(true, true))
        assertEquals(0f, MonitorLayoutPolicy.capturePanelTopCorner(true, false))
        assertEquals(16f, MonitorLayoutPolicy.capturePanelBottomCorner(true, false))
    }

    @Test fun drumCellsFitTheirLargestLabelWithoutChangingGestureTravel() {
        val short = MonitorDrumSelection.metrics(listOf("100", "12800"))
        val long = MonitorDrumSelection.metrics(listOf("AF-S", "Showcase"))
        assertEquals(1.95f, short.selectedScale)
        assertEquals(1.6f, long.selectedScale)
        assertTrue(long.cellWidth > short.cellWidth)
        assertEquals(1, MonitorDrumSelection.settledIndex(0f, -56f, 6))
    }

    @Test fun audioNumbersStayBoundedAndKeepChannelsIndependent() {
        assertEquals("−21", MonitorAudioReadout.label(-21.4))
        assertEquals("−14", MonitorAudioReadout.label(-14.0))
        assertEquals("−∞", MonitorAudioReadout.label(-60.0))
        assertEquals("—", MonitorAudioReadout.label(Double.NaN))
        assertEquals(0f, MonitorAudioReadout.fraction(Double.NaN))
        assertEquals(1f, MonitorAudioReadout.fraction(10.0))
        assertEquals(0f, MonitorAudioReadout.fraction(-99.0))
    }

    @Test fun audioPlateKeepsTheMockupCrossAxis() {
        assertEquals(28f, MonitorAudioMetrics.CROSS_AXIS)
        assertEquals(168f, MonitorAudioMetrics.LONG_AXIS)
        assertEquals(28f, MonitorAudioMetrics.panelWidth(MonitorAudioOrientation.VERTICAL))
        assertEquals(168f, MonitorAudioMetrics.panelHeight(MonitorAudioOrientation.VERTICAL))
        assertEquals(168f, MonitorAudioMetrics.panelWidth(MonitorAudioOrientation.HORIZONTAL))
        assertEquals(28f, MonitorAudioMetrics.panelHeight(MonitorAudioOrientation.HORIZONTAL))
    }

    @Test fun cutoutPhoneCornerDropIsTwoAndAHalfPercentOfHudHeight() {
        assertEquals(0f, MonitorLayoutPolicy.cutoutPhoneCornerInset(393f, tablet = true, hasDisplayCutout = true))
        assertEquals(0f, MonitorLayoutPolicy.cutoutPhoneCornerInset(393f, tablet = false, hasDisplayCutout = false))
        assertEquals(9.825f, MonitorLayoutPolicy.cutoutPhoneCornerInset(393f, tablet = false, hasDisplayCutout = true), .001f)
    }

    @Test fun assistCellsMatchTheMockupSquareAndSevenColumnMath() {
        assertEquals(54f, MonitorLayoutPolicy.systemButtonSize(false))
        assertEquals(48f, MonitorLayoutPolicy.systemButtonSize(true))
        assertEquals(54f, MonitorLayoutPolicy.assistButtonSize(false))
        assertEquals(48f, MonitorLayoutPolicy.assistButtonSize(true))
        assertEquals(29f, MonitorLayoutPolicy.assistIconSize(false), .01f)
        assertEquals(48f * 29f / 54f, MonitorLayoutPolicy.assistIconSize(true), .01f)
        assertEquals(29f, MonitorLayoutPolicy.assistCompactIconSize(false), .01f)
        assertEquals(27f, MonitorLayoutPolicy.ASSIST_EXPANSION_BUTTON_WIDTH)
        assertEquals(38f, MonitorLayoutPolicy.ASSIST_HORIZONTAL_INSETS)
        assertEquals(54f, MonitorLayoutPolicy.assistCellWidth(874f, false, false))
        assertEquals(54f, MonitorLayoutPolicy.assistCellWidth(393f, true, false))
        assertEquals(48f, MonitorLayoutPolicy.assistCellWidth(1024f, false, true))
    }

    @Test fun glassPlatesUseMockupRgbAndAlphas() {
        assertEquals(20 / 255f, MonitorPalette.panel.red, .002f)
        assertEquals(22 / 255f, MonitorPalette.panel.green, .002f)
        assertEquals(24 / 255f, MonitorPalette.panel.blue, .002f)
        assertEquals(.52f, MonitorPalette.compactGlass.alpha, .01f)
        assertEquals(.62f, MonitorPalette.expandedGlass.alpha, .01f)
        assertEquals(.86f, MonitorPalette.overlayPanel.alpha, .01f)
    }

    @Test fun motionTokensMatchTheMockupMorphs() {
        assertEquals(150, MonitorMotion.PALETTE_MS)
        assertEquals(150, MonitorMotion.INSPECTOR_MS)
        assertEquals(85, MonitorMotion.PICKER_MORPH_MS)
        assertEquals(220, MonitorMotion.DRUM_SETTLE_MS)
        assertEquals(220, MonitorMotion.REC_MORPH_MS)
        assertEquals(260, MonitorMotion.ZOOM_IN_MS)
        assertEquals(180, MonitorMotion.ZOOM_OUT_MS)
        assertEquals(28f, MonitorMotion.INSPECTOR_FROM_PX)
    }
}
