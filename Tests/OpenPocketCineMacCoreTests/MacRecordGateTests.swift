import Foundation
import Testing

@testable import OpenPocketCineMacCore

struct MacRecordGateTests {
    private func camera(
        _ id: UUID, recording: Bool?, age: TimeInterval = 0, busy: Bool = false,
        connected: Bool = true
    ) -> MacRecordCamera {
        MacRecordCamera(
            id: id, recording: recording, statusAge: age, busy: busy, connected: connected)
    }

    @Test func freshIdleCameraMayStartAndFreshRecordingCameraMayStop() {
        let idle = UUID()
        let rolling = UUID()
        #expect(MacRecordGate.toggle(camera(idle, recording: false)) == .start)
        #expect(MacRecordGate.toggle(camera(rolling, recording: true)) == .stop)
    }

    @Test func staleOrBusyCameraRefuses() {
        let id = UUID()
        #expect(MacRecordGate.toggle(camera(id, recording: false, age: 3)) == .refuse)
        #expect(MacRecordGate.toggle(camera(id, recording: false, busy: true)) == .refuse)
        #expect(MacRecordGate.toggle(camera(id, recording: nil)) == .refuse)
        #expect(MacRecordGate.toggle(camera(id, recording: false, connected: false)) == .refuse)
    }

    @Test func groupStartSkipsCamerasAlreadyRecording() {
        let rolling = UUID()
        let idle = UUID()
        let decision = MacRecordGate.group(
            [camera(rolling, recording: true), camera(idle, recording: false)], stop: false)
        #expect(!decision.refused)
        #expect(decision.actions[rolling] == .skip)
        #expect(decision.actions[idle] == .start)
    }

    @Test func oneStaleCameraRefusesTheGroup() {
        let fresh = UUID()
        let stale = UUID()
        let decision = MacRecordGate.group(
            [camera(fresh, recording: false), camera(stale, recording: false, age: 4)], stop: false)
        #expect(decision.refused)
        #expect(decision.actions[fresh] == .refuse)
        #expect(decision.actions[stale] == .refuse)
    }

    @Test func mixedResultStaysOnEachTile() {
        let confirmed = UUID()
        let missed = UUID()
        let report = MacGroupRecordReport.make(
            [confirmed: .confirmed, missed: .unconfirmed], stop: false)
        #expect(report.perTile[confirmed] == .confirmed)
        #expect(report.perTile[missed] == .unconfirmed)
        #expect(report.summary == "1 of 2 confirmed · check camera tiles")
    }
}
