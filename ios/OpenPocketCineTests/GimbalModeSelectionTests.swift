import OpenPocketViewCore
import XCTest
import OpenCineDJIApple

@testable import OpenPocketCine

@MainActor
final class GimbalModeSelectionTests: XCTestCase {
    private func liveModel(ownedRepairPolicy: ConnectionDonorPeer? = nil) async throws -> AppModel {
        let decoder: HevcDecoder
        var admittedModel: AppModel?
        if let ownedRepairPolicy {
            let model = AppModel()
            model.session = CameraSession()
            decoder = model.session.decoder
            let camera = DjiAppleSighting(id: UUID(), name: "OsmoPocket4P-Test",
                model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22)
            let admitted = await ownedRepairPolicy.admitExistingConnection(model.session, target: camera)
            admittedModel = try XCTUnwrap(admitted ? model : nil)
        } else { decoder = HevcDecoder() }
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        if let admittedModel {
            // The owned session's real presentation callback records rolling
            // native output; warmup must finish before repair becomes the gate.
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while admittedModel.session.isFeedWarming, ContinuousClock.now < deadline {
                decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
                try await Task.sleep(for: .milliseconds(40))
            }
            XCTAssertFalse(admittedModel.session.isFeedWarming)
        } else {
            // Preserve the original borrowed-context native picture setup.
            decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while decoder.lastPresentedAt == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        XCTAssertNotNil(decoder.lastPresentedAt)
        let model = admittedModel ?? AppModel()
        if ownedRepairPolicy != nil {
            model.session.datalink = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
            XCTAssertFalse(model.session.isMultiviewBorrowed)
            XCTAssertEqual(model.session.phase, .live)
        } else {
            model.session = CameraSession(borrowing: decoder)
            model.session.updateMultiview(
                camera: DjiAppleSighting(
                    id: UUID(), name: "OsmoPocket4P-Test",
                    model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22),
                driver: DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: ""),
                status: CameraStatus())
        }
        return model
    }

    func testModeAndSpeedAreRejectedDuringRecoveryWarmupAndInactiveScene() async throws {
        let saved = OperatorPrefs.headTrackingEnabled
        defer { OperatorPrefs.headTrackingEnabled = saved }
        for context in ["warming", "held", "repair", "inactive"] {
            let policy = context == "repair" ? ConnectionDonorPeer(cached: true) : nil
            let model = try await liveModel(ownedRepairPolicy: policy)
            defer { model.session.disconnect(); withExtendedLifetime(policy) {} }
            let session = model.session
            switch context {
            case "warming":
                session.decoder.reset()
                session.noteMultiviewFrame()
            case "held": session.holdsMonitor = true
            case "repair":
                XCTAssertTrue(session.startFeedRecovery { _ in try? await Task.sleep(for: .seconds(1)) })
            default: session.noteSceneBecameInactive()
            }
            model.headTrackingEnabled = true
            model.setGimbalMode(.directionLock)
            session.gimbal.setSpeed(.fast)
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
            camera: DjiAppleSighting(
                id: UUID(), name: "OsmoPocket4P-Test",
                model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22),
            driver: nil, status: CameraStatus())
        model.session.isLocked = true
        model.setGimbalMode(.directionLock)
        XCTAssertTrue(model.headTrackingEnabled)
        XCTAssertEqual(model.session.gimbalMode, .follow)
    }
}
