import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct SavedCameraTests {
    private func camera(
        id: UUID = UUID(),
        name: String = "OsmoPocket4P-AAAA",
        model: String = "Osmo Pocket 4 Pro",
        ssid: String? = "OsmoPocket4P-AAAA",
        at: Date = Date(),
        custom: String? = nil
    ) -> SavedCamera {
        SavedCamera(
            id: id,
            advertisedName: name,
            modelName: model,
            lastSSID: ssid,
            lastConnectedAt: at,
            customName: custom
        )
    }

    @Test func upsertKeepsNewestFirstAndPreservesCustomName() {
        let id = UUID()
        let older = camera(id: id, ssid: nil, at: Date(timeIntervalSince1970: 1), custom: "A-cam")
        let newer = camera(id: id, ssid: "OsmoPocket4P-AAAA", at: Date(timeIntervalSince1970: 9))
        let other = camera(
            name: "OsmoPocket3-AAAA", model: "Osmo Pocket 3", at: Date(timeIntervalSince1970: 5))

        let result = SavedCameras.upserting(newer, into: [older, other])
        #expect(result.count == 2)
        #expect(result[0].id == id)
        #expect(result[0].customName == "A-cam")
        #expect(result[0].lastSSID == "OsmoPocket4P-AAAA")
        #expect(result[1].id == other.id)
    }

    @Test func upsertKeepsSavedModelIdWhenReconnectAdvertOmitsIt() {
        let id = UUID()
        let first = camera(id: id, model: "Osmo Nano")
        var stored = first
        stored.modelId = 0x19
        let reconnect = camera(
            id: id, name: "DJI camera", model: "DJI Osmo camera", ssid: "OsmoNano-ABCD")
        let result = SavedCameras.upserting(reconnect, into: [stored])
        #expect(result[0].modelId == 0x19)
    }

    @Test func canonicalizedDropsDuplicateIds() {
        let id = UUID()
        let a = camera(id: id, at: Date(timeIntervalSince1970: 2))
        let b = camera(id: id, at: Date(timeIntervalSince1970: 1))
        let result = SavedCameras.canonicalized([a, b])
        #expect(result.count == 1)
        #expect(result[0].lastConnectedAt == a.lastConnectedAt)
    }

    @Test func renameAndRemove() {
        let id = UUID()
        let stored = [camera(id: id)]
        let renamed = SavedCameras.renaming(id, to: "  Van  ", in: stored)
        #expect(renamed[0].customName == "Van")
        #expect(renamed[0].displayName == "Van")
        let cleared = SavedCameras.renaming(id, to: "   ", in: renamed)
        #expect(cleared[0].customName == nil)
        #expect(cleared[0].displayName == "OsmoPocket4P-AAAA")
        #expect(SavedCameras.removing(id, from: stored).isEmpty)
    }

    @Test func launchDestinationMatchesOpenZCinePolicy() {
        #expect(CameraStartupPolicy.launchDestination(savedCameras: []) == .addCamera)
        #expect(CameraStartupPolicy.launchDestination(savedCameras: [camera()]) == .savedCameras)
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
                "OsmoPocket4P-AAAA", cameraId: nano, saved: saved))
        #expect(
            !CameraWifiResolution.isSSIDOwnedByAnotherCamera(
                "OsmoNano-ABCD", cameraId: nano, saved: saved))
        #expect(
            !CameraWifiResolution.isSSIDOwnedByAnotherCamera(
                "OsmoPocket4P-AAAA", cameraId: pocket, saved: saved))
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

    @Test func leftoverGATTMustNotDriveTheSelectedSession() {
        let nano = UUID()
        let pocket = UUID()
        #expect(BlePeerPolicy.acceptsGATT(from: nano, selected: nano))
        #expect(!BlePeerPolicy.acceptsGATT(from: pocket, selected: nano))
        #expect(!BlePeerPolicy.acceptsGATT(from: pocket, selected: nil))
    }

    @Test func wizardStepsFollowConnectionPhase() {
        #expect(ConnectionPhase.scanning.pocketWizardStep == 1)
        #expect(ConnectionPhase.awaitingApproval.pocketWizardStep == 2)
        #expect(ConnectionPhase.joiningWifi.pocketWizardStep == 3)
        #expect(ConnectionPhase.openingDatalink.pocketWizardStep == 4)
        #expect(ConnectionPhase.pocketWizardStepCount == 4)
        #expect(ConnectionPhase.failed("x").pocketWizardStep == 1)
    }
}
