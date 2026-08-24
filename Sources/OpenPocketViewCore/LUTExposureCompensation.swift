import Foundation

/// Input-referred stops applied **before** the Rec.709 cube.
///
/// ETTR: expose 1–2 stops hot, then pull here so the cube's mid-grey lands.
/// Negative is a pull; positive is a push. Not camera EV — that SET stays
/// on the body.
public enum LUTExposureCompensation: Sendable {
    public static let minStops: Double = -3
    public static let maxStops: Double = 3
    public static let step: Double = 0.5

    /// Half-stop ticks from ``minStops`` through ``maxStops`` (13 values).
    public static var stops: [Double] {
        var values: [Double] = []
        var value = minStops
        while value <= maxStops + 0.000_1 {
            values.append(snap(value))
            value += step
        }
        return values
    }

    public static func snap(_ stops: Double) -> Double {
        guard stops.isFinite else { return 0 }
        let clamped = min(max(stops, minStops), maxStops)
        let snapped = (clamped / step).rounded() * step
        return abs(snapped) < 0.000_1 ? 0 : snapped
    }

    public static func canStep(_ stops: Double, by delta: Double) -> Bool {
        stepped(stops, by: delta) != snap(stops)
    }

    public static func stepped(_ stops: Double, by delta: Double) -> Double {
        snap(snap(stops) + delta)
    }

    /// Operator chrome: `0.0`, `+1.5`, `−2.0`.
    public static func label(_ stops: Double) -> String {
        let value = snap(stops)
        if value == 0 { return "0.0" }
        return String(format: "%+.1f", value).replacingOccurrences(of: "-", with: "−")
    }

    public static func linearGain(_ stops: Double) -> Double {
        pow(2.0, snap(stops))
    }

    /// Encoded camera code after an exposure gain in the transfer's linear light.
    public static func compensateEncoded(
        _ encoded: Double, stops: Double, transfer: MonitorTransfer
    ) -> Double {
        let value = snap(stops)
        if value == 0 { return min(max(encoded, 0), 1) }
        let linear = LiveColorScience.linearize(encoded, transfer: transfer)
        return LiveColorScience.encode(linear * linearGain(value), transfer: transfer)
    }
}

extension CubeLUT {
    /// Remap cube **inputs** by ``LUTExposureCompensation`` so a pulled log
    /// code hits the Rec.709 slot the cube expected at nominal exposure.
    /// `stops == 0` returns `self`.
    public func compensatingExposure(stops: Double, transfer: MonitorTransfer) -> CubeLUT {
        let value = LUTExposureCompensation.snap(stops)
        if value == 0 { return self }
        let n = size
        guard n >= 2, rgb.count == n * n * n * 3 else { return self }
        let denom = Double(n - 1)
        var out = [Float]()
        out.reserveCapacity(rgb.count)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let er = LUTExposureCompensation.compensateEncoded(
                        Double(r) / denom, stops: value, transfer: transfer)
                    let eg = LUTExposureCompensation.compensateEncoded(
                        Double(g) / denom, stops: value, transfer: transfer)
                    let eb = LUTExposureCompensation.compensateEncoded(
                        Double(b) / denom, stops: value, transfer: transfer)
                    let mapped = map(red: Float(er), green: Float(eg), blue: Float(eb))
                    out.append(mapped.red)
                    out.append(mapped.green)
                    out.append(mapped.blue)
                }
            }
        }
        return CubeLUT(size: n, rgb: out)
    }

    /// Share / export cube. `bakeExposure` false is the table at 0.0; true
    /// applies ``compensatingExposure(stops:transfer:)`` so the file matches
    /// the monitor pull.
    public func preparedForExport(
        bakeExposure: Bool, stops: Double, transfer: MonitorTransfer
    ) -> CubeLUT {
        let gpu = colorCube
        guard bakeExposure else { return gpu }
        return gpu.compensatingExposure(stops: stops, transfer: transfer)
    }
}
