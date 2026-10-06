package com.opencapture.openpocketcine

import com.opencapture.opencine.core.MonitorLayoutCapabilities
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureShutterPolicy

/**
 * The app's part of the layout: clip delete, clip star and the internet hop, until media and
 * connection routes carry them (SHELL-02). Audio stays on before the body is known, as main
 * offered the AUDIO tile and Clean view pin on every body. Everything else is what the camera
 * declares.
 */
internal val appLayoutBase =
    MonitorLayoutCapabilities(audio = true, clipDelete = true, clipStar = true, requiresInternetHop = true)

/** What the monitor lays out: the DJI integration's projection of the connected body (iOS `OsmoMonitorPresentation.capabilities`). */
internal fun AppModel.monitorLayout(): MonitorLayoutCapabilities = singleViewLayout(session.control.layout(appLayoutBase))

/** Single view shows the timecode on every body, Nano included, as main did; Multi View reads the body's declaration. */
internal fun singleViewLayout(declared: MonitorLayoutCapabilities): MonitorLayoutCapabilities = declared.copy(timecode = true)

/** AUDIO tile, assist, live meter and drum: a body that reports audio levels, in a video mode. */
internal fun AppModel.showsAudio(status: CameraStatus): Boolean =
    monitorLayout().audio && CaptureShutterPolicy.showsAudioControls(status.shootingMode)

/** The camera profile, including current recording mode limits, owns shortcut availability. */
internal fun AppModel.monitorZoomStops(): com.opencapture.monitorui.MonitorZoomTapStops {
    val profile = session.connectedCamera?.model
    val extended = if (profile?.zoomStops?.contains(12.0) == true) listOf(6.0, 12.0) else emptyList()
    return com.opencapture.monitorui.MonitorZoomTapStops.from(session.zoomStops(), extended)
}
