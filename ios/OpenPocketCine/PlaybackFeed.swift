import AVFoundation
import CoreImage
import CoreVideo
import OpenPocketViewCore
import QuartzCore
import UIKit

/// Present order for clip assists — same contract as live `HevcDecoder.applyAssistResult`.
/// Identity stays on `AVPlayerLayer` until Metal owns LUT replace; then the player
/// hides (live hides the VT layer the same way). Overlay (PEAK / FALSE / ZEBRA)
/// keeps the player. `CIFeedView` unhides only after a bake presents.
enum PlaybackFeedHandoff {
    struct Plan: Equatable {
        var showPlayer: Bool
        var showFeed: Bool
        var overlay: Bool
        var unmanaged: Bool
    }

    static func plan(
        effects: LiveImageEffects,
        overlayOnly: Bool,
        unmanagedBake: Bool,
        metalHasPresented: Bool
    ) -> Plan {
        if !effects.needsGPUFeed {
            return Plan(showPlayer: true, showFeed: false, overlay: false, unmanaged: false)
        }
        if overlayOnly || effects.needsOverlayFeed {
            return Plan(
                showPlayer: true, showFeed: metalHasPresented, overlay: true, unmanaged: true)
        }
        // Same as live `HevcDecoder.adoptReplacingMetalFeed`: identity until
        // Metal owns the cube, then hide the HEVC layer so AVPlayer is not a
        // second present under the grade.
        return Plan(
            showPlayer: !metalHasPresented,
            showFeed: metalHasPresented,
            overlay: false,
            unmanaged: presentUnmanaged(overlay: false, unmanagedBake: unmanagedBake))
    }

    /// Overlay chrome is always unmanaged. LUT replace follows the engine —
    /// same `unmanaged: result.unmanagedBake` as live `HevcDecoder`.
    static func presentUnmanaged(overlay: Bool, unmanagedBake: Bool) -> Bool {
        overlay || unmanagedBake
    }

    /// Next/prev keeps the LUT chip and often the last buffer / metal flag.
    /// Until *this item* has presented, keep force-pulling — a single pull
    /// before the decoder has a frame is a no-op, and display-link
    /// `force: false` will not resubmit `lastBuffer`.
    static func shouldForcePull(
        effectsChanged: Bool,
        hasLastBuffer: Bool,
        metalHasPresented: Bool,
        itemHasPresented: Bool
    ) -> Bool {
        if !itemHasPresented { return true }
        return effectsChanged || !hasLastBuffer || !metalHasPresented
    }

    /// One `PlaybackFeedSession` is shared across SwiftUI identities. A slide
    /// `.id(active.id)` used to spawn a second representable whose
    /// `updateUIView` stole `attach` on the way out — LUT chrome stayed armed
    /// while the surviving host never presented.
    static func shouldAdoptHost(
        incomingGeneration: Int, currentGeneration: Int?, isSameHost: Bool
    ) -> Bool {
        if isSameHost { return true }
        guard let currentGeneration else { return true }
        return incomingGeneration > currentGeneration
    }

    /// Overlay bakes set `hasPresentedFrame`, but LUT then flips the Metal layer
    /// opaque. Treating that stale flag as ownership is a black plate over the player.
    static func replaceOwnsPicture(hasPresentedFrame: Bool, lastPresentWasOverlay: Bool) -> Bool {
        FeedPresentPolicy.replaceOwnsPicture(
            hasPresentedFrame: hasPresentedFrame,
            lastPresentWasOverlay: lastPresentWasOverlay)
    }
}

/// Pull clock for preview LUT. LUT-off is `AVPlayerLayer` at the clip rate.
/// A 15–30 Hz display link preferred 24 is the 22–23 fps hitch: 30p proxies
/// get pulldown, and the system may shed to 15. Poll the display; the cube
/// only bakes when `hasNewPixelBuffer` (or until the first present).
enum PlaybackDisplayLink {
    static let pollRange = CAFrameRateRange(minimum: 24, maximum: 120, preferred: 120)

    static func shouldPull(itemHasPresented: Bool, hasNewPixelBuffer: Bool) -> Bool {
        if !itemHasPresented { return true }
        return hasNewPixelBuffer
    }
}

