import Foundation
import OpenPocketViewCore
import SwiftUI
import os

/// iOS look adapters on the committed core type. Cubes, zebra thresholds, and the
/// false-colour ruler call `LiveColorScience` — do not keep a second science file.

extension LiveColorScience {
    /// OpenZCine `Peaking.gateScale` — display-referred feeds read larger gradients than log.
    static func peakingGateScale(for transfer: MonitorTransfer) -> Double {
        switch transfer {
        case .rec709, .hdr:
            let gradient = 1.57
            return gradient * gradient
        case .dlog, .dlog2, .dlogm:
            return 1
        }
    }
}

// MARK: - False colour cubes (core bands → CIColorCube)

enum PocketFalseColorMap {
    /// 64³ keyed on encoded luma (not linearized Reinhard IRE). 33³ + the old
    /// tone map quantized live D-Log2 into four posters.
    static let cubeSize = 64
    static let minimumSceneStop = -6.0

    /// Value key — the old per-frame interpolated-String keys allocated on every preview tick.
    private struct CubeKey: Hashable, Sendable {
        /// `overlayPaintDisplay` = paint pre-compensated for the color-managed
        /// (no-LUT) bake, whose output DeviceRGB-encodes untagged cube results.
        enum Kind: Hashable, Sendable {
            case full, overlayPaint, overlayPaintDisplay, overlayWeight
        }
        var kind: Kind
        var scale: FalseColorScaleKind
        var transfer: MonitorTransfer
        var clipByte: Int
    }

    private struct OverlayKey: Hashable, Sendable {
        var scale: FalseColorScaleKind
        var transfer: MonitorTransfer
        var managedRender: Bool
    }

    struct OverlayMaps: Sendable {
        var dimension: Int
        var paint: Data
        var weight: Data
        var clipByte: Int
    }

    /// Both caches bound to 6 entries (an operator flips between a couple of scale/mode
    /// pairs; unbounded growth kept every visited 33³ lattice alive for the session).
    private struct Store {
        var cubes: [CubeKey: CubeLUT] = [:]
        var cubeOrder: [CubeKey] = []
        var data: [CubeKey: (Int, Data)] = [:]
        var dataOrder: [CubeKey] = []
        var warming: Set<CubeKey> = []
        var overlays: [OverlayKey: OverlayMaps] = [:]
        var overlayOrder: [OverlayKey] = []
        var requestedOverlays: [OverlayKey: Int] = [:]
        var buildingOverlays: Set<OverlayKey> = []

        static func touch(_ order: inout [CubeKey], _ key: CubeKey) {
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
                order.append(key)
            }
        }

        mutating func insertCube(_ key: CubeKey, _ cube: CubeLUT) {
            if cubes.updateValue(cube, forKey: key) == nil {
                cubeOrder.append(key)
            } else {
                Self.touch(&cubeOrder, key)
            }
            while cubeOrder.count > PocketFalseColorMap.maxCachedEntries {
                cubes[cubeOrder.removeFirst()] = nil
            }
        }

