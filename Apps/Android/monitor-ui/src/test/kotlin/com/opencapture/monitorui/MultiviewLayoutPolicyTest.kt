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
                if (!portrait && arrangement == CENTER_STAGE) {
                    // DISP sits left of Record on its row, at the shared size.
                    assertEquals(layout.record.x - 8, layout.display.maxX, case)
                    assertEquals(layout.record.y + layout.record.height / 2, layout.display.y + layout.display.height / 2, case)
                    assertEquals(live.display.width, layout.display.width, case)
                    assertEquals(live.display.width, layout.display.height, case)
                } else {
                    assertEquals(live.display, layout.display, case)
                }
                if (!portrait) {
                    // Both landscape arrangements mount Live View's horizontal palette.
                    assertEquals(live.assists, layout.assists, case)
                    assertTrue(layout.assistsHorizontal, case)
                    assertTrue(layout.readoutsOverlay, case)
                }
                val expectedNetwork = when {
                    // Close then Wi-Fi, 8 dp apart, at Live View's portrait corner row.
                    portrait -> live.settings.copy(x = live.lock.maxX + 8, y = minOf(live.gauges.y, safe.top + 12))
                    else -> live.settings.copy(x = live.lock.midX - live.settings.width / 2, y = live.lock.maxY + 8)
                }
                assertEquals(expectedNetwork, layout.network, case)
                assertEquals(if (portrait) live.lock.copy(y = minOf(live.gauges.y, safe.top + 12)) else live.lock,
                    layout.sessionControls, case)
                val controls = listOf(layout.sessionControls, layout.readouts, layout.assists,
                    layout.network, layout.display, layout.record)
                val visibleTiles = layout.tiles.mapIndexedNotNull { index, tile ->
                    if (index in layout.secondaryIndices) intersection(tile, checkNotNull(layout.secondaryViewport)) else tile
                }
                for (frame in visibleTiles + controls) {
                    assertTrue(frame.x >= 0 && frame.y >= 0, "$case: $frame")
                    assertTrue(frame.width > 0 && frame.height > 0, "$case: $frame")
                    assertTrue(frame.maxX <= w + 0.1f && frame.maxY <= h + 0.1f, "$case: $frame")
                }
                layout.tiles.forEachIndexed { index, tile ->
                    for (other in layout.tiles.drop(index + 1)) assertFalse(overlaps(tile, other), "$case: $tile / $other")
                    val visible = if (index in layout.secondaryIndices) intersection(tile, checkNotNull(layout.secondaryViewport)) else tile
                    // Landscape overlays the values row and the palette on the main (Grid: lower-left) picture.
                    val paletteHost = if (arrangement == GRID) 2 else selected
                    if (visible != null) for (control in controls) {
                        // Portrait Grid's palette grows up over the feeds.
                        if (!(layout.readoutsOverlay && (control == layout.readouts ||
                                (control == layout.assists && index == paletteHost))) &&
                            !(portrait && arrangement == GRID && control == layout.assists))
                            assertFalse(overlaps(visible, control), "$case: $visible / $control")
                    }
                    if (arrangement == CENTER_STAGE && index == selected) {
                        assertEquals(16f / 9f, tile.width / tile.height, 0.001f, case)
                    }
                }
                controls.forEachIndexed { index, control ->
                    // Portrait Grid's palette expands over the in-tile values.
                    for (other in controls.drop(index + 1)) if (!(portrait && arrangement == GRID &&
                            control == layout.readouts && other == layout.assists))
                        assertFalse(overlaps(control, other), "$case: $control / $other")
                }
            }
        }
    }

    @Test
    fun portraitGridFillsFullWidthRowsWithABottomRightPalette() {
        val safe = MultiviewSafeArea(top = 59f, bottom = 34f)
        val grid = MultiviewPresentationLayout.compute(393f, 852f, safe, GRID, 0)
        val live = MonitorLayoutPolicy.fieldMonitor(393f, 852f, safe.top, safe.leading, safe.bottom, safe.trailing)
        assertTrue(grid.tiles.all { it.x == 15f && it.maxX == 393f - 15f })
        // DISP mirrored across Record, anchored at the bottom row.
        assertEquals(grid.record.x - grid.display.maxX, grid.assists.x - grid.record.maxX, 0.01f)
        assertEquals(live.display.maxY, grid.assists.maxY, 0.01f)
        // The selected camera's values sit inside its tile, as in landscape.
        assertTrue(grid.readoutsOverlay)
        assertEquals(grid.tiles[0].maxY - 8f, grid.readouts.maxY, 0.01f)
        assertEquals(grid.tiles[0].width, grid.readouts.width, 0.01f)
        assertEquals(grid.sessionControls.maxY + 10f, grid.tiles[0].y)
        // Feeds reach down to Record and the collapsed palette's top.
        val collapsedTop = grid.assists.maxY - (grid.controlCellSize + 35f)
        assertEquals(minOf(grid.record.y, collapsedTop) - 12f, grid.tiles[3].maxY, 0.01f)
        assertEquals(grid.tiles[0].height, grid.tiles[3].height)
        assertFalse(grid.assistsHorizontal)
        assertTrue(abs(grid.tiles[0].width / grid.tiles[0].height - 16f / 9f) > 0.1f)
    }

    @Test
    fun portraitFocusKeepsMainPictureAndStartsToolbarBelowIt() {
        val layout = MultiviewPresentationLayout.compute(393f, 852f,
            MultiviewSafeArea(top = 59f, bottom = 34f), CENTER_STAGE, 2)
        val main = layout.tiles[2]
        val thumbs = layout.tiles.filterIndexed { index, _ -> index != 2 }
        assertEquals(layout.sessionControls.maxX + 8f, layout.network.x)
        assertEquals(layout.sessionControls.y, layout.network.y)
        assertEquals(MonitorRect(15f, layout.sessionControls.maxY + 10f, 363f, 204.1875f), main)
        // Readouts sit directly under the main picture, the feeds below them.
        assertEquals(main.maxY + 8f, layout.readouts.y)
        assertEquals(layout.readouts.maxY + 12f, thumbs[0].y)
        assertTrue(thumbs.all { it.x == 15f && it.maxX == layout.assists.x - 6f })
        // The fixed tool column spans the secondary feeds exactly.
        assertEquals(thumbs[0].y, layout.assists.y)
        assertEquals(thumbs[2].maxY, layout.assists.maxY, 0.001f)
        assertEquals(layout.record.y - 12f, thumbs[2].maxY, 0.001f)
        assertTrue(layout.assists.height >= 4 * 44f + 8f)
        assertEquals(thumbs[0].height, thumbs[1].height)
    }

    @Test
    fun landscapeGridMountsCenterStageChromeWithValuesInTheSelectedTile() {
        for (safe in listOf(MultiviewSafeArea(leading = 59f, bottom = 21f),
            MultiviewSafeArea(trailing = 59f, bottom = 21f), MultiviewSafeArea())) {
            val live = MonitorLayoutPolicy.fieldMonitor(852f, 393f, safe.top, safe.leading, safe.bottom, safe.trailing)
            for (selected in 0 until 4) {
                val grid = MultiviewPresentationLayout.compute(852f, 393f, safe, GRID, selected)
                val stage = MultiviewPresentationLayout.compute(852f, 393f, safe, CENTER_STAGE, selected)
                assertEquals(stage.sessionControls, grid.sessionControls)
                assertEquals(stage.network, grid.network)
                assertEquals(stage.assists, grid.assists)
                // Only DISP keeps Live View's slot above Record.
                assertEquals(live.display, grid.display)
                val tile = grid.tiles[selected]
                assertEquals(tile.maxX, grid.readouts.maxX, 0.01f)
                assertEquals(tile.maxY - 8f, grid.readouts.maxY, 0.01f)
                assertTrue(grid.readouts.x >= tile.x)
                assertFalse(overlaps(grid.readouts, grid.assists))
                assertEquals(tile.x == grid.tiles[0].x && tile.y > grid.tiles[0].y,
                    grid.readouts.x > tile.x)
            }
        }
        val left = MultiviewPresentationLayout.compute(852f, 393f, MultiviewSafeArea(leading = 59f, bottom = 21f), GRID, 1)
        val right = MultiviewPresentationLayout.compute(852f, 393f, MultiviewSafeArea(trailing = 59f, bottom = 21f), GRID, 1)
        assertEquals(left.tiles, right.tiles)
        assertEquals(left.sessionControls.maxX + 8f, left.tiles[0].x)
        assertEquals(left.sessionControls.y, left.tiles[1].y)
        assertEquals(393f - 21f - 12f, left.tiles[3].maxY, 0.01f)
    }

    @Test
    fun landscapeHalfTurnKeepsPicturesAndPaletteSlot() {
        for ((w, h, cutout) in listOf(Triple(844f, 390f, 44f), Triple(852f, 393f, 59f),
            Triple(956f, 440f, 62f), Triple(976f, 448f, 62f), Triple(800f, 480f, 40f))) {
            for (arrangement in listOf(GRID, CENTER_STAGE)) {
                val left = MultiviewPresentationLayout.compute(w, h,
                    MultiviewSafeArea(leading = cutout, bottom = 21f), arrangement, 0)
                val right = MultiviewPresentationLayout.compute(w, h,
                    MultiviewSafeArea(trailing = cutout, bottom = 21f), arrangement, 0)
                if (arrangement == GRID) assertEquals(left.tiles, right.tiles)
                else assertEquals(left.tiles[0], right.tiles[0])
                assertEquals(left.assists, right.assists)
                for (layout in listOf(left, right)) {
                    assertTrue(layout.assists.maxX < w / 2)
                    // Center stage: the palette floats over the main picture; values clear it.
                    if (arrangement == CENTER_STAGE) assertTrue(layout.readouts.x >= layout.assists.maxX + 6f - 0.01f)
                }
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
                assertEquals(grid.sessionControls, stage.sessionControls)
                if (h > w) {
                    assertEquals(grid.display, stage.display)
                    assertEquals(grid.network, stage.network)
                    assertEquals(stage.tiles[selected].maxY + 8f, stage.readouts.y)
                } else {
                    assertEquals(stage.sessionControls.midX, stage.network.midX)
                    assertTrue(stage.assistsHorizontal)
                }
                assertTrue(stage.tiles[selected].width > stage.tiles[(selected + 1) % 4].width)
            }
        }
    }

    @Test
    fun toolbarContainsFourFullTouchTargets() {
        for ((w, h) in listOf(393f to 852f, 744f to 1133f)) {
            val layout = MultiviewPresentationLayout.compute(w, h, arrangement = GRID, selected = 0)
            val cell = MonitorLayoutPolicy.assistButtonSize(layout.tablet)
            val case = "$w x $h"
            assertEquals(cell, layout.controlCellSize, case)
            assertEquals(MonitorLayoutPolicy.systemButtonSize(layout.tablet), layout.controlCellSize, case)
            assertFalse(layout.assistsHorizontal, case)
            assertEquals(cell + 8, layout.assists.width, case)
            assertTrue(layout.assists.height <= cell * 4 + 44, case)
            assertTrue(layout.assists.height >= cell + 8, case)
            assertTrue(layout.assists.x > w / 2, case)
            assertEquals(MonitorLayoutPolicy.systemButtonSize(layout.tablet), layout.sessionControls.width, case)
        }
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
                    // Portrait Grid's palette grows up over the feeds; values sit in a tile.
                    if (arrangement == CENTER_STAGE) {
                        assertFalse(overlaps(tile, layout.assists), case)
                        assertFalse(overlaps(tile, layout.readouts), case)
                    }
                    assertFalse(overlaps(tile, layout.record), case)
                    assertFalse(overlaps(tile, layout.display), case)
                }
                if (arrangement == CENTER_STAGE) assertFalse(overlaps(layout.assists, layout.readouts), case)
                assertFalse(overlaps(layout.assists, layout.display), case)
                if (arrangement == CENTER_STAGE) {
                    assertEquals(16f / 9f, layout.tiles[0].width / layout.tiles[0].height, 0.001f)
                    assertEquals(layout.tiles[0].maxY + 8, layout.readouts.y, 0.001f)
                    assertEquals(layout.readouts.maxY + 12, layout.assists.y, 0.001f)
                    assertEquals(layout.tiles.drop(1).maxOf { it.maxY }, layout.assists.maxY, 0.001f)
                }
            }
        }
    }

    @Test
    fun focusedLandscapeUsesLargerMainAndIndependentOverflowStrip() {
        val left = MultiviewPresentationLayout.compute(852f, 393f,
            MultiviewSafeArea(leading = 59f, bottom = 21f), CENTER_STAGE, 2)
        val right = MultiviewPresentationLayout.compute(852f, 393f,
            MultiviewSafeArea(trailing = 59f, bottom = 21f), CENTER_STAGE, 2)
        val main = left.tiles[2]
        val strip = checkNotNull(left.secondaryViewport)
        assertEquals(main, right.tiles[2])
        assertEquals(listOf(0, 1, 3), left.secondaryIndices)
        assertTrue(left.readoutsOverlay)
        // The palette floats over the main picture; the values row clears it.
        assertTrue(left.readouts.x >= left.assists.maxX + 6 - 0.01f)
        assertEquals(565f, main.width)
        assertEquals(16f / 9f, main.width / main.height, .001f)
        assertEquals(left.sessionControls.y, main.y)
        assertEquals(main.maxY - 45, left.readouts.y)
        assertEquals(main.maxX, left.readouts.maxX, .01f)
        // The strip reaches the trailing margin: 18 on the plain edge, the cutout reserve opposite.
        assertEquals(834f, strip.maxX)
        assertEquals(785f, checkNotNull(right.secondaryViewport).maxX)
        assertEquals(main.maxX + 12, strip.x)
        assertEquals(strip.width, left.tiles[0].width)
        assertEquals(16f / 9f, left.tiles[0].width / left.tiles[0].height, .001f)
        assertEquals(140f, right.tiles[0].width)
        assertEquals(left.record.y - 8, strip.maxY)
        assertEquals(left.record.x - 8, left.display.maxX)
        assertTrue(left.tiles[3].maxY > strip.maxY)
        assertEquals(left.sessionControls.maxY + 8, left.network.y)
        assertTrue(left.assists.y >= (393f + 112f) / 2)
        assertEquals(MonitorLayoutPolicy.fieldMonitor(852f, 393f, 0f, 59f, 21f, 0f).assists, left.assists)
    }

    private fun intersection(a: MonitorRect, b: MonitorRect): MonitorRect? {
        val left = maxOf(a.x, b.x)
        val top = maxOf(a.y, b.y)
        val width = minOf(a.maxX, b.maxX) - left
        val height = minOf(a.maxY, b.maxY) - top
        return if (width > 0 && height > 0) MonitorRect(left, top, width, height) else null
    }

    private fun overlaps(a: MonitorRect, b: MonitorRect) =
        a.x < b.maxX - 0.01f && a.maxX > b.x + 0.01f && a.y < b.maxY - 0.01f && a.maxY > b.y + 0.01f
}
