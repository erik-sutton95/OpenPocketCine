import Foundation
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
        // A settings editor borrows only the command/status path. It never owns the feed.
        var controlsModel: AppModel?
        func retireControls() {
            controlsModel?.captureSheet = nil
            controlsModel?.captureDrum = nil
            controlsModel?.session.releaseMultiview()
            controlsModel = nil
            previewDemand = false
        }
        /// Camera settings' live preview borrows this decoder's existing sample
        /// path, like Live View's assist inspector demand. No new decoder.
        var previewDemand = false {
            didSet { if previewDemand != oldValue, liveModel == nil { updateLUT() } }
        }
        var driver: DatalinkDriver? {
            didSet {
                liveModel?.session.datalink = nil
                retireControls()
            }
        }
        var connecting = false { didSet { if connecting { retireControls() } } }
        var experimentalNetwork = false
        var networkVerified = false
        var cameraAddress = ""
        var identity: [UInt8]?
        // Per ACK frame bookkeeping; no view reads it.
        @ObservationIgnored var responses: [UInt16: Duml.Frame] = [:]
        var camera: FoundCamera? { didSet { if camera?.id != oldValue?.id { retireControls() } } }
        var status = "Add camera"
        var failureMessage: String?
        var recovery = MultiviewRecovery()
        @ObservationIgnored var repairTask: Task<Void, Never>?
        var recovering = false { didSet { if recovering { retireControls() } } }
        var pathLostAt: Date?
        var checkForegroundDecoder = false
        var settings = CameraStatus()
        @ObservationIgnored var pose = GimbalStickMapping()
        @ObservationIgnored var latestSettings = CameraStatus()
        @ObservationIgnored var settingsPublishedAt = Date.distantPast
        let sampleBus = LiveFrameSampleBus()
        var lutEnabled = true
        var effects = LiveImageEffects()
        var lutCaption = "Auto LUT"

        func updateSettings(_ frame: Duml.Frame) {
            guard let camera else { return }
            controlsModel?.session.receiveMultiview(frame)
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
            next.inspectorSample = previewDemand
            effects = next
            decoder.effects = next
            decoder.adoptIncomingTransfer(settings.monitorTransfer)
            if next.needsGPUFeed { decoder.unlockHardwareDecoder() }
        }

        var timecodeReadout: String? {
            guard let camera, camera.model.family != .nano,
                let timecode = settings.timecode, !timecode.isEmpty
            else { return nil }
            return settings.timecodeClock
        }

        var hasPicture = false
        private(set) var previewFresh = false
        private(set) var previewFrames = 0
        var previewAccessibilityValue: String {
            let state = previewFresh ? "Live" : (camera == nil ? "Empty" : "Reconnecting")
            #if DEBUG
                if ProcessInfo.processInfo.environment["OPV_PHYSICAL_MULTIVIEW_PROBE"] == "1" {
                    // Read-only physical-test evidence from decoded camera status, never
                    // the settings editor's optimistic format/exposure presentation.
                    let format = latestSettings.videoFormat
                    let values = [
                        "frames=\(previewFrames)",
                        "fps=\(format.map { Int($0.frameRate.rawValue) } ?? -1)",
                        "res=\(format.map { Int($0.resolution.rawValue) } ?? -1)",
                        "expo=\(latestSettings.expoMode.map { Int($0.rawValue) } ?? -1)",
                        "shutter=\(latestSettings.shutterDenom)",
                        "mode=\(latestSettings.shootingMode)",
                        "rec=\(latestSettings.isRecording ? 1 : 0)",
                        "usesAngle=\(OperatorPrefs.shutterUsesAngle ? 1 : 0)",
                        "angle=\(OperatorPrefs.shutterAngleDegrees)",
                        "shutters=\(latestSettings.availableShutterDenoms.map(String.init).joined(separator: ","))",
                    ]
                    return ([state] + values).joined(separator: "; ")
                }
            #endif
            return state
        }
        /// Sample health on the existing 1 Hz monitor, never in the view's frame loop.
        func samplePreviewHealth(now: Date = Date()) {
            let since = max(previewStarted ?? now, now.addingTimeInterval(-2))
            let fresh = hasFreshPicture(since: since, now: now)
            if previewFresh != fresh { previewFresh = fresh }
            if fresh { previewFrames = decoder.sourcePresentations }
        }
        func hasFreshPicture(since: Date, now: Date = Date()) -> Bool {
            guard publishing, !connecting, let driver,
                !decoder.referenceRecoveryNeeded,
                let source = decoder.lastSourceFrameAt, source > since,
                let present = decoder.monitorPresentedAt, present > since,
                let packet = driver.lastVideoPacketAt, packet > since
            else { return false }
            if decoder.nativeOutputExpected {
                guard let age = decoder.nativeOutputAge, now.addingTimeInterval(-age) > since
                else { return false }
            }
            return true
        }
        var publishing = false
        var recordingBusy = false
        var recordingAvailable = false
        var recordingNote: String?
        var controlHost: String? { didSet { if controlHost != oldValue { retireControls() } } }
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
            guard pendingAssistHandoff, !recovering, let driver, controlHost != nil,
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
        /// Install the input callbacks for exactly this tile's current endpoint.
        func bindPreviewInput(_ driver: DatalinkDriver) {
            let tile = self
            driver.onVideoDiscontinuity = { [weak tile, weak driver] in
                guard let tile, let driver, tile.driver === driver else { return }
                tile.decoder.noteCompressedDiscontinuity()
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
        }

        func watchdogSnapshot(now: Date, pathReady: Bool) -> FeedWatchdog.Snapshot? {
            guard let driver else { return nil }
            let age: (Date?) -> TimeInterval? = { $0.map { now.timeIntervalSince($0) } }
            return FeedWatchdog.Snapshot(
                now: now.timeIntervalSinceReferenceDate,
                lastDecodedFrameAge: age(decoder.lastPresentedAt),
                lastVideoPacketAge: age(driver.lastVideoPacketAt),
                lastAccessUnitAge: age(driver.lastAccessUnitAt),
                lastStatusAge: age(driver.lastStatusAt), flowHealthy: driver.isFlowHealthy,
                pathReady: pathReady,
                hasFormat: decoder.hasFormat,
                decoderFailed: decoder.isDecoderWedged
                    || decoder.displayLayer.status == .failed,
                live: true, sawPicture: hasPicture, tcpPokeReady: driver.isTcpPokeReady,
                secondsSinceLastRebuild: driver.secondsSinceLastRebuild,
                hadVideo: driver.videoPackets > 0,
                secondsSinceLastEnable: now.timeIntervalSince(lastEnable),
                secondsSinceCameraSet: driver.secondsSinceLastCommand,
                lastDecoderOutputAge: decoder.nativeOutputAge,
                decoderOutputExpected: decoder.nativeOutputExpected,
                referenceRecoveryNeeded: decoder.referenceRecoveryNeeded,
                secondsSinceLastIrap: decoder.lastIrapAt.map { now.timeIntervalSince($0) },
                repairReady: decoder.isDisplayReady)
        }

        /// Readiness and an actual enable each get their own bounded window.
        static func decoderRepairHasTime(
            requestedAt: Date, sentAt: Date?, now: Date = Date()
        ) -> Bool {
            now.timeIntervalSince(sentAt ?? requestedAt) < FeedWatchdog.decoderRepairDeadline
        }

        func finishDecoderRepair(
            previous: MultiviewRecovery, sentAt: Date?, applicationActive: Bool,
            foregroundUnchanged: Bool = true
        ) -> Bool {
            guard applicationActive, foregroundUnchanged, sentAt != nil else {
                recovery = previous
                return false
            }
            if decoder.nativeOutputExpected,
                (decoder.nativeOutputAge ?? .infinity) < FeedWatchdog.stallThreshold
            {
                recovery.watchdog = FeedWatchdog()
                return false
            }
            return true
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
    @ObservationIgnored private var activityGeneration = 0
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
    private let resetCamera: ((MultiviewStageStore.Camera) async throws -> Bool)?
    private let resetRetryDelay: () async -> Void
    private let saveStage: (MultiviewStageStore.Stage?) -> Bool
    private let loadNetwork: (String, Bool) -> MultiviewNetworkStore.Network?
    private var cleanupJournalWritten = false
    private let ble = BleLink(allowsConcurrentCameras: true)
    private var scanTask: Task<Void, Never>?
    private var networkScanTask: Task<Void, Error>?
    private var discovering = false
    private var monitor: Task<Void, Never>?
    private var running = false

    init(
        resetCamera: ((MultiviewStageStore.Camera) async throws -> Bool)? = nil,
        resetRetryDelay: @escaping () async -> Void = {
            try? await Task.sleep(for: .seconds(3))
        },
        saveStage: @escaping (MultiviewStageStore.Stage?) -> Bool = MultiviewStageStore.save,
        loadNetwork: @escaping (String, Bool) -> MultiviewNetworkStore.Network? =
            MultiviewNetworkStore.load(ssid:hotspot:)
    ) {
        self.resetCamera = resetCamera
        self.resetRetryDelay = resetRetryDelay
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
        case timeout, unavailable, rejected, network, pairingDeferred
        var errorDescription: String? {
            switch self {
            case .timeout: "Camera did not respond. Close other camera apps and try again."
            case .unavailable: "Camera is not nearby. Check that it is powered on."
            case .rejected:
                "Camera could not complete this step. Check the Wi-Fi details and try again."
            case .network: "Join the shared Wi-Fi network on this device first."
            case .pairingDeferred: "Camera is not ready to pair again. Please try again."
            }
        }
    }
    func openLiveView(_ tile: Tile) {
        closeCameraSettings()
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
            if let session = tile.liveModel?.session { tile.pose = session.multiviewPose }
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
                    tile.samplePreviewHealth()
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
        } else if !discovering, !busy {
            scan()
        }
    }

    /// The wizard owns selection; this session owns the scan and its persistent cleanup.
    /// Reuse Add setup's same-link station scan instead of a second BLE implementation.
    func scanNetworks(onFound: @escaping @MainActor (String) -> Void) async throws {
        guard running, !closing, !busy, !tiles.contains(where: { $0.camera != nil }) else {
            throw CancellationError()
        }
        busy = true
        defer {
            busy = false
            networkScanTask = nil
            refreshDiscovery()
        }
        let task = Task {
            var camera: FoundCamera?
            for _ in 0..<10 {
                try Task.checkCancellation()
                camera = found.first(where: { $0.hasMultiviewPreview })
                if camera != nil { break }
                try await Task.sleep(for: .milliseconds(300))
            }
            guard let camera else { throw Failure.unavailable }
            stopDiscovery()
            try await MultiviewProvisioner.scanNetworks(
                camera,
                beforeStationChange: {
                    guard self.recordStationChange(camera) else {
                        throw ProvisioningFailure.message(
                            "Could not save camera Wi-Fi cleanup. Try again.")
                    }
                },
                onRestored: { restored in
                    if restored {
                        self.pendingReset.removeAll { $0.id == camera.id }
                        if self.pendingReset.isEmpty { self.networkSetupError = nil }
                        self.persistStage()
                    } else {
                        self.networkSetupError =
                            "Camera Wi-Fi could not be restored. Keep it powered on and close Multiview to retry."
                    }
                }, onFound: onFound)
        }
        networkScanTask = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    @discardableResult func recordStationChange(_ camera: FoundCamera) -> Bool {
        let saved = MultiviewStageStore.Camera(
            slot: 0, id: camera.id, name: camera.name, modelId: camera.modelId,
            identity: nil, address: "", experimental: false, lutEnabled: false)
        pendingReset = MultiviewStageStore.cleanupTargets(pendingReset, including: [saved])
        return persistStage()
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
        guard applicationActive != active else { return }
        applicationActive = active
        activityGeneration &+= 1
        ControlLiveLog.line("multiview: scene \(active ? "active" : "inactive")")
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
        guard
            let snapshot = tile.watchdogSnapshot(
                now: now, pathReady: SharedWiFiPath.address(hotspot: usePhoneHotspot) != nil)
        else { return }
        if snapshot.pathReady {
            tile.pathLostAt = nil
        } else if tile.pathLostAt == nil {
            tile.pathLostAt = now
        }
        if tile.checkForegroundDecoder && FeedWatchdog.udpReceiveAlive(snapshot) {
            tile.checkForegroundDecoder = false
            if tile.decoder.displayLayer.status == .failed
                || tile.decoder.displayLayer.requiresFlushToResumeDecoding
            {
                tile.decoder.prepareAfterForeground()
                tile.decoder.noteCompressedDiscontinuity()
                ControlLiveLog.line(
                    "multiview: foreground display resumed; watchdog owns references")
                return
            }
        }
        let previousRecovery = tile.recovery
        let action = tile.recovery.action(snapshot)
        if tile.decoder.awaitingIDR, tile.decoder.canReleaseIDRHold,
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
            guard tile.decoder.isPresentationReady, let camera = tile.camera else {
                tile.recovery = previousRecovery
                return
            }
            driver.reRegister()
            driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
            tile.lastEnable = now
            tile.enableSends += 1
            tile.decoder.beginIDRHold()
            return
        }
        if action == .rebuildVTSession {
            guard
                tile.decoder.rebuildPresentationIfNeeded(
                    referenceLossOnly: snapshot.referenceRecoveryNeeded)
            else {
                tile.recovery = previousRecovery
                return
            }
            tile.recovering = true
            let generation = activityGeneration
            tile.repairTask = Task { [weak self, weak tile, weak driver] in
                guard let self, let tile, let driver else { return }
                defer {
                    tile.recovering = false
                    tile.repairTask = nil
                }
                let requestedAt = Date()
                var sentAt: Date?
                while running, !Task.isCancelled, tile.driver === driver,
                    applicationActive, activityGeneration == generation,
                    Tile.decoderRepairHasTime(requestedAt: requestedAt, sentAt: sentAt)
                {
                    if let sentAt, tile.hasFreshPicture(since: sentAt) {
                        tile.recovery.watchdog = FeedWatchdog()
                        ControlLiveLog.line("multiview: decoder repair restored fresh picture")
                        return
                    }
                    if sentAt == nil, applicationActive, tile.decoder.isPresentationReady,
                        SharedWiFiPath.address(hotspot: usePhoneHotspot) != nil,
                        let camera = tile.camera
                    {
                        driver.startLiveView(receiver: camera.model.liveViewEnableReceiver)
                        tile.pendingAssistHandoff = false
                        tile.lastEnable = Date()
                        tile.enableSends += 1
                        sentAt = tile.lastEnable
                        ControlLiveLog.line("multiview: decoder repair enable, socket retained")
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard running, !Task.isCancelled, tile.driver === driver else { return }
                guard
                    tile.finishDecoderRepair(
                        previous: previousRecovery, sentAt: sentAt,
                        applicationActive: applicationActive,
                        foregroundUnchanged: activityGeneration == generation)
                else { return }
                await rejoinWhenAvailable(tile)
            }
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
        tile.bindPreviewInput(driver)
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
        tile.failureMessage = nil
        tile.driver?.close()
        tile.driver = nil
        tile.camera = nil
        tile.networkVerified = false
        tile.experimentalNetwork = false
        tile.settings = CameraStatus()
        tile.latestSettings = CameraStatus()
        tile.pose = GimbalStickMapping()
        tile.lutEnabled = true
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
        closeCameraSettings()
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
        networkScanTask?.cancel()
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
        closeCameraSettings()
        guard !closing else { return false }
        closing = true
        networkScanTask?.cancel()
        _ = try? await networkScanTask?.value
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
            let success = await returnCameraWiFi(saved)
            if success { pendingReset.removeAll { $0.id == saved.id } }
            persistStage()
            stationResetTasks.removeValue(forKey: saved.id)
            return success
        }
        stationResetTasks[saved.id] = task
        return await task.value
    }
    private func returnCameraWiFi(_ saved: MultiviewStageStore.Camera) async -> Bool {
        for attempt in 1...3 {
            do {
                if let resetCamera { return try await resetCamera(saved) }
                return try await resetStation(saved)
            } catch Failure.pairingDeferred where attempt < 3 {
                ControlLiveLog.line(
                    "multiview: camera pairing deferred; Wi-Fi return retry \(attempt) of 2")
                await resetRetryDelay()
            } catch {
                return false
            }
        }
        return false
    }

    private func resetStation(_ saved: MultiviewStageStore.Camera) async throws -> Bool {
        let client = MultiviewProvisioner()
        var phase = "pairing"
        do {
            try await client.connect(restoredCamera(saved), pairingTimeout: 12)
            phase = "AP switch"
            let reply = try await client.exchange(
                MulticamCommands.stationMode(false, seq: client.next()))
            let accepted = reply.payload == [0] || reply.payload == [0, 0]
            ControlLiveLog.line("multiview: return camera Wi-Fi accepted=\(accepted)")
            await client.closeAndWait()
            return accepted
        } catch {
            // A new cleanup attempt must not share a Bluetooth link that is still closing.
            await client.closeAndWait()
            ControlLiveLog.line(
                "multiview: return camera Wi-Fi failed phase=\(phase) domain=\((error as NSError).domain) code=\((error as NSError).code)"
            )
            throw error
        }
    }
    static func wifiAddress() -> String? { SharedWiFiPath.address() }
}

/// Discovery is broader than the preview command profiles captured so far.
extension FoundCamera {
    var appearsInMultiview: Bool { MulticamSupport.appears(model) }
    var hasMultiviewPreview: Bool { MulticamSupport.hasPreview(model) }
}
