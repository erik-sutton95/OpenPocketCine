import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class GimbalModeSelectionTests: XCTestCase {
    func testMenuTakesControlFromHeadTrackingUntilExplicitlyEnabledAgain() {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        let model = AppModel()
        model.session = CameraSession(borrowing: HevcDecoder())
        model.session.updateMultiview(
            camera: FoundCamera(id: UUID(), name: "OsmoPocket4P-Test",
                model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22),
            driver: nil, status: CameraStatus())
        model.headTrackingEnabled = true
        model.setGimbalMode(.directionLock)
        XCTAssertEqual(model.session.gimbalMode, .directionLock)
        XCTAssertFalse(model.headTrackingEnabled)
        // Leaving Direction Lock must not silently restart the calibrated stream.
        model.setGimbalMode(.follow)
        XCTAssertFalse(model.headTrackingEnabled)
        model.headTrackingEnabled = true
        XCTAssertTrue(model.headTrackingEnabled)
    }

    func testRejectedModeSelectionPreservesHeadTrackingPreference() {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        let model = AppModel()
        model.headTrackingEnabled = true
        model.setGimbalMode(.directionLock)
        XCTAssertTrue(model.headTrackingEnabled)
        model.session = CameraSession(borrowing: HevcDecoder())
        model.session.updateMultiview(
            camera: FoundCamera(id: UUID(), name: "OsmoPocket4P-Test",
                model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22),
            driver: nil, status: CameraStatus())
        model.session.isLocked = true
        model.setGimbalMode(.directionLock)
        XCTAssertTrue(model.headTrackingEnabled)
        XCTAssertEqual(model.session.gimbalMode, .follow)
    }
}
