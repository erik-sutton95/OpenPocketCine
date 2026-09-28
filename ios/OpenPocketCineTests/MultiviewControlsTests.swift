import CoreVideo
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor final class MultiviewControlsTests: XCTestCase {
    func testEditorTargetsSelectedCameraAndRoutesOnlyItsReportedSettings() {
        let session = fixture()
        defer { session.closeCameraSettings() }
        let a = session.tiles[0]
        let b = session.tiles[1]
        let first = session.openCameraSettings(a)!
        XCTAssertTrue(first.session.datalink === a.driver)
        XCTAssertTrue(first.session.decoder === a.decoder)
        first.session.setWhiteBalanceCustom(kelvin: 5600, tint: 0)
        XCTAssertEqual(first.session.status.whiteBalance, .custom(kelvin: 5600, tint: 0))
        XCTAssertNil(first.session.controlNote)
        XCTAssertNil(b.controlsModel)
        // Unrelated camera traffic must not confirm the active editor's optimistic pin.
        b.updateSettings(wb(.auto))
        a.updateSettings(wb(.auto))
        XCTAssertEqual(first.session.status.whiteBalance, .custom(kelvin: 5600, tint: 0))
        a.updateSettings(wb(.custom(kelvin: 5600, tint: 0)))
        a.updateSettings(wb(.auto))
        XCTAssertEqual(first.session.status.whiteBalance, .auto)
        let focus = session.focusedIndex
        let second = session.openCameraSettings(b)!
        XCTAssertNil(first.session.datalink)
        XCTAssertNil(a.controlsModel)
        XCTAssertTrue(second.session.datalink === b.driver)
        XCTAssertEqual(session.focusedIndex, focus)
        first.session.setWhiteBalanceCustom(kelvin: 6000, tint: 0)
        XCTAssertEqual(first.session.controlNote, "not live")
        XCTAssertEqual(first.session.status.whiteBalance, .auto)
        XCTAssertEqual(second.session.status.whiteBalance, .auto)
    }

    func testOnlySelectedCameraACKCompletesItsControlRequest() async throws {
        let session = fixture()
        defer { session.closeCameraSettings() }
        let a = session.tiles[0]
        let b = session.tiles[1]
        let model = session.openCameraSettings(a)!
        var completed = false
        let refresh = Task {
            await model.session.refreshFocusTrack()
            completed = true
        }
        try await Task.sleep(for: .milliseconds(20))
        let ack = Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0xC0,
            cmdSet: 2, cmdId: 0x8E,
            payload: [0, 0, 1, 0x3B, 0, 2, 1, FocusTrackMode.subjectLock.rawValue])
        b.updateSettings(ack)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(completed, "Another tile's ACK cannot settle this editor")
        a.updateSettings(ack)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(completed, "Selected camera ACK reaches the existing command waiter")
        XCTAssertEqual(model.session.status.focusTrack, .subjectLock)
        await refresh.value
    }

    func testRecordingGuardsModeAndFormatOnTheBorrowedCommandPath() {
        let session = fixture()
        defer { session.closeCameraSettings() }
        let model = session.openCameraSettings(session.tiles[0])!
        model.session.status.isRecording = true
        let before = model.session.status
        model.session.setShootingMode(.slowMo)
        model.session.setVideoFormat(
            resolution: .init(rawValue: 0x10), frameRate: .init(rawValue: 3))
        XCTAssertEqual(model.session.status.shootingMode, before.shootingMode)
        XCTAssertEqual(model.session.status.videoFormat, before.videoFormat)
    }

    func testCommandAdmissionRejectsInactiveOrRecordingTransition() {
        for state in 0..<3 {
            let session = fixture()
            let tile = session.tiles[0]
            let model = session.openCameraSettings(tile)!
            switch state {
            case 0: session.applicationActive = false
            case 1: session.groupRecordingBusy = true
            default: tile.recordingBusy = true
            }
            model.session.setWhiteBalanceCustom(kelvin: 6200, tint: 0)
            XCTAssertEqual(model.session.controlNote, "not live")
            XCTAssertEqual(model.session.status.whiteBalance, .auto)
            session.closeCameraSettings()
        }
    }

    func testRecoveryRemovalAndTransportReplacementInvalidatePendingEditor() {
        for event in 0..<4 {
            let session = fixture()
            let tile = session.tiles[0]
            let model = session.openCameraSettings(tile)!
            model.session.setWhiteBalanceCustom(kelvin: 5600, tint: 0)
            model.session.setWhiteBalanceCustom(kelvin: 5700, tint: 0)
            switch event {
            case 0: tile.recovering = true
            case 1: tile.camera = nil
            case 2: tile.driver = DatalinkDriver(port: 9010, tcpPoke: false, pairingToken: "")
            default: tile.controlHost = nil
            }
            XCTAssertNil(tile.controlsModel)
            XCTAssertNil(model.session.datalink)
            let held = model.session.status.whiteBalance
            model.session.setWhiteBalanceCustom(kelvin: 6200, tint: 0)
            XCTAssertEqual(model.session.controlNote, "not live")
            XCTAssertEqual(model.session.status.whiteBalance, held)
        }
    }

    func testControlsEditorNeverChangesDecoderOwnershipCallbacksOrPose() {
        let session = fixture()
        let tile = session.tiles[0]
        let layer = tile.decoder.displayLayer
        // A reachable tile state: body turned 180 and the tile's own Auto LUT. The
        // settings preview re-derives the tile's effects (#447); the editor must not.
        tile.pose.commanded180 = true
        tile.updateLUT()
        let effects = tile.decoder.effects
        var handoffs = 0
        var sourceCallbacks = 0
        tile.decoder.onHandoffNeedsIDR = { handoffs += 1 }
        tile.decoder.onSourceFrame = { _ in sourceCallbacks += 1 }
        let model = session.openCameraSettings(tile)!
        XCTAssertTrue(model.session.isMultiviewControlsOnly)
        XCTAssertNil(tile.liveModel)
        XCTAssertTrue(tile.decoder.poseViewFlip)
        XCTAssertFalse(tile.decoder.assistMirror)
        model.session.receiveMultiview(wb(.custom(kelvin: 4000, tint: 0)))
        model.session.adoptMultiviewPose(GimbalStickMapping())
        session.closeCameraSettings()
        XCTAssertTrue(tile.decoder.displayLayer === layer)
        XCTAssertEqual(tile.decoder.effects, effects)
        XCTAssertTrue(tile.decoder.poseViewFlip)
        XCTAssertFalse(tile.decoder.assistMirror)
        tile.decoder.onHandoffNeedsIDR?()
        XCTAssertEqual(handoffs, 1)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault, 2, 2, kCVPixelFormatType_32BGRA,
                nil, &buffer), kCVReturnSuccess)
        tile.decoder.onSourceFrame?(buffer!)
        XCTAssertEqual(sourceCallbacks, 1)
        XCTAssertNotNil(tile.driver)
    }

    func testLUTDefaultsOnAndExplicitChoiceSurvivesEditorAndLayoutChanges() {
        let session = fixture()
        XCTAssertTrue(session.tiles.allSatisfy(\.lutEnabled))
        let tile = session.tiles[0]
        tile.toggleLUT()
        session.layout = .grid
        session.openCameraSettings(tile)
        session.closeCameraSettings()
        session.layout = .centerStage
        XCTAssertFalse(tile.lutEnabled)
        XCTAssertTrue(session.tiles[1].lutEnabled)
        XCTAssertEqual(tile.timecodeReadout, "14:32:08")
        XCTAssertEqual(
            tile.settings.timecode, "14:32:08:12", "Protocol telemetry retains frame data")
    }

    private func fixture() -> MultiviewSession {
        let session = MultiviewUIReview.makeSession(count: 2)
        for (index, tile) in session.tiles.prefix(2).enumerated() {
            tile.driver = DatalinkDriver(
                port: UInt16(9004 + index), tcpPoke: false, pairingToken: "")
            tile.controlHost = "192.0.2.\(index + 1)"
            tile.recordingAvailable = true
            tile.settings.whiteBalance = .auto
            tile.latestSettings = tile.settings
        }
        return session
    }

    private func wb(_ value: WhiteBalance) -> Duml.Frame {
        Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0, cmdId: 0x99,
            payload: SubscribePush.pack(
                name: "cam_image_effect", value: [0, 0, 0, 0] + value.setPayload))
    }
}
