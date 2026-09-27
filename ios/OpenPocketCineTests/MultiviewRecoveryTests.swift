import OpenPocketViewCore
import UIKit
import XCTest

@testable import OpenPocketCine

@MainActor final class MultiviewRecoveryTests: XCTestCase {
    func testDelayedEnableGetsTheFullPictureDeadlineAfterReadinessReturns() {
        let request = Date(timeIntervalSinceReferenceDate: 100)
        let enable = request.addingTimeInterval(15)
        XCTAssertFalse(
            MultiviewSession.Tile.decoderRepairHasTime(
                requestedAt: request, sentAt: nil, now: request.addingTimeInterval(16)))
        for delay in [16.0, 25.0, 30.0] {
            XCTAssertTrue(
                MultiviewSession.Tile.decoderRepairHasTime(
                    requestedAt: request, sentAt: enable, now: request.addingTimeInterval(delay)),
                "Display/path readiness must not spend the camera's fresh-picture wait")
        }
        XCTAssertFalse(
            MultiviewSession.Tile.decoderRepairHasTime(
                requestedAt: request, sentAt: enable, now: request.addingTimeInterval(31)))
    }

    func testBlockedOrBackgroundedDecoderDeadlineDoesNotSpendARejoin() {
        for (sent, active, uninterrupted) in [
            (false, true, true), (true, false, false), (true, true, false),
        ] {
            let tile = MultiviewSession.Tile()
            var stalled = FeedWatchdog.Snapshot(
                now: 100, lastDecodedFrameAge: 10, lastVideoPacketAge: 0,
                lastAccessUnitAge: 0, lastStatusAge: 0, flowHealthy: true,
                pathReady: true, hasFormat: true, decoderFailed: false,
                live: true, sawPicture: true, secondsSinceLastEnable: 50,
                lastDecoderOutputAge: 10, decoderOutputExpected: true,
                referenceRecoveryNeeded: true)
            let previous = tile.recovery
            XCTAssertEqual(tile.recovery.action(stalled), .rebuildVTSession)
            XCTAssertFalse(
                tile.finishDecoderRepair(
                    previous: previous, sentAt: sent ? Date() : nil,
                    applicationActive: active, foregroundUnchanged: uninterrupted))
            stalled.now += FeedWatchdog.decoderRepairDeadline + 4
            XCTAssertEqual(
                tile.recovery.action(stalled), .rebuildVTSession,
                "A blocked enable or background interruption must retry decoder repair, not reconnect"
            )
        }
    }

    func testRetiredEndpointCannotChangeEitherCameraDecoder() {
        let first = MultiviewSession.Tile()
        let second = MultiviewSession.Tile()
        let retired = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "test")
        first.driver = retired
        first.bindPreviewInput(retired)
        let current = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "test")
        first.driver = current
        first.bindPreviewInput(current)
        retired.onVideoDiscontinuity?()
        XCTAssertFalse(first.decoder.awaitingIDR)
        XCTAssertFalse(second.decoder.awaitingIDR)
        current.onVideoDiscontinuity?()
        XCTAssertTrue(first.decoder.awaitingIDR)
        XCTAssertFalse(second.decoder.awaitingIDR)
        retired.close()
        current.close()
    }

    func testSuspendedDeliveryOverflowReachesTheTileRepairOwner() throws {
        let tile = MultiviewSession.Tile()
        let driver = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "test")
        tile.driver = driver
        tile.bindPreviewInput(driver)
        let host = DisplayLayerView(tile.decoder.displayLayer)
        host.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        host.layoutSubviews()
        defer {
            tile.decoder.reset()
            driver.close()
        }
        let assembler = SoftAPVideoAssembler()
        _ = assembler.ingest(HevcFixture.packet(0, HevcFixture.keyframe))
        // Suspension can let the receive queue outrun MainActor's AU delivery.
        for frame in 1...UInt8(SoftAPVideoAssembler.pendingLimit + 2) {
            _ = assembler.ingest(HevcFixture.packet(frame, HevcFixture.pFrame))
        }
        let batch = assembler.takeDelivery()
        XCTAssertTrue(batch.discontinuity)
        XCTAssertTrue(batch.awaitingRandomAccess)
        batch.deliver(
            onDiscontinuity: { driver.onVideoDiscontinuity?() },
            onAccessUnit: { driver.onAccessUnit?($0) })
        XCTAssertTrue(tile.hasPicture, "The retained frame should remain visible")
        XCTAssertTrue(
            tile.decoder.referenceRecoveryNeeded,
            "Multiview must forward the real receive queue's reference loss")

        // The queue still sees complete AUs but cannot deliver dependent frames.
        _ = assembler.ingest(HevcFixture.packet(60, HevcFixture.pFrame))
        XCTAssertTrue(assembler.takeDelivery().accessUnits.isEmpty)
        var snapshot = try XCTUnwrap(tile.watchdogSnapshot(now: Date(), pathReady: true))
        let arrival = assembler.snapshot()
        snapshot.lastVideoPacketAge = Date().timeIntervalSince(try XCTUnwrap(arrival.lastPacket))
        snapshot.lastAccessUnitAge = Date().timeIntervalSince(try XCTUnwrap(arrival.lastAU))
        snapshot.lastStatusAge = 0
        snapshot.flowHealthy = true
        snapshot.hadVideo = true
        XCTAssertEqual(
            tile.recovery.action(snapshot), .rebuildVTSession,
            "Fresh UDP must not hide a stopped picture after background delivery loss")
    }

    func testTileSnapshotIncludesDecoderLossEvenWithFreshTransport() throws {
        let tile = MultiviewSession.Tile()
        let driver = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "test")
        tile.driver = driver
        let host = DisplayLayerView(tile.decoder.displayLayer)
        host.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        host.layoutSubviews()
        defer {
            tile.decoder.reset()
            driver.close()
        }
        XCTAssertTrue(tile.decoder.decode(accessUnit: HevcFixture.keyframe))
        tile.hasPicture = true
        tile.decoder.noteCompressedDiscontinuity()
        let snapshot = try XCTUnwrap(tile.watchdogSnapshot(now: Date(), pathReady: true))
        XCTAssertTrue(snapshot.referenceRecoveryNeeded)
        XCTAssertTrue(snapshot.decoderOutputExpected)
        XCTAssertEqual(snapshot.repairReady, tile.decoder.isDisplayReady)
    }
}