/// Pixel buffers pulled from the player for the live compositor.
///
/// Preview LUT is `CIColorCube` on this buffer, not `AVVideoComposition`.
/// 32BGRA forces an HEVC→RGB conversion every frame; live grades 420 IOSurface.
enum PlaybackVideoOutput {
    static let pixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
    ]

    static var pixelFormat: OSType? {
        let value = pixelBufferAttributes[kCVPixelBufferPixelFormatTypeKey as String]
        if let number = value as? NSNumber { return number.uint32Value }
        return value as? OSType
    }

    /// True when the output asks AVPlayer to author RGB instead of native YUV.
    static var forcesRGBConversion: Bool {
        pixelFormat == kCVPixelFormatType_32BGRA
    }
}

/// Player → pixel buffer → `LiveAssistEngine` → `CIFeedView`.
///
/// `AVVideoComposition` after `replaceCurrentItem` never called the compositor on
/// the parked frame, so LUT / PEAK / FALSE / ZEBRA looked like a no-op. Video
/// output is attached **before** the item becomes current — a late add drops
/// buffers until the next seek.
final class PlaybackFeedSession: NSObject {
    let output: AVPlayerItemVideoOutput
    private let assistEngine = LiveAssistEngine()
    private let linkTarget = DisplayLinkTarget()
    private let pullQueue = DispatchQueue(
        label: "opv.playback-pull", qos: .userInteractive)
    private var displayLink: CADisplayLink?
    private weak var boundItem: AVPlayerItem?
    private weak var player: AVPlayer?
    private weak var host: PlaybackFeedHostView?
    private weak var sampleBus: LiveFrameSampleBus?
    private var effects = LiveImageEffects()
    private var transfer = MonitorTransfer.rec709
    private var lastBuffer: CVPixelBuffer?
    private var lastSubmittedNs: Int64 = 0
    private var lastOverlayOnly = false
    private var lastUnmanagedBake = false
    private var pendingKick = false
    private var loggedRaster = false
    private var lastPresentHealthLogAt: Date?
    private var hostGeneration = 0
    /// Bumped in `prepare`. `presentedEpoch` catches up in `adoptPresentedFeed`.
    private var itemEpoch: UInt64 = 0
    private var presentedEpoch: UInt64 = 0

    override init() {
        output = AVPlayerItemVideoOutput(
            pixelBufferAttributes: PlaybackVideoOutput.pixelBufferAttributes)
        super.init()
        output.setDelegate(self, queue: pullQueue)
        linkTarget.handler = { [weak self] in
            guard let self else { return }
            let time = self.outputTime()
            let hasNew = self.output.hasNewPixelBuffer(forItemTime: time)
            guard
                PlaybackDisplayLink.shouldPull(
                    itemHasPresented: self.itemHasPresented, hasNewPixelBuffer: hasNew)
            else { return }
            self.schedulePull(force: self.effects.needsSample && !self.itemHasPresented)
        }
    }

    /// Must run before `replaceCurrentItem`. Toggling a look later must not
    /// rebuild the player graph — same as Android `PlaybackFeedView`.
    @MainActor
    func prepare(_ item: AVPlayerItem) {
        if let boundItem, boundItem !== item {
            boundItem.remove(output)
        }
        if !item.outputs.contains(where: { $0 === output }) {
            item.add(output)
        }
        boundItem = item
        lastBuffer = nil
        lastSubmittedNs = 0
        pendingKick = false
        loggedRaster = false
        itemEpoch += 1
        assistEngine.reset()
        // LUT chip stays on across next/prev. Drop the previous clip's metal
        // ownership and force a bake of this item — otherwise the toolbar
        // stays armed while the new picture is ungraded identity.
        host?.ciFeed.resetPresentation()
        if host != nil {
            applyLayerPlan(metalHasPresented: false)
        }
        output.requestNotificationOfMediaDataChange(withAdvanceInterval: 1.0 / 60.0)
    }

    func reserveHostGeneration() -> Int {
        hostGeneration += 1
        return hostGeneration
    }

    var debugBoundHost: PlaybackFeedHostView? { host }

    var debugItemHasPresented: Bool { itemHasPresented }

    private var itemHasPresented: Bool { itemEpoch > 0 && presentedEpoch == itemEpoch }

