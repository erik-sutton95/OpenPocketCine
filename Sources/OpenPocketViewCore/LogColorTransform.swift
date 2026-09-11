import Foundation

/// Technical D-Log ↔ D-Log2 convert. Decode source log, move D-Gamut ↔
/// D-Gamut2 through Rec.709 linear, encode dest log. Not a look LUT.
///
/// Rec.709 display stays the official cube (Bake LUT). D-Log M is out.
public enum LogColorTransform: String, Equatable, Sendable, CaseIterable, Identifiable {
    case dLogToDLog2
    case dLog2ToDLog

    public var id: String { rawValue }

    public var source: MonitorTransfer {
        switch self {
        case .dLogToDLog2: .dlog
        case .dLog2ToDLog: .dlog2
        }
    }

    public var destination: MonitorTransfer {
        switch self {
        case .dLogToDLog2: .dlog2
        case .dLog2ToDLog: .dlog
        }
    }

    public var label: String { "\(source.label) → \(destination.label)" }

    /// Filename stem token for the dest log (`clip.dlog2.mov`).
    public var filenameToken: String {
        switch destination {
        case .dlog2: "dlog2"
        case .dlog: "dlog"
        default: rawValue
        }
    }

    public static func converting(from colorMode: ColorMode) -> LogColorTransform? {
        switch colorMode {
        case .dLog: .dLogToDLog2
        case .dLog2: .dLog2ToDLog
        default: nil
        }
    }

    /// One destination per batch. A clip already on that curve needs no transform.
    public static func converting(
        from colorMode: ColorMode, to destination: MonitorTransfer
    ) -> LogColorTransform? {
        guard let transform = converting(from: colorMode), transform.destination == destination
        else {
            return nil
        }
        return transform
    }

    public func apply(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        let linear = LiveColorScience.linearizeRGB(
            red: r, green: g, blue: b, transfer: source)
        let rec709 = sourceGamutToRec709(r: linear.red, g: linear.green, b: linear.blue)
        let destLinear = rec709ToDestinationGamut(r: rec709.r, g: rec709.g, b: rec709.b)
        return (
            LiveColorScience.encode(destLinear.r, transfer: destination),
            LiveColorScience.encode(destLinear.g, transfer: destination),
            LiveColorScience.encode(destLinear.b, transfer: destination)
        )
    }

    /// Sampled 3D table for the existing export bake (`CIColorCube`).
    public func cube(size: Int = CubeLUT.colorCubeMaxDimension) -> CubeLUT {
        let n = max(2, min(size, CubeLUT.colorCubeMaxDimension))
        let denom = Double(n - 1)
        var rgb = [Float]()
        rgb.reserveCapacity(n * n * n * 3)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let mapped = apply(
                        r: Double(r) / denom, g: Double(g) / denom, b: Double(b) / denom)
                    rgb.append(Float(mapped.r))
                    rgb.append(Float(mapped.g))
                    rgb.append(Float(mapped.b))
                }
            }
        }
        return CubeLUT(size: n, rgb: rgb)
    }

    private func sourceGamutToRec709(r: Double, g: Double, b: Double) -> (
        r: Double, g: Double, b: Double
    ) {
        switch source {
        case .dlog: DGamut.rgbToRec709.apply(r: r, g: g, b: b)
        case .dlog2: DGamut2.rgbToRec709.apply(r: r, g: g, b: b)
        case .rec709, .hdr, .dlogm: (r, g, b)
        }
    }

    private func rec709ToDestinationGamut(r: Double, g: Double, b: Double) -> (
        r: Double, g: Double, b: Double
    ) {
        switch destination {
        case .dlog: DGamut.rec709ToRGB.apply(r: r, g: g, b: b)
        case .dlog2: DGamut2.rec709ToRGB.apply(r: r, g: g, b: b)
        case .rec709, .hdr, .dlogm: (r, g, b)
        }
    }
}
