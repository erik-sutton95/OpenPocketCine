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
        _ = assembler.ingest(packet(0, Self.keyframe))
        // Suspension can let the receive queue outrun MainActor's AU delivery.
        for frame in 1...UInt8(SoftAPVideoAssembler.pendingLimit + 2) {
            _ = assembler.ingest(packet(frame, Self.pFrame))
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
        _ = assembler.ingest(packet(60, Self.pFrame))
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
        XCTAssertTrue(tile.decoder.decode(accessUnit: Self.keyframe))
        tile.hasPicture = true
        tile.decoder.noteCompressedDiscontinuity()
        let snapshot = try XCTUnwrap(tile.watchdogSnapshot(now: Date(), pathReady: true))
        XCTAssertTrue(snapshot.referenceRecoveryNeeded)
        XCTAssertTrue(snapshot.decoderOutputExpected)
        XCTAssertEqual(snapshot.repairReady, tile.decoder.isDisplayReady)
    }

    private func packet(_ frame: UInt8, _ accessUnit: [UInt8]) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 20)
        header[6] = 2
        header[16] = frame
        return header + accessUnit
    }

    // Synthetic gray 64x64 HEVC (libx265); no camera captures or identifiers.
    private static let keyframe: [UInt8] = [
        "40010c01ffff01600000030090000003000003001eba0240",
        "42010101600000030090000003000003001ea020810596e92930bc05a02000000300200000030321",
        "4401c073c089", "2801ac76071c24748e",
    ].flatMap { [UInt8]([0, 0, 0, 1]) + bytes($0) }
    private static let pFrame = [UInt8]([0, 0, 0, 1]) + bytes("0201d0097883b0a098")
    private static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }
}
