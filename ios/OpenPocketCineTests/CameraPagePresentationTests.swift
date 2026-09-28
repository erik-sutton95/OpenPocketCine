import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class CameraPagePresentationTests: XCTestCase {
    func testSavedAndNearbyCardsUseIdentityAndDoNotInventTelemetry() {
        let model = AppModel()
        let firstID = UUID()
        let secondID = UUID()
        let newID = UUID()
        model.savedCameras = [
            SavedCamera(
                id: firstID, advertisedName: "Camera one", modelName: "Pocket",
                lastConnectedAt: Date(timeIntervalSince1970: 1)),
            SavedCamera(
                id: secondID, advertisedName: "Camera two", modelName: "Nano",
                lastConnectedAt: Date(timeIntervalSince1970: 2)),
        ]
        model.session.found = [found(firstID), found(newID)]
        let saved = OsmoCameraPageAdapter.paired(model)
        XCTAssertEqual(saved.map(\.id), [firstID.uuidString, secondID.uuidString])
        XCTAssertTrue(saved[0].isAvailable)
        XCTAssertFalse(saved[1].isAvailable)
        XCTAssertFalse(saved[0].isPrimary)
        XCTAssertTrue(saved[1].isPrimary)
        XCTAssertTrue(saved.allSatisfy { $0.signalBars == nil && $0.details.isEmpty })
        XCTAssertEqual(OsmoCameraPageAdapter.nearby(model).map(\.id), [newID.uuidString])
    }

    func testPairingSelectionDoesNotAdvanceConnectionAndRequiresPresentDevice() {
        let model = AppModel()
        let id = UUID()
        model.session.phase = .scanning
        model.session.found = [found(id)]
        let selected = OsmoCameraPageAdapter.pairing(model, selected: id)
        XCTAssertEqual(selected.currentStep, 0)
        XCTAssertTrue(selected.primaryActionEnabled)
        XCTAssertEqual(model.session.phase, .scanning)
        XCTAssertFalse(OsmoCameraPageAdapter.pairing(model, selected: UUID()).primaryActionEnabled)
        model.session.found = []
        XCTAssertFalse(OsmoCameraPageAdapter.pairing(model, selected: id).primaryActionEnabled)
    }

    func testRealConnectionProgressReplacesDemoAdvanceButtons() {
        let model = AppModel()
        for (phase, step) in [
            (ConnectionPhase.awaitingApproval, 1), (.joiningWifi, 2), (.openingDatalink, 3),
        ] {
            model.session.phase = phase
            let page = OsmoCameraPageAdapter.pairing(model, selected: nil)
            XCTAssertEqual(page.currentStep, step)
            XCTAssertEqual(page.progress, phase.label)
            XCTAssertNil(page.primaryAction)
            XCTAssertEqual(page.backAction, "Cancel")
            XCTAssertFalse(page.primaryActionEnabled)
            if step >= 2 {
                XCTAssertEqual(page.checks.last?.stateLabel, "WAITING")
            }
        }
        model.session.phase = .failed("Connection failed")
        let failed = OsmoCameraPageAdapter.pairing(model, selected: nil)
        XCTAssertNil(failed.progress)
        XCTAssertNotNil(failed.error)
        XCTAssertEqual(failed.primaryAction, "Try again")
        XCTAssertTrue(failed.primaryActionEnabled)
    }

    func testPermissionFailuresOfferSettingsAndSilentDatalinkNamesTheFix() {
        let model = AppModel()
        for reason in [
            StartupConnectionCopy.bluetoothDenied, StartupConnectionCopy.localNetworkDenied,
        ] {
            model.session.phase = .failed(reason)
            let page = OsmoCameraPageAdapter.pairing(model, selected: nil)
            XCTAssertEqual(page.error, reason)
            XCTAssertEqual(page.primaryAction, "Open Settings")
            XCTAssertTrue(page.primaryActionEnabled)
        }
        model.session.phase = .failed(StartupConnectionCopy.bluetoothOff)
        XCTAssertEqual(
            OsmoCameraPageAdapter.pairing(model, selected: nil).primaryAction, "Try again")
        for raw in [
            "camera never answered the datalink handshake",
            "camera Wi-Fi path was not ready for the datalink",
        ] {
            XCTAssertEqual(
                StartupConnectionCopy.friendly(raw), StartupConnectionCopy.datalinkSilent)
        }
        XCTAssertEqual(
            DatalinkDriver.DatalinkError.localNetworkDenied.errorDescription,
            StartupConnectionCopy.localNetworkDenied)
        XCTAssertEqual(
            WiFiJoiner.JoinError.personalHotspot.errorDescription,
            StartupConnectionCopy.personalHotspotOn)
        XCTAssertFalse(
            WiFiJoiner.JoinError.rejectsCredentials(WiFiJoiner.JoinError.personalHotspot))
        XCTAssertTrue(WiFiJoiner.JoinError.rejectsCredentials(WiFiJoiner.JoinError.pathNotReady))
    }

    func testSavedCardOffersSettingsForPermissionFailure() {
        let model = AppModel()
        let id = UUID()
        let saved = SavedCamera(
            id: id, advertisedName: "Camera one", modelName: "Pocket",
            lastConnectedAt: Date(timeIntervalSince1970: 1))
        model.savedCameras = [saved]
        model.session.reviewConnecting(id, setup: .cameraWiFi, progress: "")
        model.session.phase = .failed(StartupConnectionCopy.localNetworkDenied)
        let failure = OsmoCameraPageAdapter.connectFailure(model, saved: saved, busy: false)
        XCTAssertEqual(failure?.actions.map(\.id), ["settings", "retry"])
    }

    func testScanShowsPreCheckThenStillLookingHint() {
        let model = AppModel()
        model.session.phase = .scanning
        XCTAssertEqual(
            OsmoCameraPageAdapter.pairing(model, selected: nil).instructions.first?.lines,
            ["Before pairing, turn off DJI Frame Tap and force quit DJI Mimo."])
        model.session.scanLooksEmpty = true
        let page = OsmoCameraPageAdapter.pairing(model, selected: nil)
        XCTAssertEqual(page.instructions.count, 1)
        XCTAssertEqual(
            page.instructions.first?.lines,
            [
                "Turn off DJI Frame Tap and force quit DJI Mimo on every phone near the camera. Make sure the camera is on and activated, then move closer."
            ])
        model.session.phase = .failed(StartupConnectionCopy.bluetoothOff)
        XCTAssertTrue(OsmoCameraPageAdapter.pairing(model, selected: nil).instructions.isEmpty)
        XCTAssertTrue(
            StartupConnectionCopy.friendly("pairing timed out").contains("DJI Frame Tap"))
    }

    private func found(_ id: UUID) -> FoundCamera {
        FoundCamera(
            id: id, name: "Test camera", model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"),
            modelId: 0x22)
    }
}
