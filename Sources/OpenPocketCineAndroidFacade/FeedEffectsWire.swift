import Foundation
import OpenPocketViewCore

/// Bakes LUT-adjacent assist payloads for the Android GLES feed.
///
/// Overlay cubes and zebra codes follow iOS `PocketFalseColorMap` /
/// `LiveMonitorCompositor` so PEAK / FALSE / ZEBRA / LUT match the Metal path.
/// Compiles on Darwin so `swift test` exercises the same lattice as the APK.
public enum FeedEffectsWire {
    public static let falseColorCubeSize = 64
    public static let assistScalarCount = 4
    public static let stopsDetailBlend = 0.4

    public static func monitorTransfer(colorModeCode: Int) -> MonitorTransfer {
        guard (0...255).contains(colorModeCode),
            let mode = ColorMode(rawValue: UInt8(colorModeCode))
        else { return .rec709 }
        return MonitorTransfer(mode)
    }

    public static func falseColorScale(_ ordinal: Int) -> LiveFalseColorScale? {
        switch ordinal {
        case 0: .stops
        case 1: .ire
        case 2: .limits
        default: nil
        }
    }

    /// Packed-2D RGBA8 overlay paint (`n³ × 4`). Sampled on encoded camera codes.
    public static func packedFalseColorPaint(
        scaleOrdinal: Int, colorModeCode: Int, iso: Int
    ) -> [UInt8]? {
        guard let scale = falseColorScale(scaleOrdinal) else { return nil }
        let transfer = preparedTransfer(colorModeCode: colorModeCode, iso: iso)
        let key = cacheKey("paint", scale: scale, transfer: transfer)
        return cached(key) {
            LUTLibraryWire.packedRGBA(
                cube: overlayCube(scale: scale, transfer: transfer) {
                    ($0.red, $0.green, $0.blue)
                })
        }
    }

    /// Packed-2D RGBA8 overlay weight. IRE / PStops are opaque; Limits is holes-only.
    public static func packedFalseColorWeight(
        scaleOrdinal: Int, colorModeCode: Int, iso: Int
    ) -> [UInt8]? {
        guard let scale = falseColorScale(scaleOrdinal) else { return nil }
        let transfer = preparedTransfer(colorModeCode: colorModeCode, iso: iso)
        let key = cacheKey("weight", scale: scale, transfer: transfer)
        return cached(key) {
            LUTLibraryWire.packedRGBA(
                cube: overlayCube(scale: scale, transfer: transfer) {
                    ($0.weight, $0.weight, $0.weight)
                })
        }
    }

    /// `[highlightNative, midtoneNative, midtoneHalfNative, peakingGateScale]`.
    public static func assistScalars(
        colorModeCode: Int, iso: Int, highlightIRE: Double, midtoneIRE: Double
    ) -> [Float] {
        let transfer = preparedTransfer(colorModeCode: colorModeCode, iso: iso)
        let highlight = ScopeDisplayScale.signalNative(
            monitorPercent: highlightIRE, transfer: transfer)
        let half = LiveZebra.midtoneHalfWidthIRE
        let lo = ScopeDisplayScale.signalNative(
            monitorPercent: midtoneIRE - half, transfer: transfer)
        let hi = ScopeDisplayScale.signalNative(
            monitorPercent: midtoneIRE + half, transfer: transfer)
        return [
            Float(highlight),
            Float((lo + hi) * 0.5),
            Float(abs(hi - lo) * 0.5),
            Float(peakingGateScale(for: transfer)),
        ]
    }

    /// Display-referred feeds read larger gradients than log (iOS `peakingGateScale`).
    public static func peakingGateScale(for transfer: MonitorTransfer) -> Double {
        switch transfer {
        case .rec709, .hdr:
            let gradient = 1.57
            return gradient * gradient
        case .dlog, .dlog2:
            return 1
        }
    }

    private static func preparedTransfer(colorModeCode: Int, iso: Int) -> MonitorTransfer {
        if (50...102_400).contains(iso) {
            ScopeExposureCeiling.setISO(iso)
        }
        return monitorTransfer(colorModeCode: colorModeCode)
    }

