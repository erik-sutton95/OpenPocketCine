package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MonitorAssistPaletteRevealTest {
    @Test fun tapThresholdAndFlickChooseTheSettledState() {
        assertFalse(MonitorAssistPaletteReveal.shouldOpen(0.4f, 0f))
        assertTrue(MonitorAssistPaletteReveal.shouldOpen(0.5f, 0f))
        assertTrue(MonitorAssistPaletteReveal.shouldOpen(0.15f, 300f))
        assertFalse(MonitorAssistPaletteReveal.shouldOpen(0.8f, -300f))
        assertTrue(MonitorAssistPaletteReveal.projectedProgress(0.2f, 400f, 200f) > 0.5f)
        assertEquals(0f, MonitorAssistPaletteReveal.extraToolOpacity(0f))
    }

    @Test
    fun expandedPlateKeepsItsOrderUntilCollapse() {
        val ranked = listOf("LUT", "PEAK", "FALSE")
        val pinned = listOf("PEAK", "FALSE", "LUT")
        assertEquals(pinned, MonitorAssistPaletteReveal.pinnedOrder(ranked, pinned, true))
        assertEquals(ranked, MonitorAssistPaletteReveal.pinnedOrder(ranked, pinned, false))
        assertEquals(
            listOf("PEAK", "WAVE"),
            MonitorAssistPaletteReveal.pinnedOrder(listOf("WAVE", "PEAK"), listOf("PEAK", "GONE", "FALSE"), true),
        )
    }

    @Test fun grabbedPortraitEdgeStaysUnderTheFinger() {
        val full = 400f
        val compact = 90f
        val visible = 90f
        val fingerOnChevron = (full - visible) + 12f
        val grab = MonitorAssistPaletteReveal.portraitGrabOffset(fingerOnChevron, visible, full)
        assertEquals(12f, grab)
        val next = MonitorAssistPaletteReveal.portraitVisibleHeight(
            fingerOnChevron - 40f, grab, compact, full)
        assertEquals(visible + 40f, next)
    }

    @Test fun stillScreenFingerKeepsHeightWhenPopupTopMoves() {
        val full = 400f
        val compact = 90f
        val plateBottom = 1000f
        val fingerScreen = 922f
        val finger = MonitorAssistPaletteReveal.paletteFingerY(fingerScreen, plateBottom, full)
        val grab = MonitorAssistPaletteReveal.portraitGrabOffset(finger, compact, full)
        val raised = MonitorAssistPaletteReveal.portraitVisibleHeight(
            MonitorAssistPaletteReveal.paletteFingerY(fingerScreen - 40f, plateBottom, full),
            grab, compact, full)
        assertEquals(compact + 40f, raised)
        val still = MonitorAssistPaletteReveal.portraitVisibleHeight(
            MonitorAssistPaletteReveal.paletteFingerY(fingerScreen - 40f, plateBottom, full),
            grab, compact, full)
        assertEquals(raised, still)
        val reversed = MonitorAssistPaletteReveal.portraitVisibleHeight(
            MonitorAssistPaletteReveal.paletteFingerY(fingerScreen - 20f, plateBottom, full),
            grab, compact, full)
        assertEquals(compact + 20f, reversed)
    }

    @Test fun dragFromTheArrowScrubsThePlate() {
        assertEquals(0.25f, MonitorAssistPaletteReveal.progress(50f, 200f, false))
        assertEquals(0.75f, MonitorAssistPaletteReveal.progress(-50f, 200f, true))
        assertEquals(40f, MonitorAssistPaletteReveal.translationAlongExpand(10f, -40f, true))
        assertEquals(10f, MonitorAssistPaletteReveal.translationAlongExpand(10f, -40f, false))
    }

    @Test fun landscapeColumnsKeepTheCollapsedStackInPlace() {
        assertEquals(0, MonitorAssistPaletteReveal.landscapeCellIndex(0, 0))
        assertEquals(1, MonitorAssistPaletteReveal.landscapeCellIndex(0, 1))
        assertEquals(2, MonitorAssistPaletteReveal.landscapeCellIndex(1, 0))
    }
}
