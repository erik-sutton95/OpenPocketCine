import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite("Watch relay wire protocol")
struct WatchRelayProtocolTests {
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

    @Test("A ticking timecode is not a state change")
    func liveReadoutsDoNotCountAsStateChange() {
        let state = sampleState()
        let ticked = WatchRelayState(
            isRecording: state.isRecording,
            timecode: "01:02:04",
            media: state.media,
            cameraBatteryPercent: state.cameraBatteryPercent,
            cameraName: state.cameraName,
            connection: state.connection,
            feedLive: state.feedLive)
        #expect(ticked != state)
        #expect(ticked.matchesIgnoringLiveReadouts(state))
    }

    @Test("A stills-mode flip is a state change")
    func modeFlipCountsAsStateChange() {
        let state = sampleState()
        let photography = WatchRelayState(
            isRecording: state.isRecording,
            timecode: state.timecode,
            media: state.media,
            cameraBatteryPercent: state.cameraBatteryPercent,
            cameraName: state.cameraName,
            connection: state.connection,
            feedLive: state.feedLive,
            isPhotography: true)
        #expect(!photography.matchesIgnoringLiveReadouts(state))
    }

    @Test("State round-trips through its envelope")
    func stateEnvelopeRoundTrips() throws {
        let state = sampleState()
        let envelope = try WatchRelayEnvelope.encode(kind: .state, payload: state)
        #expect(try WatchRelayEnvelope.kind(of: envelope) == .state)
        let decoded = try WatchRelayEnvelope.decode(WatchRelayState.self, from: envelope)
        #expect(decoded == state)
    }

    @Test("State without photography keys still decodes")
    func stateWithoutPhotographyKeysDecodes() throws {
        let json = """
            {"isRecording":false,"timecode":"--:--:--","media":"—","cameraBatteryPercent":-1,"cameraName":"","connection":"noCamera","feedLive":false}
            """
        var envelope = Data([WatchRelayProtocol.Kind.state.rawValue])
        envelope.append(Data(json.utf8))
        let decoded = try WatchRelayEnvelope.decode(WatchRelayState.self, from: envelope)
        #expect(decoded.isPhotography == false)
        #expect(decoded.feedAspectRatio == 16.0 / 9.0)
        #expect(decoded.connection == .noCamera)
    }

    @Test("Frame round-trips through its envelope")
    func frameEnvelopeRoundTrips() throws {
        let frame = WatchRelayFrame(
            jpeg: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
            timecode: "12:34:56",
            isRecording: true)
        let envelope = try WatchRelayEnvelope.encode(kind: .frame, payload: frame)
        #expect(try WatchRelayEnvelope.kind(of: envelope) == .frame)
        let decoded = try WatchRelayEnvelope.decode(WatchRelayFrame.self, from: envelope)
        #expect(decoded == frame)
    }

    @Test("Command round-trips through its envelope")
    func commandEnvelopeRoundTrips() throws {
        let envelope = try WatchRelayEnvelope.encode(
            kind: .command, payload: WatchRelayCommand.toggleRecord)
        #expect(try WatchRelayEnvelope.kind(of: envelope) == .command)
        #expect(
            try WatchRelayEnvelope.decode(WatchRelayCommand.self, from: envelope) == .toggleRecord)
    }

    @Test("Result round-trips through its envelope")
    func resultEnvelopeRoundTrips() throws {
        let result = WatchCommandResult(
            accepted: false, isRecording: true, error: WatchRelayCopy.busy)
        let envelope = try WatchRelayEnvelope.encode(kind: .result, payload: result)
        #expect(try WatchRelayEnvelope.kind(of: envelope) == .result)
        #expect(try WatchRelayEnvelope.decode(WatchCommandResult.self, from: envelope) == result)
    }

    @Test("Empty envelope reports an empty error")
    func emptyEnvelopeThrows() {
        #expect(throws: WatchRelayEnvelopeError.empty) {
            try WatchRelayEnvelope.kind(of: Data())
        }
    }

    @Test("Unknown kind byte is rejected")
    func unknownKindThrows() {
        #expect(throws: WatchRelayEnvelopeError.unknownKind(0x99)) {
            try WatchRelayEnvelope.kind(of: Data([0x99, 0x00]))
        }
    }

    @Test("Storage label prefers GB and percent, then remaining minutes")
    func storageLabelMatchesPhoneHUD() {
        #expect(
            WatchRelayMedia.label(
                storageFreeMb: 12_288, storageTotalMb: 26_624,
                sdFreeMb: 0, sdTotalMb: 0, recordRemainingSec: 600)
                == "12 GB · 46%")
        #expect(
            WatchRelayMedia.label(
                storageFreeMb: 0, storageTotalMb: 0,
                sdFreeMb: 0, sdTotalMb: 0, recordRemainingSec: 180)
                == "3 Min")
        #expect(
            WatchRelayMedia.label(
                storageFreeMb: 0, storageTotalMb: 0,
                sdFreeMb: 0, sdTotalMb: 0, recordRemainingSec: 0)
                == "—")
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

    @Test("Operator copy never names a sister app")
    func operatorCopyIsPocketFacing() {
        let facing = [
            WatchRelayCopy.openOnIPhone,
            WatchRelayCopy.noCamera,
            WatchRelayCopy.waitingLive,
            WatchRelayCopy.connectFirst,
            WatchRelayCopy.switchToVideo,
            WatchRelayCopy.switchToPhoto,
            WatchRelayCopy.busy,
        ]
        for text in facing {
            #expect(!text.localizedCaseInsensitiveContains("OpenZCine"))
            #expect(!text.localizedCaseInsensitiveContains("Nikon"))
        }
    }
}
