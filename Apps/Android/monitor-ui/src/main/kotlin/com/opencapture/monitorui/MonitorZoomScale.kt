package com.opencapture.monitorui

import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt

/** Continuous logarithmic input; hundredths are reserved for labels and accessibility. */
object MonitorZoomScale {
    const val ANGULAR_SPAN = 210.0 * Math.PI / 180.0
    const val TICK_INCREMENT = 0.01
    const val MINOR_TICK_COUNT = 18
    val labeledTicks = listOf(1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 9.0, 12.0)
    val wholeStops = listOf(1.0, 2.0, 3.0, 4.0, 6.0, 9.0, 12.0)

    fun minorTickPositions(): List<Double> =
        (0..MINOR_TICK_COUNT).map { it.toDouble() / MINOR_TICK_COUNT }

    fun quantized(value: Double, minimum: Double = 1.0, maximum: Double): Double {
        if (!value.isFinite()) return minimum
        val lo = if (minimum.isFinite() && minimum > 0) minimum else 1.0
        val hi = if (maximum.isFinite()) maxOf(lo, maximum) else lo
        val clamped = value.coerceIn(lo, hi)
        val snapped = (clamped / TICK_INCREMENT).roundToInt() * TICK_INCREMENT
        return snapped.coerceIn(lo, hi)
    }

    fun dialLabel(value: Double, minimum: Double = 1.0, maximum: Double): String =
        String.format(java.util.Locale.US, "%.2f×", quantized(value, minimum, maximum))

    fun isLabeledTick(value: Double, minimum: Double = 1.0, maximum: Double): Boolean {
        val tick = quantized(value, minimum, maximum)
        return labeledTicks.any {
            abs(quantized(it, minimum, maximum) - tick) < TICK_INCREMENT / 2
        }
    }

    fun position(value: Double, minimum: Double, maximum: Double): Double {
        val lo = if (minimum.isFinite() && minimum > 0) minimum else 1.0
        val hi = if (maximum.isFinite()) maxOf(lo, maximum) else lo
        if (hi <= lo || !value.isFinite()) return 0.0
        return ln(value.coerceIn(lo, hi) / lo) / ln(hi / lo)
    }

    fun valueAt(position: Double, minimum: Double, maximum: Double): Double {
        val lo = if (minimum.isFinite() && minimum > 0) minimum else 1.0
        val hi = if (maximum.isFinite()) maxOf(lo, maximum) else lo
        if (!position.isFinite()) return lo
        return lo * (hi / lo).pow(position.coerceIn(0.0, 1.0))
    }

}
