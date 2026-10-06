import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import OpenCineApple
import OpenCineMedia
import OpenPocketViewCore
import VideoToolbox
import os

/// This app supplies source interpretation, operator choices and diagnostics.
/// The retained decoder, native demand, recovery facts and presentation live in OpenCineApple.
@MainActor
final class HevcDecoder: OpenCineApple.MonitorLiveVideoRuntime {
    var effects = MonitorFrameEffects() {
        didSet { syncDemand() }
    }
    var needsWatchPreview: Bool {
        get { demand.externalPreview }
        set {
            guard demand.externalPreview != newValue else { return }
            demand.externalPreview = newValue
        }
    }
    var onWatchPreview: ((CIImage, CVPixelBuffer?, Bool) -> Void)? {
        get { onPreviewFrame }
        set { onPreviewFrame = newValue }
    }
    var incomingColorMode: ColorMode? {
        didSet {
            if let incomingColorMode { incomingTransfer = MonitorTransfer(incomingColorMode) }
        }
    }
    /// Installed once by the actual source owner, never by a borrowed editor.
    /// Read only when binding/reopening a source or after a camera report.
    var sourceCalibrationProvider: (() -> Int?)?
    var effectsProvider: (() -> MonitorFrameEffects)? {
        didSet {
            demandProvider = { [weak self] in
                guard let self else { return .init() }
                if let next = self.effectsProvider?(), next != self.effects { self.effects = next }
                return self.demand
            }
        }
    }
    var backdropEffects: MonitorFrameEffects {
        var result = effects
        let native = backdropPolicy.image
        result.clipByte = native.clipByte
        result.mirror = presentedPictureFlip ?? pictureFlip
        result.lutDimension = native.lutDimension
        result.lutRGBA = native.lutRGBA
        result.peaking = native.peaking
        result.zebra = native.zebra
        result.falseColor = native.falseColor
        result.desqueezeFactor = native.desqueezeFactor
        return result
    }

    #if targetEnvironment(simulator)
        private let simulatorFeed = SimulatorLiveFeed()
    #endif

    init() {
        super.init(
            configuration: .init(
                assists: LiveAssistEngine.configuration,
                shouldRebuildSession: { CameraSoftAP.shouldRebuildVTSession(status: $0) },
                policyChanged: { replacing in
                    AppDiagnostics.incidents.recordBreadcrumb(
                        FeedIncidentBreadcrumb(
                            monotonicAt: ProcessInfo.processInfo.systemUptime, kind: .assistChange,
                            detail: replacing ? "replacement" : "identity"))
                },
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
                }))
        syncDemand()
        feedUpscaler = FeedUpscaleSwitch.rendererReadsUpscaler
        onSourceAdvanced = {
            NotificationCenter.default.post(name: .monitorBackdropSourceAdvanced, object: nil)
        }
    }

    private func syncDemand() {
        demand = .init(
            assists: effects.nativeAssistPolicy,
            decodedSource: effects.faceAF || effects.inspectorSample,
            externalPreview: demand.externalPreview)
    }

    func attach(
        sampleBus: LiveFrameSampleBus, effects provider: @escaping () -> MonitorFrameEffects,
        transfer: @escaping () -> MonitorTransfer? = { nil }
    ) {
        bindSourcePublication(sampleBus)
        self.effectsProvider = provider
        transferProvider = transfer
        effects = provider()
        adoptIncomingTransfer(transfer())
    }

    func bindSourcePublication(_ bus: LiveFrameSampleBus) {
        sampleBus = bus
        refreshSourceCalibration()
    }

    @discardableResult
    func refreshSourceCalibration() -> Bool {
        updateSourceCalibration(iso: sourceCalibrationProvider?(), source: sourceToken)
    }

    @discardableResult
    func decode(accessUnit: [UInt8]) -> Bool {
        super.decode(accessUnit: accessUnit, source: sourceToken)
    }

    nonisolated func handleDecodedFrame(
        _ buffer: CVPixelBuffer, effects: MonitorFrameEffects? = nil,
        transfer: MonitorTransfer? = nil, isNewSourceFrame: Bool = true, generation: Int? = nil,
        timeNs: Int64 = 0, source: MonitorVideoSourceToken? = nil
    ) {
        super.submitDecodedFrame(
            buffer, policy: effects?.nativeAssistPolicy,
            transfer: transfer, isNewSourceFrame: isNewSourceFrame, generation: generation,
            timeNs: timeNs, source: source)
    }

    nonisolated func handleDecodedFrame(
        _ lease: DecodedFrameLease, effects: MonitorFrameEffects? = nil,
        transfer: MonitorTransfer? = nil, isNewSourceFrame: Bool = true,
        source: MonitorVideoSourceToken? = nil
    ) {
        super.submitDecodedFrame(
            lease, policy: effects?.nativeAssistPolicy,
            transfer: transfer, isNewSourceFrame: isNewSourceFrame, source: source)
    }

    override func close() {
        stopSimulatorSample()
        super.close()
        effectsProvider = nil
        sourceCalibrationProvider = nil
    }

    override func reset() {
        stopSimulatorSample()
        super.reset()
        refreshSourceCalibration()
        startSimulatorSampleIfNeeded()
    }

    /// Simulator footage is an app-selected source, admitted with the token captured at start.
    func startSimulatorSampleIfNeeded() {
        #if targetEnvironment(simulator)
            guard let source = sourceToken else { return }
            preparePixelBufferSource(transfer: .dlog2)
            simulatorFeed.start { [weak self] buffer in
                self?.handleDecodedFrame(buffer, transfer: .dlog2, source: source)
            }
        #endif
    }

    func stopSimulatorSample() {
        #if targetEnvironment(simulator)
            simulatorFeed.stop()
        #endif
    }
}

