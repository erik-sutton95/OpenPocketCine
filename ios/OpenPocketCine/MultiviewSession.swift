import Foundation
import Observation
import OpenCineAppKit
import OpenCineApple
import OpenCineCore
import OpenCineDJIApple
import OpenCineMedia
import OpenCineMulticam
import OpenPocketViewCore
import UIKit

@MainActor @Observable
final class MultiviewSession {
    let backdropRenderer = MonitorVideoBackdropRenderer()
    @MainActor @Observable final class Tile: Identifiable {
        let id = UUID()
        let decoder = HevcDecoder()
        /// This tile's camera as a common session (MULTI-02): one per tile for its lifetime, so
        /// selection, layout and rotation never change it. Its control epoch advances when the
        /// tile's link or camera is replaced.
        let control: DJICameraSessionAdapter
        let controlPort: MultiviewTileControl
        /// The tile's picture stream, named for the multicam engine.
        let stream = StreamID()
        var liveModel: AppModel?
        // A settings editor borrows only the command/status path. It never owns the feed.
        var controlsModel: AppModel?
        func retireControls() {
            controlsModel?.captureSheet = nil
            controlsModel?.captureDrum = nil
            controlsModel?.control.unbind()
            controlsModel?.session.releaseMultiview()
            controlsModel = nil
            previewDemand = false
        }
        /// Camera settings' live preview borrows this decoder's existing sample
        /// path, like Live View's assist inspector demand. No new decoder.
        var previewDemand = false {
            didSet { if previewDemand != oldValue, liveModel == nil { updateLUT() } }
        }
        var driver: DjiAppleDatalink? {
            didSet {
                liveModel?.session.datalink = nil
                retireControls()
                if driver !== oldValue { control.linkDidChange() }
            }
        }
        var connecting = false { didSet { if connecting { retireControls() } } }
        var experimentalNetwork = false
        var networkVerified = false
        var cameraAddress = ""
        var identity: [UInt8]?
        // Per ACK frame bookkeeping; no view reads it.
        @ObservationIgnored var responses: [UInt16: Duml.Frame] = [:]
        var camera: DjiAppleSighting? {
            didSet {
                if camera?.id != oldValue?.id {
                    retireControls()
                    control.linkDidChange()
                }
            }
        }
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
        var effects = MonitorFrameEffects()
        var lutCaption = "Auto LUT"

        func updateSettings(_ frame: Duml.Frame) {
            guard let camera else { return }
            controlsModel?.session.receiveMultiview(frame)
            let previousFlip = latestSettings.selfieFlip
            CameraStatusDecoder.apply(frame, to: &latestSettings, model: camera.model)
            decoder.refreshSourceCalibration()
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
            var next = MonitorFrameEffects()
            next.colorMode = settings.colorMode ?? .normal
            let source = autoLUTSource
            let lut: OfficialDJILUT?
            if case .dji(let official) = source { lut = official } else { lut = nil }
            var loaded = false
            if let lut, lutEnabled, let cube = BundledOfficialDJILUT.cube(lut) {
                let gpu = cube.colorCube
                next.lutDimension = gpu.size
                next.lutRGBA = gpu.rgbaComponents.withUnsafeBytes { Data($0) }
                loaded = true
            }
            lutCaption = autoLUT(for: source).caption(enabled: lutEnabled, conversionLoaded: loaded)
            next.inspectorSample = previewDemand
            effects = next
            decoder.effects = next
            decoder.adoptIncomingTransfer(settings.monitorTransfer)
            if next.needsGPUFeed { decoder.unlockHardwareDecoder() }
        }

