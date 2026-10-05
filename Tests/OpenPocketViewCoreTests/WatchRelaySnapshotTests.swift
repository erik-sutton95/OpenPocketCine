import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite("Watch relay snapshot from this app's camera status")
struct WatchRelaySnapshotTests {
    private func sampleState() -> WatchRelayState {
        WatchRelayState(
            isRecording: true,
            timecode: "01:02:03",
            media: "12 GB · 47%",
            cameraBatteryPercent: 80,
            cameraName: "Osmo Pocket 4",
            connection: .connected,
            feedLive: true)
    }

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
        #expect(state.media == "2 GB · 50%")
        #expect(state.cameraBatteryPercent == 41)
        #expect(!state.isPhotography)
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

    @Test("Wrist-down does not cover a live tally with open-on-iPhone")
    func placeholderKeepsLastTallyWhenUnreachable() {
        let live = sampleState()
        #expect(
            WatchMonitorPlaceholder.resolve(
                isReachable: false, state: live, hasFeed: true) == .none)
        #expect(
            WatchMonitorPlaceholder.resolve(
                isReachable: false, state: nil, hasFeed: false) == .openOnIPhone)
        #expect(
            WatchMonitorPlaceholder.resolve(
                isReachable: true, state: nil, hasFeed: false) == .none)
        let noCamera = WatchRelayState.snapshot(
            status: CameraStatus(), phase: .idle, cameraName: "", feedLive: false)
        #expect(
            WatchMonitorPlaceholder.resolve(
                isReachable: true, state: noCamera, hasFeed: false) == .noCamera)
    }

    @Test("Disconnect labels a retained picture, even while the wrist is down")
    func disconnectedSnapshotOverlaysOldFrame() {
        let noCamera = WatchRelayState.snapshot(
            status: CameraStatus(), phase: .idle, cameraName: "", feedLive: false)
        for reachable in [true, false] {
            #expect(
                WatchMonitorPlaceholder.resolve(
                    isReachable: reachable, state: noCamera, hasFeed: true) == .noCamera)
        }
    }
}
