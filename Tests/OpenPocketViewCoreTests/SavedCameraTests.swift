import Foundation
import OpenCineCore
import Testing

@testable import OpenPocketViewCore

@Suite struct SavedCameraTests {
    /// A saved camera as the shared document holds it (SHELL-02): camera Wi-Fi is its first route.
    private func camera(
        id: UUID = UUID(),
        name: String = "OsmoPocket4P-AAAA",
        model: String = "Osmo Pocket 4 Pro",
        ssid: String? = "OsmoPocket4P-AAAA"
    ) -> SavedCamera {
        SavedCamera(
            id: id.uuidString, integration: DJICameraSessionAdapter.integration,
            advertisedName: name, model: model,
            routes: [SavedRoute(key: "ap", kind: .cameraAccessPoint, network: ssid, bluetooth: true)])
    }

    @Test func wifiCredsDoNotCrossBodies() {
        let pocket = UUID()
        let nano = UUID()
        let memory = CameraWifiResolution.Memory(
            cameraId: pocket, ssid: "OsmoPocket4P-AAAA", password: "pocket-pass")
        let stolen = CameraWifiResolution.resolve(
            cameraId: nano,
            savedSSID: nil,
            memory: memory,
            keychainSSID: nil,
            keychainPassword: nil)
        #expect(stolen.ssid == nil)
        #expect(stolen.password == nil)
        #expect(!stolen.skipBle)
        #expect(stolen.source == "none")

        let own = CameraWifiResolution.resolve(
            cameraId: pocket,
            savedSSID: "OsmoPocket4P-AAAA",
            memory: memory,
            keychainSSID: nil,
            keychainPassword: nil)
        #expect(own.ssid == "OsmoPocket4P-AAAA")
        #expect(own.password == "pocket-pass")
        #expect(own.skipBle)
        #expect(own.source == "memory")

        let nanoStore = CameraWifiResolution.resolve(
            cameraId: nano,
            savedSSID: "OsmoNano-ABCD",
            memory: memory,
            keychainSSID: "OsmoNano-ABCD",
            keychainPassword: "nano-pass")
        #expect(nanoStore.ssid == "OsmoNano-ABCD")
        #expect(nanoStore.password == "nano-pass")
        #expect(nanoStore.skipBle)
        #expect(nanoStore.source == "keychain")
    }

