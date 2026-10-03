import CoreImage
import Metal
import OpenCineApple
import OpenCineMedia
import OpenPocketViewCore
import UIKit

/// Local GPU monitor tools. Peaking, false colour, and zebra measure **source
/// camera codes**: the same pre-LUT buffer WAVE / HISTO tap. Never the active LUT.
/// False colour Limits uses `ScopeDisplayScale.monitorPercent` for the active
/// `ColorMode`, as do Video / IRE; CineStop reads scene stops. LUT and de-squeeze are display-only CI ops. Mirror is a view-space
/// flip (`MirrorAssist.feedScale`) so it never lands in this graph.
struct LiveImageEffects: Equatable, Sendable {
    var peaking = false
    var zebra = false
    var falseColor = false
    var histogram = false
    var waveform = false
    var parade = false
    var vectorscope = false
    var trafficLights = false
    var ndMeter = false
    var lutDimension = 0
    var lutRGBA = Data()

    var peakingColor: PeakingPaint = .red
    var peakingSensitivity: PeakingSense = .medium
    var falseColorScale: FalseColorScaleKind = .sceneStops
    /// Read: 709 (official Rec.709 look) or LOG (signal). Part of the effects so a
    /// change re-renders and rebakes the overlay.
    var falseColorRec709 = false
    var zebraHighlight = true
    var zebraMidtone = true
    var zebraHighlightIRE: Double = LiveZebra.highlightIRE
    var zebraMidtoneIRE: Double = LiveZebra.midtoneIRE
    var zebraHighlightColor: ZebraPaint = .white
    var zebraMidtoneColor: ZebraPaint = .amber
    /// Sibling / session stamps the camera color mode so D-Log2 IRE does not treat mid-grey as clip.
    var colorMode: ColorMode = .normal
    /// Live-tap clip byte of this source for `colorMode`'s curve, stamped next to it from the
    /// source's own ``ScopeExposureCeiling`` (never a process-wide one). Zebra and FALSE key it.
    /// `nil` until a source stamps it: the curve's reference ceiling (EI 1600, no ratchet).
    var clipByte: Int?
    /// Photo has an authoritative Rec.709 source; scene brightness cannot identify log.
    var allowsTransferInference = true
    var splitComparison = false
    var splitVertical = true
    /// Left-to-right monitor flip. Applied in `VideoView`, not this compositor.
    var mirror = false
    /// Top-to-bottom monitor flip (MIRROR Vertical). Same view-space path as `mirror`.
    var mirrorVertical = false
    /// Anamorphic display stretch. `1` is off. Anamorphic adapters squeeze the source;
    /// this preview-only correction never changes recordings or scope samples.
    var desqueezeFactor: Double = 1
    var desqueezeHorizontal = true
    /// Traffic-light pixel-fraction threshold (operator compensation, stops / 10).
    var trafficThreshold: Double = ScopeTrafficLights.defaultThreshold
    /// AF-C face box. Starts VT so Vision can see a `CVPixelBuffer`.
    var faceAF = false
    /// An open inspector requests the existing decoded-source tap. It never
    /// enables a main-picture effect or an additional decoder/display sink.
    var inspectorSample = false

    /// Peaking / false colour / zebra / LUT / display transforms — painted on the video frame.
    var needsGPUFeed: Bool {
        peaking || zebra || falseColor
            || lutDimension >= 2 || desqueezeFactor > 1.001
    }

    /// LUT / de-squeeze remake every pixel. Zebra, peaking, and false colour
    /// only paint — the identity HEVC / VT layer stays so contrast does not
    /// shift. A DeviceRGB bake of the Rec.709 picture is a visible
    /// Rec.709→sRGB re-encode. 50/50 is a LUT option, not its own replace
    /// path — split without a cube covered HEVC with an empty Metal plate.
    var replacesIdentityFeed: Bool {
        lutDimension >= 2
            || desqueezeFactor > 1.001
    }

    /// GPU 50/50 log-vs-LUT. Same gate as Android `FeedEffectsRenderPlan`.
    var appliesSplitComparison: Bool {
        FeedPresentPolicy.appliesSplitComparison(
            enabled: splitComparison,
            hasLUTCube: lutDimension >= 2 && !lutRGBA.isEmpty,
            falseColorPaintsFullFrame: falseColor && falseColorScale != .limits)
    }

