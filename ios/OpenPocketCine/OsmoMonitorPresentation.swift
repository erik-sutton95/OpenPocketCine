import Foundation
import MonitorPresentation
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

    static func capabilities(_ session: CameraSession) -> MonitorCapabilities {
        #if targetEnvironment(simulator)
            if MonitorUIReview.isActive {
                let gimbal = ProcessInfo.processInfo.environment["OPV_UI_REVIEW_BODY"] != "nano"
                return MonitorCapabilities(
                    gimbal: gimbal, zoom: gimbal, focus: gimbal, audio: true,
                    headTracking: gimbal, clipDelete: true, clipStar: true,
                    requiresInternetHop: true, timecode: true)
            }
        #endif
        return MonitorCapabilities(
            gimbal: session.hasGimbal, zoom: session.supportsZoom,
            focus: session.supportsFocusMode, iris: session.supportsAperture, audio: true,
            headTracking: session.hasGimbal, clipDelete: true, clipStar: true,
            requiresInternetHop: true, timecode: true)
    }
}
