import Foundation
import Testing

@testable import OpenPocketViewCore

struct MulticamTests {
    @Test func stationFallbackRequiresExplicitMissingQueryAndAcceptedSetter() {
        #expect(MulticamStationPolicy.decision(reply: [0xe0], allowMissingQuery: false) == .reject)
        #expect(
            MulticamStationPolicy.decision(reply: [0xe0], allowMissingQuery: true)
                == .setWithoutReadback)
        #expect(
            MulticamStationPolicy.decision(reply: [0, 0], allowMissingQuery: true) == .setAndVerify)
        #expect(
            MulticamStationPolicy.decision(reply: [0, 1], allowMissingQuery: true)
                == .alreadyStation)
        for reply: [UInt8] in [[], [0], [0xff], [1, 0xff], [0xe0, 0]] {
            #expect(
                MulticamStationPolicy.decision(reply: reply, allowMissingQuery: true) == .reject)
        }
        #expect(MulticamStationPolicy.acceptsSetter([0], missingQuery: true))
        #expect(!MulticamStationPolicy.acceptsSetter([0], missingQuery: false))
        #expect(MulticamStationPolicy.acceptsSetter([0, 0], missingQuery: false))
        for reply: [UInt8] in [[], [0xe0], [0, 0, 0], [0, 1]] {
            #expect(!MulticamStationPolicy.acceptsSetter(reply, missingQuery: true))
        }
    }

    @Test func stationRoleIsIndependentOfShootingMode() {
        let station = MulticamCommands.stationMode(true, seq: 42)
        #expect(station.receiver == 7)
        #expect(station.cmdSet == 7 && station.cmdId == 0x48)
        #expect(station.payload == [1])
        #expect(station.flags == 0x40 && station.seq == 42)
        #expect(MulticamCommands.stationMode(false, seq: 43).payload == [0])
        let getter = MulticamCommands.wifiWorkMode(seq: 44)
        #expect(getter.cmdSet == 7 && getter.cmdId == 0x39 && getter.payload == [0])
        let video = MulticamCommands.videoMode(seq: 45)
        #expect(video.receiver == 8 && video.cmdSet == 2 && video.cmdId == 0xe1)
        #expect(video.payload == [1])
        #expect(DumlTransport.scanFrames(Duml.encode(station)) == [station])
    }

    @Test func recordingControlWaitsForInitialWindowRatherThanHandshakeReply() {
        var handshake = [UInt8](repeating: 0, count: 15)
        handshake[8] = 1
        #expect(MulticamCommands.controlSequence(fromInitialWindow: handshake) == nil)
        var window = [UInt8](repeating: 0, count: 34)
        window[6] = 1
        window[8] = 0x38
        window[9] = 0x12
        #expect(MulticamCommands.controlSequence(fromInitialWindow: window) == 0x1240)
        window[6] = 3
        #expect(MulticamCommands.controlSequence(fromInitialWindow: window) == nil)
    }

    /// Both observed success shapes connect; only the Wi-Fi transition `01 ff`
    /// retries, and only within the attempt budget.
    @Test func joinPolicyAcceptsObservedSuccessAndRetriesOnlyTheTransition() {
        #expect(MulticamJoinPolicy.decision(reply: [0, 0, 0], attempt: 1) == .connected)
        #expect(MulticamJoinPolicy.decision(reply: [0, 0, 1], attempt: 1) == .rejected)
        #expect(MulticamJoinPolicy.decision(reply: [0, 0, 0, 0], attempt: 1) == .rejected)
        #expect(MulticamJoinPolicy.decision(reply: [1, 0xff], attempt: 1) == .retry)
        #expect(MulticamJoinPolicy.decision(reply: [0, 0], attempt: 2) == .connected)
        #expect(MulticamJoinPolicy.decision(reply: [1, 0xff], attempt: 3) == .rejected)
        #expect(MulticamJoinPolicy.decision(reply: [1, 1], attempt: 1) == .rejected)
        #expect(MulticamJoinPolicy.decision(reply: [], attempt: 1) == .rejected)
        #expect(MulticamJoinPolicy.decision(reply: [0], attempt: 1) == .rejected)
    }

    @Test func joinUsesUTF8LengthsAndRejectsOversizedSSID() throws {
        let command = try MulticamCommands.join(ssid: "Café", password: "", seq: 1)
        #expect(command.payload == [5] + Array("Café".utf8) + [0])
        #expect(throws: MulticamCommands.Failure.self) {
            try MulticamCommands.join(ssid: String(repeating: "a", count: 33), password: "", seq: 1)
        }
    }
}

