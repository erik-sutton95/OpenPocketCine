import Foundation

/// Auto-exposure chip copy. EV stays the value; the camera-chosen shutter
/// remains readable in the caption.
public enum MonitorExposureReadout: Sendable {
    public static func autoEvCaption(shutterDenom: Int) -> String {
        shutterDenom > 0 ? "EV 1/\(shutterDenom)s" : "EV"
    }
}
