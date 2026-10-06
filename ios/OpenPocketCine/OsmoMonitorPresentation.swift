import Foundation
import MonitorPresentation
import OpenCineCore
import OpenPocketViewCore

/// Capability translation belongs to the Osmo adapter. Native monitor modules
/// never need to identify a camera brand, body name, or wire opcode.
@MainActor
enum OsmoMonitorPresentation {
    static func zoomTapStops(_ session: CameraSession) -> MonitorZoomTapStops {
        // Only the Pro's native capability table includes the 6×/12× range.
        // Other bodies retain their full ordinary tap sequence (including 4×).
        let supportsExtended =
            session.connectedCamera?.model.zoomStops.contains(12)
            ?? session.zoomStops.contains(12)
        return MonitorZoomTapStops(
            supported: session.zoomStops, extended: supportsExtended ? [6, 12] : [])
    }

    static func zoomCaption(_ session: CameraSession) -> String {
        MonitorZoomCaption.label(factor: session.zoomReadout, opticalStops: session.zoomStops)
    }

    /// What the monitor lays out: the DJI integration's projection of the connected body
    /// (`DJICameraSessionAdapter.layout`). Only clip delete, clip star and the internet hop are
    /// the app's, until media and connection routes carry them (SHELL-02). Audio stays on before
    /// the body is known, as main offered the AUDIO tile and Clean view pin on every body.
    static func capabilities(_ session: CameraSession) -> MonitorLayoutCapabilities {
        var layout = session.control.layout(base: appBase)
        // Single view shows the timecode on every body, Nano included, as main did; Multi View
        // reads the body's declaration.
        layout.timecode = true
        return layout
    }

    private static let appBase: MonitorLayoutCapabilities = {
        var base = MonitorLayoutCapabilities()
        base.audio = true
        base.clipDelete = true
        base.clipStar = true
        base.requiresInternetHop = true
        return base
    }()
}
