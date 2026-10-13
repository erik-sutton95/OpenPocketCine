import Foundation
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenPocketViewCore
import SwiftUI
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

// MARK: - False colour cubes (the shared mapper)

/// Pocket's false colour cubes come from the shared mapper on DJI's official Rec.709 looks, the
/// same science and cache the inspector preview and the Android facade use (A1-48).
enum PocketFalseColorMap {
    typealias OverlayMaps = MonitorFalseColorMapper.OverlayMaps
    // ponytail: one process-wide cache, as before; Pocket monitors one source at a time.
    private static let native = MonitorFalseColorMapper(
        lookCurves: DJIMonitorColorProfile.value.rec709LookCurves)

    static func cube(
        scale: MonitorFalseColorSelection, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> CubeLUT {
        native.cube(scale: scale.liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
    }

    /// Band paint for the compositor overlay. Sampled on **encoded camera codes**.
    static func overlayPaintCube(
        scale: MonitorFalseColorSelection, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> CubeLUT {
        native.overlayPaintCube(
            scale: scale.liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
    }

    /// Coverage mask for the same overlay. 0 = show the displayed look (LUT or identity).
    static func overlayWeightCube(
        scale: MonitorFalseColorSelection, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> CubeLUT {
        native.overlayWeightCube(
            scale: scale.liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
    }

    /// Cached `CIColorCube` bytes for the compositor, `nil` until the async warm lands.
    static func overlayPaintData(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int,
        managedRender: Bool = false
    ) -> (Int, Data)? {
        native.overlayPaintData(
            scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte, managedRender: managedRender)
    }

    /// The full lattice (grayscale base with the painted zones). Tests sample it.
    static func fullPaintData(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int
    ) -> (Int, Data)? {
        native.fullPaintData(
            scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte)
    }

    static func overlayWeightData(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int
    ) -> (Int, Data)? {
        native.overlayWeightData(
            scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte)
    }

    /// Paint and mask from one exposure snapshot; the last complete map stays while a new
    /// exposure warms.
    static func overlayPairData(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int,
        managedRender: Bool = false
    ) -> OverlayMaps? {
        native.overlayPairData(
            scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte, managedRender: managedRender)
    }

    /// Kicks the overlay build before the first FALSE frame. `clipByte` nil rewarms the look at
    /// the clip it last showed (an operator toggle has no source).
    static func warm(
        scale: MonitorFalseColorSelection, mode: ColorMode, rec709: Bool, clipByte: Int?,
        hasLUT: Bool = false
    ) {
        native.warm(
            scale: scale.liveScale, transfer: MonitorTransfer(mode), rec709: rec709,
            clipByte: clipByte, hasLUT: hasLUT)
    }

    static func bands(
        scale: MonitorFalseColorSelection, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> [LiveFalseColorBand] {
        native.bands(scale: scale.liveScale, transfer: transfer, rec709: rec709, clipByte: clipByte)
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
