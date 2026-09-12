package com.opencapture.openpocketcine

import com.opencapture.monitorui.MonitorCapabilities
import com.opencapture.openpocketcine.session.CameraStatus

/** The existing adapter remains the only authority for body-specific features. */
internal fun AppModel.monitorCapabilities(status: CameraStatus): MonitorCapabilities {
    val body = session.connectedCamera?.model
    return MonitorCapabilities(
        gimbal = session.hasGimbal,
        zoom = body?.activeZoomStops(status.resolutionCode, status.shootingMode)?.size?.let { it > 1 } ?: false,
        focus = body?.supportsFocusMode == true,
        timecode = status.timecode?.isNotBlank() == true,
    )
}

/** The camera profile, including current recording mode limits, owns shortcut availability. */
internal fun AppModel.monitorZoomStops(): com.opencapture.monitorui.MonitorZoomStops {
    val profile = session.connectedCamera?.model
    val separateDigital = profile?.zoomStops?.containsAll(listOf(1.0, 3.0, 6.0, 12.0)) == true
    return com.opencapture.monitorui.MonitorZoomStops.from(session.zoomStops(), separateDigital)
}
