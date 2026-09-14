package com.opencapture.monitorui

import kotlin.math.abs

/** Shortcut groups come from adapter-supported stops; this policy never invents zoom values. */
data class MonitorZoomTapStops(val singleTap: List<Double>, val doubleTap: List<Double>) {
    val primary: List<Double> get() = singleTap
    val secondary: List<Double> get() = doubleTap

    fun next(from: Double, extended: Boolean = false): Double? {
        val stops = if (extended) doubleTap else singleTap
        val first = stops.firstOrNull() ?: return null
        if (!from.isFinite()) return first
        return stops.firstOrNull { it > from + 0.05 } ?: first
    }

    companion object {
        fun from(supported: List<Double>, extended: List<Double> = emptyList()): MonitorZoomTapStops {
            val stops = supported.filter { it.isFinite() && it > 0.0 }.distinct().sorted()
            val extendedStops = stops.filter { it in extended }
            return MonitorZoomTapStops(
                singleTap = stops.filter { it !in extendedStops },
                doubleTap = extendedStops,
            )
        }

        fun from(supported: List<Double>, separateDigital: Boolean): MonitorZoomTapStops =
            from(supported, if (separateDigital) listOf(6.0, 12.0) else emptyList())
    }
}

/** @deprecated Use [MonitorZoomTapStops]. Kept so existing call sites compile while adapters switch. */
typealias MonitorZoomStops = MonitorZoomTapStops

object MonitorZoomCaption {
    fun label(factor: Double, opticalStops: List<Double>): String {
        if (!factor.isFinite()) return "WIDE"
        if (abs(factor - 1.0) < 0.05) return "WIDE"
        if (opticalStops.any { abs(it - 3.0) < 0.01 }) {
            if (abs(factor - 3.0) < 0.05) return "TELE"
            return if (factor > 3.0) "DIGITAL · SOFT" else "WIDE CROP"
        }
        return "DIGITAL CROP"
    }

    /** Past the last optical stop the picture is a digital crop (detail loss). */
    fun isDigital(factor: Double, opticalStops: List<Double>): Boolean {
        if (!factor.isFinite()) return false
        val opticalMax = opticalStops.filter { it.isFinite() && it > 0.0 }.maxOrNull() ?: 1.0
        return factor > opticalMax + 0.02
    }
}
