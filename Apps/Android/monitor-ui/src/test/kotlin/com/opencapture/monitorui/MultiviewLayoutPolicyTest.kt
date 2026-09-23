package com.opencapture.monitorui

import com.opencapture.monitorui.MultiviewArrangement.CENTER_STAGE
import com.opencapture.monitorui.MultiviewArrangement.GRID
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Mirrors Tests/MonitorPresentationTests/MultiviewPresentationLayoutTests.swift. */
class MultiviewLayoutPolicyTest {
    @Test
    fun everyDeviceKeepsFourStableTilesAndReachableTransport() {
        val sizes = listOf(
            667f to 375f, 844f to 390f, 852f to 393f, 956f to 440f, 976f to 448f,
            1133f to 744f, 1194f to 834f, 1366f to 1024f,
        )
        for ((width, height) in sizes) for (portrait in listOf(false, true)) for (right in listOf(false, true)) {
            val w = if (portrait) height else width
            val h = if (portrait) width else height
            val phone = minOf(w, h) < 600
            val cutout = phone && width != 667f
            val safe = MultiviewSafeArea(
                top = if (portrait && cutout) 59f else 0f,
                leading = if (!portrait && cutout && !right) 59f else 0f,
                bottom = if (width == 667f) 0f else 21f,
                trailing = if (!portrait && cutout && right) 59f else 0f,
            )
            for (arrangement in MultiviewArrangement.entries) for (selected in 0 until 4) {
                val layout = MultiviewPresentationLayout.compute(w, h, safe, arrangement, selected)
                val case = "$w x $h $safe $arrangement $selected"
                assertEquals(4, layout.tiles.size)
                val frames = layout.tiles + listOf(
                    layout.record, layout.display, layout.sessionControls, layout.assists, layout.network,
                )
                for (frame in frames) {
                    assertTrue(frame.x >= 0 && frame.y >= 0, case)
                    assertTrue(frame.width > 0 && frame.height > 0, case)
                    assertTrue(frame.maxX <= w + 0.1f && frame.maxY <= h + 0.1f, case)
                }
                for (first in 0 until 4) {
                    for (second in first + 1 until 4) {
                        assertFalse(overlaps(layout.tiles[first], layout.tiles[second]), case)
                    }
                    if (arrangement == CENTER_STAGE && first != selected) {
                        val tile = layout.tiles[first]
                        assertTrue(abs(tile.width / tile.height - 16f / 9f) < 0.001f, case)
                        assertFalse(overlaps(tile, layout.record), case)
                    }
                }
                if (arrangement == GRID) {
                    for (tile in layout.tiles) for (control in listOf(
                        layout.sessionControls, layout.assists, layout.network, layout.record, layout.display,
                    )) assertFalse(overlaps(tile, control), case)
                }
                assertFalse(overlaps(layout.record, layout.display), case)
                assertFalse(overlaps(layout.network, layout.record), case)
                assertFalse(overlaps(layout.network, layout.display), case)
                assertTrue(layout.network.y > layout.assists.maxY, case)
                assertTrue(layout.network.width >= 44 && layout.network.height >= 44, case)
                val fitCenterX =
                    if (layout.assistsHorizontal) layout.assists.maxX - 4 - layout.controlCellSize / 2
                    else layout.assists.midX
                assertEquals(fitCenterX, layout.network.midX, 0.001f, case)
            }
        }
    }

    @Test
    fun portraitStageUsesOneColumnOfSecondaryCameras() {
        val layout = MultiviewPresentationLayout.compute(
            393f, 852f, MultiviewSafeArea(top = 59f, bottom = 34f), CENTER_STAGE, 2,
        )
        val main = layout.tiles[2]
        val thumbs = layout.tiles.filterIndexed { index, _ -> index != 2 }
        assertEquals(393f, main.width)
        assertTrue(abs(main.width / main.height - 16f / 9f) < 0.001f)
        assertTrue(thumbs.all { it.y > main.maxY && abs(it.midX - 393f / 2) < 0.01f })
        assertTrue(thumbs[0].y < thumbs[1].y && thumbs[1].y < thumbs[2].y)
    }

