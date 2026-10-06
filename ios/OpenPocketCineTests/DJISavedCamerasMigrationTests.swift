import Foundation
import OpenCineAppKit
import OpenCineCore
import OpenCineDJI
import XCTest
import OpenCineDJIApple

@testable import OpenPocketCine

/// SHELL-02 migration tests 1-6 on golden fixtures that the shipping app's encoder wrote
/// (`SavedCameraStore.save`: JSONEncoder over canonicalized `[SavedCamera]`, dates in seconds
/// since 2001), through the app's own store wiring (`AppModel.camerasStore`), plus the DJI save
/// rules and failure copy the shared flow now applies.
@MainActor
final class DJISavedCamerasMigrationTests: XCTestCase {
    private let a = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    private let b = "7A1B2C3D-4E5F-4061-8293-A4B5C6D7E8F9"
    private let c = "0D1E2F30-4152-4637-8899-AABBCCDDEEFF"
    private let d = "99999999-2222-4333-8444-555555555555"
    private let e = "5E5E5E5E-1111-4222-8333-444444444444"
    private let legacyKey = "OpenPocketCine.SavedCameras"
    private let documentKey = "OpenPocketCine.Cameras"
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "shell02.pocket.migration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appending(path: "DJIFixtures/saved-cameras/\(name).json"))
    }

    private func loaded(_ legacy: String) throws -> SavedCamerasStore {
        defaults.set(try fixture(legacy), forKey: legacyKey)
        let store = AppModel.camerasStore(defaults)
        store.load()
        return store
    }

    private var storedKeys: Set<String> { Set((defaults.persistentDomain(forName: suite) ?? [:]).keys) }
    private func milliseconds(_ date: Date?) -> Int64? { date.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } }

    /// The decoder every released build runs: the synthesized Codable of the app's old record.
    private struct OldRecord: Codable {
        enum Setup: String, Codable { case cameraWiFi, wifi, phoneHotspot }
        var id: UUID
        var advertisedName: String
        var modelName: String
        var modelId: Int?
        var lastSSID: String?
        var lastConnectedAt: Date
        var customName: String?
        var wifiSSID: String?
        var hotspotSSID: String?
        var lastSetup: Setup?
    }

    // 1
    func testUpgradeImportsEveryCameraAndLeavesLegacyAlone() throws {
        let store = try loaded("legacy")
        XCTAssertEqual(defaults.data(forKey: legacyKey), try fixture("legacy"))
        XCTAssertEqual(storedKeys, [legacyKey, documentKey], "nothing else is written; credentials stay in the Keychain")
        XCTAssertEqual(store.cameras.map(\.id), [a, b, c, e])
        XCTAssertTrue(store.cameras.allSatisfy { $0.integration == DJICameraSessionAdapter.integration && $0.device == nil })

        let first = store.cameras[0]
        XCTAssertEqual(first.name, "A cam")
        XCTAssertEqual(first.advertisedName, "OsmoPocket4P-1A2B")
        XCTAssertEqual(first.model, "Osmo Pocket 4 Pro")
        XCTAssertEqual(first.routes.map(\.kind), [.cameraAccessPoint])
        XCTAssertEqual(first.routes.map(\.network), ["OsmoPocket4P-1A2B"])
        XCTAssertEqual(first.preferredRoute, first.routes[0].id)
        XCTAssertEqual(milliseconds(first.lastConnected), 1_759_307_200_250)
        XCTAssertEqual(first.extras, ["modelId": "34"])

        // Both setups that move the camera, the Wi-Fi one last used.
        let second = store.cameras[1]
        XCTAssertNil(second.name)
        XCTAssertEqual(second.routes.map(\.key), ["ap", "wifi", "hotspot"])
        XCTAssertEqual(second.routes.map(\.network), ["OsmoPocket3-4D5E", "Studio", "Rig iPhone"])
        XCTAssertEqual(second.preferredRoute, second.routes[1].id)
        XCTAssertTrue(second.mayBeInStationRole)

        let third = store.cameras[2]
        XCTAssertEqual(third.routes.map(\.key), ["ap"])
        XCTAssertNil(third.routes[0].network)
        XCTAssertNil(third.preferredRoute)
        XCTAssertEqual(milliseconds(third.lastConnected), 1_757_307_200_500)
        XCTAssertEqual(third.modelId, 0x19)

        // A hotspot connect stamped station role, then the hotspot setup was forgotten.
        let fifth = store.cameras[3]
        XCTAssertEqual(fifth.routes.map(\.key), ["ap"])
        XCTAssertNil(fifth.preferredRoute)
        XCTAssertEqual(fifth.extras, ["modelId": "33", "lastSetup": "phoneHotspot"])
        XCTAssertTrue(fifth.mayBeInStationRole, "the next camera Wi-Fi connect restores its access point")

        let document = try XCTUnwrap(defaults.data(forKey: documentKey))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: document) as? [String: Any])?["version"] as? Int, 1)
    }

    // 2
    func testMigrationIsIdempotent() throws {
        let first = try loaded("legacy")
        let document = defaults.data(forKey: documentKey)
        for _ in 0..<2 {
            let again = AppModel.camerasStore(defaults)
            again.load()
            XCTAssertEqual(again.cameras, first.cameras)
        }
        XCTAssertEqual(defaults.data(forKey: documentKey), document)
        XCTAssertEqual(defaults.data(forKey: legacyKey), try fixture("legacy"))
        XCTAssertEqual(storedKeys, [legacyKey, documentKey])
    }

    // 3: rename, forget, a moving setup, a camera Wi-Fi connect that restores the access point and
    // a new pair through the shared model and the DJI integration, then the older build reads the
    // mirror with its own decoder.
    func testMirrorRoundTripDecodesWithTheOldDecoder() async throws {
        defaults.set(try fixture("legacy"), forKey: legacyKey)
        let port = FakeDJIPort()
        let connectedAt = Date(timeIntervalSinceReferenceDate: 790_000_000)
        let integration = DJIIntegration(port: port, now: { connectedAt })
        let model = CamerasModel(integrations: [AppIntegration(integration)], store: AppModel.camerasStore(defaults))
        let live = OpenPocketCine.CameraSession()
        integration.savedCameras = { model.saved }
        integration.saveRecord = { model.upsert($0) }
        model.rename(a, to: "Renamed")
        await model.forget(c)
        XCTAssertEqual(port.forgotten, [c], "forget drops the camera's saved Wi-Fi")

        // B over its hotspot setup: remembered before the attempt, which then fails.
        let second = try XCTUnwrap(model.saved.first { $0.id == b })
        model.connect(second, route: second.routes.first { $0.key == "hotspot" }?.id)
        try await until { port.connects.count == 1 }
        XCTAssertEqual(port.connects[0].setup, .phoneHotspot(network: "Rig iPhone", password: nil))
        XCTAssertEqual(model.saved.first { $0.id == b }?.extras["modelId"], "32")
        let stamped = try JSONDecoder().decode([OldRecord].self, from: XCTUnwrap(defaults.data(forKey: legacyKey)))
        XCTAssertEqual(stamped.first { $0.id.uuidString == b }?.lastSetup, .phoneHotspot, "stamped before it moves the camera")
        port.finish(.failure(CancellationError()))
        try await until { model.attempts.isEmpty }

        // E over camera Wi-Fi: the access point is restored first, and the stamp goes once live.
        let fifth = try XCTUnwrap(model.saved.first { $0.id == e })
        model.connect(fifth)
        try await until { port.connects.count == 2 }
        XCTAssertTrue(port.connects[1].restoreAccessPoint)
        port.finish(.success(DJIConnection(session: live.control, joinedNetwork: "OsmoPocket4-EEFF")))
        try await until { model.saved.first { $0.id == e }?.lastConnected == connectedAt }
        model.sessionEnded()

        // A new pair whose joined network another saved camera owns: the network is not saved.
        port.onSightings?([DJISighting(id: d, name: "OsmoPocket4P-AABB", model: .resolve(modelId: 0x22, name: nil), modelId: 0x22)])
        try await until { !model.nearby.isEmpty }
        model.connect(model.nearby[0])
        try await until { port.connects.count == 3 }
        port.finish(.success(DJIConnection(
            session: live.control, joinedNetwork: "OsmoPocket3-4D5E",
            camera: DJISighting(id: d, name: "OsmoPocket4P-AABB", model: .resolve(modelId: 0x22, name: nil), modelId: 0x22))))
        try await until { model.saved.count == 4 }

        let old = try JSONDecoder().decode([OldRecord].self, from: XCTUnwrap(defaults.data(forKey: legacyKey)))
        XCTAssertEqual(old.map(\.id.uuidString), [a, b, e, d])
        XCTAssertEqual(old[0].customName, "Renamed")
        XCTAssertEqual(old[0].lastSetup, .cameraWiFi)
        XCTAssertEqual(old[1].lastSetup, .phoneHotspot)
        XCTAssertEqual(old[1].wifiSSID, "Studio")
        XCTAssertEqual(old[1].hotspotSSID, "Rig iPhone")
        XCTAssertEqual(old[2].lastConnectedAt, connectedAt)
        XCTAssertEqual(old[2].lastSetup, .cameraWiFi, "a camera Wi-Fi connect clears the station stamp")
        XCTAssertEqual(old[2].lastSSID, "OsmoPocket4-EEFF")
        XCTAssertEqual(old[3].advertisedName, "OsmoPocket4P-AABB")
        XCTAssertEqual(old[3].modelName, "Osmo Pocket 4 Pro")
        XCTAssertEqual(old[3].modelId, 0x22)
        XCTAssertNil(old[3].lastSSID, "another saved camera's network is never saved with this one")
        XCTAssertEqual(old[3].lastSetup, .cameraWiFi)

        let again = AppModel.camerasStore(defaults)
        again.load()
        XCTAssertEqual(again.cameras, model.saved)
    }

    // 4
    func testDowngradeEditsMergeBackOnUpgrade() throws {
        let store = try loaded("legacy")
        var cameras = store.cameras
        cameras[0].device = .durable("SN-A", integration: DJICameraSessionAdapter.integration)
        store.save(cameras)
        XCTAssertEqual(defaults.data(forKey: legacyKey), try fixture("legacy"), "a document-only edit leaves legacy alone")
        let apRoute = cameras[0].routes[0].id

        // The older build renamed B, forgot C, paired D and added a hotspot setup to A, then
        // connected A over it.
        defaults.set(try fixture("legacy-downgrade-edits"), forKey: legacyKey)
        let upgraded = AppModel.camerasStore(defaults)
        upgraded.load()
        XCTAssertEqual(Set(upgraded.cameras.map(\.id)), [a, b, d, e])
        let first = try XCTUnwrap(upgraded.cameras.first { $0.id == a })
        XCTAssertEqual(first.device, .durable("SN-A", integration: DJICameraSessionAdapter.integration))
        XCTAssertEqual(first.routes.map(\.key), ["ap", "hotspot"])
        XCTAssertEqual(first.routes[0].id, apRoute)
        XCTAssertEqual(first.routes[1].network, "Rig iPhone")
        XCTAssertEqual(first.preferredRoute, first.routes[1].id)
        XCTAssertEqual(milliseconds(first.lastConnected), 1_761_307_200_000)
        XCTAssertEqual(upgraded.cameras.first { $0.id == b }?.name, "B cam")
        let fourth = try XCTUnwrap(upgraded.cameras.first { $0.id == d })
        XCTAssertEqual(fourth.routes.map(\.network), ["OsmoPocket4P-AABB"])
        XCTAssertEqual(fourth.preferredRoute, fourth.routes[0].id)
        XCTAssertEqual(upgraded.cameras.first { $0.id == e }?.extras["lastSetup"], "phoneHotspot")
        XCTAssertEqual(defaults.data(forKey: legacyKey), try fixture("legacy-downgrade-edits"))
    }

    // 5
    func testABadRecordIsKeptAndNeverOverwritten() throws {
        let store = try loaded("legacy-bad-record")
        XCTAssertEqual(store.cameras.map(\.id), [a, b, c, e], "one bad record no longer empties the list")
        var cameras = store.cameras
        cameras[0].name = "Renamed"
        store.save(cameras)
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: legacyKey))) as? [[String: Any]])
        XCTAssertEqual(raw.count, 5)
        XCTAssertEqual(raw[0]["customName"] as? String, "Renamed")
        XCTAssertNil(raw[4]["id"])
        XCTAssertEqual(raw[4]["advertisedName"] as? String, "Broken")
        XCTAssertEqual((raw[4]["futureField"] as? [String: Any])?["kept"] as? Bool, true)
    }

    // 6
    func testADocumentFromANewerBuildIsNeverWritten() throws {
        let future = Data(#"{"cameras":[],"legacy":{},"version":2}"#.utf8)
        defaults.set(future, forKey: documentKey)
        let store = try loaded("legacy")
        XCTAssertFalse(store.writesDocument)
        XCTAssertEqual(store.cameras.map(\.id), [a, b, c, e], "this build runs from legacy")
        var cameras = store.cameras
        cameras[1].name = "Edited"
        store.save(cameras)
        XCTAssertEqual(defaults.data(forKey: documentKey), future)
        let old = try JSONDecoder().decode([OldRecord].self, from: XCTUnwrap(defaults.data(forKey: legacyKey)))
        XCTAssertEqual(old[1].customName, "Edited")
    }

    /// The connect pipeline's failures keep this app's copy, the vendor-app tip included, typed
    /// at the error it threw; a setting only Settings fixes offers Open Settings.
    func testConnectFailuresKeepTheAppCopy() {
        let session = OpenPocketCine.CameraSession()
        session.lastConnectError = DjiAppleDatalink.DatalinkError.noHandshake
        let silent = session.typedFailure("camera never answered the datalink handshake")
        XCTAssertEqual(silent.message, StartupConnectionCopy.datalinkSilent)
        XCTAssertTrue(silent.message.contains("DJI Frame Tap") && silent.message.contains("DJI Mimo"))
        XCTAssertEqual(silent.reason, .timedOut)
        XCTAssertEqual(silent.actions, [.retry])

        session.lastConnectError = OpenPocketCine.CameraSession.Fail.pairingTimeout
        let approval = session.typedFailure(OpenPocketCine.CameraSession.Fail.pairingTimeout.errorDescription ?? "")
        XCTAssertEqual(approval.reason, .notApproved)
        XCTAssertTrue(approval.message.contains("DJI Frame Tap"))

        session.lastConnectError = DjiAppleDatalink.DatalinkError.localNetworkDenied
        let local = session.typedFailure(StartupConnectionCopy.localNetworkDenied)
        XCTAssertEqual(local.reason, .permission(.localNetwork))
        XCTAssertEqual(local.actions, [.openSettings, .retry])

        session.lastConnectError = nil
        let bluetooth = session.typedFailure(StartupConnectionCopy.bluetoothDenied)
        XCTAssertEqual(bluetooth.reason, .permission(.bluetooth))
        XCTAssertEqual(bluetooth.actions, [.openSettings, .retry])
        XCTAssertEqual(bluetooth.code, "org.opencapture.openpocketcine.dji.bluetooth.denied")
    }

    /// A cancelled shared attempt cannot stay parked on the app's hotspot confirmation.
    func testCancellingHotspotConfirmationReleasesItsWaiter() async throws {
        let model = AppModel()
        let confirmation = Task { await model.askHotspot("Test hotspot") }
        try await until { model.hotspotQuestion != nil }
        confirmation.cancel()
        let accepted = await confirmation.value
        XCTAssertFalse(accepted)
        XCTAssertNil(model.hotspotQuestion)
    }

    func testReplacingHotspotConfirmationKeepsTheNewQuestion() async throws {
        let model = AppModel()
        let first = Task { await model.askHotspot("First hotspot") }
        try await until { model.hotspotQuestion?.network == "First hotspot" }
        let second = Task { await model.askHotspot("Second hotspot") }
        try await until { model.hotspotQuestion?.network == "Second hotspot" }
        first.cancel()
        let firstAccepted = await first.value
        XCTAssertFalse(firstAccepted)
        XCTAssertEqual(model.hotspotQuestion?.network, "Second hotspot")
        model.answerHotspot(true)
        let secondAccepted = await second.value
        XCTAssertTrue(secondAccepted)
        XCTAssertNil(model.hotspotQuestion)
    }

    func testCancelledPortNeverReconnectsAfterALateHotspotAcceptance() async throws {
        let session = OpenPocketCine.CameraSession()
        var reply: CheckedContinuation<Bool, Never>?
        session.confirmHotspot = { _ in
            await withCheckedContinuation { reply = $0 }
        }
        let attempt = Task {
            try await session.connect(
                cameraID: a, setup: .phoneHotspot(network: "Test hotspot", password: nil),
                restoreAccessPoint: false)
        }
        try await until { reply != nil }
        attempt.cancel()
        reply?.resume(returning: true)
        do {
            _ = try await attempt.value
            XCTFail("A cancelled attempt must not connect")
        } catch is CancellationError {
            XCTAssertEqual(session.phase, .idle)
            XCTAssertNil(session.stationNetwork)
        }
    }

    /// A nameless first advert lists by its model; the record keeps the real advertised name.
    func testSightingsListByTitle() {
        let nameless = DjiAppleSighting(
            id: UUID(), name: "DJI camera", model: .resolve(modelId: 0x19, name: nil), modelId: 0x19)
        XCTAssertEqual(OpenPocketCine.CameraSession.sighting(nameless).name, nameless.model.name)
        XCTAssertEqual(OpenPocketCine.CameraSession.sighting(nameless).modelId, 0x19)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}

/// A scripted DJI pipeline: records scans, connects and forgets and holds each connect until the
/// test finishes it. A new connect or a disconnect cancels the one in flight.
@MainActor
final class FakeDJIPort: DJIConnectPort {
    var onSightings: (([DJISighting]) -> Void)?
    var onStage: ((DJIConnectionStage, String?) -> Void)?
    private(set) var connects: [(cameraID: String, setup: DJISetup, restoreAccessPoint: Bool)] = []
    private(set) var forgotten: [String] = []
    private var pending: CheckedContinuation<DJIConnection, Error>?

    func startScan() {}
    func stopScan() {}

    func connect(cameraID: String, setup: DJISetup, restoreAccessPoint: Bool) async throws -> DJIConnection {
        cancelPending()
        connects.append((cameraID, setup, restoreAccessPoint))
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func finish(_ result: Result<DJIConnection, Error>) {
        let waiter = pending
        pending = nil
        waiter?.resume(with: result)
    }

    func disconnect() { cancelPending() }
    func forget(cameraID: String) { forgotten.append(cameraID) }

    private func cancelPending() {
        let waiter = pending
        pending = nil
        waiter?.resume(throwing: CancellationError())
    }
}
