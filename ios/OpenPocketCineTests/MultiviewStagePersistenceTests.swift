import Foundation
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class MultiviewStagePersistenceTests: XCTestCase {
    func testStageRoundTripPreservesSlotsIdentityAndOperatorChoices() throws {
        let camera = MultiviewStageStore.Camera(
            slot: 2, id: UUID(), name: "OsmoPocket3-Test",
            modelId: nil, identity: [0, 4, 84, 101, 115, 116], address: "192.168.1.20",
            experimental: true, lutEnabled: true)
        let stage = MultiviewStageStore.Stage(
            ssid: "Test network", hotspot: false,
            layout: MultiviewLayout.grid.rawValue, focusedIndex: 2, cameras: [camera],
            pendingReset: [camera], returnedToCameraWiFi: false, fill: true)
        let data = try JSONEncoder().encode(stage)
        let decoded = try JSONDecoder().decode(MultiviewStageStore.Stage.self, from: data)
        XCTAssertEqual(decoded.validated, stage)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("password"))
        XCTAssertTrue(
            CameraModel.resolve(
                modelId: decoded.cameras[0].modelId,
                name: decoded.cameras[0].name
            ).isPocket3)
    }
    func testLegacyStageWithoutFitFillStillRestores() throws {
        let stage = MultiviewStageStore.Stage(ssid: "Test", hotspot: false,
            layout: MultiviewLayout.centerStage.rawValue, focusedIndex: 0, cameras: [])
        let data = try JSONEncoder().encode(stage)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("fill"))
        let restored = try JSONDecoder().decode(MultiviewStageStore.Stage.self, from: data)
        XCTAssertNotNil(restored.validated)
        XCTAssertNil(restored.fill)
    }

    func testInvalidStageCannotAssignDuplicateCamerasOrInvalidSlots() {
        let camera = MultiviewStageStore.Camera(
            slot: 0, id: UUID(), name: "OsmoNano-Test",
            modelId: 0x19, identity: nil, address: "", experimental: false, lutEnabled: false)
        var stage = MultiviewStageStore.Stage(
            ssid: "Test", hotspot: true,
            layout: "Center stage", focusedIndex: 0, cameras: [camera])
        XCTAssertNotNil(stage.validated)
        stage.cameras.append(camera)
        XCTAssertNil(stage.validated)
        stage.cameras = [camera]
        stage.cameras[0].slot = 4
        XCTAssertNil(stage.validated)
        stage.cameras = [camera]
        stage.version = 99
        XCTAssertNil(stage.validated)
    }
}
