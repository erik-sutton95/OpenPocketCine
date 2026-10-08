import Foundation
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenPocketViewCore
import SwiftUI
import os
import OpenCineApple
import OpenCineMedia

/// iOS look adapters on the committed core type. Cubes, zebra thresholds, and the
/// false-colour ruler call `LiveColorScience` — do not keep a second science file.

extension LiveColorScience {
    /// OpenZCine `Peaking.gateScale` — display-referred feeds read larger gradients than log.
    static func peakingGateScale(for transfer: MonitorTransfer) -> Double {
        switch transfer {
        case .rec709, .hdr, .srgb:
            let gradient = 1.57
            return gradient * gradient
        case .dlog, .dlog2, .dlogm, .ilog, .nlog, .log3G10:
            return 1
        }
    }
}

// MARK: - False colour cubes (core bands → CIColorCube)

enum PocketFalseColorMap {
    /// 64³ keyed on encoded luma (not linearized Reinhard IRE). 33³ + the old
    /// tone map quantized live D-Log2 into four posters.
    static let cubeSize = 64

    /// Value key — the old per-frame interpolated-String keys allocated on every preview tick.
    private struct CubeKey: Hashable, Sendable {
        /// `overlayPaintDisplay` = paint pre-compensated for the color-managed
        /// (no-LUT) bake, whose output DeviceRGB-encodes untagged cube results.
        enum Kind: Hashable, Sendable {
            case full, overlayPaint, overlayPaintDisplay, overlayWeight
        }
        var kind: Kind
        var scale: MonitorFalseColorSelection
        var transfer: MonitorTransfer
        var clipByte: Int
        /// Read through the official Rec.709 look (`MonitorFrameEffects.falseColorRec709`).
        var rec709: Bool
    }

    // ponytail: keyed by look, not by source; the latest clip a source requests wins.
    // Only the one monitored source paints FALSE today. Key by clip too if two ever do.
    private struct OverlayKey: Hashable, Sendable {
        var scale: MonitorFalseColorSelection
        var transfer: MonitorTransfer
        var managedRender: Bool
        /// Read: 709 / LOG. Without it a toggle returned the cached overlay forever.
        var rec709: Bool
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

    /// Every look input is explicit: the source's Read (709 / LOG) and its live ceiling for
    /// `transfer` (``ScopeExposureCeiling/clipByte(transfer:iso:)`` of that source).
    private static func key(
        _ kind: CubeKey.Kind, scale: MonitorFalseColorSelection, transfer: MonitorTransfer,
        rec709: Bool, clipByte: Int
    ) -> CubeKey {
        CubeKey(kind: kind, scale: scale, transfer: transfer, clipByte: clipByte, rec709: rec709)
    }

