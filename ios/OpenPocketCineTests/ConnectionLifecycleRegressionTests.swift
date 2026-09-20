import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// Exercise the actual single-camera screen, including its warmup opacity,
/// panel coverage and UIViewRepresentable updates. Generic canvas identity
/// tests cannot establish that these production callers preserve the feed.
@MainActor
final class ConnectionLifecycleRegressionTests: XCTestCase {
    func testStatsAgingDoesNotReplaceAnEstablishedPictureWithStartupWaiting() async throws {
        let model = AppModel()
        let decoder = model.session.decoder
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        defer { model.session.disconnect() }
        XCTAssertTrue(model.session.isFeedWarming)
        try await presentRollingPictures(model)
        XCTAssertFalse(model.session.isFeedWarming)
        let heldPicture = try XCTUnwrap(decoder.lastPresentedAt)
        // CameraSession.publishPipelineStats -> refreshLinkHealth added this
        // age() call in UI 2.0. refreshFeedWarmup subsequently consumes these
        // exact values while the decoder retains its already presented image.
        model.session.refreshLinkHealth(at: Date.timeIntervalSinceReferenceDate + 3)
        XCTAssertEqual(decoder.lastPresentedAt, heldPicture)
        XCTAssertFalse(decoder.displayedImageRemoved)
        XCTAssertFalse(
            model.session.isFeedWarming,
            "An established monitor must keep its held picture instead of returning to startup Waiting"
        )
        XCTAssertEqual(model.session.liveFPS, "—", "Idle test session must lose its cached FPS")
        model.session.phase = .live
        model.session.startFeedRecovery { try? await Task.sleep(for: .seconds(30)) }
        model.session.refreshLinkHealth(at: Date.timeIntervalSinceReferenceDate + 3)
        XCTAssertEqual(
            model.session.liveFPS, "RECOV", "Recovery must remain visible in its own chrome")
        XCTAssertTrue(model.session.feedRecovering)
        XCTAssertFalse(model.session.isFeedWarming)
        model.session.disconnect()
        XCTAssertTrue(
            model.session.isFeedWarming, "A new connection must qualify its first picture")
    }

