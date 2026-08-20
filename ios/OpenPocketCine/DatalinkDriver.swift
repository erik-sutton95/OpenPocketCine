import Foundation
import Network
import OpenPocketViewCore
import os

/// The DUML-over-UDP datalink on iOS: opens the socket to 192.168.2.1, runs the handshake, registers
/// the app, subscribes to status, and pumps keepalives — using the byte builders from the (tested)
/// core. This is the stateful half the core deliberately leaves out (session id, the sequence
/// counters, the peer-cursor echo).
///
/// Video (pktType 0x02) is best-effort UDP. Mimo keeps the camera's send window open by echoing the
/// latest video transport-seq in a pktType-0x04 ACK ~40 times a second. We do the same. Receive is
/// re-armed on the UDP queue (never the main actor) so a busy UI cannot stall the socket.
@MainActor
final class DatalinkDriver {
    private let port: UInt16
    private let tcpPoke: Bool
    private let pairingToken: String
    private let q = DispatchQueue(label: "opv.datalink.udp")
    private var conn: NWConnection?
    private var pokeConn: NWConnection?          // kept open for the session; Mimo does not RST 7001
    private var ackTimer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private var writeHealthy = true
    private var lastCommandWriteLanded: Bool?
    private var rebuilding = false
    private var lastRebuildAt: Date?
    /// Bumped before the old UDP is canceled so its 89 / write failures
    /// cannot mark the replacement socket dead.
    private var udpGeneration = 0
    private var cameraInterface: NWInterface?
    private var cameraLocalIPv4: String?

    // Sequencing state (mirrors Osmosis DumlTransport). Touched on `q` after open().
    private var sessionId: UInt16 = 0
    private var baseSeq: UInt16 = 0
    private var udpSeq: UInt16 = 0
    private var dumlSeq: UInt16 = 0xA000
    private var cmdCounter: UInt8 = 0
    private var peerCursor: UInt16 = 0
    private var camChannel: UInt16 = 0
    /// Set on the UDP queue the instant pktType 0x00 lands. MainActor ingest
    /// used to see the ACK after SwiftUI had already burned the wait loop.
    nonisolated private let handshakeFlag = OSAllocatedUnfairLock(initialState: false)
    /// Inbound datagrams seen before the ACK. Zero on a miss means the reader
    /// is dead or the camera never heard us.
    nonisolated private let handshakeInbound = OSAllocatedUnfairLock(initialState: 0)
    /// `receiveMessage` has been armed on the current `conn`.
    private var receiveArmed = false
    /// Camera still pushes the last GOP after Disconnect. Do not count or
    /// decode those 0x02 packets until `0x09/0xa8` has gone out.
    nonisolated private let videoGate = OSAllocatedUnfairLock(initialState: VideoGate())

    private struct VideoGate {
        var accepting = false
        var loggedDrop = false
    }

