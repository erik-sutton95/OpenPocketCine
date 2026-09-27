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
    private var connectingBLE = false
    private var connectCancellation: Task<Void, Never>?
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
        connectingBLE = true
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await ble.connect(camera)
            } onCancel: {
                Task { @MainActor in
                    // Only the pre-role GATT wait is interruptible by disconnecting.
                    guard self.connectingBLE else { return }
                    self.connectCancellation = Task { await self.ble.disconnectAndWait() }
                }
            }
            connectingBLE = false
        } catch {
            connectingBLE = false
            await connectCancellation?.value
            connectCancellation = nil
            throw error
        }
        await connectCancellation?.value
        connectCancellation = nil
        try Task.checkCancellation()
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
                approved = try Self.acceptsPairingReply(response, sequence: pair.seq)
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
    /// A previous network session can answer `00 06` at cleanup. It is not
    /// approval: close that BLE link and retry pairing before sending an AP SET.
    static func acceptsPairingReply(_ response: Duml.Frame, sequence: UInt16) throws -> Bool {
        guard response.seq == sequence, response.cmdSet == 7, response.cmdId == 0x45,
            response.flags & 128 != 0
        else { return false }
        switch response.payload {
        case [0, 1]: return true
        case [0, 2]: return false
        case [0, 6]: throw MultiviewSession.Failure.pairingDeferred
        default: throw MultiviewSession.Failure.rejected
        }
    }

    /// Closes and returns once iOS reports the Bluetooth link down, so the next connect to
    /// this camera from another link is not dropped with it.
    func closeAndWait() async {
        closed = true
        keepalive?.cancel()
        router?.cancel()
        await ble.disconnectAndWait()
        replies.removeAll()
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
    /// Networks the camera can see, reported as they arrive: Multiview's captured station
    /// role, repeated `07/AB` scans and their `07/AC` reports, until `rounds` finish or the
    /// caller cancels. `07/48 00` then returns the camera to its own Wi-Fi on the same link,
    /// even after cancellation. The caller stamps the role change first.
    static func scanNetworks(
        _ camera: FoundCamera, rounds: Int = 4,
        beforeStationChange: @escaping @MainActor () throws -> Void = {},
        onRestored: @escaping @MainActor (Bool) -> Void = { _ in },
        onFound: @escaping @MainActor (String) -> Void
    ) async throws {
        let client = MultiviewProvisioner()
        var seen = Set<String>()
        client.onFrame = { frame in
            guard frame.cmdSet == 7, frame.cmdId == 0xac, frame.sender == 7 else { return }
            for name in MulticamWiFiScan.names(frame.payload) where seen.insert(name).inserted {
                onFound(name)
            }
        }
        var failure: Error?
        var restored = false
        var restoreNeeded = false
        do {
            try await client.connect(camera, pairingTimeout: 30)
            if camera.model.family == .nano {
                _ = try await client.exchange(Commands.session5310(id: client.next()))
            }
            do {
                try beforeStationChange()
                restoreNeeded = true
                let role = try await client.exchange(
                    MulticamCommands.stationMode(true, seq: client.next()))
                guard role.payload.first == 0 else { throw MultiviewSession.Failure.rejected }
                try await Task.sleep(for: .seconds(10))
                for _ in 0..<rounds {
                    // A lost scan reply is not fatal; later rounds and reports still land.
                    _ = try? await client.exchange(
                        MulticamWiFiScan.request(seq: client.next()), timeout: 8)
                    try await Task.sleep(for: .seconds(5))
                }
            } catch {
                failure = error
            }
            // Its own task: a cancelled scan must still return the camera to its access point.
            if restoreNeeded {
                let back = await Task {
                    try? await client.exchange(
                        MulticamCommands.stationMode(false, seq: client.next()))
                }.value
                restored = back?.payload == [0] || back?.payload == [0, 0]
                ControlLiveLog.line(
                    "setup: camera scan found=\(seen.count) returned=\(restored)")
            }
        } catch {
            failure = error
        }
        // Also its own task: the connect that follows must not share a dying link.
        await Task { await client.closeAndWait() }.value
        if restoreNeeded { onRestored(restored) }
        if let failure { throw failure }
    }
}
