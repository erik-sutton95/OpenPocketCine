package com.opencapture.openpocketcine

import com.opencapture.opencine.core.MonitorLayoutCapabilities
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureShutterPolicy

/**
 * The app's part of the layout: clip delete, clip star and the internet hop, until media and
 * connection routes carry them (SHELL-02). Everything else is what the camera declares; before the
 * body is known nothing camera-dependent (audio included) is laid out, the shared pre-connection rule.
 */
internal val appLayoutBase =
    MonitorLayoutCapabilities(clipDelete = true, clipStar = true, requiresInternetHop = true)

/** What the monitor lays out: the DJI integration's projection of the connected body (iOS `OsmoMonitorPresentation.capabilities`). */
internal fun AppModel.monitorLayout(): MonitorLayoutCapabilities = session.control.layout(appLayoutBase)

/**
 * The DJI integration's one control model of the connected body (iOS
 * `OsmoMonitorPresentation.controls`). The adapter knows the identified body; before identification
 * its model has no profile, so nothing camera-dependent is offered (the shared pre-connection rule).
 */
internal fun AppModel.controlCapabilities(): com.opencapture.opencine.vocabulary.ControlCapabilities =
    session.control.controlCapabilities()

/** AUDIO tile, assist, live meter and drum: a body that reports audio levels, in a video mode. */
internal fun AppModel.showsAudio(status: CameraStatus): Boolean =
    monitorLayout().audio && CaptureShutterPolicy.showsAudioControls(status.shootingMode)

/** The camera profile, including current recording mode limits, owns shortcut availability. */
internal fun AppModel.monitorZoomStops(): com.opencapture.monitorui.MonitorZoomTapStops {
    val profile = session.connectedCamera?.model
    val extended = if (profile?.zoomStops?.contains(12.0) == true) listOf(6.0, 12.0, 18.0) else emptyList()
    return com.opencapture.monitorui.MonitorZoomTapStops.from(session.zoomStops(), extended)
}
