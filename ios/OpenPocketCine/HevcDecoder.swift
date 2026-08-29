import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import OpenPocketViewCore
import QuartzCore
import VideoToolbox
import os

/// Decodes Osmo live-view access units (Pocket HEVC, Nano AVC) and displays them.
/// Collects VPS/SPS/PPS (HEVC) or SPS/PPS (AVC) from keyframes into a
/// CMVideoFormatDescription, rewrites each access unit from Annex-B start codes to length-prefixed
/// NALs, and enqueues them to an AVSampleBufferDisplayLayer when GPU assists and scopes are off.
/// WAVE / HISTO / PEAK take the hardware decoder exclusively (one VT session — dual-decode starved
/// `handleDecodedFrame` after `5234802`). Scopes-only presents the same VT `CVPixelBuffer` on the
/// display layer (uncompressed, no second HEVC decoder). ZEBRA / PEAK / FALSE paint a
/// transparent overlay on that identity layer so the picture is never remade (a DeviceRGB
/// bake was a contrast shift). LUT / DE-SQ still replace the layer via `CIFeedView`.
/// Once VT starts for an assist, it stays the HEVC decoder for the rest of the
/// session. Handing HEVC back to the display layer mid-GOP required `0x09/0xa8`
/// and that GOP reset is what dropped the feed on LUT / PEAK / WAVE toggles.
///
/// Call chain (live device, scopes on, looks off):
///   DatalinkDriver.onAccessUnit → `decode(accessUnit:)` → `presentProcessed` (VT only)
///     → `handleDecodedFrame` → `LiveAssistEngine.submit` (off-main, latest-wins)
///     → `applyAssistResult` → `LiveFrameSampleBus.publish` + display-layer image buffer
///
/// `MonitorTransfer` rides from `CameraStatus.monitorTransfer` (ColorMode `3F`/`3C`/`17`/`41`
/// → rec709 / hdr / dlog / dlog2). Simulator Downloads clip is forced `.dlog2`.
@MainActor
final class HevcDecoder {
    let displayLayer = AVSampleBufferDisplayLayer()
    private(set) var hasFormat = false
    private(set) var nalTypesSeen: Set<Int> = []
    private(set) var decoderErrors = 0
    private(set) var lastKeyframeAt: Date?
    /// Last AU enqueued or VT frame presented. Watchdog stall signal (not keyframe age).
    private(set) var lastPresentedAt: Date?
    /// True after `flushAndRemoveImage` until a replacement sample is presented.
    private(set) var displayedImageRemoved = false
    /// GOP-reset recover: drop P-frames until the next IDR so the layer cannot fail to black.
    private(set) var awaitingIDR = false
    private(set) var sawKeyframe = false
    /// Local GPU assists. Identity keeps the proven AVSampleBufferDisplayLayer path.
    var effects = LiveImageEffects() {
        didSet { applyEffectsChange() }
    }
    /// Last transfer from `CameraStatus.monitorTransfer`. Provider wins when set.
    var incomingTransfer: MonitorTransfer? {
        didSet { syncAssistPolicy() }
    }
    /// Last color mode pushed from VideoView / CameraStatus. Maps to `incomingTransfer`.
    var incomingColorMode: ColorMode? {
        didSet {
            if let incomingColorMode {
                incomingTransfer = MonitorTransfer(incomingColorMode)
            }
        }
    }

    /// `VideoView.wire` used to assign `incomingTransfer = transfer` even when
    /// `status.monitorTransfer` was nil, wiping D-Log2 and shelving WAVE black.
    func adoptIncomingTransfer(_ next: MonitorTransfer?) {
        if let next { incomingTransfer = next }
    }
    /// Read on every access unit so PEAK/LUT do not depend on SwiftUI `onChange`.
    var effectsProvider: (() -> LiveImageEffects)?
    var transferProvider: (() -> MonitorTransfer?)?
    weak var processedFeed: CIFeedView? {
        didSet {
            if processedFeed !== oldValue {
                oldValue?.onPresented = nil
            }
            processedFeed?.onPresented = { [weak self] in
                Task { @MainActor in self?.adoptPresentedFeed() }
            }
            guard processedFeed !== oldValue, let buffer = lastDecodedBuffer,
                effects.needsGPUFeed
            else { return }
            handleDecodedFrame(buffer)
        }
    }
    weak var sampleBus: LiveFrameSampleBus? {
        didSet {
            if shouldStartVT, vtSession == nil, format != nil { rebuildVT() }
        }
    }
    /// Fired on the main actor after a picture is presented (live VT, layer enqueue, or simulator).
    var onPresentedFrame: (() -> Void)?
    /// VT source buffer after assist present. Face AF / Vision.
    var onSourceFrame: ((CVPixelBuffer) -> Void)?
    /// View-space X flip applied on the host view at present time (not SwiftUI).
    var poseViewFlip = false
    var assistMirror = false
    /// Set by `VideoView` so MIRROR assist commits in the same tick as enqueue.
    var applyPictureMirror: ((Bool) -> Void)?
    private var presentedPictureFlip: Bool?
    /// Holds the last picture across extra-mirror so the current frame is not X-flipped in place.
    private var extraMirrorHold = ExtraMirrorHold()
    /// First time VT takes HEVC this session. Mid-GOP P-frames cannot start a
    /// new decoder — one `0x09/0xa8`. Later assist toggles must not fire this.
    var onHandoffNeedsIDR: (() -> Void)?
    /// Pocket screen flip / vertical mode restarts the encoder. Request a new GOP
    /// only when this AU did not already carry the IDR.
    var onParameterSetsChanged: (() -> Void)?
    /// Set when SPS/PPS change mid-session; consumed after the rest of the AU is parsed.
    private var pendingParameterChangeEnable = false
    /// Last accepted format dimensions. `0` until the first parameter sets land.
    private(set) var pictureSize: CGSize = .zero
    /// Survives encoder rebuilds (screen flip zeros `pictureSize` until the new SPS).
    private(set) var isVerticalPicture = false
    var pictureAspect: CGFloat {
        EncoderPresentPath.feedAspect(
            width: Int(pictureSize.width), height: Int(pictureSize.height),
            fallback: isVerticalPicture ? 9.0 / 16.0 : Double(LiveChromeMetrics.feedAspect))
    }

