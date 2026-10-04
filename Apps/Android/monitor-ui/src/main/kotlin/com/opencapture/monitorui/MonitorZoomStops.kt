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
    /**
     * The longest stop that is a lens rather than a crop of one, or null on a body whose
     * only optics are wide.
     *
     * It is read off [opticalStops] rather than named, because which factor the second lens
     * lands on is the body's business: 3× on a Pocket 4 Pro, 2× on a Pocket 3 holding
     * Med-Tele.
     */
    fun opticalTele(opticalStops: List<Double>): Double? =
        opticalStops.filter { it.isFinite() && it > 1.05 }.maxOrNull()

    /** True while the picture is that second lens itself — full detail, no crop. */
    fun isOpticalTele(factor: Double, opticalStops: List<Double>): Boolean {
        val tele = opticalTele(opticalStops) ?: return false
        return factor.isFinite() && abs(factor - tele) < 0.05
    }

    fun label(factor: Double, opticalStops: List<Double>): String {
        if (!factor.isFinite()) return "WIDE"
        if (abs(factor - 1.0) < 0.05) return "WIDE"
        val tele = opticalTele(opticalStops) ?: return "DIGITAL CROP"
        if (abs(factor - tele) < 0.05) return "TELE"
        return if (factor > tele) "DIGITAL · SOFT" else "WIDE CROP"
    }

    /** Past the last optical stop the picture is a digital crop (detail loss). */
    fun isDigital(factor: Double, opticalStops: List<Double>): Boolean {
        if (!factor.isFinite()) return false
        val opticalMax = opticalStops.filter { it.isFinite() && it > 0.0 }.maxOrNull() ?: 1.0
        return factor > opticalMax + 0.02
    }
}
