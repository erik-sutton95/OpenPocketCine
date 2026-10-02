import OpenCineAppKit
import OpenCineCore
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class DJIControlLifetimeTests: XCTestCase {
    func testOwnedShellCloseTearsDownNativeLinkAndCoverDoesNot() async {
        let session = OpenPocketCine.CameraSession()
        defer { session.disconnect() }
        let driver = DatalinkDriver(port: 9011, tcpPoke: false, pairingToken: "")
        session.datalink = driver
        session.phase = .live
        session.status.shootingMode = 1
        session.status.recordingReported = true
        session.status.isRecording = true
        let common = session.control
        XCTAssertEqual(common.current.recording.value, .recording)
        let model = AppModel(session: session)
        let shell = model.shell
        shell.present(camera(common))
        let monitor = shell.monitor?.id
        shell.open(.settings)
        shell.open(.media)
        shell.dismissCover()
        XCTAssertEqual(shell.monitor?.id, monitor)
        XCTAssertTrue(session.datalink === driver)
        XCTAssertFalse(driver.isClosed)
        XCTAssertEqual(session.control.id, common.id)

        shell.close()
        shell.close()
        for _ in 0..<200 where !driver.isClosed { await Task.yield() }
        XCTAssertTrue(driver.isClosed)
        XCTAssertNil(session.datalink)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(common.current.connection, .disconnected(.requested))
        XCTAssertEqual(
            common.current.recording.value, .recording, "Close cannot claim a stopped recording")
        XCTAssertNotEqual(
            session.control.id, common.id, "The next connection cannot reuse a closed seam")
    }

    func testLateCloseCannotCancelSuccessorWhileSavedCameraScanning() {
        let session = OpenPocketCine.CameraSession()
        defer { session.disconnect() }
        let driver = DatalinkDriver(port: 9012, tcpPoke: false, pairingToken: "")
        session.datalink = driver
        session.phase = .live
        let first = session.control
        let next = UUID()
        session.startScan(reconnect: next)
        let successor = session.control
        first.close(.requested)
        XCTAssertNotEqual(first.id, successor.id)
        XCTAssertEqual(first.current.connection, .disconnected(.replaced))
        XCTAssertEqual(session.connectionTargetID, next)
        XCTAssertEqual(session.phase, .scanning)
        XCTAssertEqual(session.control.id, successor.id)
    }

    func testBorrowedShellReturnReleasesViewWithoutClosingTileTransport() {
        let decoder = HevcDecoder()
        let view = OpenPocketCine.CameraSession(borrowing: decoder)
        let tileDriver = DatalinkDriver(port: 9013, tcpPoke: false, pairingToken: "")
        defer { tileDriver.close() }
        view.datalink = tileDriver
        let common = view.control
        let model = AppModel(session: view)
        let shell = model.shell
        var releases = 0
        shell.borrow(
            camera(common),
            release: {
                releases += 1
                view.releaseMultiview()
            })
        shell.open(.settings)
        shell.dismissCover()
        XCTAssertEqual(releases, 0)
        XCTAssertFalse(tileDriver.isClosed)
        shell.close()
        shell.close()
        XCTAssertEqual(releases, 1)
        XCTAssertFalse(tileDriver.isClosed)
        XCTAssertNil(view.datalink)
        XCTAssertTrue(view.decoder === decoder)
        XCTAssertEqual(common.current.connection, .disconnected(.requested))
    }

    func testNativePanelCompatibilityUsesOneCoverAndKeepsHostIdentity() {
        let model = AppModel()
        defer { model.session.disconnect() }
        model.shell.present(camera(model.session.control))
        let monitor = model.shell.monitor?.id
        model.liveOperatorPanel = .settings
        XCTAssertEqual(model.shell.cover, .settings)
        XCTAssertNil(model.homePanel)
        model.shell.open(.media)
        XCTAssertEqual(model.liveOperatorPanel, .media)
        XCTAssertEqual(model.shell.monitor?.id, monitor)
        model.liveOperatorPanel = nil
        XCTAssertNil(model.shell.cover)
        XCTAssertEqual(model.shell.monitor?.id, monitor)
    }

    func testSceneSignalsAreDeduplicatedThroughActualAppShell() {
        let model = AppModel()
        defer { model.session.disconnect() }
        var signals: [Bool] = []
        model.shell.onSceneActivity = { signals.append($0) }
        model.shell.setSceneActive(false)
        model.shell.setSceneActive(false)
        model.shell.setSceneActive(true)
        model.shell.setSceneActive(true)
        XCTAssertEqual(signals, [false, true])
    }

    func testUnknownCameraCannotApproveZoomCycleOrCapture() {
        let model = AppModel()
        defer { model.session.disconnect() }
        XCTAssertFalse(model.commitZoomCycle(2))
        XCTAssertFalse(model.commitZoomCycle(.nan))
        XCTAssertNil(model.control.recordEditor())
        XCTAssertTrue(model.control.pending.isEmpty)
    }

    func testCommonFocusKeepsUnknownAndTrackedAfCOnTheNativeStrategyPath() {
        XCTAssertEqual(CaptureFocusAdmission.commonValue("AF-S", track: nil), .focusMode(.single))
        XCTAssertEqual(CaptureFocusAdmission.commonValue("AF-C", track: .default), .focusMode(.continuous))
        XCTAssertNil(CaptureFocusAdmission.commonValue("AF-C", track: nil))
        XCTAssertNil(CaptureFocusAdmission.commonValue("AF-C", track: .productShowcase))
        XCTAssertNil(CaptureFocusAdmission.commonValue("Showcase", track: .default))
    }

    private func camera(_ session: DJICameraSessionAdapter) -> ConnectedCamera {
        ConnectedCamera(
            saved: OpenCineCore.SavedCamera(
                id: "simulated-dji",
                integration: DJICameraSessionAdapter.integration, advertisedName: "SIMULATED DJI",
                model: "SIMULATED"), session: session)
    }
}