    static func cube(
        scale: MonitorFalseColorSelection, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> CubeLUT {
        cachedCube(key(.full, scale: scale, transfer: transfer, rec709: rec709, clipByte: clipByte))
    }

    /// Band paint for the compositor overlay. Sampled on **encoded camera codes**.
    static func overlayPaintCube(
        scale: MonitorFalseColorSelection, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> CubeLUT {
        cachedCube(
            key(.overlayPaint, scale: scale, transfer: transfer, rec709: rec709, clipByte: clipByte)
        )
    }

    /// Coverage mask for the same overlay. 0 = show the displayed look (LUT or identity).
    static func overlayWeightCube(
        scale: MonitorFalseColorSelection, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> CubeLUT {
        cachedCube(
            key(
                .overlayWeight, scale: scale, transfer: transfer, rec709: rec709, clipByte: clipByte
            ))
    }

    /// Cached `CIColorCube` bytes for the compositor. `nil` until the async warm lands:
    /// toggling FALSE used to stall the frame path several hundred ms building the lattice.
    /// `managedRender` selects the display-compensated paint for the color-managed
    /// (no-LUT Limits) bake; the unmanaged NSNull context wants the raw colors.
    static func overlayPaintData(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int,
        managedRender: Bool = false
    ) -> (Int, Data)? {
        overlayPairData(
            scale: scale, mode: mode, rec709: rec709, clipByte: clipByte,
            managedRender: managedRender
        ).map { ($0.dimension, $0.paint) }
    }

    /// CineStop / Video / IRE full lattice: grayscale base with the painted zones.
    /// Not used on the live path: replacing the identity feed with this cube
    /// was the DeviceRGB contrast shift. Tests still sample it.
    static func fullPaintData(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int
    ) -> (Int, Data)? {
        warmedData(
            key(
                .full, scale: scale, transfer: MonitorTransfer(mode), rec709: rec709,
                clipByte: clipByte))
    }

    static func overlayWeightData(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int
    ) -> (Int, Data)? {
        overlayPairData(scale: scale, mode: mode, rec709: rec709, clipByte: clipByte)
            .map { ($0.dimension, $0.weight) }
    }

    /// Paint and mask always come from one exposure snapshot. Keep the last
    /// complete map for this look while a new exposure is warming.
    static func overlayPairData(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int,
        managedRender: Bool = false
    ) -> OverlayMaps? {
        let key = OverlayKey(
            scale: scale, transfer: MonitorTransfer(mode), managedRender: managedRender,
            rec709: rec709)
        let clip = clipByte
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
                scale: key.scale, transfer: key.transfer, clipByte: clip,
                rec709: key.rec709)
            let weightKey = CubeKey(
                kind: .overlayWeight, scale: key.scale,
                transfer: key.transfer, clipByte: clip, rec709: key.rec709)
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
    /// `clipByte` is the source's ceiling. A caller without a source (an operator toggle)
    /// passes `nil`: that rewarms the look at the clip it last showed, or leaves the first
    /// build to the source's own engine so it never warms a different source's ceiling.
    static func warm(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int?,
        hasLUT _: Bool = false
    ) {
        let look = OverlayKey(
            scale: scale, transfer: MonitorTransfer(mode), managedRender: false, rec709: rec709)
        guard
            let clip = clipByte
                ?? store.withLock({ $0.requestedOverlays[look] ?? $0.overlays[look]?.clipByte })
        else { return }
        _ = overlayPairData(scale: scale, mode: mode, rec709: rec709, clipByte: clip)
    }

    static func bands(
        scale: MonitorFalseColorSelection, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> [LiveFalseColorBand] {
        let clip = DJILook.falseColorClip(
            scale: scale.liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
        return LiveColorScience.falseColorBands(
            scale.liveScale, transfer: clip.transfer, clipEncoded: clip.ceiling)
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
        let lattice = MonitorFalseColorLattice.signal(scale: key.scale.liveScale,
            transfer: key.transfer, clipByte: key.clipByte,
            rec709ClipByte: DJIScopeExposureCeiling.referenceClipByte(transfer: .rec709),
            lookCurve: DJIMonitorColorProfile.value.rec709LookCurves[key.transfer],
            readThroughLook: key.rec709, size: cubeSize)
        switch key.kind {
        case .full:
            return lattice.cube(.composite)
        case .overlayPaint:
            return lattice.cube(.paint)
        case .overlayPaintDisplay:
            return lattice.cube(.paint, paintEncoding: .linearSRGB)
        case .overlayWeight:
            return lattice.cube(.weight)
        }
    }
}

extension MonitorFalseColorSelection {
    var transitionWidth: Double { liveScale.edgeSoftness }

    /// OpenZCine `FalseColorScale.legendStops` — painted zones in operator order.
    /// Labels come from ``FalseColorAssist/legendLabels(scale:)`` so WAVE-axis
    /// copy can differ from ``LiveColorScience`` without rewriting the mapper.
    func legendStops(transfer: MonitorTransfer, rec709: Bool, clipByte: Int) -> [LiveFalseColorBand]
    {
        let bands = PocketFalseColorMap.bands(
            scale: self, transfer: transfer, rec709: rec709, clipByte: clipByte)
        // CineStop labels come from core: the clip band moves with the camera.
        guard !liveScale.usesSceneStops else { return bands }
        return zip(
            bands,
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
    var scale: MonitorFalseColorSelection
    var colorMode: ColorMode = .normal
    var rec709: Bool
    var clipByte: Int

    static let panelSize = FalseColorReference.panelSize

    var body: some View {
        FalseColorAssist.referenceDisplay(
            scale: scale, colorMode: colorMode, rec709: rec709, clipByte: clipByte,
            looks: .app)
    }
}
