package com.opencapture.monitorui

import androidx.compose.ui.layout.LayoutCoordinates
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Reversible displayed-order sweep. Unchanged endpoints do not rebuild the set. */
class MonitorMediaDragSelection private constructor(
    private val ids: List<String>,
    private val original: Set<String>,
    private val origin: Int,
    private val selects: Boolean,
    private val selected: LinkedHashSet<String>,
) {
    private var endpoint = origin
    val selectedIds: Set<String> get() = selected.toSet()

    init { apply(origin, sweeping = true) }

    fun move(to: Int): Boolean {
        if (ids.isEmpty()) return false
        val next = to.coerceIn(0, ids.lastIndex)
        if (next == endpoint) return false
        val oldLow = min(origin, endpoint)
        val oldHigh = max(origin, endpoint)
        val newLow = min(origin, next)
        val newHigh = max(origin, next)
        if (oldLow < newLow) for (i in oldLow until newLow) apply(i, sweeping = false)
        if (newHigh < oldHigh) for (i in (newHigh + 1)..oldHigh) apply(i, sweeping = false)
        if (newLow < oldLow) for (i in newLow until oldLow) apply(i, sweeping = true)
        if (oldHigh < newHigh) for (i in (oldHigh + 1)..newHigh) apply(i, sweeping = true)
        endpoint = next
        return true
    }

    private fun apply(index: Int, sweeping: Boolean) {
        val id = ids[index]
        if (if (sweeping) selects else original.contains(id)) selected.add(id) else selected.remove(id)
    }

    companion object {
        fun start(orderedIds: List<String>, originId: String, selectedIds: Set<String>): MonitorMediaDragSelection? {
            val index = orderedIds.indexOf(originId)
            if (index < 0) return null
            val selected = LinkedHashSet(selectedIds)
            return MonitorMediaDragSelection(
                orderedIds, selectedIds, index, originId !in selectedIds, selected,
            )
        }
    }
}

object MonitorMediaSelectionPolicy {
    const val HOLD_MS = 280L
    const val HOLD_SLOP = 5f
    const val EDGE_BAND = 56f
    const val MAX_EDGE_VELOCITY = 720f
    const val MAX_FRAME_DT = 0.05f

    fun edgeBand(viewportHeight: Float): Float =
        if (!viewportHeight.isFinite() || viewportHeight <= 0f) 0f
        else min(EDGE_BAND, viewportHeight / 3f)

    fun edgeVelocity(y: Float, viewportHeight: Float): Float {
        if (!y.isFinite() || !viewportHeight.isFinite() || viewportHeight <= 0f) return 0f
        val edge = edgeBand(viewportHeight)
        if (edge <= 0f) return 0f
        if (y < edge) {
            val strength = ((edge - y) / edge).coerceIn(0f, 1f)
            return -MAX_EDGE_VELOCITY * strength * strength
        }
        if (y > viewportHeight - edge) {
            val strength = ((y - viewportHeight + edge) / edge).coerceIn(0f, 1f)
            return MAX_EDGE_VELOCITY * strength * strength
        }
        return 0f
    }
}

/** Visible-item bounds only. Off-screen lazy leftovers are ignored. */
class MonitorMediaHitRegistry {
    data class Box(val id: String, val left: Float, val top: Float, val right: Float, val bottom: Float)

    var host: LayoutCoordinates? = null
    private val items = ArrayList<Box>(16)

    fun putFrom(id: String, item: LayoutCoordinates) {
        val root = host
        if (root == null || !root.isAttached || !item.isAttached) return
        val rect = root.localBoundingBoxOf(item, clipBounds = false)
        put(id, rect.left, rect.top, rect.right, rect.bottom)
    }

    fun put(id: String, left: Float, top: Float, right: Float, bottom: Float) {
        val box = Box(id, left, top, right, bottom)
        val index = items.indexOfFirst { it.id == id }
        if (index >= 0) items[index] = box else items.add(box)
    }

    fun remove(id: String) { items.removeAll { it.id == id } }

    fun clear() { items.clear() }

    fun resolve(
        x: Float, y: Float, viewportWidth: Float, viewportHeight: Float, nearest: Boolean,
    ): String? {
        if (!x.isFinite() || !y.isFinite() || !viewportWidth.isFinite() || !viewportHeight.isFinite()) return null
        if (viewportWidth <= 0f || viewportHeight <= 0f) return null
        if (!nearest && (x < 0f || y < 0f || x >= viewportWidth || y >= viewportHeight)) return null
        val cx = x.coerceIn(1f, max(1f, viewportWidth - 1f))
        val cy = y.coerceIn(1f, max(1f, viewportHeight - 1f))
        var closest: Box? = null
        var closestDistance = Float.POSITIVE_INFINITY
        for (box in items) {
            if (box.right <= 0f || box.left >= viewportWidth || box.bottom <= 0f || box.top >= viewportHeight) continue
            if (cx >= box.left && cx < box.right && cy >= box.top && cy < box.bottom) return box.id
            if (nearest) {
                val dx = max(box.left - cx, max(0f, cx - box.right))
                val dy = max(box.top - cy, max(0f, cy - box.bottom))
                val distance = dx * dx + dy * dy
                if (distance < closestDistance) {
                    closest = box
                    closestDistance = distance
                }
            }
        }
        return if (nearest) closest?.id else null
    }
}

