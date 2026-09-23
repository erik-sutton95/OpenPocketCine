import Foundation
import Testing

@testable import OpenPocketViewCore

/// Synthetic transport and operator requests cross the real protocol/policy interfaces.
/// No simulated decoder, socket, UI or camera result is reported as physical evidence.
@Suite("Seeded connection chaos", .serialized)
struct ConnectionChaosTests {
    @Test(arguments: ChaosProfile.allCases)
    func packetAndControlStorm(profile: ChaosProfile) throws {
        let environment = ProcessInfo.processInfo.environment
        if let selected = environment["OPC_CHAOS_PROFILE"] {
            #expect(ChaosProfile(rawValue: selected) != nil)
            if selected != profile.rawValue { return }
        }
        let first = UInt64(environment["OPC_CHAOS_SEED"] ?? "401") ?? 401
        let count = Int(environment["OPC_CHAOS_SEEDS"] ?? "8") ?? 8
        #expect((1...1_000).contains(count))
        guard (1...1_000).contains(count) else { return }
        for offset in 0..<count {
            let seed = first &+ UInt64(offset)
            var experiment = ChaosExperiment(seed: seed, profile: profile)
            let result = experiment.run(canary: environment["OPC_CHAOS_CANARY"] == "1")
            if let output = environment["OPC_CHAOS_OUTPUT"] {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(result).write(
                    to: URL(fileURLWithPath: output)
                        .appendingPathComponent("\(profile.rawValue)-\(seed).json"),
                    options: .atomic)
            }
            #expect(
                result.failures.isEmpty,
                "seed=\(seed) profile=\(profile.rawValue) failures=\(result.failures)")
        }
    }

    @Test func networkProfileReplayIsDeterministicAndBounded() {
        for profile in ChaosProfile.allCases {
            var first = ChaosExperiment(seed: 401, profile: profile)
            var second = ChaosExperiment(seed: 401, profile: profile)
            #expect(first.run() == second.run())
        }
    }
}

enum ChaosProfile: String, CaseIterable, Codable, Sendable {
    case baseline, loss, burst, jitter, duplicate, congestion, blackout, combined
}

private struct ChaosRandom {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func chance(_ percent: UInt64) -> Bool { next() % 100 < percent }
}

private struct ChaosDatagram {
    var due: Int
    var order: Int
    var bytes: [UInt8]
    var key: UInt16?
    var sequence: UInt16
    var epoch: Int
}

/// Virtual milliseconds, finite byte queue, no sleeps or platform transport.
private struct ChaosLink {
    static let byteLimit = 8_192
    var random: ChaosRandom
    var pending: [ChaosDatagram] = []
    var bytes = 0
    var peakBytes = 0
    var dropped = 0
    var duplicated = 0
    var delayed = 0
    var serial = 0
    var nextWireTime = 0
    var offered = 0

    mutating func send(
        _ payload: [UInt8], key: UInt16? = nil, sequence: UInt16 = 0,
        epoch: Int, at now: Int, profile: ChaosProfile
    ) {
        offered += 1
        let combined = profile == .combined
        if (profile == .loss || combined) && random.chance(10)
            || (profile == .burst || combined) && offered % 47 < 6
            || (profile == .blackout || combined) && (3_000..<9_500).contains(now)
        {
            dropped += 1
            return
        }
        let copies = (profile == .duplicate || combined) && random.chance(20) ? 2 : 1
        for _ in 0..<copies {
            guard bytes + payload.count <= Self.byteLimit else {
                dropped += 1
                continue
            }
            var due = now
            if profile == .congestion || combined {
                // Eight bytes per millisecond: below the generated video rate.
                due = max(now, nextWireTime) + max(1, (payload.count + 7) / 8)
                nextWireTime = due
            }
            if profile == .jitter || combined { due += Int(random.next() % 121) }
            if due > now { delayed += 1 }
            serial += 1
            pending.append(
                ChaosDatagram(
                    due: due, order: serial, bytes: payload, key: key,
                    sequence: sequence, epoch: epoch))
            bytes += payload.count
            peakBytes = max(peakBytes, bytes)
        }
        if copies == 2 { duplicated += 1 }
    }

