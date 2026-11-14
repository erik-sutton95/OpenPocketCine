import Observation
import OpenCineCore
import OpenCineHostedTestSupport
import OpenPocketViewCore
import XCTest
import OpenCineDJIApple

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
            tile.camera = DjiAppleSighting(
                id: UUID(), name: name,
                model: .resolve(modelId: nil, name: name), modelId: nil)
            tile.settings.timecodeValue = nil
            XCTAssertNil(tile.timecodeReadout)
            tile.settings.timecodeValue =
                CameraTimecode(hours: 1, minutes: 2, seconds: 3, frames: 4)
            XCTAssertEqual(tile.timecodeReadout, name.contains("Nano") ? nil : "01:02:03")
        }
    }

    func testPocketTileCompensatesSelfiePoseOnlyWithCameraFlipOff() {
        let tile = MultiviewSession.Tile()
        tile.camera = DjiAppleSighting(
            id: UUID(), name: "Test Pocket",
            model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22)
        let yaw = UInt16(bitPattern: Int16(-1800))
        var payload = [UInt8](repeating: 0, count: GimbalStick.attitudeLength)
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
        tile.camera = DjiAppleSighting(
            id: UUID(), name: "Test camera", model: .resolve(modelId: 0x19, name: "OsmoNano-Test"),
            modelId: 0x19)
        tile.recordingObservation = (recording, Date())
        tile.recordingAvailable = available
        tile.driver = DjiAppleDatalink(port: 9030, tcpPoke: false, pairingToken: "")
        tile.controlHost = "192.0.2.30"
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
    func testRecordingFlipRefreshesTheStageByItself() {
        let session = MultiviewSession()
        let tile = session.tiles[0]
        assign(tile, recording: false, available: true)
        let changed = ObservationFlag()
        withObservationTracking {
            _ = session.anyRecording
            _ = session.coordinator.recordingActive(slot: 0)
        } onChange: {
            changed.set()
        }
        tile.recordingObservation = (true, Date())
        XCTAssertTrue(
            changed.value, "the border, lamp and Stop/Start follow the camera's REC flip itself")
    }
    func testMemberLinkStatusShowsPocketsTileCopyAndTheSessionOwnsTheControlHost() {
        let session = MultiviewSession()
        let tile = session.tiles[0]
        tile.cameraAddress = "192.0.2.41"
        tile.failureMessage = "Could not restore preview. Tap Reconnect to try again."
        tile.onStatus?(.opening)
        XCTAssertEqual(tile.status, "Connecting normal preview")
        XCTAssertNil(tile.controlHost, "Opening is not yet control")
        tile.onStatus?(.controlling)
        XCTAssertEqual(tile.controlHost, "192.0.2.41", "The session records the address it opened")
        XCTAssertNil(tile.failureMessage)
        XCTAssertEqual(tile.status, "Connecting normal preview")
        tile.onStatus?(.awaitingPicture)
        XCTAssertEqual(tile.status, "Waiting for video")
        tile.onStatus?(.live)
        XCTAssertEqual(tile.status, "Live · Video mode")
        tile.onStatus?(.reconnecting)
        XCTAssertEqual(tile.status, "Reconnecting…")
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

    // The DJI recovery ladder's own tests live with it in OpenCine (OpenCineDJITests'
    // `MultiviewRecoveryTests`) since Shared Multiview Plan 3.

    func testBorrowedLiveViewDoesNotOwnOrCloseTileTransport() {
        let tile = MultiviewSession.Tile()
        assign(tile, recording: false, available: true)
        let driver = DjiAppleDatalink(
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
        let driver = DjiAppleDatalink(
            port: 9004, tcpPoke: false, pairingToken: "test", stationHost: "192.168.1.10")
        defer {
            borrowed.releaseMultiview()
            driver.close()
            decoder.reset()
        }
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
        _ = await HostedCondition.wait { decoder.lastPresentedAt != nil }
        XCTAssertNotNil(decoder.lastPresentedAt)
        let camera = DjiAppleSighting(
            id: UUID(), name: "OsmoPocket4P-Test",
            model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22)
        borrowed.updateMultiview(camera: camera, driver: driver, status: CameraStatus())
        borrowed.receiveMultiview(
            .init(
                sender: 0, receiver: 0, seq: 1, flags: 0, cmdSet: 4, cmdId: 5,
                payload: [UInt8](repeating: 0, count: GimbalStick.attitudeLength)))
        let start = try XCTUnwrap(borrowed.gimbal.freshWaypoint)
        var end = start
        end.yawDeg += 10
        borrowed.gimbalProgram = GimbalProgram(a: start, b: end)
        borrowed.gimbal.runProgrammedMove()
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
            camera: DjiAppleSighting(
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
        let first = DjiAppleDatalink(
            port: 9004, tcpPoke: false, pairingToken: "test", stationHost: "192.168.1.10")
        let next = DjiAppleDatalink(
            port: 9004, tcpPoke: false, pairingToken: "test", stationHost: "192.168.1.11")
        model.session.datalink = first
        tile.driver = next
        XCTAssertNil(model.session.datalink)
        first.close()
        next.close()
    }

}

/// Set once by an observation's `onChange`.
private final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false
    var value: Bool { lock.withLock { isSet } }
    func set() { lock.withLock { isSet = true } }
}