    @Test func ssidCannotBeStolenFromAnotherSavedBody() {
        let pocket = UUID()
        let nano = UUID()
        let saved = [
            camera(id: pocket, name: "OsmoPocket4P-AAAA", ssid: "OsmoPocket4P-AAAA"),
            camera(
                id: nano, name: "OsmoNano-ABCD", model: "Osmo Nano", ssid: nil),
        ]
        #expect(
            CameraWifiResolution.isSSIDOwnedByAnotherCamera(
                "OsmoPocket4P-AAAA", cameraId: nano.uuidString, saved: saved))
        #expect(
            !CameraWifiResolution.isSSIDOwnedByAnotherCamera(
                "OsmoNano-ABCD", cameraId: nano.uuidString, saved: saved))
        #expect(
            !CameraWifiResolution.isSSIDOwnedByAnotherCamera(
                "OsmoPocket4P-AAAA", cameraId: pocket.uuidString, saved: saved))
        #expect(
            CameraWifiResolution.isSSIDOwnedByAnotherCamera(
                " osmonano-abcd ", cameraId: pocket.uuidString, saved: saved),
            "an advertised name owns its network too")
    }

    @Test func foundCameraUpgradesNamelessFirstAdvert() {
        #expect(FoundCameraIdentity.isGenericName("DJI camera"))
        #expect(FoundCameraIdentity.isGenericName(""))
        #expect(!FoundCameraIdentity.isGenericName("OsmoNano-ABCD"))
        #expect(
            FoundCameraIdentity.shouldReplace(
                existingName: "DJI camera", existingModelId: nil,
                incomingName: "OsmoNano-ABCD", incomingModelId: 0x19))
        #expect(
            !FoundCameraIdentity.shouldReplace(
                existingName: "OsmoNano-ABCD", existingModelId: 0x19,
                incomingName: "DJI camera", incomingModelId: nil))
        #expect(
            FoundCameraIdentity.shouldReplace(
                existingName: "OsmoPocket4P-AAAA", existingModelId: 0x22,
                incomingName: "VanCam", incomingModelId: 0x22),
            "BLE local name follows a SoftAP rename — keep the scan row current")
        #expect(
            !FoundCameraIdentity.shouldReplace(
                existingName: "VanCam", existingModelId: 0x22,
                incomingName: "DJI camera", incomingModelId: 0x22))
    }

    @Test func namelessAdvertKeepsSavedNanoIdentity() {
        let next = FoundCameraIdentity.enriched(
            name: "DJI camera", modelId: nil,
            savedName: "OsmoNano-ABCD", savedModelId: 0x19)
        #expect(next.name == "OsmoNano-ABCD")
        #expect(next.modelId == 0x19)
        #expect(CameraModel.resolve(modelId: next.modelId, name: next.name).name == "Osmo Nano")
        #expect(CameraModel.resolve(modelId: next.modelId, name: next.name).usesCapturedLiveEnable)
    }

    @Test func pocketSSIDConflictsWithNanoBody() {
        #expect(
            CameraBodyFamily.ssidConflictsWithBody(
                ssid: "OsmoPocket4P-AAAA", modelId: 0x19, advertisedName: "OsmoNano-ABCD"))
        #expect(
            CameraBodyFamily.ssidConflictsWithBody(
                ssid: "OsmoNano-ABCD", modelId: 0x22, advertisedName: "OsmoPocket4P-AAAA"))
        #expect(
            !CameraBodyFamily.ssidConflictsWithBody(
                ssid: "OsmoNano-ABCD", modelId: 0x19, advertisedName: "OsmoNano-ABCD"))
        #expect(
            !CameraBodyFamily.ssidConflictsWithBody(
                ssid: "DJI-XXXX", modelId: 0x19, advertisedName: "OsmoNano-ABCD"))
    }

    @Test func scanListSeparatesNamelessPocketAndNano() {
        #expect(
            FoundCameraIdentity.listTitle(
                advertisedName: "DJI camera", modelName: "Osmo Nano") == "Osmo Nano")
        #expect(
            FoundCameraIdentity.listTitle(
                advertisedName: "OsmoNano-BBBB", modelName: "Osmo Nano") == "OsmoNano-BBBB")
        #expect(
            FoundCameraIdentity.listSubtitle(
                advertisedName: "DJI camera", modelName: "Osmo Pocket 4 Pro"
            )
            .contains("Pocket"))
        #expect(
            FoundCameraIdentity.listSubtitle(
                advertisedName: "OsmoNano-BBBB", modelName: "Osmo Nano"
            )
            .contains("Nano"))
        #expect(CameraSoftAP.isOsmoSoftAPSSID("OsmoPocket4P-AAAA"))
        #expect(CameraSoftAP.isOsmoSoftAPSSID("OsmoNano-BBBB"))
        #expect(!CameraSoftAP.isOsmoSoftAPSSID("HomeWiFi"))
    }

    @Test func renamedSoftAPUsesLiveAdvertisedSSIDNotCache() {
        let id = UUID()
        let memory = CameraWifiResolution.Memory(
            cameraId: id, ssid: "OsmoPocket4P-AAAA", password: "pocket-pass")
        let renamed = CameraWifiResolution.resolve(
            cameraId: id,
            savedSSID: "OsmoPocket4P-AAAA",
            memory: memory,
            keychainSSID: "OsmoPocket4P-AAAA",
            keychainPassword: "pocket-pass",
            advertisedName: "VanCam")
        #expect(renamed.ssid == "VanCam")
        #expect(renamed.password == "pocket-pass")
        #expect(renamed.skipBle)
        #expect(renamed.source == "memory")

        let generic = CameraWifiResolution.resolve(
            cameraId: id,
            savedSSID: "OsmoPocket4P-AAAA",
            memory: memory,
            keychainSSID: "OsmoPocket4P-AAAA",
            keychainPassword: "pocket-pass",
            advertisedName: "DJI camera")
        #expect(generic.ssid == "OsmoPocket4P-AAAA")
        #expect(generic.skipBle)

        let matching = CameraWifiResolution.resolve(
            cameraId: id,
            savedSSID: "OsmoPocket4P-AAAA",
            memory: memory,
            keychainSSID: "OsmoPocket4P-AAAA",
            keychainPassword: "pocket-pass",
            advertisedName: "OsmoPocket4P-AAAA")
        #expect(matching.ssid == "OsmoPocket4P-AAAA")
        #expect(matching.skipBle)
    }

    @Test func leftoverGATTMustNotDriveTheSelectedSession() {
        let nano = UUID()
        let pocket = UUID()
        #expect(BlePeerPolicy.acceptsGATT(from: nano, selected: nano))
        #expect(!BlePeerPolicy.acceptsGATT(from: pocket, selected: nano))
        #expect(!BlePeerPolicy.acceptsGATT(from: pocket, selected: nil))
    }

}
