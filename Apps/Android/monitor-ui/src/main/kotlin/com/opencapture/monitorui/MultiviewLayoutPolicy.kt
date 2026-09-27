package com.opencapture.monitorui

import kotlin.math.max
import kotlin.math.min

// Port of Sources/MonitorPresentation/MultiviewPresentationLayout.swift.
// Camera geometry is shared; DISP and Record reuse each platform's Live View slots.

enum class MultiviewArrangement { GRID, CENTER_STAGE }

/** Window insets in dp, mirroring Swift `MonitorSafeArea`. */
data class MultiviewSafeArea(
    val top: Float = 0f,
    val leading: Float = 0f,
    val bottom: Float = 0f,
    val trailing: Float = 0f,
)

/** Four persistent camera owners; selection changes rectangles, never feed ownership. */
data class MultiviewPresentationLayout(
    val tiles: List<MonitorRect>,
    val sessionControls: MonitorRect,
    val readouts: MonitorRect,
    val assists: MonitorRect,
    val network: MonitorRect,
    val display: MonitorRect,
    val record: MonitorRect,
    val portrait: Boolean,
    val tablet: Boolean,
    val controlCellSize: Float,
    val sessionControlsHorizontal: Boolean,
    val assistsHorizontal: Boolean,
    val secondaryViewport: MonitorRect? = null,
    val secondaryIndices: List<Int> = emptyList(),
    val readoutsOverlay: Boolean = false,
) {
    companion object {
        fun compute(
            width: Float,
            height: Float,
            safeArea: MultiviewSafeArea = MultiviewSafeArea(),
            arrangement: MultiviewArrangement,
            selected: Int,
            topControlInset: Float = 0f,
        ): MultiviewPresentationLayout {
            val w = max(1.0, width.finiteNonnegative())
            val h = max(1.0, height.finiteNonnegative())
            val safeTop = min(h, safeArea.top.finiteNonnegative())
            val safeLeading = min(w, safeArea.leading.finiteNonnegative())
            val safeBottom = min(h, safeArea.bottom.finiteNonnegative())
            val safeTrailing = min(w, safeArea.trailing.finiteNonnegative())
            val controlInset = min(h, topControlInset.finiteNonnegative())
            val portrait = h > w
            val tablet = min(w, h) >= 600
            val banded = tablet && !portrait
            val focusedLandscape = !portrait && arrangement == MultiviewArrangement.CENTER_STAGE
            val cell = MonitorLayoutPolicy.assistButtonSize(tablet).toDouble()
            // Landscape stages mount Live View's horizontal View Assist palette, Wi-Fi under
            // Exit and the selected camera's values inside its tile.
            val horizontal = !portrait
            val toolbarWidth = cell + 8
            val toolbarHeight = cell * 4 + 44
            val portraitSecondaryMinimum = (if (tablet) 52.0 else 44.0) * 4 + 17
            val live = MonitorLayoutPolicy.fieldMonitor(
                w.toFloat(), h.toFloat(), safeTop.toFloat(), safeLeading.toFloat(),
                safeBottom.toFloat(), safeTrailing.toFloat(), topControlInset = controlInset.toFloat(),
            )
            val headerTop = (if (portrait || banded) safeTop else 0.0) + 12 + controlInset
            // Portrait Exit then Wi-Fi, 8 dp apart, at Live View's portrait corner row.
            val portraitTop = min(live.gauges.y.toDouble(), headerTop).toFloat()
            val close = if (portrait) live.lock.copy(y = portraitTop) else live.lock
            val network = when {
                portrait -> live.settings.copy(x = close.maxX + 8, y = portraitTop)
                else -> live.settings.copy(x = close.midX - live.settings.width / 2, y = close.maxY + 8)
            }
            // Center stage reserves the far right for the strip: DISP sits left of Record.
            val display = if (focusedLandscape) MonitorRect(
                live.record.x - 8 - live.display.width, live.record.y + (live.record.height - live.display.width) / 2,
                live.display.width, live.display.width,
            ) else live.display
            val cutout = max(safeLeading, safeTrailing)
            val toolX = w - 14 - (live.settings.width + toolbarWidth) / 2
            // Portrait Grid: full-width feeds; the collapsible palette mirrors DISP across Record
            // (same gap, same row bottom) and grows upward over them.
            val portraitGrid = portrait && arrangement == MultiviewArrangement.GRID
            val cornerPaletteX = live.record.maxX + (live.record.x - live.display.maxX).toDouble()
            val stageTop = when {
                portrait -> close.maxY + 10.0
                else -> close.y.toDouble()
            }
            // Landscape grid: only DISP keeps Live View's slot above Record.
            val stageLeft = if (portrait) 15.0 else max(if (banded) 28.0 else cutout + 8, close.maxX + 8.0)
            val stageRight = when {
                portrait -> toolX - 6
                else -> min(w - (if (banded) 28.0 else max(18.0, cutout + 8)),
                    min(display.x, live.record.x) - 8.0)
            }
            var readouts = Rect(18.0, max(stageTop, live.record.y - 58.0), w - 36, 37.0)
            val stageBottom = when {
                // The feeds reach down to Record and the collapsed palette; the selected
                // camera's values sit inside its tile.
                portraitGrid -> max(stageTop + 1, min(live.record.y.toDouble(), live.display.maxY - (cell + 35)) - 12)
                portrait -> readouts.y - 12
                banded -> min(h - 111, live.display.y - 12.0)
                else -> h - safeBottom - 12
            }
            val stageWidth = max(1.0, stageRight - stageLeft)
            val stageHeight = max(1.0, stageBottom - stageTop)
            val gap = if (portrait) 9.0 else if (tablet) 14.0 else 12.0
            val focused = selected.coerceIn(0, 3)
            val tiles = MutableList(4) { Rect(0.0, 0.0, 0.0, 0.0) }
            var toolbarTop = stageTop
            var columnBottom: Double? = null
            var secondaryViewport: MonitorRect? = null
            val secondaryIndices = if (focusedLandscape) (0 until 4).filter { it != focused } else emptyList()
            if (arrangement == MultiviewArrangement.GRID) {
                val columns = if (portrait) 1 else 2
                val rows = 4 / columns
                val tileWidth = if (portrait) max(1.0, w - 30) else max(1.0, (stageWidth - (columns - 1) * gap) / columns)
                val tileHeight = max(1.0, (stageHeight - (rows - 1) * gap) / rows)
                for (index in 0 until 4) {
                    tiles[index] = Rect(
                        stageLeft + (index % columns) * (tileWidth + gap),
                        stageTop + (index / columns) * (tileHeight + gap), tileWidth, tileHeight,
                    )
                }
                if (portrait) {
                    val tile = tiles[focused]
                    readouts = Rect(tile.x, max(tile.y, tile.maxY - 8 - GRID_READOUT_HEIGHT), tile.width, GRID_READOUT_HEIGHT)
                } else {
                    val tile = tiles[focused]
                    val rowY = max(tile.y, tile.maxY - 8 - GRID_READOUT_HEIGHT)
                    val palette = live.assists
                    val underPalette = palette.maxX > tile.x && palette.y < rowY + GRID_READOUT_HEIGHT && palette.maxY > rowY
                    val readoutsLeft = if (underPalette) max(tile.x, palette.maxX + 6.0) else tile.x
                    readouts = Rect(readoutsLeft, rowY, max(0.0, tile.maxX - readoutsLeft), GRID_READOUT_HEIGHT)
                }
            } else if (portrait) {
                // Readouts sit directly under the main picture; the feeds and the fixed
                // tool column fill the rest down to the system row.
                val bottom = max(stageTop + 1, min(live.record.y, display.y) - 12.0)
                columnBottom = bottom
                val secondaryMinimum = max(portraitSecondaryMinimum, 3 * 44.0 + 2 * gap)
                val mainHeight = min(max(1.0, w - 30) * 9 / 16, max(1.0, bottom - stageTop - 57 - secondaryMinimum))
                val mainWidth = mainHeight * 16 / 9
                tiles[focused] = Rect((w - mainWidth) / 2, stageTop, mainWidth, mainHeight)
                readouts = Rect(18.0, tiles[focused].maxY + 8, w - 36, 37.0)
                toolbarTop = readouts.maxY + 12
                val thumbHeight = max(1.0, (bottom - toolbarTop - 2 * gap) / 3)
                var row = 0
                for (index in 0 until 4) {
                    if (index == focused) continue
                    tiles[index] = Rect(stageLeft, toolbarTop + row * (thumbHeight + gap), stageWidth, thumbHeight)
                    row++
                }
            } else {
                // Like Live View, the collapsed palette floats over the main picture.
                val mainLeft = maxOf(cutout + 8, close.maxX + 8.0)
                // The main picture keeps the cutout reserve on both edges so a half turn does not
                // move it; the strip takes the room to the trailing margin.
                val reservedRight = w - max(18.0, cutout + 8)
                val stripRight = w - max(18.0, safeTrailing + 8)
                val columnGap = if (tablet) 18.0 else 12.0
                val minimumThumb = max(1.0, min(if (tablet) 200.0 else 140.0, (reservedRight - mainLeft - columnGap) * .26))
                val mainWidth = max(1.0, min((h - safeBottom - 12 - stageTop) * 16 / 9,
                    reservedRight - minimumThumb - columnGap - mainLeft))
                val mainHeight = mainWidth * 9 / 16
                tiles[focused] = Rect(mainLeft, stageTop, mainWidth, mainHeight)
                val stripLeft = mainLeft + mainWidth + columnGap
                val thumbWidth = max(1.0, stripRight - stripLeft)
                val thumbHeight = thumbWidth * 9 / 16
                val stripBottom = max(stageTop + 44, min(display.y, live.record.y) - 8.0)
                secondaryViewport = Rect(stripLeft, stageTop, thumbWidth, stripBottom - stageTop).clamped(w, h)
                val thumbGap = if (tablet) 14.0 else 9.0
                secondaryIndices.forEachIndexed { row, index ->
                    tiles[index] = Rect(stripLeft, stageTop + row * (thumbHeight + thumbGap), thumbWidth, thumbHeight)
                }
                // Camera values start past the palette, as Live View's value row does.
                val readoutsLeft = maxOf(mainLeft, live.assists.maxX + 6.0)
                readouts = Rect(readoutsLeft, max(stageTop, stageTop + mainHeight - 45),
                    maxOf(0.0, mainLeft + mainWidth - readoutsLeft), 37.0)
            }
            val paletteHeight = max(1.0, min(toolbarHeight, live.display.maxY - stageTop))
            val assists = if (!portrait) live.assists.let {
                Rect(it.x.toDouble(), it.y.toDouble(), it.width.toDouble(), it.height.toDouble())
            } else if (columnBottom != null) {
                // Portrait Center stage: a plain column spanning the secondary feeds exactly.
                Rect(toolX, toolbarTop, toolbarWidth, max(1.0, columnBottom - toolbarTop))
            } else Rect(cornerPaletteX, live.display.maxY - paletteHeight, toolbarWidth, paletteHeight)
            return MultiviewPresentationLayout(
                tiles = tiles.mapIndexed { index, rect ->
                    if (index in secondaryIndices) rect.unclamped() else rect.clamped(w, h)
                }, sessionControls = close,
                readouts = readouts.clamped(w, h),
                assists = assists.clamped(w, h), network = network,
                display = display, record = live.record, portrait = portrait, tablet = tablet,
                controlCellSize = cell.toFloat(), sessionControlsHorizontal = true, assistsHorizontal = horizontal,
                secondaryViewport = secondaryViewport, secondaryIndices = secondaryIndices,
                readoutsOverlay = !portrait || portraitGrid,
            )
        }
    }
}

/** Grid tiles carry the selected camera's values as a small row above the footer. */
private const val GRID_READOUT_HEIGHT = 24.0

private fun Float.finiteNonnegative() = if (isFinite()) max(0.0, toDouble()) else 0.0

private class Rect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val maxX get() = x + width
    val maxY get() = y + height
    fun unclamped() = MonitorRect(x.toFloat(), y.toFloat(), width.toFloat(), height.toFloat())
    fun clamped(viewWidth: Double, viewHeight: Double): MonitorRect {
        val fittedWidth = width.coerceIn(1.0, viewWidth)
        val fittedHeight = height.coerceIn(1.0, viewHeight)
        return MonitorRect(
            x.coerceIn(0.0, viewWidth - fittedWidth).toFloat(),
            y.coerceIn(0.0, viewHeight - fittedHeight).toFloat(),
            fittedWidth.toFloat(), fittedHeight.toFloat(),
        )
    }
}
