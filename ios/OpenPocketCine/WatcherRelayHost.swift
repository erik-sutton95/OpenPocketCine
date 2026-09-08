import CoreVideo
import Foundation
import Network
import Observation
import OpenPocketViewCore
import os

/// Advertises `_opc-mon._tcp` and fans out re-encoded HEVC. Encode/send off the ACK thread.
@MainActor
@Observable
final class WatcherRelayHost {
    var watcherCount = 0
    var encoderFailed = false
    var pendingControlRequest: (name: String, watcherID: String)?
    var holderName = "Host"

    private var listener: NWListener?
    private var peers: [ObjectIdentifier: Peer] = [:]
    private let encoder = WatcherRelayEncoder()
    private let encodeQueue = DispatchQueue(label: "opc.watcher-relay.encode", qos: .userInitiated)
    private var bitrate = WatcherRelayBitrate()
    private var lease = WatcherRelayControlLease()
    private var passcode = ""
    private var hostName = "OpenPocketCine"
    private var cameraName = ""
    private var allowsControl = true
    private var lastState: WatcherRelayState?
    private var extraMirrored = false
    private var isRecording = false
    private var lastKeyframePeerNeed = false
    private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "relay")

    func start(
        hostName: String, cameraName: String, passcode: String, ceilingIndex: Int,
        allowsControl: Bool, includePeerToPeer: Bool
    ) {
        stop()
        self.hostName = hostName
        self.cameraName = cameraName
        self.passcode = passcode
        self.allowsControl = allowsControl
        bitrate = WatcherRelayBitrate(ceilingIndex: ceilingIndex)
        lease = WatcherRelayControlLease(holderName: hostName)
        encoderFailed = false
        encoder.bitsPerSecond = bitrate.bitsPerSecond
        encoder.onEncoded = { [weak self] data, isKey, sets in
            Task { @MainActor in
                self?.broadcast(hevc: data, isKey: isKey, sets: sets)
            }
        }
        do {
            let listener = try NWListener(using: Self.parameters(peerToPeer: includePeerToPeer))
            var txt = NWTXTRecord()
            txt[WatcherRelayProtocol.txtCamera] = cameraName
            txt[WatcherRelayProtocol.txtWatchable] = "1"
            listener.service = NWListener.Service(
                name: hostName, type: WatcherRelayProtocol.serviceType, txtRecord: txt)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    Task { @MainActor in
                        self?.encoderFailed = true
                        self?.stop()
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            log.info("relay: listening \(WatcherRelayProtocol.serviceType, privacy: .public)")
        } catch {
            encoderFailed = true
            log.error("relay: listen failed \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for peer in peers.values { peer.conn.cancel() }
        peers.removeAll()
        watcherCount = 0
        pendingControlRequest = nil
        encoder.invalidate()
        encoder.onEncoded = nil
    }

    func setCeiling(_ index: Int) {
        bitrate.ceilingIndex = index
        encoder.bitsPerSecond = bitrate.bitsPerSecond
    }

    func ingest(identity: CVPixelBuffer, extraMirrored: Bool, state: WatcherRelayState) {
        guard listener != nil else { return }
        self.extraMirrored = extraMirrored
        self.isRecording = state.isRecording
        lastState = state
        let allFull = !peers.isEmpty && peers.values.allSatisfy { $0.inFlight >= 2 }
        _ = bitrate.recordTick(
            saturated: allFull, cameraStarving: false, now: CFAbsoluteTimeGetCurrent())
        encoder.bitsPerSecond = bitrate.bitsPerSecond
        if peers.values.allSatisfy({ !$0.authorized }) { return }
        if WatcherRelayBitrate.shouldSkipEncode(allPeersSaturated: allFull) { return }
        let needKey = peers.values.contains { $0.needsKeyframe } || lastKeyframePeerNeed
        lastKeyframePeerNeed = false
        if needKey { encoder.requestKeyframe() }
        encodeQueue.async { [encoder] in
            encoder.encode(identity, forceKey: needKey)
        }
    }

    func grantControl() {
        guard let pending = pendingControlRequest else { return }
        lease.grant(name: pending.name, watcherID: pending.watcherID)
        holderName = pending.name
        pendingControlRequest = nil
        broadcastToken()
    }

    func denyControl() {
        pendingControlRequest = nil
    }

    func reclaimControl() {
        lease.reclaim(hostName: hostName)
        holderName = hostName
        pendingControlRequest = nil
        broadcastToken()
    }

    func applyCommand(_ command: WatcherRelayCommand, from watcherID: String?)
        -> WatcherRelayCommand?
    {
        guard lease.shouldProxy(commandFrom: watcherID) else { return nil }
        return command
    }

    private func accept(_ conn: NWConnection) {
        let peer = Peer(conn: conn)
        peers[ObjectIdentifier(peer)] = peer
        watcherCount = peers.count
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self, weak peer] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, let peer else { return }
                self.handle(peer: peer, data: data, isComplete: isComplete, error: error)
            }
        }
        conn.stateUpdateHandler = { [weak self, weak peer] state in
            if case .failed = state {
                Task { @MainActor in
                    if let peer { self?.drop(peer) }
                }
            }
        }
        conn.start(queue: .main)
    }

    private func handle(peer: Peer, data: Data?, isComplete: Bool, error: Error?) {
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
            Task { @MainActor in
                guard let self, let peer else { return }
                self.handle(peer: peer, data: data, isComplete: isComplete, error: error)
            }
        }
    }

    private func onMessage(peer: Peer, msg: WatcherRelayFraming.Decoded) throws {
        switch msg.kind {
        case .hello:
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
                lastKeyframePeerNeed = true
            }
        case .requestControl:
            guard peer.authorized, allowsControl else { return }
            pendingControlRequest = (peer.name, peer.watcherID ?? "")
        case .releaseControl:
            if lease.shouldProxy(commandFrom: peer.watcherID) {
                reclaimControl()
            }
        case .command:
            guard peer.authorized else { return }
            let command = try JSONDecoder().decode(WatcherRelayCommand.self, from: msg.payload)
            NotificationCenter.default.post(
                name: .opcWatcherRelayCommand,
                object: nil,
                userInfo: ["command": command, "watcherID": peer.watcherID as Any])
        default:
            break
        }
    }

    private func broadcast(hevc: Data, isKey: Bool, sets: [Data]?) {
        let meta = WatcherRelayFrameMetadata(
            isKeyframe: isKey, parameterSets: sets, isRecording: isRecording,
            extraMirrored: extraMirrored)
        guard let payload = try? WatcherRelayFrameBlob.encode(metadata: meta, hevc: hevc) else {
            return
        }
        let wire = WatcherRelayFraming.encode(kind: .frame, payload: payload)
        for peer in peers.values where peer.authorized {
            if !isKey, peer.needsKeyframe { continue }
            if peer.inFlight >= 2 {
                peer.needsKeyframe = true
                continue
            }
            send(wire: wire, on: peer)
            if isKey { peer.needsKeyframe = false }
        }
        if let lastState { broadcast(state: lastState) }
    }

    private func broadcast(state: WatcherRelayState) {
        var s = state
        s.allowsControlRequests = allowsControl
        for peer in peers.values where peer.authorized {
            send(s, kind: .state, on: peer)
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

    private func send(wire: Data, on peer: Peer) {
        peer.inFlight += 1
        peer.conn.send(
            content: wire,
            completion: .contentProcessed { [weak self, weak peer] _ in
                Task { @MainActor in
                    peer?.inFlight = max(0, (peer?.inFlight ?? 1) - 1)
                    self?.watcherCount = self?.peers.count ?? 0
                }
            })
    }

    private func drop(_ peer: Peer) {
        peer.conn.cancel()
        if lease.shouldProxy(commandFrom: peer.watcherID) {
            _ = lease.park(watcherID: peer.watcherID, name: peer.name, now: Date())
            if lease.hostHolds { holderName = hostName }
            broadcastToken()
        }
        peers.removeValue(forKey: ObjectIdentifier(peer))
        watcherCount = peers.count
        if pendingControlRequest?.watcherID == peer.watcherID {
            pendingControlRequest = nil
        }
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

    fileprivate final class Peer {
        let conn: NWConnection
        var buffer = Data()
        var authorized = false
        var needsKeyframe = true
        var inFlight = 0
        var watcherID: String?
        var name = "Watcher"
        init(conn: NWConnection) { self.conn = conn }
    }
}

extension Notification.Name {
    static let opcWatcherRelayCommand = Notification.Name("opc.watcherRelay.command")
}
