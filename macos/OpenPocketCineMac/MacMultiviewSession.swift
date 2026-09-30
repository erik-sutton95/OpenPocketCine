import Foundation
import Observation
import OpenPocketCineMacCore
import OpenPocketViewCore

extension FoundCamera {
    var appearsInMultiview: Bool { MulticamSupport.appears(model) }
    var hasMultiviewPreview: Bool { MulticamSupport.hasPreview(model) }
}

@MainActor
@Observable
final class MacTile: Identifiable {
    let id = UUID()
    var camera: FoundCamera?
    var status = "Empty"
    var failure: String?
    var connecting = false
    var controlHost: String?
    var cameraAddress = ""
    var identity: [UInt8]?
    var recording: Bool?
    var recordingAt: Date?
    var recordingBusy = false
    var recordingNote: String?
    let decoder = MacPreviewDecoder()
    var driver: DatalinkDriver?
    var responses: [UInt16: Duml.Frame] = [:]

    var recordCamera: MacRecordCamera {
        MacRecordCamera(
            id: id,
            recording: recording,
            statusAge: recordingAt.map { Date().timeIntervalSince($0) } ?? .infinity,
            busy: recordingBusy || connecting,
            connected: controlHost != nil)
    }

    func clearConnection() {
        driver?.close()
        driver = nil
        controlHost = nil
        cameraAddress = ""
        identity = nil
        recording = nil
        recordingAt = nil
        recordingBusy = false
        recordingNote = nil
        responses.removeAll()
        decoder.reset()
    }
}

/// Four cameras on one shared LAN. Each occupied tile owns its datalink and decoder.
@MainActor
@Observable
final class MacMultiviewSession {
    var tiles: [MacTile] = (0..<MacTileBoard.capacity).map { _ in MacTile() }
    var ssid = ""
    var password = ""
    var wifiNameDenied = false
    var networkAccepted = false
    var lanAddress: String?
    var cameraHotspotAddress: String?
    private var detectedSSID: String?
    var discovered: [FoundCamera] = []
    var scanNote = "Bluetooth is starting"
    var groupBusy = false
    var groupNote = "Recording is not synchronized."
    var busy = false

    init(previewStage: Bool = false) {
        if previewStage {
            ssid = "Shared Wi-Fi"
            lanAddress = "192.168.1.20"
            networkAccepted = true
            scanNote = "Looking for cameras"
        }
        currentWiFi.onChange = { [weak self] in self?.applyCurrentWiFi() }
        startKeepalive()
    }

