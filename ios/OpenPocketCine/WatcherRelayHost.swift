import CoreVideo
import Foundation
import Network
import Observation
import OpenPocketViewCore
import os

/// Advertises `_opc-mon._tcp` and fans out re-encoded HEVC. Encode/send off the ACK thread.
final class WatcherRelayTransport: @unchecked Sendable {
    let queue = DispatchQueue(label: "opc.watcher-relay.transport", qos: .userInitiated)
    var controlRevision: UInt64 = 0
    private let orientationLock = NSLock()
    private var orientation = false
    var onChange: (() -> Void)?
    var onCommand: ((WatcherRelayCommand, String?) -> Void)?
    private var active = true
    private let admission = WatcherRelayAdmission()
    var watcherCount = 0
    var encoderFailed = false
    var pendingControlRequest: (name: String, watcherID: String)?
    var holderName = "Host"

    typealias SendWire = (Data, NWConnection, @escaping () -> Void) -> Void
    private let sendWire: SendWire
    typealias EncodeFrame = (
        CVPixelBuffer, Bool, @escaping (WatcherRelayEncoder.Annex?, Bool) -> Void
    ) -> Void
    private let encodeFrame: EncodeFrame?
    private let now: () -> TimeInterval

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        encodeFrame: EncodeFrame? = nil,
        sendWire: @escaping SendWire = { data, connection, completion in
            connection.send(content: data, completion: .contentProcessed { _ in completion() })
        }
    ) {
        self.sendWire = sendWire
        self.encodeFrame = encodeFrame
        self.now = now
    }

    private var listener: NWListener?
    var peers: [ObjectIdentifier: Peer] = [:]
    private let encoder = WatcherRelayEncoder()
    private var bitrate = WatcherRelayBitrate()
    var bitsPerSecond: Int { bitrate.bitsPerSecond }
    var lease = WatcherRelayControlLease()
    private var passcode = ""
    private var hostName = "OpenPocketCine"
    private var cameraName = ""
    private var allowsControl = true
    private var lastState: WatcherRelayState?
    private var isRecording = false
    private var lastMetricsAt: TimeInterval = 0
    private var sentFrames = 0
    private var skippedFrames = 0
    private var keyframes = 0
    private var lastStateAt: TimeInterval = -.infinity
    private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "relay")

    func start(
        hostName: String, cameraName: String, passcode: String, ceilingIndex: Int,
        allowsControl: Bool, includePeerToPeer: Bool
    ) {
        active = true
        self.hostName = hostName
        self.cameraName = cameraName
        self.passcode = passcode
        self.allowsControl = allowsControl
        bitrate = WatcherRelayBitrate(ceilingIndex: ceilingIndex, now: now())
        lease = WatcherRelayControlLease(holderName: hostName)
        encoderFailed = false
        encoder.bitsPerSecond = bitrate.bitsPerSecond
        do {
            let listener = try NWListener(using: Self.parameters(peerToPeer: includePeerToPeer))
            var txt = NWTXTRecord()
            txt[WatcherRelayProtocol.txtCamera] = cameraName
            txt[WatcherRelayProtocol.txtWatchable] = "1"
            listener.service = NWListener.Service(
                name: hostName, type: WatcherRelayProtocol.serviceType, txtRecord: txt)
            listener.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.encoderFailed = true
                    self?.stop()
                    self?.onChange?()
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            log.info("relay: listening \(WatcherRelayProtocol.serviceType, privacy: .public)")
        } catch {
            encoderFailed = true
            onChange?()
            log.error("relay: listen failed \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        active = false
        admission.stop()
        listener?.cancel()
        listener = nil
        for peer in peers.values { peer.conn.cancel() }
        peers.removeAll()
        watcherCount = 0
        pendingControlRequest = nil
        encoder.invalidate()
        onChange?()
    }

    func setCeiling(_ index: Int) {
        bitrate.ceilingIndex = index
        encoder.bitsPerSecond = bitrate.bitsPerSecond
    }

    /// Called directly by the decoder. Bound admission BEFORE either dispatch queue.
    func updateOrientation(_ mirrored: Bool) {
        orientationLock.lock()
        orientation = mirrored
        orientationLock.unlock()
    }

    func submit(_ identity: CVPixelBuffer) {
        guard admission.admit() else { return }
        orientationLock.lock()
        let mirrored = orientation
        orientationLock.unlock()
        queue.async { [self] in
            guard active else {
                admission.release()
                return
            }
            let authorized = peers.values.filter { $0.authorized }
            guard !authorized.isEmpty else {
                admission.release()
                return
            }
            let allFull = authorized.allSatisfy { $0.inFlight >= 2 }
            guard !allFull else {
                admission.release()
                return
            }
            let needKey = authorized.contains { $0.needsKeyframe && $0.inFlight < 2 }
            let recording = isRecording
            let encode =
                encodeFrame ?? { [encoder] buffer, key, done in
                    encoder.encode(buffer, forceKey: key, completion: done)
                }
            encode(identity, needKey) { [weak self] result, failed in
                guard let self else { return }
                self.queue.async {
                    defer { self.admission.release() }
                    guard self.active else { return }
                    guard !failed else {
                        self.encoderFailed = true
                        self.stop()
                        self.onChange?()
                        return
                    }
                    guard let result else { return }
                    self.broadcast(
                        hevc: result.data, isKey: result.isKey, sets: result.sets,
                        mirrored: mirrored, recording: recording)
                }
            }
        }
    }

    func update(state: WatcherRelayState) {
        isRecording = state.isRecording
        lastState = state
        // Camera FPS is measured by the host present path, independently of relay sends.
        admission.measuredFPS = Double(state.liveFPS)
        let now = now()
        let cameraStarving = admission.cameraStarving
        let authorized = peers.values.filter { $0.authorized }
        if !authorized.isEmpty {
            let allFull = authorized.allSatisfy { $0.inFlight >= 2 }
            if let bps = bitrate.recordTick(
                saturated: allFull,
                cameraStarving: cameraStarving, now: now)
            {
                encoder.bitsPerSecond = bps
            }
            if now - lastMetricsAt >= 5 {
                lastMetricsAt = now
                log.info(
                    "relay: peers=\(authorized.count) bps=\(self.bitrate.bitsPerSecond) sent=\(self.sentFrames) skipped=\(self.skippedFrames) keys=\(self.keyframes) cameraFPS=\(self.admission.measuredFPS ?? 0)"
                )
                sentFrames = 0
                skippedFrames = 0
                keyframes = 0
            }
        }
        if now - lastStateAt >= LiveChromeThrottle.statusInterval {
            lastStateAt = now
            broadcast(state: state)
        }
    }

    func grantControl() {
        guard let pending = pendingControlRequest else { return }
        lease.grant(name: pending.name, watcherID: pending.watcherID)
        holderName = pending.name
        pendingControlRequest = nil
        broadcastToken()
        onChange?()
    }

    func denyControl() {
        pendingControlRequest = nil
        onChange?()
    }

    func reclaimControl() {
        lease.reclaim(hostName: hostName)
        holderName = hostName
        pendingControlRequest = nil
        broadcastToken()
        onChange?()
    }

    func applyCommand(_ command: WatcherRelayCommand, from watcherID: String?)
        -> WatcherRelayCommand?
    {
        guard lease.shouldProxy(commandFrom: watcherID) else { return nil }
        return command
    }

    private func accept(_ conn: NWConnection) {
        guard active else {
            conn.cancel()
            return
        }
        let peer = Peer(conn: conn)
        peers[ObjectIdentifier(peer)] = peer
        watcherCount = peers.values.filter { $0.authorized }.count
        onChange?()
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self, weak peer] data, _, isComplete, error in
            guard let self, let peer else { return }
            self.handle(peer: peer, data: data, isComplete: isComplete, error: error)
        }
        conn.stateUpdateHandler = { [weak self, weak peer] state in
            if case .failed = state {
                if let peer { self?.drop(peer) }
            }
        }
        conn.start(queue: queue)
    }

    private func handle(peer: Peer, data: Data?, isComplete: Bool, error: Error?) {
        guard active, peers[ObjectIdentifier(peer)] === peer else { return }
        if let data, !data.isEmpty {
            peer.buffer.append(data)
            do {
                while let msg = try WatcherRelayFraming.decode(from: peer.buffer) {
                    peer.buffer.removeFirst(msg.consumedBytes)
                    try onMessage(peer: peer, msg: msg)
                }
            } catch {
                drop(peer)
                return
            }
        }
        if isComplete || error != nil {
            drop(peer)
            return
        }
        peer.conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self, weak peer] data, _, isComplete, error in
            guard let self, let peer else { return }
            self.handle(peer: peer, data: data, isComplete: isComplete, error: error)
        }
    }

    func onMessage(peer: Peer, msg: WatcherRelayFraming.Decoded) throws {
        switch msg.kind {
        case .hello:
            guard !peer.authorized else { return }
            let hello = try JSONDecoder().decode(WatcherRelayHello.self, from: msg.payload)
            switch WatcherRelayJoin.hostAccepts(hello: hello, requiredPasscode: passcode) {
            case .failure(let denied):
                send(denied, kind: .joinDenied, on: peer)
                drop(peer)
            case .success:
                peer.authorized = true
                peer.name = hello.hostName
                peer.watcherID = hello.watcherID
                if lease.claim(watcherID: hello.watcherID, name: hello.hostName, now: Date()) {
                    holderName = hello.hostName
                }
                send(
                    WatcherRelayHello(hostName: hostName, cameraName: cameraName),
                    kind: .hello, on: peer)
                if let lastState { send(lastState, kind: .state, on: peer) }
                send(lease.token(forWatcherID: peer.watcherID), kind: .controlToken, on: peer)
                peer.needsKeyframe = true
                watcherCount = peers.values.filter { $0.authorized }.count
                onChange?()
            }
        case .requestControl:
            guard peer.authorized, allowsControl else { return }
            pendingControlRequest = (peer.name, peer.watcherID ?? "")
            onChange?()
        case .releaseControl:
            if lease.shouldProxy(commandFrom: peer.watcherID) {
                reclaimControl()
            }
        case .command:
            guard peer.authorized else { return }
            let command = try JSONDecoder().decode(WatcherRelayCommand.self, from: msg.payload)
            guard lease.shouldProxy(commandFrom: peer.watcherID) else { return }
            onCommand?(command, peer.watcherID)
        default:
            break
        }
    }

    func broadcast(
        hevc: Data, isKey: Bool, sets: [Data]?, mirrored: Bool = false, recording: Bool = false
    ) {
        let meta = WatcherRelayFrameMetadata(
            isKeyframe: isKey, parameterSets: sets, isRecording: recording,
            extraMirrored: mirrored)
        guard let payload = try? WatcherRelayFrameBlob.encode(metadata: meta, hevc: hevc) else {
            return
        }
        let wire = WatcherRelayFraming.encode(kind: .frame, payload: payload)
        if isKey { keyframes += 1 }
        for peer in peers.values where peer.authorized {
            if !isKey, peer.needsKeyframe { continue }
            if peer.inFlight >= 2 {
                skippedFrames += 1
                peer.needsKeyframe = true
                continue
            }
            sentFrames += 1
            send(wire: wire, on: peer, video: true)
            if isKey { peer.needsKeyframe = false }
        }
    }

    private func broadcast(state: WatcherRelayState) {
        var s = state
        s.allowsControlRequests = allowsControl
        for peer in peers.values where peer.authorized {
            guard !peer.stateInFlight else { continue }
            peer.stateInFlight = true
            guard let payload = try? JSONEncoder().encode(s) else {
                peer.stateInFlight = false
                continue
            }
            sendWire(WatcherRelayFraming.encode(kind: .state, payload: payload), peer.conn) {
                [weak self, weak peer] in
                self?.queue.async { peer?.stateInFlight = false }
            }
        }
    }

    private func broadcastToken() {
        for peer in peers.values where peer.authorized {
            send(lease.token(forWatcherID: peer.watcherID), kind: .controlToken, on: peer)
        }
    }

    private func send<T: Encodable>(_ value: T, kind: WatcherRelayProtocol.Kind, on peer: Peer) {
        guard let payload = try? JSONEncoder().encode(value) else { return }
        send(wire: WatcherRelayFraming.encode(kind: kind, payload: payload), on: peer)
    }

    private func send(wire: Data, on peer: Peer, video: Bool = false) {
        if video { peer.inFlight += 1 }
        sendWire(wire, peer.conn) { [weak self, weak peer] in
            guard video else { return }
            self?.queue.async {
                peer?.inFlight = max(0, (peer?.inFlight ?? 1) - 1)
            }
        }
    }

    func drop(_ peer: Peer) {
        peer.conn.cancel()
        if lease.shouldProxy(commandFrom: peer.watcherID) {
            _ = lease.park(watcherID: peer.watcherID, name: peer.name, now: Date())
            if lease.hostHolds { holderName = hostName }
            broadcastToken()
        }
        peers.removeValue(forKey: ObjectIdentifier(peer))
        watcherCount = peers.values.filter { $0.authorized }.count
        if pendingControlRequest?.watcherID == peer.watcherID {
            pendingControlRequest = nil
        }
        onChange?()
    }

    private static func parameters(peerToPeer: Bool) -> NWParameters {
        let p = NWParameters.tcp
        p.includePeerToPeer = peerToPeer
        p.serviceClass = .interactiveVideo
        if let tcp = p.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 10
            tcp.keepaliveInterval = 5
            tcp.keepaliveCount = 3
        }
        return p
    }

    final class Peer: @unchecked Sendable {
        let conn: NWConnection
        var buffer = Data()
        var authorized = false
        var needsKeyframe = true
        var inFlight = 0
        var stateInFlight = false
        var watcherID: String?
        var name = "Watcher"
        init(conn: NWConnection) { self.conn = conn }
    }
}