struct MulticamSupportTests {
    @Test func previewIsLimitedToCapturedLiveEnableBodies() {
        for (id, name) in [
            (0x20, "Osmo Pocket 3"), (0x21, "Osmo Pocket 4"), (0x22, "Osmo Pocket 4 Pro"),
            (0x19, "Osmo Nano"),
        ] {
            let model = CameraModel.resolve(modelId: id, name: name)
            #expect(MulticamSupport.appears(model), "\(name)")
            #expect(MulticamSupport.hasPreview(model), "\(name)")
        }
        for (id, name) in [
            (0x10, "Osmo Action 2"), (0x12, "Osmo Action 3"), (0x14, "Osmo Action 4"),
            (0x15, "Osmo Action 5 Pro"), (0x17, "Osmo 360"), (0x18, "Osmo Action 6"),
        ] {
            let model = CameraModel.resolve(modelId: id, name: name)
            #expect(MulticamSupport.appears(model), "\(name)")
            #expect(!MulticamSupport.hasPreview(model), "\(name)")
        }
        let drone = CameraModel.resolve(modelId: 0x7E, name: "DJI Neo")
        #expect(!MulticamSupport.appears(drone))
        #expect(!MulticamSupport.hasPreview(drone))
        #expect(MulticamSupport.hasPreview(.resolve(modelId: nil, name: "OsmoPocket3-Test")))
        let oldPocket = CameraModel.resolve(modelId: nil, name: "Osmo Pocket 2")
        #expect(MulticamSupport.appears(oldPocket))
        #expect(!MulticamSupport.hasPreview(oldPocket))
    }

    @Test func missingRoleQueryOnlyForPocket3AndNanoE0() {
        for (name, accepted) in [
            ("OsmoPocket3-Test", true), ("OsmoNano-Test", true),
            ("OsmoPocket4P-Test", false), ("OsmoAction4-Test", false),
        ] {
            let model = CameraModel.resolve(modelId: nil, name: name)
            #expect(MulticamSupport.acceptsMissingRoleQuery(model, reply: [0xe0]) == accepted)
            for reply: [UInt8] in [[], [0], [0xff], [0xe0, 0], [0, 0]] {
                #expect(!MulticamSupport.acceptsMissingRoleQuery(model, reply: reply))
            }
        }
    }

    @Test func recoveryAllowsTwoRejoinsThenFails() {
        var recovery = MultiviewRecovery()
        let budget = (0..<3).map { _ in recovery.beginRejoin() }
        #expect(budget == [true, true, false])
        #expect(recovery.rejoins == 2)
        #expect(recovery.failed)
        let stalled = FeedWatchdog.Snapshot(
            now: 100, lastDecodedFrameAge: 20, lastVideoPacketAge: 20,
            lastStatusAge: 20, flowHealthy: false, pathReady: true, hasFormat: true,
            decoderFailed: false, live: true, sawPicture: true,
            secondsSinceLastEnable: 50)
        let action = recovery.action(stalled)
        #expect(action == .none)
    }