    @MainActor
    func attach(host: PlaybackFeedHostView, player: AVPlayer) {
        let sameHost = self.host === host
        guard
            PlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: host.attachGeneration,
                currentGeneration: self.host?.attachGeneration,
                isSameHost: sameHost)
        else { return }
        if !sameHost, let previous = self.host {
            previous.onDrawableReady = nil
            previous.ciFeed.onPresented = nil
        }
        self.host = host
        self.player = player
        host.playerLayer.player = player
        host.ciFeed.onPresented = { [weak self] in
            Task { @MainActor in self?.adoptPresentedFeed() }
        }
        host.onDrawableReady = { [weak self] in
            Task { @MainActor in self?.pullIfMetalWaiting() }
        }
        if sameHost {
            applyLayerPlan(metalHasPresented: host.ciFeed.hasPresentedFrame)
        } else {
            applyLayerPlan(metalHasPresented: false)
            if let lastBuffer {
                submit(lastBuffer, timeNs: 0)
            }
        }
        pullIfMetalWaiting()
    }

    @MainActor
    func detach(host: PlaybackFeedHostView) {
        guard self.host === host else { return }
        host.onDrawableReady = nil
        host.ciFeed.onPresented = nil
        self.host = nil
    }

    @MainActor
    func setEffects(
        _ effects: LiveImageEffects,
        transfer: MonitorTransfer,
        sampleBus: LiveFrameSampleBus
    ) {
        let changed = self.effects != effects || self.transfer != transfer
        self.effects = effects
        self.transfer = transfer
        self.sampleBus = sampleBus
        if changed {
            lastSubmittedNs = 0
            host?.ciFeed.resetPresentDedup()
            assistEngine.updatePolicy(effects: effects, transfer: transfer)
            if effects.falseColor {
                PocketFalseColorMap.warm(
                    scale: effects.falseColorScale,
                    mode: effects.colorMode,
                    hasLUT: effects.lutDimension >= 2)
            }
            lastOverlayOnly = effects.needsOverlayFeed
            lastUnmanagedBake = effects.replacesIdentityFeed
            // Drop the previous look (and its in-flight bake) so a stale LUT
            // cannot cover identity while zebra / peaking are still scheduling.
            presentedEpoch = itemEpoch &- 1
            host?.ciFeed.resetPresentation()
            applyLayerPlan(metalHasPresented: false)
        }
        if effects.needsSample {
            startLink()
            // Same look on a new item: `changed` is false. Force-pull until
            // *this* item presents — not merely until some prior bake did.
            if PlaybackFeedHandoff.shouldForcePull(
                effectsChanged: changed,
                hasLastBuffer: lastBuffer != nil,
                metalHasPresented: host?.ciFeed.hasPresentedFrame ?? false,
                itemHasPresented: itemHasPresented)
            {
                schedulePull(force: true)
            }
        } else if changed {
            stopLink()
            sampleBus.playbackBundle = nil
        }
    }

    @MainActor
    func shutdown() {
        stopLink()
        boundItem?.remove(output)
        boundItem = nil
        lastBuffer = nil
        lastSubmittedNs = 0
        sampleBus?.playbackBundle = nil
        assistEngine.reset()
        host?.onDrawableReady = nil
        host?.ciFeed.onPresented = nil
        host?.ciFeed.invalidatePendingPresents()
        host?.ciFeed.setOverlayChrome(false)
        host?.ciFeed.isHidden = true
        host?.playerLayer.isHidden = false
        host = nil
        player = nil
        sampleBus = nil
    }

    private func startLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: linkTarget, selector: #selector(DisplayLinkTarget.tick))
        link.preferredFrameRateRange = PlaybackDisplayLink.pollRange
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// New item is current and (usually) playing. Kick the output — the first
    /// `prepare` pull often ran before a pixel buffer existed.
    @MainActor
    func noteItemReady() {
        guard effects.needsSample else { return }
        output.requestNotificationOfMediaDataChange(withAdvanceInterval: 1.0 / 60.0)
        schedulePull(force: true)
    }

    private func schedulePull(force: Bool) {
        pullQueue.async { [weak self] in
            self?.pull(force: force)
        }
    }

    @MainActor
    private func pullIfMetalWaiting() {
        guard effects.needsSample, !itemHasPresented else { return }
        schedulePull(force: true)
    }

    private func pull(force: Bool) {
        guard effects.needsSample else { return }
        let time = outputTime()
        let timeNs = Self.timeNs(time)
        if output.hasNewPixelBuffer(forItemTime: time),
            let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        {
            let working = FeedWorkingRaster.prepared(buffer)
            if !loggedRaster {
                loggedRaster = true
                let w = CVPixelBufferGetWidth(working)
                let h = CVPixelBufferGetHeight(working)
                let srcW = CVPixelBufferGetWidth(buffer)
                ControlLiveLog.line(
                    "media: grade \(w)x\(h) from \(srcW)x\(CVPixelBufferGetHeight(buffer)) \(LiveFrameTap.fourCC(buffer))"
                )
            }
            lastBuffer = working
            submit(working, timeNs: timeNs)
            return
        }
        if let lastBuffer, force {
            submit(lastBuffer, timeNs: timeNs)
            return
        }
        // Output added after decode has started (or the item is parked) holds
        // no pixel buffer until a seek. Live never has this — VT already owns the frame.
        if force, lastBuffer == nil, !pendingKick, let player {
            pendingKick = true
            let seekTime = player.currentTime()
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) {
                [weak self] _ in
                self?.pendingKick = false
                self?.schedulePull(force: true)
            }
        }
    }

    private func outputTime() -> CMTime {
        if let player, player.rate != 0 {
            return output.itemTime(forHostTime: CACurrentMediaTime())
        }
        return boundItem?.currentTime() ?? player?.currentTime() ?? .zero
    }

    private func submit(_ buffer: CVPixelBuffer, timeNs: Int64) {
        lastSubmittedNs = timeNs
        assistEngine.submit(buffer, effects: effects, transfer: transfer, timeNs: timeNs) {
            [weak self] result in
            Task { @MainActor [weak self] in
                self?.present(result)
            }
        }
    }

    private static func timeNs(_ time: CMTime) -> Int64 {
        guard time.isValid, !time.isIndefinite else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        return Int64(seconds * 1_000_000_000)
    }

    @MainActor
    private func present(_ result: LiveAssistEngine.Result) {
        if let bundle = result.bundle {
            sampleBus?.playbackBundle = bundle
        }
        guard result.shouldPresent else { return }
        lastOverlayOnly = result.overlayOnly
        lastUnmanagedBake = result.unmanagedBake
        guard let host else {
            applyLayerPlan(metalHasPresented: false)
            return
        }
        let feed = host.ciFeed
        if !result.needsGPU || !effects.needsGPUFeed {
            applyLayerPlan(metalHasPresented: false)
            return
        }
        if result.overlayOnly {
            let painted = feed.display(
                result.output, unmanaged: true, overlay: true, timeNs: result.timeNs)
            if !painted {
                feed.setOverlayChrome(false)
                feed.isHidden = true
            }
            host.playerLayer.isHidden = false
            return
        }
        // Do not unhide Metal here — that is an empty opaque plate over the
        // player. `display` schedules the bake; `presentLatestBake` unhides
        // only with a texture in hand. Player stays underlay.
        let unmanaged = PlaybackFeedHandoff.presentUnmanaged(
            overlay: false, unmanagedBake: result.unmanagedBake)
        let painted =
            feed.display(
                result.output, unmanaged: unmanaged, overlay: false, timeNs: result.timeNs)
            || feed.display(
                result.identity, unmanaged: false, overlay: false, timeNs: result.timeNs)
        if !painted {
            feed.setOverlayChrome(false)
            feed.isHidden = true
            host.playerLayer.isHidden = false
        }
    }

    @MainActor
    private func adoptPresentedFeed() {
        presentedEpoch = itemEpoch
        guard let feed = host?.ciFeed else { return }
        maybeLogPresentHealth()
        if lastOverlayOnly || effects.needsOverlayFeed {
            applyLayerPlan(metalHasPresented: feed.hasPresentedFrame)
            return
        }
        applyLayerPlan(metalHasPresented: replaceOwnsPicture)
    }

    @MainActor
    private func maybeLogPresentHealth() {
        guard effects.needsGPUFeed, let feed = host?.ciFeed else { return }
        let now = Date()
        if let last = lastPresentHealthLogAt, now.timeIntervalSince(last) < 2 { return }
        lastPresentHealthLogAt = now
        ControlLiveLog.line("media: \(feed.debugLine)")
    }

    private var replaceOwnsPicture: Bool {
        guard let feed = host?.ciFeed else { return false }
        return PlaybackFeedHandoff.replaceOwnsPicture(
            hasPresentedFrame: feed.hasPresentedFrame,
            lastPresentWasOverlay: feed.lastPresentWasOverlay)
    }

    @MainActor
    private func applyLayerPlan(metalHasPresented: Bool) {
        guard let host else { return }
        let plan = PlaybackFeedHandoff.plan(
            effects: effects,
            overlayOnly: lastOverlayOnly,
            unmanagedBake: lastUnmanagedBake,
            metalHasPresented: metalHasPresented)
        host.playerLayer.isHidden = !plan.showPlayer
        if plan.showFeed {
            host.ciFeed.isHidden = false
        } else {
            // Clear ownership so `attach` cannot unhide an empty plate.
            // Do not bump presentGeneration — SwiftUI calls attach every pass
            // and would cancel the LUT bake that `present` just scheduled.
            host.ciFeed.hideForLayerPlan()
        }
    }
}

