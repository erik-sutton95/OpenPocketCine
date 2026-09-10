import Foundation
import Network
import OpenPocketViewCore

/// One short-lived standard datalink session to an RTMP publisher's LAN address.
/// All socket writes and 40 Hz window acknowledgements are serialized off MainActor.
final class MultiviewWiFiControl {
    struct Result {
        let reply: [UInt8]?
        let recording: Bool?
    }
    enum Failure: LocalizedError {
        case unavailable, timeout
        var errorDescription: String? {
            switch self {
            case .unavailable: "Could not open camera control on the shared Wi-Fi."
            case .timeout:
                "The camera did not confirm recording. Check its screen before trying again."
            }
        }
    }
    private let queue = DispatchQueue(label: "multiview.camera-control", qos: .userInitiated)
    private let host: String
    private let token: String
    private var tcp: NWConnection?
    private var udp: NWConnection?
    private var tcpReady = false
    private var udpReady = false
    private var phase = 0
    private let session = UInt16.random(in: 0x1000...0xfffe)
    private let base = UInt16.random(in: 0x1000...0xf000) & 0xfff8
    private var transportSequence: UInt16 = 0
    private var commandSequence: UInt16 = 0xa000
    private var counter: UInt8 = 0
    private var windows = DumlTransport.AckWindows()
    private var hasVideoSequence = false
    private var timer: DispatchSourceTimer?
    private var deadline = Date.distantFuture
    private var lastHandshake = Date.distantPast
    private var requestedSequence: UInt16?
    private var requestedRecording = false
    private var receivedReply: [UInt8]?
    private var observedRecording: Bool?
    private var completion: CheckedContinuation<Result, Error>?

    init(host: String, token: String) {
        self.host = host
        self.token = token
    }

