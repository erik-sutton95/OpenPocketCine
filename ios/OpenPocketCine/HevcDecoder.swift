import Foundation
import MonitorPresentation
import OpenCineApple
import OpenCineCameraControls
import OpenCineMedia
import OpenPocketViewCore

/// Camera interpretation and host values for the shared native decoder.
@MainActor
final class HevcDecoder: OpenCineApple.MonitorLiveVideoDecoder {
    var incomingColorMode: ColorMode? {
        didSet {
            if let incomingColorMode { incomingTransfer = MonitorTransfer(incomingColorMode) }
        }
    }

    init() {
        super.init(
            configuration: .init(
                assists: LiveAssistEngine.configuration,
                shouldRebuildSession: { CameraSoftAP.shouldRebuildVTSession(status: $0) },
                decodeEvent: { event in
                    #if DEBUG
                        switch event {
                        case .submitted: FeedStressAutomation.noteDecodeSubmit()
                        case .decoded: FeedStressAutomation.noteDecoded()
                        case .presented: FeedStressAutomation.notePresent()
                        }
                    #endif
                },
                discardOutput: {
                    #if DEBUG
                        return FeedStressAutomation.shouldSilenceOutput()
                    #else
                        return false
                    #endif
                }), simulator: SimulatorLiveFeed.configuration)
        effects = .init()
        feedUpscaler = FeedUpscaleSwitch.shared.upscaler
        onSourceAdvanced = {
            NotificationCenter.default.post(name: .monitorBackdropSourceAdvanced, object: nil)
        }
    }
}

/// The app keeps its existing operator-selected footage namespace and source interpretation.
enum SimulatorLiveFeed {
    #if DEBUG && targetEnvironment(simulator)
        static var referenceReviewClipURL: URL? {
            guard let review = ReviewLaunch.current,
                review.screen == .live, review.state == "reference-split"
            else { return nil }
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("ReferenceSplitLive.mov")
        }
    #endif

    static var clipURL: URL? {
        #if DEBUG && targetEnvironment(simulator)
            if let fixture = referenceReviewClipURL { return fixture }
        #endif
        let env = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"]
        let stored = UserDefaults.standard.string(forKey: "OPV.SimFeedClipPath")
        guard let path = [env, stored].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    static var isConfigured: Bool {
        clipURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    static var configuration: MonitorSimulatorVideoConfiguration {
        .init(clipURL: { Self.clipURL }, transfer: .dlog2, queueLabel: "opv.sim-live",
            logSubsystem: "com.opencapture.openpocketcine",
            missingClipMessage: "Simulator live feed clip not configured - set OPV_SIM_FEED_CLIP or OPV.SimFeedClipPath",
            startedMessage: "Simulator D-Log2 clip looping through handleDecodedFrame")
    }
}