        mutating func insertData(_ key: CubeKey, _ value: (Int, Data)) {
            if data.updateValue(value, forKey: key) == nil {
                dataOrder.append(key)
            } else {
                Self.touch(&dataOrder, key)
            }
            while dataOrder.count > PocketFalseColorMap.maxCachedEntries {
                data[dataOrder.removeFirst()] = nil
            }
        }
    }

    private static let maxCachedEntries = 6
    private static let store = OSAllocatedUnfairLock(initialState: Store())
    /// `.userInitiated`: at `.utility` the 64³ lattice starved for seconds behind
    /// 4K decode on device — FALSE looked "missing" on first toggle.
    private static let warmQueue = DispatchQueue(label: "opv.false-color-warm", qos: .userInitiated)

    private static func key(
        _ kind: CubeKey.Kind, scale: FalseColorScaleKind, transfer: MonitorTransfer
    ) -> CubeKey {
        CubeKey(
            kind: kind, scale: scale, transfer: transfer,
            clipByte: ScopeExposureCeiling.clipByte(transfer: transfer))
    }

    static func cube(scale: FalseColorScaleKind, transfer: MonitorTransfer) -> CubeLUT {
        cachedCube(key(.full, scale: scale, transfer: transfer))
    }

    static func cube(scale: FalseColorScaleKind, mode: ColorMode) -> CubeLUT {
        cube(scale: scale, transfer: MonitorTransfer(mode))
    }

    /// Band paint for the compositor overlay. Sampled on **encoded camera codes**.
    static func overlayPaintCube(scale: FalseColorScaleKind, transfer: MonitorTransfer) -> CubeLUT {
        cachedCube(key(.overlayPaint, scale: scale, transfer: transfer))
    }

    static func overlayPaintCube(scale: FalseColorScaleKind, mode: ColorMode) -> CubeLUT {
        overlayPaintCube(scale: scale, transfer: MonitorTransfer(mode))
    }

    /// Coverage mask for the same overlay. 0 = show the displayed look (LUT or identity).
    static func overlayWeightCube(scale: FalseColorScaleKind, transfer: MonitorTransfer) -> CubeLUT
    {
        cachedCube(key(.overlayWeight, scale: scale, transfer: transfer))
    }

    static func overlayWeightCube(scale: FalseColorScaleKind, mode: ColorMode) -> CubeLUT {
        overlayWeightCube(scale: scale, transfer: MonitorTransfer(mode))
    }

    /// Cached `CIColorCube` bytes for the compositor. `nil` until the async warm lands —
    /// toggling FALSE used to stall the frame path several hundred ms building the lattice.
    /// `managedRender` selects the display-compensated paint for the color-managed
    /// (no-LUT Limits) bake; the unmanaged NSNull context wants the raw colors.
    static func overlayPaintData(
        scale: FalseColorScaleKind, mode: ColorMode, managedRender: Bool = false
    ) -> (Int, Data)? {
        overlayPairData(scale: scale, mode: mode, managedRender: managedRender)
            .map { ($0.dimension, $0.paint) }
    }

    /// IRE / CineStop / EL Zone full lattice: WAVE-axis grayscale with the painted zones.
    /// Not used on the live path — replacing the identity feed with this cube
    /// was the DeviceRGB contrast shift. Tests still sample it.
    static func fullPaintData(scale: FalseColorScaleKind, mode: ColorMode) -> (Int, Data)? {
        warmedData(key(.full, scale: scale, transfer: MonitorTransfer(mode)))
    }

    static func overlayWeightData(scale: FalseColorScaleKind, mode: ColorMode) -> (Int, Data)? {
        overlayPairData(scale: scale, mode: mode).map { ($0.dimension, $0.weight) }
    }

    /// Paint and mask always come from one exposure snapshot. Keep the last
    /// complete map for this look while a new exposure is warming.
    static func overlayPairData(
        scale: FalseColorScaleKind, mode: ColorMode, managedRender: Bool = false
    ) -> OverlayMaps? {
        let key = OverlayKey(
            scale: scale, transfer: MonitorTransfer(mode), managedRender: managedRender)
        let clip = ScopeExposureCeiling.clipByte(transfer: key.transfer)
        let request = store.withLock { state -> (OverlayMaps?, Bool) in
            let previous = state.overlays[key]
            if previous != nil {
                state.overlayOrder.removeAll { $0 == key }
                state.overlayOrder.append(key)
            }
            if state.buildingOverlays.contains(key) {
                state.requestedOverlays[key] = clip
                return (previous, false)
            }
            guard previous?.clipByte != clip else { return (previous, false) }
            state.requestedOverlays[key] = clip
            return (previous, state.buildingOverlays.insert(key).inserted)
        }
        if request.1 { scheduleOverlay(key) }
        return request.0
    }

    private static func scheduleOverlay(_ key: OverlayKey) {
        warmQueue.async {
            guard let clip = store.withLock({ $0.requestedOverlays.removeValue(forKey: key) })
            else {
                store.withLock { _ = $0.buildingOverlays.remove(key) }
                return
            }
            let paintKey = CubeKey(
                kind: key.managedRender ? .overlayPaintDisplay : .overlayPaint,
                scale: key.scale, transfer: key.transfer, clipByte: clip)
            let weightKey = CubeKey(
                kind: .overlayWeight, scale: key.scale,
                transfer: key.transfer, clipByte: clip)
            let paint = build(paintKey)
            let weight = build(weightKey)
            let maps = OverlayMaps(
                dimension: paint.size,
                paint: paint.rgbaComponents.withUnsafeBytes { Data($0) },
                weight: weight.rgbaComponents.withUnsafeBytes { Data($0) }, clipByte: clip)
            let again = store.withLock { state in
                let latest = state.requestedOverlays[key] ?? clip
                if latest == clip || state.overlays[key] == nil {
                    state.overlays[key] = maps
                    state.overlayOrder.removeAll { $0 == key }
                    state.overlayOrder.append(key)
                }
                while state.overlayOrder.count > 3 {
                    state.overlays[state.overlayOrder.removeFirst()] = nil
                }
                if latest != clip, state.overlays[key]?.clipByte != latest { return true }
                state.requestedOverlays[key] = nil
                state.buildingOverlays.remove(key)
                return false
            }
            // One queued request per look; intermediate ISO updates are replaced.
            if again { scheduleOverlay(key) }
        }
    }

    /// Kick the 64³ overlay build before the first FALSE frame. Every scale
    /// paints holes-only over the identity / LUT look — do not warm the full
    /// replace lattice (that remake was the contrast shift).
    static func warm(scale: FalseColorScaleKind, mode: ColorMode, hasLUT _: Bool = false) {
        _ = overlayPaintData(scale: scale, mode: mode)
        _ = overlayWeightData(scale: scale, mode: mode)
    }

    static func limitsPaintCube(transfer: MonitorTransfer) -> CubeLUT {
        overlayPaintCube(scale: .limits, transfer: transfer)
    }

    static func limitsPaintCube(mode: ColorMode) -> CubeLUT {
        overlayPaintCube(scale: .limits, mode: mode)
    }

    static func limitsWeightCube(transfer: MonitorTransfer) -> CubeLUT {
        overlayWeightCube(scale: .limits, transfer: transfer)
    }

    static func limitsWeightCube(mode: ColorMode) -> CubeLUT {
        overlayWeightCube(scale: .limits, mode: mode)
    }

    static func bands(scale: FalseColorScaleKind, transfer: MonitorTransfer) -> [LiveFalseColorBand]
    {
        LiveColorScience.falseColorBands(scale.liveScale, transfer: transfer)
    }

    static func bands(scale: FalseColorScaleKind, mode: ColorMode) -> [LiveFalseColorBand] {
        bands(scale: scale, transfer: MonitorTransfer(mode))
    }

    static func maximumSceneStop(transfer: MonitorTransfer) -> Double {
        let ev = LiveColorScience.stops(
            encoded: ScopeExposureCeiling.clipEncoded(transfer: transfer),
            transfer: transfer)
        guard ev.isFinite else { return 6 }
        return max(3, ev)
    }

    static func maximumSceneStop(mode: ColorMode) -> Double {
        maximumSceneStop(transfer: MonitorTransfer(mode))
    }

    private static func cachedCube(_ key: CubeKey) -> CubeLUT {
        let hit = store.withLock { state -> CubeLUT? in
            guard let cube = state.cubes[key] else { return nil }
            Store.touch(&state.cubeOrder, key)
            return cube
        }
        if let hit { return hit }
        // Built outside the lock — a racing duplicate build is harmless and rare.
        let cube = build(key)
        store.withLock { $0.insertCube(key, cube) }
        return cube
    }

    /// Frame-path lookup: hit or `nil` plus a one-shot utility-queue warm per key.
    private static func warmedData(_ key: CubeKey) -> (Int, Data)? {
        let hit = store.withLock { state -> (Int, Data)? in
            guard let value = state.data[key] else { return nil }
            Store.touch(&state.dataOrder, key)
            return value
        }
        if let hit { return hit }
        let shouldWarm = store.withLock { $0.warming.insert(key).inserted }
        if shouldWarm {
            warmQueue.async {
                let cube = cachedCube(key)
                let data = cube.rgbaComponents.withUnsafeBytes { Data($0) }
                store.withLock { state in
                    state.insertData(key, (cube.size, data))
                    state.warming.remove(key)
                }
            }
        }
        return nil
    }

    private static func build(_ key: CubeKey) -> CubeLUT {
        switch key.kind {
        case .full:
            buildCube(scale: key.scale, transfer: key.transfer, clipByte: key.clipByte)
        case .overlayPaint:
            overlayCube(scale: key.scale, transfer: key.transfer, clipByte: key.clipByte) {
                ($0.red, $0.green, $0.blue)
            }
        case .overlayPaintDisplay:
            // The managed bake output-converts linear working space → DeviceRGB
            // (≈ sRGB encode; the measured "untagged cube result gets lifted"
            // from `LiveMonitorWorkingSpace`). Store decode(target) so the encode
            // lands the band on its authored color.
            overlayCube(scale: key.scale, transfer: key.transfer, clipByte: key.clipByte) {
                (srgbDecode($0.red), srgbDecode($0.green), srgbDecode($0.blue))
            }
        case .overlayWeight:
            // Mask values are consumed in working space, never output-converted.
            overlayCube(scale: key.scale, transfer: key.transfer, clipByte: key.clipByte) {
                ($0.weight, $0.weight, $0.weight)
            }
        }
    }

    /// sRGB EOTF (decode). Inverse of the managed bake's output encode.
    private static func srgbDecode(_ value: Double) -> Double {
        let v = min(1, max(0, value))
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func buildCube(
        scale: FalseColorScaleKind, transfer: MonitorTransfer, clipByte: Int
    ) -> CubeLUT {
        let size = cubeSize
        let denom = Double(size - 1)
        // Hoisted: `falseColorBands` per lattice point rebuilt the band table
        // 64³ times — the seconds-long warm behind FALSE "missing" on device.
        let anchors = ScopeAnchors.make(transfer: transfer, clipByte: clipByte)
        let bandList = LiveColorScience.falseColorBands(
            scale.liveScale, transfer: transfer, clipEncoded: anchors.clip)
        var rgb = [Float]()
        rgb.reserveCapacity(size * size * size * 3)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let er = Double(r) / denom
                    let eg = Double(g) / denom
                    let eb = Double(b) / denom
                    let yEnc = encodedLuma(red: er, green: eg, blue: eb, transfer: transfer)
                    let level = ScopeDisplayScale.waveformLevel(yEnc, anchors: anchors)
                    let ire = min(
                        100,
                        max(
                            0,
                            (level - ScopeDisplayScale.crushLevel)
                                / (ScopeDisplayScale.clipLevel - ScopeDisplayScale.crushLevel) * 100
                        ))
                    let value =
                        scale.liveScale.usesSceneStops
                        ? LiveColorScience.stops(encoded: yEnc, transfer: transfer) : ire
                    let color = renderedColor(
                        value: value, scale: scale, bands: bandList,
                        source: (er, eg, eb),
                        monitorGray: ire / 100)
                    rgb.append(Float(color.red))
                    rgb.append(Float(color.green))
                    rgb.append(Float(color.blue))
                }
            }
        }
        return CubeLUT(size: size, rgb: rgb)
    }

    private static func overlayCube(
        scale: FalseColorScaleKind,
        transfer: MonitorTransfer,
        clipByte: Int,
        component: ((red: Double, green: Double, blue: Double, weight: Double)) -> (
            Double, Double, Double
        )
    ) -> CubeLUT {
        let size = cubeSize
        let denom = Double(size - 1)
        // Hoisted out of the 64³ walk — see `buildCube`.
        let anchors = ScopeAnchors.make(transfer: transfer, clipByte: clipByte)
        let bandList = LiveColorScience.falseColorBands(
            scale.liveScale, transfer: transfer, clipEncoded: anchors.clip)
        var rgb = [Float]()
        rgb.reserveCapacity(size * size * size * 3)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let er = Double(r) / denom
                    let eg = Double(g) / denom
                    let eb = Double(b) / denom
                    let yEnc = encodedLuma(red: er, green: eg, blue: eb, transfer: transfer)
                    let level = ScopeDisplayScale.waveformLevel(yEnc, anchors: anchors)
                    let ire = min(
                        100,
                        max(
                            0,
                            (level - ScopeDisplayScale.crushLevel)
                                / (ScopeDisplayScale.clipLevel - ScopeDisplayScale.crushLevel) * 100
                        ))
                    let value =
                        scale.liveScale.usesSceneStops
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

    /// Encoded-domain luma — same axis WAVE / ZEBRA use. Do not linearize.
    private static func encodedLuma(
        red: Double, green: Double, blue: Double, transfer: MonitorTransfer
    ) -> Double {
        let w = LiveColorScience.lumaWeights(transfer)
        return w.red * red + w.green * green + w.blue * blue
    }

    /// Band colour + coverage. Limits: weight 0 leaves the picture. IRE / CineStop /
    /// EL Zone always paint — gaps are WAVE grayscale, not a hole onto the camera image.
    private static func overlayPaint(
        value: Double, scale: FalseColorScaleKind, bands: [LiveFalseColorBand], monitorGray: Double
    ) -> (red: Double, green: Double, blue: Double, weight: Double) {
        switch scale {
        case .stops, .ire, .elZone:
            let color = renderedColor(
                value: value, scale: scale, bands: bands,
                source: (0, 0, 0), monitorGray: monitorGray)
            return (color.red, color.green, color.blue, 1)
        case .limits:
            break
        }
        let width = scale.transitionWidth
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
        scale: FalseColorScaleKind,
        bands: [LiveFalseColorBand],
        source: (red: Double, green: Double, blue: Double),
        monitorGray: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let base: (red: Double, green: Double, blue: Double)
        switch scale {
        case .stops, .ire, .elZone:
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
            ($0, bandWeight(value: value, band: $0, width: scale.transitionWidth))
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
        _ band: LiveFalseColorBand, scale: FalseColorScaleKind, detailGray: Double
    ) -> (red: Double, green: Double, blue: Double) {
        _ = detailGray
        return (band.red, band.green, band.blue)
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
}

extension FalseColorScaleKind {
    var liveScale: LiveFalseColorScale {
        switch self {
        case .stops: .stops
        case .ire: .ire
        case .limits: .limits
        case .elZone: .elZone
        }
    }

    var transitionWidth: Double {
        switch self {
        case .elZone: 0.05
        case .stops, .ire, .limits: 0.5
        }
    }

    /// OpenZCine `FalseColorReference.scaleLabel`.
    var referenceScaleLabel: String {
        switch self {
        case .stops: "CineStop"
        case .ire: "IRE"
        case .limits: "Limits"
        case .elZone: "EL Zone"
        }
    }

    /// OpenZCine `FalseColorScale.legendStops` — painted zones in operator order.
    /// Labels come from ``FalseColorAssist/legendLabels(scale:)`` so WAVE-axis
    /// copy can differ from ``LiveColorScience`` without rewriting the mapper.
    func legendStops(transfer: MonitorTransfer) -> [LiveFalseColorBand] {
        zip(
            PocketFalseColorMap.bands(scale: self, transfer: transfer),
            FalseColorAssist.legendLabels(scale: self)
        ).map { band, label in
            LiveFalseColorBand(
                lowerBound: band.lowerBound,
                upperBound: band.upperBound,
                red: band.red,
                green: band.green,
                blue: band.blue,
                label: label
            )
        }
    }
}

/// OpenZCine `FalseColorReference` chrome — 264×52 glass ruler with sparse zone chips.
struct FalseColorReferenceChrome: View {
    var scale: FalseColorScaleKind
    var colorMode: ColorMode = .normal

    static let panelSize = FalseColorReference.panelSize

    var body: some View {
        FalseColorAssist.referenceDisplay(scale: scale, colorMode: colorMode)
    }
}
