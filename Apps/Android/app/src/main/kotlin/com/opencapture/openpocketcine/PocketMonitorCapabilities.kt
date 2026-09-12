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
