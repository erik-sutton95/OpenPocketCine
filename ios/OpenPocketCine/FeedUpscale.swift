import Foundation
import Observation
import OpenCineApple
import os

/// Source-compatible name; native support and scaling math have one shared owner.

/// Persisted feed-upscaler choice. The renderer reads `rendererReadsUpscaler` off the main actor.
@MainActor
@Observable
final class FeedUpscaleSwitch {
    static let shared = FeedUpscaleSwitch()

    private nonisolated static let storageKey = "OpenPocketCine.feedUpscaler"

    var upscaler: MonitorUpscaler = FeedUpscaleSwitch.rendererReadsUpscaler {
        didSet {
            Self.rendererReadsUpscaler = upscaler
            UserDefaults.standard.set(upscaler.rawValue, forKey: Self.storageKey)
        }
    }

    private nonisolated static let rendererSelection = OSAllocatedUnfairLock(
        initialState: MonitorUpscaler.supported(or: storedChoice))
    private nonisolated static let rendererInputPreview = OSAllocatedUnfairLock(initialState: false)

    nonisolated static var rendererReadsUpscaler: MonitorUpscaler {
        get { rendererSelection.withLock { $0 } }
        set { rendererSelection.withLock { $0 = newValue } }
    }

    nonisolated static var presentsSuperResolutionInput: Bool {
        get { rendererInputPreview.withLock { $0 } }
        set { rendererInputPreview.withLock { $0 = newValue } }
    }

    private nonisolated static var storedChoice: MonitorUpscaler? {
        guard let stored = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        if let known = MonitorUpscaler(rawValue: stored) { return known }
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

    @ObservationIgnored private var restoreAfterOff: MonitorUpscaler?
}

extension SettingsHelpCopy {
    static let feedUpscaler =
        "How the live-view frame is enlarged to fill the panel. The camera sends far fewer pixels than the panel has, so something always does this. Off is a plain sample, Fast is a fixed sharpening kernel, and Quality is the OS spatial upscaler.\n\nAI is different in kind: it is a machine-learning model that INFERS detail the camera never captured. It gives the sharpest-looking picture, but the fine texture it adds is invented — plausible rather than real — so it can suggest crispness the lens did not record. Judge critical focus on Quality or Fast, and treat AI as a viewing aid rather than evidence.\n\nOnly the options this device supports are shown."
}
