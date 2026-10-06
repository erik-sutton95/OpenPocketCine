import AVFoundation
import CoreImage
import CoreVideo
import Metal
import OpenCineApple
import OpenPocketViewCore
import XCTest
import OpenCineMedia

@testable import OpenPocketCine

/// Playback LUT / PEAK / FALSE / ZEBRA must follow live present order:
/// identity on `AVPlayerLayer`, assist image on `CIFeedView` only after a bake
/// lands. `AVVideoComposition` after `replaceCurrentItem` never showed the look.
final class PlaybackAssistTests: XCTestCase {
    @MainActor
    func testPlaybackFrameProjectionPreservesTheDonorNativePolicy() {
        for mode in [ColorMode.normal, .hdr, .dLog, .dLogM, .dLog2] {
            for scale in MonitorFalseColorSelection.allCases {
                for clip in [Int?.none, Int?.some(143)] {
                    var effects = MonitorFrameEffects()
                    effects.peaking = true
                    effects.peakingColor = .green
                    effects.peakingSensitivity = .high
                    effects.zebra = true
                    effects.falseColor = true
                    effects.falseColorScale = scale
                    effects.falseColorRec709 = true
                    effects.zebraHighlightIRE = 93
                    effects.zebraMidtoneIRE = 47
                    effects.zebraHighlightColor = .cyan
                    effects.zebraMidtoneColor = .red
                    effects.histogram = true
                    effects.waveform = true
                    effects.parade = true
                    effects.vectorscope = true
                    effects.trafficLights = true
                    effects.ndMeter = true
                    effects.trafficThreshold = 0.004
                    effects.colorMode = mode
                    effects.clipByte = clip
                    let cube = BuiltInLook.mono.cube()
                    effects.lutDimension = cube.size
                    effects.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
                    effects.splitComparison = true
                    effects.splitVertical = false
                    effects.desqueezeFactor = 1.57
                    effects.desqueezeHorizontal = false
                    effects.allowsTransferInference = false
                    effects.mirror = true
                    effects.mirrorVertical = true
                    let value = effects.playbackFrameEffects
                    XCTAssertEqual(value.nativeAssistPolicy, effects.nativeAssistPolicy)
                    XCTAssertEqual(value.clipByte, clip)
                    XCTAssertEqual(value.transfer, MonitorTransfer(mode))
                    XCTAssertTrue(value.mirror)
                    XCTAssertTrue(value.mirrorVertical)
                }
            }
        }
        for effects in [
            MonitorFrameEffects(), MonitorFrameEffects(faceAF: true),
            MonitorFrameEffects(inspectorSample: true),
        ] {
            XCTAssertEqual(effects.playbackFrameEffects.needsSample, effects.needsSample)
        }
    }

    @MainActor
    func testPlaybackAudioWithoutASourceRemainsUnknown() async {
        let runtime = MediaPlaybackAudioSession.makeMeter()
        let polled = expectation(description: "actual native audio owner polls its absent source")
        var observed: AudioMeterLevels?
        var received = false
        runtime.startPolling { value in
            guard !received else { return }
            received = true
            observed = value.map(AudioMeterLevels.init)
            polled.fulfill()
        }
        await fulfillment(of: [polled], timeout: 2)
        runtime.close()
        XCTAssertTrue(received)
        XCTAssertNil(observed, "An absent PCM source must not become measured silence")
        XCTAssertEqual(
            AudioMeterLevels(OpenCineMedia.MonitorAudioMeterLevels.silent), .silent,
            "Known silence remains a distinct measured value")
    }

    /// Sentry OPENPOCKETCINE-IOS-2Q: Main waited on a busy pull during a clip
    /// change until the watchdog killed the app.
    @MainActor
    func testSourceChangeDoesNotWaitForABusyPull() {
        let session = PlaybackFeedSession()
        let release = DispatchSemaphore(value: 0)
        session.debugOnPullQueue { release.wait() }
        // Bounded, so the old sync blocks 2 s and fails instead of hanging the run.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { release.signal() }
        let start = CACurrentMediaTime()
        session.beginSourceChange()
        XCTAssertLessThan(CACurrentMediaTime() - start, 0.5)
        release.signal()
        session.shutdown()
    }

