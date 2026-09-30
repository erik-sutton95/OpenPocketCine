import Foundation

/// Lens annotation for the zoom chip and disc hub. Optical stops come from the
/// adapter; this never invents 3× if the body does not have it.
public enum MonitorZoomCaption {
    /// The body's longest optical stop, whatever it is: 3× on a Pocket 4 Pro,
    /// 2× on a Pocket 3 wearing Med-Tele. Naming a number here would be wrong
    /// for one of them, so read it off the stops the adapter reported.
    public static func opticalTele(_ opticalStops: [Double]) -> Double? {
        opticalStops.filter { $0.isFinite && $0 > 1.05 }.max()
    }

    /// True when this factor is the optical tele itself — a second lens, not a
    /// crop that happens to land on the same number.
    public static func isOpticalTele(factor: Double, opticalStops: [Double]) -> Bool {
        guard let tele = opticalTele(opticalStops), factor.isFinite else { return false }
        return abs(factor - tele) < 0.05
    }

    public static func label(factor: Double, opticalStops: [Double]) -> String {
        guard factor.isFinite else { return "WIDE" }
        if abs(factor - 1) < 0.05 { return "WIDE" }
        guard let tele = opticalTele(opticalStops) else { return "DIGITAL CROP" }
        if abs(factor - tele) < 0.05 { return "TELE" }
        return factor > tele ? "DIGITAL · SOFT" : "WIDE CROP"
    }

    /// Past the last optical stop the picture is a digital crop (detail loss).
    public static func isDigital(factor: Double, opticalStops: [Double]) -> Bool {
        guard factor.isFinite else { return false }
        let opticalMax = opticalStops.filter { $0.isFinite && $0 > 0 }.max() ?? 1
        return factor > opticalMax + 0.02
    }
}
