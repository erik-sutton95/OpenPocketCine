import Foundation
import OpenPocketViewCore

/// One camera owns one BLE link, sequence space, reply router and keepalive.
@MainActor final class MultiviewProvisioner {
    private let ble = BleLink(allowsConcurrentCameras: true)
    private var router: Task<Void, Never>?
    private var keepalive: Task<Void, Never>?
    private var replies: [UInt16: Duml.Frame] = [:]
    private var sequence: UInt16 = 1200
    private var approved = false
    private var closed = false
    /// Sees every camera frame first (e.g. `07/AC` scan reports, whatever their flags).
    var onFrame: ((Duml.Frame) -> Void)?

    func next() -> UInt16 {
        sequence &+= 1
        return sequence
    }
    func send(_ frame: Duml.Frame) { if !closed { ble.send(frame) } }
    func exchange(_ frame: Duml.Frame, timeout: TimeInterval = 12) async throws -> Duml.Frame {
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        replies.removeValue(forKey: frame.seq)
        send(frame)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            if let reply = replies.removeValue(forKey: frame.seq),
                reply.cmdSet == frame.cmdSet, reply.cmdId == frame.cmdId
            {
                return reply
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw MultiviewSession.Failure.timeout
    }
    func connect(_ camera: FoundCamera, pairingTimeout: TimeInterval = 90) async throws {
        let powerDeadline = Date().addingTimeInterval(8)
        while !ble.isPoweredOn && Date() < powerDeadline {
            guard !closed else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard ble.isPoweredOn else { throw MultiviewSession.Failure.unavailable }
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        try await ble.connect(camera)
        guard !closed else { throw CancellationError() }
        let frames = ble.frames
        router = Task { [weak self] in
            for await frame in frames {
                guard let self, !Task.isCancelled, !closed else { return }
                onFrame?(frame)
                if frame.cmdSet == 7, frame.cmdId == 0x46, frame.flags & 128 == 0 {
                    send(Commands.pairApprovalAck(seq: frame.seq))
                    approved = true
                } else if frame.flags & 128 != 0 {
                    if replies.count > 128 { replies.removeAll() }
                    replies[frame.seq] = frame
                }
            }
        }
        send(Commands.sessionWake(id: next()))
        let pair = Commands.setPairingPin(pin: camera.model.pairingToken, id: next())
        send(pair)
        let deadline = Date().addingTimeInterval(pairingTimeout)
        while !approved && Date() < deadline {
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            if let response = replies.removeValue(forKey: pair.seq) {
                if response.payload == [0, 1] {
                    approved = true
                } else if response.payload != [0, 2] {
                    throw MultiviewSession.Failure.rejected
                }
            }
            if !approved { try await Task.sleep(for: .milliseconds(100)) }
        }
        guard approved else { throw MultiviewSession.Failure.timeout }
        keepalive = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !closed else { return }
                send(Commands.sessionKeepalive(id: next()))
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    func close() {
        closed = true
        keepalive?.cancel()
        router?.cancel()
        ble.disconnect()
        replies.removeAll()
    }
}

extension MultiviewProvisioner {
    /// Networks the camera can see: Multiview's captured station role, `07/AB` scan and
    /// `07/AC` reports, then `07/48 00` on the same link so the camera is back on its own
    /// Wi-Fi before this returns. The caller stamps the role change first.
    static func scanNetworks(_ camera: FoundCamera) async throws -> [String] {
        let client = MultiviewProvisioner()
        defer { client.close() }
        var names: [String] = []
        client.onFrame = { frame in
            guard frame.cmdSet == 7, frame.cmdId == 0xac, frame.sender == 7 else { return }
            for name in MulticamWiFiScan.names(frame.payload) where !names.contains(name) {
                names.append(name)
            }
        }
        try await client.connect(camera, pairingTimeout: 30)
        if camera.model.family == .nano {
            _ = try await client.exchange(Commands.session5310(id: client.next()))
        }
        do {
            let role = try await client.exchange(
                MulticamCommands.stationMode(true, seq: client.next()))
            guard role.payload.first == 0 else { throw MultiviewSession.Failure.rejected }
            try await Task.sleep(for: .seconds(10))
            _ = try await client.exchange(MulticamWiFiScan.request(seq: client.next()), timeout: 8)
            try await Task.sleep(for: .seconds(6))
        } catch {
            _ = try? await client.exchange(MulticamCommands.stationMode(false, seq: client.next()))
            throw error
        }
        let back = try? await client.exchange(
            MulticamCommands.stationMode(false, seq: client.next()))
        ControlLiveLog.line(
            "setup: camera scan found=\(names.count) returned=\(back?.payload.first == 0)")
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