/// Same stacking as live `DisplayLayerView`: identity layer and Metal are
/// siblings under a plain UIView. `CAMetalLayer` nested in `AVPlayerLayer`
/// (this view's old `layerClass`) presents LUT replace as a black plate;
/// transparent zebra / peaking overlays still showed through.
final class PlaybackFeedHostView: UIView {
    let playerLayer = AVPlayerLayer()
    let ciFeed = CIFeedView()
    var onDrawableReady: (() -> Void)?
    /// SwiftUI identity for this representable. A lower generation is the
    /// departing next/prev twin and must not steal `PlaybackFeedSession`.
    var attachGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
        addSubview(ciFeed)
        ciFeed.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        noteDrawableReady()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        ciFeed.frame = bounds
        noteDrawableReady()
    }

    private func noteDrawableReady() {
        let ready = window != nil && bounds.width > 1 && bounds.height > 1
        ciFeed.isEnabled = ready
        if ready { onDrawableReady?() }
    }
}

extension PlaybackFeedSession: AVPlayerItemOutputPullDelegate {
    nonisolated func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        pull(force: true)
    }
}

private final class DisplayLinkTarget: NSObject {
    var handler: () -> Void = {}
    @objc func tick() { handler() }
}

/// AVPlayerItemVideoOutput frames are Metal IOSurface + Rec.709 attachments.
/// Live unmanaged LUT is encoded camera codes without those tags — cloning
/// onto CPU BGRA is the same input the compositor tests already grade.
enum PlaybackPixelCopy {
    private static let copyContext = CIContext(options: LiveMonitorWorkingSpace.contextOptions)

    static func untaggedBGRA(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 1, height > 1 else { return buffer }
        var clone: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &clone)
        guard status == kCVReturnSuccess, let clone else { return buffer }
        if CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
            blitBGRA(from: buffer, to: clone)
        {
            return clone
        }
        let image = CIImage(cvPixelBuffer: buffer, options: LiveMonitorWorkingSpace.imageOptions)
        copyContext.render(
            image, to: clone,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: nil)
        return clone
    }

    private static func blitBGRA(from source: CVPixelBuffer, to dest: CVPixelBuffer) -> Bool {
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else {
            return false
        }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(dest, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(dest, []) }
        guard let src = CVPixelBufferGetBaseAddress(source),
            let dst = CVPixelBufferGetBaseAddress(dest)
        else { return false }
        let height = CVPixelBufferGetHeight(source)
        let width = CVPixelBufferGetWidth(source)
        let srcStride = CVPixelBufferGetBytesPerRow(source)
        let dstStride = CVPixelBufferGetBytesPerRow(dest)
        let rowBytes = min(srcStride, dstStride, width * 4)
        for y in 0..<height {
            dst.advanced(by: y * dstStride).copyMemory(
                from: src.advanced(by: y * srcStride), byteCount: rowBytes)
        }
        return true
    }
}
