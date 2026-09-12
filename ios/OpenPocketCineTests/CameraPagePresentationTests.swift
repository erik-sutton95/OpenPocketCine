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

    private func found(_ id: UUID) -> FoundCamera {
        FoundCamera(
            id: id, name: "Test camera", model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"),
            modelId: 0x22)
    }
}
