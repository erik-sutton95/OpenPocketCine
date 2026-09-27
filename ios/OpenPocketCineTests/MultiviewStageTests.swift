import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor final class MultiviewStageTests: XCTestCase {
    func testBLEDiscoveryFollowsAddAndConnectDemand() {
        typealias S = MultiviewSession
        XCTAssertTrue(
            S.needsDiscovery(
                running: true, applicationActive: true, hasEmptySlot: true, connecting: false),
            "an empty slot can open the Add picker")
        XCTAssertFalse(
            S.needsDiscovery(
                running: true, applicationActive: true, hasEmptySlot: false, connecting: false),
            "a full, settled stage has no discovery consumer")
        XCTAssertTrue(
            S.needsDiscovery(
                running: true, applicationActive: false, hasEmptySlot: false, connecting: true),
            "scan stays up until a connecting camera finishes")
        XCTAssertFalse(
            S.needsDiscovery(
                running: true, applicationActive: false, hasEmptySlot: true, connecting: false))
        XCTAssertFalse(
            S.needsDiscovery(
                running: false, applicationActive: true, hasEmptySlot: true, connecting: true))
    }

    func testTimecodeRequiresCameraReportAndIsHiddenOnNano() {
        let tile = MultiviewSession.Tile()
        for name in ["OsmoPocket3-Test", "OsmoPocket4P-Test", "OsmoNano-Test"] {
            tile.camera = FoundCamera(
                id: UUID(), name: name,
                model: .resolve(modelId: nil, name: name), modelId: nil)
            tile.settings.timecode = nil
            XCTAssertNil(tile.timecodeReadout)
            tile.settings.timecode = "01:02:03:04"
            XCTAssertEqual(tile.timecodeReadout, name.contains("Nano") ? nil : "01:02:03")
        }
    }

    func testPocketTileCompensatesSelfiePoseOnlyWithCameraFlipOff() {
        let tile = MultiviewSession.Tile()
        tile.camera = FoundCamera(
            id: UUID(), name: "Test Pocket",
            model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22)
        let yaw = UInt16(bitPattern: Int16(-1800))
        var payload = [UInt8](repeating: 0, count: 12)
        payload[4] = UInt8(truncatingIfNeeded: yaw)
        payload[5] = UInt8(truncatingIfNeeded: yaw >> 8)
        tile.updateSettings(
            .init(sender: 0, receiver: 0, seq: 1, flags: 0, cmdSet: 4, cmdId: 5, payload: payload))
        XCTAssertTrue(tile.decoder.poseViewFlip)
        tile.updateSettings(
            .init(
                sender: 0, receiver: 0, seq: 2, flags: 0xC0, cmdSet: 2, cmdId: 0x8E,
                payload: [0, 0, 1, 0x38, 0, 1, 1]))
        XCTAssertFalse(tile.decoder.poseViewFlip)
        tile.updateSettings(
            .init(
                sender: 0, receiver: 0, seq: 3, flags: 0xC0, cmdSet: 2, cmdId: 0x8E,
                payload: [0, 0, 1, 0x38, 0, 1, 0]))
        XCTAssertTrue(tile.decoder.poseViewFlip)
        XCTAssertFalse(MultiviewSession.Tile().decoder.poseViewFlip)
    }

    private func assign(_ tile: MultiviewSession.Tile, recording: Bool, available: Bool) {
        tile.camera = FoundCamera(
            id: UUID(), name: "Test camera", model: .resolve(modelId: 0x19, name: "OsmoNano-Test"),
            modelId: 0x19)
        tile.recordingObservation = (recording, Date())
        tile.recordingAvailable = available
    }
    func testUnavailableRecordingCameraKeepsStopIntentAndBlocksGroupCommand() {
        let session = MultiviewSession()
        assign(session.tiles[0], recording: true, available: false)
        assign(session.tiles[1], recording: false, available: true)
        XCTAssertTrue(session.anyRecording)
        XCTAssertFalse(session.canRecordTogether)
        session.tiles[0].recordingAvailable = true
        XCTAssertTrue(session.canRecordTogether)
        session.tiles[1].recordingBusy = true
        XCTAssertFalse(session.canRecordTogether)
    }
    func testChangingNetworkClearsUnrelatedPassword() {
        let session = MultiviewSession()
        session.ssid = "Old test network"
        session.password = "old-test-password"
        session.selectNetwork("New test network \(UUID().uuidString)")
        XCTAssertEqual(session.password, "")
    }

    func testAutoLUTFollowsEachTilesCameraColorIndependently() {
        let session = MultiviewSession()
        let nano = session.tiles[0]
        assign(nano, recording: false, available: true)
        nano.settings.colorMode = .dLogM
        XCTAssertTrue(nano.lutEnabled)
        nano.updateLUT()
        XCTAssertGreaterThan(nano.effects.lutDimension, 0)
        XCTAssertEqual(session.tiles[1].effects.lutDimension, 0)
        nano.settings.colorMode = .normal
        nano.updateLUT()
        XCTAssertEqual(nano.effects.lutDimension, 0)
        XCTAssertTrue(nano.lutEnabled)
    }

    func testRecoveryDoesNotResetHealthyVideoForStalePresentation() {
        var recovery = MultiviewRecovery()
        let snapshot = FeedWatchdog.Snapshot(
            now: 100, lastDecodedFrameAge: 20, lastVideoPacketAge: 0.01,
            lastStatusAge: 0.1, flowHealthy: true, pathReady: true, hasFormat: true,
            decoderFailed: false, live: true, sawPicture: true,
            secondsSinceLastEnable: 50)
        XCTAssertEqual(recovery.action(snapshot), .none)
    }
    func testFirstPictureFailureEscalatesBeyondBaseCooldown() {
        var recovery = MultiviewRecovery()
        func snapshot(_ time: Double) -> FeedWatchdog.Snapshot {
            FeedWatchdog.Snapshot(
                now: time, lastDecodedFrameAge: nil, lastVideoPacketAge: nil,
                lastStatusAge: nil, flowHealthy: true, pathReady: true, hasFormat: false,
                decoderFailed: false, live: true, sawPicture: false, hadVideo: false,
                secondsSinceLastEnable: 50)
        }
        XCTAssertEqual(recovery.action(snapshot(100)), .resendLiveViewEnable)
        XCTAssertEqual(recovery.action(snapshot(110)), .reopenDatalink)
        XCTAssertEqual(recovery.action(snapshot(120)), .none)
        var noNetwork = snapshot(130)
        noNetwork.pathReady = false
        XCTAssertEqual(recovery.action(noNetwork), .none)
        var recentEnable = snapshot(130)
        recentEnable.secondsSinceLastEnable = 1
        XCTAssertEqual(recovery.action(recentEnable), .none)
        XCTAssertEqual(recovery.action(snapshot(130)), .fullSessionRejoin)
    }

    func testBorrowedLiveViewDoesNotOwnOrCloseTileTransport() {
        let tile = MultiviewSession.Tile()
        assign(tile, recording: false, available: true)
        let driver = DatalinkDriver(
            port: 9004, tcpPoke: false, pairingToken: "test", stationHost: "192.168.1.10")
        let borrowed = CameraSession(borrowing: tile.decoder)
        borrowed.updateMultiview(camera: tile.camera!, driver: driver, status: tile.settings)
        XCTAssertTrue(borrowed.decoder === tile.decoder)
        XCTAssertTrue(borrowed.datalink === driver)
        borrowed.disconnect()
        XCTAssertNil(borrowed.datalink)
        XCTAssertFalse(driver.isClosed)
        driver.close()
    }
    func testLeavingBorrowedLiveViewCancelsProgrammedMove() async throws {
        let decoder = HevcDecoder()
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        let borrowed = CameraSession(borrowing: decoder)
        let driver = DatalinkDriver(
            port: 9004, tcpPoke: false, pairingToken: "test", stationHost: "192.168.1.10")
        defer {
            borrowed.releaseMultiview()
            driver.close()
            decoder.reset()
        }
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, decoder.lastPresentedAt == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(decoder.lastPresentedAt)
        let camera = FoundCamera(
            id: UUID(), name: "OsmoPocket4P-Test",
            model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22)
        borrowed.updateMultiview(camera: camera, driver: driver, status: CameraStatus())
        borrowed.receiveMultiview(
            .init(
                sender: 0, receiver: 0, seq: 1, flags: 0, cmdSet: 4, cmdId: 5,
                payload: [UInt8](repeating: 0, count: 22)))
        let start = try XCTUnwrap(borrowed.freshGimbalWaypoint)
        var end = start
        end.yawDeg += 10
        borrowed.gimbalProgram = GimbalProgram(a: start, b: end)
        borrowed.runProgrammedMove()
        XCTAssertTrue(borrowed.gimbalMoveRunning, borrowed.controlNote ?? "Move did not start")
        XCTAssertEqual(borrowed.gimbalStartCountdown, 3)

        borrowed.releaseMultiview()

        XCTAssertFalse(borrowed.gimbalMoveRunning)
        XCTAssertNil(borrowed.gimbalStartCountdown)
        XCTAssertNil(borrowed.datalink)
        XCTAssertFalse(driver.isClosed, "The tile still owns its transport")
    }

    func testBorrowedLiveViewCannotStartSharingOrChangeItsPreference() {
        let model = AppModel()
        model.session = CameraSession(borrowing: HevcDecoder())
        model.session.updateMultiview(
            camera: FoundCamera(
                id: UUID(), name: "OsmoPocket4P-Test",
                model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22),
            driver: nil, status: CameraStatus())
        let savedPreference = OperatorPrefs.shareThisFeed
        model.shareThisFeed = false
        model.setShareThisFeed(true)
        XCTAssertFalse(model.shareThisFeed)
        XCTAssertEqual(OperatorPrefs.shareThisFeed, savedPreference)

        // Automatic startup must also reject a previously saved sharing preference.
        model.shareThisFeed = true
        model.startRelayHost()
        XCTAssertNil(model.session.decoder.onIdentityFrame)
        XCTAssertNil(model.session.decoder.onIdentityOrientation)
    }

    func testReplacingTileDriverDetachesBorrowedControlsUntilVerified() {
        let tile = MultiviewSession.Tile()
        let model = AppModel()
        model.session = CameraSession(borrowing: tile.decoder)
        tile.liveModel = model
        let first = DatalinkDriver(
            port: 9004, tcpPoke: false, pairingToken: "test", stationHost: "192.168.1.10")
        let next = DatalinkDriver(
            port: 9004, tcpPoke: false, pairingToken: "test", stationHost: "192.168.1.11")
        model.session.datalink = first
        tile.driver = next
        XCTAssertNil(model.session.datalink)
        first.close()
        next.close()
    }

}
