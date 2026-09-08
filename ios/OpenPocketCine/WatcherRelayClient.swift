import Foundation
import Network
import Observation
import OpenPocketViewCore

enum WatcherRelayClientStatus: Equatable {
    case idle
    case connecting
    case reconnecting(Int)
    case needsPasscode
    case live
    case failed(String)
}

/// One TCP join to a host. Frames go to a dedicated `HevcDecoder`.
@MainActor
@Observable
final class WatcherRelayClient {
    var status: WatcherRelayClientStatus = .idle
    var state = WatcherRelayState()
    var token = WatcherRelayControlToken(holderName: "Host", holderIsRecipient: false)
    var hostTitle = ""
    let decoder = HevcDecoder()
    let samples = LiveFrameSampleBus()

    private var conn: NWConnection?
    private var reader: WatcherRelayReader?
    private var endpoint: NWEndpoint?
    private var passcode = ""
    private var watcherID = ""
    private var deviceName = "iPhone"
    private var serviceName = ""
    @ObservationIgnored var resolveEndpoint: ((String) -> NWEndpoint?)?
    @ObservationIgnored var onReconnect: (() -> Void)?
    @ObservationIgnored private var recovery: WatcherRelayRecovery?
    @ObservationIgnored private var freshness = WatcherRelayFrameFreshness()
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var lastPictureAt: TimeInterval?
    @ObservationIgnored private var lastPresentation: Date?
    @ObservationIgnored private var acceptedAt: TimeInterval?
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var fpsSince = ProcessInfo.processInfo.systemUptime
    var receivedFPS = 0
    var waitingForPicture = false
    var controlRequested = false
    @ObservationIgnored private var controlRequestedAt: TimeInterval?
    var colorMode: ColorMode? {
        ColorMode(label: state.color)
    }
    var transfer: MonitorTransfer? { colorMode.map(MonitorTransfer.init) }
    var canControl: Bool { status == .live && token.holderIsRecipient }