        /// The body's clock at its declared precision, only where it declares one (Nano has none).
        var timecodeReadout: String? {
            guard camera != nil, control.layout().timecode else { return nil }
            return MonitorTimecodeFormat.label(control.current)
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
                control.sessionDidChange()
            }
        }
        private(set) var recordingActive: Bool?
        init() {
            let port = MultiviewTileControl()
            controlPort = port
            control = DJICameraSessionAdapter(session: port)
            // Backstops only: the tile's own 8 s confirmation window decides first.
            control.wireTimeout = .seconds(9)
            control.readbackTimeout = .seconds(9)
            decoder.feedUpscaler = .off
            decoder.sourceCalibrationProvider = { [weak self] in
                guard let self, self.latestSettings.iso > 0 else { return nil }
                return self.latestSettings.iso
            }
            decoder.onPresentedFrame = { [weak self] in
                self?.liveModel?.session.noteMultiviewFrame()
            }
            port.tile = self
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
        func bindPreviewInput(_ driver: DjiAppleDatalink) {
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
    let tiles = (0..<MultiviewQualificationPolicy.tileCount).map { _ in Tile() }
    var found: [DjiAppleSighting] = []
    var busy = false
    var ready = false
    var ssid = ""
    var usePhoneHotspot = false
    var password = ""
    var groupRecordingBusy = false
    var groupRecordingNote: String?
    /// Settings-editor leases (OpenCineMulticam): one per open editor, asked before every SET.
    @ObservationIgnored var editorLeases = EditorLeases()
    var recordingTiles: [Tile] { tiles.filter { $0.camera != nil } }
    var anyRecording: Bool { recordingTiles.contains { $0.recordingActive == true } }
    var canRecordTogether: Bool { !busy && !groupRecordingBusy && recordPlan().isExecutable }

    var networkConfigured = false
    var configuringNetwork = false
    var networkSetupError: String?
    var applicationActive = true
    @ObservationIgnored private var activityGeneration = 0
    private var foregroundAt = Date.distantPast
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    var host = ""
    var error: String?
    let presentation = MultiviewStageState(slotCount: MultiviewQualificationPolicy.tileCount)
    var layout: MultiviewLayout {
        get { presentation.layout == .grid ? .grid : .centerStage }
        set { presentation.layout = newValue == .grid ? .grid : .centerStage }
    }
    var feedAspect: PortraitFeedAspect {
        get { presentation.fill ? .fill : .fit16x9 }
        set { presentation.fill = newValue == .fill }
    }
    var focusedIndex: Int {
        get { presentation.selected }
        set { presentation.selected = newValue }
    }
    var closing = false
    var connectingCameras: Bool { tiles.contains { $0.connecting } }
    /// The phone's side of the shared network and DJI's camera setup, through OpenCine's seams.
    let hostPath: any StationHostPath
    private let commissioner: any StationCommissioner<DjiAppleSighting>
    private var searches: [UUID: DjiAppleNetworkDiscovery] = [:]
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
    private let ble = DjiAppleBluetoothLink(allowsConcurrentCameras: true, host: .pocket)
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
        let hostPath = SharedWiFiPath()
        self.hostPath = hostPath
        commissioner = DJIStationCommissioner(
            host: .pocket, hostPath: hostPath, retryDelay: resetRetryDelay)
    }

    private enum ProvisioningFailure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    typealias Failure = MultiviewFailure
    func openLiveView(_ tile: Tile) {
        closeCameraSettings()
        guard let camera = tile.camera, tile.controlHost != nil, !tile.recovering else { return }
        let model = AppModel(session: CameraSession(borrowing: tile.decoder))
        model.session.updateMultiview(
            camera: camera, driver: tile.driver, status: tile.latestSettings)
        model.session.adoptMultiviewPose(tile.pose)
        model.frameSamples = tile.sampleBus
        model.assist.lutEnabled = tile.lutEnabled
        model.borrowMonitor(camera) { [weak self] in self?.closeLiveView() }
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
        restoreStage()
        scan()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.ready = self.hostPath.address(hotspot: self.usePhoneHotspot) != nil
                for tile in self.tiles {
                    tile.keepalive()
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
            var camera: DjiAppleSighting?
            for _ in 0..<10 {
                try Task.checkCancellation()
                camera = found.first(where: { commissioner.hasPreview($0) })
                if camera != nil { break }
                try await Task.sleep(for: .milliseconds(300))
            }
            guard let camera else { throw Failure.unavailable }
            stopDiscovery()
            try await commissioner.scanNetworks(
                through: camera,
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

    @discardableResult func recordStationChange(_ camera: DjiAppleSighting) -> Bool {
        let record = commissioner.record(camera)
        let saved = MultiviewStageStore.Camera(
            slot: 0, id: record.id, name: record.name, modelId: record.modelId,
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
        guard
            let address = try await hostPath.join(
                StationNetwork(ssid: ssid, password: password, hotspot: false))
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

    /// The coordinator's half of repair: when a tile may repair, the 45 s path-loss rule, and the
    /// rejoin within the tile's budget. The tile's own link decides and runs the repair.
    private func monitorPreview(_ tile: Tile) {
        guard applicationActive, Date().timeIntervalSince(foregroundAt) > 3,
            !busy, !tile.recovering, !tile.recovery.failed,
            tile.publishing, tile.driver != nil
        else { return }
        let now = Date()
        let pathReady = hostPath.address(hotspot: usePhoneHotspot) != nil
        if pathReady {
            tile.pathLostAt = nil
        } else if tile.pathLostAt == nil {
            tile.pathLostAt = now
        }
        let generation = activityGeneration
        let context = MultiviewRepairContext(
            pathReady: pathReady,
            running: { [weak self] in self?.running ?? false },
            applicationActive: { [weak self] in self?.applicationActive ?? false },
            foregroundUnchanged: { [weak self] in self?.activityGeneration == generation },
            pathAvailable: { [weak self] in
                guard let self else { return false }
                return hostPath.address(hotspot: usePhoneHotspot) != nil
            })
        switch tile.repair(context) {
        case .healthy:
            if !pathReady, now.timeIntervalSince(tile.pathLostAt ?? now) > 45 {
                tile.recovery.fail()
                tile.failureMessage =
                    "Shared network unavailable. Rejoin it, then reconnect this camera."
            }
        case .handled:
            break
        case .repair(let work):
            tile.recovering = true
            tile.repairTask = Task { [weak self, weak tile] in
                guard let self, let tile else { return }
                defer {
                    tile.recovering = false
                    tile.repairTask = nil
                }
                if await work() { await rejoinWhenAvailable(tile) }
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

    func add(_ camera: DjiAppleSighting, to tile: Tile, experimental: Bool = false) async {
        let reasons = ResourceAdmission.reasons(
            admitting: ResourceRequest(entry: MonitorEntryID(tile.id), device: nil, claims: []),
            qualification: commissioner.qualification(camera, experimental: experimental),
            alongside: recordingTiles.map {
                ResourceRequest(entry: MonitorEntryID($0.id), device: nil, claims: [])
            }, budget: MultiviewQualificationPolicy.budget)
        guard reasons.isEmpty else {
            error = "Multiview preview is not available for this camera model yet."
            return
        }
        guard running, networkConfigured, !closing, !busy, !tile.connecting, tile.camera == nil,
            !tiles.contains(where: { $0.camera?.id == camera.id })
        else { return }
        tile.connecting = true
        var client: (any StationCommission)?
        tile.camera = camera
        tile.experimentalNetwork = experimental
        tile.networkVerified = false
        tile.status = "Connecting · approve on camera"
        refreshDiscovery()
        defer {
            tile.connecting = false
            client?.close()
            if running { persistStage() }
            refreshDiscovery()
        }
        persistStage()
        var stage = "host Wi-Fi"
        do {
            try await joinSharedNetwork()
            stage = "Bluetooth pairing"
            let link = try await commissioner.connect(camera) { tile.status = $0 }
            client = link
            stage = "camera Wi-Fi identity"
            let identity = try await link.identity()
            stage = "station join"
            let outcome = try await link.join(
                StationNetwork(ssid: ssid, password: password, hotspot: usePhoneHotspot),
                identity: identity, experimental: experimental, progress: { tile.status = $0 },
                verifyOnNetwork: {
                    try await self.discoverPreview(tile, camera: camera, identity: identity)
                    return true
                })
            tile.identity = identity
            MultiviewNetworkStore.save(ssid: ssid, password: password, hotspot: usePhoneHotspot)
            if outcome == .verified { return }
            link.close()
            stage = "LAN discovery"
            try await discoverPreview(tile, camera: camera, identity: identity)
        } catch {
            guard running, !Task.isCancelled else { return }
            tile.close()
            tile.status = "Could not connect"
            tile.failureMessage = djiConnectionFailureDescription(
                error, fallback: error.localizedDescription)
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
            tile.close()
            tile.publishing = false
            tile.controlHost = nil
            tile.status = "Could not connect preview"
            tile.failureMessage = "Could not restore preview. Tap Reconnect to try again."
            tile.recovery.fail()
        }
    }

    private func discoverPreview(_ tile: Tile, camera: DjiAppleSighting, identity: [UInt8]) async throws
    {
        let search = DjiAppleNetworkDiscovery()
        searches[tile.id] = search
        defer {
            search.cancel()
            searches.removeValue(forKey: tile.id)
        }
        tile.close()
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
                    tile.close()
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

    private func openPreview(_ tile: Tile, camera: DjiAppleSighting, identity: [UInt8]) async throws {
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
        try await tile.open(
            camera, at: tile.cameraAddress, identity: identity, hotspot: usePhoneHotspot)
        guard running else { throw CancellationError() }
        tile.networkVerified = true
        if !commissioner.hasPreview(camera) {
            tile.close()
            tile.failureMessage = nil
            tile.status = "Wi-Fi join verified · Preview not supported yet"
            ControlLiveLog.line(
                "multiview: experimental LAN identity verified; preview unavailable")
            return
        }
        try await tile.startPreview(camera)
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
        tile.close()
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
        commissioner.closeCommissions()
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
            tile.close()
            tile.decoder.reset()
        }
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
        presentation.importLegacy(
            .init(
                layout: MultiviewLayout(rawValue: stage.layout) == .grid ? .grid : .centerStage,
                selected: stage.focusedIndex, fill: stage.fill == true))
        // Migrate unfinished camera cleanup before a new camera is added.
        // With no cleanup, retain the last preferences even if setup is cancelled.
        if cleanupJournalWritten { persistStage() }
    }
    func enqueueAdd(_ camera: DjiAppleSighting, to tile: Tile, experimental: Bool = false) {
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
    /// The test hook replaces only the radio step; the bounded retry is the same either way.
    private func returnCameraWiFi(_ saved: MultiviewStageStore.Camera) async -> Bool {
        if let resetCamera {
            var retries = 0
            return await restoreCameraWiFiWithRetry(waitBetween: {
                retries += 1
                ControlLiveLog.line(
                    "multiview: camera pairing deferred; Wi-Fi return retry \(retries) of 2")
                await resetRetryDelay()
            }) {
                try await resetCamera(saved)
            }
        }
        return await commissioner.restoreAccessPoint(
            StationCameraRecord(id: saved.id, name: saved.name, modelId: saved.modelId))
    }

    static func wifiAddress() -> String? { DjiAppleSharedWiFiPath.address() }
}

/// Discovery is broader than the preview command profiles captured so far.
extension DjiAppleSighting {
    var appearsInMultiview: Bool { MulticamSupport.appears(model) }
    var hasMultiviewPreview: Bool { MulticamSupport.hasPreview(model) }
}
