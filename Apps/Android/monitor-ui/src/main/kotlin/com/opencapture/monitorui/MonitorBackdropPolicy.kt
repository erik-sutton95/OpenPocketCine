package com.opencapture.monitorui

/** Matches MonitorPresentation.MonitorBackdropPolicy. One job in flight; no window capture. */
object MonitorBackdropPolicy {
    const val MAXIMUM_DIMENSION = 320
    const val MINIMUM_INTERVAL_NS = 16_666_667L

    fun intervalNs(thermalMultiplier: Double = 1.0): Long =
        (MINIMUM_INTERVAL_NS * thermalMultiplier.coerceAtLeast(1.0)).toLong()
}
