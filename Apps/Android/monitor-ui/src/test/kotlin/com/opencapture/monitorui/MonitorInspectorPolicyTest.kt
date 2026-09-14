package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MonitorInspectorPolicyTest {
    @Test fun assistAndGimbalShareTheWidePreferredWidth() {
        assertEquals(460f, MonitorInspectorPolicy.width(800f), .01f)
        assertEquals(480f * .92f, MonitorInspectorPolicy.width(480f), .01f)
        assertEquals(460f, MonitorInspectorPolicy.width(2000f), .01f)
    }

    @Test fun portraitTrailingHeightUsesViewportNotFeedAndNeverFloorsAt280() {
        val short = MonitorInspectorPolicy.height(500f, portrait = true, trailing = true)
        assertEquals(minOf(500f * .52f, 620f), short, .01f)
        assertTrue(short < 280f)
        val tall = MonitorInspectorPolicy.height(1400f, portrait = true, trailing = true)
        assertEquals(620f, tall, .01f)
        assertEquals(852f, MonitorInspectorPolicy.height(852f, portrait = true, trailing = false), .01f)
        assertEquals(402f, MonitorInspectorPolicy.height(402f, portrait = false, trailing = true), .01f)
    }

    @Test fun fittedFillTabletAndSplitWindowsStayCapped() {
        val phonePortrait = MonitorInspectorPolicy.frame(393f, 852f, trailing = true)
        assertTrue(phonePortrait.portrait)
        assertEquals(minOf(852f * .52f, 620f), phonePortrait.height, .01f)
        val tabletLandscape = MonitorInspectorPolicy.frame(1366f, 1024f, trailing = true)
        assertEquals(460f, tabletLandscape.width, .01f)
        assertEquals(1024f, tabletLandscape.height, .01f)
        val split = MonitorInspectorPolicy.frame(320f, 480f, trailing = true)
        assertEquals(minOf(320f, 320f * .92f), split.width, .01f)
        assertEquals(minOf(480f * .52f, 620f), split.height, .01f)
    }

    @Test fun landscapeEdgeInsetUsesTheFullCutoutWithoutACap() {
        assertEquals(0f, MonitorInspectorPolicy.edgeInset(true, false, 59f, 0f), .01f)
        assertEquals(59f, MonitorInspectorPolicy.edgeInset(false, false, 59f, 0f), .01f)
        assertEquals(80f, MonitorInspectorPolicy.edgeInset(false, true, 0f, 80f), .01f)
        assertEquals(20f, MonitorInspectorPolicy.edgeInset(false, false, 20f, 0f), .01f)
    }

    @Test fun landscapePreferredWidthStaysUnchangedWhenTheCutoutIsClearedInternally() {
        assertEquals(460f, MonitorInspectorPolicy.width(800f), .01f)
        assertEquals(480f * .92f, MonitorInspectorPolicy.width(480f), .01f)
    }
}
