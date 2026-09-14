package com.opencapture.monitorui

/** Auto-exposure chip copy. EV stays the value; camera-chosen shutter stays in the caption. */
object MonitorExposureReadout {
    fun autoEvCaption(shutterDenom: Int): String =
        if (shutterDenom > 0) "EV 1/${shutterDenom}s" else "EV"
}
