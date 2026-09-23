package com.opencapture.openpocketcine

import com.opencapture.monitorui.MonitorCapabilities
import com.opencapture.openpocketcine.session.CameraStatus

/** The existing adapter remains the only authority for body-specific features. */
internal fun AppModel.monitorCapabilities(status: CameraStatus): MonitorCapabilities {
    val body = session.connectedCamera?.model
    return MonitorCapabilities(
        gimbal = session.hasGimbal,
        zoom = body?.activeZoomStops(status.resolutionCode, status.shootingMode)?.isNotEmpty() == true,
        focus = body?.supportsFocusMode == true,
        iris = body?.supportsAperture == true,
        audio = true,
        headTracking = session.hasGimbal,
        clipDelete = true,
        clipStar = true,
        requiresInternetHop = true,
        timecode = true,
    )
}

/** The camera profile, including current recording mode limits, owns shortcut availability. */
internal fun AppModel.monitorZoomStops(): com.opencapture.monitorui.MonitorZoomTapStops {
    val profile = session.connectedCamera?.model
    val extended = if (profile?.zoomStops?.contains(12.0) == true) listOf(6.0, 12.0) else emptyList()
    return com.opencapture.monitorui.MonitorZoomTapStops.from(session.zoomStops(), extended)
}