    private static func overlayCube(
        scale: LiveFalseColorScale,
        transfer: MonitorTransfer,
        component: ((red: Double, green: Double, blue: Double, weight: Double)) -> (
            Double, Double, Double
        )
    ) -> CubeLUT {
        let size = falseColorCubeSize
        let denom = Double(size - 1)
        let bandList = LiveColorScience.falseColorBands(scale, transfer: transfer)
        var rgb = [Float]()
        rgb.reserveCapacity(size * size * size * 3)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let er = Double(r) / denom
                    let eg = Double(g) / denom
                    let eb = Double(b) / denom
                    let yEnc = encodedLuma(red: er, green: eg, blue: eb, transfer: transfer)
                    let ire = ScopeDisplayScale.monitorPercent(yEnc, transfer: transfer)
                    let value =
                        scale == .stops
                        ? LiveColorScience.stops(encoded: yEnc, transfer: transfer) : ire
                    let chosen = component(
                        overlayPaint(
                            value: value, scale: scale, bands: bandList,
                            monitorGray: ire / 100))
                    rgb.append(Float(chosen.0))
                    rgb.append(Float(chosen.1))
                    rgb.append(Float(chosen.2))
                }
            }
        }
        return CubeLUT(size: size, rgb: rgb)
    }

    private static func encodedLuma(
        red: Double, green: Double, blue: Double, transfer: MonitorTransfer
    ) -> Double {
        let w = LiveColorScience.lumaWeights(transfer)
        return w.red * red + w.green * green + w.blue * blue
    }

    private static func overlayPaint(
        value: Double, scale: LiveFalseColorScale, bands: [LiveFalseColorBand],
        monitorGray: Double
    ) -> (red: Double, green: Double, blue: Double, weight: Double) {
        switch scale {
        case .stops, .ire:
            let color = renderedColor(
                value: value, scale: scale, bands: bands,
                source: (0, 0, 0), monitorGray: monitorGray)
            return (color.red, color.green, color.blue, 1)
        case .limits:
            break
        }
        let width = transitionWidth(scale)
        var paint = (red: 0.0, green: 0.0, blue: 0.0)
        var total = 0.0
        for item in bands {
            let weight = bandWeight(value: value, band: item, width: width)
            let color = renderedBandColor(item, scale: scale, detailGray: monitorGray)
            paint.red += color.red * weight
            paint.green += color.green * weight
            paint.blue += color.blue * weight
            total += weight
        }
        guard total > 0 else { return (0, 0, 0, 0) }
        return (paint.red / total, paint.green / total, paint.blue / total, min(1, total))
    }

    private static func renderedColor(
        value: Double,
        scale: LiveFalseColorScale,
        bands: [LiveFalseColorBand],
        source: (red: Double, green: Double, blue: Double),
        monitorGray: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let base: (red: Double, green: Double, blue: Double)
        switch scale {
        case .stops, .ire:
            let gray = min(1, max(0, monitorGray))
            base = (gray, gray, gray)
        case .limits:
            base = (
                min(1, max(0, source.red)),
                min(1, max(0, source.green)),
                min(1, max(0, source.blue))
            )
        }
        let weighted = bands.map {
            ($0, bandWeight(value: value, band: $0, width: transitionWidth(scale)))
        }
        let total = weighted.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return base }
        let normalization = max(1, total)
        let baseWeight = max(0, 1 - total)
        let painted = weighted.reduce(
            (
                red: base.red * baseWeight, green: base.green * baseWeight,
                blue: base.blue * baseWeight
            )
        ) { result, item in
            let color = renderedBandColor(item.0, scale: scale, detailGray: monitorGray)
            return (
                result.red + color.red * item.1,
                result.green + color.green * item.1,
                result.blue + color.blue * item.1
            )
        }
        return (
            painted.red / normalization,
            painted.green / normalization,
            painted.blue / normalization
        )
    }

    private static func renderedBandColor(
        _ band: LiveFalseColorBand, scale: LiveFalseColorScale, detailGray: Double
    ) -> (red: Double, green: Double, blue: Double) {
        guard scale == .stops else { return (band.red, band.green, band.blue) }
        let gray = min(1, max(0, detailGray))
        let colorWeight = 1 - stopsDetailBlend
        return (
            band.red * colorWeight + gray * stopsDetailBlend,
            band.green * colorWeight + gray * stopsDetailBlend,
            band.blue * colorWeight + gray * stopsDetailBlend
        )
    }

    private static func bandWeight(
        value: Double, band: LiveFalseColorBand, width: Double
    ) -> Double {
        let rising =
            band.lowerBound.isFinite && band.lowerBound != 0
            ? smoothStep(
                edge0: band.lowerBound - width, edge1: band.lowerBound + width, value: value)
            : 1
        let falling =
            band.upperBound.isFinite
            ? 1
                - smoothStep(
                    edge0: band.upperBound - width, edge1: band.upperBound + width, value: value)
            : 1
        return rising * falling
    }

    private static func smoothStep(edge0: Double, edge1: Double, value: Double) -> Double {
        let span = edge1 - edge0
        guard span != 0 else { return value >= edge1 ? 1 : 0 }
        let progress = min(1, max(0, (value - edge0) / span))
        return progress * progress * (3 - 2 * progress)
    }

    private static func transitionWidth(_ scale: LiveFalseColorScale) -> Double {
        switch scale {
        case .stops: 0.05
        case .ire, .limits: 0.5
        }
    }

    private static let cacheLock = NSLock()
    // Protected by cacheLock.
    nonisolated(unsafe) private static var cubeCache: [String: [UInt8]] = [:]

    private static func cacheKey(
        _ kind: String, scale: LiveFalseColorScale, transfer: MonitorTransfer
    ) -> String {
        let clip = ScopeExposureCeiling.clipByte(transfer: transfer)
        return "\(kind):\(scale.rawValue):\(transfer.rawValue):\(clip)"
    }

    private static func cached(_ key: String, build: () -> [UInt8]) -> [UInt8] {
        cacheLock.lock()
        if let hit = cubeCache[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()
        let built = build()
        cacheLock.lock()
        cubeCache[key] = built
        cacheLock.unlock()
        return built
    }
}