    @MainActor
    func testReadyPlaybackOutputDoesNotSeekToANonnumericTime() async {
        for time in [CMTime.invalid, .indefinite, .positiveInfinity, .negativeInfinity] {
            let player = UnreadyPlaybackPlayer(time: time)
            let session = PlaybackFeedSession()
            let item = ReadyPlaybackItem(url: URL(fileURLWithPath: "/tmp/unready-playback.mp4"))
            session.prepare(item)
            player.replaceCurrentItem(with: item)
            let host = PlaybackFeedHostView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
            session.attach(host: host, player: player)
            var effects = MonitorFrameEffects()
            effects.zebra = true
            session.setEffects(effects.playbackFrameEffects, transfer: .rec709, sampleBus: LiveFrameSampleBus())
            try? await Task.sleep(for: .milliseconds(150))
            session.shutdown()
            XCTAssertEqual(player.seekCount, 0, "A ready output must still wait for a numeric time")
        }
    }

    @MainActor
    func testReadyParkedPlaybackStillKicksAtNumericTime() async {
        let player = UnreadyPlaybackPlayer(time: .zero)
        let item = ReadyPlaybackItem(url: URL(fileURLWithPath: "/tmp/parked-playback.mp4"))
        let session = PlaybackFeedSession()
        session.prepare(item)
        player.replaceCurrentItem(with: item)
        let host = PlaybackFeedHostView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        session.attach(host: host, player: player)
        var effects = MonitorFrameEffects()
        effects.zebra = true
        session.setEffects(effects.playbackFrameEffects, transfer: .rec709, sampleBus: LiveFrameSampleBus())
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while player.seekCount == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        session.shutdown()
        XCTAssertEqual(player.seekCount, 1, "A parked ready item still needs its first frame")
    }