    private var format: CMVideoFormatDescription?
    /// Latched from the first parameter-set AU. Pocket HEVC / Nano AVC.
    private var liveCodec: LiveVideoCodec?
    private var vps: [UInt8]?
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    private var vtSession: VTDecompressionSession?
    private var vtGeneration = 0
    private var displayReadyCont: CheckedContinuation<Bool, Never>?
    private var frameIndex: Int64 = 0
    private let assistEngine = LiveAssistEngine()
    private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "hevc")
    private let loggedLiveVT = OSAllocatedUnfairLock(initialState: false)
    /// Simulator (and any pixel-buffer-only source) paints identity on `CIFeedView`.
    private var prefersPixelBufferDisplay = false
    /// Fast / Quality / AI must present through Metal. Off keeps the identity HEVC layer.
    var feedUpscaler: FeedUpscaler = FeedUpscaleSwitch.rendererReadsUpscaler {
        didSet {
            guard oldValue != feedUpscaler else { return }
            applyEffectsChange()
        }
    }
    /// VT owns the HEVC block; the display layer only shows already-decoded image buffers.
    private var vtOwnsHardwareDecode = false
    #if targetEnvironment(simulator)
        private let simulatorFeed = SimulatorLiveFeed()
    #endif

    /// WAVE/HISTO/PEAK need a `CVPixelBuffer`. Do not also start VT just because
    /// `sampleBus` is attached — that dual-decoded 4K60 HEVC with the display layer
    /// and starved `handleDecodedFrame` on device after `5234802`.
    /// Sticky after the first assist: tearing VT to hand HEVC back is a GOP reset.
    private var sessionOwnsVT = false
    /// Format + `effects.needsSample` (or `unlockHardwareDecoder`) starts VT.
    /// Waiting for a presented picture GOP-reset persisted LUT ~5 s later.
    private var hardwareDecoderUnlocked = false
    private var wantsFeedUpscale: Bool { feedUpscaler != .off }
    /// Fast/Quality enlarge a *baked* GPU frame (LUT / de-squeeze). They must
    /// not steal the HEVC layer for an identity view — that remake is what
    /// went black, and it also swallowed zebra / false colour into the same
    /// dead present.
    private var presentsOnMetal: Bool {
        prefersPixelBufferDisplay || (wantsFeedUpscale && effects.replacesIdentityFeed)
    }

    private var shouldStartVT: Bool {
        if prefersPixelBufferDisplay { return true }
        guard hardwareDecoderUnlocked else { return false }
        return effects.needsSample || sessionOwnsVT
    }
    /// VT owns the picture so the hardware decoder is not shared with the display layer.
    private var usesPixelBufferDisplay: Bool { prefersPixelBufferDisplay || shouldStartVT }
    /// UDP may still be alive. This is a present hitch, not a recover enable.
    var isPresentFrozen: Bool {
        let age: TimeInterval?
        if effects.replacesIdentityFeed, let feed = processedFeed, feed.hasPresentedFrame {
            age = feed.lastPresentedAt.map { Date().timeIntervalSince($0) }
        } else {
            age = lastPresentedAt.map { Date().timeIntervalSince($0) }
        }
        return FeedPresentPolicy.isFrozen(secondsSinceLastPresent: age)
    }

    /// Last HEVC picture is still on the layer; release it only when a VT frame is in hand.
    private var pendingLayerRelease = false
    /// LUT (or other GPU) just ended. Keep the last CI frame until the layer presents.
    private var layerHandoffPending = false
    private var lastNeedsSample = false
    /// Last VT / assist source. LUT-off enqueues this on the layer so the canvas never goes black.
    private var lastDecodedBuffer: CVPixelBuffer?
    private var lastPresentHealthLogAt: Date?
    private var builtVPS: [UInt8]?
    private var builtSPS: [UInt8]?
    private var builtPPS: [UInt8]?
    /// Parameter sets we already tried to open a VT session for. Repeated PPS must not retry.
    private var vtAttemptedStamp: (vps: [UInt8], sps: [UInt8], pps: [UInt8])?

    init() {
        displayLayer.videoGravity = .resizeAspect
        // OpenZCine: fused-peaking self-check is ~0.5 s. Do it before the first PEAK frame.
        Task.detached(priority: .utility) { _ = LiveMonitorCompositor.fusedPeakingAvailable }
    }

    var pictureFlip: Bool { poseViewFlip != assistMirror }

    func syncPictureFlip() {
        // Extra-mirror commits on the next present, not on the pose edge —
        // flipping the last frame in place is the jarring swap.
    }

    /// New live host view — do not keep a presented flag from a torn-down layer.
    func invalidatePictureFlipPresentation() {
        presentedPictureFlip = nil
        extraMirrorHold.reset()
    }

    /// Layer is in the view hierarchy with a real size — safe to enqueue the first IDR.
    var isDisplayReady: Bool {
        displayLayer.superlayer != nil && displayLayer.bounds.width > 1
            && displayLayer.bounds.height > 1
    }

    /// True while a VT session is allocated. LUT-off hands HEVC back to the display layer.
    var videoToolboxActive: Bool { vtSession != nil }
    /// Successful `VTDecompressionSessionCreate` count. Repeated VPS/SPS/PPS must not bump this.
    private(set) var vtRebuildCount = 0

    /// Mid-session re-enable gate: display attached, and VT exists when this path needs it.
    var isPresentationReady: Bool {
        guard isDisplayReady else { return false }
        if shouldStartVT, format != nil { return vtSession != nil }
        return true
    }

    nonisolated static func shouldRebuildSession(status: OSStatus) -> Bool {
        CameraSoftAP.shouldRebuildVTSession(status: status)
    }

    func noteDisplayReady() {
        finishDisplayWait(isDisplayReady)
    }

    /// Wait until VideoView has laid out the layer. First connect used to enable
    /// before attach; those AUs were discarded and the GOP stayed black.
    @discardableResult
    func waitUntilDisplayReady(timeout: Duration = .milliseconds(800)) async -> Bool {
        if isDisplayReady { return true }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            displayReadyCont = cont
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self else { return }
                self.finishDisplayWait(self.isDisplayReady)
            }
        }
    }

    private func finishDisplayWait(_ ready: Bool) {
        guard let cont = displayReadyCont else { return }
        displayReadyCont = nil
        cont.resume(returning: ready)
    }

    func attach(
        sampleBus: LiveFrameSampleBus,
        effects provider: @escaping () -> LiveImageEffects,
        transfer: @escaping () -> MonitorTransfer? = { nil }
    ) {
        self.sampleBus = sampleBus
        self.effectsProvider = provider
        self.transferProvider = transfer
        let fx = provider()
        if fx != effects { effects = fx }
        adoptIncomingTransfer(transfer())
        syncAssistPolicy()
    }

    /// One access unit (Annex-B; the depacketizer already stripped the DJI frame marker).
    /// Pocket is HEVC; Nano is AVC. Returns true if a frame was enqueued for display.
    @discardableResult
    func decode(accessUnit: [UInt8]) -> Bool {
        if let provided = effectsProvider?(), provided != effects {
            effects = provided
        }
        adoptIncomingTransfer(transferProvider?())
        var slices: [[UInt8]] = []
        let nals = Hevc.nalUnits(accessUnit)
        if liveCodec == nil { liveCodec = LiveVideo.detect(nals: nals) }
        let avc = liveCodec == .avc
        for nal in nals where !nal.isEmpty {
            if avc {
                let type = Avc.nalType(nal[0])
                nalTypesSeen.insert(type)
                if Avc.isKeyframeNal(type) {
                    sawKeyframe = true
                    lastKeyframeAt = Date()
                }
                switch type {
                case Avc.sps: sps = nal
                case Avc.pps:
                    pps = nal
                    buildFormatIfReady()
                case let t where Avc.isVCL(t): slices.append(nal)
                default: break
                }
            } else {
                let type = Hevc.nalType(nal[0])
                nalTypesSeen.insert(type)
                if Hevc.isKeyframeNal(type) {
                    sawKeyframe = true
                    lastKeyframeAt = Date()
                }
                switch type {
                case Hevc.vps: vps = nal
                case Hevc.sps: sps = nal
                case Hevc.pps:
                    pps = nal
                    buildFormatIfReady()
                case let t where Hevc.isVCL(t): slices.append(nal)
                default: break
                }
            }
        }
        let hasIDR =
            avc
            ? slices.contains { !$0.isEmpty && Avc.nalType($0[0]) == Avc.idr }
            : slices.contains { !$0.isEmpty && Hevc.nalType($0[0]) == Hevc.idr }
        if pendingParameterChangeEnable {
            pendingParameterChangeEnable = false
            if EncoderPresentPath.shouldRequestEnableAfterParameterChange(
                accessUnitHasIDR: hasIDR)
            {
                onParameterSetsChanged?()
            }
        }
        guard
            FeedWatchdog.shouldPresentSample(
                hasPicture: !slices.isEmpty, awaitingIDR: awaitingIDR, isIDR: hasIDR
            )
        else { return false }
        guard let format, let sample = sampleBuffer(slices, format), Self.isPresentable(sample)
        else { return false }
        if hasIDR {
            if awaitingIDR {
                log.info("feed: IDR landed — release hold")
            }
            awaitingIDR = false
            // Session counts this hold as done on the next enable.
        }
        if shouldStartVT {
            // Keep the last HEVC picture on the layer. flushAndRemoveImage here
            // is the LUT-off / assist-toggle black canvas.
            if !vtOwnsHardwareDecode {
                pendingLayerRelease = lastPresentedAt != nil && !displayedImageRemoved
                vtOwnsHardwareDecode = true
            }
            if !effects.needsGPUFeed, !presentsOnMetal {
                displayLayer.isHidden = false
                processedFeed?.isHidden = true
            }
            // Do not fall through to HEVC enqueue — that dual-decodes and can
            // fail the layer to black when presentProcessed misses one AU.
            return presentProcessed(sample)
        } else {
            vtOwnsHardwareDecode = false
            displayLayer.isHidden = false
            processedFeed?.isHidden = true
        }
        if displayLayer.requiresFlushToResumeDecoding { displayLayer.flush() }
        if !displayLayer.isReadyForMoreMediaData { displayLayer.flush() }
        guard commitPictureFlipIfNeeded() else { return true }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.enqueue(sample)
        CATransaction.commit()
        if displayLayer.status == .failed {
            displayLayer.flush()
            if displayLayer.status == .failed {
                displayedImageRemoved = true
                flushForRecovery()
                decoderErrors += 1
                return false
            }
        }
        finishLayerHandoffIfNeeded()
        notePresentedFrame(sampleRate: true)
        return true
    }

    /// Single entry for live VT, the simulator clip, and tests. A decoded `CVPixelBuffer` is enough.
    /// Assist work is off-main; this method does not hop to MainActor before enqueueing.
    nonisolated func handleDecodedFrame(
        _ imageBuffer: CVPixelBuffer,
        effects: LiveImageEffects? = nil,
        transfer: MonitorTransfer? = nil
    ) {
        // One MainActor hop per engine callback — a second per-frame Task for the frame
        // counters doubled main-queue pressure at 25 fps for two one-line writes.
        assistEngine.submit(imageBuffer, effects: effects, transfer: transfer, timeNs: 0) {
            [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyAssistResult(result)
                // Once per drained frame; the late scope-bundle callback must not double-count.
                if result.shouldPresent {
                    self.notePresentedFrame(sampleRate: true)
                    self.sampleBus?.noteDecodedFrame()
                }
            }
        }
    }

    func reset() {
        finishDisplayWait(false)
        stopSimulatorSample()
        format = nil
        liveCodec = nil
        vps = nil
        sps = nil
        pps = nil
        hasFormat = false
        nalTypesSeen.removeAll()
        pictureSize = .zero
        isVerticalPicture = false
        decoderErrors = 0
        lastKeyframeAt = nil
        lastPresentedAt = nil
        sawKeyframe = false
        displayedImageRemoved = false
        awaitingIDR = false
        pendingParameterChangeEnable = false
        pendingLayerRelease = false
        layerHandoffPending = false
        lastNeedsSample = false
        sessionOwnsVT = false
        hardwareDecoderUnlocked = false
        lastDecodedBuffer = nil
        lastPresentHealthLogAt = nil
        presentedPictureFlip = nil
        extraMirrorHold.reset()
        builtVPS = nil
        builtSPS = nil
        builtPPS = nil
        vtAttemptedStamp = nil
        vtRebuildCount = 0
        frameIndex = 0
        loggedLiveVT.withLock { $0 = false }
        assistEngine.reset()
        sampleBus?.reset()
        // Invalidate VT and flush the layer. That is the Android analog of
        // joining the MediaCodec output thread and unbinding a dead Surface —
        // in-app disconnect must not leave a live decoder bound to leftover GOP.
        invalidateVT()
        vtOwnsHardwareDecode = false
        displayLayer.isHidden = false
        processedFeed?.invalidatePendingPresents()
        processedFeed?.setOverlayChrome(false)
        processedFeed?.isHidden = true
        displayLayer.flushAndRemoveImage()
        displayedImageRemoved = true
        // Session connect calls reset(); keep the D-Log2 clip running in Simulator.
        startSimulatorSampleIfNeeded()
    }

    /// Drop format so the next IDR rebuilds it. Keeps the last displayed picture.
    /// The session may send a one-shot 0x09/0xa8 after this — never a 1 Hz re-enable loop.
    func flushForRecovery() {
        if displayLayer.status == .failed || displayLayer.requiresFlushToResumeDecoding {
            displayLayer.flush()
        }
        if displayLayer.status == .failed { displayedImageRemoved = true }
        dropFormatForRecovery()
        pendingParameterChangeEnable = false
        beginIDRHold()
    }

    /// Watchdog stage 2: rebuild a wedged VT session. Keeps the last frame.
    /// Does not send enable — caller must wait for `isPresentationReady`.
    @discardableResult
    func rebuildPresentation() -> Bool {
        if displayLayer.status == .failed || displayLayer.requiresFlushToResumeDecoding {
            displayLayer.flush()
        }
        if displayLayer.status == .failed { displayedImageRemoved = true }
        if format != nil {
            rebuildVT(force: true)
            if shouldStartVT, vtSession == nil { dropFormatForRecovery() }
        } else {
            dropFormatForRecovery()
        }
        beginIDRHold()
        return isPresentationReady
    }

    /// After a GOP-reset enable, ignore P-frames until the IDR AU.
    func beginIDRHold() {
        awaitingIDR = true
    }

    private func dropFormatForRecovery() {
        format = nil
        liveCodec = nil
        vps = nil
        sps = nil
        pps = nil
        hasFormat = false
        builtVPS = nil
        builtSPS = nil
        builtPPS = nil
        pictureSize = .zero
        invalidateVT()
        vtOwnsHardwareDecode = false
    }

    private func removeDisplayedImage() {
        guard
            FeedPresentPolicy.shouldFlushDisplayedImage(
                disconnecting: false,
                layerFailed: displayLayer.status == .failed,
                nextFrameReady: lastDecodedBuffer != nil)
        else { return }
        displayLayer.flushAndRemoveImage()
        displayedImageRemoved = true
        log.info("feed: black removed displayed image")
    }

    private func notePresentedFrame(sampleRate: Bool = false) {
        lastPresentedAt = Date()
        displayedImageRemoved = false
        if sampleRate { onPresentedFrame?() }
    }

    /// After the first GOP is rolling. Calling this on the first present
    /// sent a second `0x09/0xa8`, held P-frames, and froze the canvas on LINK.
    func unlockHardwareDecoder() {
        guard !hardwareDecoderUnlocked else { return }
        hardwareDecoderUnlocked = true
        applyEffectsChange()
    }

    /// SoftAP / VT die in the background. Rebuild VT if it was in use, keep the
    /// last picture. Do **not** begin an IDR hold here — that dropped every
    /// P-frame after Control Center when 0x09/0xa8 was then skipped.
    func prepareAfterForeground() {
        if displayLayer.status == .failed || displayLayer.requiresFlushToResumeDecoding {
            displayLayer.flush()
        }
        if displayLayer.status == .failed { displayedImageRemoved = true }
        if shouldStartVT, format != nil { rebuildVT(force: true) }
    }

    private func releaseLayerDecoderIfNeeded() {
        // Do not flushAndRemoveImage — the layer keeps the last picture so LUT-off
        // and false stalls never paint black.
        pendingLayerRelease = false
    }

    nonisolated private static func isPresentable(_ sample: CMSampleBuffer) -> Bool {
        guard CMSampleBufferIsValid(sample), CMSampleBufferGetNumSamples(sample) > 0 else {
            return false
        }
        if let image = CMSampleBufferGetImageBuffer(sample) {
            return isPresentable(image)
        }
        if let block = CMSampleBufferGetDataBuffer(sample) {
            return CMBlockBufferGetDataLength(block) > 0
        }
        return false
    }

    nonisolated private static func isPresentable(_ imageBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferGetWidth(imageBuffer) > 1 && CVPixelBufferGetHeight(imageBuffer) > 1
    }

    /// Simulator-only: loop the D-Log2 Downloads clip through `handleDecodedFrame`.
    func startSimulatorSampleIfNeeded() {
        #if targetEnvironment(simulator)
            prefersPixelBufferDisplay = true
            incomingTransfer = .dlog2
            assistEngine.updatePolicy(effects: effectsProvider?() ?? effects, transfer: .dlog2)
            simulatorFeed.start { [weak self] buffer in
                self?.handleDecodedFrame(buffer, transfer: .dlog2)
            }
        #endif
    }

    func stopSimulatorSample() {
        #if targetEnvironment(simulator)
            simulatorFeed.stop()
        #endif
    }

    private func applyEffectsChange() {
        // Parameter sets + assist: start VT now. Gating on lastPresentedAt
        // delayed persisted LUT until the 5 s unlock, then sent 0x09/0xa8.
        if hasFormat, effects.needsSample {
            hardwareDecoderUnlocked = true
        }
        if effects.needsSample { sessionOwnsVT = true }
        processedFeed?.resetPresentDedup()
        let needVT = shouldStartVT
        let needGPU = effects.needsGPUFeed || presentsOnMetal
        // A fresh VT session cannot decode mid-GOP P-frames. Once VT owns the
        // session, assist off is a present-path change — keep decoding.
        let vtStarting = needVT && !lastNeedsSample
        let releasingAssist = !effects.needsSample && lastNeedsSample && sessionOwnsVT
        if needVT {
            if vtSession == nil, format != nil { rebuildVT() }
            vtOwnsHardwareDecode = vtSession != nil
        }
        if !needGPU {
            // Opaque CIFeedView covers Rec.709 / HLG even when the layer has a picture.
            processedFeed?.invalidatePendingPresents()
            layerHandoffPending = false
            if !vtStarting { awaitingIDR = false }
            displayLayer.isHidden = false
            processedFeed?.setOverlayChrome(false)
            processedFeed?.isHidden = true
            if let buffer = lastDecodedBuffer, isDisplayReady {
                _ = enqueueDecodedFrame(buffer, recoverOnFailure: false)
            }
        } else if effects.needsOverlayFeed, !presentsOnMetal {
            // Zebra / peaking / false colour ride on top of the identity layer.
            displayLayer.isHidden = false
        }
        lastNeedsSample = needVT
        syncAssistPolicy()
        if vtStarting {
            // Empty VT cannot join mid-GOP. Hold even if the session skips a
            // second 0x09/0xa8 because the live-start enable is still in flight.
            beginIDRHold()
        }
        if FeedWatchdog.shouldRequestKeyFrameForDecoderStart(
            startingHardwareDecoder: vtStarting,
            hasFormat: hasFormat,
            hasPicture: lastPresentedAt != nil
        ) {
            log.info("feed: start VT for assist — one 0x09/0xa8")
            ControlLiveLog.line("feed: start VT for assist — one 0x09/0xa8")
            onHandoffNeedsIDR?()
        } else if releasingAssist {
            log.info("feed: assist off — keep VT, no 0x09/0xa8")
            ControlLiveLog.line("feed: assist off — keep VT, no 0x09/0xa8")
        }
    }

    private func finishLayerHandoffIfNeeded() {
        guard layerHandoffPending else { return }
        layerHandoffPending = false
        displayLayer.isHidden = false
        if effects.needsOverlayFeed, !presentsOnMetal,
            processedFeed?.hasPresentedFrame == true
        {
            processedFeed?.isHidden = false
        } else if !effects.needsOverlayFeed {
            processedFeed?.setOverlayChrome(false)
            processedFeed?.isHidden = true
        }
    }

    private func syncAssistPolicy() {
        let fx = effectsProvider?() ?? effects
        let transfer = MonitorTransfer.resolved(
            transferProvider?() ?? incomingTransfer,
            colorMode: incomingColorMode,
            previous: incomingTransfer)
        assistEngine.updatePolicy(effects: fx, transfer: transfer)
    }

    /// LUT metal owns the picture only after a drawable landed. Until then the
    /// HEVC / VT layer stays the identity — OpenZCine has no HEVC layer, so it
    /// never has this underlay.
    private func adoptReplacingMetalFeed(_ feed: CIFeedView) {
        guard
            FeedPresentPolicy.replaceOwnsPicture(
                hasPresentedFrame: feed.hasPresentedFrame,
                lastPresentWasOverlay: feed.lastPresentWasOverlay)
        else { return }
        feed.isHidden = false
        displayLayer.isHidden = true
        releaseLayerDecoderIfNeeded()
    }

    private func adoptPresentedFeed() {
        guard let feed = processedFeed else { return }
        if !effects.needsGPUFeed {
            feed.setOverlayChrome(false)
            feed.isHidden = true
            displayLayer.isHidden = false
            return
        }
        if effects.needsOverlayFeed {
            if feed.hasPresentedFrame { feed.isHidden = false }
            displayLayer.isHidden = false
            return
        }
        if effects.replacesIdentityFeed {
            adoptReplacingMetalFeed(feed)
        }
        maybeLogPresentHealth()
    }

    private func maybeLogPresentHealth() {
        guard effects.needsGPUFeed else { return }
        let now = Date()
        if let last = lastPresentHealthLogAt, now.timeIntervalSince(last) < 2 { return }
        lastPresentHealthLogAt = now
        let frozen = isPresentFrozen ? 1 : 0
        let line = processedFeed?.debugLine ?? "feed present none frozen=\(frozen)"
        ControlLiveLog.line(line)
        if isPresentFrozen {
            log.info(
                "feed: freeze lastFrame=\(self.lastPresentedAt.map { now.timeIntervalSince($0) } ?? -1, format: .fixed(precision: 1), privacy: .public)s (keep picture)"
            )
        }
    }

    private func applyAssistResult(_ result: LiveAssistEngine.Result) {
        if let bundle = result.bundle {
            sampleBus?.publish(
                source: result.source,
                transfer: result.transfer,
                colorMode: result.colorMode,
                bundle: bundle)
        }
        if result.shouldPresent {
            lastDecodedBuffer = result.source
            onSourceFrame?(result.source)
        }
        if !result.shouldPresent { return }

        let replaceIdentity = effects.replacesIdentityFeed
        let metalOwnsPicture = replaceIdentity && (processedFeed?.hasPresentedFrame ?? false)

        // Identity picture: same VT buffer Face AF already sees. Never skip this
        // for a Metal remake — NSNull / 10-bit layer enqueue is how the well
        // went black while tracking still worked.
        if usesPixelBufferDisplay, !metalOwnsPicture {
            displayLayer.isHidden = false
            _ = enqueueDecodedFrame(result.source, recoverOnFailure: false)
        } else if !replaceIdentity {
            displayLayer.isHidden = false
        }

        if !result.needsGPU || !effects.needsGPUFeed {
            if !metalOwnsPicture {
                processedFeed?.setOverlayChrome(false)
                processedFeed?.isHidden = true
            }
            return
        }
        guard let feed = processedFeed else { return }
        if metalOwnsPicture, !commitPictureFlipIfNeeded() {
            return
        }

        if result.overlayOnly, !replaceIdentity, !prefersPixelBufferDisplay {
            // Transparent stripes on top of the layer. Do not unhide here —
            // an unpresented CAMetalLayer is an opaque black plate.
            let painted = feed.display(
                result.output, unmanaged: true, overlay: true, timeNs: result.timeNs)
            if !painted {
                feed.setOverlayChrome(false)
                feed.isHidden = true
            }
            return
        }

        if prefersPixelBufferDisplay, result.overlayOnly {
            let picture = LiveMonitorCompositor.place(result.output, over: result.identity)
            if feed.display(picture, unmanaged: false, overlay: false, timeNs: result.timeNs)
                || feed.display(result.identity, unmanaged: false, timeNs: result.timeNs)
            {
                adoptReplacingMetalFeed(feed)
            }
            return
        }

        if replaceIdentity {
            if feed.display(
                result.output, unmanaged: result.unmanagedBake, timeNs: result.timeNs)
                || feed.display(result.identity, unmanaged: false, timeNs: result.timeNs)
            {
                adoptReplacingMetalFeed(feed)
            }
        }
    }

    private func buildFormatIfReady() {
        if liveCodec == .avc {
            buildAvcFormatIfReady()
            return
        }
        guard let vps, let sps, let pps else { return }
        if format != nil, vps == builtVPS, sps == builtSPS, pps == builtPPS {
            if shouldStartVT, vtSession == nil { rebuildVT() }
            return
        }
        let changing = EncoderPresentPath.parameterSetsChanged(
            hadFormat: format != nil,
            previousVPS: builtVPS, previousSPS: builtSPS, previousPPS: builtPPS,
            nextVPS: vps, nextSPS: sps, nextPPS: pps)
        vps.withUnsafeBufferPointer { v in
            sps.withUnsafeBufferPointer { s in
                pps.withUnsafeBufferPointer { p in
                    let ptrs: [UnsafePointer<UInt8>] = [
                        v.baseAddress!, s.baseAddress!, p.baseAddress!,
                    ]
                    let sizes = [vps.count, sps.count, pps.count]
                    var fmt: CMFormatDescription?
                    let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: 3,
                        parameterSetPointers: ptrs, parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &fmt)
                    if status == noErr, let fmt {
                        adoptFormat(fmt, vps: vps, sps: sps, pps: pps, changing: changing)
                    }
                }
            }
        }
    }

    private func buildAvcFormatIfReady() {
        guard let sps, let pps else { return }
        if format != nil, sps == builtSPS, pps == builtPPS {
            if shouldStartVT, vtSession == nil { rebuildVT() }
            return
        }
        let changing = EncoderPresentPath.parameterSetsChanged(
            hadFormat: format != nil,
            previousVPS: nil, previousSPS: builtSPS, previousPPS: builtPPS,
            nextVPS: nil, nextSPS: sps, nextPPS: pps)
        sps.withUnsafeBufferPointer { s in
            pps.withUnsafeBufferPointer { p in
                let ptrs: [UnsafePointer<UInt8>] = [s.baseAddress!, p.baseAddress!]
                let sizes = [sps.count, pps.count]
                var fmt: CMFormatDescription?
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2,
                    parameterSetPointers: ptrs, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &fmt)
                if status == noErr, let fmt {
                    adoptFormat(fmt, vps: nil, sps: sps, pps: pps, changing: changing)
                }
            }
        }
    }

    private func adoptFormat(
        _ fmt: CMFormatDescription, vps: [UInt8]?, sps: [UInt8], pps: [UInt8], changing: Bool
    ) {
        format = fmt
        hasFormat = true
        builtVPS = vps
        builtSPS = sps
        builtPPS = pps
        let previousSize = pictureSize
        let dims = CMVideoFormatDescriptionGetDimensions(fmt)
        let next = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
        if next.width > 1, next.height > 1 {
            pictureSize = next
            isVerticalPicture = EncoderPresentPath.isVertical(
                width: Int(next.width), height: Int(next.height))
        }
        let sizeChanged =
            previousSize.width > 1 && previousSize.height > 1 && previousSize != next
        // Same-raster VPS/SPS (zoom / FORMAT / color) must not tear or IDR-hold.
        // That hold + skipped 0x09/0xa8 (UDP alive) is a black well with live HUD.
        if changing,
            EncoderPresentPath.shouldRebuildDecoderAfterParameterChange(
                pictureSizeChanged: sizeChanged, accessUnitHasIDR: false)
        {
            handleEncoderFormatChange()
        }
        // Persisted LUT/scopes: start VT on this parameter-set AU. `onHandoffNeedsIDR`
        // still requires a picture, so the first GOP is not cut.
        if effects.needsSample {
            hardwareDecoderUnlocked = true
        }
        if shouldStartVT {
            rebuildVT(force: changing && sizeChanged)
            lastNeedsSample = true
        }
    }

    /// Screen flip / vertical mode restarts the camera encoder. The old VT
    /// session and sample-buffer layer format cannot decode the new GOP.
    /// Same-raster SPS (zoom) must not call this — IDR-hold without enable
    /// blacks the well while HUD/gimbal stay up.
    private func handleEncoderFormatChange() {
        log.info(
            "feed: encoder parameter sets changed \(Int(self.pictureSize.width))x\(Int(self.pictureSize.height))"
        )
        if displayLayer.status == .failed || displayLayer.requiresFlushToResumeDecoding {
            displayLayer.flush()
        }
        invalidateVT()
        vtAttemptedStamp = nil
        if EncoderPresentPath.shouldBeginIDRHoldAfterParameterChange(
            pictureSizeChanged: true, accessUnitHasIDR: false)
        {
            beginIDRHold()
        }
        pendingParameterChangeEnable = true
    }

    private func sampleBuffer(_ nals: [[UInt8]], _ format: CMVideoFormatDescription)
        -> CMSampleBuffer?
    {
        var avcc = [UInt8]()
        for nal in nals {
            var len = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &len) { avcc.append(contentsOf: $0) }
            avcc.append(contentsOf: nal)
        }

        var block: CMBlockBuffer?
        guard
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: avcc.count, flags: 0, blockBufferOut: &block)
                == kCMBlockBufferNoErr, let block
        else { return nil }
        let ok = avcc.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!, blockBuffer: block,
                offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard ok == kCMBlockBufferNoErr else { return nil }

        frameIndex += 1
        var timing = LiveViewPresentTiming.sampleTiming(frameIndex: frameIndex)
        var sample: CMSampleBuffer?
        var sizes = [avcc.count]
        guard
            CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &sizes, sampleBufferOut: &sample)
                == noErr, let sample
        else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample, createIfNecessary: true),
            CFArrayGetCount(attachments) > 0
        {
            let dict = unsafeBitCast(
                CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    private func invalidateVT() {
        if let vtSession { VTDecompressionSessionInvalidate(vtSession) }
        vtSession = nil
        vtGeneration += 1
        vtAttemptedStamp = nil
    }

    private func rebuildVT(force: Bool = false) {
        guard shouldStartVT else { return }
        if !force, vtSession != nil { return }
        if !force, let stamp = vtAttemptedStamp,
            stamp.vps == (builtVPS ?? []), stamp.sps == builtSPS, stamp.pps == builtPPS
        {
            return
        }
        invalidateVT()
        if let sps = builtSPS, let pps = builtPPS {
            vtAttemptedStamp = (builtVPS ?? [], sps, pps)
        }
        loggedLiveVT.withLock { $0 = false }
        guard let format else { return }
        // Face AF / scopes read these buffers; the identity picture is the same
        // buffer enqueued to `AVSampleBufferDisplayLayer`. OpenZCine never does
        // that — it presents 8-bit JPEG via Metal. The layer goes black on the
        // 10-bit `x420` VT first used to hand Pocket (Face AF still works).
        // 8-bit 420v is what the layer, Vision, and the scope tap all accept.
        let attempts: [(name: String, attrs: [String: Any]?)] = [
            (
                "metal-420v",
                [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(
                        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                ]
            ),
            (
                "metal-x420",
                [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(
                        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                ]
            ),
            (
                "metal-native",
                [
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                ]
            ),
            (
                "metal-bgra",
                [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                ]
            ),
            ("native", nil),
            (
                "cpu-bgra",
                [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                ]
            ),
        ]
        for attempt in attempts {
            var session: VTDecompressionSession?
            let status = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: format,
                decoderSpecification: nil,
                imageBufferAttributes: attempt.attrs.map { $0 as CFDictionary },
                outputCallback: nil,
                decompressionSessionOut: &session)
            if status == noErr, let session {
                vtSession = session
                sessionOwnsVT = true
                vtOwnsHardwareDecode = true
                vtRebuildCount += 1
                log.info("VT session \(attempt.name, privacy: .public)")
                return
            }
            log.error("VT create \(attempt.name, privacy: .public) failed \(status)")
        }
    }

    /// Extra-mirror the host view with the next present. `false` keeps the last picture.
    @discardableResult
    private func commitPictureFlipIfNeeded() -> Bool {
        switch extraMirrorHold.step(want: pictureFlip, now: CFAbsoluteTimeGetCurrent()) {
        case .unchanged:
            if presentedPictureFlip != pictureFlip, let apply = applyPictureMirror {
                apply(pictureFlip)
                presentedPictureFlip = pictureFlip
            }
            return true
        case .hold:
            return false
        case .commit(let mirrored):
            applyPictureMirror?(mirrored)
            presentedPictureFlip = mirrored
            return true
        }
    }

    /// Zero-copy present of a VT frame. Uncompressed — the layer must not start a second HEVC decoder.
    @discardableResult
    private func enqueueDecodedFrame(_ imageBuffer: CVPixelBuffer, recoverOnFailure: Bool = true)
        -> Bool
    {
        guard commitPictureFlipIfNeeded() else { return true }
        guard Self.isPresentable(imageBuffer) else { return false }
        var format: CMVideoFormatDescription?
        guard
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                formatDescriptionOut: &format) == noErr,
            let format
        else { return false }

        frameIndex += 1
        var timing = LiveViewPresentTiming.sampleTiming(frameIndex: frameIndex)
        var sample: CMSampleBuffer?
        guard
            CMSampleBufferCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: format,
                sampleTiming: &timing,
                sampleBufferOut: &sample) == noErr,
            let sample
        else { return false }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample, createIfNecessary: true),
            CFArrayGetCount(attachments) > 0
        {
            let dict = unsafeBitCast(
                CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        if displayLayer.requiresFlushToResumeDecoding { displayLayer.flush() }
        if !displayLayer.isReadyForMoreMediaData { displayLayer.flush() }
        releaseLayerDecoderIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.enqueue(sample)
        CATransaction.commit()
        if displayLayer.status == .failed {
            if recoverOnFailure {
                displayedImageRemoved = true
                flushForRecovery()
                decoderErrors += 1
            }
            return false
        }
        finishLayerHandoffIfNeeded()
        notePresentedFrame()
        return true
    }

    /// Decode to a pixel buffer. GPU fx and scopes run on `LiveAssistEngine` (off-main).
    @discardableResult
    private func presentProcessed(_ sample: CMSampleBuffer) -> Bool {
        if vtSession == nil, format != nil { rebuildVT() }
        guard let vtSession else { return false }
        let fx = effects
        let transfer = MonitorTransfer.resolved(
            transferProvider?() ?? incomingTransfer,
            colorMode: incomingColorMode,
            previous: incomingTransfer)
        let flags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        let gen = vtGeneration
        let err = decodeFrame(
            vtSession, sample, flags: flags, generation: gen, effects: fx, transfer: transfer)
        if err == noErr { return true }
        if Self.shouldRebuildSession(status: err) {
            rebuildVT(force: true)
            if let rebuilt = self.vtSession,
                decodeFrame(
                    rebuilt, sample, flags: flags, generation: vtGeneration, effects: fx,
                    transfer: transfer) == noErr
            {
                return true
            }
        }
        decoderErrors += 1
        return false
    }

    private func decodeFrame(
        _ session: VTDecompressionSession,
        _ sample: CMSampleBuffer,
        flags: VTDecodeFrameFlags,
        generation: Int,
        effects: LiveImageEffects,
        transfer: MonitorTransfer
    ) -> OSStatus {
        VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sample, flags: flags, infoFlagsOut: nil
        ) { [weak self] status, _, imageBuffer, _, _ in
            guard let self else { return }
            if status != noErr {
                if Self.shouldRebuildSession(status: status) {
                    Task { @MainActor [weak self] in
                        guard let self, self.vtGeneration == generation, self.shouldStartVT else {
                            return
                        }
                        self.rebuildVT(force: true)
                    }
                }
                return
            }
            guard let imageBuffer, Self.isPresentable(imageBuffer) else { return }
            self.logFirstLiveVT(imageBuffer)
            self.handleDecodedFrame(imageBuffer, effects: effects, transfer: transfer)
        }
    }

    nonisolated private func logFirstLiveVT(_ buffer: CVPixelBuffer) {
        let first = loggedLiveVT.withLock { logged -> Bool in
            if logged { return false }
            logged = true
            return true
        }
        guard first else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let baseNil = CVPixelBufferGetBaseAddress(buffer) == nil
        let ioSurface = LiveFrameTap.isIOSurfaceBacked(buffer)
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        Logger(subsystem: "com.opencapture.openpocketcine", category: "hevc").info(
            "live VT \(LiveFrameTap.fourCC(buffer), privacy: .public) \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer)) planes=\(CVPixelBufferGetPlaneCount(buffer)) baseNil=\(baseNil) ioSurface=\(ioSurface)"
        )
    }
}

/// SoftAP live HEVC is encoder-declared 25 fps (VPS/SPS `time_scale=25`). A 30 fps
/// sample duration would still pace a faster GOP if the camera ever sent one.
enum LiveViewPresentTiming {
    static let timescale: Int32 = 60_000

    static func sampleTiming(frameIndex: Int64) -> CMSampleTimingInfo {
        CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: timescale),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: timescale),
            decodeTimeStamp: .invalid)
    }
}

#if targetEnvironment(simulator)
    /// Loops the operator's D-Log2 4K/25p clip from Downloads. Not part of the Xcode/git tree.
    /// `AVAssetReader` — OpenZCine playback uses a player view; this feed only needs pixel buffers.
    final class SimulatorLiveFeed: @unchecked Sendable {
        /// `OPV_SIM_FEED_CLIP` (env) beats `OPV.SimFeedClipPath` (defaults). No machine-specific
        /// fallback — point the simulator at local footage without editing code.
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
                        "Simulator live feed clip not configured — set OPV_SIM_FEED_CLIP or OPV.SimFeedClipPath"
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