    @Test
    fun switchingLayoutDoesNotMoveSessionControls() {
        for ((width, height) in listOf(852f to 393f, 393f to 852f, 1194f to 834f)) {
            val grid = MultiviewPresentationLayout.compute(width, height, arrangement = GRID, selected = 0)
            val stage = MultiviewPresentationLayout.compute(width, height, arrangement = CENTER_STAGE, selected = 3)
            assertEquals(grid.record, stage.record)
            assertEquals(grid.display, stage.display)
            assertEquals(grid.sessionControls, stage.sessionControls)
            assertEquals(grid.assists, stage.assists)
        }
    }

    @Test
    fun floatingControlsUseReferenceRowsAndColumnsWithoutShrinkingTargets() {
        for ((width, height) in listOf(393f to 852f, 852f to 393f, 744f to 1133f, 1133f to 744f)) {
            val layout = MultiviewPresentationLayout.compute(width, height, arrangement = GRID, selected = 0)
            val landscapeTablet = layout.tablet && !layout.portrait
            val cell = if (layout.tablet) 52f else 44f
            assertEquals(cell, layout.controlCellSize)
            assertEquals(landscapeTablet, layout.sessionControlsHorizontal)
            assertEquals(landscapeTablet || layout.portrait, layout.assistsHorizontal)
            for ((frame, horizontal) in listOf(
                layout.sessionControls to layout.sessionControlsHorizontal,
                layout.assists to layout.assistsHorizontal,
            )) {
                // Two square controls, a 3dp gap, and 4dp glass padding per edge.
                assertEquals(if (horizontal) cell * 2 + 11 else cell + 8, frame.width)
                assertEquals(if (horizontal) cell + 8 else cell * 2 + 11, frame.height)
            }
        }
    }

    @Test
    fun landscapeGridUsesHeightAndWidthBetweenControls() {
        val layout = MultiviewPresentationLayout.compute(
            956f, 440f, MultiviewSafeArea(leading = 62f, bottom = 21f), GRID, 0,
        )
        val left = layout.tiles[0]
        val right = layout.tiles[1]
        val bottom = layout.tiles[2]
        assertTrue(left.width > 350)
        assertTrue(left.height > 190)
        assertEquals(12f, left.y)
        assertEquals(409f, bottom.maxY)
        assertEquals(layout.display.x - 10, right.maxX)
    }

    @Test
    fun tabletGridReservesWindowControlInset() {
        for ((width, height) in listOf(744f to 1133f, 1133f to 744f)) {
            val layout = MultiviewPresentationLayout.compute(
                width, height, arrangement = GRID, selected = 0, topControlInset = 28f,
            )
            assertEquals(layout.sessionControls.maxY + 10, layout.tiles[0].y)
            for (tile in layout.tiles) assertFalse(overlaps(tile, layout.sessionControls))
        }
    }

