package com.opencapture.openpocketcine.lut

import kotlin.math.abs
import kotlin.math.round
import kotlin.math.pow

/**
 * iOS `LUTExposureCompensation`. Input-referred stops before the Rec.709 cube.
 * Negative is a pull (ETTR); not camera EV.
 */
internal object LutExposureCompensation {
    const val MIN_STOPS = -3.0
    const val MAX_STOPS = 3.0
    const val STEP = 0.5
    const val TITLE = "Exposure"
    const val HELP = "Input stops before the cube. Pull 1–2 after ETTR."

    fun snap(stops: Double): Double {
        if (!stops.isFinite()) return 0.0
        val clamped = stops.coerceIn(MIN_STOPS, MAX_STOPS)
        val snapped = round(clamped / STEP) * STEP
        return if (abs(snapped) < 0.0001) 0.0 else snapped
    }

    fun canStep(stops: Double, delta: Double): Boolean = stepped(stops, delta) != snap(stops)

    fun stepped(stops: Double, delta: Double): Double = snap(snap(stops) + delta)

    fun label(stops: Double): String {
        val value = snap(stops)
        if (value == 0.0) return "0.0"
        val formatted = "%+.1f".format(value)
        return formatted.replace("-", "−")
    }

    fun linearGain(stops: Double): Double = 2.0.pow(snap(stops))
}