    /// Transparent stripe / peaking overlay on top of the identity layer.
    var needsOverlayFeed: Bool {
        needsGPUFeed && !replacesIdentityFeed
    }

    /// Clip byte zebra and FALSE use for `colorMode`.
    var resolvedClipByte: Int {
        clipByte
            ?? OpenCineDJI.ScopeExposureCeiling.referenceClipByte(
                transfer: MonitorTransfer(colorMode))
    }

    /// Stamp the source's curve and its live ceiling together.
    mutating func stamp(transfer: MonitorTransfer, ceiling: OpenCineDJI.ScopeExposureCeiling) {
        colorMode = transfer.colorMode
        clipByte = ceiling.clipByte(transfer: MonitorTransfer(colorMode))
    }

    mutating func stamp(transfer: MonitorTransfer, ceiling: OpenCineMedia.ScopeExposureCeiling) {
        colorMode = transfer.colorMode
        clipByte = ceiling.clipByte(transfer: transfer)
    }

    /// WAVE / PARADE / HISTO / VECTOR / LIGHTS / ND share the source tap.
    var needsScopes: Bool {
        histogram || waveform || parade || vectorscope || trafficLights || ndMeter
    }

    var needsScopePoints: Bool {
        waveform || parade || vectorscope
    }

    var activeScopeCount: Int {
        [histogram, waveform, parade, vectorscope, trafficLights, ndMeter].filter { $0 }
            .count
    }

    /// GPU feed, CPU scopes, or AF-C face detect. Any one starts VT for a pixel buffer.
    var needsSample: Bool {
        needsGPUFeed || needsScopes || faceAF || inspectorSample
    }

    var needsProcessedFeed: Bool { needsSample }

    func withFaceAF(_ on: Bool) -> LiveImageEffects {
        var fx = self
        fx.faceAF = on
        return fx
    }
}

/// OpenZCine `Peaking.Color` — paint table lives on ``PeakingAssist/Color``.
typealias PeakingPaint = PeakingAssist.Color
/// OpenZCine `Peaking.Sensitivity` — detector steps live on ``PeakingAssist/Sensitivity``.
typealias PeakingSense = PeakingAssist.Sensitivity

/// Raw values are the persisted keys. `stops` is the scale now labeled Video;
/// its key stays "CineStop" so saved settings keep the scale they chose.
enum FalseColorScaleKind: String, CaseIterable, Codable, Sendable {
    case sceneStops = "SceneStops"
    case stops = "CineStop"
    case ire = "IRE"
    case limits = "Limits"
}

enum ZebraPaint: String, CaseIterable, Codable, Sendable {
    case white = "White"
    case amber = "Amber"
    case red = "Red"
    case cyan = "Cyan"
    case green = "Green"

    /// OpenZCine `ImageEffectsCompositor.zebraRGB`.
    var rgb: (Double, Double, Double) {
        switch self {
        case .white: (1, 1, 1)
        case .amber: (1, 0.72, 0.2)
        case .red: (1, 0.15, 0.15)
        case .cyan: (0, 0.85, 0.9)
        case .green: (0.2, 0.9, 0.35)
        }
    }
}

typealias LiveMonitorWorkingSpace = OpenCineApple.MonitorWorkingSpace

enum LiveMonitorCompositor {
    static var fusedPeakingAvailable: Bool {
        OpenCineApple.MonitorImageCompositor.fusedPeakingAvailable
    }
    static var fusedPeakingNote: String { OpenCineApple.MonitorImageCompositor.fusedPeakingNote }
    static func apply(to source: CIImage, effects: LiveImageEffects, display: CIImage? = nil)
        -> CIImage
    {
        OpenCineApple.MonitorImageCompositor.apply(
            to: source, effects: effects.nativeImageEffects, display: display)
    }
    static func applyProduct(to source: CIImage, effects: LiveImageEffects, display: CIImage? = nil)
        -> (image: CIImage, unmanagedBake: Bool)
    {
        OpenCineApple.MonitorImageCompositor.applyProduct(
            to: source, effects: effects.nativeImageEffects, display: display)
    }
    static func assistOverlay(from source: CIImage, effects: LiveImageEffects) -> CIImage {
        OpenCineApple.MonitorImageCompositor.assistOverlay(
            from: source, effects: effects.nativeImageEffects)
    }
    static func place(_ overlay: CIImage, over base: CIImage) -> CIImage {
        OpenCineApple.MonitorImageCompositor.place(overlay, over: base)
    }
}

