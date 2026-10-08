import OpenCineCameraControls
import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Fixed camera telemetry chrome. It has no assist state, gestures or pixel sampling.
enum CameraEVMeter {
    static func frame(in feed: CGRect, avoiding obstacle: CGRect? = nil) -> CGRect {
        MonitorOperatorExposureGeometry.frame(in: feed, avoiding: obstacle)
    }
}
