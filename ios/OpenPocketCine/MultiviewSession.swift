import Foundation
import NetworkExtension
import Observation
import OpenPocketViewCore
import UIKit

@MainActor @Observable
final class MultiviewSession {
    @MainActor @Observable final class Tile: Identifiable {
        let id = UUID()
        let decoder = HevcDecoder()
        var liveModel: AppModel?
        var driver: DatalinkDriver? {
            didSet { liveModel?.session.datalink = nil }
        }
        var connecting = false
        var experimentalNetwork = false
        var networkVerified = false
        var cameraAddress = ""
        var identity: [UInt8]?
        var responses: [UInt16: Duml.Frame] = [:]
        var camera: FoundCamera?
        var status = "Add camera"
        var failureMessage: String?
        var recovery = MultiviewRecovery()
        @ObservationIgnored var repairTask: Task<Void, Never>?
        var recovering = false
        var pathLostAt: Date?
        var checkForegroundDecoder = false
        var foregroundRepairAt: Date?
        var settings = CameraStatus()
        @ObservationIgnored var pose = GimbalStickMapping()
        @ObservationIgnored var latestSettings = CameraStatus()
        @ObservationIgnored var settingsPublishedAt = Date.distantPast
        let sampleBus = LiveFrameSampleBus()
        var lutEnabled = false
        var effects = LiveImageEffects()
        var lutCaption = "Auto LUT"

        func updateSettings(_ frame: Duml.Frame) {
            guard let camera else { return }
            let previousFlip = latestSettings.selfieFlip
            CameraStatusDecoder.apply(frame, to: &latestSettings, model: camera.model)
            if frame.cmdSet == 4, frame.cmdId == 5 { pose.applyAttitude(frame.payload) }
            if frame.cmdSet == 4, frame.cmdId == 0x27 {
                _ = pose.noteBodyFace(latestSettings.gimbalFace)
            }
            pose.selfieFlip = latestSettings.selfieFlip?.isOn ?? false
            if liveModel == nil {
                if previousFlip != latestSettings.selfieFlip {
                    decoder.invalidatePictureFlipPresentation()
                }
                decoder.poseViewFlip = pose.poseViewFlip
                decoder.syncPictureFlip()
            }
            let colorChanged = latestSettings.colorMode != settings.colorMode
            if colorChanged || Date().timeIntervalSince(settingsPublishedAt) >= 0.2 {
                if settings != latestSettings { settings = latestSettings }
                settingsPublishedAt = Date()
            }
            if colorChanged && liveModel == nil { updateLUT() }
        }
        func toggleLUT() {
            lutEnabled.toggle()
            updateLUT()
        }
        func updateLUT() {
            if liveModel == nil {
                decoder.poseViewFlip = pose.poseViewFlip
                decoder.assistMirror = false
            }
            var next = LiveImageEffects()
            next.colorMode = settings.colorMode ?? .normal
            let lut = OfficialDJILUT.auto(
                colorMode: settings.colorMode,
                family: camera?.model.family ?? .pocket, cameraName: camera?.model.name)
            lutCaption =
                settings.colorMode == nil
                ? "Waiting for camera color" : "Auto · no conversion needed"
            if let lut {
                lutCaption = "Auto · " + lut.title
                if lutEnabled, let cube = BundledOfficialDJILUT.cube(lut) {
                    let gpu = cube.colorCube
                    next.lutDimension = gpu.size
                    next.lutRGBA = gpu.rgbaComponents.withUnsafeBytes { Data($0) }
                } else if lutEnabled {
                    lutCaption = "LUT unavailable"
                }
            }
            effects = next
            decoder.effects = next
            decoder.adoptIncomingTransfer(settings.monitorTransfer)
            if next.needsGPUFeed { decoder.unlockHardwareDecoder() }
        }

        var timecodeReadout: String? {
            guard let camera, camera.model.family != .nano,
                let timecode = settings.timecode, !timecode.isEmpty
            else { return nil }
            return timecode
        }

        var hasPicture = false
        var publishing = false
        var recordingBusy = false
        var recordingAvailable = false
        var recordingNote: String?
        var controlHost: String?
        var recordingObservation: (active: Bool, received: Date)?
        init() {
            decoder.feedUpscaler = .off
            decoder.onPresentedFrame = { [weak self] in
                self?.liveModel?.session.noteMultiviewFrame()
            }
        }
        var lastEnable = Date.distantPast
        var enableSends = 0
        var pendingAssistHandoff = false
        func recoverAssistHandoff() {
            guard pendingAssistHandoff, let driver, controlHost != nil,
                decoder.isPresentationReady, let camera
            else { return }
            guard
                FeedWatchdog.shouldSendEnableForAssistVTStart(
                    secondsSinceLastEnable: Date().timeIntervalSince(lastEnable),
                    hasPresentedPicture: decoder.lastPresentedAt != nil,
                    liveViewEnableSends: enableSends)
            else { return }
            pendingAssistHandoff = false
            driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
            lastEnable = Date()
            enableSends += 1
            ControlLiveLog.line("multiview: assist VT handoff enable")
        }
        var previewStarted: Date?
        var lastFrame = Date.distantPast
    }
    let tiles = (0..<4).map { _ in Tile() }
    var found: [FoundCamera] = []
    var busy = false
    var ready = false
    var ssid = ""
    var usePhoneHotspot = false
    var password = ""
    var networks: [String] = []
    var networkMessage = "Choose a camera to scan for Wi-Fi."
    var networkScanning = false
    var preparedCamera: UUID?
    var groupRecordingBusy = false
    var groupRecordingNote: String?
    var recordingTiles: [Tile] { tiles.filter { $0.camera != nil } }
    var anyRecording: Bool { recordingTiles.contains { $0.recordingObservation?.active == true } }
    var canRecordTogether: Bool {
        !busy && !groupRecordingBusy && !recordingTiles.isEmpty
            && recordingTiles.allSatisfy { $0.recordingAvailable && !$0.recordingBusy }
    }

