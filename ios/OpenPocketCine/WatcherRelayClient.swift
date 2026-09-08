import Foundation
import Network
import Observation
import OpenPocketViewCore

enum WatcherRelayClientStatus: Equatable {
    case idle
    case connecting
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
    private var buffer = Data()
    private var endpoint: NWEndpoint?
    private var passcode = ""
    private var watcherID = ""
    private var deviceName = "iPhone"

    func join(
        endpoint: NWEndpoint, hostName: String, passcode: String, watcherID: String,
        deviceName: String
    ) {
        leave()
        self.endpoint = endpoint
        self.passcode = passcode
        self.watcherID = watcherID
        self.deviceName = deviceName
        hostTitle = hostName
        status = .connecting
        decoder.attach(sampleBus: samples, effects: { LiveImageEffects() }, transfer: { nil })
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        params.serviceClass = .interactiveVideo
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        let conn = NWConnection(to: endpoint, using: params)
        self.conn = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.sendHello()
                case .failed(let error):
                    self?.fail(error.localizedDescription)
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
        receive()
    }

    func retryPasscode(_ code: String) {
        guard let endpoint else { return }
        join(
            endpoint: endpoint, hostName: hostTitle, passcode: code, watcherID: watcherID,
            deviceName: deviceName)
    }

    func leave() {
        conn?.cancel()
        conn = nil
        buffer.removeAll()
        decoder.reset()
        if status != .needsPasscode { status = .idle }
    }

    func requestControl() {
        send(Data(), kind: .requestControl)
    }

    func releaseControl() {
        send(Data(), kind: .releaseControl)
    }

    func sendCommand(_ command: WatcherRelayCommand) {
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
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) {
            [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    do {
                        while let msg = try WatcherRelayFraming.decode(from: self.buffer) {
                            self.buffer.removeFirst(msg.consumedBytes)
                            try self.onMessage(msg)
                        }
                    } catch {
                        self.fail("The feed ended.")
                        return
                    }
                }
                if let error {
                    self.fail(error.localizedDescription)
                    return
                }
                if isComplete {
                    self.fail("The host stopped sharing.")
                    return
                }
                self.receive()
            }
        }
    }

    private func onMessage(_ msg: WatcherRelayFraming.Decoded) throws {
        switch msg.kind {
        case .hello:
            if let hello = try? JSONDecoder().decode(WatcherRelayHello.self, from: msg.payload) {
                hostTitle = hello.hostName
                if let camera = hello.cameraName, !camera.isEmpty {
                    hostTitle = "\(hello.hostName) · \(camera)"
                }
            }
            status = .live
        case .joinDenied:
            let denied = try JSONDecoder().decode(WatcherRelayJoinDenied.self, from: msg.payload)
            if denied.passcodeRequired {
                status = .needsPasscode
            } else {
                fail(denied.reason)
            }
        case .state:
            state = try JSONDecoder().decode(WatcherRelayState.self, from: msg.payload)
        case .controlToken:
            token = try JSONDecoder().decode(WatcherRelayControlToken.self, from: msg.payload)
        case .frame:
            let (meta, hevc) = try WatcherRelayFrameBlob.decode(msg.payload)
            decoder.poseViewFlip = false
            decoder.assistMirror = false
            if meta.extraMirrored {
                decoder.poseViewFlip = true
            }
            _ = decoder.decode(accessUnit: [UInt8](hevc))
        default:
            break
        }
    }

    private func fail(_ message: String) {
        conn?.cancel()
        conn = nil
        status = .failed(message)
    }
}