    mutating func receive(at now: Int) -> [ChaosDatagram] {
        let ready = pending.filter { $0.due <= now }.sorted {
            $0.due == $1.due ? $0.order < $1.order : $0.due < $1.due
        }
        pending.removeAll { $0.due <= now }
        bytes -= ready.reduce(0) { $0 + $1.bytes.count }
        return ready
    }
}

private struct ChaosResult: Codable, Equatable {
    var schema = 1
    var evidence = "core_simulation"
    var seed: UInt64
    var profile: ChaosProfile
    var virtualMilliseconds = 0
    var packetDrops = 0
    var packetDelays = 0
    var packetDuplicates = 0
    var peakQueuedBytes = 0
    var completedFrames = 0
    var incompleteFrames = 0
    var controlOffers = 0
    var controlSends = 0
    var controlAcknowledgments = 0
    var controlTimeouts = 0
    var coalescedControls = 0
    var retiredDatagrams = 0
    var watchdogActions: [String: Int] = [:]
    var firstRecoveryFrameMs: Int?
    var failures: [String] = []
}

private struct ChaosExperiment {
    let seed: UInt64
    let profile: ChaosProfile
    var link: ChaosLink
    var random: ChaosRandom
    var assembler = HevcDepacketizer()
    var mailbox = CameraSetMailbox()
    var watchdog = FeedWatchdog()
    var handshake = DatalinkHandshakeAdmission()
    var epoch = 1
    var sequence: UInt16 = 65_440
    var expectedFrames: Set<[UInt8]> = []
    var lastPacket = 0
    var lastFrame = 0
    var lastProducedFrame = 0
    var lastStatus = 0
    var lastSet = 0
    var lastEnable: Int?
    var open: [UInt16: (sequence: UInt16, sent: Int)] = [:]
    var requested: [UInt16: Int] = [:]
    var applied: [UInt16: Int] = [:]
    var sentValues: [UInt16: Int] = [:]
    var result: ChaosResult
    let keys: [UInt16] = [0x0218, 0x028E, CameraSetMailbox.zoomOpcodeKey]

    init(seed: UInt64, profile: ChaosProfile) {
        self.seed = seed
        self.profile = profile
        random = ChaosRandom(state: seed)
        link = ChaosLink(random: ChaosRandom(state: seed ^ 0xA5A5))
        result = ChaosResult(seed: seed, profile: profile)
        handshake.reset(epoch: 1)
    }