    /// Scripted camera for the shared station sequence: replies keyed by opcode, in order.
    @MainActor final class StationScript {
        var replies: [UInt8: [[UInt8]]]
        var sent: [UInt8] = []
        var seq: UInt16 = 0
        init(_ replies: [UInt8: [[UInt8]]]) { self.replies = replies }
        func exchange(_ frame: Duml.Frame, _: TimeInterval) throws -> Duml.Frame {
            sent.append(frame.cmdId)
            guard var queue = replies[frame.cmdId], !queue.isEmpty else {
                throw MulticamCommands.Failure.invalidInput  // lost reply
            }
            let payload = queue.removeFirst()
            replies[frame.cmdId] = queue
            return Duml.Frame(
                sender: 7, receiver: 2, seq: frame.seq, flags: 0x80, cmdSet: frame.cmdSet,
                cmdId: frame.cmdId, payload: payload)
        }
    }

    private func pocket4() -> CameraModel { .resolve(modelId: 0x22, name: "OsmoPocket4P-AAAA") }

    @MainActor @Test func stationJoinSetsRoleThenRetriesTransientJoin() async throws {
        let camera = StationScript([
            0x39: [[0, 0], [0, 1]], 0x48: [[0, 0]], 0x47: [[1, 0xff], [0, 0]],
        ])
        var probes = 0
        let outcome = try await StationJoin(
            model: pocket4(), ssid: "Rig Phone", password: "secret", hotspot: true
        ).run(
            identity: [0, 4, 0x41, 0x42], exchange: camera.exchange,
            send: { camera.sent.append($0.cmdId) },
            next: {
                camera.seq += 1
                return camera.seq
            }, status: { _ in }, hotspotReady: { true },
            verifyOnNetwork: {
                probes += 1
                return true
            }, sleep: { _ in })
        #expect(outcome == .joined)
        #expect(camera.sent == [0xe1, 0x39, 0x48, 0x39, 0x47, 0x47])
        #expect(probes == 0)
    }

    @MainActor @Test func stationJoinProbesExistingStationOnlyWhenAsked() async throws {
        let camera = StationScript([0x39: [[0, 1]], 0x47: [[0, 0]]])
        var join = StationJoin(model: pocket4(), ssid: "Rig Phone", password: "p", hotspot: true)
        join.probeExistingStation = true
        let outcome = try await join.run(
            identity: [0, 4, 0x41, 0x42], exchange: camera.exchange, send: { _ in },
            next: { 1 }, status: { _ in }, hotspotReady: { true },
            verifyOnNetwork: { true }, sleep: { _ in })
        #expect(outcome == .verified)
        #expect(camera.sent == [0x39])
    }

    @MainActor @Test func stationJoinChecksLanWhenJoinReplyIsLostAndRejectsBadCredentials()
        async throws
    {
        let lost = StationScript([0x39: [[0, 1]]])
        let found = try await StationJoin(
            model: pocket4(), ssid: "Rig Phone", password: "p", hotspot: false
        ).run(
            identity: [0, 4, 0x41, 0x42], exchange: lost.exchange, send: { _ in }, next: { 1 },
            status: { _ in }, hotspotReady: { false }, verifyOnNetwork: { true }, sleep: { _ in })
        #expect(found == .verified)

        let refused = StationScript([0x39: [[0, 1]], 0x47: [[1, 0xff], [1, 0xff], [1, 0xff]]])
        await #expect(throws: StationJoin.Failure.joinRejected) {
            _ = try await StationJoin(
                model: pocket4(), ssid: "Rig Phone", password: "p", hotspot: false
            ).run(
                identity: [0, 4, 0x41, 0x42], exchange: refused.exchange, send: { _ in },
                next: { 1 }, status: { _ in }, hotspotReady: { false },
                verifyOnNetwork: { false }, sleep: { _ in })
        }
        await #expect(throws: StationJoin.Failure.rejected) {
            _ = try await StationJoin(
                model: pocket4(), ssid: "Rig Phone", password: "p", hotspot: false
            ).run(
                identity: [0xe4], exchange: refused.exchange, send: { _ in }, next: { 1 },
                status: { _ in }, hotspotReady: { false }, verifyOnNetwork: { false },
                sleep: { _ in })
        }
    }
}
