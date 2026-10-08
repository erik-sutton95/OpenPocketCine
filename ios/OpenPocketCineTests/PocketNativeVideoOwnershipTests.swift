import AVFoundation
import CoreVideo
import Observation
import OpenCineAppKit
import OpenCineApple
import OpenCineCameraVocabulary
import OpenCineMedia
import OpenPocketViewCore
import XCTest
import OpenCineDJIApple

@testable import OpenPocketCine

/// SIMULATED source input exercises the actual app adapter and native publication owner.
@MainActor
final class PocketNativeVideoOwnershipTests: XCTestCase {
    func testRetiredRuntimeResetCannotEraseSuccessorSamples() async {
        let samples = LiveFrameSampleBus()
        let old = HevcDecoder()
        old.sampleBus = samples
        let successor = HevcDecoder()
        successor.sampleBus = samples
        let source = ScopeTestBuffers.makeEdgeBuffer()
        let delivered = expectation(description: "successor native source delivered")
        successor.onSourceFrame = { _ in delivered.fulfill() }
        successor.handleDecodedFrame(source)
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertTrue(samples.sourcePixelBuffer === source)

        old.reset()

        XCTAssertTrue(
            samples.sourcePixelBuffer === source,
            "Retiring the old runtime must leave its successor's publication intact")
        successor.reset()
    }

    func testLiveISOReportCannotCalibrateTheCoveredPlaybackSource() {
        let samples = LiveFrameSampleBus()
        let session = OpenPocketCine.CameraSession()
        let decoder = session.decoder
        decoder.sampleBus = samples
        let liveCeiling = samples.exposureCeiling
        let playback = samples.openSource(.playback)
        var exposure = [UInt8](repeating: 0, count: 46)
        exposure[7] = 1
        exposure[16] = 0x20
        exposure[17] = 0x03
        session.applyIncomingStatus(
            Duml.Frame(
                sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0, cmdId: 0x99,
                payload: SubscribePush.pack(name: "cam_expo_param", value: exposure)))

        XCTAssertEqual(session.captureControlState?.reported.iso, 800)
        XCTAssertEqual(
            liveCeiling.resolvedISO(), 800, "The report belongs to the live publication owner")
        XCTAssertEqual(
            playback.exposureCeiling.resolvedISO(), 1600, "A covered clip keeps its calibration")
        samples.closeSource(playback)
        decoder.close()
    }

    func testKnownReportSeedsOnlyTheAttachedAndReusedLiveSource() {
        let session = OpenPocketCine.CameraSession()
        let decoder = session.decoder
        var exposure = [UInt8](repeating: 0, count: 46)
        exposure[7] = 1
        exposure[16] = 0x20
        exposure[17] = 0x03
        session.applyIncomingStatus(
            Duml.Frame(
                sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0, cmdId: 0x99,
                payload: SubscribePush.pack(name: "cam_expo_param", value: exposure)))
        let samples = LiveFrameSampleBus()
        let playback = samples.openSource(.playback)
        decoder.bindSourcePublication(samples)
        XCTAssertEqual(playback.exposureCeiling.resolvedISO(), 1600)
        samples.closeSource(playback)
        XCTAssertEqual(
            samples.exposureCeiling.resolvedISO(), 800,
            "The report arrived before any source lease existed")

        let original = decoder.sourceToken
        decoder.reset()
        XCTAssertNotEqual(decoder.sourceToken, original)
        XCTAssertEqual(
            samples.exposureCeiling.resolvedISO(), 800,
            "A recovery reset reads the same owner's actual report")
        session.disconnect()
        XCTAssertEqual(
            samples.exposureCeiling.resolvedISO(), 1600,
            "A disconnected owner cannot reuse its previous camera observation")
        decoder.close()
    }

