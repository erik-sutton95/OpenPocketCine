import Foundation
import NetworkExtension
import Observation
import OpenPocketViewCore
import UIKit

@MainActor @Observable
final class MultiviewSession {
    let backdropRenderer = MonitorVideoBackdropRenderer()
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
        // Per ACK frame bookkeeping; no view reads it.
        @ObservationIgnored var responses: [UInt16: Duml.Frame] = [:]
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
        /// Stamped per 0x02/0x80 frame. Views read `recordingActive`, which
        /// only changes on a REC flip, instead of re-rendering per timestamp.
        @ObservationIgnored var recordingObservation: (active: Bool, received: Date)? {
            didSet {
                let active = recordingObservation?.active
                if active != recordingActive { recordingActive = active }
            }
        }
        private(set) var recordingActive: Bool?
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
    var anyRecording: Bool { recordingTiles.contains { $0.recordingActive == true } }
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
    private var addressReservations: [String: UUID] = [:]
    private var pendingReset: [MultiviewStageStore.Camera] = []
    private var stationResetTasks: [UUID: Task<Bool, Never>] = [:]
    private let resetCamera: ((MultiviewStageStore.Camera) async -> Bool)?
    private let saveStage: (MultiviewStageStore.Stage?) -> Bool
    private let loadNetwork: (String, Bool) -> MultiviewNetworkStore.Network?
    private var cleanupJournalWritten = false
    private let ble = BleLink(allowsConcurrentCameras: true)
    private var scanTask: Task<Void, Never>?
    private var discovering = false
    private var router: Task<Void, Never>?
    private var keepalive: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var sequence: UInt16 = 1200
    private var replies: [UInt16: Duml.Frame] = [:]
    private var approved = false
    private var running = false

