package com.opencapture.monitorui

import com.opencapture.monitorui.MultiviewArrangement.CENTER_STAGE
import com.opencapture.monitorui.MultiviewArrangement.GRID
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MultiviewLayoutPolicyTest {
    @Test
    fun deviceMatrixKeepsSeparatePicturesAndNormalLiveViewControls() {
        val sizes = listOf(
            667f to 375f, 844f to 390f, 852f to 393f, 956f to 440f, 976f to 448f,
            1133f to 744f, 1194f to 834f, 1366f to 1024f, 800f to 480f,
        )
        for ((width, height) in sizes) for (portrait in listOf(false, true)) for (right in listOf(false, true)) {
            val w = if (portrait) height else width
            val h = if (portrait) width else height
            val cutout = minOf(w, h) < 600 && width != 667f
            val safe = MultiviewSafeArea(
                top = if (portrait && cutout) 59f else 0f,
                leading = if (!portrait && cutout && !right) 59f else 0f,
                bottom = if (width == 667f) 0f else if (portrait) 34f else 21f,
                trailing = if (!portrait && cutout && right) 59f else 0f,
            )
            val live = MonitorLayoutPolicy.fieldMonitor(w, h, safe.top, safe.leading, safe.bottom, safe.trailing)
            for (arrangement in MultiviewArrangement.entries) for (selected in 0 until 4) {
                val layout = MultiviewPresentationLayout.compute(w, h, safe, arrangement, selected)
                val case = "$w x $h $safe $arrangement $selected"
                assertEquals(4, layout.tiles.size)
                // Android's native offsets intentionally differ slightly from the iOS shell.
                assertEquals(live.record, layout.record, case)
                assertEquals(live.display, layout.display, case)
                assertEquals(if (portrait) live.settings.copy(x = w - 14 - live.settings.width, y = safe.top + 12) else live.settings, layout.network, case)
                assertEquals(if (portrait) live.lock.copy(y = safe.top + 12) else live.lock, layout.sessionControls, case)
                val controls = listOf(layout.sessionControls, layout.readouts, layout.assists,
                    layout.network, layout.display, layout.record)
                for (frame in layout.tiles + controls) {
                    assertTrue(frame.x >= 0 && frame.y >= 0, "$case: $frame")
                    assertTrue(frame.width > 0 && frame.height > 0, "$case: $frame")
                    assertTrue(frame.maxX <= w + 0.1f && frame.maxY <= h + 0.1f, "$case: $frame")
                }
                layout.tiles.forEachIndexed { index, tile ->
                    for (other in layout.tiles.drop(index + 1)) assertFalse(overlaps(tile, other), "$case: $tile / $other")
                    for (control in controls) assertFalse(overlaps(tile, control), "$case: $tile / $control")
                    if (arrangement == CENTER_STAGE && (!portrait || index == selected)) {
                        assertEquals(16f / 9f, tile.width / tile.height, 0.001f, case)
                    }
                }
                controls.forEachIndexed { index, control ->
                    for (other in controls.drop(index + 1)) assertFalse(overlaps(control, other), "$case: $control / $other")
                }
            }
        }
    }

    @Test
    fun portraitGridFillsFourRowsBesideTheToolbar() {
        val grid = MultiviewPresentationLayout.compute(393f, 852f, MultiviewSafeArea(top = 59f, bottom = 34f), GRID, 0)
        assertTrue(grid.tiles.all { it.x == 15f && it.maxX == grid.assists.x - 6f })
        assertEquals(129f, grid.tiles[0].y)
        assertEquals(grid.readouts.y - 12f, grid.tiles[3].maxY, 0.001f)
        assertEquals(grid.tiles[0].height, grid.tiles[3].height)
        assertFalse(grid.assistsHorizontal)
        assertEquals(grid.network.maxY + 8, grid.assists.y)
        assertTrue(abs(grid.tiles[0].width / grid.tiles[0].height - 16f / 9f) > 0.1f)
    }

    @Test
    fun portraitFocusKeepsMainPictureAndStartsToolbarBelowIt() {
        val layout = MultiviewPresentationLayout.compute(393f, 852f,
            MultiviewSafeArea(top = 59f, bottom = 34f), CENTER_STAGE, 2)
        val main = layout.tiles[2]
        val thumbs = layout.tiles.filterIndexed { index, _ -> index != 2 }
        assertEquals(MonitorRect(15f, 129f, 363f, 204.1875f), main)
        assertEquals(main.maxY + 15f, layout.assists.y)
        assertTrue(thumbs.all { it.x == 15f && it.maxX == layout.assists.x - 6f })
        assertEquals(layout.assists.y, thumbs[0].y)
        assertEquals(layout.readouts.y - 12f, thumbs[2].maxY, 0.001f)
        assertEquals(thumbs[0].height, thumbs[1].height)
    }

    @Test
    fun landscapeRotationMovesOnlyToolbarToTheColumnOppositeTheCutout() {
        for (arrangement in MultiviewArrangement.entries) {
            val left = MultiviewPresentationLayout.compute(852f, 393f,
                MultiviewSafeArea(leading = 59f, bottom = 21f), arrangement, 1)
            val right = MultiviewPresentationLayout.compute(852f, 393f,
                MultiviewSafeArea(trailing = 59f, bottom = 21f), arrangement, 1)
            assertEquals(left.tiles, right.tiles)
            assertEquals(left.record, right.record)
            assertEquals(left.display.x, right.display.x)
            assertEquals(left.sessionControls, right.sessionControls)
            assertEquals(left.network, right.network)
            assertEquals(left.display.midX, left.assists.midX)
            assertEquals(left.network.midX, left.assists.midX)
            assertEquals(right.sessionControls.midX, right.assists.midX)
            assertEquals(left.network.maxY + 8f, left.assists.y)
            assertEquals(right.sessionControls.maxY + 8f, right.assists.y)
            assertTrue(left.assists.x > left.tiles.maxOf { it.maxX })
            assertTrue(right.assists.maxX < right.tiles.minOf { it.x })
            for (layout in listOf(left, right)) {
                assertFalse(layout.assistsHorizontal)
                assertTrue(layout.assists.maxY <= layout.display.y - 8f)
            }
            assertEquals(left.record.y - 8f, left.display.maxY)
            assertEquals(right.record.y - 8f, right.display.maxY)
        }
    }

    @Test
    fun landscapeRailClearsNotchAndIslandBandsWithStableFramesAcrossRotation() {
        for ((w, h, cutout) in listOf(Triple(844f, 390f, 44f), Triple(852f, 393f, 59f),
            Triple(956f, 440f, 62f), Triple(976f, 448f, 62f), Triple(800f, 480f, 40f))) {
            for (arrangement in MultiviewArrangement.entries) {
                val left = MultiviewPresentationLayout.compute(w, h,
                    MultiviewSafeArea(leading = cutout, bottom = 21f), arrangement, 0)
                val right = MultiviewPresentationLayout.compute(w, h,
                    MultiviewSafeArea(trailing = cutout, bottom = 21f), arrangement, 0)
                assertEquals(left.tiles, right.tiles)
                assertEquals(left.display.midX, left.assists.midX)
                assertEquals(right.sessionControls.midX, right.assists.midX)
                for ((layout, trailing) in listOf(left to false, right to true)) {
                    val height = if (cutout >= 55f) 112f else 124f
                    val band = MonitorRect(if (trailing) w - cutout else 0f, (h - height) / 2, cutout, height)
                    assertFalse(overlaps(layout.assists, band), "$w x $h / $band / ${layout.assists}")
                    if (trailing) {
                        assertTrue(layout.assists.maxX < w / 2)
                        assertTrue(layout.tiles.all { it.x >= layout.assists.maxX + 6f })
                    } else {
                        assertTrue(layout.assists.x > w / 2)
                        assertTrue(layout.tiles.all { it.maxX <= layout.assists.x - 6f })
                    }
                }
            }
        }
    }

    @Test
    fun landscapeGridFillsStageWithoutAspectConstraint() {
        val grid = MultiviewPresentationLayout.compute(852f, 393f,
            MultiviewSafeArea(leading = 59f, bottom = 21f), GRID, 0)
        assertEquals(MonitorRect(71f, 11.825f, 340.5f, 143.5875f), grid.tiles[0])
        assertEquals(764f, grid.tiles[3].maxX)
        assertEquals(311f, grid.tiles[3].maxY)
        assertTrue(grid.tiles.all { it.width == 340.5f && it.height == 143.5875f })
    }

    @Test
    fun landscapeTopAlignedFeedsLeaveReadoutsBelowForEverySelection() {
        for ((w, h) in listOf(667f to 375f, 852f to 393f, 1194f to 834f)) {
            for (arrangement in MultiviewArrangement.entries) for (selected in 0 until 4) {
                val layout = MultiviewPresentationLayout.compute(w, h,
                    MultiviewSafeArea(bottom = 21f), arrangement, selected)
                val main = layout.tiles[if (arrangement == CENTER_STAGE) selected else 0]
                val firstSecondary = layout.tiles.first { it !== main }
                assertEquals(layout.sessionControls.y, main.y)
                assertEquals(layout.network.y, main.y)
                assertEquals(main.y, firstSecondary.y)
                assertTrue(layout.tiles.all { it.maxX <= layout.network.x - 6f })
                assertTrue(layout.tiles.all { it.maxY <= layout.readouts.y - 12f })
                assertEquals(37f, layout.readouts.height)
                if (!layout.tablet) assertEquals(h - 21f - 12f, layout.readouts.maxY)
            }
        }
    }

    @Test
    fun selectionAndLayoutPreserveSystemControlsAndFourOwners() {
        for ((w, h) in listOf(852f to 393f, 393f to 852f, 1194f to 834f)) {
            val grid = MultiviewPresentationLayout.compute(w, h, arrangement = GRID, selected = 0)
            for (selected in 0 until 4) {
                val otherGrid = MultiviewPresentationLayout.compute(w, h, arrangement = GRID, selected = selected)
                val stage = MultiviewPresentationLayout.compute(w, h, arrangement = CENTER_STAGE, selected = selected)
                assertEquals(grid.tiles, otherGrid.tiles)
                assertEquals(grid.record, stage.record)
                assertEquals(grid.display, stage.display)
                assertEquals(grid.sessionControls, stage.sessionControls)
                assertEquals(grid.network, stage.network)
                assertEquals(grid.readouts, stage.readouts)
                if (h < w) assertEquals(grid.assists, stage.assists)
                assertTrue(stage.tiles[selected].width > stage.tiles[(selected + 1) % 4].width)
            }
        }
    }

    @Test
    fun toolbarContainsFourFullTouchTargets() {
        for ((w, h) in listOf(393f to 852f, 852f to 393f, 744f to 1133f, 1133f to 744f)) {
            val layout = MultiviewPresentationLayout.compute(w, h, arrangement = GRID, selected = 0)
            val cell = if (layout.tablet) 52f else 44f
            assertEquals(cell, layout.controlCellSize)
            assertFalse(layout.assistsHorizontal)
            assertEquals(cell + 8, layout.assists.width)
            assertTrue(layout.assists.height <= cell * 4 + 17)
            assertTrue(layout.assists.height >= cell + 8)
            assertTrue(layout.assists.x > w / 2)
            assertEquals(MonitorLayoutPolicy.systemButtonSize(layout.tablet), layout.sessionControls.width)
        }
    }

    @Test
    fun smallLandscapeRailUsesTheAvailableHeightWithoutShrinkingTouchTargets() {
        val layout = MultiviewPresentationLayout.compute(667f, 375f, arrangement = GRID, selected = 0)
        assertEquals(44f, layout.controlCellSize)
        assertEquals(52f, layout.assists.width)
        assertEquals(layout.display.midX, layout.assists.midX)
        assertEquals(layout.network.maxY + 8f, layout.assists.y)
        assertEquals(layout.display.y - 8f, layout.assists.maxY)
        assertTrue(layout.assists.height < 4 * layout.controlCellSize + 17)
        assertFalse(layout.assistsHorizontal)
    }

    @Test
    fun topWindowControlsMoveHeaderAndStageWithoutMovingRecord() {
        for ((w, h) in listOf(744f to 1133f, 1133f to 744f)) {
            val plain = MultiviewPresentationLayout.compute(w, h, arrangement = GRID, selected = 0)
            val inset = MultiviewPresentationLayout.compute(w, h, arrangement = GRID, selected = 0, topControlInset = 28f)
            assertEquals(plain.sessionControls.y + 28f, inset.sessionControls.y)
            assertEquals(plain.tiles[0].y + 28f, inset.tiles[0].y)
            assertEquals(plain.record, inset.record)
            assertEquals(plain.display, inset.display)
        }
    }

    @Test
    fun constrainedPortraitWindowsReserveToolbarAndUsableSecondaryRows() {
        for ((w, h) in listOf(500f to 650f, 600f to 650f, 650f to 700f)) {
            for (arrangement in MultiviewArrangement.entries) {
                val layout = MultiviewPresentationLayout.compute(w, h,
                    MultiviewSafeArea(top = 24f, bottom = 20f), arrangement, 0, topControlInset = 28f)
                val case = "$w x $h $arrangement"
                for (tile in layout.tiles) {
                    assertTrue(tile.height >= 44f || tile == layout.tiles[0] && arrangement == CENTER_STAGE, case)
                    assertFalse(overlaps(tile, layout.assists), case)
                    assertFalse(overlaps(tile, layout.readouts), case)
                    assertFalse(overlaps(tile, layout.record), case)
                    assertFalse(overlaps(tile, layout.display), case)
                }
                assertFalse(overlaps(layout.assists, layout.readouts), case)
                assertFalse(overlaps(layout.assists, layout.display), case)
                if (arrangement == CENTER_STAGE) {
                    assertEquals(16f / 9f, layout.tiles[0].width / layout.tiles[0].height, 0.001f)
                    assertEquals(layout.tiles[0].maxY + 15, layout.assists.y, 0.001f)
                }
            }
        }
    }

    private fun overlaps(a: MonitorRect, b: MonitorRect) =
        a.x < b.maxX - 0.01f && a.maxX > b.x + 0.01f && a.y < b.maxY - 0.01f && a.maxY > b.y + 0.01f
}