    func recording(_ enabled: Bool) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.completion = continuation
                self.requestedRecording = enabled
                self.deadline = Date().addingTimeInterval(15)
                self.open()
            }
        }
    }
    private func open() {
        let tcp = NWConnection(host: NWEndpoint.Host(host), port: 7001, using: .tcp)
        let udp = NWConnection(host: NWEndpoint.Host(host), port: 9004, using: .udp)
        self.tcp = tcp
        self.udp = udp
        tcp.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.tcpReady = true
                tcp.send(
                    content: Data(Duml.encode(Commands.setPairingPin(pin: self.token))),
                    completion: .idempotent)
                self.beginHandshake()
            case .failed: self.finish(.failure(Failure.unavailable))
            default: break
            }
        }
        udp.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.udpReady = true
                self.beginHandshake()
            case .failed: self.finish(.failure(Failure.unavailable))
            default: break
            }
        }
        tcp.start(queue: queue)
        udp.start(queue: queue)
        receiveTCP()
        receiveUDP()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(25), repeating: .milliseconds(25))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }
    private func beginHandshake() {
        guard phase == 0, tcpReady, udpReady else { return }
        phase = 1
        handshake()
    }
    private func handshake() {
        lastHandshake = Date()
        write(
            DumlTransport.handshakeDatagram(
                sessionId: session, seq: transportSequence, baseSeq: base))
        transportSequence &+= 8
    }
    private func receiveTCP() {
        tcp?.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] _, _, done, error in
            guard let self, self.completion != nil else { return }
            if done || error != nil {
                self.finish(.failure(Failure.unavailable))
            } else {
                self.receiveTCP()
            }
        }
    }
    private func receiveUDP() {
        udp?.receiveMessage { [weak self] data, _, _, error in
            guard let self, self.completion != nil else { return }
            if error != nil {
                self.finish(.failure(Failure.unavailable))
                return
            }
            if let data { self.ingest(Array(data)) }
            if self.completion != nil { self.receiveUDP() }
        }
    }
    private func write(_ bytes: [UInt8]) {
        udp?.send(
            content: Data(bytes),
            completion: .contentProcessed { [weak self] error in
                if error != nil { self?.finish(.failure(Failure.unavailable)) }
            })
    }
    @discardableResult private func send(_ frame: Duml.Frame) -> UInt16 {
        var frame = frame
        frame.seq = commandSequence
        commandSequence &+= 1
        counter &+= 1
        let routing = DumlTransport.routingHeader(seq: transportSequence, cmdCounter: counter)
        let payload = routing + Duml.encode(frame)
        write(
            DumlTransport.transportHeader(
                pktType: 5, payloadLen: payload.count, sessionId: session, seq: transportSequence)
                + payload)
        transportSequence &+= 8
        return frame.seq
    }
    private func ack() {
        let payload = DumlTransport.ackPayload(
            peerCursor: windows.video,
            ackedDataCursor: windows.hasAckedData ? windows.ackedData : base,
            extraCursor: windows.hasExtra ? windows.extra : base)
        write(
            DumlTransport.transportHeader(
                pktType: 4, payloadLen: payload.count, sessionId: session, seq: 0) + payload)
    }
    private func ingest(_ bytes: [UInt8]) {
        guard bytes.count >= 8 else { return }
        if DumlTransport.isHandshake(bytes), phase == 1 { phase = 2 }
        windows = windows.advancing(datagram: bytes)
        if bytes[6] == DumlTransport.PktType.video.rawValue,
            let sequence = DumlTransport.transportSeq(bytes)
        {
            windows.video = sequence
            hasVideoSequence = true
        }
        if let incoming = DumlTransport.ackWindows(fromTelemetry: bytes) {
            if !hasVideoSequence { windows.video = incoming.video }
            // The 15-byte handshake reply is not the command sequence window.
            // Wait for the first 34-byte telemetry packet before registration.
            if phase == 2, let sequence = MulticamCommands.controlSequence(fromInitialWindow: bytes)
            {
                transportSequence = sequence
                phase = 3
                ack()
                send(Commands.appDeviceInfo(seq: 0))
                ack()
                send(Commands.appPresenceFrame(seq: 0))
                ack()
                requestedSequence = send(
                    requestedRecording ? Commands.recordStart() : Commands.recordStop())
                deadline = Date().addingTimeInterval(12)
                ControlLiveLog.line(
                    "multiview: Wi-Fi record command sent start=\(requestedRecording)")
            }
        }
        for frame in DumlTransport.scanFrames(bytes) where requestedSequence != nil {
            if frame.seq == requestedSequence, frame.cmdSet == 2, frame.cmdId == 2,
                frame.flags & 128 != 0
            {
                receivedReply = frame.payload
                let code = frame.payload.prefix(4).map { String(format: "%02x", $0) }.joined(
                    separator: " ")
                ControlLiveLog.line("multiview: Wi-Fi recording reply=\(code)")
                if frame.payload != [0] {
                    finish(.success(Result(reply: frame.payload, recording: nil)))
                    return
                }
                deadline = Date().addingTimeInterval(3)
            }
            if frame.cmdSet == 2, frame.cmdId == 0x80, frame.payload.count >= 13 {
                var status = CameraStatus()
                CameraStatusDecoder.apply(frame, to: &status)
                observedRecording = status.isRecording
            }
        }
        if receivedReply == [0], observedRecording == requestedRecording {
            ack()
            ControlLiveLog.line(
                "multiview: Wi-Fi recording state confirmed start=\(requestedRecording)")
            finish(.success(Result(reply: receivedReply, recording: observedRecording)))
        }
    }
    private func tick() {
        guard completion != nil else { return }
        if Date() >= deadline {
            if receivedReply != nil || observedRecording == requestedRecording {
                finish(.success(Result(reply: receivedReply, recording: observedRecording)))
            } else {
                finish(.failure(Failure.timeout))
            }
            return
        }
        if phase == 1, Date().timeIntervalSince(lastHandshake) >= 1 { handshake() }
        if phase >= 2 { ack() }
    }
    private func finish(_ result: Swift.Result<Result, Error>) {
        guard let continuation = completion else { return }
        completion = nil
        timer?.cancel()
        timer = nil
        tcp?.stateUpdateHandler = nil
        udp?.stateUpdateHandler = nil
        tcp?.cancel()
        udp?.cancel()
        tcp = nil
        udp = nil
        continuation.resume(with: result)
    }
}
