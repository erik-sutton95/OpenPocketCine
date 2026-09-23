package com.opencapture.monitorui

import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Interactive View Assist plate: tap the arrow, or press and drag it. */
object MonitorAssistPaletteReveal {
    const val SNAP = 0.5f
    const val SLOP = 8f
    const val FLICK = 280f
    const val COAST = 0.22f

    /** Reserve the full plate before its first reveal frame and through the collapse spring. */
    fun reservationSize(expanded: Boolean, dragging: Boolean, animating: Boolean, progress: Float,
        compact: IntSize, full: IntSize): IntSize =
        if (expanded || dragging || animating || progress > 0.001f) full else compact

    /** The same bottom-leading window placement drives rendering and obstruction bounds. */
    fun popupBounds(slot: IntRect, windowWidth: Int, size: IntSize): IntRect {
        val left = slot.left.coerceIn(0, maxOf(0, windowWidth - size.width))
        val top = (slot.bottom - size.height).coerceAtLeast(0)
        return IntRect(left, top, left + size.width, top + size.height)
    }

    fun lerp(a: Float, b: Float, t: Float): Float {
        val clamped = min(1f, max(0f, t))
        return a + (b - a) * clamped
    }

    fun translationAlongExpand(dx: Float, dy: Float, portrait: Boolean): Float =
        if (portrait) -dy else dx

    fun progress(visible: Float, compact: Float, full: Float): Float {
        val span = full - compact
        if (span <= 1f) return if (full >= compact) 1f else 0f
        return min(1f, max(0f, (visible - compact) / span))
    }

    fun progress(translationAlongExpand: Float, span: Float, fromExpanded: Boolean): Float {
        if (span <= 1f) return if (fromExpanded) 1f else 0f
        val origin = if (fromExpanded) span else 0f
        return min(1f, max(0f, (origin + translationAlongExpand) / span))
    }

    fun visibleEdge(finger: Float, grabOffset: Float, compact: Float, full: Float): Float =
        min(full, max(compact, finger + grabOffset))

    fun portraitGrabOffset(fingerY: Float, visibleHeight: Float, fullHeight: Float): Float =
        fingerY - (fullHeight - visibleHeight)

    fun portraitVisibleHeight(fingerY: Float, grabOffset: Float, compact: Float, full: Float): Float =
        min(full, max(compact, full - (fingerY - grabOffset)))

    /** Top-origin Y in the full plate, matching iOS `assistPalette` space. */
    fun paletteFingerY(fingerScreenY: Float, plateBottomScreenY: Float, fullHeight: Float): Float =
        fingerScreenY - (plateBottomScreenY - fullHeight)

    fun projectedProgress(progress: Float, velocityAlongExpand: Float, span: Float): Float {
        if (span <= 1f) return progress
        return min(1f, max(0f, progress + velocityAlongExpand * COAST / span))
    }

    fun shouldOpen(progress: Float, velocityAlongExpand: Float, projectedProgress: Float = progress): Boolean {
        if (abs(velocityAlongExpand) >= FLICK) return velocityAlongExpand > 0f
        return projectedProgress >= SNAP
    }

    fun extraToolOpacity(progress: Float): Float = min(1f, max(0f, (progress - 0.08f) / 0.42f))

    fun landscapeCellIndex(column: Int, row: Int): Int = column * 2 + row

    fun compactToolCount(portrait: Boolean): Int = if (portrait) 1 else 2

    /** Keep the open plate still. Ranking updates apply only after collapse. */
    fun pinnedOrder(ranked: List<String>, pinned: List<String>, frozen: Boolean): List<String> {
        if (!frozen || pinned.isEmpty()) return ranked
        val seen = linkedSetOf<String>()
        val kept = pinned.filter { it in ranked && seen.add(it) }
        val extras = ranked.filter { seen.add(it) }
        return kept + extras
    }
}
