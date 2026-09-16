import Foundation
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class MultiviewStagePersistenceTests: XCTestCase {
    @MainActor func testSavedHotspotStageCannotSkipSessionNetworkChoiceOrRestoreCameraLocks() {
        let camera = MultiviewStageStore.Camera(
            slot: 0, id: UUID(), name: "OsmoPocket3-Test", modelId: 0x20,
            identity: nil, address: "", experimental: false, lutEnabled: false)
        let session = MultiviewSession(
            saveStage: { _ in true },
            loadNetwork: { name, hotspot in
                .init(ssid: name, password: "test-password", hotspot: hotspot)
            })
        session.restoreStage(
            .init(
                ssid: "Old hotspot", hotspot: true, layout: MultiviewLayout.grid.rawValue,
                focusedIndex: 0, cameras: [camera], pendingReset: [], returnedToCameraWiFi: true))
        XCTAssertFalse(session.networkConfigured, "Every entry must ask for the session network")
        XCTAssertTrue(
            session.tiles.allSatisfy { $0.camera == nil }, "Old slots must not lock setup")
        session.selectNetworkSource(hotspot: false)
        XCTAssertFalse(session.usePhoneHotspot, "Local Wi-Fi must remain selectable")
        session.stop()
    }

    @MainActor func testChangingNetworkSourceInvalidatesPreviousSessionConfirmation() {
        let session = MultiviewSession(saveStage: { _ in true })
        session.networkConfigured = true
        session.usePhoneHotspot = true
        session.selectNetworkSource(hotspot: false)
        XCTAssertFalse(session.networkConfigured)
        XCTAssertFalse(session.usePhoneHotspot)
    }

    @MainActor func testCredentialsAreLoadedOnlyAfterAnExplicitNetworkChoice() {
        var lookups: [(String, Bool)] = []
        let session = MultiviewSession(
            saveStage: { _ in true },
            loadNetwork: { name, hotspot in
                lookups.append((name, hotspot))
                return .init(ssid: name, password: "saved-test-password", hotspot: hotspot)
            })
        session.selectNetworkSource(hotspot: true)
        XCTAssertTrue(lookups.isEmpty)
        session.selectNetwork("Test phone hotspot")
        XCTAssertEqual(session.password, "saved-test-password")
        XCTAssertTrue(lookups[0].1)
        session.networkConfigured = true
        session.selectNetworkSource(hotspot: false)
        XCTAssertFalse(session.networkConfigured)
        XCTAssertEqual(session.ssid, "")
        XCTAssertEqual(session.password, "")
        session.selectNetwork("Test local Wi-Fi")
        XCTAssertEqual(lookups.count, 2)
        XCTAssertEqual(lookups[1].0, "Test local Wi-Fi")
        XCTAssertFalse(lookups[1].1)
        XCTAssertEqual(session.ssid, "Test local Wi-Fi")
        XCTAssertFalse(session.networkConfigured, "Selecting a name still requires Done")
    }

    @MainActor func testRemovingLastCameraAllowsChoosingAnotherSessionNetwork() async {
        let session = MultiviewSession(saveStage: { _ in true }, loadNetwork: { _, _ in nil })
        session.networkConfigured = true
        session.ssid = "Old hotspot"
        session.usePhoneHotspot = true
        session.tiles[0].camera = FoundCamera(
            id: UUID(), name: "OsmoPocket3-Test", model: .resolve(modelId: 0x20, name: "Test"),
            modelId: 0x20)
        session.selectNetworkSource(hotspot: false)
        XCTAssertTrue(session.usePhoneHotspot, "An assigned camera still owns the active network")
        session.selectNetwork("Other network")
        XCTAssertEqual(session.ssid, "Old hotspot")
        let configured = await session.configureNetwork()
        XCTAssertFalse(configured)
        let removed = await session.remove(session.tiles[0])
        XCTAssertTrue(removed)
        session.selectNetworkSource(hotspot: false)
        session.selectNetwork("New local Wi-Fi")
        XCTAssertFalse(session.usePhoneHotspot)
        XCTAssertEqual(session.ssid, "New local Wi-Fi")
        XCTAssertFalse(session.networkConfigured)
    }

    @MainActor func testLegacyAssignedCamerasBecomeCleanupOnlyWithoutSelectingTheirNetwork() {
        let camera = MultiviewStageStore.Camera(
            slot: 0, id: UUID(), name: "OsmoPocket3-Test", modelId: 0x20,
            identity: nil, address: "", experimental: false, lutEnabled: false)
        var journal: MultiviewStageStore.Stage?
        let session = MultiviewSession(saveStage: {
            journal = $0
            return true
        })
        session.restoreStage(
            .init(
                ssid: "Legacy hotspot", hotspot: true, layout: MultiviewLayout.grid.rawValue,
                focusedIndex: 0, cameras: [camera], returnedToCameraWiFi: false))
        XCTAssertFalse(session.networkConfigured)
        XCTAssertEqual(session.ssid, "")
        XCTAssertFalse(session.usePhoneHotspot)
        XCTAssertTrue(session.tiles.allSatisfy { $0.camera == nil })
        XCTAssertEqual(journal?.ssid, "")
        XCTAssertEqual(journal?.cameras, [])
        XCTAssertEqual(journal?.pendingReset, [camera])
    }

    @MainActor func testCancellingNewSetupDoesNotDeleteLastPresentationPreferences() async {
        var journal: MultiviewStageStore.Stage? = .init(
            ssid: "Previous network", hotspot: true, layout: MultiviewLayout.grid.rawValue,
            focusedIndex: 2, cameras: [], pendingReset: [], returnedToCameraWiFi: true, fill: true)
        let session = MultiviewSession(saveStage: {
            journal = $0
            return true
        })
        session.restoreStage(journal)
        XCTAssertEqual(session.layout, .grid)
        XCTAssertEqual(session.feedAspect, .fill)
        XCTAssertFalse(session.networkConfigured)
        let closed = await session.closeStage()
        XCTAssertTrue(closed)
        XCTAssertEqual(journal?.layout, MultiviewLayout.grid.rawValue)
        XCTAssertEqual(journal?.focusedIndex, 2)
        XCTAssertEqual(journal?.fill, true)
    }

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
        let stage = MultiviewStageStore.Stage(
            ssid: "Test", hotspot: false,
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

    func testCleanupOnlyJournalDoesNotRequireNetworkOrTileSlots() throws {
        let cameras = (0..<6).map { index in
            MultiviewStageStore.Camera(
                slot: 0, id: UUID(), name: "Scan camera \(index)", modelId: nil,
                identity: nil, address: "", experimental: false, lutEnabled: false)
        }
        var stage = MultiviewStageStore.Stage(
            ssid: "", hotspot: false, layout: "Grid", focusedIndex: 0, cameras: [],
            pendingReset: cameras)
        XCTAssertNotNil(stage.validated, "Cleanup targets are independent of the four tile slots")
        let restored = try JSONDecoder().decode(
            MultiviewStageStore.Stage.self, from: JSONEncoder().encode(stage))
        XCTAssertEqual(restored.validated, stage)
        stage.cameras = [cameras[0]]
        XCTAssertNil(stage.validated, "An assigned stage still requires a network")
        stage.cameras = []
        stage.pendingReset = cameras + [cameras[0]]
        XCTAssertNil(stage.validated, "A camera must only be reset once")
        stage.pendingReset = []
        XCTAssertNil(stage.validated, "Completed cleanup journals must be deleted")
    }

    func testCleanupUnionPreservesUnassignedCamerasAndDeduplicatesByIdentity() {
        let scanned = MultiviewStageStore.Camera(
            slot: 0, id: UUID(), name: "Scan camera", modelId: nil,
            identity: nil, address: "", experimental: false, lutEnabled: false)
        var assigned = scanned
        assigned.slot = 2
        assigned.address = "192.168.1.20"
        var other = scanned
        other.id = UUID()
        let combined = MultiviewStageStore.cleanupTargets([scanned, other], including: [assigned])
        XCTAssertEqual(combined, [assigned, other])
    }

    @MainActor func testScanOnlyCleanupSurvivesFailureAndSecondCloseRetries() async throws {
        var journal: MultiviewStageStore.Stage?
        var attempts = 0
        let session = MultiviewSession(
            resetCamera: { _ in
                attempts += 1
                return attempts > 1
            },
            saveStage: {
                journal = $0
                return true
            })
        let camera = FoundCamera(
            id: UUID(), name: "OsmoPocket3-Test",
            model: .resolve(modelId: nil, name: "OsmoPocket3-Test"), modelId: nil)
        XCTAssertTrue(session.recordStationChange(camera))
        XCTAssertEqual(journal?.ssid, "")
        XCTAssertEqual(journal?.cameras, [])
        XCTAssertEqual(journal?.pendingReset?.map(\.id), [camera.id])
        XCTAssertNotNil(journal?.validated)
        let firstClose = await session.closeStage()
        XCTAssertFalse(firstClose)
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(session.hasPendingCleanup)
        XCTAssertEqual(journal?.pendingReset?.map(\.id), [camera.id])
        let secondClose = await session.closeStage()
        XCTAssertTrue(secondClose)
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(journal)
        XCTAssertFalse(session.hasPendingCleanup)
    }

    @MainActor func testCloseReusesUncancelledScanCleanup() async throws {
        var journal: MultiviewStageStore.Stage?
        var attempts = 0
        var finish: CheckedContinuation<Bool, Never>?
        let session = MultiviewSession(
            resetCamera: { _ in
                attempts += 1
                return await withCheckedContinuation { finish = $0 }
            },
            saveStage: {
                journal = $0
                return true
            })
        let camera = FoundCamera(
            id: UUID(), name: "OsmoPocket3-Test",
            model: .resolve(modelId: nil, name: "OsmoPocket3-Test"), modelId: nil)
        XCTAssertTrue(session.recordStationChange(camera))
        let saved = try XCTUnwrap(journal?.pendingReset?.first)
        let scanCleanup = Task { await session.resetStationOnce(saved) }
        while finish == nil { await Task.yield() }
        scanCleanup.cancel()
        let closing = Task { await session.closeStage() }
        while !session.closing { await Task.yield() }
        finish?.resume(returning: true)
        let scanResult = await scanCleanup.value
        let closeResult = await closing.value
        XCTAssertTrue(scanResult)
        XCTAssertTrue(closeResult)
        XCTAssertEqual(attempts, 1)
        XCTAssertNil(journal)
    }

    @MainActor func testCleanupOnlyRestoreDefersRadioWorkUntilCloseAndAssignsNoTiles() async throws
    {
        for ssid in ["", "Forgotten test network \(UUID().uuidString)"] {
            await checkCleanupRestoreWithoutNetwork(ssid: ssid)
        }
    }

    @MainActor private func checkCleanupRestoreWithoutNetwork(ssid: String) async {
        let camera = MultiviewStageStore.Camera(
            slot: 0, id: UUID(), name: "Scan camera", modelId: nil,
            identity: nil, address: "", experimental: false, lutEnabled: false)
        var journal: MultiviewStageStore.Stage? = .init(
            ssid: ssid, hotspot: false, layout: "Grid", focusedIndex: 0, cameras: [],
            pendingReset: [camera])
        var restored: [UUID] = []
        let session = MultiviewSession(
            resetCamera: {
                restored.append($0.id)
                return true
            },
            saveStage: {
                journal = $0
                return true
            })
        session.restoreStage(journal)
        XCTAssertFalse(session.busy)
        XCTAssertTrue(restored.isEmpty, "Entering setup must not change camera networks")
        XCTAssertFalse(session.networkConfigured)
        XCTAssertTrue(session.tiles.allSatisfy { $0.camera == nil })
        XCTAssertEqual(journal?.pendingReset?.map(\.id), [camera.id])
        let closed = await session.closeStage()
        XCTAssertTrue(closed)
        XCTAssertEqual(restored, [camera.id])
        XCTAssertNil(journal)
    }
}
