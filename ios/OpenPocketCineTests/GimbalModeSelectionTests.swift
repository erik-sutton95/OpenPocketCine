import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class GimbalModeSelectionTests: XCTestCase {
    private func liveModel() async throws -> AppModel {
        let decoder = HevcDecoder()
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while decoder.lastPresentedAt == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(decoder.lastPresentedAt)
        let model = AppModel()
        model.session = CameraSession(borrowing: decoder)
        model.session.updateMultiview(
            camera: FoundCamera(
                id: UUID(), name: "OsmoPocket4P-Test",
                model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22),
            driver: DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: ""),
            status: CameraStatus())
        return model
    }

    func testModeAndSpeedAreRejectedDuringRecoveryWarmupAndInactiveScene() async throws {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        for context in ["warming", "held", "repair", "inactive"] {
            let model = try await liveModel()
            defer { model.session.disconnect() }
            let session = model.session
            switch context {
            case "warming":
                session.decoder.reset()
                session.noteMultiviewFrame()
            case "held": session.holdsMonitor = true
            case "repair":
                session.startFeedRecovery { try? await Task.sleep(for: .seconds(1)) }
            default: session.noteSceneBecameInactive()
            }
            model.headTrackingEnabled = true
            model.setGimbalMode(.directionLock)
            session.setGimbalSpeed(.fast)
            XCTAssertEqual(session.gimbalMode, .follow, context)
            XCTAssertEqual(session.gimbalSpeed, .defaultSpeed, context)
            XCTAssertTrue(model.headTrackingEnabled, context)
        }
    }

    func testMenuTakesControlFromHeadTrackingUntilExplicitlyEnabledAgain() async throws {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        let model = try await liveModel()
        defer { model.session.disconnect() }
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
            camera: FoundCamera(
                id: UUID(), name: "OsmoPocket4P-Test",
                model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22),
            driver: nil, status: CameraStatus())
        model.session.isLocked = true
        model.setGimbalMode(.directionLock)
        XCTAssertTrue(model.headTrackingEnabled)
        XCTAssertEqual(model.session.gimbalMode, .follow)
    }
}