    private let keys = [
        "OpenPocketCine.Assist.v1",
        "OpenPocketCine.PlaybackAssists.v1",
        "OpenPocketCine.LUTSelection",
        "OpenPocketCine.LastMonitorColorMode",
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in keys {
            saved[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = saved[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        saved.removeAll()
        super.tearDown()
    }

    @MainActor
    func testPlaybackEffectsCarryMonitorColorMode() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        assist.togglePlayback(.zebra)
        XCTAssertEqual(assist.playbackEffects.colorMode, .dLog2)
        XCTAssertTrue(assist.playbackEffects.zebra)
        XCTAssertTrue(assist.playbackEffects.needsOverlayFeed)
        XCTAssertFalse(assist.playbackEffects.replacesIdentityFeed)
    }

    @MainActor
    func testPlaybackPeakingAndFalseColorStayOverlays() {
        let assist = LiveAssistState()
        assist.togglePlayback(.peaking)
        XCTAssertTrue(assist.playbackEffects.needsOverlayFeed)
        XCTAssertFalse(assist.playbackEffects.replacesIdentityFeed)

        assist.togglePlayback(.peaking)
        assist.togglePlayback(.falseColor)
        XCTAssertTrue(assist.playbackEffects.falseColor)
        XCTAssertTrue(assist.playbackEffects.needsOverlayFeed)
        XCTAssertFalse(assist.playbackEffects.replacesIdentityFeed)
    }

    @MainActor
    func testPlaybackLUTReplacesIdentityOnceACubeIsArmed() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        assist.togglePlayback(.lut)
        guard BundledOfficialDJILUT.cube(.pocketDLog2) != nil else {
            XCTFail("official D-Log2 cube must load from the app bundle")
            return
        }
        XCTAssertGreaterThanOrEqual(assist.playbackEffects.lutDimension, 2)
        XCTAssertFalse(assist.playbackEffects.lutRGBA.isEmpty)
        XCTAssertTrue(assist.playbackEffects.replacesIdentityFeed)
        XCTAssertFalse(assist.playbackEffects.needsOverlayFeed)
    }

    func testHandoffPlanKeepsThePlayerUntilMetalOwnsThePicture() {
        var zebra = MonitorFrameEffects()
        zebra.zebra = true
        let cube = BuiltInLook.mono.cube()
        var lut = MonitorFrameEffects()
        lut.lutDimension = cube.size
        lut.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        XCTAssertTrue(lut.replacesIdentityFeed)
        struct Case {
            let name: String
            let effects: MonitorFrameEffects
            var overlayOnly = false
            var unmanagedBake = false
            var hdrDisplay = false
            let metalHasPresented: Bool
            let showPlayer: Bool
            let showFeed: Bool
            var overlay: Bool? = nil
            var unmanaged: Bool? = nil
        }
        let cases = [
            // Identity stays on AVPlayerLayer; an unpresented CAMetalLayer is a black plate.
            Case(
                name: "zebra waiting", effects: zebra, overlayOnly: true, metalHasPresented: false,
                showPlayer: true, showFeed: false, overlay: true),
            // Stripes unhide only after the bake presents.
            Case(
                name: "zebra landed", effects: zebra, overlayOnly: true, metalHasPresented: true,
                showPlayer: true, showFeed: true, overlay: true),
            Case(
                name: "HDR identity waiting", effects: MonitorFrameEffects(), hdrDisplay: true,
                metalHasPresented: false, showPlayer: true, showFeed: false),
            Case(
                name: "HDR identity landed", effects: MonitorFrameEffects(), hdrDisplay: true,
                metalHasPresented: true, showPlayer: false, showFeed: true, overlay: false),
            // Player stays until the LUT drawable lands.
            Case(
                name: "LUT waiting", effects: lut, unmanagedBake: true, metalHasPresented: false,
                showPlayer: true, showFeed: false, overlay: false),
            // Live hides the identity layer once Metal owns LUT replace; a second HEVC
            // present is the hitch. The cube product presents unmanaged, like HevcDecoder.
            Case(
                name: "LUT landed", effects: lut, unmanagedBake: true, metalHasPresented: true,
                showPlayer: false, showFeed: true, overlay: false, unmanaged: true),
            Case(
                name: "assists off", effects: MonitorFrameEffects(), metalHasPresented: true,
                showPlayer: true, showFeed: false),
        ]
        for c in cases {
            let plan = MonitorPlaybackFeedHandoff.plan(
                effects: c.effects.playbackFrameEffects, overlayOnly: c.overlayOnly, unmanagedBake: c.unmanagedBake,
                metalHasPresented: c.metalHasPresented, hdrDisplay: c.hdrDisplay)
            XCTAssertEqual(plan.showPlayer, c.showPlayer, "\(c.name): showPlayer")
            XCTAssertEqual(plan.showFeed, c.showFeed, "\(c.name): showFeed")
            if let overlay = c.overlay {
                XCTAssertEqual(plan.overlay, overlay, "\(c.name): overlay")
            }
            if let unmanaged = c.unmanaged {
                XCTAssertEqual(plan.unmanaged, unmanaged, "\(c.name): unmanaged")
            }
        }
    }

    func testPausedLinkParksOnlyAfterAPausedSeekCanLand() {
        XCTAssertFalse(MonitorPlaybackDisplayLink.parkIsDue(idleSince: nil, now: 10))
        XCTAssertFalse(MonitorPlaybackDisplayLink.parkIsDue(idleSince: 10, now: 10.1))
        XCTAssertFalse(MonitorPlaybackDisplayLink.parkIsDue(idleSince: 10, now: 10.5))
        XCTAssertTrue(MonitorPlaybackDisplayLink.parkIsDue(idleSince: 10, now: 10.61))
    }

    func testPlaybackDisplayLinkDoesNotCapTheCubeAtTwentyFour() {
        XCTAssertGreaterThanOrEqual(
            MonitorPlaybackDisplayLink.pollRange.maximum, 60,
            "max 30 preferred 24 is the 22–23 fps LUT hitch; LUT-off is AVPlayerLayer at clip rate")
        XCTAssertNotEqual(MonitorPlaybackDisplayLink.pollRange.preferred, 24)
        XCTAssertGreaterThan(MonitorPlaybackDisplayLink.pollRange.minimum, 15)
        XCTAssertTrue(
            MonitorPlaybackDisplayLink.shouldPull(
                itemHasPresented: false, hasNewPixelBuffer: false),
            "until the first cube lands, keep pulling even without a new buffer")
        XCTAssertFalse(
            MonitorPlaybackDisplayLink.shouldPull(itemHasPresented: true, hasNewPixelBuffer: false),
            "after present, the cube only bakes a new player frame")
        XCTAssertTrue(
            MonitorPlaybackDisplayLink.shouldPull(itemHasPresented: true, hasNewPixelBuffer: true))
    }

    func testPausedPlaybackParksTheDisplayLinkOnceTheSourceIsReady() {
        XCTAssertTrue(MonitorPlaybackDisplayLink.shouldPark(itemHasPresented: true, playerRate: 0))
        XCTAssertFalse(
            MonitorPlaybackDisplayLink.shouldPark(itemHasPresented: true, playerRate: 1),
            "playing keeps display-rate polling")
        XCTAssertFalse(
            MonitorPlaybackDisplayLink.shouldPark(itemHasPresented: false, playerRate: 0),
            "a new item keeps force-pulling until it presents")
    }

    func testScopesOnlyPlaybackIsReadyWithoutAMetalCompletion() {
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.sourceReadyWithoutMetal(
                needsGPUFeed: false, hdrDisplay: false),
            "scopes-only never reaches a Metal completion")
        XCTAssertFalse(
            MonitorPlaybackFeedHandoff.sourceReadyWithoutMetal(
                needsGPUFeed: true, hdrDisplay: false))
        XCTAssertFalse(
            MonitorPlaybackFeedHandoff.sourceReadyWithoutMetal(
                needsGPUFeed: false, hdrDisplay: true))
    }

