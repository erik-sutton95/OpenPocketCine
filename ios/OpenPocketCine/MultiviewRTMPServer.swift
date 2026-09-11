import Foundation
import Network
import OpenPocketViewCore

/// Foreground-only local RTMP receiver. Parsing and NAL assembly stay off MainActor.
final class MultiviewRTMPServer {
    private let queue = DispatchQueue(label: "multiview.rtmp", qos: .userInitiated)
    private var listener: NWListener?
    private var clients: [UUID: Peer] = [:]
    private var keys: Set<String> = []
    var onVideo: ((String, [UInt8]) -> Bool)?
    var onState: ((String, String) -> Void)?
    var onPublisher: ((String, String) -> Void)?
    var onReady: ((Bool) -> Void)?

    func allow(_ key: String) { queue.async { self.keys.insert(key) } }
    func remove(_ key: String) {
        queue.async {
            self.keys.remove(key)
            for peer in Array(self.clients.values) where peer.key == key { peer.close() }
        }
    }
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let next = try NWListener(using: parameters, on: 1935)
        listener = next
        next.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.onReady?(true) }
            if case .failed = state { self?.onReady?(false) }
        }
        next.newConnectionHandler = { [weak self] connection in
            guard let self, self.clients.count < 4 else {
                connection.cancel()
                return
            }
            let id = UUID()
            let peer = Peer(connection: connection)
            self.clients[id] = peer
            peer.accept = { [weak self, weak peer] key in
                guard let self else { return false }
                return self.keys.contains(key)
                    && !self.clients.values.contains { $0 !== peer && $0.key == key }
            }
            peer.publisher = { [weak self] key, address in self?.onPublisher?(key, address) }
            peer.video = { [weak self] key, bytes in self?.onVideo?(key, bytes) ?? false }
            peer.state = { [weak self] key, status in self?.onState?(key, status) }
            peer.closed = { [weak self] in self?.clients.removeValue(forKey: id) }
            peer.start(queue: self.queue)
        }
        next.start(queue: queue)
    }
    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for peer in Array(self.clients.values) { peer.close() }
            self.clients.removeAll()
            self.keys.removeAll()
        }
    }

    private final class Peer {
        let connection: NWConnection
        var key: String?
        var accept: ((String) -> Bool)?
        var video: ((String, [UInt8]) -> Bool)?
        var state: ((String, String) -> Void)?
        var publisher: ((String, String) -> Void)?
        var closed: (() -> Void)?
        private var handshake: [UInt8] = []
        private var stage = 0
        private var parser = RTMPIngest.Parser()
        private var byteCount: UInt32 = 0
        private var acknowledged: UInt32 = 0
        private var parameterSets: [UInt8] = []
        private var nalLength = 4
        private var ended = false
        private var needsKeyframe = true
        private var startedAt = Date()
        private var lastReceived = Date()
        private var timer: DispatchSourceTimer?

        init(connection: NWConnection) { self.connection = connection }
        func start(queue: DispatchQueue) {
            connection.stateUpdateHandler = { [weak self] state in
                if case .failed = state { self?.close() }
            }
            connection.start(queue: queue)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                if (self.key == nil && Date().timeIntervalSince(self.startedAt) > 15)
                    || Date().timeIntervalSince(self.lastReceived) > 15
                {
                    self.close()
                }
            }
            self.timer = timer
            timer.resume()
            receive()
        }
        func close() {
            guard !ended else { return }
            ended = true
            timer?.cancel()
            timer = nil
            connection.cancel()
            if let key { state?(key, "Stream disconnected") }
            closed?()
        }
        private func send(_ bytes: [UInt8]) {
            connection.send(
                content: Data(bytes),
                completion: .contentProcessed { [weak self] error in
                    if error != nil { self?.close() }
                })
        }
        private func message(_ type: UInt8, _ payload: [UInt8], stream: UInt32 = 0) {
            send(RTMPIngest.encode(.init(type: type, stream: stream, payload: payload)))
        }
        private func command(_ values: [RTMPIngest.Value], stream: UInt32 = 0) {
            message(20, RTMPIngest.amf(values), stream: stream)
        }
        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                [weak self] data, _, done, error in
                guard let self, !self.ended else { return }
                if let data, !data.isEmpty {
                    self.lastReceived = Date()
                    do { try self.consume(Array(data)) } catch {
                        self.close()
                        return
                    }
                }
                if done || error != nil { self.close() } else { self.receive() }
            }
        }
        private func consume(_ bytes: [UInt8]) throws {
            byteCount &+= UInt32(bytes.count)
            var incoming = bytes
            if stage < 2 {
                handshake += incoming
                if stage == 0 {
                    guard handshake.count >= 1537 else { return }
                    guard handshake[0] == 3 else { throw RTMPIngest.Failure.malformed }
                    let clientHello = Array(handshake[1..<1537])
                    var serverHello = [UInt8](repeating: 0, count: 1536)
                    for i in 8..<1536 { serverHello[i] = UInt8.random(in: 0...255) }
                    send([3] + serverHello + clientHello)
                    handshake.removeFirst(1537)
                    stage = 1
                }
                guard handshake.count >= 1536 else { return }
                handshake.removeFirst(1536)
                incoming = handshake
                handshake.removeAll()
                stage = 2
            }
            for packet in try parser.append(incoming) { try handle(packet) }
            if byteCount &- acknowledged >= 1_000_000 {
                message(3, RTMPIngest.big32(byteCount))
                acknowledged = byteCount
            }
        }
        private func handle(_ packet: RTMPIngest.Message) throws {
            switch packet.type {
            case 4:
                if packet.payload.count >= 6, packet.payload[0] == 0, packet.payload[1] == 6 {
                    message(4, [0, 7] + packet.payload.dropFirst(2))
                }
            case 20, 17:
                let payload = packet.type == 17 ? Array(packet.payload.dropFirst()) : packet.payload
                let values = try RTMPIngest.values(payload)
                guard let name = values.first?.string else { return }
                let transaction = values.count > 1 ? values[1].number ?? 0 : 0
                switch name {
                case "connect":
                    message(5, RTMPIngest.big32(2_500_000))
                    message(6, RTMPIngest.big32(2_500_000) + [2])
                    command([
                        .string("_result"), .number(transaction),
                        .object(["fmsVer": .string("FMS/3,5,7,7009"), "capabilities": .number(31)]),
                        .object([
                            "level": .string("status"),
                            "code": .string("NetConnection.Connect.Success"),
                            "description": .string("Connected"), "objectEncoding": .number(0),
                        ]),
                    ])
                case "createStream":
                    command([.string("_result"), .number(transaction), .null, .number(1)])
                case "releaseStream", "FCPublish", "_checkbw":
                    command([.string("_result"), .number(transaction), .null, .null])
                case "publish":
                    guard key == nil, values.count > 3, let requested = values[3].string,
                        accept?(requested) == true
                    else {
                        close()
                        return
                    }
                    key = requested
                    if case .hostPort(let host, _) = connection.endpoint {
                        publisher?(requested, host.debugDescription)
                    }
                    message(4, [0, 0, 0, 0, 0, 1])
                    command(
                        [
                            .string("onStatus"), .number(0), .null,
                            .object([
                                "level": .string("status"),
                                "code": .string("NetStream.Publish.Start"),
                                "description": .string("Publishing"),
                            ]),
                        ], stream: 1)
                    state?(requested, "Waiting for video")
                case "deleteStream", "closeStream", "FCUnpublish": close()
                default: break
                }
            case 9: try videoPacket(packet.payload)
            default: break  // Audio intentionally muted in the first multiview prototype.
            }
        }
        private func videoPacket(_ bytes: [UInt8]) throws {
            guard let key, bytes.count >= 5 else { return }
            var kind = Int(bytes[1])
            var offset = 5
            let isHEVC: Bool
            if bytes[0] & 128 != 0 {
                guard Array(bytes[1..<5]) == Array("hvc1".utf8) else { return }
                isHEVC = true
                kind = Int(bytes[0] & 15)
                offset = kind == 1 ? 8 : 5
                if kind == 3 { kind = 1 }
            } else {
                isHEVC = bytes[0] & 15 == 12
                guard isHEVC || bytes[0] & 15 == 7 else { return }
            }
            guard bytes.count >= offset else { throw RTMPIngest.Failure.malformed }
            let body = Array(bytes.dropFirst(offset))
            if kind == 0 {
                parameterSets.removeAll()
                if isHEVC {
                    guard body.count >= 23 else { throw RTMPIngest.Failure.malformed }
                    nalLength = Int(body[21] & 3) + 1
                    var i = 23
                    for _ in 0..<Int(body[22]) {
                        guard i + 3 <= body.count else { throw RTMPIngest.Failure.malformed }
                        let count = Int(body[i + 1]) * 256 + Int(body[i + 2])
                        i += 3
                        for _ in 0..<count { try appendParameter(body, &i) }
                    }
                } else {
                    guard body.count >= 7 else { throw RTMPIngest.Failure.malformed }
                    nalLength = Int(body[4] & 3) + 1
                    var i = 6
                    for _ in 0..<Int(body[5] & 31) { try appendParameter(body, &i) }
                    guard i < body.count else { throw RTMPIngest.Failure.malformed }
                    let count = Int(body[i])
                    i += 1
                    for _ in 0..<count { try appendParameter(body, &i) }
                }
            } else if kind == 1 {
                var accessUnit: [UInt8] = []
                var i = 0
                let keyframe = (bytes[0] & 0x70) == 0x10
                if needsKeyframe && !keyframe { return }
                if keyframe {
                    accessUnit = parameterSets
                    needsKeyframe = false
                }
                while i < body.count {
                    guard i + nalLength <= body.count else { throw RTMPIngest.Failure.malformed }
                    let count = body[i..<i + nalLength].reduce(0) { $0 * 256 + Int($1) }
                    i += nalLength
                    guard count > 0, i + count <= body.count else {
                        throw RTMPIngest.Failure.malformed
                    }
                    accessUnit += [0, 0, 0, 1] + body[i..<i + count]
                    i += count
                }
                if !accessUnit.isEmpty, video?(key, accessUnit) != true { needsKeyframe = true }
            }
        }
        private func appendParameter(_ body: [UInt8], _ index: inout Int) throws {
            guard index + 2 <= body.count else { throw RTMPIngest.Failure.malformed }
            let count = Int(body[index]) * 256 + Int(body[index + 1])
            index += 2
            guard count > 0, index + count <= body.count else { throw RTMPIngest.Failure.malformed }
            parameterSets += [0, 0, 0, 1] + body[index..<index + count]
            index += count
        }
    }
}
