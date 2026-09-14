package com.opencapture.monitorui

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt

/** Detent impacts for dials. Tiny neighbors stay silent; 172° → 180° still thonks. */
object MonitorDialHaptic {
    const val COARSE_LIMIT = 24

    fun shouldTick(previous: String?, next: String, optionCount: Int): Boolean {
        if (next == previous) return false
        if (optionCount <= COARSE_LIMIT) return true
        return isMajor(next)
    }

    /** Empty [majors] ticks whole-unit crossings. Zoom passes [MonitorZoomScale.wholeStops]. */
    fun shouldTick(previous: Double, next: Double, majors: List<Double> = emptyList()): Boolean {
        if (!previous.isFinite() || !next.isFinite() || abs(next - previous) <= 1e-9) return false
        val lo = minOf(previous, next)
        val hi = maxOf(previous, next)
        if (majors.isEmpty()) {
            val whole = floor(lo) + 1
            return whole <= hi + 1e-9 && whole > lo + 1e-9
        }
        return majors.any { stop ->
            abs(next - stop) < 0.005 && abs(previous - stop) >= 0.005 || stop > lo && stop <= hi
        }
    }

    fun isMajor(label: String): Boolean {
        val trimmed = label.trim()
        if (trimmed.isEmpty()) return false
        when {
            trimmed.endsWith("°") -> return true
            trimmed.endsWith("×") || trimmed.endsWith("x", ignoreCase = true) -> {
                val number = trimmed.dropLast(1).toDoubleOrNull() ?: 0.0
                return MonitorZoomScale.wholeStops.any { abs(it - number) < 0.05 }
            }
            trimmed.endsWith("K") -> {
                val kelvin = trimmed.dropLast(1).toIntOrNull() ?: 0
                return kelvin in setOf(2000, 2800, 3200, 4300, 5600, 6500, 8000, 10000)
            }
            trimmed.endsWith("s") -> {
                val seconds = trimmed.dropLast(1).toDoubleOrNull() ?: return false
                return seconds >= 0 && abs(seconds - seconds.roundToInt()) < 0.05
            }
        }
        trimmed.indexOf('/').takeIf { it >= 0 }?.let { slash ->
            val denom = trimmed.substring(slash + 1).toIntOrNull() ?: 0
            return denom in setOf(24, 25, 30, 48, 50, 60, 90, 100, 120, 125, 180, 250, 500, 1000)
        }
        trimmed.toIntOrNull()?.let { iso ->
            return iso in setOf(50, 100, 200, 400, 800, 1600, 3200, 6400, 12800, 25600)
        }
        return trimmed.none { it.isDigit() }
    }
}
