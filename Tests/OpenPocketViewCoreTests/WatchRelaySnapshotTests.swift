import Foundation
import OpenCineCore
import OpenCineMedia
import Testing

@testable import OpenPocketViewCore

@Suite("Watch relay snapshot from this app's camera status")
struct WatchRelaySnapshotTests {
    @Test("Snapshot maps live telemetry onto the wrist state")
    func snapshotMapsLiveStatus() {
        var status = CameraStatus()
        status.isRecording = true
        status.timecode = "01:02:03:04"
        status.storageFreeMb = 2048
        status.storageTotalMb = 4096
        status.batteryPercent = 41
        status.shootingMode = Int(ShootingMode.video.rawValue)
        let state = WatchRelayState.snapshot(
            status: status, phase: .live, cameraName: "Pocket 4 Pro", feedLive: true)
        #expect(state.connection == .connected)
        #expect(state.feedLive)
        #expect(state.isRecording)
        #expect(state.timecode == "01:02:03")
        #expect(state.media == "2.15 GB · 50%")
        #expect(state.cameraBatteryPercent == 41)
        #expect(!state.isPhotography)
    }

    @Test("Typed storage keeps exact bytes, zero and unknown on the wrist")
    func typedStorageOverridesLegacyMegabytesWithoutInventingUnknown() {
        var status = CameraStatus()
        status.storageFreeMb = 2048
        status.storageTotalMb = 4096
        func state(_ bytes: UInt64) -> WatchRelayState {
            let volume = StorageVolume(
                id: "active",
                freeBytes: ObservedValue(bytes, origin: .cameraReported, at: nil),
                totalBytes: ObservedValue(UInt64(2000), origin: .cameraReported, at: nil))
            return .snapshot(
                status: status, phase: .live, cameraName: "SIMULATED", feedLive: true,
                storage: ObservedValue([volume], origin: .cameraReported, at: nil))
        }
        #expect(state(1001).media == "1 KB · 50%")
        #expect(state(0).media == "0 B · 0%")
        let unknown: StorageStatus = .unknown
        #expect(
            WatchRelayState.snapshot(
                status: status, phase: .live, cameraName: "SIMULATED", feedLive: true,
                storage: unknown
            ).media == StorageReadout.unavailable)
    }

    @Test("Snapshot is noCamera when the phone is not live")
    func snapshotNoCameraWhenIdle() {
        let state = WatchRelayState.snapshot(
            status: CameraStatus(), phase: .idle, cameraName: "", feedLive: false)
        #expect(state.connection == .noCamera)
        #expect(!state.feedLive)
        #expect(state.timecode == "--:--:--")
    }

    @Test("Photo shooting mode sets photography chrome")
    func photoModeSetsPhotography() {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.photo.rawValue)
        let state = WatchRelayState.snapshot(
            status: status, phase: .live, cameraName: "Pocket", feedLive: true)
        #expect(state.isPhotography)

        status.shootingMode = Int(ShootingMode.photoRawPocket3AndNano)
        let pocket3 = WatchRelayState.snapshot(
            status: status, phase: .live, cameraName: "Pocket 3", feedLive: true)
        #expect(pocket3.isPhotography)

        status.shootingMode = Int(ShootingMode.superNight.rawValue)
        let lowLight = WatchRelayState.snapshot(
            status: status, phase: .live, cameraName: "Pocket 3", feedLive: true)
        #expect(!lowLight.isPhotography)
    }
}