    /// Depacketize + video counters on the UDP queue. Main only hops complete AUs.
    nonisolated private let videoAssembler = SoftAPVideoAssembler()
    /// Session/socket snapshot for the 40 Hz ACK pump (UDP queue, not MainActor).
    nonisolated private let wire = OSAllocatedUnfairLock(initialState: WireState())
    private var lastStatusDate: Date?
    private var receiveErrors = 0
    private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "datalink")

    private struct WireState {
        var sessionId: UInt16 = 0
        var baseSeq: UInt16 = 0
        var conn: NWConnection?
    }

    /// Called (on the main actor) for every DUML frame the camera pushes.
    /// Status, control ACKs, and media-list chunks (`0x00/0x27`) all arrive here.
    var onStatusFrame: ((Duml.Frame) -> Void)?
    /// Called (on the main actor) with each complete HEVC access unit (DJI marker already stripped).
    var onAccessUnit: (([UInt8]) -> Void)?

    /// Snapshot of video-pipeline counters. Safe to read from the main actor for the HUD.
    var videoPackets: Int { videoAssembler.snapshot().packets }
    var droppedIncomplete: Int { videoAssembler.snapshot().dropped }
    var receiveErrorCount: Int { receiveErrors }
    var lastVideoPacketAt: Date? { videoAssembler.snapshot().lastPacket }
    var lastAccessUnitAt: Date? { videoAssembler.snapshot().lastAU }
    var lastStatusAt: Date? { lastStatusDate }
    var isTcpPokeReady: Bool {
        guard let pokeConn else { return false }
        if case .ready = pokeConn.state { return true }
        return false
    }
    /// Last command `send` completion. `nil` until Network.framework reports.
    var lastWriteLanded: Bool? { lastCommandWriteLanded }
    var isFlowHealthy: Bool { writeHealthy && isConnectionReady }
    var isRebuilding: Bool { rebuilding }
    var secondsSinceLastRebuild: TimeInterval? {
        lastRebuildAt.map { Date().timeIntervalSince($0) }
    }
    var needsRebuild: Bool {
        if rebuilding { return false }
        return CameraSoftAP.shouldRebuildFlow(flowHealth)
    }

    private var isConnectionReady: Bool {
        guard let conn else { return false }
        if case .ready = conn.state { return true }
        return false
    }

    private var flowHealth: CameraSoftAP.DatalinkFlowHealth {
        if !WiFiJoiner.isCameraPathReady() { return .pathLost }
        guard let conn else { return .notReady }
        switch conn.state {
        case .ready: return writeHealthy ? .ready : .writeRejected
        case .cancelled: return .cancelled
        case .failed, .waiting: return .notReady
        default: return .notReady
        }
    }

    init(port: UInt16, tcpPoke: Bool, pairingToken: String) {
        self.port = port; self.tcpPoke = tcpPoke; self.pairingToken = pairingToken
    }

    private var handshakeAcked: Bool {
        get { handshakeFlag.withLock { $0 } }
        set { handshakeFlag.withLock { $0 = newValue } }
    }

    /// Bring the datalink up: poke, handshake, register, subscribe. Throws if the socket never opens
    /// or the handshake is never answered (which is how "wrong UDP port for this model" surfaces).
    ///
    /// `afterHandshake` runs after register + subscribe — send `0x09/0xa8`
    /// there. Enable before subscribe is ignored on first boot.
    func open(afterHandshake: (@MainActor () async -> Void)? = nil) async throws {
        // Sockets created before 192.168.2.x exist bind to the old Wi-Fi, then
        // RST when the camera AP finishes associating (first-connect black feed).
        try await WiFiJoiner.waitUntilCameraPathReady()
        try await refreshCameraPath()
        try await ensurePoke()

        var rebinds = 0
        var haveSocket = false
        while true {
            try Task.checkCancellation()
            resetHandshakeSession()
            // Do not discard before the first bind — that was a no-op on a
            // fresh driver but raced the reader on session retry.
            if haveSocket { discardUDP() }
            try await openUDP()
            haveSocket = true
            syncWire()
            startPathWatch()

            let sends = CameraSoftAP.handshakeSendsPerBind
            for send in 1...sends {
                try Task.checkCancellation()
                if handshakeAcked { break }
                if !CameraSoftAP.canSendHandshake(
                    receiveArmed: receiveArmed, connectionReady: isConnectionReady
                ) {
                    log.info("datalink: handshake UDP not ready reader=\(self.receiveArmed) — will rebind")
                    break
                }
                let pkt = DumlTransport.handshakeDatagram(
                    sessionId: sessionId, seq: udpSeq, baseSeq: baseSeq)
                write(pkt)
                udpSeq = udpSeq &+ 8
                log.info("datalink: handshake send \(send)/\(sends)")
                try await waitForHandshakeAck()
                if handshakeAcked { break }
            }
            if handshakeAcked {
                log.info("datalink: handshake acked session=\(self.sessionId, privacy: .public)")
                // Protocol: register + subscribe, then 0x09/0xa8. Enable before
                // subscribe is ignored; first-boot then piled mid-GOP P-frames
                // and first-picture tore UDP during the IDR gap.
                if camChannel != 0 { udpSeq = camChannel &+ 8 }
                sendAck()
                register()
                subscribe()
                startAckPump()
                if let afterHandshake { await afterHandshake() }
                // Enable first, then accept 0x02. Arming earlier ingested the
                // leftover GOP (videoPkts=125, first picture never recovered).
                armLiveVideo()
                return
            }

            let inbound = handshakeInbound.withLock { $0 }
            let pathReady = WiFiJoiner.isCameraPathReady()
            switch CameraSoftAP.handshakeTimeoutStep(pathReady: pathReady, rebindsUsed: rebinds) {
            case .rebindUDP:
                rebinds += 1
                log.info("datalink: handshake miss inbound=\(inbound, privacy: .public) — SoftAP up, rebind UDP (\(rebinds)/\(CameraSoftAP.handshakeRebindLimit))")
            case .fail:
                log.info("datalink: handshake never acked inbound=\(inbound, privacy: .public)")
                throw DatalinkError.noHandshake
            }
        }
    }

    /// pktType 0x00 can land in tens of ms; 350 ms is only the cap per send.
    private func waitForHandshakeAck() async throws {
        let poll = CameraSoftAP.handshakePollMilliseconds
        let cap = CameraSoftAP.handshakeSendIntervalMilliseconds
        var waited = 0
        while waited < cap {
            if handshakeAcked { return }
            try Task.checkCancellation()
            let slice = min(poll, cap - waited)
            try await Task.sleep(for: .milliseconds(slice))
            waited += slice
        }
    }

    private func resetHandshakeSession() {
        sessionId = UInt16.random(in: 0x1000...0xFFFE)
        baseSeq = UInt16.random(in: 0x1000...0xF000) & 0xFFF8   // 8-aligned; fresh per connect
        camChannel = baseSeq
        udpSeq = 0
        handshakeAcked = false
        handshakeInbound.withLock { $0 = 0 }
        videoGate.withLock { $0 = VideoGate() }
        videoAssembler.reset()
        lastStatusDate = nil
        receiveErrors = 0
        writeHealthy = true
        lastCommandWriteLanded = nil
    }

    /// Keep an already-ready 7001 poke. A second connect after a miss used to
    /// open another TCP and RST the one the camera still had.
    private func ensurePoke() async throws {
        guard tcpPoke else {
            log.info("datalink: TCP 7001 poke skipped (model)")
            return
        }
        if isTcpPokeReady {
            log.info("datalink: TCP 7001 poke already ready")
            return
        }
        pokeConn?.cancel()
        pokeConn = nil
        do {
            try await poke7001()
            log.info("datalink: TCP 7001 poke ready")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log.info("datalink: TCP 7001 poke failed (\(error.localizedDescription, privacy: .public)) — trying UDP")
        }
    }

    /// Re-assert app-presence + ack; call ~1 Hz to hold the session (and playback) open.
    func keepalive() {
        sendDuml(Commands.appPresenceFrame(seq: 0))
        sendAck()
    }

    func enterPlayback() { sendDuml(Commands.enterPlayback(seq: 0)) }
    func exitPlayback() { sendDuml(Commands.exitPlayback(seq: 0)) }

    /// Send the live-view enable (`0x09/0xa8`) on **UDP 9004** only.
    /// Never writes TCP 7001 — a second enable on a dying UDP flow RST'd the poke.
    func startLiveView(receiver: UInt8 = Commands.liveViewEnableReceiverPocket) {
        let seq = sendDuml(Commands.liveViewEnable(seq: 0, receiver: receiver), trackCommand: true)
        log.info("datalink: sent 0x09/0xa8 rcv=0x\(String(receiver, radix: 16), privacy: .public) seq=\(seq, privacy: .public) ready=\(self.isConnectionReady ? 1 : 0) videoPkts=\(self.videoPackets, privacy: .public)")
    }

    /// Drop leftover GOP counters and accept 0x02. Call after `0x09/0xa8`.
    func armLiveVideo() {
        videoAssembler.reset()
        videoGate.withLock {
            $0.accepting = true
            $0.loggedDrop = false
        }
    }

    /// App → camera DUML on the live datalink (`0x02/*` record, mode, param SET).
    /// Returns the `dumlSeq` stamped on the wire (the builder's `seq` is a placeholder).
    @discardableResult
    func send(_ frame: Duml.Frame) -> UInt16 {
        lastCommandWriteLanded = nil
        return sendDuml(frame, trackCommand: true)
    }

    func close() {
        ackTimer?.cancel(); ackTimer = nil
        pathMonitor?.cancel(); pathMonitor = nil
        conn?.cancel(); conn = nil
        pokeConn?.cancel(); pokeConn = nil
        videoAssembler.reset()
        writeHealthy = false
        syncWire()
    }

    /// Tear down a dead `en0` channel-flow and open a new UDP socket on the
    /// interface that owns `192.168.2.x`. Keeps session/seq so the camera
    /// still recognizes us; live-view enable is the caller's job if video dies.
    /// Does not touch TCP 7001 — canceling the poke is the `tcp_output RST`.
    func rebuildUDP(reason: String) async throws {
        if rebuilding { return }
        rebuilding = true
        lastRebuildAt = Date()
        defer { rebuilding = false }
        log.info("datalink: rebuilding UDP (\(reason, privacy: .public))")
        ControlLiveLog.line("datalink: rebuilding UDP (\(reason))")
        discardUDP()
        writeHealthy = true
        lastCommandWriteLanded = nil
        videoAssembler.noteRebuild()
        try await WiFiJoiner.waitUntilCameraPathReady(timeout: 5)
        try await refreshCameraPath()
        try await openUDP()
        writeHealthy = true
        syncWire()
        sendAck()
        sendDuml(Commands.appPresenceFrame(seq: 0))
    }

    /// Drop the live UDP socket only. TCP 7001 stays up for the session.
    private func discardUDP() {
        udpGeneration += 1
        receiveArmed = false
        let old = conn
        conn = nil
        syncWire()
        old?.stateUpdateHandler = nil
        old?.cancel()
    }

    // ---- registration ----------------------------------------------------------------------------

    private func register() {
        sendDuml(Commands.appDeviceInfo(seq: 0)); sendAck()
        sendDuml(Commands.appPresenceFrame(seq: 0)); sendAck()
        sendDuml(Commands.gimbalInit(seq: 0)); sendAck()
    }

    private func subscribe() {
        var subId = Commands.firstSubId
        for key in Commands.subscriptionKeys {
            sendDuml(Commands.subscribe(key: key, subId: subId, seq: 0))
            subId += 1
        }
        sendAck()
    }

    // ---- send ------------------------------------------------------------------------------------

    private func sendRaw(pktType: UInt8, payload: [UInt8]) {
        let pkt = DumlTransport.transportHeader(pktType: pktType, payloadLen: payload.count,
                                                sessionId: sessionId, seq: udpSeq) + payload
        write(pkt)
        udpSeq = udpSeq &+ 8
    }

    /// Wrap a DUML frame in the transport + routing headers and send it (pktType 0x05).
    @discardableResult
    private func sendDuml(_ frame: Duml.Frame, trackCommand: Bool = false) -> UInt16 {
        cmdCounter = cmdCounter &+ 1
        var f = frame
        f.seq = dumlSeq
        dumlSeq = dumlSeq &+ 1
        let routing = DumlTransport.routingHeader(seq: udpSeq, cmdCounter: cmdCounter)
        let duml = Duml.encode(f)
        let pkt = DumlTransport.transportHeader(pktType: 0x05, payloadLen: routing.count + duml.count,
                                                sessionId: sessionId, seq: udpSeq) + routing + duml
        write(pkt, trackCommand: trackCommand)
        udpSeq = udpSeq &+ 8
        return f.seq
    }

    /// pktType-0x04 window ACK, sent with seq 0 (echoes the peer's cursor so it opens its downlink).
    private func sendAck() {
        peerCursor = videoAssembler.peerCursor(fallback: peerCursor)
        let payload = DumlTransport.ackPayload(peerCursor: peerCursor, baseSeq: baseSeq)
        let pkt = DumlTransport.transportHeader(pktType: 0x04, payloadLen: payload.count,
                                                sessionId: sessionId, seq: 0) + payload
        write(pkt)
    }

    private func write(_ bytes: [UInt8], trackCommand: Bool = false) {
        guard let conn else {
            writeHealthy = false
            if trackCommand { lastCommandWriteLanded = false }
            return
        }
        switch conn.state {
        case .ready:
            break
        default:
            // Not-ready is not a dead flow. Latch writeHealthy here and the
            // 1 Hz keepalive tears UDP during LUT / zoom — receive may still
            // be fine. State watch owns failed / waiting / cancelled.
            if trackCommand { lastCommandWriteLanded = false }
            if trackCommand {
                log.info("datalink: skip write — UDP not ready (\(String(describing: conn.state), privacy: .public))")
            }
            return
        }
        let generation = udpGeneration
        let socket = conn
        conn.send(content: Data(bytes), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    guard CameraSoftAP.shouldApplyStaleSocketHealth(
                        isLiveConnection: self.udpGeneration == generation && self.conn === socket
                    ) else { return }
                    let wasHealthy = self.writeHealthy
                    self.writeHealthy = false
                    if trackCommand { self.lastCommandWriteLanded = false }
                    if wasHealthy || trackCommand {
                        self.log.info("datalink: write rejected (\(error.localizedDescription, privacy: .public))")
                    }
                }
            } else if trackCommand {
                Task { @MainActor in
                    guard self.udpGeneration == generation else { return }
                    self.lastCommandWriteLanded = true
                }
            }
        })
    }

    /// Mimo ACKs ~41 Hz (p50 24.4 ms) with cursor = latest video transport seq. 1 Hz is not enough
    /// to keep the camera's send window open once live view is flowing.
    /// Runs on the UDP queue — a MainActor Task per tick starved control ACKs.
    private func startAckPump() {
        ackTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + .milliseconds(25), repeating: .milliseconds(25))
        t.setEventHandler { [weak self] in
            self?.sendWindowAck()
        }
        t.resume()
        ackTimer = t
    }

    /// Window ACK from the UDP queue. Does not hop to MainActor.
    nonisolated private func sendWindowAck() {
        let cursor = videoAssembler.peerCursor(fallback: 0)
        let (session, base, conn) = wire.withLock { ($0.sessionId, $0.baseSeq, $0.conn) }
        guard let conn else { return }
        switch conn.state {
        case .cancelled, .failed: return
        default: break
        }
        let payload = DumlTransport.ackPayload(peerCursor: cursor, baseSeq: base)
        let pkt = DumlTransport.transportHeader(
            pktType: 0x04, payloadLen: payload.count, sessionId: session, seq: 0
        ) + payload
        conn.send(content: Data(pkt), completion: .idempotent)
    }

    private func syncWire() {
        let sid = sessionId
        let base = baseSeq
        let socket = conn
        wire.withLock {
            $0.sessionId = sid
            $0.baseSeq = base
            $0.conn = socket
        }
    }

    // ---- receive ---------------------------------------------------------------------------------

    private func startReceiveLoop() {
        guard let conn else { return }
        // Capture the connection and re-arm from a nonisolated static so the next receiveMessage
        // is scheduled on `q` immediately. `startReceiveLoop()` is MainActor-isolated — calling
        // it from the UDP callback hopped to main and froze the feed when the UI was busy.
        let assembler = videoAssembler
        let handshake = handshakeFlag
        let inbound = handshakeInbound
        let gate = videoGate
        let generation = udpGeneration
        let socket = conn
        receiveArmed = true
        log.info("datalink: UDP reader armed")
        Self.armReceive(conn, queue: q, onError: { [weak self] message in
            let canceled = CameraSoftAP.isCanceledReceive(message)
            let awaitingAck = !handshake.withLock { $0 }
            Task { @MainActor in
                guard let self else { return }
                let live = self.udpGeneration == generation && self.conn === socket
                if awaitingAck {
                    self.log.info("datalink: handshake UDP recv error canceled=\(canceled) live=\(live) (\(message, privacy: .public))")
                }
                guard CameraSoftAP.shouldCountReceiveError(isLiveConnection: live, canceled: canceled)
                else { return }
                self.receiveErrors += 1
                self.log.info("datalink: UDP receive error #\(self.receiveErrors, privacy: .public) (\(message, privacy: .public)) — re-arm")
            }
        }) { [weak self] bytes in
            let awaitingAck = !handshake.withLock { $0 }
            if awaitingAck {
                inbound.withLock { $0 += 1 }
                let count = bytes.count
                let pktType = count > 6 ? bytes[6] : 0xFF
                Task { @MainActor in
                    self?.log.info("datalink: handshake inbound bytes=\(count, privacy: .public) pktType=0x\(String(format: "%02x", pktType), privacy: .public)")
                }
            }
            if DumlTransport.isHandshake(bytes) {
                handshake.withLock { $0 = true }
                Task { @MainActor in
                    self?.log.info("datalink: handshake reply pktType=0x00")
                }
            }
            let video = bytes.count > 6 && bytes[6] == 0x02
            if video {
                let accept = gate.withLock { $0.accepting }
                if !CameraSoftAP.shouldIngestLiveVideo(liveViewEnabled: accept) {
                    let logDrop = gate.withLock { state -> Bool in
                        if state.loggedDrop { return false }
                        state.loggedDrop = true
                        return true
                    }
                    if logDrop {
                        let count = bytes.count
                        Task { @MainActor in
                            self?.log.info("datalink: drop leftover video before enable bytes=\(count, privacy: .public)")
                        }
                    }
                    return
                }
                let assembled = assembler.ingest(bytes)
                if assembled.firstPacket {
                    let count = bytes.count
                    Task { @MainActor in
                        self?.log.info("datalink: first video pktType=0x02 bytes=\(count, privacy: .public)")
                    }
                }
                if assembled.shouldHop {
                    Task(priority: .utility) { @MainActor in
                        self?.flushPendingAccessUnits()
                    }
                }
                return
            }
            Task(priority: .high) { @MainActor in
                self?.ingest(bytes)
            }
        }
    }

    /// First-connect path updates used to stop `receiveMessage` on the first
    /// error — inbound video and command ACKs died while BLE stayed up.
    nonisolated private static func armReceive(
        _ conn: NWConnection,
        queue: DispatchQueue,
        onError: @escaping @Sendable (String) -> Void,
        ingest: @escaping @Sendable ([UInt8]) -> Void
    ) {
        conn.receiveMessage { data, _, _, error in
            // Re-arm BEFORE ingest. Ingest-first froze videoPkts at the first
            // burst (272, rxErr=0) so the enable-triggered IDR never arrived.
            if let error {
                let canceled = CameraSoftAP.isCanceledReceive(error.localizedDescription)
                onError(error.localizedDescription)
                let live = Self.shouldRearmReceive(conn)
                if CameraSoftAP.shouldRearmAfterError(isLiveConnection: live, canceled: canceled) {
                    queue.asyncAfter(deadline: .now() + .milliseconds(40)) {
                        guard Self.shouldRearmReceive(conn) else { return }
                        armReceive(conn, queue: queue, onError: onError, ingest: ingest)
                    }
                }
            } else {
                armReceive(conn, queue: queue, onError: onError, ingest: ingest)
            }
            if let data, !data.isEmpty { ingest([UInt8](data)) }
        }
    }

    nonisolated private static func shouldRearmReceive(_ conn: NWConnection) -> Bool {
        switch conn.state {
        case .cancelled, .failed: false
        default: true
        }
    }

    private func ingest(_ datagram: [UInt8]) {
        // Learn the peer's sequence channel (bytes 8-9) and the window cursor.
        if datagram.count >= 10 {
            let ch = UInt16(datagram[8]) | (UInt16(datagram[9]) << 8)
            if ch != 0 { camChannel = ch }
        }
        if DumlTransport.isHandshake(datagram) { handshakeAcked = true }

        // 0x01 telemetry carries a cursor at [10:12]. Video (0x02) has no such field — Mimo echoes
        // the video packet's own transport seq (bytes 4-5) instead, 96% of ACKs in the capture.
        if datagram.count == 34, datagram[6] == 0x01 {
            peerCursor = UInt16(datagram[10]) | (UInt16(datagram[11]) << 8)
            videoAssembler.notePeerCursor(peerCursor)
        }

        // Video is assembled on the UDP queue. A stray main-actor copy must not
        // double-count packets or hop the datagram again.
        if datagram.count > 20, datagram[6] == 0x02 {
            return
        }
        // Forward every DUML frame; the session applies CameraStatusDecoder to the ones it recognises.
        let frames = DumlTransport.scanFrames(datagram)
        if !frames.isEmpty {
            lastStatusDate = Date()
            noteInboundTraffic()
        }
        for frame in frames { onStatusFrame?(frame) }
    }

    /// Receive is the live-socket signal. One command write reject must not
    /// keep the flow marked dead until the next keepalive rebuild.
    private func noteInboundTraffic() {
        guard !writeHealthy else { return }
        writeHealthy = true
        log.info("datalink: inbound restored write health")
    }

    /// Drain AUs assembled on the UDP queue. One hop per batch so a Task-per-AU
    /// cannot stall receive or preempt control ACKs.
    private func flushPendingAccessUnits() {
        noteInboundTraffic()
        let batch = videoAssembler.takePending()
        for accessUnit in batch {
            onAccessUnit?(accessUnit)
        }
        if videoAssembler.hasPending {
            Task(priority: .utility) { @MainActor [weak self] in
                self?.flushPendingAccessUnits()
            }
        }
    }

    // ---- socket helpers --------------------------------------------------------------------------

    private func openUDP() async throws {
        let savedIP = cameraLocalIPv4
        let savedIF = cameraInterface
        var last: Error = DatalinkError.notReady
        let modes: [(String, String?, NWInterface?)] = [
            ("bound", savedIP, savedIF),
            ("interface", nil, savedIF),
            ("wifi-type", nil, nil),
        ]
        for (label, ip, iface) in modes {
            cameraLocalIPv4 = ip
            cameraInterface = iface
            do {
                try await openUDPOnce(label: label)
                cameraLocalIPv4 = savedIP
                cameraInterface = savedIF
                return
            } catch is CancellationError {
                cameraLocalIPv4 = savedIP
                cameraInterface = savedIF
                throw CancellationError()
            } catch {
                last = error
                discardUDP()
                log.info("datalink: UDP \(label, privacy: .public) failed (\(error.localizedDescription, privacy: .public))")
            }
        }
        cameraLocalIPv4 = savedIP
        cameraInterface = savedIF
        throw last
    }

    private func openUDPOnce(label: String) async throws {
        let params = wifiUDP()
        let host = CameraSoftAP.host
        conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        log.info("datalink: UDP \(label, privacy: .public) \(host, privacy: .public):\(self.port) if=\(self.cameraInterface?.name ?? "-", privacy: .public) local=\(self.cameraLocalIPv4 ?? "-", privacy: .public)")
        try await start(conn!)
        startReceiveLoop()
        if let conn { installStateWatch(conn) }
    }

    private func refreshCameraPath() async throws {
        cameraLocalIPv4 = WiFiJoiner.cameraLocalIPv4()
        cameraInterface = await WiFiJoiner.resolveCameraInterface()
#if !targetEnvironment(simulator)
        if cameraLocalIPv4 == nil {
            throw DatalinkError.notReady
        }
#endif
        log.info("datalink: camera path if=\(self.cameraInterface?.name ?? "unlisted", privacy: .public) local=\(self.cameraLocalIPv4 ?? "-", privacy: .public)")
    }

    private func wifiUDP() -> NWParameters {
        cameraParameters(NWParameters.udp)
    }

    private func wifiTCP() -> NWParameters {
        cameraParameters(NWParameters.tcp)
    }

    /// Bind to the SoftAP IPv4 / interface. `requiredInterfaceType = .wifi` alone
    /// scopes the flow to `en0` (home Wi-Fi) and later writes fail.
    private func cameraParameters(_ p: NWParameters) -> NWParameters {
        p.prohibitedInterfaceTypes = [.cellular]
        p.allowLocalEndpointReuse = true
        var boundLocal = false
#if !targetEnvironment(simulator)
        if let cameraLocalIPv4, let localPort = NWEndpoint.Port(rawValue: 0) {
            p.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(cameraLocalIPv4), port: localPort)
            boundLocal = true
        }
