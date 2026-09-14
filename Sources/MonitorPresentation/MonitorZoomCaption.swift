import Foundation

/// Lens annotation for the zoom chip and disc hub. Optical stops come from the
/// adapter; this never invents 3× if the body does not have it.
public enum MonitorZoomCaption {
    public static func label(factor: Double, opticalStops: [Double]) -> String {
        guard factor.isFinite else { return "WIDE" }
        if abs(factor - 1) < 0.05 { return "WIDE" }
        if opticalStops.contains(where: { abs($0 - 3) < 0.01 }) {
            if abs(factor - 3) < 0.05 { return "TELE" }
            return factor > 3 ? "DIGITAL · SOFT" : "WIDE CROP"
        }
        return "DIGITAL CROP"
    }
}
