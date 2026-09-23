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
        metalHasPresented: Bool,
        hdrDisplay: Bool = false
    ) -> Plan {
        if hdrDisplay && !effects.needsGPUFeed {
            return Plan(
                showPlayer: !metalHasPresented, showFeed: metalHasPresented,
                overlay: false, unmanaged: false)
        }
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

    /// Scopes, Face AF and inspector samples leave the picture on `AVPlayerLayer`,
    /// so the item is ready once its first source frame is processed. Waiting for
    /// a Metal completion that never comes resubmitted `lastBuffer` every display
    /// tick, including while paused.
    static func sourceReadyWithoutMetal(needsGPUFeed: Bool, hdrDisplay: Bool) -> Bool {
        !needsGPUFeed && !hdrDisplay
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

    /// A paused, presented item has nothing to poll. Park the link (a 120 Hz
    /// link also holds ProMotion at 120 Hz) and let the output's media-data
    /// notification wake it on play or seek, as Apple's video-output sample does.
    static func shouldPark(itemHasPresented: Bool, playerRate: Float) -> Bool {
        itemHasPresented && playerRate == 0
    }

    /// Paused ticks with no new picture before parking. An exact seek while
    /// paused decodes from the previous keyframe (tens of ms), and the scope
    /// throttle (up to 500 ms when critical) can drop the first new sample, so
    /// the link keeps polling this long and forces one last pull before parking.
    static let parkAfter: CFTimeInterval = 0.6

    static func parkIsDue(idleSince: CFTimeInterval?, now: CFTimeInterval) -> Bool {
        guard let idleSince else { return false }
        return now - idleSince >= parkAfter
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
    private var lastBackdropBuffer: CVPixelBuffer?
    private var lastOverlayOnly = false
    private var lastUnmanagedBake = false
    private var pendingKick = false
    private var loggedRaster = false
    private var lastPresentHealthLogAt: Date?
    private var hostGeneration = 0
    /// Bumped in `prepare`. `presentedEpoch` catches up in `adoptPresentedFeed`.
    private var itemEpoch: UInt64 = 0
    private var presentedEpoch: UInt64 = 0
    /// First paused tick without a new picture; see `PlaybackDisplayLink.parkAfter`.
    private var idleSince: CFTimeInterval?

    override init() {
        output = AVPlayerItemVideoOutput(
            pixelBufferAttributes: PlaybackVideoOutput.pixelBufferAttributes)
        super.init()
        output.setDelegate(self, queue: pullQueue)
        linkTarget.handler = { [weak self] in
            guard let self else { return }
            let time = self.outputTime()
            let hasNew = time.isNumeric && self.output.hasNewPixelBuffer(forItemTime: time)
            guard
                PlaybackDisplayLink.shouldPull(
                    itemHasPresented: self.itemHasPresented, hasNewPixelBuffer: hasNew)
            else {
                if PlaybackDisplayLink.shouldPark(
                    itemHasPresented: self.itemHasPresented, playerRate: self.player?.rate ?? 0)
                {
                    let now = CACurrentMediaTime()
                    let idleSince = self.idleSince ?? now
                    self.idleSince = idleSince
                    if PlaybackDisplayLink.parkIsDue(idleSince: idleSince, now: now) {
                        // Resample the held picture so scopes match it after a paused seek.
                        if self.effects.needsSample { self.schedulePull(force: true) }
                        self.parkLink()
                    }
                } else {
                    self.idleSince = nil
                }
                return
            }
            self.idleSince = nil
            self.schedulePull(force: self.effects.needsSample && !self.itemHasPresented)
        }
    }

    /// Must run before `replaceCurrentItem`. Toggling a look later must not
    /// rebuild the player graph — same as Android `PlaybackFeedView`.
    @MainActor
    func prepare(_ item: AVPlayerItem) {
        beginSourceChange()
        if !item.outputs.contains(where: { $0 === output }) {
            item.add(output)
        }
        boundItem = item
        loggedRaster = false
        displayLink?.isPaused = false
        // LUT chip stays on across next/prev. Drop the previous clip's metal
        // ownership and force a bake of this item — otherwise the toolbar
        // stays armed while the new picture is ungraded identity.
        host?.ciFeed.resetPresentation()
        if host != nil {
            applyLayerPlan(metalHasPresented: false)
        }
        output.requestNotificationOfMediaDataChange(withAdvanceInterval: 1.0 / 60.0)
    }

    /// Retire a clip as soon as Next/Previous starts loading, including a slow
    /// download. Keep the native host; old samples cannot become the new meter.
    @MainActor
    func beginSourceChange() {
        boundItem?.remove(output)
        boundItem = nil
        itemEpoch &+= 1
        // Drain an admitted pull before clearing its retained buffer. Engine
        // completions are asynchronous and are rejected by the item epoch.
        pullQueue.sync {
            lastBuffer = nil
            pendingKick = false
        }
        lastBackdropBuffer = nil
        sampleBus?.clearPlaybackSource()
        assistEngine.reset()
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
        if !sampleBus.usesPlaybackSource { sampleBus.clearPlaybackSource() }
        sampleBus.usesPlaybackSource = true
        if changed {
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
        if effects.needsSample || LiveHDRDisplay.isEnabled {
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
            sampleBus.clearPlaybackSource()
        }
    }

    @MainActor
    func shutdown() {
        stopLink()
        boundItem?.remove(output)
        boundItem = nil
        lastBuffer = nil
        lastBackdropBuffer = nil
        sampleBus?.playbackBundle = nil
        sampleBus?.clearPlaybackSource()
        sampleBus?.usesPlaybackSource = false
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
        displayLink?.isPaused = false
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: linkTarget, selector: #selector(DisplayLinkTarget.tick))
        link.preferredFrameRateRange = PlaybackDisplayLink.pollRange
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Called only by the visible backdrop's admitted 5 Hz job. The existing
    /// output is already attached to the player; this neither seeks nor starts
    /// a second output, display link, decoder or assist presentation pipeline.
    @MainActor
    func backdropSource() -> CVPixelBuffer? {
        guard boundItem != nil else { return nil }
        if effects.needsSample { return sampleBus?.playbackSourcePixelBuffer }
        let time = outputTime()
        guard time.isNumeric else { return lastBackdropBuffer }
        if output.hasNewPixelBuffer(forItemTime: time),
            let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        {
            lastBackdropBuffer = buffer
        }
        return lastBackdropBuffer
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func parkLink() {
        idleSince = nil
        guard let displayLink, !displayLink.isPaused else { return }
        displayLink.isPaused = true
        output.requestNotificationOfMediaDataChange(withAdvanceInterval: 1.0 / 60.0)
    }

    /// New item is current and (usually) playing. Kick the output — the first
    /// `prepare` pull often ran before a pixel buffer existed.
    @MainActor
    func noteItemReady() {
        guard effects.needsSample || LiveHDRDisplay.isEnabled else { return }
        displayLink?.isPaused = false
        output.requestNotificationOfMediaDataChange(withAdvanceInterval: 1.0 / 60.0)
        schedulePull(force: true)
    }

    private func schedulePull(force: Bool) {
        let sourceEpoch = itemEpoch
        pullQueue.async { [weak self] in
            guard let self, self.itemEpoch == sourceEpoch else { return }
            self.pull(force: force, sourceEpoch: sourceEpoch)
        }
    }

    @MainActor
    private func pullIfMetalWaiting() {
        guard effects.needsSample || LiveHDRDisplay.isEnabled, !itemHasPresented else { return }
        schedulePull(force: true)
    }

    private func pull(force: Bool, sourceEpoch: UInt64) {
        guard boundItem != nil else { return }
        guard effects.needsSample || LiveHDRDisplay.isEnabled else { return }
        let time = outputTime()
        let timeNs = Self.timeNs(time)
        if time.isNumeric, output.hasNewPixelBuffer(forItemTime: time),
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
            submit(working, timeNs: timeNs, sourceEpoch: sourceEpoch)
            NotificationCenter.default.post(name: .monitorBackdropSourceAdvanced, object: nil)
            return
        }
        if let lastBuffer, force {
            submit(lastBuffer, timeNs: timeNs, sourceEpoch: sourceEpoch)
            return
        }
        // Output added after decode has started (or the item is parked) holds
        // no pixel buffer until a seek. Live never has this — VT already owns the frame.
        if force, lastBuffer == nil, !pendingKick, let player {
            let seekTime = player.currentTime()
            // A newly attached or failed remote item can report invalid or
            // indefinite time. AVPlayer raises an Objective-C exception if
            // that value is used as a seek target; wait for the ready callback.
            guard let boundItem, player.currentItem === boundItem,
                boundItem.status == .readyToPlay, seekTime.isNumeric
            else { return }
            pendingKick = true
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

    private func submit(_ buffer: CVPixelBuffer, timeNs: Int64, sourceEpoch: UInt64? = nil) {
        let sourceEpoch = sourceEpoch ?? itemEpoch
        assistEngine.submit(buffer, effects: effects, transfer: transfer, timeNs: timeNs) {
            [weak self] result in
            Task { @MainActor [weak self] in
                self?.present(result, sourceEpoch: sourceEpoch)
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
    private func present(_ result: LiveAssistEngine.Result, sourceEpoch: UInt64) {
        guard boundItem != nil, sourceEpoch == itemEpoch else { return }
        if let bundle = result.bundle {
            sampleBus?.playbackBundle = bundle
        }
        guard result.shouldPresent else { return }
        sampleBus?.playbackSourcePixelBuffer = result.source
        sampleBus?.playbackSourceTransfer = result.transfer
        lastOverlayOnly = result.overlayOnly
        lastUnmanagedBake = result.unmanagedBake
        guard let host else {
            applyLayerPlan(metalHasPresented: false)
            return
        }
        let feed = host.ciFeed
        if LiveHDRDisplay.isEnabled, !effects.needsGPUFeed {
            let identity = CIImage(cvPixelBuffer: result.source)
            if feed.display(identity, unmanaged: false, overlay: false, timeNs: result.timeNs) {
                return
            }
        }
        if !result.needsGPU || !effects.needsGPUFeed {
            if PlaybackFeedHandoff.sourceReadyWithoutMetal(
                needsGPUFeed: effects.needsGPUFeed, hdrDisplay: LiveHDRDisplay.isEnabled)
            {
                presentedEpoch = itemEpoch
            }
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
            metalHasPresented: metalHasPresented,
            hdrDisplay: LiveHDRDisplay.isEnabled)
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
        ciFeed.syncHDRDisplay()
        LiveHDRDisplay.configure(playerLayer)
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
        pull(force: true, sourceEpoch: itemEpoch)
        DispatchQueue.main.async { [weak self] in self?.displayLink?.isPaused = false }
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