#endif
        if let cameraInterface {
            p.requiredInterface = cameraInterface
        } else if !boundLocal {
            p.requiredInterfaceType = .wifi
        }
        return p
    }

    private func startPathWatch() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !WiFiJoiner.isCameraPathReady() {
                    self.writeHealthy = false
                    self.log.info("datalink: camera 192.168.2.x left the path")
                }
            }
        }
        monitor.start(queue: q)
        pathMonitor = monitor
    }

    private func installStateWatch(_ c: NWConnection) {
        let generation = udpGeneration
        c.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                guard CameraSoftAP.shouldApplyStaleSocketHealth(
                    isLiveConnection: self.udpGeneration == generation && self.conn === c
                ) else { return }
                switch state {
                case .failed(let error):
                    self.writeHealthy = false
                    self.log.info("datalink: UDP failed (\(error.localizedDescription, privacy: .public))")
                case .waiting(let error):
                    self.writeHealthy = false
                    self.log.info("datalink: UDP waiting (\(error.localizedDescription, privacy: .public))")
                case .cancelled:
                    self.writeHealthy = false
                default:
                    break
                }
            }
        }
    }

    private func start(_ c: NWConnection, timeout: TimeInterval = 5) async throws {
        do {
            try await startUntilReady(c, timeout: timeout)
        } catch {
            c.cancel()
            throw error
        }
    }

    private func startUntilReady(_ c: NWConnection, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            let finish: (Result<Void, Error>) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                switch result {
                case .success: cont.resume()
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            c.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .failed(let e): finish(.failure(e))
                case .cancelled: finish(.failure(CancellationError()))
                default: break
                }
            }
            c.start(queue: q)
            q.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(DatalinkError.notReady))
            }
        }
    }

    /// TCP-7001 "poke": write a SetPairingPIN frame to arm the UDP datalink. Mimo keeps this socket
    /// open for the session (camera pushes 0x21/0x06); closing it is what produced the tcp_output RST.
    /// Retry while the camera AP is still coming up — first connect used to ready-then-RST.
    private func poke7001() async throws {
        var last: Error = DatalinkError.notReady
        for attempt in 1...4 {
            try Task.checkCancellation()
            do {
                try await poke7001Once()
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                last = error
                log.info("datalink: TCP 7001 attempt \(attempt) failed (\(error.localizedDescription, privacy: .public))")
                pokeConn?.cancel()
                pokeConn = nil
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
        throw last
    }

    private func poke7001Once() async throws {
        let tcp = NWConnection(host: NWEndpoint.Host(CameraSoftAP.host), port: 7001, using: wifiTCP())
        pokeConn = tcp
        try await start(tcp, timeout: 2)
        tcp.send(content: Data(Duml.encode(Commands.setPairingPin(pin: pairingToken))), completion: .idempotent)
        try await Task.sleep(for: .milliseconds(400))
        switch tcp.state {
        case .ready: return
        case .failed(let e): throw e
        default: throw DatalinkError.notReady
        }
    }

    enum DatalinkError: LocalizedError {
        case noHandshake
        case notReady
        var errorDescription: String? {
            switch self {
            case .noHandshake: "camera never answered the datalink handshake"
            case .notReady: "camera Wi-Fi path was not ready for the datalink"
            }
        }
    }
}

/// HEVC reassembly on the UDP queue. Main hops only complete access units (~25 Hz),
/// not every SoftAP datagram.
private final class SoftAPVideoAssembler: @unchecked Sendable {
    struct Snapshot {
        var packets = 0
        var dropped = 0
        var lastPacket: Date?
        var lastAU: Date?
        var accessUnits = 0
    }

    struct Ingest {
        var accessUnit: [UInt8]?
        var firstPacket = false
        var shouldHop = false
    }

    private struct State {
        var depacketizer = HevcDepacketizer()
        var packets = 0
        var accessUnits = 0
        var lastPacket: Date?
        var lastAU: Date?
        var loggedFirst = false
        var peerCursor: UInt16 = 0
        var pending: [[UInt8]] = []
        var hopScheduled = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func ingest(_ datagram: [UInt8]) -> Ingest {
        lock.withLock { state in
            state.packets += 1
            state.lastPacket = Date()
            if let seq = DumlTransport.transportSeq(datagram) {
                state.peerCursor = seq
            }
            let first = !state.loggedFirst
            if first { state.loggedFirst = true }
            let au = state.depacketizer.feed(datagram)
            var shouldHop = false
            if let au {
                state.accessUnits += 1
                state.lastAU = Date()
                state.pending.append(au)
                if state.pending.count > 8 {
                    state.pending.removeFirst(state.pending.count - 8)
                }
                if !state.hopScheduled {
                    state.hopScheduled = true
                    shouldHop = true
                }
            }
            return Ingest(accessUnit: au, firstPacket: first, shouldHop: shouldHop)
        }
    }

    func takePending() -> [[UInt8]] {
        lock.withLock { state in
            let aus = state.pending
            state.pending.removeAll(keepingCapacity: true)
            state.hopScheduled = false
            return aus
        }
    }

    var hasPending: Bool {
        lock.withLock { !$0.pending.isEmpty }
    }

    func snapshot() -> Snapshot {
        lock.withLock { state in
            Snapshot(
                packets: state.packets,
                dropped: state.depacketizer.droppedIncomplete,
                lastPacket: state.lastPacket,
                lastAU: state.lastAU,
                accessUnits: state.accessUnits
            )
        }
    }

    func peerCursor(fallback: UInt16) -> UInt16 {
        lock.withLock { state in
            state.peerCursor == 0 ? fallback : state.peerCursor
        }
    }

    func notePeerCursor(_ cursor: UInt16) {
        lock.withLock { $0.peerCursor = cursor }
    }

    func reset() {
        lock.withLock { $0 = State() }
    }

    /// Clear receive clocks. Stamping `Date()` looked like a live packet and
    /// reset the feed watchdog to idle, which then rebuilt again at 2s.
    func noteRebuild() {
        lock.withLock {
            $0.lastPacket = nil
            $0.lastAU = nil
        }
    }
}
