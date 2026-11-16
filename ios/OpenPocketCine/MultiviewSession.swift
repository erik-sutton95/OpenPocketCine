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
        let id: UUID
        /// The stage's half of this tile (camera, copy, control host, record state, recovery
        /// budget), owned by OpenCine's `MultiviewCoordinator`; the properties below forward to it.
        let member: MultiviewMember<DjiAppleSighting>
        let decoder = HevcDecoder()
        /// This tile's camera as a common session (MULTI-02): one per tile for its lifetime, so
        /// selection, layout and rotation never change it. Its control epoch advances when the
        /// tile's link or camera is replaced.
        let control: DJICameraSessionAdapter
        let controlPort: MultiviewTileControl
        /// The tile's picture stream, named for the multicam engine.
        var stream: StreamID { member.stream }
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
        var connecting: Bool {
            get { member.connecting }
            set { member.connecting = newValue }
        }
        var experimentalNetwork: Bool {
            get { member.experimental }
            set { member.experimental = newValue }
        }
        var networkVerified: Bool {
            get { member.networkVerified }
            set { member.networkVerified = newValue }
        }
        var cameraAddress: String {
            get { member.address }
            set { member.address = newValue }
        }
        var identity: [UInt8]? {
            get { member.identity }
            set { member.identity = newValue }
        }
        // Per ACK frame bookkeeping; no view reads it.
        @ObservationIgnored var responses: [UInt16: Duml.Frame] = [:]
        var camera: DjiAppleSighting? {
            get { member.camera }
            set { member.camera = newValue }
        }
        var status: String {
            get { member.status }
            set { member.status = newValue }
        }
        var failureMessage: String? {
            get { member.failureMessage }
            set { member.failureMessage = newValue }
        }
        /// DJI's own feed-watchdog ladder on this tile's link; the rejoin budget is the member's.
        var recovery = MultiviewRecovery()
        var recovering: Bool {
            get { member.recovering }
            set { member.recovering = newValue }
        }
        var checkForegroundDecoder = false
        var settings = CameraStatus()
        @ObservationIgnored var pose = GimbalStickMapping()
        @ObservationIgnored var latestSettings = CameraStatus()
        @ObservationIgnored var settingsPublishedAt = Date.distantPast
        let sampleBus = LiveFrameSampleBus()
        var lutEnabled: Bool {
            get { member.lutEnabled }
            set { member.lutEnabled = newValue }
        }
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
        var publishing: Bool {
            get { member.publishing }
            set { member.publishing = newValue }
        }
        /// The member link's own record that its control link is up (it reported `controlling`);
        /// the session's `controlHost` follows it.
        @ObservationIgnored var controlLinkUp = false
        /// Where the member link reports its status; the session maps it to the tile's copy.
        @ObservationIgnored var onStatus: (@MainActor (MultiviewLinkStatus) -> Void)?
        var recordingBusy: Bool {
            get { member.recordingBusy }
            set { member.recordingBusy = newValue }
        }
        var recordingAvailable: Bool {
            get { member.recordingAvailable }
            set { member.recordingAvailable = newValue }
        }
        var recordingNote: String? {
            get { member.recordingNote }
            set { member.recordingNote = newValue }
        }
        var controlHost: String? {
            get { member.controlHost }
            set { member.controlHost = newValue }
        }
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
            id = UUID()
            member = MultiviewMember(id: id)
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
                    tile.onStatus?(.live)
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
    let tiles: [Tile]
    /// The shared stage (OpenCine's `MultiviewCoordinator`): lifecycle, network, discovery, adds,
    /// recovery budgets, record plans, editor leases, the journal and close. This session is its
    /// host: the tiles' pictures, Live View, editors and background time are Pocket's.
    @ObservationIgnored let coordinator: MultiviewCoordinator<Tile>
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var found: [DjiAppleSighting] { coordinator.found }
    var busy: Bool {
        get { coordinator.busy }
        set { coordinator.busy = newValue }
    }
    var ready: Bool {
        get { coordinator.ready }
        set { coordinator.ready = newValue }
    }
    var ssid: String {
        get { coordinator.ssid }
        set { coordinator.ssid = newValue }
    }
    var usePhoneHotspot: Bool {
        get { coordinator.usePhoneHotspot }
        set { coordinator.usePhoneHotspot = newValue }
    }
    var password: String {
        get { coordinator.password }
        set { coordinator.password = newValue }
    }
    var groupRecordingBusy: Bool {
        get { coordinator.groupRecordingBusy }
        set { coordinator.groupRecordingBusy = newValue }
    }
    var groupRecordingNote: String? {
        get { coordinator.groupRecordingNote }
        set { coordinator.groupRecordingNote = newValue }
    }
    /// Settings-editor leases (OpenCineMulticam): one per open editor, asked before every SET.
    var editorLeases: EditorLeases {
        get { coordinator.editorLeases }
        set { coordinator.editorLeases = newValue }
    }
    var recordingTiles: [Tile] { tiles.filter { $0.camera != nil } }
    var anyRecording: Bool { coordinator.anyRecording }
    var canRecordTogether: Bool { coordinator.canRecordTogether }

    var networkConfigured: Bool {
        get { coordinator.networkConfigured }
        set { coordinator.networkConfigured = newValue }
    }
    var configuringNetwork: Bool {
        get { coordinator.configuringNetwork }
        set { coordinator.configuringNetwork = newValue }
    }
    var networkSetupError: String? {
        get { coordinator.networkSetupError }
        set { coordinator.networkSetupError = newValue }
    }
    var applicationActive: Bool {
        get { coordinator.applicationActive }
        set { coordinator.applicationActive = newValue }
    }
    var host: String {
        get { coordinator.hostAddress }
        set { coordinator.hostAddress = newValue }
    }
    var error: String? {
        get { coordinator.error }
        set { coordinator.error = newValue }
    }
    var presentation: MultiviewStageState { coordinator.presentation }
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
    var closing: Bool {
        get { coordinator.closing }
        set { coordinator.closing = newValue }
    }
    var connectingCameras: Bool { coordinator.connectingCameras }
    /// The phone's side of the shared network, through OpenCine's seam.
    var hostPath: any StationHostPath { coordinator.hostPath }
    var hasPendingCleanup: Bool { coordinator.hasPendingCleanup }

    init(
        resetCamera: ((MultiviewStageJournal.Camera) async throws -> Bool)? = nil,
        resetRetryDelay: @escaping () async -> Void = {
            try? await Task.sleep(for: .seconds(3))
        },
        saveStage: @escaping (MultiviewStageJournal.Stage?) -> Bool = MultiviewStageStore.save,
        loadNetwork: @escaping (String, Bool) -> SharedNetworkStore.Network? =
            MultiviewNetworkStore.load(ssid:hotspot:)
    ) {
        let tiles = (0..<MultiviewQualificationPolicy.tileCount).map { _ in Tile() }
        self.tiles = tiles
        let hostPath = SharedWiFiPath()
        let commissioner = MultiviewStationCommissioner(
            base: DJIStationCommissioner(
                host: .pocket, hostPath: hostPath, retryDelay: resetRetryDelay),
            resetCamera: resetCamera, resetRetryDelay: resetRetryDelay)
        coordinator = MultiviewCoordinator(
            links: tiles, members: tiles.map(\.member), policy: .dji,
            commissioner: commissioner,
            scanner: MultiviewNearbyScanner(
                ble: DjiAppleBluetoothLink(allowsConcurrentCameras: true, host: .pocket)),
            hostPath: hostPath, describe: { commissioner.record($0) },
            journal: MultiviewJournalStorage(
                load: { MultiviewStageStore.load() }, save: { saveStage($0) }),
            networks: MultiviewNetworkStorage(
                password: { loadNetwork($0, $1)?.password },
                save: {
                    MultiviewNetworkStore.save(
                        ssid: $0.ssid, password: $0.password, hotspot: $0.hotspot)
                }),
            budget: MultiviewQualificationPolicy.budget,
            failureMessage: { djiConnectionFailureDescription($0, fallback: $0.localizedDescription) })
        coordinator.host = self
    }

    private func slot(_ tile: Tile) -> Int {
        guard let slot = tiles.firstIndex(where: { $0 === tile }) else {
            preconditionFailure("a tile of another Multiview session")
        }
        return slot
    }

    /// The coordinator's half of a member link's status: the tile's copy, and the control host
    /// it records once the link's control path is up at the address it was opened at.
    func show(_ status: MultiviewLinkStatus, on tile: Tile) {
        coordinator.show(status, slot: slot(tile))
    }

    func openLiveView(_ tile: Tile) {
        coordinator.openLiveView(slot: slot(tile))
    }

    func start() { coordinator.start() }

    /// BLE discovery feeds the Add picker and network setup, and stays up while a camera
    /// connects. A full stage, or an inactive app with nothing connecting, has no consumer for
    /// an unfiltered duplicate scan.
    static func needsDiscovery(
        running: Bool, applicationActive: Bool, hasEmptySlot: Bool, connecting: Bool
    ) -> Bool {
        MultiviewCoordinator<Tile>.needsDiscovery(
            running: running, applicationActive: applicationActive, hasEmptySlot: hasEmptySlot,
            connecting: connecting)
    }

    func scan() { coordinator.scan() }

    /// The wizard owns selection; the stage owns the scan and its persistent cleanup.
    func scanNetworks(onFound: @escaping @MainActor (String) -> Void) async throws {
        try await coordinator.scanNetworks(onFound: onFound)
    }

    @discardableResult func recordStationChange(_ camera: DjiAppleSighting) -> Bool {
        coordinator.recordStationChange(camera)
    }

    func selectNetworkSource(hotspot: Bool) { coordinator.selectNetworkSource(hotspot: hotspot) }

    func selectNetwork(_ name: String) { coordinator.selectNetwork(name) }

    func joinSharedNetwork() async throws { try await coordinator.joinSharedNetwork() }

    func configureNetwork() async -> Bool { await coordinator.configureNetwork() }

    func setApplicationActive(_ active: Bool) { coordinator.setApplicationActive(active) }

    func reconnect(_ tile: Tile) async { await coordinator.reconnect(slot: slot(tile)) }

    func tryExperimentalNetwork(_ tile: Tile) async {
        await coordinator.tryExperimentalNetwork(slot: slot(tile))
    }

    func add(_ camera: DjiAppleSighting, to tile: Tile, experimental: Bool = false) async {
        await coordinator.add(camera, slot: slot(tile), experimental: experimental)
    }

    func connectPreview(_ tile: Tile) async { await coordinator.connectPreview(slot: slot(tile)) }

    func remove(_ tile: Tile) async -> Bool { coordinator.remove(slot: slot(tile)) }

    func stop() { coordinator.stop() }

    @discardableResult func persistStage() -> Bool { coordinator.persistStage() }

    /// A new Multiview session always asks for a network and starts with empty slots. Old
    /// Keychain stages supply presentation preferences and cleanup obligations only; they must
    /// not choose a network or reconnect cameras.
    func restoreStage(_ savedStage: MultiviewStageJournal.Stage? = MultiviewStageStore.load()) {
        coordinator.restoreStage(savedStage)
    }

    func enqueueAdd(_ camera: DjiAppleSighting, to tile: Tile, experimental: Bool = false) {
        coordinator.enqueueAdd(camera, slot: slot(tile), experimental: experimental)
    }

    /// Close every camera's monitor first, then restore its own access point in parallel.
    /// A force quit cannot run asynchronous cleanup; unfinished entries remain device-local.
    func closeStage() async -> Bool { await coordinator.closeStage() }

    /// Shared by scan completion/cancellation, close and restored cleanup. Its task survives
    /// caller cancellation and prevents two BLE resets for the same camera.
    @discardableResult func resetStationOnce(_ saved: MultiviewStageJournal.Camera) async -> Bool {
        await coordinator.resetStationOnce(saved)
    }

    static func wifiAddress() -> String? { DjiAppleSharedWiFiPath.address() }
}

