import Foundation
import Metal
import Observation

#if canImport(MetalFX)
    import MetalFX
#endif
#if !targetEnvironment(simulator)
    import VideoToolbox
#endif

/// Which upscaler carries the bake→drawable blow-up. Raw values are the segment titles.
enum FeedUpscaler: String, CaseIterable, Sendable {
    /// Plain bilinear sample — the reference the rest are judged against.
    case off = "Off"
    /// MPS Lanczos. Every device can run this.
    case lanczos = "Fast"
    /// MetalFX Spatial, the FSR1-class edge-aware upscaler. A13+.
    case spatial = "Quality"
    /// VideoToolbox low-latency super-resolution. Infers detail the camera never captured.
    case superResolution = "AI"

    var isSupportedOnThisDevice: Bool {
        switch self {
        case .off, .lanczos: true
        case .spatial: Self.spatialSupported
        case .superResolution: Self.superResolutionSupported
        }
    }

    static var supportedOnThisDevice: [FeedUpscaler] { allCases.filter(\.isSupportedOnThisDevice) }

    /// `candidate` when this device can run it, otherwise the Fast floor.
    static func supported(or candidate: FeedUpscaler?) -> FeedUpscaler {
        if let candidate, candidate.isSupportedOnThisDevice { return candidate }
        return .lanczos
    }

    private static let spatialSupported: Bool = {
        #if canImport(MetalFX)
            guard let device = MTLCreateSystemDefaultDevice() else { return false }
            return MTLFXSpatialScalerDescriptor.supportsDevice(device)
        #else
            return false
        #endif
    }()

    private static let superResolutionSupported: Bool = {
        #if targetEnvironment(simulator)
            return false
        #else
            guard #available(iOS 26.0, *) else { return false }
            return VTLowLatencySuperResolutionScalerConfiguration.isSupported
        #endif
    }()

    static func superResolutionInputSize(
        source: (width: Int, height: Int),
        target: (width: Int, height: Int),
        scale: Float,
        maximum: (width: Int, height: Int)
    ) -> (width: Int, height: Int) {
        guard source.width > 0, source.height > 0, maximum.width > 0, maximum.height > 0
        else { return source }
        var shrink = min(
            Double(maximum.width) / Double(source.width),
            Double(maximum.height) / Double(source.height),
            1)
        if scale > 0 {
            let clears = max(
                Double(target.width) / (Double(source.width) * Double(scale)),
                Double(target.height) / (Double(source.height) * Double(scale)))
            if clears < 1 { shrink = min(shrink, clears) }
        }
        guard shrink < 1 else { return source }
        return (
            max(1, Int((Double(source.width) * shrink).rounded(.down))),
            max(1, Int((Double(source.height) * shrink).rounded(.down)))
        )
    }

    static func superResolutionScale(offered: [Float], ratio: Double, held: Float? = nil) -> Float?
    {
        if let held, Double(held) >= ratio { return held }
        let ordered = offered.sorted()
        return ordered.first { Double($0) >= ratio } ?? ordered.last
    }
}

/// Persisted feed-upscaler choice. The renderer reads `rendererReadsUpscaler` off the main actor.
@MainActor
@Observable
final class FeedUpscaleSwitch {
    static let shared = FeedUpscaleSwitch()

    private nonisolated static let storageKey = "OpenPocketCine.feedUpscaler"

    var upscaler: FeedUpscaler = FeedUpscaleSwitch.rendererReadsUpscaler {
        didSet {
            Self.rendererReadsUpscaler = upscaler
            UserDefaults.standard.set(upscaler.rawValue, forKey: Self.storageKey)
        }
    }

    nonisolated(unsafe) static var rendererReadsUpscaler: FeedUpscaler = .supported(
        or: storedChoice)
    nonisolated(unsafe) static var presentsSuperResolutionInput = false

    private nonisolated static var storedChoice: FeedUpscaler? {
        guard let stored = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        if let known = FeedUpscaler(rawValue: stored) { return known }
        switch stored {
        case "Lanczos": return .lanczos
        case "MetalFX": return .spatial
        case "Super Res": return .superResolution
        default: return nil
        }
    }

    private init() {}

    func toggleAgainstOff() {
        if upscaler == .off {
            upscaler = .supported(or: restoreAfterOff)
            restoreAfterOff = nil
        } else {
            restoreAfterOff = upscaler
            upscaler = .off
        }
    }

    @ObservationIgnored private var restoreAfterOff: FeedUpscaler?
}

extension SettingsHelpCopy {
    static let feedUpscaler =
        "How the live-view frame is enlarged to fill the panel. The camera sends far fewer pixels than the panel has, so something always does this. Off is a plain sample, Fast is a fixed sharpening kernel, and Quality is the OS spatial upscaler.\n\nAI is different in kind: it is a machine-learning model that INFERS detail the camera never captured. It gives the sharpest-looking picture, but the fine texture it adds is invented — plausible rather than real — so it can suggest crispness the lens did not record. Judge critical focus on Quality or Fast, and treat AI as a viewing aid rather than evidence.\n\nOnly the options this device supports are shown."
}