extension LiveImageEffects {
    var nativeImageEffects: OpenCineApple.MonitorImageEffects {
        var result = nativeImagePlan
        if falseColor,
            let maps = PocketFalseColorMap.overlayPairData(
                scale: falseColorScale, mode: colorMode, rec709: falseColorRec709,
                clipByte: resolvedClipByte)
        {
            result.falseColorMaps = OpenCineApple.MonitorOverlayMaps(
                dimension: maps.dimension, paint: maps.paint, weight: maps.weight)
        }
        return result
    }
    var nativeImagePlan: OpenCineApple.MonitorImageEffects {
        let transfer = MonitorTransfer(colorMode)
        var result = OpenCineApple.MonitorImageEffects()
        result.peaking = peaking
        result.zebra = zebra
        result.falseColor = falseColor
        result.lutDimension = lutDimension
        result.lutRGBA = lutRGBA
        result.peakingColor = OpenCineApple.MonitorRGB(peakingColor.rgb)
        result.peakingSensitivity = OpenCineApple.MonitorPeakingSensitivity(
            ratioThreshold: peakingSensitivity.ratioThreshold,
            noiseGate: peakingSensitivity.noiseGate)
        result.peakingGateScale = LiveColorScience.peakingGateScale(for: transfer)
        result.transfer = transfer
        result.clipByte = resolvedClipByte
        result.zebraSpec = OpenCineApple.MonitorZebraSpec(
            highlightEnabled: zebraHighlight, highlightIRE: zebraHighlightIRE,
            highlightColor: OpenCineApple.MonitorRGB(zebraHighlightColor.rgb),
            midtoneEnabled: zebraMidtone, midtoneIRE: zebraMidtoneIRE,
            midtoneColor: OpenCineApple.MonitorRGB(zebraMidtoneColor.rgb))
        result.falseColorPaintsFullFrame = falseColor && falseColorScale != .limits
        result.splitComparison = splitComparison
        result.splitVertical = splitVertical
        result.desqueezeFactor = desqueezeFactor
        result.desqueezeHorizontal = desqueezeHorizontal
        return result
    }
}

/// Compatibility name; the actual bake and retained texture pool are native-owned.
typealias FeedFrameBaker = OpenCineApple.MonitorFrameBaker

typealias FeedPresentationMetrics = OpenCineApple.MonitorPresentationMetrics
typealias FeedPresentOperations = OpenCineApple.MonitorPresentOperations

/// The app supplies operator choices; the stable native host owns rendering and presentation.
final class CIFeedView: OpenCineApple.MonitorPictureHost {
    init(frame: CGRect = .zero) {
        super.init(
            frame: frame,
            options: { screen in
                LiveHDRDisplay.refreshGain(screen: screen)
                return OpenCineApple.MonitorPresentationOptions(
                    upscaler: FeedUpscaleSwitch.rendererReadsUpscaler,
                    hdr: LiveHDRDisplay.isEnabled, hdrGain: LiveHDRDisplay.presentGain,
                    previewSuperResolutionInput: FeedUpscaleSwitch.presentsSuperResolutionInput)
            }, logSubsystem: "com.opencapture.openpocketcine")
        #if DEBUG
            onSuccessfulPresent = { FeedStressAutomation.notePresent() }
        #endif
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension LiveImageEffects {
    var nativeAssistPolicy: OpenCineApple.MonitorAssistPolicy {
        var result = OpenCineApple.MonitorAssistPolicy()
        result.image = nativeImagePlan
        result.histogram = histogram
        result.waveform = waveform
        result.parade = parade
        result.vectorscope = vectorscope
        result.trafficLights = trafficLights
        result.ndMeter = ndMeter
        result.trafficThreshold = trafficThreshold
        result.allowsTransferInference = allowsTransferInference
        switch falseColorScale {
        case .sceneStops: result.falseColorScale = .sceneStops
        case .stops: result.falseColorScale = .stops
        case .ire: result.falseColorScale = .ire
        case .limits: result.falseColorScale = .limits
        }
        result.falseColorRec709 = falseColorRec709
        return result
    }
}