#if targetEnvironment(simulator)
    /// Loops the operator's D-Log2 4K/25p clip from Downloads. Not part of the Xcode/git tree.
    /// `AVAssetReader` - OpenZCine playback uses a player view; this feed only needs pixel buffers.
    final class SimulatorLiveFeed: @unchecked Sendable {
        /// `OPV_SIM_FEED_CLIP` (env) beats `OPV.SimFeedClipPath` (defaults). No machine-specific
        /// fallback - point the simulator at local footage without editing code.
        static var clipURL: URL? {
            let env = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"]
            let stored = UserDefaults.standard.string(forKey: "OPV.SimFeedClipPath")
            guard let path = [env, stored].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }

        private let queue = DispatchQueue(label: "opv.sim-live", qos: .userInitiated)
        private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "sim-live")
        private var reader: AVAssetReader?
        private var output: AVAssetReaderTrackOutput?
        private var timer: DispatchSourceTimer?
        private var sink: (@Sendable (CVPixelBuffer) -> Void)?
        private var missingLogged = false
        private var running = false
        private var loggedFirst = false

        func start(sink: @escaping @Sendable (CVPixelBuffer) -> Void) {
            queue.async { [self] in
                if running {
                    self.sink = sink
                    return
                }
                begin(sink: sink)
            }
        }

        func stop() {
            queue.async { [self] in teardown() }
        }

        private func begin(sink: @escaping @Sendable (CVPixelBuffer) -> Void) {
            teardown()
            self.sink = sink
            guard let url = Self.clipURL, FileManager.default.fileExists(atPath: url.path) else {
                if !missingLogged {
                    missingLogged = true
                    log.warning(
                        "Simulator live feed clip not configured - set OPV_SIM_FEED_CLIP or OPV.SimFeedClipPath"
                    )
                }
                return
            }
            guard openReader() else { return }
            running = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.04, repeating: 1.0 / 25.0)
            timer.setEventHandler { [weak self] in self?.pull() }
            timer.resume()
            self.timer = timer
            log.info("Simulator D-Log2 clip looping through handleDecodedFrame")
        }

        @discardableResult
        private func openReader() -> Bool {
            reader?.cancelReading()
            reader = nil
            output = nil
            guard let url = Self.clipURL else { return false }
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else {
                log.error("Simulator clip has no video track")
                return false
            }
            do {
                let reader = try AVAssetReader(asset: asset)
                let settings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(
                        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                ]
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
                output.alwaysCopiesSampleData = false
                reader.add(output)
                guard reader.startReading() else {
                    log.error(
                        "AVAssetReader failed to start: \(reader.error?.localizedDescription ?? "unknown", privacy: .public)"
                    )
                    return false
                }
                self.reader = reader
                self.output = output
                return true
            } catch {
                log.error("AVAssetReader: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }

        private func pull() {
            guard let sink else { return }
            if reader?.status == .completed || output == nil {
                _ = openReader()
            }
            guard let output,
                let sample = output.copyNextSampleBuffer(),
                let buffer = CMSampleBufferGetImageBuffer(sample)
            else { return }
            if !loggedFirst {
                loggedFirst = true
                let format = CVPixelBufferGetPixelFormatType(buffer)
                let chars = [
                    UInt8((format >> 24) & 0xFF), UInt8((format >> 16) & 0xFF),
                    UInt8((format >> 8) & 0xFF), UInt8(format & 0xFF),
                ]
                let fourCC = String(bytes: chars, encoding: .ascii) ?? String(format)
                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                let baseNil = CVPixelBufferGetBaseAddress(buffer) == nil
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                log.info(
                    "first sim frame \(fourCC, privacy: .public) \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer)) planes=\(CVPixelBufferGetPlaneCount(buffer)) baseNil=\(baseNil)"
                )
            }
            sink(buffer)
        }

        private func teardown() {
            timer?.cancel()
            timer = nil
            reader?.cancelReading()
            reader = nil
            output = nil
            sink = nil
            running = false
            loggedFirst = false
        }
    }
#endif