    /** Expected rectangles printed by the Swift implementation. */
    @Test
    fun matchesSwiftGeometryExactly() {
        val cases = listOf(
            Pinned(
                393f, 852f, MultiviewSafeArea(59f, 0f, 34f, 0f),
                controls = listOf(r(14f, 79f, 52f, 99f), r(18f, 678f, 99f, 52f), r(69f, 733f, 44f, 44f), r(251f, 777f, 48f, 48f), r(309f, 766f, 70f, 70f)),
                grid = listOf(r(14f, 188f, 177.5f, 235f), r(201.5f, 188f, 177.5f, 235f), r(14f, 433f, 177.5f, 235f), r(201.5f, 433f, 177.5f, 235f)),
                stage = listOf(r(0f, 69f, 393f, 221.0625f), r(93.4074074074074f, 300.0625f, 206.1851851851852f, 115.97916666666667f), r(93.4074074074074f, 426.0416666666667f, 206.1851851851852f, 115.97916666666667f), r(93.4074074074074f, 552.0208333333334f, 206.1851851851852f, 115.97916666666667f)),
            ),
            Pinned(
                852f, 393f, MultiviewSafeArea(0f, 59f, 21f, 59f),
                controls = listOf(r(18f, 12f, 52f, 99f), r(18f, 216f, 52f, 99f), r(22f, 318f, 44f, 44f), r(651f, 318f, 48f, 48f), r(709f, 307f, 70f, 70f)),
                grid = listOf(r(80f, 12f, 275.5f, 170f), r(365.5f, 12f, 275.5f, 170f), r(80f, 192f, 275.5f, 170f), r(365.5f, 192f, 275.5f, 170f)),
                stage = listOf(r(51f, 12f, 609.5555555555555f, 350f), r(670.5555555555555f, 12f, 108.44444444444444f, 61f), r(670.5555555555555f, 83f, 108.44444444444444f, 61f), r(670.5555555555555f, 154f, 108.44444444444444f, 61f)),
            ),
            Pinned(
                1024f, 1366f, MultiviewSafeArea(0f, 0f, 0f, 0f),
                controls = listOf(r(14f, 22f, 60f, 115f), r(18f, 1204f, 115f, 60f), r(77f, 1267f, 52f, 52f), r(859f, 1283.5f, 57f, 57f), r(926f, 1270f, 84f, 84f)),
                grid = listOf(r(14f, 147f, 493f, 518.5f), r(517f, 147f, 493f, 518.5f), r(14f, 675.5f, 493f, 518.5f), r(517f, 675.5f, 493f, 518.5f)),
                stage = listOf(r(0f, 12f, 1024f, 576f), r(341.9259259259259f, 598f, 340.14814814814815f, 191.33333333333334f), r(341.9259259259259f, 799.3333333333334f, 340.14814814814815f, 191.33333333333334f), r(341.9259259259259f, 1000.6666666666667f, 340.14814814814815f, 191.33333333333334f)),
            ),
            Pinned(
                1366f, 1024f, MultiviewSafeArea(0f, 0f, 0f, 0f),
                controls = listOf(r(14f, 37f, 115f, 60f), r(14f, 899f, 115f, 60f), r(73f, 962f, 52f, 52f), r(1234f, 935f, 44f, 44f), r(1288f, 925f, 64f, 64f)),
                grid = listOf(r(14f, 107f, 664f, 386f), r(688f, 107f, 664f, 386f), r(14f, 503f, 664f, 386f), r(688f, 503f, 664f, 386f)),
                stage = listOf(r(14f, 180.5f, 1178.6666666666667f, 663f), r(1202.6666666666667f, 180.5f, 149.33333333333334f, 84f), r(1202.6666666666667f, 274.5f, 149.33333333333334f, 84f), r(1202.6666666666667f, 368.5f, 149.33333333333334f, 84f)),
            ),
        )
        for (case in cases) {
            val grid = MultiviewPresentationLayout.compute(case.width, case.height, case.safe, GRID, 0)
            val gridSelected = MultiviewPresentationLayout.compute(case.width, case.height, case.safe, GRID, 2)
            val stage = MultiviewPresentationLayout.compute(case.width, case.height, case.safe, CENTER_STAGE, 0)
            val stageSelected = MultiviewPresentationLayout.compute(case.width, case.height, case.safe, CENTER_STAGE, 2)
            for (layout in listOf(grid, gridSelected, stage, stageSelected)) {
                val controls = listOf(
                    layout.sessionControls, layout.assists, layout.network, layout.display, layout.record,
                )
                assertRects(case.controls, controls, "${case.width}x${case.height} controls")
            }
            assertRects(case.grid, grid.tiles, "${case.width}x${case.height} grid 0")
            assertRects(case.grid, gridSelected.tiles, "${case.width}x${case.height} grid 2")
            assertRects(case.stage, stage.tiles, "${case.width}x${case.height} stage 0")
            // Selecting camera 2 swaps its tile with the main slot; thumbs keep camera order.
            val swapped = listOf(case.stage[1], case.stage[2], case.stage[0], case.stage[3])
            assertRects(swapped, stageSelected.tiles, "${case.width}x${case.height} stage 2")
        }
    }

    private class Pinned(
        val width: Float,
        val height: Float,
        val safe: MultiviewSafeArea,
        val controls: List<MonitorRect>,
        val grid: List<MonitorRect>,
        val stage: List<MonitorRect>,
    )

    private fun r(x: Float, y: Float, width: Float, height: Float) = MonitorRect(x, y, width, height)

    private fun assertRects(expected: List<MonitorRect>, actual: List<MonitorRect>, message: String) {
        assertEquals(expected.size, actual.size, message)
        for ((e, a) in expected.zip(actual)) {
            assertEquals(e.x, a.x, 0.01f, message)
            assertEquals(e.y, a.y, 0.01f, message)
            assertEquals(e.width, a.width, 0.01f, message)
            assertEquals(e.height, a.height, 0.01f, message)
        }
    }

    private fun overlaps(a: MonitorRect, b: MonitorRect) =
        a.x < b.maxX && a.maxX > b.x && a.y < b.maxY && a.maxY > b.y
}
