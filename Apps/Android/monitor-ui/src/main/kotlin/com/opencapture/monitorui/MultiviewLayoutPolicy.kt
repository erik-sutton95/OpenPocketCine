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
            val cell = if (tablet) 52.0 else 44.0
            val horizontal = false
            val toolbarWidth = cell + 8
            val toolbarHeight = cell * 4 + 17
            val live = MonitorLayoutPolicy.fieldMonitor(
                w.toFloat(), h.toFloat(), safeTop.toFloat(), safeLeading.toFloat(),
                safeBottom.toFloat(), safeTrailing.toFloat(), topControlInset = controlInset.toFloat(),
            )
            val headerTop = (if (portrait || banded) safeTop else 0.0) + 12 + controlInset
            val close = if (portrait) live.lock.copy(y = headerTop.toFloat()) else live.lock
            val network = if (portrait) live.settings.copy(
                x = (w - 14 - live.settings.width).toFloat(), y = headerTop.toFloat(),
            ) else live.settings
            val cutout = max(safeLeading, safeTrailing)
            val leftToolX = close.midX - toolbarWidth / 2
            val rightToolX = live.display.midX - toolbarWidth / 2
            val toolbarOnLeft = !portrait && safeTrailing > safeLeading
            val toolX = when {
                portrait -> network.midX - toolbarWidth / 2
                toolbarOnLeft -> leftToolX
                else -> rightToolX
            }
            val stageTop = when {
                portrait -> max(safeTop + 70 + controlInset, close.maxY + 4.0)
                else -> close.y.toDouble()
            }
            val preferredStageLeft = if (banded) 28.0 else max(cutout + 8, 18.0)
            val exitClearance = if (close.maxY > stageTop) close.maxX + 4.0 else preferredStageLeft
            // Keep feed rectangles fixed across cutout rotations; only the toolbar changes sides.
            val stageLeft = if (portrait) 15.0 else maxOf(
                preferredStageLeft, exitClearance,
                if (cutout > 0) leftToolX + toolbarWidth + 6 else preferredStageLeft,
            )
            val stageRight = when {
                portrait -> toolX - 6
                banded -> minOf(w - 28, rightToolX - 6, network.x - 6.0)
                else -> minOf(w - max(88.0, cutout + 12), rightToolX - 6, network.x - 6.0)
            }
            val readouts = when {
                portrait -> Rect(18.0, max(stageTop, live.record.y - 58.0), w - 36, 37.0)
                banded -> Rect(28.0, live.record.y + live.record.height / 2 - 18.5,
                    live.record.x - 52.0, 37.0)
                else -> Rect(stageLeft, h - safeBottom - 12 - 37, stageRight - stageLeft, 37.0)
            }
            val stageBottom = when {
                portrait -> readouts.y - 12
                banded -> min(h - 111, live.display.y - 12.0)
                else -> readouts.y - 12
            }
            val stageWidth = max(1.0, stageRight - stageLeft)
            val stageHeight = max(1.0, stageBottom - stageTop)
            val gap = if (portrait) 9.0 else if (tablet) 14.0 else 12.0
            val focused = selected.coerceIn(0, 3)
            val tiles = MutableList(4) { Rect(0.0, 0.0, 0.0, 0.0) }
            var toolbarTop = stageTop
            if (arrangement == MultiviewArrangement.GRID) {
                val columns = if (portrait) 1 else 2
                val rows = 4 / columns
                val tileWidth = max(1.0, (stageWidth - (columns - 1) * gap) / columns)
                val tileHeight = max(1.0, (stageHeight - (rows - 1) * gap) / rows)
                for (index in 0 until 4) {
                    tiles[index] = Rect(
                        stageLeft + (index % columns) * (tileWidth + gap),
                        stageTop + (index / columns) * (tileHeight + gap), tileWidth, tileHeight,
                    )
                }
            } else if (portrait) {
                val secondaryMinimum = max(toolbarHeight, 3 * 44.0 + 2 * gap)
                val mainHeight = min(max(1.0, w - 30) * 9 / 16, max(1.0, stageHeight - 15 - secondaryMinimum))
                val mainWidth = mainHeight * 16 / 9
                tiles[focused] = Rect((w - mainWidth) / 2, stageTop, mainWidth, mainHeight)
                toolbarTop = tiles[focused].maxY + 15
                val thumbHeight = max(1.0, (stageBottom - toolbarTop - 2 * gap) / 3)
                var row = 0
                for (index in 0 until 4) {
                    if (index == focused) continue
                    tiles[index] = Rect(stageLeft, toolbarTop + row * (thumbHeight + gap), stageWidth, thumbHeight)
                    row++
                }
            } else {
                val thumbGap = if (tablet) 14.0 else 9.0
                val columnGap = if (tablet) 18.0 else 12.0
                val thumbWidth = max(1.0, minOf(
                    if (tablet) 252.0 else 184.0,
                    (stageHeight - 2 * thumbGap) * 16 / 27,
                    (stageWidth - columnGap - 2 * thumbGap * 16 / 9) / 4,
                ))
                val thumbHeight = thumbWidth * 9 / 16
                val mainColumnWidth = max(1.0, stageWidth - thumbWidth - columnGap)
                val mainWidth = min(stageHeight * 16 / 9, mainColumnWidth)
                val mainHeight = mainWidth * 9 / 16
                tiles[focused] = Rect(
                    stageLeft + (mainColumnWidth - mainWidth) / 2,
                    stageTop, mainWidth, mainHeight,
                )
                val stripTop = stageTop
                var row = 0
                for (index in 0 until 4) {
                    if (index == focused) continue
                    tiles[index] = Rect(stageRight - thumbWidth, stripTop + row * (thumbHeight + thumbGap), thumbWidth, thumbHeight)
                    row++
                }
            }
            val toolTop = when {
                portrait -> max(toolbarTop, network.maxY + 8.0)
                toolbarOnLeft -> close.maxY + 8.0
                else -> network.maxY + 8.0
            }
            val toolBottom = if (portrait) stageBottom else live.display.y - 8.0
            // Short rails scroll their four full-size targets between the native system controls.
            val assists = Rect(toolX, toolTop, toolbarWidth, min(toolbarHeight, max(1.0, toolBottom - toolTop)))
            return MultiviewPresentationLayout(
                tiles = tiles.map { it.clamped(w, h) }, sessionControls = close,
                readouts = readouts.clamped(w, h),
                assists = assists.clamped(w, h), network = network,
                display = live.display, record = live.record, portrait = portrait, tablet = tablet,
                controlCellSize = cell.toFloat(), sessionControlsHorizontal = true, assistsHorizontal = horizontal,
            )
        }
    }
}

private fun Float.finiteNonnegative() = if (isFinite()) max(0.0, toDouble()) else 0.0

private class Rect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val maxX get() = x + width
    val maxY get() = y + height
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