/**
 * Pointer/hold/range state machine. Compose supplies positions, hits, and frame dt.
 * News.Selection is omitted when the active endpoint did not change.
 */
class MonitorMediaSelectionController(
    var slop: Float = MonitorMediaSelectionPolicy.HOLD_SLOP,
    var holdMs: Long = MonitorMediaSelectionPolicy.HOLD_MS,
) {
    sealed class News {
        data class Open(val id: String) : News()
        data class Selection(val selecting: Boolean, val selected: Set<String>) : News()
    }

    var ids: List<String> = emptyList()
        private set
    var selecting: Boolean = false
        private set
    var selected: Set<String> = emptySet()
        private set
    val consuming: Boolean get() = sweep != null
    var fingerX: Float = 0f
        private set
    var fingerY: Float = 0f
        private set

    private var indexById: Map<String, Int> = emptyMap()
    private var pointerDown = false
    private var downX = 0f
    private var downY = 0f
    private var downTime = 0L
    private var downId: String? = null
    private var moved = false
    private var scrollLocked = false
    private var sweep: MonitorMediaDragSelection? = null

    fun bind(ids: List<String>, selecting: Boolean, selected: Set<String>) {
        if (ids != this.ids) {
            if (sweep != null || pointerDown) cancel()
            this.ids = ids
            indexById = ids.withIndex().associate { it.value to it.index }
        }
        if (sweep == null) {
            this.selecting = selecting
            this.selected = selected
        }
    }

    fun down(id: String?, x: Float, y: Float, timeMs: Long) {
        pointerDown = true
        downId = id
        downX = x
        downY = y
        downTime = timeMs
        moved = false
        scrollLocked = false
        fingerX = x
        fingerY = y
    }

    fun move(id: String?, x: Float, y: Float): News? {
        if (!pointerDown) return null
        fingerX = x
        fingerY = y
        val dx = x - downX
        val dy = y - downY
        if (dx * dx + dy * dy >= slop * slop) moved = true
        if (moved && selecting && sweep == null && !scrollLocked &&
            abs(fingerY - downY) >= abs(fingerX - downX)
        ) {
            scrollLocked = true
        }
        if (sweep != null) return hover(id)
        if (selecting && moved && !scrollLocked) {
            val origin = downId ?: id ?: return null
            val started = begin(origin)
            return hover(id) ?: started
        }
        return null
    }

    /** Vertical-dominant motion in selection mode stays a native scroll for this touch. */
    fun shouldYieldToScroll(): Boolean {
        if (!pointerDown || sweep != null || !moved) return false
        if (!selecting) return true
        return scrollLocked
    }

    fun holdDue(timeMs: Long): News? {
        if (!pointerDown || moved || sweep != null) return null
        if (timeMs - downTime < holdMs) return null
        val id = downId ?: return null
        return begin(id)
    }

    fun up(childConsumed: Boolean): News? {
        if (!pointerDown) return null
        pointerDown = false
        val active = sweep
        sweep = null
        if (active != null) return null
        if (childConsumed || moved) return null
        val tapId = downId ?: return null
        return if (selecting) {
            val next = LinkedHashSet(selected)
            if (!next.add(tapId)) next.remove(tapId)
            selected = next
            News.Selection(true, next)
        } else {
            News.Open(tapId)
        }
    }

    fun cancel() {
        pointerDown = false
        sweep = null
        moved = false
        scrollLocked = false
        downId = null
    }

    fun inEdgeBand(viewportHeight: Float, density: Float = 1f): Boolean {
        val scale = if (density.isFinite() && density > 0f) density else 1f
        return sweep != null && pointerDown &&
            MonitorMediaSelectionPolicy.edgeVelocity(fingerY / scale, viewportHeight / scale) != 0f
    }

    fun edgeScroll(dt: Float, viewportHeight: Float, density: Float = 1f): Float {
        if (sweep == null || !pointerDown || !dt.isFinite() || dt <= 0f) return 0f
        val scale = if (density.isFinite() && density > 0f) density else 1f
        val step = min(dt, MonitorMediaSelectionPolicy.MAX_FRAME_DT)
        return MonitorMediaSelectionPolicy.edgeVelocity(fingerY / scale, viewportHeight / scale) * scale * step
    }

    fun afterScroll(hitId: String?): News? {
        if (sweep == null) return null
        return hover(hitId)
    }

    private fun begin(id: String): News? {
        val next = MonitorMediaDragSelection.start(ids, id, selected) ?: return null
        sweep = next
        selecting = true
        selected = next.selectedIds
        return News.Selection(true, selected)
    }

    private fun hover(hitId: String?): News? {
        val active = sweep ?: return null
        val index = hitId?.let { indexById[it] } ?: return null
        if (!active.move(index)) return null
        selected = active.selectedIds
        return News.Selection(true, selected)
    }
}
