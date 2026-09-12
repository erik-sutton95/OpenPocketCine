import Foundation
import MonitorPresentation
import OpenPocketViewCore

/// Capability translation belongs to the Osmo adapter. Native monitor modules
/// never need to identify a camera brand, body name, or wire opcode.
@MainActor
enum OsmoMonitorPresentation {
    static func zoomCaption(_ session: CameraSession) -> String {
        let factor = session.zoomReadout
        if abs(factor - 1) < 0.05 { return "WIDE" }
        if session.zoomStops.contains(3) {
            if abs(factor - 3) < 0.05 { return "TELE" }
            return factor > 3 ? "DIGITAL · SOFT" : "WIDE CROP"
        }
        return "DIGITAL CROP"
    }

    static func capabilities(_ session: CameraSession) -> MonitorCapabilities {
        #if targetEnvironment(simulator)
            if MonitorUIReview.isActive {
                let gimbal = ProcessInfo.processInfo.environment["OPV_UI_REVIEW_BODY"] != "nano"
                return MonitorCapabilities(
                    gimbal: gimbal, zoom: true, focus: true, audio: true,
                    headTracking: gimbal, requiresInternetHop: true)
            }
        #endif
        return MonitorCapabilities(
            gimbal: session.hasGimbal, zoom: !session.zoomStops.isEmpty,
            focus: session.supportsFocusMode, audio: true,
            headTracking: session.hasGimbal, requiresInternetHop: true)
    }
}
