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