    func testOverflowRetainingAnOldIRAPCannotHideBlockedAdmissionFromRepair() throws {
        let assembler = SoftAPVideoAssembler()
        let decoder = HevcDecoder()
        let display = DisplayLayerView(decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        display.layoutSubviews()
        defer { decoder.reset() }
        XCTAssertFalse(decoder.nativeOutputExpected, "Exercise clean compressed HEVC, without VT")

        _ = assembler.ingest(packet(0, Self.syntheticKeyframe))
        for frame in UInt8(1)...10 {
            _ = assembler.ingest(packet(frame, Self.syntheticPFrame))
        }
        let retained = assembler.takeDelivery()
        XCTAssertTrue(retained.discontinuity)
        XCTAssertTrue(retained.awaitingRandomAccess)
        var discontinuities = 0
        retained.deliver(
            onDiscontinuity: {
                discontinuities += 1
                decoder.noteCompressedDiscontinuity()
            },
            onAccessUnit: { XCTAssertTrue(decoder.decode(accessUnit: $0)) })
        XCTAssertEqual(discontinuities, 1)
        XCTAssertNotNil(decoder.lastPresentedAt, "Retain the available picture while repairing")
        XCTAssertTrue(decoder.referenceRecoveryNeeded)

        for frame in UInt8(11)...15 {
            _ = assembler.ingest(packet(frame, Self.syntheticPFrame))
            XCTAssertTrue(assembler.takeDelivery().accessUnits.isEmpty)
        }
        let arriving = assembler.snapshot()
        XCTAssertGreaterThan(arriving.accessUnits, retained.accessUnits.count)
        XCTAssertNotNil(arriving.lastAU)
        let snapshot = FeedWatchdog.Snapshot(
            now: 20, lastDecodedFrameAge: 3,
            lastVideoPacketAge: Date().timeIntervalSince(try XCTUnwrap(arriving.lastPacket)),
            lastAccessUnitAge: Date().timeIntervalSince(try XCTUnwrap(arriving.lastAU)),
            lastStatusAge: 0, flowHealthy: true, pathReady: true,
            hasFormat: decoder.hasFormat, decoderFailed: decoder.isDecoderWedged,
            live: true, sawPicture: decoder.lastPresentedAt != nil,
            secondsSinceLastEnable: 20,
            lastDecoderOutputAge: decoder.nativeOutputAge,
            decoderOutputExpected: decoder.nativeOutputExpected,
            repairReady: decoder.isDisplayReady)
        var watchdog = FeedWatchdog()
        XCTAssertNotEqual(
            watchdog.tick(snapshot), .none,
            "A retained old IRAP must not suppress repair while admission still drops every new P-frame"
        )

        // The next genuine IRAP reopens admission and restores the decoder's
        // reference chain, without another discontinuity or speculative PLI.
        _ = assembler.ingest(packet(16, Self.syntheticKeyframe))
        _ = assembler.ingest(packet(17, Self.syntheticPFrame))
        let recovered = assembler.takeDelivery()
        XCTAssertFalse(recovered.awaitingRandomAccess)
        recovered.deliver(
            onDiscontinuity: {
                discontinuities += 1
                decoder.noteCompressedDiscontinuity()
            },
            onAccessUnit: { XCTAssertTrue(decoder.decode(accessUnit: $0)) })
        XCTAssertEqual(discontinuities, 1)
        XCTAssertFalse(decoder.referenceRecoveryNeeded)
        XCTAssertTrue(decoder.canReleaseIDRHold)
    }

    func testOverflowWithAFreshIRAPSuffixRestoresReferencesInTheSameDelivery() {
        let assembler = SoftAPVideoAssembler()
        let decoder = HevcDecoder()
        let display = DisplayLayerView(decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        display.layoutSubviews()
        defer { decoder.reset() }
        _ = assembler.ingest(packet(0, Self.syntheticKeyframe))
        for frame in UInt8(1)...6 {
            _ = assembler.ingest(packet(frame, Self.syntheticPFrame))
        }
        _ = assembler.ingest(packet(7, Self.syntheticKeyframe))
        for frame in UInt8(8)...10 {
            _ = assembler.ingest(packet(frame, Self.syntheticPFrame))
        }
        let suffix = assembler.takeDelivery()
        XCTAssertTrue(suffix.discontinuity)
        XCTAssertFalse(suffix.awaitingRandomAccess)
        XCTAssertEqual(suffix.accessUnits.count, 3)
        var discontinuities = 0
        suffix.deliver(
            onDiscontinuity: {
                discontinuities += 1
                decoder.noteCompressedDiscontinuity()
            },
            onAccessUnit: { XCTAssertTrue(decoder.decode(accessUnit: $0)) })
        XCTAssertEqual(discontinuities, 1)
        XCTAssertTrue(decoder.canReleaseIDRHold)
        XCTAssertFalse(decoder.referenceRecoveryNeeded)
        XCTAssertFalse(decoder.awaitingIDR, "A current IRAP must not be invalidated after delivery")
    }

    func testWaitingFeedReceivesPicturesAcrossSettingsAndGeometryChanges() async throws {
        let model = AppModel()
        model.assist.lutEnabled = false
        model.assist.histogram = true
        let decoder = model.session.decoder
        let host = UIHostingController(rootView: LiveViewScreen().environment(model))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
            model.session.disconnect()
        }

        try await settle(host.view)
        decoder.stopSimulatorSample()
        let original = try XCTUnwrap(displayHosts(in: host.view).first)
        XCTAssertEqual(displayHosts(in: host.view).count, 1)
        XCTAssertTrue(original.ownsDisplayLayer)
        XCTAssertTrue(decoder.isDisplayReady, "The zero-opacity waiting feed must still lay out")
        XCTAssertTrue(decoder.processedFeed === original.ciFeed)
        try await presentRollingPictures(model)
        XCTAssertFalse(model.session.isFeedWarming, "Healthy source pictures must dismiss Waiting")

        for (index, size) in [
            CGSize(width: 400, height: 800),
            CGSize(width: 800, height: 400),
            CGSize(width: 400, height: 800),
            CGSize(width: 800, height: 400),
        ].enumerated() {
            model.liveOperatorPanel = index.isMultiple(of: 2) ? .settings : nil
            window.frame.size = size
            host.view.frame = window.bounds
            try await settle(host.view)
            decoder.stopSimulatorSample()

            let displays = displayHosts(in: host.view)
            XCTAssertEqual(displays.count, 1)
            XCTAssertTrue(
                displays.first === original, "Settings/rotation must retain the native host")
            XCTAssertTrue(original.ownsDisplayLayer)
            XCTAssertTrue(decoder.processedFeed === original.ciFeed)
            XCTAssertTrue(decoder.sampleBus === model.frameSamples)
            XCTAssertTrue(decoder.isDisplayReady)
            XCTAssertTrue(original.ciFeed.isEnabled)
            let previous = decoder.lastSourceFrameAt
            try await presentRollingPictures(model)
            XCTAssertNotEqual(decoder.lastSourceFrameAt, previous)
            XCTAssertFalse(model.session.isFeedWarming)
        }
    }

    private func presentRollingPictures(_ model: AppModel) async throws {
        let decoder = model.session.decoder
        let first = Date()
        // The production warmup gate requires rolling intervals, not one
        // enqueue. Feed real assist completions into its real session callback.
        for _ in 0..<12 {
            decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
            try await Task.sleep(for: .milliseconds(40))
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while decoder.lastSourceFrameAt.map({ $0 >= first }) != true,
            ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(decoder.lastSourceFrameAt), first)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(decoder.lastPresentedAt), first)
    }

    private func settle(_ view: UIView) async throws {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        view.layoutIfNeeded()
    }

    private func displayHosts(in view: UIView) -> [DisplayLayerView] {
        (view as? DisplayLayerView).map { [$0] }
            ?? view.subviews.flatMap { displayHosts(in: $0) }
    }

    private func packet(_ frame: UInt8, _ accessUnit: [UInt8]) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 20)
        header[6] = 2
        header[16] = frame
        return header + accessUnit
    }

    // Synthetic gray 64x64 HEVC, generated with libx265, bframes=0 and a single
    // IDR. Excludes encoder metadata; these are not camera captures.
    private static let syntheticKeyframe: [UInt8] = [
        "40010c01ffff01600000030090000003000003001eba0240",
        "42010101600000030090000003000003001ea020810596e92930bc05a02000000300200000030321",
        "4401c073c089",
        "2801ac76071c24748e",
    ].flatMap { [UInt8]([0, 0, 0, 1]) + bytes($0) }
    private static let syntheticPFrame = [UInt8]([0, 0, 0, 1]) + bytes("0201d0097883b0a098")

    private static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)!
        }
    }
}