    func testBorrowedCoverAndReturnKeepTheTilePublicationAlive() async {
        let samples = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        decoder.bindSourcePublication(samples)
        let source = ScopeTestBuffers.makeEdgeBuffer()
        let delivered = expectation(description: "owned tile source delivered")
        decoder.onSourceFrame = { _ in delivered.fulfill() }
        decoder.handleDecodedFrame(source)
        await fulfillment(of: [delivered], timeout: 2)
        let token = decoder.sourceToken
        let borrowed = OpenPocketCine.CameraSession(borrowing: decoder, controlsOnly: true)
        let model = AppModel(session: borrowed)
        model.frameSamples = samples
        let camera = DjiAppleSighting(
            id: UUID(), name: "SIMULATED Pocket source",
            model: .resolve(modelId: 0x0020, name: "SIMULATED Pocket source"), modelId: 0x0020)
        borrowed.updateMultiview(camera: camera, driver: nil, status: CameraStatus())
        var releases = 0
        model.borrowMonitor(camera) {
            releases += 1
            borrowed.releaseMultiview()
        }

        for cover in [OpenCineAppKit.ShellModel.Cover.settings, .media] {
            model.shell.open(cover)
            model.shell.dismissCover()
            XCTAssertEqual(decoder.sourceToken, token)
            XCTAssertTrue(samples.sourcePixelBuffer === source)
        }
        model.disconnect()
        model.disconnect()
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(decoder.sourceToken, token)
        XCTAssertTrue(samples.sourcePixelBuffer === source)
        decoder.close()
    }

    func testRetiredDecoderCannotDetachSuccessorPictureHooksOrReopenAfterClose() {
        let picture = CIFeedView()
        let old = HevcDecoder()
        old.processedFeed = picture
        let successor = HevcDecoder()
        successor.processedFeed = picture

        old.close()
        old.reset()
        XCTAssertNil(old.sourceToken)
        XCTAssertNotNil(picture.onPresented)
        XCTAssertTrue(successor.processedFeed === picture)
        successor.close()
        XCTAssertNil(picture.onPresented)
    }

    func testOldPlaybackShutdownCannotClearItsSuccessorBundle() async throws {
        let samples = LiveFrameSampleBus()
        let old = PlaybackFeedSession()
        old.setEffects(
            MonitorFrameEffects(histogram: true).playbackFrameEffects, transfer: .rec709,
            sampleBus: samples)
        let oldItem = AVPlayerItem(asset: AVMutableComposition())
        old.prepare(oldItem)
        let successor = PlaybackFeedSession()
        successor.setEffects(
            MonitorFrameEffects(histogram: true).playbackFrameEffects, transfer: .rec709,
            sampleBus: samples)
        let fixture = try await PlaybackOutputFixture.make(in: self)
        defer { old.shutdown(); successor.shutdown(); fixture.close() }
        let successorItem = fixture.item
        fixture.prepare(successor)
        try await fixture.publishScopes(using: successor, samples: samples, in: self)
        XCTAssertTrue(oldItem.outputs.contains(where: { $0 === old.output }))
        XCTAssertTrue(successorItem.outputs.contains(where: { $0 === successor.output }))
        XCTAssertGreaterThan(samples.playbackBundle?.samples.histogramLuma[180] ?? 0, 0)

        old.shutdown()
        XCTAssertFalse(oldItem.outputs.contains(where: { $0 === old.output }))
        XCTAssertTrue(successorItem.outputs.contains(where: { $0 === successor.output }))
        XCTAssertGreaterThan(samples.playbackBundle?.samples.histogramLuma[180] ?? 0, 0)
        successor.shutdown()
        XCTAssertNil(samples.playbackBundle)
        XCTAssertFalse(samples.usesPlaybackSource)
    }

    func testNeutralSourceProfileRetainsMeasuredDJICalibrationGoldens() {
        let transfers: [MonitorTransfer] = [.rec709, .hdr, .dlog, .dlogm, .dlog2, .ilog]
        for iso in [50, 100, 200, 400, 800, 1600, 3200, 6400, 102_400] {
            for transfer in transfers {
                let legacy = DJIScopeExposureCeiling()
                let neutral = OpenCineMedia.ScopeExposureCeiling(
                    profile: PocketMonitorCalibration.clipProfile)
                legacy.setISO(iso)
                neutral.setISO(iso)
                XCTAssertEqual(
                    neutral.clipByte(transfer: transfer), legacy.clipByte(transfer: transfer))
                for tap: UInt8 in [0, 223, 224, 233, 247, 248, 254, 255] {
                    let original = legacy.observeTapMax(tap, transfer: transfer)
                    let moved = neutral.observeTapMax(tap, transfer: transfer)
                    XCTAssertEqual(moved.clip, original.clip)
                    XCTAssertEqual(moved.maxRose, original.maxRose)
                    XCTAssertEqual(
                        neutral.anchors(transfer: transfer), legacy.anchors(transfer: transfer))
                }
            }
        }
    }
}