extension MultiviewSession: MultiviewHost {
    func openLiveView(slot: Int) -> Bool {
        let tile = tiles[slot]
        guard let camera = tile.camera else { return false }
        let model = AppModel(session: CameraSession(borrowing: tile.decoder))
        model.session.updateMultiview(
            camera: camera, driver: tile.driver, status: tile.latestSettings)
        model.session.adoptMultiviewPose(tile.pose)
        model.frameSamples = tile.sampleBus
        model.assist.lutEnabled = tile.lutEnabled
        model.borrowMonitor(camera) { [weak self] in self?.closeLiveView() }
        tile.liveModel = model
        return true
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

    func closeEditors() {
        for tile in tiles { tile.retireControls() }
    }

    func memberChanged(slot: Int, _ change: MultiviewMemberChange) {
        let tile = tiles[slot]
        switch change {
        case .camera:
            tile.retireControls()
            tile.control.linkDidChange()
        case .control:
            tile.retireControls()
        case .removed:
            tile.recovery = MultiviewRecovery()
            tile.settings = CameraStatus()
            tile.latestSettings = CameraStatus()
            tile.pose = GimbalStickMapping()
            tile.updateLUT()
            tile.previewStarted = nil
            tile.recordingObservation = nil
            tile.responses.removeAll()
            tile.hasPicture = false
            tile.decoder.onHandoffNeedsIDR = nil
            tile.pendingAssistHandoff = false
            tile.enableSends = 0
            tile.lastEnable = .distantPast
            tile.decoder.reset()
        }
    }

    func applicationActivityChanged(_ active: Bool) {
        if active {
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

    func stageStopped() {
        for tile in tiles { tile.decoder.reset() }
    }

    /// A tile repairs only while it has its own datalink (a closed link has nothing to repair).
    func showsPicture(slot: Int) -> Bool { tiles[slot].driver != nil }

    func log(_ line: String) { ControlLiveLog.line(line) }
}

/// Pocket's nearby DJI discovery as the stage's scanner.
@MainActor final class MultiviewNearbyScanner: NearbyCameraScanner {
    typealias Camera = DjiAppleSighting
    private let ble: DjiAppleBluetoothLink

    init(ble: DjiAppleBluetoothLink) { self.ble = ble }

    func waitUntilReady() async -> Bool { await ble.waitUntilPoweredOn() }

    func scan(_ found: @escaping @MainActor (DjiAppleSighting) -> Void) async {
        for await camera in ble.scan() {
            guard !Task.isCancelled else { return }
            found(camera)
        }
    }

    func stop() { ble.stopScan() }
}

/// DJI's station commissioner with Pocket's test hook: a test replaces only the radio step of a
/// camera's return; the bounded retry around it is the same either way.
@MainActor final class MultiviewStationCommissioner: StationCommissioner {
    typealias Camera = DjiAppleSighting
    private let base: DJIStationCommissioner
    private let resetCamera: ((MultiviewStageJournal.Camera) async throws -> Bool)?
    private let resetRetryDelay: () async -> Void

    init(
        base: DJIStationCommissioner,
        resetCamera: ((MultiviewStageJournal.Camera) async throws -> Bool)?,
        resetRetryDelay: @escaping () async -> Void
    ) {
        self.base = base
        self.resetCamera = resetCamera
        self.resetRetryDelay = resetRetryDelay
    }

    var scansNetworks: Bool { base.scansNetworks }

    func record(_ camera: DjiAppleSighting) -> StationCameraRecord { base.record(camera) }

    func connect(
        _ camera: DjiAppleSighting, progress: @escaping @MainActor (String) -> Void
    ) async throws -> any StationCommission {
        try await base.connect(camera, progress: progress)
    }

    func closeCommissions() { base.closeCommissions() }

    func restoreAccessPoint(_ record: StationCameraRecord) async -> StationRestoreResult {
        guard let resetCamera else { return await base.restoreAccessPoint(record) }
        let saved = MultiviewStageJournal.Camera(
            slot: 0, id: record.id, name: record.name, modelId: record.modelId, identity: nil,
            deviceAddress: record.deviceAddress, address: "", experimental: false,
            lutEnabled: false)
        var retries = 0
        let restored = await restoreCameraWiFiWithRetry(waitBetween: { [resetRetryDelay] in
            retries += 1
            ControlLiveLog.line(
                "multiview: camera pairing deferred; Wi-Fi return retry \(retries) of 2")
            await resetRetryDelay()
        }) {
            try await resetCamera(saved)
        }
        return restored ? .restored : .failed
    }

    func scanNetworks(
        through camera: DjiAppleSighting,
        beforeStationChange: @escaping @MainActor () throws -> Void,
        onRestored: @escaping @MainActor (Bool) -> Void,
        onFound: @escaping @MainActor (String) -> Void
    ) async throws {
        try await base.scanNetworks(
            through: camera, beforeStationChange: beforeStationChange, onRestored: onRestored,
            onFound: onFound)
    }
}

/// Discovery is broader than the preview command profiles captured so far.
extension DjiAppleSighting {
    var appearsInMultiview: Bool { MulticamSupport.appears(model) }
    var hasMultiviewPreview: Bool { MulticamSupport.hasPreview(model) }
}
