import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import OpenCineApple
import OpenCineCore
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
    /// Codec runtime (OpenCineApple, MEDIA-02): the retained display layer, format, VT session,
    /// sample buffers, error ledger and the generation fence that stamps decoded-frame leases.
    /// This class keeps the presentation policy (assists, layer/Metal ownership, IDR holds).
    private let vt = VideoToolboxDecoder(
        hooks: .init(
            shouldRebuildSession: { HevcDecoder.shouldRebuildSession(status: $0) },
            journal: { ControlLiveLog.line($0) },
            logSubsystem: "com.opencapture.openpocketcine"))
    /// Lives as long as this decoder: host views adopt it, they never recreate it.
    var displayLayer: AVSampleBufferDisplayLayer { vt.displayLayer }
    var hasFormat: Bool { vt.format != nil }
    private var hasSubmittedRandomAccess = false
    private(set) var nalTypesSeen: Set<Int> = []
    var decoderErrors: Int { vt.decoderErrors }
    /// Last VT / layer decode failure. `decoderErrors` is cumulative: one bad
    /// AU an hour ago must not read as `decoderWedged` on the observe line.
    var lastDecodeErrorAt: Date? { vt.lastDecodeErrorAt }
    var lastDecodeStatus: Int32 { vt.lastDecodeStatus }
    var lastDecodeOrigin: String { vt.lastDecodeOrigin }
    var lastDecodeFlags: UInt32 { vt.lastDecodeFlags }

    var nativeOutputAge: TimeInterval? { pipelineMetrics.outputAge }
    var incidentDecodeSnapshot: LiveDecodeMetrics.Snapshot { pipelineMetrics.snapshot }
    private(set) var sourcePresentations = 0
    var incidentPresentations: Int {
        if effects.replacesIdentityFeed, let processedFeed { return processedFeed.presentedFrames }
        return sourcePresentations
    }
    var nativeOutputExpected: Bool { shouldStartVT || referenceRecoveryNeeded }
    private(set) var referenceRecoveryNeeded = false
    /// Last accepted IRAP. Tells the watchdog an enable was already answered.
    private(set) var lastIrapAt: Date?
    var nativeDecodeTotals: (submitted: Int, accepted: Int, output: Int) { pipelineMetrics.totals }
    var canReleaseIDRHold: Bool { hasSubmittedRandomAccess && !vt.sessionFailed }

    private(set) var lastKeyframeAt: Date?
    /// Last AU enqueued or VT frame presented. Watchdog stall signal (not keyframe age).
    private(set) var lastPresentedAt: Date?
    /// New source pictures only; cached LUT/layout redraws never advance this.
    private(set) var lastSourceFrameAt: Date?
    /// True after `flushAndRemoveImage` until a replacement sample is presented.
    private(set) var displayedImageRemoved = false
    /// GOP-reset recover: drop P-frames until the next IDR so the layer cannot fail to black.
    private(set) var awaitingIDR = false
    private(set) var sawKeyframe = false
    /// Local GPU assists. Identity keeps the proven AVSampleBufferDisplayLayer path.
    var effects = LiveImageEffects() {
        didSet { applyEffectsChange() }
    }
    /// Installed companion needs decoded pixels even with AF-S and all assists off.
    /// Keep the existing decoder through wrist sleep; reachability gates JPEG work.
    var needsWatchPreview = false {
        didSet {
            if needsWatchPreview != oldValue { applyEffectsChange() }
        }
    }
    private var needsDecodedSample: Bool { effects.needsSample || needsWatchPreview }
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
            handleDecodedFrame(
                buffer, isNewSourceFrame: false, timeNs: lastDecodedTimeNs)
        }
    }
    weak var sampleBus: LiveFrameSampleBus? {
        didSet {
            // The engine measures and ratchets the ceiling of the bus it publishes into.
            if let sampleBus { assistEngine.adopt(exposureCeiling: sampleBus.exposureCeiling) }
            if shouldStartVT, vt.session == nil, vt.format != nil { rebuildVT() }
        }
    }
    /// Fired on the main actor after a picture is presented (live VT, layer enqueue, or simulator).
    var onPresentedFrame: (() -> Void)?
    /// VT source buffer after assist present. Face AF / Vision. The lease is lent for the call
    /// and released when it returns; keep `pixelBuffer` to use the pixels later.
    var onSourceFrame: ((DecodedFrameLease) -> Void)?
    /// Wrist preview. `source` is the VT identity buffer when a cube does not own
    /// the picture (`nil` for LUT replace). `unmanaged` is a cube product.
    var onWatchPreview: ((CIImage, CVPixelBuffer?, Bool) -> Void)?
    /// Decoded identity buffer before LUT/PEAK. Watcher-relay encode tap.
    nonisolated(unsafe) var onIdentityFrame: ((CVPixelBuffer) -> Void)?
    /// View-space X flip applied on the host view at present time (not SwiftUI).
    var poseViewFlip = false
    var assistMirror = false
    /// Set by `VideoView` so MIRROR assist commits in the same tick as enqueue.
    var applyPictureMirror: ((Bool) -> Void)?
    /// Relay metadata follows the actual flip commit, independently of the 5 Hz HUD.
    var onIdentityOrientation: ((Bool) -> Void)?
    private(set) var presentedPictureFlip: Bool? {
        didSet {
            if presentedPictureFlip != oldValue {
                onIdentityOrientation?(presentedPictureFlip ?? false)
            }
        }
    }
    /// Holds the last picture across extra-mirror so the current frame is not X-flipped in place.
    private var extraMirrorHold = ExtraMirrorHold()
    /// First time VT takes HEVC this session. Mid-GOP P-frames cannot start a
    /// new decoder — one `0x09/0xa8`. Later assist toggles must not fire this.
    var onHandoffNeedsIDR: (() -> Void)?
    /// Pocket screen flip / vertical mode restarts the encoder. Request a new GOP
    /// only when this AU did not already carry the IDR.
    var onParameterSetsChanged: (() -> Void)?
    /// The decoder is not observable; the session republishes the raster so the
    /// layout re-fits when the camera flips between horizontal and vertical.
    var onPictureSizeChanged: (() -> Void)?
    /// Set when SPS/PPS change mid-session; consumed after the rest of the AU is parsed.
    private var pendingParameterChangeEnable = false
    /// Last accepted format dimensions. `0` until the first parameter sets land.
    private(set) var pictureSize: CGSize = .zero
    /// Survives encoder rebuilds (screen flip zeros `pictureSize` until the new SPS).
    private(set) var isVerticalPicture = false
    var pictureAspect: CGFloat {
        FeedRaster.aspect(
            width: Int(pictureSize.width), height: Int(pictureSize.height),
            fallback: isVerticalPicture ? 9.0 / 16.0 : Double(LiveChromeMetrics.feedAspect))
    }

    /// Latched from the first parameter-set AU. Pocket HEVC / Nano AVC.
    private var liveCodec: LiveVideoCodec?
    var incidentCodec: String { liveCodec.map { $0 == .avc ? "avc" : "hevc" } ?? "unknown" }
    private var vps: [UInt8]?
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    /// Capture before asynchronous decode; returned pixels must retain this token
    /// through assist work and its eventual MainActor completion.
    nonisolated var sourceFrameGeneration: Int {
        Int(truncatingIfNeeded: vt.fence.generation.value)
    }
    private var displayReadyCont: CheckedContinuation<Bool, Never>?
    private let assistEngine = LiveAssistEngine()
    nonisolated private let pipelineMetrics = LiveDecodeMetrics()
    private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "hevc")
    /// Simulator (and any pixel-buffer-only source) paints identity on `CIFeedView`.
    private var prefersPixelBufferDisplay = false
    /// Fast / Quality / AI must present through Metal. Off keeps the identity HEVC layer.
    var feedUpscaler: FeedUpscaler = FeedUpscaleSwitch.rendererReadsUpscaler {
        didSet {
            guard oldValue != feedUpscaler else { return }
            applyEffectsChange()
        }
    }
    /// Outdoor HDR panel. Identity presents through Metal EDR; VT stays sticky.
    var hdrDisplayEnabled = false {
        didSet {
            guard oldValue != hdrDisplayEnabled else { return }
            #if !targetEnvironment(simulator)
                prefersPixelBufferDisplay = hdrDisplayEnabled
            #endif
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
        // AVC must keep the decoder that receives the first IDR. Switching from
        // compressed-layer decode to VT after enqueue loses its reference state.
        if liveCodec == .avc { return true }
        if prefersPixelBufferDisplay { return true }
        guard hardwareDecoderUnlocked else { return false }
        return needsDecodedSample || sessionOwnsVT
    }
    /// VT owns the picture so the hardware decoder is not shared with the display layer.
    private var usesPixelBufferDisplay: Bool { prefersPixelBufferDisplay || shouldStartVT }
    /// Test seam: the live VT session (if any) can decode samples stamped with
    /// the current format description. `adoptFormat` must keep this true.
    var vtSessionAcceptsCurrentFormat: Bool { vt.sessionAcceptsCurrentFormat }

    /// Decode failed after the last presented picture — VT / layer is not
    /// producing frames right now. Fresh signal for `LinkDiagnoser`.
    var isDecoderWedged: Bool {
        guard let error = lastDecodeErrorAt else { return false }
        if shouldStartVT, let lastDecodeErrorUptime = vt.lastDecodeErrorUptime {
            guard let outputAge = pipelineMetrics.outputAge else { return true }
            return ProcessInfo.processInfo.systemUptime - lastDecodeErrorUptime < outputAge
        }
        guard let presented = lastPresentedAt else { return true }
        return error > presented
    }

    /// Replacement Metal reports completion, not asynchronous bake admission.
    var monitorPresentedAt: Date? {
        if effects.replacesIdentityFeed, let feed = processedFeed, feed.hasPresentedFrame {
            return feed.lastPresentedAt
        }
        return lastPresentedAt
    }

    /// UDP may still be alive. This is a present hitch, not a recover enable.
    var isPresentFrozen: Bool {
        let now = Date()
        return FeedPresentPolicy.isFrozen(
            secondsSinceLastPresent: monitorPresentedAt.map { now.timeIntervalSince($0) },
            secondsSinceLastDecodedFrame: lastSourceFrameAt.map { now.timeIntervalSince($0) })
    }

    /// Last HEVC picture is still on the layer; release it only when a VT frame is in hand.
    private var pendingLayerRelease = false
    /// LUT (or other GPU) just ended. Keep the last CI frame until the layer presents.
    private var layerHandoffPending = false
    private var lastNeedsSample = false
    private var lastNeedGPU = false
    private var lastOverlayFeed = false
    private var lastReplacesIdentity = false
    /// Last VT / assist source. LUT-off enqueues this on the layer so the canvas never goes black.
    private var lastDecodedBuffer: CVPixelBuffer?
    /// Passive chrome input. Never starts VT, requests an IDR, or changes the
    /// display owner; a compressed-layer-only session uses the public fallback.
    var backdropSource: CVPixelBuffer? {
        displayedImageRemoved ? nil : lastDecodedBuffer
    }

    var backdropEffects: LiveImageEffects {
        var result = effects
        // FALSE / ZEBRA thresholds follow this source's own ceiling.
        result.clipByte = sampleBus?.exposureCeiling.clipByte(
            transfer: MonitorTransfer(result.colorMode))
        result.mirror = presentedPictureFlip ?? pictureFlip
        // Until the current Metal product owns the picture, use identity.
        if result.needsGPUFeed, processedFeed?.hasPresentedFrame != true {
            result.lutDimension = 0
            result.lutRGBA = Data()
            result.peaking = false
            result.zebra = false
            result.falseColor = false
            result.desqueezeFactor = 1
        }
        return result
    }
    private var lastDecodedTimeNs: Int64 = 0
    private var lastPresentHealthLogAt: Date?

    init() {
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
    var isDisplayReady: Bool { vt.isDisplayReady }

    /// True while a VT session is allocated. LUT-off hands HEVC back to the display layer.
    var videoToolboxActive: Bool { vt.session != nil }
    /// Successful `VTDecompressionSessionCreate` count. Repeated VPS/SPS/PPS must not bump this.
    var vtRebuildCount: Int { vt.sessionCreateCount }

    /// Mid-session re-enable gate: display attached, and VT exists when this path needs it.
    var isPresentationReady: Bool {
        guard isDisplayReady else { return false }
        if shouldStartVT, vt.format != nil { return vt.session != nil }
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
        guard let liveCodec else { return false }
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
            : slices.contains { !$0.isEmpty && Hevc.isIRAP(Hevc.nalType($0[0])) }
        if pendingParameterChangeEnable {
            pendingParameterChangeEnable = false
            if EncoderPresentPath.shouldRequestEnableAfterParameterChange(
                accessUnitHasIDR: hasIDR)
            {
                onParameterSetsChanged?()
            }
        }
        // A P-frame accepted by AVSampleBufferDisplayLayer is not a decoded
        // first picture. Without a random-access frame it can silently render
        // nothing, yet marking it presented would disable first-picture recovery.
        guard hasSubmittedRandomAccess || hasIDR else { return false }
        guard
            FeedWatchdog.shouldPresentSample(
                hasPicture: !slices.isEmpty, awaitingIDR: awaitingIDR, isIDR: hasIDR
            )
        else { return false }
        guard let format = vt.format, let sample = vt.makeCompressedSample(slices, format: format),
            VideoToolboxDecoder.isPresentable(sample)
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
            let submitted = presentProcessed(sample)
            if submitted && hasIDR {
                hasSubmittedRandomAccess = true
                referenceRecoveryNeeded = false
                lastIrapAt = Date()
            }
            return submitted
        } else {
            vtOwnsHardwareDecode = false
            displayLayer.isHidden = false
            processedFeed?.isHidden = true
        }
        if displayLayer.requiresFlushToResumeDecoding { displayLayer.flush() }
        // Backpressure is not a failed layer. flush() here hitch-blacked a live GOP.
        guard displayLayer.isReadyForMoreMediaData else {
            // A dropped compressed frame is a missing reference, not backpressure only.
            if hasSubmittedRandomAccess { noteCompressedDiscontinuity() }
            return false
        }
        // A compressed frame skipped during the mirror hold left later P-frames
        // without their reference. Decode it, just do not show it.
        let mirrorHold = !commitPictureFlipIfNeeded()
        if mirrorHold { VideoToolboxDecoder.markDoNotDisplay(sample) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.enqueue(sample)
        CATransaction.commit()
        if displayLayer.status == .failed {
            displayLayer.flush()
            if displayLayer.status == .failed {
                displayedImageRemoved = true
                flushForRecovery()
                noteDecodeError()
                return false
            }
        }
        if hasIDR {
            hasSubmittedRandomAccess = true
            referenceRecoveryNeeded = false
            lastIrapAt = Date()
        }
        if mirrorHold { return true }
        finishLayerHandoffIfNeeded()
        lastSourceFrameAt = Date()
        notePresentedFrame(sampleRate: true)
        return true
    }

    /// Single entry for live VT, the simulator clip, and tests. A decoded `CVPixelBuffer` is enough.
    /// Assist work is off-main; this method does not hop to MainActor before enqueueing.
    nonisolated func handleDecodedFrame(
        _ imageBuffer: CVPixelBuffer,
        effects: LiveImageEffects? = nil,
        transfer: MonitorTransfer? = nil,
        isNewSourceFrame: Bool = true,
        generation: Int? = nil,
        timeNs: Int64 = 0
    ) {
        let lease = vt.fence.lease(
            imageBuffer,
            generation: generation.map { StreamGeneration(UInt64(truncatingIfNeeded: $0)) },
            timeNs: timeNs)
        handleDecodedFrame(
            lease, effects: effects, transfer: transfer, isNewSourceFrame: isNewSourceFrame)
    }

    /// Lease form of the entry above. A lease from an older generation is released unused.
    nonisolated func handleDecodedFrame(
        _ lease: DecodedFrameLease,
        effects: LiveImageEffects? = nil,
        transfer: MonitorTransfer? = nil,
        isNewSourceFrame: Bool = true
    ) {
        let generation = lease.generation
        guard vt.fence.isCurrent(generation), let imageBuffer = lease.pixelBuffer else {
            lease.release()
            return
        }
        let sourceTime = Date()
        let sourceTimeNs =
            lease.timeNs != 0
            ? lease.timeNs
            : (isNewSourceFrame ? Int64(clamping: DispatchTime.now().uptimeNanoseconds) : 0)
        if isNewSourceFrame { onIdentityFrame?(imageBuffer) }
        let assistSubmittedAt = ProcessInfo.processInfo.systemUptime
        if isNewSourceFrame { pipelineMetrics.assistInput() }
        // One MainActor hop per engine callback — a second per-frame Task for the frame
        // counters doubled main-queue pressure at 25 fps for two one-line writes.
        assistEngine.submit(imageBuffer, effects: effects, transfer: transfer, timeNs: sourceTimeNs)
        {
            [weak self] result in
            let completedAt = ProcessInfo.processInfo.systemUptime
            if isNewSourceFrame, result.shouldPresent,
                self?.vt.fence.isCurrent(generation) == true
            {
                self?.pipelineMetrics.assistOutput(
                    at: completedAt, submittedAt: assistSubmittedAt)
            }
            Task { @MainActor [weak self] in
                // The source lease ends here: published, or refused as stale.
                defer { lease.release() }
                guard let self, self.vt.fence.isCurrent(generation) else { return }
                if isNewSourceFrame, result.shouldPresent {
                    self.pipelineMetrics.adopted(
                        at: ProcessInfo.processInfo.systemUptime, completedAt: completedAt)
                }
                let presented = self.applyAssistResult(
                    result, generation: generation, isNewSourceFrame: isNewSourceFrame)
                // Cached repaints cannot refresh camera or watcher liveness.
                if result.shouldPresent && isNewSourceFrame {
                    self.lastSourceFrameAt = sourceTime
                    self.sampleBus?.noteDecodedFrame()
                }
                if presented && isNewSourceFrame {
                    self.publishWatchPreview(result)
                    self.notePresentedFrame(sampleRate: true)
                }
            }
        }
    }

    func reset() {
        invalidateVT()
        hasSubmittedRandomAccess = false
        referenceRecoveryNeeded = false
        finishDisplayWait(false)
        stopSimulatorSample()
        vt.dropFormat()
        liveCodec = nil
        vps = nil
        sps = nil
        pps = nil
        nalTypesSeen.removeAll()
        pictureSize = .zero
        isVerticalPicture = false
        onPictureSizeChanged?()
        vt.clearErrors()
        lastKeyframeAt = nil
        lastPresentedAt = nil
        lastSourceFrameAt = nil
        sawKeyframe = false
        displayedImageRemoved = false
        awaitingIDR = false
        pendingParameterChangeEnable = false
        pendingLayerRelease = false
        layerHandoffPending = false
        lastNeedsSample = false
        lastNeedGPU = false
        lastOverlayFeed = false
        lastReplacesIdentity = false
        sessionOwnsVT = false
        hardwareDecoderUnlocked = false
        lastDecodedBuffer = nil
        lastDecodedTimeNs = 0
        lastPresentHealthLogAt = nil
        presentedPictureFlip = nil
        extraMirrorHold.reset()
        vt.resetCounters()
        assistEngine.reset()
        pipelineMetrics.reset()
        sampleBus?.reset()
        // VT was invalidated before clearing state. Release its old layer image
        // too: an in-app disconnect must not leave a picture from the prior GOP.
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
        processedFeed?.invalidatePendingPresents()
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
        if vt.format != nil {
            rebuildVT(force: true)
            if shouldStartVT, vt.session == nil { dropFormatForRecovery() }
        } else {
            dropFormatForRecovery()
        }
        beginIDRHold()
        return isPresentationReady
    }

    /// A current IRAP can restore references between the watchdog snapshot
    /// and its scheduled owner. MainActor makes this check and mutation atomic.
    /// Returns whether a rebuild was spent, independently of display readiness.
    func rebuildPresentationIfNeeded(referenceLossOnly: Bool) -> Bool {
        if referenceLossOnly, !referenceRecoveryNeeded { return false }
        _ = rebuildPresentation()
        return true
    }

    /// Missing compressed references cannot be repaired by dropping another
    /// arbitrary frame. Retain the image and let the watchdog request an IRAP.
    func noteCompressedDiscontinuity() {
        referenceRecoveryNeeded = referenceRecoveryNeeded || hasSubmittedRandomAccess
        hasSubmittedRandomAccess = false
        beginIDRHold()
        ControlLiveLog.line("decoder: compressedDiscontinuity awaitingRandomAccess=1")
    }

    /// After a GOP-reset enable, ignore P-frames until the IDR AU.
    func beginIDRHold() {
        awaitingIDR = true
    }

    /// UDP is alive and the last picture is still on the layer — do not wait
    /// forever for an IRAP that a PLI did not cut.
    func endIDRHold() {
        guard canReleaseIDRHold else { return }
        awaitingIDR = false
    }

    private func dropFormatForRecovery() {
        vt.dropFormat()
        liveCodec = nil
        vps = nil
        sps = nil
        pps = nil
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
        sourcePresentations += 1
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
        // Preserve the native reference chain on app return. The watchdog owns
        // an evidenced decoder rebuild and its one random-access request.
    }

    private func releaseLayerDecoderIfNeeded() {
        // Do not flushAndRemoveImage — the layer keeps the last picture so LUT-off
        // and false stalls never paint black.
        pendingLayerRelease = false
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
        FeedIncidentRuntime.recordBreadcrumb(
            FeedIncidentBreadcrumb(
                monotonicAt: ProcessInfo.processInfo.systemUptime, kind: .assistChange,
                detail: effects.replacesIdentityFeed ? "replacement" : "identity"))
        // Parameter sets + assist: start VT now. Gating on lastPresentedAt
        // delayed persisted LUT until the 5 s unlock, then sent 0x09/0xa8.
        if hasFormat, needsDecodedSample || hdrDisplayEnabled {
            hardwareDecoderUnlocked = true
        }
        if needsDecodedSample || hdrDisplayEnabled { sessionOwnsVT = true }
        processedFeed?.resetPresentDedup()
        let needVT = shouldStartVT
        let needGPU = effects.needsGPUFeed || presentsOnMetal
        let overlay = effects.needsOverlayFeed && !presentsOnMetal
        let replace = effects.replacesIdentityFeed
        // LUT 50/50 is a compositor flag on an already-replacing cube. Do not
        // rebuild VT, hold IDR, or flip layer ownership — that was the
        // Reconnecting / force-quit (#218).
        let pathUnchanged =
            needVT == lastNeedsSample && needGPU == lastNeedGPU && overlay == lastOverlayFeed
            && replace == lastReplacesIdentity
        // Identity (!needGPU) must still restore the HEVC layer even when the
        // flags look unchanged — tests and LUT-off cover Metal that was left
        // visible. Skip only while we stay on an already-running GPU path
        // (LUT 50/50 is a compositor flag, not a layer/VT tear).
        if pathUnchanged, needGPU, !(needVT && vt.session == nil && vt.format != nil) {
            syncAssistPolicy()
            return
        }
        // A fresh VT session cannot decode mid-GOP P-frames. Once VT owns the
        // session, assist off is a present-path change — keep decoding.
        let vtStarting = needVT && !lastNeedsSample
        let releasingAssist = !needsDecodedSample && lastNeedsSample && sessionOwnsVT
        if needVT {
            if vt.session == nil, vt.format != nil { rebuildVT() }
            vtOwnsHardwareDecode = vt.session != nil
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
                _ = enqueueDecodedFrame(
                    buffer, recoverOnFailure: false, isNewSourceFrame: false)
            }
        } else if overlay {
            // Zebra / peaking / false colour ride on top of the identity layer.
            displayLayer.isHidden = false
        }
        lastNeedsSample = needVT
        lastNeedGPU = needGPU
        lastOverlayFeed = overlay
        lastReplacesIdentity = replace
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
            if hdrDisplayEnabled, feed.hasPresentedFrame {
                adoptReplacingMetalFeed(feed)
                return
            }
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

    private func publishWatchPreview(_ result: LiveAssistEngine.Result) {
        let cubeOwnsPicture =
            result.needsGPU && effects.replacesIdentityFeed && !result.overlayOnly
        let preview: CIImage
        if cubeOwnsPicture {
            preview = result.output
        } else if !result.identity.extent.isEmpty {
            preview = result.identity
        } else {
            preview = CIImage(cvPixelBuffer: result.source)
        }
        // Identity JPEGs encode the VT buffer. A cube product has no matching
        // buffer — passing source there would drop the grade.
        onWatchPreview?(
            preview, cubeOwnsPicture ? nil : result.source,
            cubeOwnsPicture && result.unmanagedBake)
    }

    private func applyAssistResult(
        _ result: LiveAssistEngine.Result, generation: StreamGeneration,
        isNewSourceFrame: Bool = true
    ) -> Bool {
        // The inspector borrows raw main-feed pixels even when no scope is
        // enabled. Retaining the buffer performs no copy or scope calculation;
        // only an actual scope bundle advances the bus's observable generation.
        sampleBus?.publish(
            source: result.source,
            transfer: result.transfer,
            colorMode: result.colorMode,
            bundle: result.bundle)
        if result.shouldPresent {
            lastDecodedBuffer = result.source
            lastDecodedTimeNs = result.timeNs
            if let onSourceFrame {
                let lease = vt.fence.lease(
                    result.source, generation: generation, timeNs: result.timeNs)
                vt.fence.publish(lease, to: onSourceFrame)
                lease.release()
            }
            NotificationCenter.default.post(name: .monitorBackdropSourceAdvanced, object: nil)
        }
        if !result.shouldPresent { return false }
        var presentedIdentity = false

        let replaceIdentity = effects.replacesIdentityFeed
        let metalOwnsPicture =
            replaceIdentity
            && FeedPresentPolicy.replaceOwnsPicture(
                hasPresentedFrame: processedFeed?.hasPresentedFrame ?? false,
                lastPresentWasOverlay: processedFeed?.lastPresentWasOverlay ?? false)

        // Identity picture: same VT buffer Face AF already sees. Never skip this
        // for a Metal remake — NSNull / 10-bit layer enqueue is how the well
        // went black while tracking still worked.
        if usesPixelBufferDisplay, !metalOwnsPicture {
            displayLayer.isHidden = false
            presentedIdentity = enqueueDecodedFrame(
                result.source, recoverOnFailure: false, isNewSourceFrame: isNewSourceFrame)
        } else if !replaceIdentity {
            displayLayer.isHidden = false
        }

        if !result.needsGPU || !effects.needsGPUFeed {
            if hdrDisplayEnabled, let feed = processedFeed {
                let identity = CIImage(cvPixelBuffer: result.source)
                if feed.display(identity, unmanaged: false, overlay: false, timeNs: result.timeNs) {
                    adoptReplacingMetalFeed(feed)
                    return true
                }
            }
            if !metalOwnsPicture {
                processedFeed?.setOverlayChrome(false)
                processedFeed?.isHidden = true
            }
            return presentedIdentity
        }
        guard let feed = processedFeed else { return presentedIdentity }
        if metalOwnsPicture, !commitPictureFlipIfNeeded() {
            return presentedIdentity
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
            return presentedIdentity
        }

        if prefersPixelBufferDisplay, result.overlayOnly {
            let picture = LiveMonitorCompositor.place(result.output, over: result.identity)
            if feed.display(picture, unmanaged: false, overlay: false, timeNs: result.timeNs)
                || feed.display(result.identity, unmanaged: false, timeNs: result.timeNs)
            {
                adoptReplacingMetalFeed(feed)
                return true
            }
            return presentedIdentity
        }

        if replaceIdentity {
            if feed.display(
                result.output, unmanaged: result.unmanagedBake, timeNs: result.timeNs)
                || feed.display(result.identity, unmanaged: false, timeNs: result.timeNs)
            {
                adoptReplacingMetalFeed(feed)
                return true
            }
        }
        return presentedIdentity
    }

    private func buildFormatIfReady() {
        if liveCodec == .avc {
            buildAvcFormatIfReady()
            return
        }
        guard let vps, let sps, let pps else { return }
        if vt.format != nil, vps == vt.builtVPS, sps == vt.builtSPS, pps == vt.builtPPS {
            if shouldStartVT, vt.session == nil { rebuildVT() }
            return
        }
        let changing = EncoderPresentPath.parameterSetsChanged(
            hadFormat: vt.format != nil,
            previousVPS: vt.builtVPS, previousSPS: vt.builtSPS, previousPPS: vt.builtPPS,
            nextVPS: vps, nextSPS: sps, nextPPS: pps)
        if let fmt = VideoToolboxDecoder.makeHEVCFormat(vps: vps, sps: sps, pps: pps) {
            adoptFormat(fmt, vps: vps, sps: sps, pps: pps, changing: changing)
        }
    }

    private func buildAvcFormatIfReady() {
        guard let sps, let pps else { return }
        if vt.format != nil, sps == vt.builtSPS, pps == vt.builtPPS {
            if shouldStartVT, vt.session == nil { rebuildVT() }
            return
        }
        let changing = EncoderPresentPath.parameterSetsChanged(
            hadFormat: vt.format != nil,
            previousVPS: nil, previousSPS: vt.builtSPS, previousPPS: vt.builtPPS,
            nextVPS: nil, nextSPS: sps, nextPPS: pps)
        if let fmt = VideoToolboxDecoder.makeAVCFormat(sps: sps, pps: pps) {
            adoptFormat(fmt, vps: nil, sps: sps, pps: pps, changing: changing)
        }
    }

    private func adoptFormat(
        _ fmt: CMFormatDescription, vps: [UInt8]?, sps: [UInt8], pps: [UInt8], changing: Bool
    ) {
        vt.adoptFormat(fmt, vps: vps, sps: sps, pps: pps)
        let previousSize = pictureSize
        let dims = CMVideoFormatDescriptionGetDimensions(fmt)
        let next = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
        if next.width > 1, next.height > 1 {
            pictureSize = next
            isVerticalPicture = FeedRaster.isVertical(
                width: Int(next.width), height: Int(next.height))
            if next != previousSize {
                // Raster changes are rare (format / screen flip); the size decides layout.
                ControlLiveLog.line(
                    "decoder: picture \(Int(next.width))x\(Int(next.height)) vertical=\(isVerticalPicture ? 1 : 0)"
                )
                onPictureSizeChanged?()
            }
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
        // Same raster, new sets: VT decides. Keeping a session that refuses the
        // new SPS fails every frame with no log — frozen well, live HUD.
        if vt.session != nil,
            EncoderPresentPath.shouldRebuildDecoderForRejectedFormat(
                parameterSetsChanged: changing,
                sessionAcceptsFormat: vt.sessionAccepts(fmt))
        {
            log.info("feed: VT refused new parameter sets — rebuild VT, keep picture")
            ControlLiveLog.line("feed: VT refused new parameter sets — rebuild VT, keep picture")
            rebuildVT(force: true)
        }
        // Persisted LUT/scopes: start VT on this parameter-set AU. `onHandoffNeedsIDR`
        // still requires a picture, so the first GOP is not cut.
        if needsDecodedSample {
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
        if EncoderPresentPath.shouldBeginIDRHoldAfterParameterChange(
            pictureSizeChanged: true, accessUnitHasIDR: false)
        {
            beginIDRHold()
        }
        pendingParameterChangeEnable = true
    }

    private func invalidateVT() {
        // The runtime fences successful callbacks before teardown can deliver its final output.
        vt.invalidateSession()
        hasSubmittedRandomAccess = false
    }

    private func rebuildVT(force: Bool = false) {
        guard shouldStartVT, vt.needsSession(force: force) else { return }
        invalidateVT()
        if vt.openSession() {
            sessionOwnsVT = true
            vtOwnsHardwareDecode = true
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
    func enqueueDecodedFrame(
        _ imageBuffer: CVPixelBuffer, recoverOnFailure: Bool = true, isNewSourceFrame: Bool = true
    ) -> Bool {
        guard commitPictureFlipIfNeeded() else { return false }
        guard VideoToolboxDecoder.isPresentable(imageBuffer) else { return false }
        // VT output keeps one size and color tagging per session; the runtime reuses its description.
        guard let sample = vt.makeDecodedSample(imageBuffer) else { return false }
        if displayLayer.requiresFlushToResumeDecoding { displayLayer.flush() }
        guard displayLayer.isReadyForMoreMediaData else { return false }
        releaseLayerDecoderIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.enqueue(sample)
        CATransaction.commit()
        if displayLayer.status == .failed {
            if recoverOnFailure {
                displayedImageRemoved = true
                flushForRecovery()
                noteDecodeError()
            }
            return false
        }
        finishLayerHandoffIfNeeded()
        if isNewSourceFrame {
            #if DEBUG
                FeedStressAutomation.notePresent()
            #endif
            notePresentedFrame()
        } else {
            displayedImageRemoved = false
        }
        return true
    }

    /// Decode to a pixel buffer. GPU fx and scopes run on `LiveAssistEngine` (off-main).
    @discardableResult
    private func presentProcessed(_ sample: CMSampleBuffer) -> Bool {
        if vt.session == nil, vt.format != nil { rebuildVT() }
        guard vt.session != nil, !vt.sessionFailed else { return false }
        let fx = effects
        let transfer = MonitorTransfer.resolved(
            transferProvider?() ?? incomingTransfer,
            colorMode: incomingColorMode,
            previous: incomingTransfer)
        let flags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        let gen = vt.fence.generation
        let err = decodeFrame(
            sample, flags: flags, generation: gen, effects: fx, transfer: transfer)
        if err == noErr { return true }
        noteDecodeError(status: err, origin: "submit")
        return false
    }

    func noteDecodeError(
        status: OSStatus = 0, origin: String = "display", flags: UInt32 = 0
    ) {
        // A newly failed session rejects every later frame until a rebuild. Report it as
        // known reference loss so the watchdog repairs on its next tick, not after two
        // seconds of inferred output silence.
        if vt.noteError(status: status, origin: origin, flags: flags), origin != "create",
            lastPresentedAt != nil
        {
            referenceRecoveryNeeded = true
        }
    }

    /// Called by the existing 1 Hz session publisher, including during silence.
    func takePipelineTimingLine() -> String {
        pipelineMetrics.takeLine(vtActive: vt.session != nil)
    }

    private func decodeFrame(
        _ sample: CMSampleBuffer,
        flags: VTDecodeFrameFlags,
        generation: StreamGeneration,
        effects: LiveImageEffects,
        transfer: MonitorTransfer
    ) -> OSStatus {
        let submittedAt = ProcessInfo.processInfo.systemUptime
        pipelineMetrics.submitted()
        #if DEBUG
            FeedStressAutomation.noteDecodeSubmit()
        #endif
        let result = vt.decode(sample, flags: flags, generation: generation) {
            [weak self] output in
            guard let self else { return }
            switch output {
            case .failed(let status, let infoFlags):
                Task { @MainActor [weak self] in
                    guard let self, self.vt.fence.isCurrent(generation) else { return }
                    self.noteDecodeError(
                        status: status, origin: "callback", flags: infoFlags.rawValue)
                }
            case .frame(let lease):
                #if DEBUG
                    if FeedStressAutomation.shouldSilenceOutput() {
                        lease.release()
                        return
                    }
                    FeedStressAutomation.noteDecoded()
                #endif
                self.pipelineMetrics.decoded(
                    at: ProcessInfo.processInfo.systemUptime, submittedAt: submittedAt)
                if let buffer = lease.pixelBuffer { self.vt.logFirstOutput(buffer) }
                self.handleDecodedFrame(lease, effects: effects, transfer: transfer)
            }
        }
        if result == noErr { pipelineMetrics.accepted() }
        return result
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
