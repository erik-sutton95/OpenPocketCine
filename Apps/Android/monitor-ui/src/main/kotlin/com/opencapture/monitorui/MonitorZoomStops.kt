package com.opencapture.monitorui

/** Shortcut groups come from adapter-supported stops; this policy never invents zoom values. */
data class MonitorZoomStops(val primary: List<Double>, val secondary: List<Double>) {
    companion object {
        fun from(supported: List<Double>, separateDigital: Boolean): MonitorZoomStops {
            val legal = supported.filter { it.isFinite() && it >= 1.0 }.distinct().sorted()
            return if (separateDigital) MonitorZoomStops(legal.filter { it <= 3.0 }, legal.filter { it == 6.0 || it == 12.0 })
                else MonitorZoomStops(legal, emptyList())
        }
    }
}