    /// The camera stops video about 10 s after the last `0x00/0x88` registration.
    /// A 1 Hz presence frame on the open datalink holds the picture.
    private func startKeepalive() {
        guard keepaliveTask == nil else { return }
        keepaliveTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                for tile in self.tiles {
                    tile.driver?.keepalive()
                }
            }
        }
    }

    private let currentWiFi = MacCurrentWiFi()
    private let scanner = BleLink(allowsConcurrentCameras: true)
    private var provisioning = false
    private var pendingIdentity: [UInt8]?
    private var scanTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var provisioners: [UUID: MultiviewProvisioner] = [:]

    var board: MacTileBoard {
        var ids = Array<UUID?>(repeating: nil, count: MacTileBoard.capacity)
        for (index, tile) in tiles.enumerated() {
            ids[index] = tile.camera?.id
        }
        return MacTileBoard(cameraIDs: ids)
    }

    var assignedRecordCameras: [MacRecordCamera] {
        tiles.filter { $0.camera != nil }.map(\.recordCamera)
    }

    var groupStop: Bool {
        assignedRecordCameras.contains { $0.recording == true }
    }

    func refreshLAN() {
        lanAddress = MacLanPath.current()?.ipv4
        updateCameraHotspot()
        guard !networkAccepted else { return }
        currentWiFi.refresh()
    }

    private func updateCameraHotspot() {
        let name = currentWiFi.ssid ?? detectedSSID ?? ssid
        if let ip = lanAddress, MacLanPath.isCameraAccessPoint(ip), MacLanPath.isOsmoSoftAP(name) {
            cameraHotspotAddress = ip
        } else {
            cameraHotspotAddress = nil
        }
    }

    private func applyCurrentWiFi() {
        wifiNameDenied = currentWiFi.denied
        guard let name = currentWiFi.ssid else { return }
        if ssid.isEmpty || ssid == detectedSSID {
            ssid = name
        }
        detectedSSID = name
        updateCameraHotspot()
    }

    func acceptNetwork() {
        refreshLAN()
        guard lanAddress != nil, cameraHotspotAddress == nil,
            !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        ssid = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        networkAccepted = true
        startScanning()
    }

    func clearPassword() {
        password = ""
    }

    func startScanning() {
        guard networkAccepted else { return }
        scanTask?.cancel()
        scanTask = Task { @MainActor in
            while !Task.isCancelled, !scanner.isPoweredOn {
                scanNote = scanner.unavailableReason
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            scanNote = discovered.isEmpty ? "Looking for cameras" : "\(discovered.count) nearby"
            let stream = scanner.scan()
            for await camera in stream {
                guard !Task.isCancelled else { return }
                guard camera.appearsInMultiview else { continue }
                if let index = discovered.firstIndex(where: { $0.id == camera.id }) {
                    discovered[index] = camera
                } else {
                    discovered.append(camera)
                }
                scanNote = "\(discovered.count) nearby"
            }
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        scanner.stopScan()
    }

    func add(_ camera: FoundCamera) async {
        guard cameraHotspotAddress == nil else {
            return
        }
        guard camera.hasMultiviewPreview, networkAccepted, !busy, board.adding(camera.id) != nil,
            let tile = tiles.first(where: { $0.camera == nil })
        else { return }
        busy = true
        provisioning = true
        tile.connecting = true
        tile.camera = camera
        tile.failure = nil
        tile.status = "Connecting · approve on camera"
        stopScanning()
        let client = MultiviewProvisioner()
        provisioners[tile.id] = client
        defer {
            provisioning = false
            tile.connecting = false
            provisioners[tile.id] = nil
            busy = false
        }
        do {
            try await client.connect(camera)
            if camera.model.family == .nano {
                tile.status = "Waking camera Wi-Fi"
                guard
                    try await client.exchange(Commands.session5310(id: client.next())).payload == [
                        1, 0, 0, 0,
                    ]
                else {
                    throw MultiviewSession.Failure.rejected
                }
                try await Task.sleep(for: .seconds(1))
            }
            tile.status = "Reading camera identity"
            let identity = try await readIdentity(client, camera: camera, tile: tile)
            tile.identity = identity
            var join = StationJoin(
                model: camera.model, ssid: ssid, password: password, hotspot: false)
            // A camera left on this Wi-Fi by the previous attempt is already in station mode.
            // Probe the LAN before sending another join, which it may not answer.
            join.probeExistingStation = true
            let outcome = try await join.run(
                identity: identity,
                exchange: { try await client.exchange($0, timeout: $1) },
                send: client.send,
                next: client.next,
                status: { tile.status = $0 },
                hotspotReady: { false },
                verifyOnNetwork: {
                    try await self.openVerifiedPreview(tile, camera: camera, identity: identity)
                    return tile.controlHost != nil
                })
            await client.closeAndWait()
            if outcome != .verified {
                try await openVerifiedPreview(tile, camera: camera, identity: identity)
            }
            if tile.controlHost == nil, tile.failure == nil {
                tile.status = "Could not find this camera on Wi-Fi"
                tile.failure =
                    "Check that this Mac and the camera are on \(ssid), and that client isolation is off."
            }
        } catch {
            tile.driver?.close()
            tile.driver = nil
            tile.controlHost = nil
            tile.status = "Could not connect"
            tile.failure = error.localizedDescription
            ControlLiveLog.line("multiview: add failed \(camera.model.name) \(error.localizedDescription)")
        }
        await client.closeAndWait()
        if networkAccepted { startScanning() }
    }

    /// Pocket ignores the first Wi-Fi identity query until a wake. Ask once, wake, ask again.
    /// Accept a `07/07` reply even when its sequence does not echo the request.
    private func readIdentity(
        _ client: MultiviewProvisioner, camera: FoundCamera, tile: MacTile
    ) async throws -> [UInt8] {
        if camera.model.family == .nano {
            return try await client.exchange(Commands.getWifiSsid(id: client.next())).payload
        }
        if let payload = await listenIdentity(client, timeout: 8) { return payload }
        ControlLiveLog.line("multiview: identity reply missing; sending Wi-Fi wake once")
        tile.status = "Waking camera"
        _ = try? await client.exchange(Commands.session5310(id: client.next()), timeout: 2)
        try await Task.sleep(for: .milliseconds(600))
        tile.status = "Reading camera identity"
        if let payload = await listenIdentity(client, timeout: 12) { return payload }
        throw MultiviewSession.Failure.timeout
    }

    private func listenIdentity(_ client: MultiviewProvisioner, timeout: TimeInterval) async -> [UInt8]? {
        pendingIdentity = nil
        let request = Commands.getWifiSsid(id: client.next())
        client.onFrame = { [weak self] frame in
            ControlLiveLog.line(
                "multiview: ble \(String(format: "%02x/%02x", frame.cmdSet, frame.cmdId)) flags=\(frame.flags) seq=\(frame.seq) \(frame.payload.count)B"
            )
            if frame.cmdSet == 0x07, frame.cmdId == 0x07, frame.payload.count > 2 {
                self?.pendingIdentity = frame.payload
            }
        }
        client.send(request)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let pendingIdentity {
                client.onFrame = nil
                return pendingIdentity
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        client.onFrame = nil
        return nil
    }

    func remove(_ tile: MacTile) {
        guard !busy, !tile.connecting, !groupBusy, !tile.recordingBusy else { return }
        tile.clearConnection()
        tile.camera = nil
        tile.failure = nil
        tile.status = "Empty"
    }

    func toggleRecording(_ tile: MacTile) async {
        guard !groupBusy else { return }
        switch MacRecordGate.toggle(tile.recordCamera) {
        case .start: await record(true, tile: tile)
        case .stop: await record(false, tile: tile)
        case .skip, .refuse: break
        }
    }

    func toggleGroupRecording() async {
        let stop = groupStop
        let decision = MacRecordGate.group(assignedRecordCameras, stop: stop)
        guard !decision.refused, !groupBusy else { return }
        groupBusy = true
        groupNote = stop ? "Stopping cameras…" : "Starting cameras…"
        var results: [UUID: MacRecordResult] = [:]
        await withTaskGroup(of: (UUID, MacRecordResult).self) { group in
            for tile in tiles where tile.camera != nil {
                let action = decision.actions[tile.id] ?? .refuse
                switch action {
                case .skip:
                    results[tile.id] = .skipped
                case .start, .stop:
                    group.addTask { @MainActor in
                        let result = await self.record(action == .start, tile: tile)
                        return (tile.id, result)
                    }
                case .refuse:
                    results[tile.id] = .unconfirmed
                }
            }
            for await (id, result) in group {
                results[id] = result
            }
        }
        groupNote = MacGroupRecordReport.make(results, stop: stop).summary
        groupBusy = false
    }

    @discardableResult
    private func record(_ enabled: Bool, tile: MacTile) async -> MacRecordResult {
        guard let driver = tile.driver, tile.controlHost != nil, !tile.recordingBusy else {
            return .unconfirmed
        }
        tile.recordingBusy = true
        defer { tile.recordingBusy = false }
        let sent = Date()
        let sequence = driver.send(enabled ? Commands.recordStart() : Commands.recordStop())
        tile.recordingNote = "Waiting for camera confirmation"
        let deadline = sent.addingTimeInterval(8)
        while Date() < deadline && tile.driver === driver {
            try? await Task.sleep(for: .milliseconds(100))
            if let reply = tile.responses[sequence], reply.cmdSet == 2, reply.cmdId == 2,
                reply.payload != [0]
            {
                tile.recordingNote = "Recording command rejected · check camera"
                return .rejected
            }
            if let recording = tile.recording, let received = tile.recordingAt, received > sent,
                recording == enabled
            {
                tile.recordingNote = enabled ? "Recording" : "Recording stopped"
                return .confirmed
            }
        }
        tile.recordingNote = "No confirmation · check camera"
        return .unconfirmed
    }

    private func openVerifiedPreview(
        _ tile: MacTile, camera: FoundCamera, identity: [UInt8]
    ) async throws {
        if SharedWiFiPath.validAddress(tile.cameraAddress) {
            do {
                try await openPreview(tile, camera: camera, identity: identity)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                tile.driver?.close()
                tile.driver = nil
                tile.controlHost = nil
            }
        }
        let search = MultiviewDiscovery()
        let excluded = Set(tiles.compactMap { $0 === tile ? nil : $0.controlHost })
        for attempt in 1...2 {
            tile.status = "Finding camera on Wi-Fi · \(attempt) of 2"
            let candidates = try await search.candidates(excluding: excluded, hotspot: false)
            for address in candidates {
                tile.cameraAddress = address
                do {
                    try await openPreview(tile, camera: camera, identity: identity)
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    tile.driver?.close()
                    tile.driver = nil
                    tile.controlHost = nil
                }
            }
            if attempt == 1 { try await Task.sleep(for: .seconds(3)) }
        }
    }

    private func openPreview(_ tile: MacTile, camera: FoundCamera, identity: [UInt8]) async throws {
        let address = tile.cameraAddress
        guard SharedWiFiPath.validAddress(address),
            !tiles.contains(where: { $0 !== tile && $0.controlHost == address })
        else { throw MultiviewSession.Failure.unavailable }
        tile.driver?.close()
        tile.responses.removeAll()
        tile.recording = nil
        tile.recordingAt = nil
        tile.decoder.reset()
        tile.status = "Connecting preview"
        let driver = DatalinkDriver(
            port: UInt16(camera.model.datalinkPort), tcpPoke: camera.model.tcpPoke,
            pairingToken: camera.model.pairingToken, stationHost: address, stationHotspot: false,
            subscriptionKeys: Commands.subscriptionKeys(for: camera.model))
        tile.driver = driver
        driver.onVideoDiscontinuity = { [weak tile, weak driver] in
            guard let tile, let driver, tile.driver === driver else { return }
            tile.decoder.noteReferenceLoss()
        }
        driver.onAccessUnit = { [weak self, weak tile, weak driver] unit in
            guard let self, !self.provisioning else { return }
            guard let tile, tile.driver === driver else { return }
            tile.decoder.submit(accessUnit: unit)
        }
        tile.decoder.onPresented = { [weak tile] in
            guard let tile, tile.failure == nil, tile.status != camera.name else { return }
            tile.status = camera.name
        }
        tile.decoder.onNeedsKeyframe = { [weak tile, weak driver] in
            guard let tile, let driver, tile.driver === driver, tile.controlHost != nil else {
                return
            }
            driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
        }
        driver.onStatusFrame = { [weak tile, weak driver] frame in
            guard let tile, let driver, tile.driver === driver else { return }
            if frame.flags & 128 != 0 {
                if tile.responses.count > 128 { tile.responses.removeAll() }
                tile.responses[frame.seq] = frame
            }
            guard tile.controlHost != nil, frame.cmdSet == 2, frame.cmdId == 0x80,
                frame.payload.count >= 13
            else { return }
            var status = CameraStatus()
            CameraStatusDecoder.apply(frame, to: &status, model: camera.model)
            tile.recording = status.isRecording
            tile.recordingAt = Date()
        }
        try await driver.open(identityOnly: true)
        let identitySequence = driver.send(Commands.getWifiSsid(id: 0))
        let deadline = Date().addingTimeInterval(8)
        while tile.responses[identitySequence] == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let reply = tile.responses.removeValue(forKey: identitySequence),
            reply.cmdSet == 7, reply.cmdId == 7, reply.payload == identity
        else {
            driver.close()
            tile.driver = nil
            throw MultiviewSession.Failure.rejected
        }
        driver.completeRegistration()
        tile.controlHost = address
        tile.failure = nil
        if camera.model.usesNanoLiveViewGate {
            driver.send(Commands.nanoLiveViewGate(start: true))
        }
        if camera.model.sendsLiveViewPrepare {
            driver.send(Commands.liveViewPrepare())
        }
        driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
        tile.status = "Waiting for video"
    }
}
