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

    @Test func stationJoinAcceptsObservedThreeByteSuccess() {
        #expect(MulticamJoinPolicy.decision(reply: [0, 0, 0], attempt: 1) == .connected)
        #expect(MulticamJoinPolicy.decision(reply: [0, 0, 1], attempt: 1) == .rejected)
        #expect(MulticamJoinPolicy.decision(reply: [0, 0, 0, 0], attempt: 1) == .rejected)
    }

    @Test func wifiTransitionRetriesOnlyObservedRejectionWithinBudget() {
        #expect(MulticamJoinPolicy.decision(reply: [1, 0xff], attempt: 1) == .retry)
        #expect(MulticamJoinPolicy.decision(reply: [0, 0], attempt: 2) == .connected)
        #expect(MulticamJoinPolicy.decision(reply: [1, 0xff], attempt: 3) == .rejected)
        #expect(MulticamJoinPolicy.decision(reply: [1, 1], attempt: 1) == .rejected)
        #expect(MulticamJoinPolicy.decision(reply: [], attempt: 1) == .rejected)
        #expect(MulticamJoinPolicy.decision(reply: [0], attempt: 1) == .rejected)
    }

    @Test func configurationHasConsistentLengthsAndNoCapturedDestination() throws {
        let url = "rtmp://192.168.1.9:1935/live/tile-test"
        let command = try MulticamCommands.configuration(url: url, seq: 88)
        let p = command.payload
        #expect(Int(p[1]) + Int(p[2]) * 256 == p.count - 3)
        #expect(Int(p[12]) + Int(p[13]) * 256 == p.count - 14)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(p.dropFirst(14))) as? [String: Any])
        #expect(object["rtmpAddress"] as? String == url)
        #expect(object["codec"] as? String == "HEVC")
        #expect(DumlTransport.scanFrames(Duml.encode(command)) == [command])
        #expect(MulticamCommands.streaming(false, seq: 1).payload == [1, 1, 0x1a, 0, 1, 2])
    }

    @Test func joinUsesUTF8LengthsAndRejectsOversizedSSID() throws {
        let command = try MulticamCommands.join(ssid: "Café", password: "", seq: 1)
        #expect(command.payload == [5] + Array("Café".utf8) + [0])
        #expect(throws: MulticamCommands.Failure.self) {
            try MulticamCommands.join(ssid: String(repeating: "a", count: 33), password: "", seq: 1)
        }
    }

    @Test func chunksSurviveEveryTCPBoundary() throws {
        let payload = (0..<601).map { UInt8($0 % 251) }
        let encoded = RTMPIngest.encode(.init(type: 9, stream: 1, payload: payload))
        for size in [1, 2, 7, 127, 128, 129, 307] {
            var parser = RTMPIngest.Parser()
            var messages: [RTMPIngest.Message] = []
            for index in stride(from: 0, to: encoded.count, by: size) {
                messages += try parser.append(
                    Array(encoded[index..<min(encoded.count, index + size)]))
            }
            #expect(messages.count == 1)
            #expect(messages.first?.payload == payload)
            #expect(messages.first?.stream == 1)
        }
    }

    @Test func compressedHeadersKeepTimestampAndStream() throws {
        // Full header followed by type-1 and type-3 headers on chunk stream 3.
        var parser = RTMPIngest.Parser()
        let a: [UInt8] = [3, 0, 0, 10, 0, 0, 1, 9, 1, 0, 0, 0, 42]
        let b: [UInt8] = [0x43, 0, 0, 5, 0, 0, 1, 9, 43]
        let c: [UInt8] = [0xc3, 44]
        let messages = try parser.append(a + b + c)
        #expect(messages.map(\.timestamp) == [10, 15, 20])
        #expect(messages.map(\.stream) == [1, 1, 1])
        #expect(messages.map(\.payload) == [[42], [43], [44]])
    }

    @Test func oversizedChunksAndMissingHeadersFail() throws {
        var parser = RTMPIngest.Parser()
        #expect(throws: RTMPIngest.Failure.self) { try parser.append([0xc3, 0]) }
        var other = RTMPIngest.Parser()
        let huge = RTMPIngest.encode(.init(type: 1, payload: [0, 2, 0, 0]))
        #expect(throws: RTMPIngest.Failure.self) { try other.append(huge) }
    }

    @Test func amfPublishRoundTripAndTruncation() throws {
        let bytes = RTMPIngest.amf([
            .string("publish"), .number(3), .null, .string("tile-test"), .string("live"),
        ])
        let values = try RTMPIngest.values(bytes)
        #expect(values[0].string == "publish")
        #expect(values[1].number == 3)
        #expect(values[3].string == "tile-test")
        #expect(throws: RTMPIngest.Failure.self) { try RTMPIngest.values(Array(bytes.dropLast())) }
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
        for (id, name) in [(0x15, "Osmo Action 5 Pro"), (0x17, "Osmo 360")] {
            let model = CameraModel.resolve(modelId: id, name: name)
            #expect(MulticamSupport.appears(model), "\(name)")
            #expect(!MulticamSupport.hasPreview(model), "\(name)")
        }
        let drone = CameraModel.resolve(modelId: 0x7E, name: "DJI Neo")
        #expect(!MulticamSupport.appears(drone))
        #expect(!MulticamSupport.hasPreview(drone))
    }

    @Test func missingRoleQueryOnlyForPocket3AndNanoE0() {
        for (name, accepted) in [
            ("OsmoPocket3-Test", true), ("OsmoNano-Test", true),
            ("OsmoPocket4P-Test", false), ("OsmoAction4-Test", false),
        ] {
            let model = CameraModel.resolve(modelId: nil, name: name)
            #expect(MulticamSupport.acceptsMissingRoleQuery(model, reply: [0xe0]) == accepted)
            for reply: [UInt8] in [[], [0], [0xe0, 0], [0, 0]] {
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
