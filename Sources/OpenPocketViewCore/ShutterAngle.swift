import Foundation

/// Operator shutter-angle ladder. The body only accepts 1/N (`setShutter`);
/// we convert `angle = 360 × fps / denom` locally — no angle opcode.
///
/// Stops match OpenZCine's ANGLE tab: 5.6° … 360°.
public enum ShutterAngle: Sendable {
    public static let degrees: [Double] = [
        5.6, 11.2, 22.5, 45, 72, 86.4, 90, 108, 144, 172, 180, 216, 288, 346, 360,
    ]

    public static let defaultDegrees: Double = 180

    public static let labels: [String] = degrees.map(label)

    /// Integer fps for the conversion. Unknown / out of range falls back to 24.
    public static func effectiveFps(_ fps: Int) -> Int {
        (8...240).contains(fps) ? fps : 24
    }

    public static func label(_ degrees: Double) -> String {
        if abs(degrees - degrees.rounded()) < 0.05 {
            return "\(Int(degrees.rounded()))°"
        }
        return String(format: "%.1f°", degrees)
    }

    public static func parse(_ label: String) -> Double? {
        let trimmed = label.replacingOccurrences(of: "°", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 0, value <= 360 else { return nil }
        return value
    }

    /// 1/N that produces this angle at `fps`. Clamped to the SET range.
    public static func denom(degrees: Double, fps: Int) -> Int {
        let angle = max(degrees, 0.1)
        let rate = Double(effectiveFps(fps))
        let raw = (360.0 * rate / angle).rounded()
        return min(max(Int(raw), 1), 16_000)
    }

    /// Prefer a legal `camcap_shutter` stop when the body has published a list.
    public static func denom(degrees: Double, fps: Int, available: [Int]) -> Int {
        let ideal = denom(degrees: degrees, fps: fps)
        return CamCapShutter.nearestDenom(ideal, in: available) ?? ideal
    }

    public static func degrees(denom: Int, fps: Int) -> Double {
        guard denom > 0 else { return defaultDegrees }
        return 360.0 * Double(effectiveFps(fps)) / Double(denom)
    }

    public static func nearestDegrees(_ value: Double) -> Double {
        degrees.min(by: { abs($0 - value) < abs($1 - value) }) ?? defaultDegrees
    }

    public static func nearestLabel(denom: Int, fps: Int) -> String {
        label(nearestDegrees(degrees(denom: denom, fps: fps)))
    }
}
