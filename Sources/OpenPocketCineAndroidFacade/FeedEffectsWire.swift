import Foundation
import OpenCineMedia
import OpenCineCameraVocabulary
import OpenPocketViewCore

/// Bakes LUT-adjacent assist payloads for the Android GLES feed.
///
/// Overlay cubes and zebra codes follow iOS `PocketFalseColorMap` /
/// `LiveMonitorCompositor` so PEAK / FALSE / ZEBRA / LUT match the Metal path.
/// Compiles on Darwin so `swift test` exercises the same lattice as the APK.
public enum FeedEffectsWire {
    public static let falseColorCubeSize = 64
    public static let assistScalarCount = 4

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
        case 3: .sceneStops
        case 4...7: falseColorScale(ordinal - 4)
        default: nil
        }
    }

    /// Ordinals 4…7 are 0…3 read through the official Rec.709 look (Read: 709 / LOG).
    public static func readsRec709Look(_ ordinal: Int) -> Bool { (4...7).contains(ordinal) }

    /// Packed-2D RGBA8 overlay paint (`n³ × 4`). Sampled on encoded camera codes.
    public static func packedFalseColorPaint(
        scaleOrdinal: Int, colorModeCode: Int, iso: Int,
        sourceProfile: MonitorColorSourceProfile = DJIMonitorColorProfile.value
    ) -> [UInt8]? {
        guard let scale = falseColorScale(scaleOrdinal) else { return nil }
        let (transfer, ceiling) = prepared(colorModeCode: colorModeCode, iso: iso, sourceProfile: sourceProfile)
        let key = cacheKey(
            readsRec709Look(scaleOrdinal) ? "paint709" : "paint", scale: scale, transfer: transfer,
            ceiling: ceiling, sourceProfile: sourceProfile)
        return cached(key) {
            lattice(scale: scale, transfer: transfer, ceiling: ceiling,
                rec709: readsRec709Look(scaleOrdinal), sourceProfile: sourceProfile).packedCube(.paint)
        }
    }

    /// Packed-2D RGBA8 overlay weight. CineStop / Video / IRE are opaque; Limits is holes-only.
    public static func packedFalseColorWeight(
        scaleOrdinal: Int, colorModeCode: Int, iso: Int,
        sourceProfile: MonitorColorSourceProfile = DJIMonitorColorProfile.value
    ) -> [UInt8]? {
        guard let scale = falseColorScale(scaleOrdinal) else { return nil }
        let (transfer, ceiling) = prepared(colorModeCode: colorModeCode, iso: iso, sourceProfile: sourceProfile)
        let key = cacheKey(
            readsRec709Look(scaleOrdinal) ? "weight709" : "weight", scale: scale,
            transfer: transfer,
            ceiling: ceiling, sourceProfile: sourceProfile)
        return cached(key) {
            lattice(scale: scale, transfer: transfer, ceiling: ceiling,
                rec709: readsRec709Look(scaleOrdinal), sourceProfile: sourceProfile).packedCube(.weight)
        }
    }

    /// `[highlightNative, midtoneNative, midtoneHalfNative, peakingGateScale]`.
    public static func assistScalars(
        colorModeCode: Int, iso: Int, highlightIRE: Double, midtoneIRE: Double,
        sourceProfile: MonitorColorSourceProfile = DJIMonitorColorProfile.value
    ) -> [Float] {
        let (transfer, ceiling) = prepared(colorModeCode: colorModeCode, iso: iso, sourceProfile: sourceProfile)
        let clipByte = ceiling.clipByte(transfer: transfer, iso: iso)
        let highlight = ScopeDisplayScale.zebraHighlightNative(
            monitorPercent: highlightIRE, transfer: transfer, clipByte: clipByte)
        let half = LiveZebra.midtoneHalfWidthIRE
        let lo = ScopeDisplayScale.signalNative(
            monitorPercent: midtoneIRE - half, transfer: transfer, clipByte: clipByte)
        let hi = ScopeDisplayScale.signalNative(
            monitorPercent: midtoneIRE + half, transfer: transfer, clipByte: clipByte)
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
        case .rec709, .hdr, .srgb:
            let gradient = 1.57
            return gradient * gradient
        case .dlog, .dlog2, .dlogm, .ilog, .nlog, .log3G10:
            return 1
        }
    }

    /// Each JNI call carries its session's ISO, so the facade builds that source's ceiling
    /// per call instead of sharing one process-wide ratchet. Kotlin ratchets its own tap
    /// ceiling per feed session; the facade never observed tap maxima. An ISO outside
    /// 50…102400 leaves ISO unknown; the supplied source profile selects any reference.
    private static func prepared(
        colorModeCode: Int, iso: Int, sourceProfile: MonitorColorSourceProfile
    ) -> (transfer: MonitorTransfer, ceiling: OpenCineMedia.ScopeExposureCeiling) {
        let ceiling = OpenCineMedia.ScopeExposureCeiling(profile: sourceProfile.clip)
        ceiling.setISO(iso)
        return (monitorTransfer(colorModeCode: colorModeCode), ceiling)
    }

    private static func lattice(scale: LiveFalseColorScale, transfer: MonitorTransfer,
        ceiling: OpenCineMedia.ScopeExposureCeiling, rec709: Bool,
        sourceProfile: MonitorColorSourceProfile) -> MonitorFalseColorLattice {
        .signal(scale: scale, transfer: transfer, clipByte: ceiling.clipByte(transfer: transfer),
            rec709ClipByte: ceiling.clipByte(transfer: .rec709),
            lookCurve: sourceProfile.rec709LookCurves[transfer], readThroughLook: rec709,
            size: falseColorCubeSize)
    }

    private static let cacheLock = NSLock()
    // Protected by cacheLock.
    nonisolated(unsafe) private static var cubeCache: [String: [UInt8]] = [:]

    private static func cacheKey(
        _ kind: String, scale: LiveFalseColorScale, transfer: MonitorTransfer,
        ceiling: OpenCineMedia.ScopeExposureCeiling, sourceProfile: MonitorColorSourceProfile
    ) -> String {
        let clip = ceiling.clipByte(transfer: transfer)
        let curve = sourceProfile.rec709LookCurves[transfer]?.map { String(describing: $0) }.joined(separator: ",") ?? "signal"
        let rec709Clip = ceiling.clipByte(transfer: .rec709)
        return "\(kind):\(scale.rawValue):\(transfer.rawValue):\(clip):\(rec709Clip):\(curve)"
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
