package com.opencapture.monitorui

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.withSign

// 1:1 port of Sources/MonitorPresentation/MultiviewPresentationLayout.swift.
// Math runs in Double like Swift and converts to Float MonitorRect at the end.

enum class MultiviewArrangement { GRID, CENTER_STAGE }

/** Window insets in dp, mirroring Swift `MonitorSafeArea`. */
data class MultiviewSafeArea(
    val top: Float = 0f,
    val leading: Float = 0f,
    val bottom: Float = 0f,
    val trailing: Float = 0f,
)

/**
 * One geometry policy for multi-camera stages. Every camera owns one persistent
 * tile; selecting a camera changes rectangles, never creates a fifth feed.
 */
data class MultiviewPresentationLayout(
    val tiles: List<MonitorRect>,
    val sessionControls: MonitorRect,
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
            val safeTop = safeArea.top.toDouble()
            val safeLeading = safeArea.leading.toDouble()
            val safeBottom = safeArea.bottom.toDouble()
            val safeTrailing = safeArea.trailing.toDouble()
            val w = max(1.0, if (width.isFinite()) width.toDouble() else 1.0)
            val h = max(1.0, if (height.isFinite()) height.toDouble() else 1.0)
            val portrait = h > w
            val tablet = min(w, h) >= 600
            val banded = tablet && !portrait
            val gap = 10.0
            val button = if (tablet) 52.0 else 44.0
            val assistsHorizontal = banded || portrait
            val nominalRecord = if (tablet) 84.0 else 70.0
            val recordSize = if (banded) 64.0 else nominalRecord
            val top = (if (portrait) max(2.0, safeTop) else 2.0) + 10
            val bottom = max(0.0, safeBottom) + 10
            val leading = 14 + (if (portrait) 0.0 else max(0.0, safeLeading))
            val trailing = 14 + (if (portrait) 0.0 else max(0.0, safeTrailing))
            val freeWidth = max(1.0, w - leading - trailing)
            val gridWidth = max(1.0, floor((freeWidth - gap) / 2))
            val fullGridHeight = swiftRound(gridWidth * 9 / 16) * 2 + gap
            val band = if (banded) max(recordSize + 24, swiftRound((h - fullGridHeight) / 2)) else 0.0
            val recordBottom = when {
                banded -> max(16.0, swiftRound((band - recordSize) / 2))
                safeBottom > 0 -> 16.0
                else -> 12.0
            }
            val record = Rect(
                max(0.0, w - trailing - recordSize), max(0.0, h - recordBottom - recordSize),
                recordSize, recordSize,
            )
            val displaySize = swiftRound(recordSize * 0.68)
            val display = Rect(
                max(0.0, record.x - gap - displaySize), record.midY - displaySize / 2,
                displaySize, displaySize,
            )
            val sessionX = if (banded || portrait) leading else 18.0
            val sessionY = when {
                banded -> max(8.0, swiftRound((band - button - 8) / 2))
                portrait -> top + 10
                else -> top
            }
            val controlInset = if (topControlInset.isFinite()) max(0.0, topControlInset.toDouble()) else 0.0
            val sessionControls = Rect(
                sessionX, sessionY + controlInset,
                if (banded) 2 * button + 11 else button + 8,
                if (banded) button + 8 else 2 * button + 11,
            )
            val assistsBottom = when {
                banded -> max(8.0, swiftRound((band - button - 8) / 2))
                portrait -> nominalRecord + safeBottom + 18
                else -> 14.0
            }
            val assistsHeight = if (assistsHorizontal) button + 8 else button * 2 + 11
            // Keep a separate network button directly below FIT, including when
            // LUT and FIT share a row. Reserve its full touch target above the edge.
            val assistsY = min(
                h - assistsBottom - assistsHeight,
                h - bottom - button - 3 - assistsHeight,
            )
            val assists = Rect(
                if (banded) leading else 18.0, max(0.0, assistsY),
                if (assistsHorizontal) button * 2 + 11 else button + 8, assistsHeight,
            )
            val network = Rect(
                assists.x + 4 + (if (assistsHorizontal) button + 3 else 0.0),
                assists.maxY + 3, button, button,
            )

            val tiles: List<Rect>
            if (arrangement == MultiviewArrangement.GRID) {
                // Grid cells use the available viewport, not a fixed picture aspect.
                // Fit/Fill controls the image inside each cell. Phone landscape uses
                // the space between the floating side controls; taller layouts use
                // the space between the top and bottom controls.
                val gridLeft: Double
                val gridRight: Double
                val gridTop: Double
                val gridBottom: Double
                if (!portrait && !tablet) {
                    gridLeft = maxOf(leading, sessionControls.maxX + gap, assists.maxX + gap)
                    gridRight = minOf(w - trailing, display.x - gap, record.x - gap)
                    gridTop = top
                    gridBottom = h - bottom
                } else {
                    gridLeft = leading
                    gridRight = w - trailing
                    gridTop = max(top, sessionControls.maxY + gap)
                    gridBottom = minOf(assists.y, network.y, display.y, record.y) - gap
                }
                val tileWidth = max(1.0, (gridRight - gridLeft - gap) / 2)
                val tileHeight = max(1.0, (gridBottom - gridTop - gap) / 2)
                tiles = (0 until 4).map { index ->
                    Rect(
                        gridLeft + (index % 2) * (tileWidth + gap),
                        gridTop + (index / 2) * (tileHeight + gap),
                        tileWidth, tileHeight,
                    )
                }
            } else {
                val selectedIndex = min(3, max(0, selected))
                val result = MutableList(4) { Rect(0.0, 0.0, 0.0, 0.0) }
                if (portrait) {
                    val mainWidth = w
                    val mainHeight = mainWidth * 9 / 16
                    result[selectedIndex] = Rect(0.0, top, mainWidth, mainHeight)
                    val stripTop = top + mainHeight + gap
                    val stripBottom = min(record.y - button - 26, assists.y - gap)
                    val available = max(3.0, stripBottom - stripTop - 2 * gap)
                    val thumbHeight = max(1.0, min(available / 3, freeWidth * 9 / 16))
                    val thumbWidth = thumbHeight * 16 / 9
                    var row = 0
                    for (index in 0 until 4) {
                        if (index == selectedIndex) continue
                        result[index] = Rect(
                            (w - thumbWidth) / 2, stripTop + row * (thumbHeight + gap),
                            thumbWidth, thumbHeight,
                        )
                        row += 1
                    }
                } else {
                    val cutout = max(safeLeading, safeTrailing)
                    val pictureLeading = if (cutout > 0) max(14.0, safeLeading - 8) else 14.0
                    val pictureFreeWidth = max(1.0, w - pictureLeading - trailing)
                    val availableHeight = max(1.0, h - top - bottom)
                    val mainHeight =
                        if (banded) min(availableHeight, swiftRound((pictureFreeWidth - gap - 150) * 9 / 16))
                        else availableHeight
                    val tentativeMain = min(pictureFreeWidth - gap - 108, swiftRound(mainHeight * 16 / 9))
                    val tentativeThumb = pictureFreeWidth - gap - tentativeMain
                    val stripHeight = max(3.0, availableHeight - nominalRecord - gap)
                    val thumbHeight = max(
                        1.0, min(floor((stripHeight - 2 * gap) / 3), swiftRound(tentativeThumb * 9 / 16)),
                    )
                    val thumbWidth = thumbHeight * 16 / 9
                    val mainWidth = max(1.0, pictureFreeWidth - gap - thumbWidth)
                    val mainY = if (banded) (h - mainHeight) / 2 else top
                    result[selectedIndex] = Rect(pictureLeading, mainY, mainWidth, mainHeight)
                    var row = 0
                    for (index in 0 until 4) {
                        if (index == selectedIndex) continue
                        result[index] = Rect(
                            pictureLeading + mainWidth + gap,
                            mainY + row * (thumbHeight + gap), thumbWidth, thumbHeight,
                        )
                        row += 1
                    }
                }
                tiles = result
            }
            return MultiviewPresentationLayout(
                tiles = tiles.map { it.toMonitorRect() },
                sessionControls = sessionControls.toMonitorRect(),
                assists = assists.toMonitorRect(),
                network = network.toMonitorRect(),
                display = display.toMonitorRect(),
                record = record.toMonitorRect(),
                portrait = portrait,
                tablet = tablet,
                controlCellSize = button.toFloat(),
                sessionControlsHorizontal = banded,
                assistsHorizontal = assistsHorizontal,
            )
        }
    }
}

/** Double working rect; clamps negative size to 0 like Swift `MonitorRect.init`. */
private class Rect(val x: Double, val y: Double, width: Double, height: Double) {
    val width = max(0.0, width)
    val height = max(0.0, height)
    val maxX get() = x + width
    val maxY get() = y + height
    val midY get() = y + height / 2
    fun toMonitorRect() = MonitorRect(x.toFloat(), y.toFloat(), width.toFloat(), height.toFloat())
}

// Swift `round` is half away from zero; Kotlin `round` is half to even.
private fun swiftRound(value: Double): Double {
    val magnitude = abs(value)
    val whole = floor(magnitude)
    return (if (magnitude - whole >= 0.5) whole + 1 else whole).withSign(value)
}