    init(
        resetCamera: ((MultiviewStageStore.Camera) async -> Bool)? = nil,
        saveStage: @escaping (MultiviewStageStore.Stage?) -> Bool = MultiviewStageStore.save,
        loadNetwork: @escaping (String, Bool) -> MultiviewNetworkStore.Network? =
            MultiviewNetworkStore.load(ssid:hotspot:)
    ) {
        self.resetCamera = resetCamera
        self.saveStage = saveStage
        self.loadNetwork = loadNetwork
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
        host = ""
        ready = false
        networkConfigured = false
        ssid = ""
        password = ""
        usePhoneHotspot = false
        UIApplication.shared.isIdleTimerDisabled = true
        restoreStage()
        Task { [weak self] in
            let current = await WiFiJoiner.currentSSID()
            guard let self, self.running, !self.usePhoneHotspot, let current,
                !current.lowercased().hasPrefix("osmo")
            else { return }
            if !self.networks.contains(current) { self.networks.append(current) }
        }
        networks = MultiviewNetworkStore.savedNetworks().filter { $0.hotspot != true }.map(\.ssid)
        scan()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.ready = SharedWiFiPath.address(hotspot: self.usePhoneHotspot) != nil
                for tile in self.tiles {
                    tile.driver?.keepalive()
                    tile.recoverAssistHandoff()
                    let available =
                        tile.controlHost != nil
                        && tile.recordingObservation.map {
                            Date().timeIntervalSince($0.received) < 3
                        } == true
                    if tile.recordingAvailable != available { tile.recordingAvailable = available }
                    self.monitorPreview(tile)
                }
            }
        }
    }
    /// BLE discovery feeds the Add picker and network setup, and stays up while
    /// a camera connects. A full stage, or an inactive app with nothing
    /// connecting, has no consumer for an unfiltered duplicate scan.
    static func needsDiscovery(
        running: Bool, applicationActive: Bool, hasEmptySlot: Bool, connecting: Bool
    ) -> Bool {
        running && (hasEmptySlot || connecting) && (applicationActive || connecting)
    }

    private var discoveryNeeded: Bool {
        Self.needsDiscovery(
            running: running && !closing, applicationActive: applicationActive,
            hasEmptySlot: tiles.contains { $0.camera == nil }, connecting: connectingCameras)
    }

    func scan() {
        scanTask?.cancel()
        guard discoveryNeeded else {
            stopDiscovery()
            return
        }
        discovering = true
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
    private func stopDiscovery() {
        scanTask?.cancel()
        ble.stopScan()
        discovering = false
    }

    /// Follow demand without restarting a running scan (that clears `found`) or
    /// starting one while the network-setup camera owns this BLE link.
    private func refreshDiscovery() {
        if !discoveryNeeded {
            if discovering { stopDiscovery() }
        } else if !discovering, !busy, preparedCamera == nil {
            scan()
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
        stopDiscovery()
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
                networkSetupError =
                    "Camera Wi-Fi could not be restored. Keep it powered on and close Multiview to retry."
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
        guard !configuringNetwork, !tiles.contains(where: { $0.camera != nil }) else { return }
        usePhoneHotspot = hotspot
        ssid = ""
        password = ""
        invalidateNetworkConfirmation()
    }

    func selectNetwork(_ name: String) {
        guard !configuringNetwork, !tiles.contains(where: { $0.camera != nil }) else { return }
        if ssid != name {
            ssid = name
            password = loadNetwork(name, usePhoneHotspot)?.password ?? ""
        }
        invalidateNetworkConfirmation()
    }

    private func invalidateNetworkConfirmation() {
        networkConfigured = false
        networkSetupError = nil
        host = ""
        ready = false
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
        guard let address = try await SharedWiFiPath.joinHost(ssid: ssid, password: password)
        else { throw Failure.network }
        host = address
        ready = true
    }

    func configureNetwork() async -> Bool {
        guard !busy, !configuringNetwork, !tiles.contains(where: { $0.camera != nil }) else {
            return false
        }
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
        refreshDiscovery()
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
        let action: FeedWatchdog.Action =
            foregroundRejoin ? .fullSessionRejoin : tile.recovery.action(snapshot)
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
        guard running, networkConfigured, !closing, !busy, !tile.connecting, tile.camera == nil,
            !tiles.contains(where: { $0.camera?.id == camera.id })
        else { return }
        tile.connecting = true
        let client = MultiviewProvisioner()
        provisioners[tile.id] = client
        tile.camera = camera
        tile.experimentalNetwork = experimental
        tile.networkVerified = false
        tile.status = "Connecting · approve on camera"
        refreshDiscovery()
        defer {
            tile.connecting = false
            client.close()
            provisioners.removeValue(forKey: tile.id)
            if running { persistStage() }
            refreshDiscovery()
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
            stage = "station join"
            var join = StationJoin(
                model: camera.model, ssid: ssid, password: password, hotspot: usePhoneHotspot)
            join.experimental = experimental
            let outcome = try await join.run(
                identity: identity, exchange: { try await client.exchange($0, timeout: $1) },
                send: client.send, next: client.next, status: { tile.status = $0 },
                hotspotReady: { SharedWiFiPath.address(hotspot: true) != nil },
                verifyOnNetwork: {
                    try await self.discoverPreview(tile, camera: camera, identity: identity)
                    return true
                }, log: { ControlLiveLog.line("multiview: \($0)") })
            tile.identity = identity
            MultiviewNetworkStore.save(ssid: ssid, password: password, hotspot: usePhoneHotspot)
            if outcome == .verified { return }
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
            stationHost: tile.cameraAddress, stationHotspot: usePhoneHotspot,
            subscriptionKeys: Commands.subscriptionKeys(for: camera.model))
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
                // Per access unit: re-writing these notified the whole tile view
                // at the feed rate.
                if !tile.hasPicture {
                    ControlLiveLog.line("multiview: station preview enqueued")
                    tile.hasPicture = true
                }
                if tile.status != "Live · Video mode" { tile.status = "Live · Video mode" }
            }
        }
        let nanoGate = camera.model.usesNanoLiveViewGate
        if nanoGate { driver.send(Commands.nanoLiveViewGate(start: true)) }
        if camera.model.sendsLiveViewPrepare {
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
        refreshDiscovery()
        return true
    }
    func stop() {
        persistStage()
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
        stopDiscovery()
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
                    ? MultiviewStageStore.cleanupTargets(pendingReset, including: saved)
                    : pendingReset,
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
    /// A new Multiview session always asks for a network and starts with empty
    /// slots. Old Keychain stages supply presentation preferences and cleanup
    /// obligations only; they must not choose a network or reconnect cameras.
    func restoreStage(_ savedStage: MultiviewStageStore.Stage? = MultiviewStageStore.load()) {
        guard let stage = savedStage else { return }
        pendingReset = stage.pendingReset ?? []
        if stage.returnedToCameraWiFi != true {
            pendingReset = MultiviewStageStore.cleanupTargets(
                pendingReset, including: stage.cameras)
        }
        cleanupJournalWritten = !pendingReset.isEmpty
        layout = MultiviewLayout(rawValue: stage.layout) ?? .centerStage
        feedAspect = stage.fill == true ? .fill : .fit16x9
        focusedIndex = stage.focusedIndex
        // Migrate unfinished camera cleanup before a new camera is added.
        // With no cleanup, retain the last preferences even if setup is cancelled.
        if cleanupJournalWritten { persistStage() }
    }
    func enqueueAdd(_ camera: FoundCamera, to tile: Tile, experimental: Bool = false) {
        guard running, networkConfigured, !closing, tile.camera == nil, !tile.connecting else {
            return
        }
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
            pendingReset = MultiviewStageStore.cleanupTargets(
                pendingReset, including: savedCameras())
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
            if let resetCamera {
                success = await resetCamera(saved)
            } else {
                success = await resetStation(saved)
            }
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
        MulticamSupport.acceptsMissingRoleQuery(model, reply: reply)
    }
    var appearsInMultiview: Bool { MulticamSupport.appears(model) }
    var hasMultiviewPreview: Bool { MulticamSupport.hasPreview(model) }
}