    mutating func run(canary: Bool = false) -> ChaosResult {
        // Two healthy seconds, eight faulted seconds, then a clean drain/recovery.
        // A replacement endpoint at 7s retires commands while old replies remain queued.
        for now in stride(from: 0, through: 16_000, by: 10) {
            let active = (2_000..<10_000).contains(now) ? profile : .baseline
            if now == 7_000 { replaceEndpoint() }
            if now.isMultiple(of: 100) {
                var status = [UInt8](repeating: 0, count: 34)
                status[6] = DumlTransport.PktType.telemetry.rawValue
                link.send(status, epoch: epoch, at: now, profile: active)
            }
            if now.isMultiple(of: 40) {
                let frame = picture(index: now / 40)
                expectedFrames.insert(frame)
                if !(canary && now >= 10_000) {
                    for packet in fragments(frame, firstSequence: sequence) {
                        link.send(packet, epoch: epoch, at: now, profile: active)
                        sequence &+= 8
                    }
                }
            }
            // 100 synthetic settings/slider offers per second while video is impaired.
            // These use the actual mailbox; this is not a native UI test.
            if now < 14_000 {
                let key = keys[Int(random.next() % UInt64(keys.count))]
                requested[key] = now
                result.controlOffers += 1
                switch mailbox.offer(key: key, urgent: false, now: Double(now) / 1_000) {
                case .launch: launch(key, at: now, profile: active)
                case .coalescePending: result.coalescedControls += 1
                }
            }
            for key in keys {
                if let command = open[key], now - command.sent >= 300 {
                    result.controlTimeouts += 1
                    let decision = mailbox.timeout(key: key, subscribeMatches: false)
                    open[key] = nil
                    if decision == .launchPending { launch(key, at: now, profile: active) }
                }
                if !mailbox.hasOpen(key),
                    mailbox.pendingLaunch(key: key, now: Double(now) / 1_000) == .immediate
                {
                    launch(key, at: now, profile: active)
                }
            }
            for packet in link.receive(at: now) { receive(packet, at: now, profile: active) }
            if now.isMultiple(of: 50) { tickWatchdog(at: now) }
            if link.bytes < 0 || link.bytes > ChaosLink.byteLimit { fail("unbounded_packet_queue") }
        }
        if lastProducedFrame < 15_000 || result.firstRecoveryFrameMs == nil {
            fail("no_fresh_picture_after_faults")
        }
        if result.completedFrames == 0 { fail("no_complete_frames") }
        if profile == .baseline && assembler.droppedIncomplete > 0 { fail("healthy_frame_loss") }
        if requested != applied { fail("latest_settings_did_not_settle") }
        if profile == .blackout && result.watchdogActions["endpoint", default: 0] == 0 {
            fail("outage_did_not_exercise_endpoint_recovery")
        }
        result.virtualMilliseconds = 16_000
        result.packetDrops = link.dropped
        result.packetDelays = link.delayed
        result.packetDuplicates = link.duplicated
        result.peakQueuedBytes = link.peakBytes
        result.incompleteFrames = assembler.droppedIncomplete
        return result
    }

    mutating func launch(_ key: UInt16, at now: Int, profile: ChaosProfile) {
        if key != CameraSetMailbox.zoomOpcodeKey && mailbox.hasOpen(key)
            && !mailbox.isAwaitingLate(key)
        {
            fail("overlapping_control_generation")
        }
        mailbox.beginLaunch(key: key, now: Double(now) / 1_000)
        sequence &+= 8
        mailbox.noteTransmit(key: key, seq: sequence)
        open[key] = (sequence, now)
        sentValues[sequence] = requested[key]
        lastSet = now
        result.controlSends += 1
        // Reply travels through the same impaired queue as video. Real transport
        // framing is parsed on receipt; a synthetic peer always echoes the SET.
        let header = DumlTransport.transportHeader(
            pktType: DumlTransport.PktType.ackedData.rawValue,
            payloadLen: 0, sessionId: UInt16(epoch), seq: sequence)
        link.send(
            header, key: key, sequence: sequence, epoch: epoch, at: now + 20, profile: profile)
    }

    mutating func receive(_ packet: ChaosDatagram, at now: Int, profile: ChaosProfile) {
        guard packet.epoch == epoch else {
            result.retiredDatagrams += 1
            return
        }
        if packet.bytes[6] == DumlTransport.PktType.telemetry.rawValue {
            lastStatus = now
            return
        }
        if let key = packet.key {
            guard DumlTransport.transportSeq(packet.bytes) == packet.sequence else {
                fail("command_sequence_corruption")
                return
            }
            let matches = mailbox.isOpenSeq(key, seq: packet.sequence)
            let decision = mailbox.decideAck(key: key, seq: packet.sequence)
            if decision == .accept || decision == .acceptLate {
                if !matches { fail("accepted_superseded_ack") }
                applied[key] = sentValues[packet.sequence]
                open[key] = nil
                result.controlAcknowledgments += 1
                if mailbox.pendingLaunch(key: key, now: Double(now) / 1_000) == .immediate {
                    launch(key, at: now, profile: profile)
                }
            }
            return
        }
        lastPacket = now
        if let frame = assembler.feed(packet.bytes) {
            guard expectedFrames.contains(frame) else {
                fail("assembly_emitted_unknown_frame")
                return
            }
            result.completedFrames += 1
            lastFrame = now
            let producedAt = (Int(frame[4]) | (Int(frame[5]) << 8)) * 40
            lastProducedFrame = producedAt
            if producedAt >= 10_000 && result.firstRecoveryFrameMs == nil {
                result.firstRecoveryFrameMs = now - 10_000
            }
        }
    }