/// Only operator state crosses MainActor. Frame bytes, VT settings, and sockets do not.
@MainActor
@Observable
final class WatcherRelayHost {
    var watcherCount = 0
    var encoderFailed = false
    var pendingControlRequest: (name: String, watcherID: String)?
    var holderName = "Host"
    @ObservationIgnored private var holderWatcherID: String?
    @ObservationIgnored private var controlRevision: UInt64 = 0
    @ObservationIgnored private(set) var transport: WatcherRelayTransport?

    func start(
        hostName: String, cameraName: String, passcode: String, ceilingIndex: Int,
        allowsControl: Bool, includePeerToPeer: Bool
    ) {
        stop()
        encoderFailed = false
        let transport = WatcherRelayTransport()
        self.transport = transport
        transport.controlRevision = controlRevision
        transport.onChange = { [weak self, weak transport] in
            guard let transport else { return }
            let revision = transport.controlRevision
            let count = transport.watcherCount
            let failed = transport.encoderFailed
            let pending = transport.pendingControlRequest
            let holder = transport.holderName
            let holderID = transport.lease.holderWatcherID
            Task { @MainActor [weak self, weak transport] in
                guard let self, self.transport === transport, self.controlRevision == revision
                else { return }
                self.watcherCount = count
                self.encoderFailed = failed
                self.pendingControlRequest = pending
                self.holderName = holder
                self.holderWatcherID = holderID
            }
        }
        transport.onCommand = { [weak self, weak transport] command, watcherID in
            guard let transport else { return }
            let revision = transport.controlRevision
            Task { @MainActor in
                guard let self, self.transport === transport, self.controlRevision == revision
                else { return }
                NotificationCenter.default.post(
                    name: .opcWatcherRelayCommand, object: nil,
                    userInfo: ["command": command, "watcherID": watcherID as Any])
            }
        }
        transport.queue.async {
            transport.start(
                hostName: hostName, cameraName: cameraName, passcode: passcode,
                ceilingIndex: ceilingIndex, allowsControl: allowsControl,
                includePeerToPeer: includePeerToPeer)
        }
    }

