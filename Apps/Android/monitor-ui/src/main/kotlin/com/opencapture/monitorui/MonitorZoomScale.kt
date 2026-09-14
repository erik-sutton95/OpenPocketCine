package com.opencapture.monitorui

import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt

/** Mirrors portable MonitorZoomScale tick and hundredths readout policy. */
object MonitorZoomScale {
    const val ANGULAR_SPAN = 210.0 * Math.PI / 180.0
    const val TICK_INCREMENT = 0.01
    const val MINOR_TICK_COUNT = 18
    val labeledTicks = listOf(1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 9.0, 12.0)
    val wholeStops = listOf(1.0, 2.0, 3.0, 4.0, 6.0, 9.0, 12.0)
    const val SLOW_SNAP_STEP = 0.025
    const val SLOW_SNAP_IN = 0.03
    const val SLOW_SNAP_HOLD = 0.06

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

    /** Light magnet on 2× / 3× / 4× … only when the pointer is barely moving. */
    fun slowSnap(next: Double, current: Double, minimum: Double = 1.0, maximum: Double): Double {
        val here = quantized(current, minimum, maximum)
        val there = quantized(next, minimum, maximum)
        if (abs(there - here) > SLOW_SNAP_STEP) return there
        val stops = wholeStops.filter { it >= minimum - 0.001 && it <= maximum + 0.001 }
        stops.firstOrNull { abs(here - it) < TICK_INCREMENT / 2 }?.let { held ->
            return if (abs(there - held) < SLOW_SNAP_HOLD) quantized(held, minimum, maximum) else there
        }
        stops.firstOrNull { abs(there - it) <= SLOW_SNAP_IN }?.let { stop ->
            return quantized(stop, minimum, maximum)
        }
        return there
    }

}