    var networkConfigured = false
    var configuringNetwork = false
    var networkSetupError: String?
    var applicationActive = true
    private var foregroundAt = Date.distantPast
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    var host = ""
    var error: String?
    var layout: MultiviewLayout = .centerStage
    var feedAspect: PortraitFeedAspect = .fit16x9
    var focusedIndex = 0
    var closing = false
    var connectingCameras: Bool { tiles.contains { $0.connecting } }
    private var provisioners: [UUID: MultiviewProvisioner] = [:]
    private var searches: [UUID: MultiviewDiscovery] = [:]
    private var connectionTasks: [UUID: Task<Void, Never>] = [:]
    private var hostJoin: Task<Void, Error>?
    private var restoration: Task<Void, Never>?
    private var addressReservations: [String: UUID] = [:]
    private var pendingReset: [MultiviewStageStore.Camera] = []
    private var stationResetTasks: [UUID: Task<Bool, Never>] = [:]
    private let resetCamera: ((MultiviewStageStore.Camera) async -> Bool)?
    private let saveStage: (MultiviewStageStore.Stage?) -> Bool
    private var cleanupJournalWritten = false
    private let ble = BleLink(allowsConcurrentCameras: true)
    private var scanTask: Task<Void, Never>?
    private var router: Task<Void, Never>?
    private var keepalive: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var sequence: UInt16 = 1200
    private var replies: [UInt16: Duml.Frame] = [:]
    private var approved = false
    private var running = false

    init(
        resetCamera: ((MultiviewStageStore.Camera) async -> Bool)? = nil,
        saveStage: @escaping (MultiviewStageStore.Stage?) -> Bool = MultiviewStageStore.save
    ) {
        self.resetCamera = resetCamera
        self.saveStage = saveStage
    }