    /// Capture once when wiring the decoder; no per-frame actor hop or retained host model.
    func frameSink() -> (CVPixelBuffer) -> Void {
        { [weak transport] buffer in transport?.submit(buffer) }
    }

    func orientationSink() -> (Bool) -> Void {
        { [weak transport] mirrored in transport?.updateOrientation(mirrored) }
    }

    func update(state: WatcherRelayState) {
        guard let transport else { return }
        transport.queue.async { transport.update(state: state) }
    }

    func stop() {
        if let transport { transport.queue.async { transport.stop() } }
        transport = nil
        holderWatcherID = nil
        watcherCount = 0
        pendingControlRequest = nil
    }

    func setCeiling(_ index: Int) {
        guard let transport else { return }
        transport.queue.async { transport.setCeiling(index) }
    }

    func grantControl() {
        guard let transport else { return }
        transport.queue.async { transport.grantControl() }
    }

    func denyControl() {
        guard let transport else { return }
        transport.queue.async { transport.denyControl() }
    }

    func reclaimControl() {
        holderWatcherID = nil
        controlRevision &+= 1
        let revision = controlRevision
        guard let transport else { return }
        transport.queue.async {
            transport.controlRevision = revision
            transport.reclaimControl()
        }
    }

    func applyCommand(_ command: WatcherRelayCommand, from watcherID: String?)
        -> WatcherRelayCommand?
    {
        guard let watcherID, watcherID == holderWatcherID else { return nil }
        return command
    }
}

extension Notification.Name {
    static let opcWatcherRelayCommand = Notification.Name("opc.watcherRelay.command")
}

/// Two retained source frames maximum, including queued, encoding, and awaiting fan-out.
/// This lock is never held across VT, socket I/O, or an actor hop.
final class WatcherRelayAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var policy = WatcherRelayEncodePolicy()
    private var stopped = false
    // Transport-queue owned measurement, independent of the admission lock.
    var measuredFPS: Double?
    private var baselineFPS: Double?

    func admit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stopped && policy.admit()
    }

    func release() {
        lock.lock()
        policy.complete()
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    var cameraStarving: Bool {
        guard let measuredFPS, measuredFPS > 0 else { return baselineFPS != nil }
        baselineFPS = max(baselineFPS ?? measuredFPS, measuredFPS)
        return measuredFPS < (baselineFPS ?? measuredFPS) * 0.8
    }
}
