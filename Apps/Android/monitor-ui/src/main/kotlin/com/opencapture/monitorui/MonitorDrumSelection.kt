package com.opencapture.monitorui

import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/** Pure detent policy, in logical display points, shared by both gesture modes. */
object MonitorDrumSelection {
    const val POINTS_PER_VALUE = 56f
    const val HOLD_MILLISECONDS = 280L
    const val DRAG_THRESHOLD = 14f

    fun position(origin: Float, translation: Float, count: Int): Float {
        if (count <= 0) return 0f
        val base = if (origin.isFinite()) origin else 0f
        val delta = if (translation.isFinite()) translation else 0f
        return (base - delta / POINTS_PER_VALUE).coerceIn(0f, (count - 1).toFloat())
    }

    fun settledIndex(origin: Float, translation: Float, count: Int): Int? =
        if (count <= 0) null else position(origin, translation, count).roundToInt()

    fun projectedPosition(position: Float): Float =
        if (position.isFinite()) (position - .55 * sin(2 * PI * position) / (2 * PI)).toFloat() else 0f
}