    mutating func tickWatchdog(at now: Int) {
        let packetAge = Double(now - lastPacket) / 1_000
        let frameAge = Double(now - lastFrame) / 1_000
        let snapshot = FeedWatchdog.Snapshot(
            now: Double(now) / 1_000,
            lastDecodedFrameAge: frameAge, lastVideoPacketAge: packetAge,
            lastAccessUnitAge: frameAge, lastStatusAge: Double(now - lastStatus) / 1_000,
            flowHealthy: true, pathReady: true, hasFormat: true, decoderFailed: false,
            live: true, sawPicture: result.completedFrames > 0,
            secondsSinceLastEnable: lastEnable.map { Double(now - $0) / 1_000 },
            secondsSinceCameraSet: Double(now - lastSet) / 1_000,
            lastDecoderOutputAge: frameAge, decoderOutputExpected: true)
        let action = watchdog.tick(snapshot)
        guard action != .none else { return }
        if frameAge < FeedWatchdog.stallThreshold { fail("repair_while_picture_fresh") }
        let name: String
        switch action {
        case .resendLiveViewEnable:
            if let lastEnable, now - lastEnable < 5_000 { fail("enable_storm") }
            lastEnable = now
            name = "enable"
        case .rebuildVTSession: name = "decoder"
        case .reopenDatalink: name = "endpoint"
        case .fullSessionRejoin: name = "session"
        case .none: return
        }
        result.watchdogActions[name, default: 0] += 1
        // Record policy decisions without inventing camera responses to a repair.
    }

    mutating func replaceEndpoint() {
        let old = epoch
        epoch += 1
        mailbox.reset()
        open.removeAll()
        handshake.reset(epoch: epoch)
        let ack = DumlTransport.handshakeDatagram(sessionId: 1, seq: 8, baseSeq: 64)
        handshake.receive(ack, epoch: old)
        if handshake.acknowledged { fail("retired_handshake_admitted") }
        handshake.receive(ack, epoch: epoch)
        if handshake.initialCommandSequence != nil { fail("handshake_without_command_window") }
        var window = [UInt8](repeating: 0, count: 34)
        window[6] = 1
        window[8] = 0xF8
        window[9] = 0xFF
        handshake.receive(window, epoch: epoch)
        if handshake.initialCommandSequence != 0 { fail("command_window_wraparound") }
    }

    mutating func fail(_ code: String) {
        if !result.failures.contains(code) { result.failures.append(code) }
    }

    func picture(index: Int) -> [UInt8] {
        [0, 0, 1, 0x65, UInt8(index & 255), UInt8(index >> 8)]
            + [UInt8](repeating: 0xAA, count: 900)
    }

    func fragments(_ frame: [UInt8], firstSequence: UInt16) -> [[UInt8]] {
        let length = frame.count
        let payload: [UInt8] =
            [
                0, 0, 1, 255, UInt8(length & 255), UInt8(length >> 8), 0, 0,
                0x90, 0x11, 0, 0, 0, 0, 0, 0,
            ] + frame
        let count = (payload.count + 255) / 256
        return (0..<count).map { index in
            var packet = [UInt8](repeating: 0, count: 20)
            let seq = firstSequence &+ UInt16(index * 8)
            packet[4] = UInt8(truncatingIfNeeded: seq)
            packet[5] = UInt8(seq >> 8)
            packet[6] = 2
            packet[16] = UInt8(truncatingIfNeeded: firstSequence / 8)
            packet[17] = UInt8(count) | UInt8((index % 2) << 7)
            packet[18] = UInt8(index / 2)
            return packet + payload[(index * 256)..<min(payload.count, (index + 1) * 256)]
        }
    }
}
