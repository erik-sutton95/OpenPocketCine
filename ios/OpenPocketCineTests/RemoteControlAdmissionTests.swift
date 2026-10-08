import CoreGraphics
import OpenCineCore
import OpenCineDJI
import OpenCineDJIApple
import OpenCineWatch
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// SIMULATED actual app admission ports. No camera report or native readiness is fabricated.
@MainActor
final class RemoteControlAdmissionTests: XCTestCase {
    func testRevokedReceiptDoesNotCommitPinsBusyOrFocusBeforeAnyWrite() {
        let session = CameraSession()
        let driver = DjiAppleDatalink(port: 9031, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.datalink = driver
        session.phase = .live
        session.status.isoIndex = .iso100
        session.status.colorMode = .normal
        session.status.whiteBalance = .auto(tint: 3)
        session.status.whiteBalanceTint = 3
        let receipt = DJICommandAdmission(owner: driver.commandOwner, isCurrent: { true })
        driver.commandOwner.replaceSource()
        var refused = 0
        let stage: @MainActor (ControlWireEvent) -> Void = {
            if case .notSent = $0 { refused += 1 }
        }
        session.setISO(.iso800, admission: receipt, onStage: stage)
        session.setEv(.zero, admission: receipt, onStage: stage)
        session.setShutterDenom(100, admission: receipt, onStage: stage)
        session.setWhiteBalanceAuto(tint: 9, admission: receipt, onStage: stage)
        session.setWhiteBalanceCustom(kelvin: 5600, tint: -5, admission: receipt, onStage: stage)
        session.setFocusMode(.continuous, admission: receipt, onStage: stage)
        session.setZoom(2, admission: receipt, onStage: stage)
        session.setZoomSlider(3, admission: receipt, onStage: stage)
        session.setRecording(true, admission: receipt, onStage: stage)
        session.takePhoto(admission: receipt)
        session.setColorMode(.dLog, admission: receipt)
        session.markFocus(at: .init(x: 0.1, y: 0.2), admission: receipt)
        XCTAssertEqual(refused, 9)
        XCTAssertFalse(session.controlBusy)
        XCTAssertEqual(session.status.isoIndex, .iso100)
        XCTAssertEqual(session.status.whiteBalance, .auto(tint: 3))
        XCTAssertEqual(session.status.colorMode, .normal)
        XCTAssertEqual(session.focusPoint.x, 0.5)
        XCTAssertEqual(session.focusPoint.y, 0.5)
        XCTAssertFalse(session.zoomColorHopPending)
        XCTAssertNil(driver.secondsSinceLastCommand)
    }

    func testReceiptFromAnotherNativeOwnerNeverFallsThroughTheActualPort() {
        let session = CameraSession()
        let driver = DjiAppleDatalink(port: 9032, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.datalink = driver
        session.phase = .live
        let other = DJICommandAdmission(owner: DJICommandOwner(), isCurrent: { true })
        var stages: [ControlWireEvent] = []
        session.setRecording(true, admission: other, onStage: { stages.append($0) })
        XCTAssertEqual(stages, [.notSent])
        XCTAssertFalse(session.controlBusy)
        XCTAssertNil(driver.secondsSinceLastCommand)
        XCTAssertTrue(session.commandOwner === driver.commandOwner)
    }

    func testConfirmationCannotBorrowTheCurrentNativeOwnerAfterRepair() {
        let session = CameraSession()
        let first = DjiAppleDatalink(port: 9033, tcpPoke: false, pairingToken: "")
        let successor = DjiAppleDatalink(port: 9034, tcpPoke: false, pairingToken: "")
        defer {
            first.close()
            session.disconnect()
        }
        session.datalink = first
        session.phase = .live
        session.status.shootingMode = 1
        session.status.recordingReported = true
        let target = session.control.target
        let admission = DJICommandAdmission(owner: first.commandOwner, isCurrent: { true })
        session.datalink = successor
        let refused = session.control.record(start: true, aimedAt: target, admission: admission)
        XCTAssertEqual(refused.stage, .rejected(.authorityExpired))
        XCTAssertFalse(session.controlBusy)
        XCTAssertNil(first.secondsSinceLastCommand)
        XCTAssertNil(successor.secondsSinceLastCommand)
    }

    func testOriginalZeroArgumentAndFunctionReferenceAPIsRemainAvailable() {
        let session = CameraSession()
        defer { session.disconnect() }
        let photo: () -> Void = session.takePhoto
        let color: (ColorMode) -> Void = session.setColorMode
        let focus: (CGPoint) -> Void = session.markFocus
        let record: (Bool, (@MainActor (ControlWireEvent) -> Void)?) -> Void = session.setRecording
        let model = AppModel(session: session)
        let watchRecord: () -> WatchCommandResult = model.watchToggleRecord
        let watchPhoto: () -> WatchCommandResult = model.watchCapture
        _ = (photo, color, focus, record)
        XCTAssertFalse(watchRecord().accepted)
        XCTAssertFalse(watchPhoto().accepted)
        XCTAssertFalse(session.controlBusy)
    }

    func testShownWatchSourceRefusesNativeReentryBeforeAnyNewPublication() throws {
        let session = CameraSession()
        let driver = DjiAppleDatalink(port: 9035, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.datalink = driver
        let model = AppModel(session: session)
        model.publishWatchState()
        let shown = try XCTUnwrap(model.watchCommandSource)
        XCTAssertTrue(shown.admits(driver.commandOwner))
        driver.commandOwner.replaceSource()
        XCTAssertFalse(shown.admits(driver.commandOwner))
        XCTAssertEqual(
            model.watchCommandSource?.source, shown.source,
            "A late watch action retains what was shown rather than acquiring the native successor")
        model.publishWatchState()
        let replacement = try XCTUnwrap(model.watchCommandSource)
        XCTAssertNotEqual(replacement.source, shown.source)
        XCTAssertTrue(replacement.admits(driver.commandOwner))
        XCTAssertFalse(shown.isCurrent)
    }

    func testShownWatchSourceCannotBorrowARecreatedCameraOwner() throws {
        let session = CameraSession()
        let driver = DjiAppleDatalink(port: 9036, tcpPoke: false, pairingToken: "")
        let successor = DjiAppleDatalink(port: 9037, tcpPoke: false, pairingToken: "")
        defer {
            driver.close()
            session.disconnect()
        }
        session.datalink = driver
        let model = AppModel(session: session)
        model.publishWatchState()
        let shown = try XCTUnwrap(model.watchCommandSource)
        session.datalink = successor
        XCTAssertFalse(shown.admits(session.commandOwner))
        model.publishWatchState()
        let current = try XCTUnwrap(model.watchCommandSource)
        XCTAssertTrue(current.admits(successor.commandOwner))
        XCTAssertFalse(shown.admits(successor.commandOwner))
        model.noteLeftLive()
        XCTAssertNil(model.watchCommandSource)
        XCTAssertNil(model.watchTarget)
        XCTAssertNil(successor.secondsSinceLastCommand)
    }
}