    private enum ProvisioningFailure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    enum Failure: LocalizedError {
        case timeout, unavailable, rejected, network
        var errorDescription: String? {
            switch self {
            case .timeout: "Camera did not respond. Close other camera apps and try again."
            case .unavailable: "Camera is not nearby. Check that it is powered on."
            case .rejected:
                "Camera could not complete this step. Check the Wi-Fi details and try again."
            case .network: "Join the shared Wi-Fi network on this device first."
            }
        }
    }
    func openLiveView(_ tile: Tile) {
        guard let camera = tile.camera, tile.controlHost != nil, !tile.recovering else { return }
        let model = AppModel()
        model.session = CameraSession(borrowing: tile.decoder)
        model.session.updateMultiview(
            camera: camera, driver: tile.driver, status: tile.latestSettings)
        model.session.adoptMultiviewPose(tile.pose)
        model.frameSamples = tile.sampleBus
        model.assist.lutEnabled = tile.lutEnabled
        tile.liveModel = model
    }
    func closeLiveView() {
        for tile in tiles where tile.liveModel != nil {
            tile.lutEnabled = tile.liveModel?.assist.lutEnabled ?? tile.lutEnabled
            tile.liveModel?.session.releaseMultiview()
            tile.liveModel?.multiviewExit = nil
            tile.liveModel = nil
            tile.decoder.onSourceFrame = nil
            tile.decoder.feedUpscaler = .off
            tile.decoder.effectsProvider = nil
            tile.decoder.transferProvider = nil
            tile.updateLUT()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        host = SharedWiFiPath.address(hotspot: usePhoneHotspot) ?? ""
        UIApplication.shared.isIdleTimerDisabled = true
        ready = !host.isEmpty
        if let saved = MultiviewNetworkStore.load() {
            ssid = saved.ssid
            password = saved.password
            usePhoneHotspot = saved.hotspot ?? false
        }
        restoreStage()
        Task { [weak self] in
            let current = await WiFiJoiner.currentSSID()
            guard let self, self.running, !self.usePhoneHotspot, let current,
                !current.lowercased().hasPrefix("osmo")
            else { return }
            if self.ssid.isEmpty { self.ssid = current }
            if !self.networks.contains(current) { self.networks.append(current) }
        }
        networks = MultiviewNetworkStore.savedNetworks().map(\.ssid)
        scan()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.ready = SharedWiFiPath.address(hotspot: self.usePhoneHotspot) != nil
                for tile in self.tiles {
                    tile.driver?.keepalive()
                    tile.recoverAssistHandoff()
                    tile.recordingAvailable =
                        tile.controlHost != nil
                        && tile.recordingObservation.map {
                            Date().timeIntervalSince($0.received) < 3
                        } == true
                    self.monitorPreview(tile)
                }
            }
        }
    }
    func scan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            guard await ble.waitUntilPoweredOn(), !Task.isCancelled else { return }
            found.removeAll()
            for await camera in ble.scan() {
                guard !Task.isCancelled else { return }
                if !found.contains(where: { $0.id == camera.id }) { found.append(camera) }
            }
        }
    }
    private func next() -> UInt16 {
        sequence &+= 1
        return sequence
    }
    private func exchange(_ frame: Duml.Frame, timeout: TimeInterval = 12) async throws
        -> Duml.Frame
    {
        ControlLiveLog.line(
            "multiview: sending \(String(frame.cmdSet, radix: 16))/\(String(frame.cmdId, radix: 16))"
        )
        try Task.checkCancellation()
        guard running else { throw CancellationError() }
        replies.removeValue(forKey: frame.seq)
        ble.send(frame)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            guard running else { throw CancellationError() }
            if let result = replies.removeValue(forKey: frame.seq), result.cmdSet == frame.cmdSet,
                result.cmdId == frame.cmdId
            {
                ControlLiveLog.line(
                    "multiview: reply \(String(frame.cmdSet, radix: 16))/\(String(frame.cmdId, radix: 16)) bytes=\(result.payload.count)"
                )
                return result
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure.timeout
    }
    private func connect(_ camera: FoundCamera) async throws {
        guard running else { throw CancellationError() }
        try await ble.connect(camera)
        try Task.checkCancellation()
        guard running else { throw CancellationError() }
        scanTask?.cancel()
        ble.stopScan()
        replies.removeAll()
        approved = false
        let frames = ble.frames
        router = Task { [weak self] in
            for await frame in frames {
                guard let self, !Task.isCancelled else { return }
                if frame.cmdSet == 7 && frame.cmdId == 0xac && frame.sender == 7 {
                    for name in MulticamWiFiScan.names(frame.payload) where !networks.contains(name)
                    {
                        networks.append(name)
                    }
                    networks.sort { $0.localizedStandardCompare($1) == .orderedAscending }
                }
                if frame.cmdSet == 2 && frame.cmdId == 0x80 && frame.payload.count >= 13,
                    let tile = tiles.first(where: { $0.camera?.id == camera.id })
                {
                    var status = CameraStatus()
                    CameraStatusDecoder.apply(frame, to: &status, model: camera.model)
                    tile.recordingObservation = (status.isRecording, Date())
                }
                if frame.cmdSet == 7 && frame.cmdId == 0x46 && frame.flags & 128 == 0 {
                    ble.send(Commands.pairApprovalAck(seq: frame.seq))
                    approved = true
                } else if frame.flags & 128 != 0 {
                    if replies.count > 128 { replies.removeAll() }
                    replies[frame.seq] = frame
                }
            }
        }
        ble.send(Commands.sessionWake(id: next()))
        let pair = Commands.setPairingPin(pin: camera.model.pairingToken, id: next())
        ble.send(pair)
        let deadline = Date().addingTimeInterval(90)
        while !approved && Date() < deadline {
            try Task.checkCancellation()
            guard running else { throw CancellationError() }
            if let response = replies.removeValue(forKey: pair.seq) {
                if response.payload == [0, 1] {
                    approved = true
                } else if response.payload != [0, 2] {
                    throw Failure.rejected
                }
            }
            if !approved { try await Task.sleep(for: .milliseconds(100)) }
        }
        guard approved else { throw Failure.timeout }
        keepalive = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                ble.send(Commands.sessionKeepalive(id: next()))
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    private func disconnectBLE() {
        keepalive?.cancel()
        keepalive = nil
        router?.cancel()
        router = nil
        ble.disconnect()
        replies.removeAll()
        preparedCamera = nil
    }

    func prepareNetworks(_ camera: FoundCamera) async {
        guard camera.hasMultiviewPreview, !busy, running, !closing else { return }
        busy = true
        networkScanning = true
        networkMessage = "Connecting · approve on camera if asked"
        defer {
            busy = false
            networkScanning = false
        }
        do {
            if preparedCamera != camera.id {
                disconnectBLE()
                try await connect(camera)
                preparedCamera = camera.id
                if camera.model.family == .nano {
                    _ = try await exchange(Commands.session5310(id: next()))
                }
            }
            networkMessage = "Preparing camera Wi-Fi"
            // A lost setter reply can still mean the camera changed roles.
            guard recordStationChange(camera) else {
                throw ProvisioningFailure.message("Could not save camera Wi-Fi cleanup. Try again.")
            }
            let role = try await exchange(MulticamCommands.stationMode(true, seq: next()))
            guard role.payload.first == 0 else { throw Failure.rejected }
            try await Task.sleep(for: .seconds(10))
            networkMessage = "Looking for Wi-Fi networks"
            _ = try await exchange(MulticamWiFiScan.request(seq: next()), timeout: 8)
            try await Task.sleep(for: .seconds(6))
            networkMessage =
                networks.isEmpty
                ? "No networks found. Retry the scan or enter a hidden network."
                : "Choose the same Wi-Fi for this device and your cameras."
        } catch {
            networkMessage = "Could not scan. Retry or enter your network name."
        }
        disconnectBLE()
        if let saved = pendingReset.first(where: { $0.id == camera.id }) {
            let scanMessage = networkMessage
            networkMessage = "Returning camera to its Wi-Fi"
            if !(await resetStationOnce(saved)) {
                networkSetupError = "Camera Wi-Fi could not be restored. Keep it powered on and close Multiview to retry."
            }
            networkMessage = scanMessage
        }
        if running, !closing { scan() }
    }

    @discardableResult func recordStationChange(_ camera: FoundCamera) -> Bool {
        let saved = MultiviewStageStore.Camera(
            slot: 0, id: camera.id, name: camera.name, modelId: camera.modelId,
            identity: nil, address: "", experimental: false, lutEnabled: false)
        pendingReset = MultiviewStageStore.cleanupTargets(pendingReset, including: [saved])
        return persistStage()
    }

    /// The setup view cancels its task first; disconnect also unblocks BLE's
    /// connection continuation, which cannot observe task cancellation itself.
    func cancelNetworkScan() {
        guard networkScanning else { return }
        disconnectBLE()
    }

    func releaseNetworkCamera() {
        guard !busy else { return }
        disconnectBLE()
        if running { scan() }
    }

    func selectNetworkSource(hotspot: Bool) {
        guard !tiles.contains(where: { $0.camera != nil }) else { return }
        usePhoneHotspot = hotspot
        let saved = MultiviewNetworkStore.load()
        if (saved?.hotspot ?? false) == hotspot {
            ssid = saved?.ssid ?? ""
            password = saved?.password ?? ""
        } else {
            ssid = ""
            password = ""
        }
    }

    func selectNetwork(_ name: String) {
        if ssid != name {
            ssid = name
            password =
                MultiviewNetworkStore.load(ssid: name, hotspot: usePhoneHotspot)?.password ?? ""
        }
    }

    func joinSharedNetwork() async throws {
        if let hostJoin { return try await hostJoin.value }
        let task = Task { try await self.performHostJoin() }
        hostJoin = task
        defer { hostJoin = nil }
        try await task.value
        try Task.checkCancellation()
        guard running else { throw CancellationError() }
    }
    private func performHostJoin() async throws {
        guard !ssid.isEmpty else { throw Failure.network }
        // The host phone must not try joining its own hotspot. Its local bridge
        // may appear only after the first camera associates.
        if usePhoneHotspot { return }
        if await WiFiJoiner.currentSSID() != ssid {
            let config =
                password.isEmpty
                ? NEHotspotConfiguration(ssid: ssid)
                : NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
            config.joinOnce = false
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                NEHotspotConfigurationManager.shared.apply(config) { error in
                    if let error,
                        (error as NSError).code
                            != NEHotspotConfigurationError.alreadyAssociated.rawValue
                    {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if await WiFiJoiner.currentSSID() == ssid, SharedWiFiPath.address() != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard await WiFiJoiner.currentSSID() == ssid,
            let address = SharedWiFiPath.address(hotspot: usePhoneHotspot)
        else {
            throw Failure.network
        }
        host = address
        ready = true
    }

    func configureNetwork() async -> Bool {
        guard !busy, !configuringNetwork else { return false }
        configuringNetwork = true
        networkSetupError = nil
        defer { configuringNetwork = false }
        do {
            _ = try MulticamCommands.join(ssid: ssid, password: password, seq: 0)
            try await joinSharedNetwork()
            MultiviewNetworkStore.save(ssid: ssid, password: password, hotspot: usePhoneHotspot)
            networkConfigured = true
            persistStage()
            return true
        } catch {
            networkSetupError = error.localizedDescription
            return false
        }
    }

    func setApplicationActive(_ active: Bool) {
        applicationActive = active
        if active {
            foregroundAt = Date()
            for tile in tiles where tile.publishing { tile.checkForegroundDecoder = true }
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        } else if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(
                withName: "Multiview transition"
            ) { [weak self] in
                guard let self else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
                // Keep camera assignments and sockets. Foreground watchdog owns repair.
            }
        }
    }

    func reconnect(_ tile: Tile) async {
        guard !busy, !tile.connecting, !tile.recovering, let camera = tile.camera else { return }
        tile.failureMessage = nil
        tile.recovery = MultiviewRecovery()
        if tile.identity != nil {
            await connectPreview(tile)
            if running, !Task.isCancelled, tile.failureMessage != nil { await readd(tile) }
        } else {
            tile.camera = nil
            await add(camera, to: tile, experimental: tile.experimentalNetwork)
        }
    }

    private func readd(_ tile: Tile) async {
        guard let camera = tile.camera else { return }
        let experimental = tile.experimentalNetwork
        let lutEnabled = tile.lutEnabled
        guard await remove(tile) else { return }
        tile.lutEnabled = lutEnabled
        await add(camera, to: tile, experimental: experimental)
    }

    func tryExperimentalNetwork(_ tile: Tile) async {
        guard let camera = tile.camera, await remove(tile) else { return }
        await add(camera, to: tile, experimental: true)
    }

    private func monitorPreview(_ tile: Tile) {
        guard applicationActive, Date().timeIntervalSince(foregroundAt) > 3,
            !busy, !tile.recovering, !tile.recovery.failed,
            tile.publishing, let driver = tile.driver
        else { return }
        let now = Date()
        let age: (Date?) -> TimeInterval? = { $0.map { now.timeIntervalSince($0) } }
        let snapshot = FeedWatchdog.Snapshot(
            now: now.timeIntervalSinceReferenceDate,
            lastDecodedFrameAge: age(tile.decoder.lastPresentedAt),
            lastVideoPacketAge: age(driver.lastVideoPacketAt),
            lastAccessUnitAge: age(driver.lastAccessUnitAt),
            lastStatusAge: age(driver.lastStatusAt), flowHealthy: driver.isFlowHealthy,
            pathReady: SharedWiFiPath.address(hotspot: usePhoneHotspot) != nil,
            hasFormat: tile.decoder.hasFormat,
            decoderFailed: tile.decoder.isDecoderWedged
                || tile.decoder.displayLayer.status == .failed,
            live: true, sawPicture: tile.hasPicture, tcpPokeReady: driver.isTcpPokeReady,
            secondsSinceLastRebuild: driver.secondsSinceLastRebuild,
            hadVideo: driver.videoPackets > 0,
            secondsSinceLastEnable: now.timeIntervalSince(tile.lastEnable),
            secondsSinceCameraSet: driver.secondsSinceLastCommand)
        if snapshot.pathReady {
            tile.pathLostAt = nil
        } else if tile.pathLostAt == nil {
            tile.pathLostAt = now
        }
        if tile.checkForegroundDecoder && FeedWatchdog.udpReceiveAlive(snapshot) {
            tile.checkForegroundDecoder = false
            if snapshot.decoderFailed || tile.decoder.displayLayer.requiresFlushToResumeDecoding
                || (FeedWatchdog.udpReceiveAlive(snapshot) && tile.decoder.isPresentFrozen)
            {
                tile.decoder.prepareAfterForeground()
                tile.pendingAssistHandoff = true
                tile.recoverAssistHandoff()
                tile.foregroundRepairAt = now
                ControlLiveLog.line("multiview: foreground decoder repair, socket retained")
                return
            }
        }
        var foregroundRejoin = false
        if let repaired = tile.foregroundRepairAt, now.timeIntervalSince(repaired) > 12 {
            tile.foregroundRepairAt = nil
            if tile.decoder.isPresentFrozen && FeedWatchdog.udpReceiveAlive(snapshot) {
                foregroundRejoin = true
            }
        }
        let action: FeedWatchdog.Action = foregroundRejoin ? .fullSessionRejoin : tile.recovery.action(snapshot)
        if tile.decoder.awaitingIDR,
            FeedWatchdog.shouldReleaseIDRHold(
                awaitingIDR: true, udpReceiveAlive: FeedWatchdog.udpReceiveAlive(snapshot),
                secondsSinceLastEnable: snapshot.secondsSinceLastEnable,
                hasPresentedPicture: tile.decoder.lastPresentedAt != nil)
        {
            tile.decoder.endIDRHold()
        }
        guard action != .none else {
            if !snapshot.pathReady, now.timeIntervalSince(tile.pathLostAt ?? now) > 45 {
                tile.recovery.fail()
                tile.failureMessage =
                    "Shared network unavailable. Rejoin it, then reconnect this camera."
            }
            return
        }
        ControlLiveLog.line("multiview: repair action=\(action)")
        tile.status = "Reconnecting…"
        if action == .resendLiveViewEnable {
            guard tile.decoder.isPresentationReady, let camera = tile.camera else { return }
            driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
            tile.lastEnable = now
            tile.enableSends += 1
            tile.decoder.beginIDRHold()
            return
        }
        tile.recovering = true
        tile.repairTask = Task { [weak self, weak tile] in
            guard let self, let tile else { return }
            defer {
                tile.recovering = false
                tile.repairTask = nil
            }
            if action == .fullSessionRejoin {
                await rejoinWhenAvailable(tile)
            } else {
                do {
                    try await driver.rebuildUDP(reason: "multiview watchdog")
                    guard running, tile.driver === driver, !Task.isCancelled,
                        let camera = tile.camera
                    else { return }
                    driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
                    tile.lastEnable = Date()
                    tile.enableSends += 1
                    tile.decoder.beginIDRHold()
                } catch {
                    guard running, !Task.isCancelled else { return }
                    await rejoinWhenAvailable(tile)
                }
            }
        }
    }

    private func rejoinWhenAvailable(_ tile: Tile) async {
        // One discovery owner; waiting tiles do not spend their retry budget.
        while busy && running && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard running, !Task.isCancelled, tile.camera != nil else { return }
        guard tile.recovery.beginRejoin() else {
            tile.failureMessage = "Could not restore preview. Tap Reconnect to try again."
            return
        }
        await connectPreview(tile)
    }

    func toggleAllRecording() async {
        guard canRecordTogether else { return }
        let stop = anyRecording
        let targets = recordingTiles.filter { $0.recordingObservation?.active != !stop }
        groupRecordingBusy = true
        groupRecordingNote = stop ? "Stopping cameras…" : "Starting cameras…"
        await withTaskGroup(of: Void.self) { group in
            for tile in targets {
                group.addTask { @MainActor in await self.recording(!stop, tile: tile) }
            }
        }
        let confirmed = targets.filter {
            $0.recordingNote == (stop ? "Recording stopped" : "Recording")
        }.count
        let allMatch = recordingTiles.allSatisfy {
            $0.recordingAvailable && $0.recordingObservation?.active == !stop
        }
        groupRecordingNote =
            confirmed == targets.count && allMatch
            ? (stop ? "Recording stopped" : "Recording on \(confirmed) cameras")
            : "\(confirmed) of \(targets.count) confirmed · check camera tiles"
        groupRecordingBusy = false
    }

    func add(_ camera: FoundCamera, to tile: Tile, experimental: Bool = false) async {
        guard camera.appearsInMultiview, camera.hasMultiviewPreview || experimental else {
            error = "Multiview preview is not available for this camera model yet."
            return
        }
        guard running, !closing, !busy, !tile.connecting, tile.camera == nil,
            !tiles.contains(where: { $0.camera?.id == camera.id })
        else { return }
        tile.connecting = true
        let client = MultiviewProvisioner()
        provisioners[tile.id] = client
        tile.camera = camera
        tile.experimentalNetwork = experimental
        tile.networkVerified = false
        tile.status = "Connecting · approve on camera"
        defer {
            tile.connecting = false
            client.close()
            provisioners.removeValue(forKey: tile.id)
            if running { persistStage() }
        }
        persistStage()
        var stage = "host Wi-Fi"
        do {
            try await joinSharedNetwork()
            stage = "Bluetooth pairing"
            try await client.connect(camera)
            if camera.model.family == .nano {
                tile.status = "Waking camera Wi-Fi"
                guard
                    try await client.exchange(Commands.session5310(id: client.next())).payload == [
                        1, 0, 0, 0,
                    ]
                else {
                    throw ProvisioningFailure.message(
                        "The Nano did not confirm its Wi-Fi wake. Keep it powered on and try again."
                    )
                }
                try await Task.sleep(for: .seconds(1))
            }
            stage = "camera Wi-Fi identity"
            let identity = try await client.exchange(Commands.getWifiSsid(id: client.next()))
                .payload
            guard identity.count > 2, identity[0] == 0 else { throw Failure.rejected }
            if camera.hasMultiviewPreview && !experimental {
                tile.status = "Selecting Video mode"
                client.send(MulticamCommands.videoMode(seq: client.next()))
                try await Task.sleep(for: .seconds(2))
            }
            stage = "station role"

            let role = try await client.exchange(MulticamCommands.wifiWorkMode(seq: client.next()))
                .payload
            let decision = MulticamStationPolicy.decision(
                reply: role,
                allowMissingQuery: experimental || camera.acceptsMissingMultiviewRoleQuery(role))
            let missingRoleQuery = decision == .setWithoutReadback
            ControlLiveLog.line(
                "multiview: station experimental=\(experimental) decision=\(decision)")
            if decision != .alreadyStation {
                guard decision != .reject else {
                    throw ProvisioningFailure.message(
                        "This camera did not report a supported Wi-Fi mode. Shared Wi-Fi setup is experimental for this model."
                    )
                }
                let switched = try await client.exchange(
                    MulticamCommands.stationMode(true, seq: client.next())
                )
                .payload
                let accepted = MulticamStationPolicy.acceptsSetter(
                    switched, missingQuery: missingRoleQuery)
                guard accepted else {
                    throw ProvisioningFailure.message(
                        "The camera did not accept shared Wi-Fi mode.")
                }
                // The bounded experimental path also permits the captured missing-getter shape.
                // Its join result and subsequent LAN identity check remain required.
                if !missingRoleQuery {
                    var stationReady = false
                    for _ in 0..<6 {
                        let reported = try await client.exchange(
                            MulticamCommands.wifiWorkMode(seq: client.next())
                        ).payload
                        if reported == [0, 1] {
                            stationReady = true
                            break
                        }
                        guard reported == [0, 0] else { throw Failure.rejected }
                        try await Task.sleep(for: .seconds(2))
                    }
                    guard stationReady else {
                        throw ProvisioningFailure.message(
                            "Camera Wi-Fi is still starting. Retry with the camera nearby.")
                    }
                }
            }
            tile.identity = identity
            stage = "camera Wi-Fi join"
            tile.status = "Waiting for camera Wi-Fi"
            try await Task.sleep(for: .seconds(MulticamJoinPolicy.prepareSettleSeconds))
            for attempt in 1...MulticamJoinPolicy.maximumAttempts {
                tile.status =
                    "Joining Wi-Fi · attempt \(attempt) of \(MulticamJoinPolicy.maximumAttempts)"
                let joined: Duml.Frame
                do {
                    joined = try await client.exchange(
                        MulticamCommands.join(ssid: ssid, password: password, seq: client.next()),
                        timeout: MulticamJoinPolicy.replyTimeoutSeconds)
                } catch {
                    if error is CancellationError { throw error }
                    ControlLiveLog.line(
                        "multiview: join reply timeout; checking verified LAN identity")
                    // A lost BLE reply is not proof that association failed.
                    if !usePhoneHotspot || SharedWiFiPath.address(hotspot: true) != nil {
                        do {
                            try await discoverPreview(tile, camera: camera, identity: identity)
                            MultiviewNetworkStore.save(
                                ssid: ssid, password: password, hotspot: usePhoneHotspot)
                            return
                        } catch { if error is CancellationError { throw error } }
                    }
                    if attempt < MulticamJoinPolicy.maximumAttempts {
                        try await Task.sleep(for: .seconds(MulticamJoinPolicy.retryDelaySeconds))
                        continue
                    }
                    tile.identity = nil
                    throw ProvisioningFailure.message(
                        "Camera Wi-Fi did not respond. Retry setup with the camera nearby.")
                }
                // Only the fixed-size result is logged, never the credential request.
                let result = joined.payload.prefix(4).map { String(format: "%02x", $0) }.joined(
                    separator: " ")
                ControlLiveLog.line("multiview: Wi-Fi join attempt=\(attempt) result=\(result)")
                switch MulticamJoinPolicy.decision(reply: joined.payload, attempt: attempt) {
                case .connected: break
                case .retry:
                    tile.status = "Retrying Wi-Fi connection"
                    try await Task.sleep(for: .seconds(MulticamJoinPolicy.retryDelaySeconds))
                    continue
                case .rejected:
                    tile.identity = nil
                    throw ProvisioningFailure.message(
                        "The camera could not join the shared Wi-Fi. Check its name and password, and make sure the network is in range."
                    )
                }
                break
            }
            tile.identity = identity
            if usePhoneHotspot {
                tile.status = "Waiting for Personal Hotspot"
                let deadline = Date().addingTimeInterval(15)
                while SharedWiFiPath.address(hotspot: true) == nil && Date() < deadline {
                    try await Task.sleep(for: .milliseconds(250))
                }
                guard SharedWiFiPath.address(hotspot: true) != nil else {
                    throw ProvisioningFailure.message(
                        "Enable Personal Hotspot and Allow Others to Join, then retry. The hotspot network is not available yet."
                    )
                }
            }
            MultiviewNetworkStore.save(ssid: ssid, password: password, hotspot: usePhoneHotspot)
            tile.identity = identity
            client.close()
            stage = "LAN discovery"
            try await discoverPreview(tile, camera: camera, identity: identity)
        } catch {
            guard running, !Task.isCancelled else { return }
            tile.driver?.close()
            tile.driver = nil
            tile.status = "Could not connect"
            tile.failureMessage = error.localizedDescription
            ControlLiveLog.line(
                "multiview: add failed stage=\(stage) error=\((error as NSError).domain)/\((error as NSError).code)"
            )
            // Keep the tile available for discovery retry after a successful join.
        }
    }
    func connectPreview(_ tile: Tile) async {
        guard running, !closing, !busy, !tile.connecting, let camera = tile.camera,
            let identity = tile.identity
        else { return }
        tile.connecting = true
        defer {
            tile.connecting = false
            if running { persistStage() }
        }
        do { try await discoverPreview(tile, camera: camera, identity: identity) } catch {
            guard running, !Task.isCancelled else { return }
            tile.driver?.close()
            tile.driver = nil
            tile.publishing = false
            tile.controlHost = nil
            tile.status = "Could not connect preview"
            tile.failureMessage = "Could not restore preview. Tap Reconnect to try again."
            tile.recovery.fail()
        }
    }

    private func discoverPreview(_ tile: Tile, camera: FoundCamera, identity: [UInt8]) async throws
    {
        let search = MultiviewDiscovery()
        searches[tile.id] = search
        defer {
            search.cancel()
            searches.removeValue(forKey: tile.id)
        }
        tile.driver?.close()
        tile.driver = nil
        tile.controlHost = nil
        tile.recordingAvailable = false
        let excluded = Set(tiles.filter { $0.id != tile.id }.compactMap(\.controlHost))
        if SharedWiFiPath.validAddress(tile.cameraAddress) {
            do {
                try await openPreview(tile, camera: camera, identity: identity)
                return
            } catch { if error is CancellationError { throw error } }
        }
        for attempt in 1...2 {
            guard running else { throw CancellationError() }
            tile.status = "Finding camera on Wi-Fi · \(attempt) of 2"
            let candidates = try await search.candidates(
                excluding: excluded, hotspot: usePhoneHotspot)
            for address in candidates {
                guard running else { throw CancellationError() }
                tile.cameraAddress = address
                do {
                    try await openPreview(tile, camera: camera, identity: identity)
                    return
                } catch {
                    tile.driver?.close()
                    tile.driver = nil
                    tile.controlHost = nil
                    if error is CancellationError { throw error }
                }
            }
            if attempt == 1 { try await Task.sleep(for: .seconds(3)) }
        }
        throw ProvisioningFailure.message(
            "Could not find this camera on the shared Wi-Fi. Check that both devices use the same network and that client isolation is off, then tap Reconnect."
        )
    }

    private func openPreview(_ tile: Tile, camera: FoundCamera, identity: [UInt8]) async throws {
        let address = tile.cameraAddress
        guard addressReservations[address] == nil || addressReservations[address] == tile.id else {
            throw Failure.unavailable
        }
        addressReservations[address] = tile.id
        defer {
            if addressReservations[address] == tile.id {
                addressReservations.removeValue(forKey: address)
            }
        }
        guard running, SharedWiFiPath.validAddress(tile.cameraAddress),
            !tiles.contains(where: { $0.id != tile.id && $0.controlHost == tile.cameraAddress })
        else {
            throw ProvisioningFailure.message(
                "Camera discovery returned an unavailable address. Tap Reconnect to search again.")
        }
        tile.driver?.close()
        tile.driver = nil
        tile.controlHost = nil
        tile.responses.removeAll()
        tile.recordingObservation = nil
        tile.recordingAvailable = false
        tile.publishing = false
        tile.previewStarted = nil
        tile.decoder.onHandoffNeedsIDR = nil
        tile.pendingAssistHandoff = false
        tile.enableSends = 0
        tile.lastEnable = .distantPast
        if tile.hasPicture { tile.decoder.beginIDRHold() } else { tile.decoder.reset() }
        tile.status = "Connecting normal preview"
        let driver = DatalinkDriver(
            port: UInt16(camera.model.datalinkPort), tcpPoke: camera.model.tcpPoke,
            pairingToken: camera.model.pairingToken,
            stationHost: tile.cameraAddress, stationHotspot: usePhoneHotspot)
        tile.driver = driver
        driver.onStatusFrame = { [weak tile, weak driver] frame in
            guard let tile, let driver, tile.driver === driver else { return }
            if frame.flags & 128 != 0 {
                if tile.responses.count > 128 { tile.responses.removeAll() }
                tile.responses[frame.seq] = frame
            }
            guard tile.controlHost != nil else { return }
            tile.updateSettings(frame)
            tile.liveModel?.session.receiveMultiview(frame)
            if frame.cmdSet == 2 && frame.cmdId == 0x80 && frame.payload.count >= 13 {
                var status = CameraStatus()
                CameraStatusDecoder.apply(frame, to: &status, model: camera.model)
                tile.recordingObservation = (status.isRecording, Date())
            }
        }
        try await driver.open(identityOnly: true)
        let identitySeq = driver.send(Commands.getWifiSsid(id: 0))
        let deadline = Date().addingTimeInterval(8)
        while tile.responses[identitySeq] == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let reply = tile.responses.removeValue(forKey: identitySeq),
            reply.cmdSet == 7, reply.cmdId == 7, reply.payload == identity
        else {
            throw ProvisioningFailure.message(
                "This network connection did not identify the selected camera."
            )
        }
        guard running else { throw CancellationError() }
        tile.networkVerified = true
        if !camera.hasMultiviewPreview {
            driver.close()
            tile.driver = nil
            tile.failureMessage = nil
            tile.status = "Wi-Fi join verified · Preview not supported yet"
            ControlLiveLog.line(
                "multiview: experimental LAN identity verified; preview unavailable")
            return
        }
        driver.completeRegistration()
        tile.controlHost = tile.cameraAddress
        tile.liveModel?.session.updateMultiview(
            camera: camera, driver: driver, status: tile.latestSettings)
        tile.failureMessage = nil
        ControlLiveLog.line("multiview: station camera identity verified")
        tile.decoder.onHandoffNeedsIDR = { [weak tile, weak driver] in
            guard let tile, let driver, tile.driver === driver, tile.controlHost != nil else {
                return
            }
            tile.pendingAssistHandoff = true
            tile.recoverAssistHandoff()
        }
        driver.onAccessUnit = { [weak tile, weak driver] bytes in
            guard let tile, let driver, tile.driver === driver else { return }
            if tile.decoder.decode(accessUnit: bytes) {
                if !tile.hasPicture { ControlLiveLog.line("multiview: station preview enqueued") }
                tile.lastFrame = Date()
                tile.hasPicture = true
                tile.status = "Live · Video mode"
            }
        }
        let nanoGate = camera.model.usesNanoLiveViewGate
        if nanoGate { driver.send(Commands.nanoLiveViewGate(start: true)) }
        if CameraSoftAP.shouldSendLiveViewPrepare(usesNanoLiveViewGate: nanoGate) {
            driver.send(Commands.liveViewPrepare())
        }
        driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
        tile.lastEnable = Date()
        tile.enableSends = 1
        tile.publishing = true
        tile.previewStarted = Date()
        if !tile.hasPicture { tile.status = "Waiting for video" }
    }

    func toggleRecording(_ tile: Tile) async {
        guard !groupRecordingBusy, let observation = tile.recordingObservation,
            Date().timeIntervalSince(observation.received) < 3
        else { return }
        await recording(!observation.active, tile: tile)
    }

    /// Commands share the tile's existing UDP session; opening another would replace preview.
    func recording(_ enabled: Bool, tile: Tile) async {
        guard running, !tile.recordingBusy, let driver = tile.driver, tile.controlHost != nil else {
            return
        }
        tile.recordingBusy = true
        defer { tile.recordingBusy = false }
        let sent = Date()
        let seq = driver.send(enabled ? Commands.recordStart() : Commands.recordStop())
        tile.recordingNote = "Waiting for camera confirmation"
        do {
            let deadline = sent.addingTimeInterval(8)
            while running && tile.driver === driver && Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
                if let reply = tile.responses[seq], reply.cmdSet == 2, reply.cmdId == 2,
                    reply.payload != [0]
                {
                    tile.recordingNote = "Recording command rejected · check camera"
                    return
                }
                if let observation = tile.recordingObservation,
                    observation.received > sent, observation.active == enabled
                {
                    ControlLiveLog.line("multiview: station recording confirmed active=\(enabled)")
                    tile.recordingNote = enabled ? "Recording" : "Recording stopped"
                    return
                }
            }
        } catch {}
        tile.recordingNote = "No confirmation · check camera"
    }

    func remove(_ tile: Tile) async -> Bool {
        guard !busy, !tile.connecting, !groupRecordingBusy, !tile.recordingBusy else {
            return false
        }
        tile.repairTask?.cancel()
        tile.repairTask = nil
        tile.recovering = false
        tile.recovery = MultiviewRecovery()
        tile.pathLostAt = nil
        tile.foregroundRepairAt = nil
        tile.failureMessage = nil
        tile.driver?.close()
        tile.driver = nil
        tile.camera = nil
        tile.networkVerified = false
        tile.experimentalNetwork = false
        tile.settings = CameraStatus()
        tile.latestSettings = CameraStatus()
        tile.pose = GimbalStickMapping()
        tile.lutEnabled = false
        tile.updateLUT()
        tile.previewStarted = nil
        tile.identity = nil
        tile.controlHost = nil
        tile.recordingObservation = nil
        tile.recordingAvailable = false
        tile.responses.removeAll()
        tile.recordingNote = nil
        tile.hasPicture = false
        tile.publishing = false
        tile.decoder.onHandoffNeedsIDR = nil
        tile.pendingAssistHandoff = false
        tile.enableSends = 0
        tile.lastEnable = .distantPast
        tile.decoder.reset()
        tile.status = "Add camera"
        persistStage()
        return true
    }
    func stop() {
        persistStage()
        restoration?.cancel()
        hostJoin?.cancel()
        hostJoin = nil
        for task in connectionTasks.values { task.cancel() }
        connectionTasks.removeAll()
        for client in provisioners.values { client.close() }
        provisioners.removeAll()
        closeLiveView()
        running = false
        setApplicationActive(true)
        for search in searches.values { search.cancel() }
        searches.removeAll()
        monitor?.cancel()
        scanTask?.cancel()
        ble.stopScan()
        disconnectBLE()
        ready = false
        password = ""
        for tile in tiles {
            tile.repairTask?.cancel()
            tile.driver?.close()
            tile.driver = nil
            tile.decoder.reset()
        }
        UIApplication.shared.isIdleTimerDisabled = false
    }
    private func savedCameras() -> [MultiviewStageStore.Camera] {
        tiles.enumerated().compactMap { index, tile in
            guard let camera = tile.camera else { return nil }
            return .init(
                slot: index, id: camera.id, name: camera.name, modelId: camera.modelId,
                identity: tile.identity, address: tile.cameraAddress,
                experimental: tile.experimentalNetwork, lutEnabled: tile.lutEnabled)
        }
    }
    @discardableResult func persistStage() -> Bool {
        if !networkConfigured, pendingReset.isEmpty {
            guard cleanupJournalWritten else { return true }
            let success = saveStage(nil)
            if success { cleanupJournalWritten = false }
            return success
        }
        let saved = savedCameras()
        let success = saveStage(
            .init(
                ssid: networkConfigured ? ssid : "", hotspot: usePhoneHotspot,
                layout: layout.rawValue, focusedIndex: focusedIndex, cameras: saved,
                pendingReset: running && !closing
                    ? MultiviewStageStore.cleanupTargets(pendingReset, including: saved) : pendingReset,
                returnedToCameraWiFi: !running && pendingReset.isEmpty,
                fill: feedAspect == .fill))
        if !success { ControlLiveLog.line("multiview: could not save stage") }
        if success, !networkConfigured { cleanupJournalWritten = true }
        return success
    }
    private func restoredCamera(_ saved: MultiviewStageStore.Camera) -> FoundCamera {
        FoundCamera(
            id: saved.id, name: saved.name,
            model: .resolve(modelId: saved.modelId, name: saved.name), modelId: saved.modelId)
    }
    func restoreStage(_ savedStage: MultiviewStageStore.Stage? = MultiviewStageStore.load()) {
        guard let stage = savedStage else { return }
        pendingReset = stage.pendingReset ?? []
        if !stage.ssid.isEmpty,
            let network = MultiviewNetworkStore.load(ssid: stage.ssid, hotspot: stage.hotspot) {
            ssid = network.ssid
            password = network.password
            usePhoneHotspot = stage.hotspot
            networkConfigured = true
        }
        cleanupJournalWritten = !networkConfigured
        layout = MultiviewLayout(rawValue: stage.layout) ?? .centerStage
        feedAspect = stage.fill == true ? .fill : .fit16x9
        focusedIndex = stage.focusedIndex
        for saved in stage.cameras where networkConfigured {
            let tile = tiles[saved.slot]
            let camera = restoredCamera(saved)
            guard camera.appearsInMultiview else { continue }
            tile.camera = camera
            tile.identity = saved.identity
            tile.cameraAddress = saved.address
            tile.experimentalNetwork = saved.experimental
            tile.lutEnabled = saved.lutEnabled
            tile.status = "Reconnecting saved camera"
        }
        busy = !pendingReset.isEmpty
        restoration = Task { [weak self] in
            guard let self else { return }
            if !pendingReset.isEmpty {
                await resetStations(pendingReset)
                busy = false
                guard running, !Task.isCancelled else { return }
                persistStage()
            }
            let needsProvisioning =
                stage.returnedToCameraWiFi == true || !(stage.pendingReset ?? []).isEmpty
            for tile in tiles where tile.camera != nil {
                connectionTasks[tile.id] = Task {
                    await self.restoreConnection(tile, needsProvisioning: needsProvisioning)
                }
            }
        }
    }
    private func restoreConnection(_ tile: Tile, needsProvisioning: Bool) async {
        guard running, let camera = tile.camera else { return }
        tile.connecting = true
        do {
            try await joinSharedNetwork()
            if !needsProvisioning, let identity = tile.identity {
                try await discoverPreview(tile, camera: camera, identity: identity)
                tile.connecting = false
                persistStage()
                return
            }
        } catch {
            guard running, !Task.isCancelled else {
                tile.connecting = false
                return
            }
            tile.driver?.close()
            tile.driver = nil
        }
        guard running, !Task.isCancelled else {
            tile.connecting = false
            return
        }
        tile.connecting = false
        tile.camera = nil
        await add(camera, to: tile, experimental: tile.experimentalNetwork)
    }
    func enqueueAdd(_ camera: FoundCamera, to tile: Tile, experimental: Bool = false) {
        guard running, !closing, tile.camera == nil, !tile.connecting else { return }
        connectionTasks[tile.id]?.cancel()
        connectionTasks[tile.id] = Task {
            await self.add(camera, to: tile, experimental: experimental)
        }
    }
    /// Close every camera's monitor first, then restore its own access point in parallel.
    /// A force quit cannot run asynchronous cleanup; unfinished entries remain device-local.
    var hasPendingCleanup: Bool { !running && !pendingReset.isEmpty && !closing }

    func closeStage() async -> Bool {
        guard !closing else { return false }
        closing = true
        if running {
            pendingReset = MultiviewStageStore.cleanupTargets(pendingReset, including: savedCameras())
        }
        persistStage()
        stop()
        await resetStations(pendingReset)
        persistStage()
        closing = false
        if !pendingReset.isEmpty {
            error =
                "Some cameras could not return to their own Wi-Fi. Keep them powered on and close Multiview again to retry."
            return false
        }
        return true
    }
    private func resetStations(_ cameras: [MultiviewStageStore.Camera]) async {
        await withTaskGroup(of: Void.self) { group in
            for saved in cameras {
                group.addTask { _ = await self.resetStationOnce(saved) }
            }
        }
    }
    /// Shared by scan completion/cancellation, close and restored cleanup. Its task
    /// survives caller cancellation and prevents two BLE resets for the same camera.
    @discardableResult func resetStationOnce(_ saved: MultiviewStageStore.Camera) async -> Bool {
        if let task = stationResetTasks[saved.id] { return await task.value }
        guard pendingReset.contains(where: { $0.id == saved.id }) else { return true }
        let task = Task {
            let success: Bool
            if let resetCamera { success = await resetCamera(saved) }
            else { success = await resetStation(saved) }
            if success { pendingReset.removeAll { $0.id == saved.id } }
            persistStage()
            stationResetTasks.removeValue(forKey: saved.id)
            return success
        }
        stationResetTasks[saved.id] = task
        return await task.value
    }
    private func resetStation(_ saved: MultiviewStageStore.Camera) async -> Bool {
        let client = MultiviewProvisioner()
        defer { client.close() }
        do {
            try await client.connect(restoredCamera(saved), pairingTimeout: 12)
            let reply = try await client.exchange(
                MulticamCommands.stationMode(false, seq: client.next()))
            let accepted = reply.payload == [0] || reply.payload == [0, 0]
            ControlLiveLog.line("multiview: return camera Wi-Fi accepted=\(accepted)")
            return accepted
        } catch {
            ControlLiveLog.line("multiview: return camera Wi-Fi failed")
            return false
        }
    }
    static func wifiAddress() -> String? { SharedWiFiPath.address() }
}

/// Discovery is broader than the preview command profiles captured so far.
extension FoundCamera {
    func acceptsMissingMultiviewRoleQuery(_ reply: [UInt8]) -> Bool {
        (model.family == .nano || model.isPocket3) && reply == [0xe0]
    }
    var appearsInMultiview: Bool {
        !model.isDrone && (model.name.lowercased().contains("osmo") || model.family != .other)
    }
    var hasMultiviewPreview: Bool {
        guard appearsInMultiview, model.usesCapturedLiveEnable else { return false }
        let name = model.name.lowercased().replacingOccurrences(of: " ", with: "")
        return model.isPocket3 || name.contains("pocket4") || model.family == .nano
    }
}
