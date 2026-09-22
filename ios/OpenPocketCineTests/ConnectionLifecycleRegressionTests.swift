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
        for frame in 1...UInt8(SoftAPVideoAssembler.pendingLimit + 2) {
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

        for frame in UInt8(SoftAPVideoAssembler.pendingLimit + 3)...UInt8(SoftAPVideoAssembler.pendingLimit + 7) {
            _ = assembler.ingest(packet(frame, Self.syntheticPFrame))
            XCTAssertTrue(assembler.takeDelivery().accessUnits.isEmpty)
        }
        let arriving = assembler.snapshot()
        XCTAssertGreaterThan(arriving.accessUnits, retained.accessUnits.count)
        XCTAssertNotNil(arriving.lastAU)
        let snapshot = FeedWatchdog.Snapshot(
            now: 20, lastDecodedFrameAge: 0.239,
            lastVideoPacketAge: Date().timeIntervalSince(try XCTUnwrap(arriving.lastPacket)),
            lastAccessUnitAge: Date().timeIntervalSince(try XCTUnwrap(arriving.lastAU)),
            lastStatusAge: 0, flowHealthy: true, pathReady: true,
            hasFormat: decoder.hasFormat, decoderFailed: decoder.isDecoderWedged,
            live: true, sawPicture: decoder.lastPresentedAt != nil,
            secondsSinceLastEnable: 20,
            lastDecoderOutputAge: decoder.nativeOutputAge,
            decoderOutputExpected: decoder.nativeOutputExpected,
            referenceRecoveryNeeded: decoder.referenceRecoveryNeeded,
            repairReady: decoder.isDisplayReady)
        var watchdog = FeedWatchdog()
        XCTAssertEqual(
            watchdog.tick(snapshot), .rebuildVTSession,
            "Known rejected references must not wait two seconds to infer native-output silence"
        )

        // The next genuine IRAP reopens admission and restores the decoder's
        // reference chain, without another discontinuity or speculative PLI.
        _ = assembler.ingest(packet(UInt8(SoftAPVideoAssembler.pendingLimit + 8), Self.syntheticKeyframe))
        _ = assembler.ingest(packet(UInt8(SoftAPVideoAssembler.pendingLimit + 9), Self.syntheticPFrame))
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

    func testInvalidSessionAfterPictureIsKnownReferenceLoss() {
        let decoder = HevcDecoder()
        let display = DisplayLayerView(decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        display.layoutSubviews()
        defer { decoder.reset() }
        XCTAssertTrue(decoder.decode(accessUnit: Hevc.stripDjiMarker(Self.syntheticKeyframe)))
        XCTAssertNotNil(decoder.lastPresentedAt)
        XCTAssertFalse(decoder.referenceRecoveryNeeded)
        decoder.noteDecodeError(status: -12903, origin: "callback")
        XCTAssertTrue(
            decoder.referenceRecoveryNeeded,
            "-12903 rejects every later frame; the watchdog must not wait 2 s to infer it")
    }

    func testOverflowWithAFreshIRAPSuffixRestoresReferencesInTheSameDelivery() {
        let assembler = SoftAPVideoAssembler()
        let decoder = HevcDecoder()
        let display = DisplayLayerView(decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        display.layoutSubviews()
        defer { decoder.reset() }
        _ = assembler.ingest(packet(0, Self.syntheticKeyframe))
        for frame in 1...UInt8(SoftAPVideoAssembler.pendingLimit - 2) {
            _ = assembler.ingest(packet(frame, Self.syntheticPFrame))
        }
        _ = assembler.ingest(packet(UInt8(SoftAPVideoAssembler.pendingLimit - 1), Self.syntheticKeyframe))
        for frame in UInt8(SoftAPVideoAssembler.pendingLimit)...UInt8(SoftAPVideoAssembler.pendingLimit + 2) {
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
        var watchdog = FeedWatchdog()
        let healthy = FeedWatchdog.Snapshot(
            now: 20, lastDecodedFrameAge: 0.01,
            lastVideoPacketAge: 0.01, lastAccessUnitAge: 0.01, lastStatusAge: 0.01,
            flowHealthy: true, pathReady: true, hasFormat: decoder.hasFormat,
            decoderFailed: decoder.isDecoderWedged, live: true,
            sawPicture: decoder.lastPresentedAt != nil,
            lastDecoderOutputAge: decoder.nativeOutputAge,
            decoderOutputExpected: decoder.nativeOutputExpected,
            referenceRecoveryNeeded: decoder.referenceRecoveryNeeded,
            repairReady: decoder.isDisplayReady)
        XCTAssertEqual(
            watchdog.tick(healthy), .none, "A fresh IRAP suffix needs no speculative PLI")
    }

    func testIntentionalReferenceResetWithRetainedPictureDoesNotInventKnownLoss() throws {
        let decoder = HevcDecoder()
        let display = DisplayLayerView(decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        display.layoutSubviews()
        defer { decoder.reset() }
        decoder.noteCompressedDiscontinuity()
        XCTAssertFalse(
            decoder.referenceRecoveryNeeded, "Cold startup has no good references to lose")
        XCTAssertTrue(decoder.decode(accessUnit: Self.syntheticKeyframe))
        let heldPicture = try XCTUnwrap(decoder.lastPresentedAt)
        XCTAssertTrue(decoder.canReleaseIDRHold)
        decoder.flushForRecovery()
        XCTAssertEqual(decoder.lastPresentedAt, heldPicture)
        XCTAssertFalse(decoder.canReleaseIDRHold)
        decoder.noteCompressedDiscontinuity()
        XCTAssertFalse(
            decoder.referenceRecoveryNeeded,
            "Intentional replacement already owns its missing references")
        XCTAssertFalse(decoder.rebuildPresentationIfNeeded(referenceLossOnly: true))
    }

    func testFreshIRAPBeforeScheduledLossRepairDoesNotRebuildPresentation() throws {
        let decoder = HevcDecoder()
        let display = DisplayLayerView(decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        display.layoutSubviews()
        defer { decoder.reset() }
        XCTAssertTrue(decoder.decode(accessUnit: Self.syntheticKeyframe))
        decoder.noteCompressedDiscontinuity()
        XCTAssertTrue(decoder.referenceRecoveryNeeded)
        // The watchdog has requested repair, but its MainActor task has not
        // executed. A spontaneous current IRAP wins that scheduling interval.
        XCTAssertTrue(decoder.decode(accessUnit: Self.syntheticKeyframe))
        let generation = decoder.sourceFrameGeneration
        XCTAssertFalse(decoder.rebuildPresentationIfNeeded(referenceLossOnly: true))
        XCTAssertEqual(decoder.sourceFrameGeneration, generation)
        XCTAssertTrue(decoder.canReleaseIDRHold)
        XCTAssertFalse(decoder.awaitingIDR)
        decoder.noteCompressedDiscontinuity()
        XCTAssertTrue(decoder.rebuildPresentationIfNeeded(referenceLossOnly: true))
        XCTAssertTrue(
            decoder.referenceRecoveryNeeded, "A spent repair keeps its loss until a current IRAP")
        decoder.reset()
        XCTAssertFalse(decoder.referenceRecoveryNeeded)
    }

    func testLostFormatWithFreshPFramesCannotStrandAnEstablishedDecoder() throws {
        let decoder = HevcDecoder()
        let display = DisplayLayerView(decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        display.layoutSubviews()
        defer { decoder.reset() }
        XCTAssertTrue(decoder.decode(accessUnit: Self.syntheticKeyframe))
        let heldPicture = try XCTUnwrap(decoder.lastPresentedAt)
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        XCTAssertTrue(decoder.nativeOutputExpected)

        // A failed display path calls this same format reset. Fresh inter-frames
        // cannot supply the missing parameter sets or rebuild its reference chain.
        decoder.flushForRecovery()
        XCTAssertFalse(decoder.decode(accessUnit: Self.syntheticPFrame))
        XCTAssertFalse(decoder.hasFormat)
        XCTAssertTrue(decoder.nativeOutputExpected)
        XCTAssertEqual(decoder.lastPresentedAt, heldPicture)
        var watchdog = FeedWatchdog()
        let snapshot = FeedWatchdog.Snapshot(
            now: 100, lastDecodedFrameAge: 3,
            lastVideoPacketAge: 0.01, lastAccessUnitAge: 0.01, lastStatusAge: 0.01,
            flowHealthy: true, pathReady: true, hasFormat: decoder.hasFormat,
            decoderFailed: decoder.isDecoderWedged, live: true,
            sawPicture: decoder.lastPresentedAt != nil, secondsSinceLastEnable: 20,
            lastDecoderOutputAge: decoder.nativeOutputAge,
            decoderOutputExpected: decoder.nativeOutputExpected,
            referenceRecoveryNeeded: decoder.referenceRecoveryNeeded,
            repairReady: decoder.isDisplayReady)
        XCTAssertEqual(watchdog.tick(snapshot), .rebuildVTSession)
        XCTAssertTrue(decoder.rebuildPresentation())
        XCTAssertEqual(decoder.lastPresentedAt, heldPicture)
        XCTAssertTrue(decoder.isPresentationReady, "The existing owner can request fresh format")
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
        let requiredPresentations = LiveFeedWarmup.minimumRollingIntervals + 1
        var completedPresentations = 0
        let sessionPresentedFrame = decoder.onPresentedFrame
        decoder.onPresentedFrame = {
            // Preserve the real session callback that records rolling FPS and
            // dismisses warmup. Only sampled source presentations qualify;
            // raw sourcePresentations also counts identity-layer enqueues.
            sessionPresentedFrame?()
            if decoder.lastSourceFrameAt.map({ $0 >= first }) == true {
                completedPresentations += 1
            }
        }
        defer { decoder.onPresentedFrame = sessionPresentedFrame }

        // Submission is not completion: assist work and display backpressure
        // can discard early frames while the hosted view starts. Keep feeding
        // at 25 Hz until the real pipeline produces the required intervals.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while completedPresentations < requiredPresentations, ContinuousClock.now < deadline {
            decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertGreaterThanOrEqual(
            completedPresentations, requiredPresentations,
            "The real session must receive a rolling run of presented frames before checking warmup"
        )
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
