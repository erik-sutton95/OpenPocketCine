package com.opencapture.monitorui

/** Matches MonitorPresentation.MonitorBackdropPolicy. One job in flight; no window capture. */
object MonitorBackdropPolicy {
    const val MAXIMUM_DIMENSION = 320
    const val MINIMUM_INTERVAL_NS = 16_666_667L

    // No thermal multiplier: glass behind the picture follows every source frame.
}
