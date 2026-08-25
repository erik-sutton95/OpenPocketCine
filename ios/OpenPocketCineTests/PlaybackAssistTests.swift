import AVFoundation
import CoreImage
import CoreVideo
import Metal
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Playback LUT / PEAK / FALSE / ZEBRA must follow live present order:
/// identity on `AVPlayerLayer`, assist image on `CIFeedView` only after a bake
/// lands. `AVVideoComposition` after `replaceCurrentItem` never showed the look.
final class PlaybackAssistTests: XCTestCase {
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

    func testPlaybackEffectsCarryMonitorColorMode() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        assist.togglePlayback(.zebra)
        XCTAssertEqual(assist.playbackEffects.colorMode, .dLog2)
        XCTAssertTrue(assist.playbackEffects.zebra)
        XCTAssertTrue(assist.playbackEffects.needsOverlayFeed)
        XCTAssertFalse(assist.playbackEffects.replacesIdentityFeed)
    }

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

    func testZebraHandoffKeepsThePlayerUntilTheOverlayBakes() {
        var fx = LiveImageEffects()
        fx.zebra = true
        let waiting = PlaybackFeedHandoff.plan(
            effects: fx, overlayOnly: true, unmanagedBake: false, metalHasPresented: false)
        XCTAssertTrue(waiting.showPlayer, "identity stays on AVPlayerLayer")
        XCTAssertFalse(waiting.showFeed, "unpresented CAMetalLayer is a black plate")
        XCTAssertTrue(waiting.overlay)

        let landed = PlaybackFeedHandoff.plan(
            effects: fx, overlayOnly: true, unmanagedBake: false, metalHasPresented: true)
        XCTAssertTrue(landed.showPlayer)
        XCTAssertTrue(landed.showFeed, "stripes unhide only after the bake presents")
        XCTAssertTrue(landed.overlay)
    }

    func testLUTHandoffHidesThePlayerOnceMetalOwnsThePicture() {
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        XCTAssertTrue(fx.replacesIdentityFeed)

        let waiting = PlaybackFeedHandoff.plan(
            effects: fx, overlayOnly: false, unmanagedBake: true, metalHasPresented: false)
        XCTAssertTrue(waiting.showPlayer, "player stays until the LUT drawable lands")
        XCTAssertFalse(waiting.showFeed)
        XCTAssertFalse(waiting.overlay)

        let landed = PlaybackFeedHandoff.plan(
            effects: fx, overlayOnly: false, unmanagedBake: true, metalHasPresented: true)
        XCTAssertFalse(
            landed.showPlayer,
            "live hides the identity layer once Metal owns LUT replace; a second HEVC present is the hitch"
        )
        XCTAssertTrue(landed.showFeed)
        XCTAssertFalse(landed.overlay)
        XCTAssertTrue(
            landed.unmanaged,
            "LUT cube product presents unmanaged, same as live HevcDecoder")
    }

    func testPlaybackDisplayLinkDoesNotCapTheCubeAtTwentyFour() {
        XCTAssertGreaterThanOrEqual(
            PlaybackDisplayLink.pollRange.maximum, 60,
            "max 30 preferred 24 is the 22–23 fps LUT hitch; LUT-off is AVPlayerLayer at clip rate")
        XCTAssertNotEqual(PlaybackDisplayLink.pollRange.preferred, 24)
        XCTAssertGreaterThan(PlaybackDisplayLink.pollRange.minimum, 15)
        XCTAssertTrue(
            PlaybackDisplayLink.shouldPull(itemHasPresented: false, hasNewPixelBuffer: false),
            "until the first cube lands, keep pulling even without a new buffer")
        XCTAssertFalse(
            PlaybackDisplayLink.shouldPull(itemHasPresented: true, hasNewPixelBuffer: false),
            "after present, the cube only bakes a new player frame")
        XCTAssertTrue(
            PlaybackDisplayLink.shouldPull(itemHasPresented: true, hasNewPixelBuffer: true))
    }

    func testPlaybackVideoOutputGradesNativeYUVNotBGRA() {
        XCTAssertFalse(
            PlaybackVideoOutput.forcesRGBConversion,
            "32BGRA from AVPlayerItemVideoOutput converts every HEVC frame; live grades 420")
        XCTAssertEqual(
            PlaybackVideoOutput.pixelFormat,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        XCTAssertEqual(
            PlaybackVideoOutput.pixelBufferAttributes[
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

    func testPresentPolicyDrivesHandoffOwnership() {
        XCTAssertEqual(
            PlaybackFeedHandoff.replaceOwnsPicture(
                hasPresentedFrame: true, lastPresentWasOverlay: false),
            FeedPresentPolicy.replaceOwnsPicture(
                hasPresentedFrame: true, lastPresentWasOverlay: false))
        XCTAssertTrue(FeedPresentPolicy.unhideMetalBeforeBake(overlay: false))
        XCTAssertFalse(FeedPresentPolicy.unhideMetalBeforeBake(overlay: true))
        XCTAssertTrue(
            FeedPresentPolicy.shouldScheduleBake(enabled: true, hasDrawable: true))
        XCTAssertFalse(
            FeedPresentPolicy.shouldRender(
                attached: true, enabled: true, hidden: true, hasDrawable: true),
            "hidden replace drawable is the black well")
        XCTAssertTrue(
            FeedPresentPolicy.isDuplicateFrameTime(42, lastPresentedNs: 42))
        XCTAssertFalse(
            FeedPresentPolicy.isDuplicateFrameTime(0, lastPresentedNs: 42),
            "unknown timestamps must not skip")
    }

    func testLUTMustNotStealThePlayerOnAStaleOverlayBake() {
        XCTAssertFalse(
            PlaybackFeedHandoff.replaceOwnsPicture(
                hasPresentedFrame: true, lastPresentWasOverlay: true),
            "PEAK/FALSE/ZEBRA present must not hide AVPlayerLayer for LUT")
        XCTAssertFalse(
            PlaybackFeedHandoff.replaceOwnsPicture(
                hasPresentedFrame: false, lastPresentWasOverlay: false),
            "LUT stays off the player until its own bake lands")
        XCTAssertTrue(
            PlaybackFeedHandoff.replaceOwnsPicture(
                hasPresentedFrame: true, lastPresentWasOverlay: false))
    }

    func testNextClipForcesAPullUntilTheHostPresents() {
        XCTAssertTrue(
            PlaybackFeedHandoff.shouldForcePull(
                effectsChanged: false, hasLastBuffer: true, metalHasPresented: true,
                itemHasPresented: false),
            "stale lastBuffer + metal from the previous clip must not skip the new item")
        XCTAssertTrue(
            PlaybackFeedHandoff.shouldForcePull(
                effectsChanged: false, hasLastBuffer: true, metalHasPresented: false,
                itemHasPresented: false),
            "prepare drops metal ownership — LUT must bake the new item without toggling the chip")
        XCTAssertFalse(
            PlaybackFeedHandoff.shouldForcePull(
                effectsChanged: false, hasLastBuffer: true, metalHasPresented: true,
                itemHasPresented: true))
        XCTAssertTrue(
            PlaybackFeedHandoff.shouldForcePull(
                effectsChanged: false, hasLastBuffer: false, metalHasPresented: true,
                itemHasPresented: true))
        XCTAssertTrue(
            PlaybackFeedHandoff.shouldForcePull(
                effectsChanged: true, hasLastBuffer: true, metalHasPresented: true,
                itemHasPresented: true))
    }

    func testShouldAdoptHostPrefersTheNewerRepresentable() {
        XCTAssertTrue(
            PlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 1, currentGeneration: nil, isSameHost: false),
            "first host always binds")
        XCTAssertTrue(
            PlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 1, currentGeneration: 1, isSameHost: true),
            "SwiftUI updateUIView on the bound host must keep it")
        XCTAssertTrue(
            PlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 2, currentGeneration: 1, isSameHost: false))
        XCTAssertFalse(
            PlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 1, currentGeneration: 2, isSameHost: false),
            "the departing next-clip identity must not steal LUT present")
        XCTAssertFalse(
            PlaybackFeedHandoff.shouldAdoptHost(
                incomingGeneration: 2, currentGeneration: 2, isSameHost: false),
            "equal generation on a different view is the outgoing slide twin")
    }

    func testAssistsOffHandoffHidesTheMetalFeed() {
        let plan = PlaybackFeedHandoff.plan(
            effects: LiveImageEffects(), overlayOnly: false, unmanagedBake: false,
            metalHasPresented: true)
        XCTAssertTrue(plan.showPlayer)
        XCTAssertFalse(plan.showFeed)
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
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        let waiting = PlaybackFeedHandoff.plan(
            effects: fx, overlayOnly: false, unmanagedBake: false, metalHasPresented: false)
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
        var fx = LiveImageEffects()
        fx.zebra = true
        session.setEffects(fx, transfer: .rec709, sampleBus: LiveFrameSampleBus())
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
        var fx = LiveImageEffects()
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
        var fx = LiveImageEffects()
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
            PlaybackFeedHandoff.presentUnmanaged(overlay: false, unmanagedBake: true),
            "LUT cube product is NSNull, same as live HevcDecoder")
        XCTAssertFalse(
            PlaybackFeedHandoff.presentUnmanaged(overlay: false, unmanagedBake: false),
            "identity fallback stays color-managed")
        XCTAssertTrue(
            PlaybackFeedHandoff.presentUnmanaged(overlay: true, unmanagedBake: false),
            "zebra / peaking / false colour overlay is unmanaged chrome")
    }

    func testLUTBakeOfRec709PlayerFrameKeepsLuma() throws {
        let lumas = try Self.measureLUTBakeLumas(buffer: Self.rec709TaggedBGRA(code: 78))
        XCTAssertGreaterThan(lumas.unmanaged, 0.04)
        XCTAssertGreaterThan(lumas.managed, 0.04)
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

    func testUnmanagedLUTBakeOfRec709Tagged420KeepsLuma() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal required")
        }
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        let buffer = ScopeTestBuffers.make420v(width: 32, height: 32, leftY: 128, rightY: 128)
        CVBufferSetAttachment(
            buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate)
        CVBufferSetAttachment(
            buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2,
            .shouldPropagate)
        CVBufferSetAttachment(
            buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            .shouldPropagate)
        let source = CIImage(cvPixelBuffer: buffer, options: LiveMonitorWorkingSpace.imageOptions)
        let identity = CIImage(cvPixelBuffer: buffer)
        let product = LiveMonitorCompositor.applyProduct(to: source, effects: fx, display: identity)
        XCTAssertTrue(product.unmanagedBake)

        let baker = FeedFrameBaker(device: device)
        let drawable = CGSize(width: 32, height: 32)
        let done = expectation(description: "420 lut bake")
        baker.scheduleBake(
            image: product.image, drawableSize: drawable, pixelFormat: .bgra8Unorm,
            unmanaged: true
        ) {
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        guard let texture = baker.bakedTexture(for: drawable, pixelFormat: .bgra8Unorm) else {
            XCTFail("baker must publish the 420 LUT texture")
            return
        }
        defer { baker.releaseBakedTexture(texture) }
        guard
            let wrapped = CIImage(
                mtlTexture: texture, options: LiveMonitorWorkingSpace.imageOptions)
        else {
            XCTFail("CIImage(mtlTexture:) must wrap the bake")
            return
        }
        XCTAssertGreaterThan(
            Self.sampleLuma(wrapped), 0.04,
            "unmanaged LUT of Rec.709-tagged 420 (live-shaped player output) must not present black"
        )
    }

    func testUnmanagedLUTBakeOfRec709TaggedBGRAKeepsLuma() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal required")
        }
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        fx.colorMode = .dLog2
        let buffer = Self.rec709TaggedBGRA(code: 78)
        let source = CIImage(cvPixelBuffer: buffer, options: LiveMonitorWorkingSpace.imageOptions)
        let identity = CIImage(cvPixelBuffer: buffer)
        let product = LiveMonitorCompositor.applyProduct(to: source, effects: fx, display: identity)
        XCTAssertTrue(product.unmanagedBake)

        let baker = FeedFrameBaker(device: device)
        let drawable = CGSize(width: 32, height: 32)
        let done = expectation(description: "lut bake")
        baker.scheduleBake(
            image: product.image, drawableSize: drawable, pixelFormat: .bgra8Unorm,
            unmanaged: product.unmanagedBake
        ) {
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        guard let texture = baker.bakedTexture(for: drawable, pixelFormat: .bgra8Unorm) else {
            XCTFail("baker must publish the LUT texture")
            return
        }
        defer { baker.releaseBakedTexture(texture) }
        guard
            let wrapped = CIImage(
                mtlTexture: texture, options: LiveMonitorWorkingSpace.imageOptions)
        else {
            XCTFail("CIImage(mtlTexture:) must wrap the bake")
            return
        }
        let luma = Self.sampleLuma(wrapped)
        XCTAssertGreaterThan(
            luma, 0.04,
            "unmanaged LUT of Rec.709-tagged BGRA (AVPlayer output) must not present black")
    }

    func testUntaggedCloneLetsUnmanagedLUTBakeKeepLumaFromIOSurface() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal required")
        }
        let made = ScopeTestBuffers.makeIOSurfaceBGRA(width: 32, height: 32, left: 78, right: 78)
        guard made.filled else { throw XCTSkip("host cannot CPU-write IOSurface BGRA") }
        CVBufferSetAttachment(
            made.buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate)
        CVBufferSetAttachment(
            made.buffer, kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        let cloned = PlaybackPixelCopy.untaggedBGRA(made.buffer)
        XCTAssertNil(
            CVBufferGetAttachment(cloned, kCVImageBufferColorPrimariesKey, nil),
            "clone must drop Rec.709 tags so NSNull present is not a black well")

        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        let source = CIImage(cvPixelBuffer: cloned, options: LiveMonitorWorkingSpace.imageOptions)
        let product = LiveMonitorCompositor.applyProduct(to: source, effects: fx, display: source)
        XCTAssertTrue(product.unmanagedBake)

        let baker = FeedFrameBaker(device: device)
        let drawable = CGSize(width: 32, height: 32)
        let done = expectation(description: "cloned lut bake")
        baker.scheduleBake(
            image: product.image, drawableSize: drawable, pixelFormat: .bgra8Unorm,
            unmanaged: true
        ) {
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        guard let texture = baker.bakedTexture(for: drawable, pixelFormat: .bgra8Unorm) else {
            XCTFail("baker must publish the cloned LUT texture")
            return
        }
        defer { baker.releaseBakedTexture(texture) }
        guard
            let wrapped = CIImage(
                mtlTexture: texture, options: LiveMonitorWorkingSpace.imageOptions)
        else {
            XCTFail("CIImage(mtlTexture:) must wrap the bake")
            return
        }
        XCTAssertGreaterThan(Self.sampleLuma(wrapped), 0.04)
    }

    private static func measureLUTBakeLumas(buffer: CVPixelBuffer) throws -> (
        managed: Float, unmanaged: Float
    ) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal required")
        }
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        fx.colorMode = .dLog2
        let source = CIImage(cvPixelBuffer: buffer, options: LiveMonitorWorkingSpace.imageOptions)
        let identity = CIImage(cvPixelBuffer: buffer)
        let product = LiveMonitorCompositor.applyProduct(to: source, effects: fx, display: identity)
        XCTAssertTrue(product.unmanagedBake)
        let baker = FeedFrameBaker(device: device)
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
                    mtlTexture: texture, options: LiveMonitorWorkingSpace.imageOptions)
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
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: code, width: width, height: height)
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
        let context = CIContext(options: LiveMonitorWorkingSpace.contextOptions)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        return (Float(bytes[0]) + Float(bytes[1]) + Float(bytes[2])) / (3 * 255)
    }
}