    func testPlaybackVideoOutputGradesNativeYUVNotBGRA() {
        XCTAssertFalse(
            MonitorPlaybackVideoOutput.forcesRGBConversion,
            "32BGRA from AVPlayerItemVideoOutput converts every HEVC frame; live grades 420")
        XCTAssertEqual(
            MonitorPlaybackVideoOutput.pixelFormat,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        XCTAssertEqual(
            MonitorPlaybackVideoOutput.pixelBufferAttributes[
                kCVPixelBufferMetalCompatibilityKey as String] as? Bool,
            true)
    }

    @MainActor
    func testPreviewLUTDoesNotInstallAVideoComposition() {
        let session = PlaybackFeedSession()
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/openpocketcine-preview-lut.mp4"))
        session.prepare(item)
        XCTAssertNil(
            item.videoComposition,
            "preview LUT grades AVPlayerItemVideoOutput on Metal; AVVideoComposition is export-only"
        )
        session.shutdown()
    }

    func testNextClipForcesAPullUntilTheHostPresents() {
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.shouldForcePull(
                effectsChanged: false, hasLastBuffer: true, metalHasPresented: true,
                itemHasPresented: false),
            "stale lastBuffer + metal from the previous clip must not skip the new item")
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.shouldForcePull(
                effectsChanged: false, hasLastBuffer: true, metalHasPresented: false,
                itemHasPresented: false),
            "prepare drops metal ownership — LUT must bake the new item without toggling the chip")
        XCTAssertFalse(
            MonitorPlaybackFeedHandoff.shouldForcePull(
                effectsChanged: false, hasLastBuffer: true, metalHasPresented: true,
                itemHasPresented: true))
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.shouldForcePull(
                effectsChanged: false, hasLastBuffer: false, metalHasPresented: true,
                itemHasPresented: true))
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.shouldForcePull(
                effectsChanged: true, hasLastBuffer: true, metalHasPresented: true,
                itemHasPresented: true))
    }

    func testShouldAdoptHostPrefersTheNewerRepresentable() {
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 1, currentGeneration: nil, isSameHost: false),
            "first host always binds")
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 1, currentGeneration: 1, isSameHost: true),
            "SwiftUI updateUIView on the bound host must keep it")
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 2, currentGeneration: 1, isSameHost: false))
        XCTAssertFalse(
            MonitorPlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 1, currentGeneration: 2, isSameHost: false),
            "the departing next-clip identity must not steal LUT present")
        XCTAssertFalse(
            MonitorPlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 2, currentGeneration: 2, isSameHost: false),
            "equal generation on a different view is the outgoing slide twin")
    }

    @MainActor
    func testPrepareDropsStaleLUTOwnershipForTheNextClip() {
        let session = PlaybackFeedSession()
        let host = PlaybackFeedHostView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        let player = AVPlayer()
        session.attach(host: host, player: player)
        host.ciFeed.resetPresentation()
        XCTAssertFalse(host.ciFeed.hasPresentedFrame)
        XCTAssertTrue(host.ciFeed.isHidden)

        let cube = BuiltInLook.mono.cube()
        var fx = MonitorFrameEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        let waiting = MonitorPlaybackFeedHandoff.plan(
            effects: fx.playbackFrameEffects, overlayOnly: false, unmanagedBake: false, metalHasPresented: false)
        XCTAssertTrue(waiting.showPlayer)
        XCTAssertFalse(waiting.showFeed)

        let item = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/openpocketcine-next.mp4"))
        session.prepare(item)
        XCTAssertFalse(
            host.ciFeed.hasPresentedFrame,
            "next clip must not inherit the previous LUT drawable")
        XCTAssertFalse(host.playerLayer.isHidden, "identity plays until this clip's cube bakes")
        XCTAssertTrue(host.ciFeed.isHidden)
        XCTAssertFalse(
            session.debugItemHasPresented,
            "next clip must keep force-pulling until this item's cube presents")
        session.shutdown()
    }

    @MainActor
    func testDepartingClipCannotStealThePlaybackHost() {
        let session = PlaybackFeedSession()
        let player = AVPlayer()
        let outgoing = PlaybackFeedHostView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        let incoming = PlaybackFeedHostView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        outgoing.attachGeneration = session.reserveHostGeneration()
        incoming.attachGeneration = session.reserveHostGeneration()

        session.attach(host: outgoing, player: player)
        XCTAssertTrue(session.debugBoundHost === outgoing)

        session.attach(host: incoming, player: player)
        XCTAssertTrue(session.debugBoundHost === incoming)

        session.attach(host: outgoing, player: player)
        XCTAssertTrue(
            session.debugBoundHost === incoming,
            "next-clip slide updateUIView on the leaving view used to steal LUT bake")

        session.detach(host: outgoing)
        XCTAssertTrue(session.debugBoundHost === incoming)
        session.detach(host: incoming)
        XCTAssertNil(session.debugBoundHost)
        session.shutdown()
    }

    @MainActor
    func testHidingTheFeedClearsReplaceOwnershipSoAttachCannotBlackThePlayer() {
        let session = PlaybackFeedSession()
        let host = PlaybackFeedHostView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        let player = AVPlayer()
        session.attach(host: host, player: player)
        var fx = MonitorFrameEffects()
        fx.zebra = true
        session.setEffects(fx.playbackFrameEffects, transfer: .rec709, sampleBus: LiveFrameSampleBus())
        XCTAssertFalse(host.ciFeed.hasPresentedFrame)
        XCTAssertFalse(host.playerLayer.isHidden)
        session.shutdown()
    }

    @MainActor
    func testSessionAddsVideoOutputBeforeTheItemBecomesCurrent() {
        let session = PlaybackFeedSession()
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/openpocketcine-playback.mp4"))
        XCTAssertTrue(item.outputs.isEmpty)
        session.prepare(item)
        XCTAssertTrue(
            item.outputs.contains { $0 === session.output },
            "AVPlayerItemVideoOutput must be on the item before replaceCurrentItem")
        session.shutdown()
        XCTAssertFalse(item.outputs.contains { $0 === session.output })
    }

    func testEngineGradesPlaybackZebraAsOverlayOnly() async {
        let engine = LiveAssistEngine()
        var fx = MonitorFrameEffects()
        fx.zebra = true
        fx.colorMode = .dLog2
        let buffer = ScopeTestBuffers.makeEdgeBuffer()
        let presented = expectation(description: "overlay present")
        presented.assertForOverFulfill = false
        engine.submit(buffer, effects: fx, transfer: .dlog2) { result in
            guard result.shouldPresent else { return }
            XCTAssertTrue(result.needsGPU)
            XCTAssertTrue(result.overlayOnly)
            XCTAssertFalse(result.unmanagedBake)
            presented.fulfill()
        }
        await fulfillment(of: [presented], timeout: 2)
    }

    func testEngineGradesPlaybackLUTAsReplace() async {
        let cube = BuiltInLook.mono.cube()
        var fx = MonitorFrameEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        fx.colorMode = .dLog2
        let engine = LiveAssistEngine()
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 78)
        let presented = expectation(description: "lut present")
        presented.assertForOverFulfill = false
        engine.submit(buffer, effects: fx, transfer: .dlog2) { result in
            guard result.shouldPresent else { return }
            XCTAssertTrue(result.needsGPU)
            XCTAssertFalse(result.overlayOnly)
            XCTAssertTrue(result.unmanagedBake)
            presented.fulfill()
        }
        await fulfillment(of: [presented], timeout: 2)
    }

    func testLUTReplacePresentsUnmanagedLikeLive() {
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.presentUnmanaged(overlay: false, unmanagedBake: true),
            "LUT cube product is NSNull, same as live HevcDecoder")
        XCTAssertFalse(
            MonitorPlaybackFeedHandoff.presentUnmanaged(overlay: false, unmanagedBake: false),
            "identity fallback stays color-managed")
        XCTAssertTrue(
            MonitorPlaybackFeedHandoff.presentUnmanaged(overlay: true, unmanagedBake: false),
            "zebra / peaking / false colour overlay is unmanaged chrome")
    }

    func testLUTBakeOfRec709PlayerFramesKeepsLuma() throws {
        let cases: [(name: String, buffer: CVPixelBuffer, colorMode: ColorMode, managed: Bool)] = [
            (
                "Rec.709-tagged BGRA (AVPlayer output)", Self.rec709TaggedBGRA(code: 78), .dLog2,
                true
            ),
            (
                "Rec.709-tagged 420 (live-shaped player output)",
                Self.tagRec709(
                    ScopeTestBuffers.make420v(width: 32, height: 32, leftY: 128, rightY: 128)),
                .normal, false
            ),
        ]
        for c in cases {
            let lumas = try Self.measureLUTBakeLumas(buffer: c.buffer, colorMode: c.colorMode)
            XCTAssertGreaterThan(
                lumas.unmanaged, 0.04, "unmanaged LUT of \(c.name) must not present black")
            if c.managed { XCTAssertGreaterThan(lumas.managed, 0.04, c.name) }
        }
    }

    @MainActor
    func testPlaybackHostKeepsPlayerAndMetalAsSiblings() {
        let host = PlaybackFeedHostView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertFalse(
            host.layer is AVPlayerLayer,
            "CAMetalLayer nested in AVPlayerLayer is the LUT black plate")
        XCTAssertTrue(host.playerLayer.superlayer === host.layer)
        XCTAssertTrue(host.ciFeed.superview === host)
        XCTAssertFalse(
            host.ciFeed.layer.superlayer is AVPlayerLayer,
            "Metal must be a sibling of AVPlayerLayer, matching live DisplayLayerView")
    }

    @MainActor
    func testHidingAnUnpresentedFeedDoesNotDropTheScheduledBake() {
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        let generation = feed.debugPresentGeneration
        feed.hideForLayerPlan()
        XCTAssertEqual(
            feed.debugPresentGeneration, generation,
            "SwiftUI attach hides the feed every pass — invalidating would cancel the LUT bake")
        XCTAssertFalse(feed.hasPresentedFrame)
        XCTAssertTrue(feed.isHidden)
        feed.resetPresentation()
        XCTAssertNotEqual(feed.debugPresentGeneration, generation)
    }

    func testUntaggedCloneLetsUnmanagedLUTBakeKeepLumaFromIOSurface() throws {
        let made = ScopeTestBuffers.makeIOSurfaceBGRA(width: 32, height: 32, left: 78, right: 78)
        guard made.filled else { throw XCTSkip("host cannot CPU-write IOSurface BGRA") }
        CVBufferSetAttachment(
            made.buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate)
        CVBufferSetAttachment(
            made.buffer, kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        let cloned = MonitorPlaybackPixelCopy.untaggedBGRA(made.buffer)
        XCTAssertNil(
            CVBufferGetAttachment(cloned, kCVImageBufferColorPrimariesKey, nil),
            "clone must drop Rec.709 tags so NSNull present is not a black well")

        let lumas = try Self.measureLUTBakeLumas(
            buffer: cloned, colorMode: .normal, displayIsSource: true)
        XCTAssertGreaterThan(lumas.unmanaged, 0.04)
    }

    /// Mono cube bake of `buffer`, sampled managed and unmanaged. `displayIsSource`
    /// passes the working-space image as the display identity (the clone path).
    private static func measureLUTBakeLumas(
        buffer: CVPixelBuffer, colorMode: ColorMode = .dLog2, displayIsSource: Bool = false
    ) throws -> (managed: Float, unmanaged: Float) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal required")
        }
        let cube = BuiltInLook.mono.cube()
        var fx = MonitorFrameEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        fx.colorMode = colorMode
        let source = CIImage(cvPixelBuffer: buffer, options: MonitorWorkingSpace.imageOptions)
        let identity = displayIsSource ? source : CIImage(cvPixelBuffer: buffer)
        let product = LiveMonitorCompositor.applyProduct(to: source, effects: fx, display: identity)
        XCTAssertTrue(product.unmanagedBake)
        let baker = MonitorFrameBaker(device: device)
        let drawable = CGSize(width: 32, height: 32)
        func luma(unmanaged: Bool) -> Float {
            let done = XCTestExpectation(description: "bake unmanaged=\(unmanaged)")
            baker.scheduleBake(
                image: product.image, drawableSize: drawable, pixelFormat: .bgra8Unorm,
                unmanaged: unmanaged
            ) {
                done.fulfill()
            }
            let wait = XCTWaiter.wait(for: [done], timeout: 2)
            XCTAssertEqual(wait, .completed)
            guard let texture = baker.bakedTexture(for: drawable, pixelFormat: .bgra8Unorm) else {
                XCTFail("baker must publish")
                return 0
            }
            defer { baker.releaseBakedTexture(texture) }
            guard
                let wrapped = CIImage(
                    mtlTexture: texture, options: MonitorWorkingSpace.imageOptions)
            else {
                XCTFail("CIImage(mtlTexture:) must wrap the bake")
                return 0
            }
            return sampleLuma(wrapped)
        }
        return (managed: luma(unmanaged: false), unmanaged: luma(unmanaged: true))
    }

    private static func rec709TaggedBGRA(code: UInt8, width: Int = 32, height: Int = 32)
        -> CVPixelBuffer
    {
        tagRec709(ScopeTestBuffers.makeFlatBuffer(code: code, width: width, height: height))
    }

    private static func tagRec709(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
        CVBufferSetAttachment(
            buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate)
        CVBufferSetAttachment(
            buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2,
            .shouldPropagate)
        CVBufferSetAttachment(
            buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            .shouldPropagate)
        return buffer
    }

    private static func sampleLuma(_ image: CIImage) -> Float {
        let context = CIContext(options: MonitorWorkingSpace.contextOptions)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        return (Float(bytes[0]) + Float(bytes[1]) + Float(bytes[2])) / (3 * 255)
    }
}

private final class UnreadyPlaybackPlayer: AVPlayer {
    private let reportedTime: CMTime
    private let seeks = NSLock()
    private var count = 0

    init(time: CMTime) {
        reportedTime = time
        super.init()
    }

    override func currentTime() -> CMTime { reportedTime }

    var seekCount: Int { seeks.withLock { count } }

    override func seek(
        to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
        completionHandler: @escaping (Bool) -> Void
    ) {
        seeks.withLock { count += 1 }
    }
}

private final class ReadyPlaybackItem: AVPlayerItem {
    override var status: AVPlayerItem.Status { .readyToPlay }
}