    func join(
        endpoint: NWEndpoint, hostName: String, passcode: String, watcherID: String,
        deviceName: String
    ) {
        leave()
        self.endpoint = endpoint
        self.passcode = passcode
        self.watcherID = watcherID
        self.deviceName = deviceName
        serviceName = hostName
        hostTitle = hostName
        state = WatcherRelayState()
        token = WatcherRelayControlToken(holderName: "Host", holderIsRecipient: false)
        receivedFPS = 0
        frameCount = 0
        fpsSince = ProcessInfo.processInfo.systemUptime
        lastPictureAt = nil
        lastPresentation = nil
        waitingForPicture = false
        recovery = WatcherRelayRecovery(now: ProcessInfo.processInfo.systemUptime)
        status = .connecting
        // VideoView owns the local raster effects; an identity provider would undo
        // the operator's selection on every incoming access unit.
        decoder.sampleBus = samples
        decoder.effectsProvider = nil
        decoder.transferProvider = { [weak self] in self?.transfer }
        decoder.onPresentedFrame = { [weak self] in
            guard let self, self.status == .live,
                let presentedAt = self.decoder.monitorPresentedAt,
                presentedAt != self.lastPresentation
            else { return }
            self.lastPresentation = presentedAt
            let now = ProcessInfo.processInfo.systemUptime
            self.lastPictureAt = now
            self.frameCount += 1
            self.recovery?.received(now: now, picture: true)
        }
        connect(to: endpoint, recovering: false)
        recoveryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.tickRecovery()
            }
        }
    }

    private func connect(to endpoint: NWEndpoint, recovering: Bool) {
        conn?.cancel()
        conn = nil
        reader = nil
        freshness = WatcherRelayFrameFreshness()
        if recovering { decoder.flushForRecovery() }
        ControlLiveLog.line("relay watcher: connecting on shared Wi-Fi")
        let connection = NWConnection(to: endpoint, using: WatcherRelayNetwork.parameters())
        conn = connection
        let streamReader = WatcherRelayReader()
        reader = streamReader
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self, let connection, self.conn === connection else { return }
                switch state {
                case .ready: self.sendHello()
                case .failed(let error): self.connectionLost(error.localizedDescription)
                case .waiting:
                    // Network.framework may recover this path itself; the join deadline bounds it.
                    ControlLiveLog.line("relay watcher: waiting for shared Wi-Fi")
                default: break
                }
            }
        }
        connection.start(queue: streamReader.queue)
        receive()
    }

    private func tickRecovery() {
        guard var policy = recovery else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let action = policy.tick(now: now)
        recovery = policy
        if policy.retryAt != nil, !isReconnecting {
            beginReconnect()
        }
        switch action {
        case .reconnect:
            let fresh =
                resolveEndpoint?(serviceName)
                ?? endpoint.map(WatcherRelayNetwork.rediscoveryEndpoint)
            guard let fresh else {
                fail("Choose a shared feed to reconnect.")
                return
            }
            connect(to: fresh, recovering: true)
        case .exhausted:
            fail(
                "Could not reconnect. Check that both devices are on the same camera Wi-Fi and sharing is on, then choose the feed again."
            )
        case .none: break
        }
        if now - fpsSince >= 1 {
            receivedFPS = Int((Double(frameCount) / (now - fpsSince)).rounded())
            frameCount = 0
            fpsSince = now
        }
        waitingForPicture = status == .live && now - (lastPictureAt ?? acceptedAt ?? now) >= 3
        if let controlRequestedAt, now - controlRequestedAt >= 15 {
            controlRequested = false
            self.controlRequestedAt = nil
        }
    }

    private var isReconnecting: Bool {
        if case .reconnecting = status { return true }
        return false
    }

    private func connectionLost(_ reason: String) {
        guard recovery != nil else { return }
        ControlLiveLog.line("relay watcher: connection interrupted — \(reason)")
        let action = recovery?.disconnected(now: ProcessInfo.processInfo.systemUptime)
        if action == .exhausted {
            fail("Could not reconnect. Check camera Wi-Fi and sharing, then choose the feed again.")
        } else {
            beginReconnect()
        }
    }

    private func beginReconnect() {
        conn?.cancel()
        conn = nil
        reader = nil
        token = WatcherRelayControlToken(holderName: token.holderName, holderIsRecipient: false)
        controlRequested = false
        acceptedAt = nil
        status = .reconnecting(recovery?.retryCount ?? 1)
        onReconnect?()
    }

    func retryPasscode(_ code: String) {
        guard let endpoint else { return }
        join(
            endpoint: endpoint, hostName: serviceName, passcode: code, watcherID: watcherID,
            deviceName: deviceName)
    }

    func leave() {
        recoveryTask?.cancel()
        recoveryTask = nil
        recovery?.stop()
        recovery = nil
        controlRequested = false
        controlRequestedAt = nil
        waitingForPicture = false
        conn?.cancel()
        conn = nil
        reader = nil
        decoder.reset()
        status = .idle
    }

    func requestControl() {
        guard status == .live, state.allowsControlRequests, !controlRequested else { return }
        controlRequested = true
        controlRequestedAt = ProcessInfo.processInfo.systemUptime
        send(Data(), kind: .requestControl)
    }

    func releaseControl() {
        guard canControl else { return }
        send(Data(), kind: .releaseControl)
    }

    func sendCommand(_ command: WatcherRelayCommand) {
        guard canControl else { return }
        guard let payload = try? JSONEncoder().encode(command) else { return }
        send(payload, kind: .command)
    }

    private func sendHello() {
        let hello = WatcherRelayHello(
            hostName: deviceName, passcode: passcode.isEmpty ? nil : passcode,
            watcherID: watcherID)
        guard let payload = try? JSONEncoder().encode(hello) else { return }
        send(payload, kind: .hello)
    }

    private func send(_ payload: Data, kind: WatcherRelayProtocol.Kind) {
        let wire = WatcherRelayFraming.encode(kind: kind, payload: payload)
        conn?.send(content: wire, completion: .contentProcessed { _ in })
    }

    private func receive() {
        guard let conn, let reader else { return }
        reader.receive(on: conn) { [weak self, weak conn] messages, complete, error in
            Task { @MainActor in
                guard let self, let conn, self.conn === conn else { return }
                do {
                    for message in messages {
                        switch message {
                        case .control(let message): try self.onMessage(message)
                        case .frame(let meta, let hevc):
                            self.decoder.poseViewFlip = meta.extraMirrored
                            guard self.status == .live else { continue }
                            if self.freshness.isFallingBehind(
                                encodedAt: meta.encodedAt,
                                receivedAt: ProcessInfo.processInfo.systemUptime)
                            {
                                self.connectionLost("The shared feed fell behind live delivery.")
                                return
                            }
                            self.decoder.decode(accessUnit: hevc)
                        }
                        guard self.conn === conn else { return }
                        if self.status == .needsPasscode { return }
                    }
                } catch {
                    self.fail("The feed ended.")
                    return
                }
                if let error {
                    self.connectionLost(error.localizedDescription)
                    return
                }
                if complete {
                    self.connectionLost("The connection closed.")
                    return
                }
                self.receive()
            }
        }
    }

    private func onMessage(_ msg: WatcherRelayFraming.Decoded) throws {
        switch msg.kind {
        case .hello:
            let hello = try JSONDecoder().decode(WatcherRelayHello.self, from: msg.payload)
            guard hello.version == WatcherRelayProtocol.version else {
                fail("Update OpenPocketCine on both devices to watch this feed.")
                return
            }
            hostTitle = hello.hostName
            if let camera = hello.cameraName, !camera.isEmpty {
                hostTitle = "\(hello.hostName) · \(camera)"
            }
            status = .live
            let now = ProcessInfo.processInfo.systemUptime
            acceptedAt = now
            recovery?.connected(now: now)
            ControlLiveLog.line("relay watcher: host accepted join")
        case .joinDenied:
            let denied = try JSONDecoder().decode(WatcherRelayJoinDenied.self, from: msg.payload)
            if denied.passcodeRequired {
                conn?.cancel()
                conn = nil
                recoveryTask?.cancel()
                recovery = nil
                status = .needsPasscode
                ControlLiveLog.line("relay watcher: passcode required")
            } else {
                fail(denied.reason)
            }
        case .state:
            state = try JSONDecoder().decode(WatcherRelayState.self, from: msg.payload)
            recovery?.received(now: ProcessInfo.processInfo.systemUptime)
        case .controlToken:
            token = try JSONDecoder().decode(WatcherRelayControlToken.self, from: msg.payload)
            controlRequested = false
            controlRequestedAt = nil
            recovery?.received(now: ProcessInfo.processInfo.systemUptime)
        default:
            break
        }
    }

    private func fail(_ message: String) {
        recoveryTask?.cancel()
        recoveryTask = nil
        recovery?.stop()
        recovery = nil
        token = WatcherRelayControlToken(holderName: token.holderName, holderIsRecipient: false)
        controlRequested = false
        waitingForPicture = false
        conn?.cancel()
        conn = nil
        status = .failed(message)
        ControlLiveLog.line("relay watcher: connection failed — \(message)")
    }
}
