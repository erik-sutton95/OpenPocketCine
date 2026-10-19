import CoreVideo
import MonitorPresentation
import MonitorUI
import Observation
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineCore
import OpenCineFrameIO
import OpenCineFrameIOApple
import OpenCineRelay
import OpenCineRelayApple
import OpenCineWatch
import OpenPocketViewCore
import SwiftUI
import UIKit
import OpenCineApple
import OpenCineDJIApple

/// App-level session object (OpenZCine `NativeAppModel` analogue). Owns the existing
/// `CameraSession` connection spine and the shared cameras model. Does not rewrite DUML.
@MainActor
@Observable
final class AppModel {
    var session: CameraSession
    @ObservationIgnored let playbackAudioSession = MonitorPlaybackAudioSession()
    /// Saved cameras, nearby sightings, pairing and connect attempts (SHELL-02): the shared flow
    /// over the DJI integration, which connects through `session`.
    let cameras: CamerasModel
    let control = MonitorControlModel()
    let shell: ShellModel
    @ObservationIgnored let integration: DJIIntegration
    #if DEBUG && targetEnvironment(simulator)
        @ObservationIgnored var simulatedControlReview: MonitorReviewControlPort?
    #endif
    /// A saved hotspot connect waiting for the operator to turn Personal Hotspot on.
    var hotspotQuestion: HotspotQuestion?

    /// `connects`: the cameras and pair pages discover and connect through this model (the app's
    /// one root model). A Multiview tile's live or settings model, previews and tests never do.
    init(session: CameraSession? = nil, connects: Bool = false) {
        #if targetEnvironment(simulator)
            if session == nil, MonitorUIReview.isActive { MonitorUIReview.resetMediaFavorites() }
        #endif
        let session = session ?? CameraSession()
        self.session = session
        var port: any DJIConnectPort = session
        var defaults = UserDefaults.standard
        #if targetEnvironment(simulator)
            if MonitorUIReview.isActive { (port, defaults) = MonitorUIReview.cameras() }
        #endif
        let integration = DJIIntegration(port: port)
        self.integration = integration
        cameras = CamerasModel(
            integrations: connects
                ? [
                    AppIntegration(
                        integration,
                        slots: IntegrationSlots(
                            nearbyCard: { [weak session] camera in
                                Self.nearbyCard(
                                    camera,
                                    verified: session?.found.first { $0.id.uuidString == camera.id }?.model.verified)
                            },
                            addSetup: { camera, done in
                                PocketAddSetup.flow(camera: camera, done: done)
                            }))
                ] : [],
            store: Self.camerasStore(defaults))
        shell = ShellModel(cameras: cameras, control: control)
        // The save rules a DJI record follows: another camera's network is never saved with
        // this one, and a setup that moves the camera is remembered before it moves it.
        integration.savedCameras = { [weak self] in self?.cameras.saved ?? [] }
        integration.saveRecord = { [weak self] in self?.cameras.upsert($0) }
        session.savedCameras = { [weak self] in self?.cameras.saved ?? [] }
        session.confirmHotspot = { [weak self] network in await self?.askHotspot(network) ?? false }
        #if targetEnvironment(simulator)
            (port as? ReviewDJIPort)?.confirmHotspot = session.confirmHotspot
        #endif
        shell.onSceneActivity = { [weak self] active in
            guard let self else { return }
            assist.inspectorSceneActive = active
            if active {
                self.session.noteSceneBecameActive()
            } else {
                self.session.noteSceneBecameInactive()
            }
        }
        control.noteFor = AppModel.controlNote(for:_:)
        control.onNote = { [weak self] in self?.session.controlNote = $0 }
    }

    /// main's write notes come from the session's own send path: the camera's message on a
    /// refusal, nothing on a timeout or a write it did not show. The shared copy stays only for a
    /// stale camera state (a kept wrong-camera guard) and for not being connected.
    static func controlNote(for stage: CommandStage, _ label: String) -> String? {
        let shared = MonitorControlModel.note(for: stage, label)
        switch stage {
        case .rejected(.staleEpoch), .rejected(.staleCapabilities): return shared
        default: return shared == MonitorControlModel.connectFirst ? shared : nil
        }
    }

    /// A nearby camera as the cameras page and pair page have always shown it: Pocket or Nano by
    /// name, and unverified bodies marked.
    static func nearbyCard(_ camera: NearbyCamera, verified: Bool?) -> NearbyCardCopy {
        let model = camera.model ?? camera.name
        return NearbyCardCopy(
            name: FoundCameraIdentity.listTitle(advertisedName: camera.name, modelName: model),
            subtitle: FoundCameraIdentity.listSubtitle(advertisedName: camera.name, modelName: model)
                + (verified == false ? " · unverified" : ""),
            status: "Needs approval on the camera")
    }

    /// The saved cameras: the shared document `OpenPocketCine.Cameras`, merged on every launch
    /// with the records older builds read and write (`OpenPocketCine.SavedCameras`), which it
    /// keeps mirrored. Wi-Fi passwords stay in the Keychain, untouched.
    static func camerasStore(_ defaults: UserDefaults = .standard) -> SavedCamerasStore {
        SavedCamerasStore(
            document: .userDefaults(defaults, key: "OpenPocketCine.Cameras"),
            legacy: .init(
                data: .userDefaults(defaults, key: "OpenPocketCine.SavedCameras"),
                codec: BodyRecordsV0(
                    integration: DJICameraSessionAdapter.integration, dates: .secondsSince2001),
                source: "OpenPocketCine.SavedCameras"))
    }

    /// Saved cameras, most recently connected first.
    var savedCameras: [SavedCamera] {
        cameras.saved.sorted {
            ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast)
        }
    }

    /// Asks before a saved hotspot connect (`CameraSession.confirmHotspot`); `false` cancels it.
    func askHotspot(_ network: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        answerHotspot(false)
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                hotspotQuestion = HotspotQuestion(
                    id: id, camera: hotspotCamera, network: network, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.hotspotQuestion?.id == id else { return }
                self?.answerHotspot(false)
            }
        }
    }

    /// The saved camera whose connect asks, by the name its card shows.
    private var hotspotCamera: String {
        for attempt in cameras.attempts.values {
            if case .saved(let camera, _) = attempt.target { return camera.displayName }
        }
        return "The camera"
    }

    func answerHotspot(_ connect: Bool) {
        let question = hotspotQuestion
        hotspotQuestion = nil
        question?.answer(connect)
    }
    @ObservationIgnored let watchRelay = WatchRelay()
    @ObservationIgnored private var watchRelayActivated = false
    /// The camera session and link the watch last showed. Watch presses are aimed at it, never
    /// at whatever `session` holds when the press lands (STATE-01).
    @ObservationIgnored private(set) var watchTarget: ControlTarget?
    @ObservationIgnored private(set) var watchCommandSource: DJICommandAdmission?
    /// The camera session this host shares with watchers; their commands are refused once the
    /// app holds another session. Link repairs of the same session keep it.
    @ObservationIgnored private(set) var relayTarget: ControlTarget?
    var multiviewExit: (() -> Void)?
    /// Live view-space X flip: TT180 extra-mirror XOR MIRROR assist.
    var livePictureViewFlip: Bool {
        GimbalStick.liveViewFlip(
            poseViewFlip: session.gimbalPoseViewFlip,
            assistMirror: assist.mirrorsHorizontally)
    }
    /// Operator tapped “Pair new camera” from the saved list.
    var isPairingNewCamera: Bool {
        get { shell.pairing }
        set { if newValue { shell.beginPairing() } else { shell.endPairing() } }
    }
    var showsLaunchSplash = true
    /// Long-press on the tap-focus box locks it: feed taps no longer move focus.
    var focusBoxLocked = false
    var assist = LiveAssistState()
    /// Decoded-frame scopes. Filled by `HevcDecoder.handleDecodedFrame` — not camera DUML.
    var frameSamples = LiveFrameSampleBus()
    @ObservationIgnored var inspectorPreview = MonitorInspectorImageRenderer()
    @ObservationIgnored let liveBackdrop = MonitorVideoBackdropRenderer()
    @ObservationIgnored let playbackBackdrop = MonitorVideoBackdropRenderer()
    /// Monitor tools follow the displayed source; watcher scopes must never read the camera bus.
    var monitorSamples: LiveFrameSampleBus { isWatchingFeed ? relayClient.samples : frameSamples }
    var monitorColorMode: ColorMode? {
        if isWatchingFeed { return relayClient.colorMode }
        if assist.gradesClip { return assist.monitorColorMode }
        return LiveMonitorColorScience.colorMode(
            isPhoto: session.status.isPhoto, colorMode: session.status.colorMode)
    }
    var monitorTransfer: MonitorTransfer? {
        if isWatchingFeed { return relayClient.transfer }
        if assist.gradesClip { return assist.monitorColorMode.map(MonitorTransfer.init) }
        return LiveMonitorColorScience.transfer(
            isPhoto: session.status.isPhoto, colorMode: session.status.colorMode)
    }

    /// Refresh LUT / decoder transfer on color or shooting-mode change. Skips watcher, clip, camera playback.
    func syncLiveMonitorColor() {
        guard !isWatchingFeed, !assist.gradesClip, !session.status.inPlayback else { return }
        let raw = session.status.colorMode
        let photo = session.status.isPhoto
        assist.syncLUT(
            to: raw,
            family: session.bodyFamily,
            cameraName: session.connectedCamera?.model.name,
            lookProfile: session.connectedCamera?.model.captureProfile?.looks ?? DJICameraLUTProfile.make(family: .pocket, cameraName: nil),
            isPhoto: photo)
        session.decoder.incomingColorMode = LiveMonitorColorScience.colorMode(
            isPhoto: photo, colorMode: raw)
    }
    /// The problem report sheet, owned by the app root (A2-24): the cameras page and Settings
    /// both open it here, so a draft outlives the camera session and the Settings cover.
    var isProblemReportPresented = false
    var captureSheet: CaptureSheet?
    var captureDrum: CaptureDrumPresentation?
    var keepScreenAwake: Bool = OperatorPrefs.keepScreenAwake {
        didSet { OperatorPrefs.keepScreenAwake = keepScreenAwake }
    }
    var hdrDisplay: Bool = OperatorPrefs.hdrDisplay {
        didSet {
            OperatorPrefs.hdrDisplay = hdrDisplay
            LiveHDRDisplay.app.setEnabled(hdrDisplay)
            LiveHDRDisplay.app.setScreenCaptured(screenCaptured)
        }
    }
    /// Screen recording / AirPlay. HDR present drops to SDR so the file is not boosted.
    var screenCaptured = false {
        didSet { LiveHDRDisplay.app.setScreenCaptured(screenCaptured) }
    }
    var hdrDisplayActive: Bool { hdrDisplay && !screenCaptured }
    var cacheFullResolution: Bool = OperatorPrefs.cacheFullResolution {
        didSet { OperatorPrefs.cacheFullResolution = cacheFullResolution }
    }
    var recordConfirmationEnabled: Bool = OperatorPrefs.recordConfirmationEnabled {
        didSet { OperatorPrefs.recordConfirmationEnabled = recordConfirmationEnabled }
    }
    var remoteShutterEnabled: Bool = OperatorPrefs.remoteShutterEnabled {
        didSet { OperatorPrefs.remoteShutterEnabled = remoteShutterEnabled }
    }
    var hapticsEnabled: Bool = OperatorPrefs.hapticsEnabled {
        didSet { OperatorPrefs.hapticsEnabled = hapticsEnabled }
    }
    var assistToolUsage: MonitorToolUsage = OperatorPrefs.assistToolUsage {
        didSet { OperatorPrefs.assistToolUsage = assistToolUsage }
    }
    var headTrackingEnabled: Bool = OperatorPrefs.headTrackingEnabled {
        didSet { OperatorPrefs.headTrackingEnabled = headTrackingEnabled }
    }
    /// A manual mode selection takes control back from the AirPods stream.
    func setGimbalMode(_ mode: GimbalMode) {
        guard session.gimbal.canSetConfiguration else { return }
        headTrackingEnabled = false
        session.gimbal.setMode(mode)
    }

    /// Live SET / STOP chip. SET starts tracking and locks forward; STOP ends it.
    var headTrackControlTitle = HeadphoneMotionBridge.calibrateTitle
    /// Raw AirPods attitude / gyro / SET-relative look. Empty when Head Tracking is off.
    var headTrackImuReadout = ""
    /// SET-relative (or first-sample) yaw/pitch for the live axis rings. `nil` without IMU.
    var headTrackAxisPose: HeadTrackAxisPose?
    /// On-screen gimbal stick is thrown. Head tracking yields.
    var gimbalScreenHeld = false
    /// Gamepad left stick is thrown. Head tracking yields.
    var gimbalPadHeld = false
    var gimbalAnalogHeld: Bool { gimbalScreenHeld || gimbalPadHeld }
    /// Extended gamepad is bound. Toast on rising/falling edge.
    var gamepadConnected = false
    var liveGimbalPanel: LiveGimbalPanel = .none
    /// Canvas-space centre of the programmed-move editor / Run pill. Nil until the operator drags it.
    var gimbalFloatCenter: CGPoint?
    /// Canvas-space centre of the programmed-move debug plate.
    var gimbalDoubleTap: GimbalDoubleTap = OperatorPrefs.gimbalDoubleTap {
        didSet {
            OperatorPrefs.gimbalDoubleTap = gimbalDoubleTap
            session.gimbalDoubleTap = gimbalDoubleTap
        }
    }
    var gimbalRamp: GimbalRamp = OperatorPrefs.gimbalRamp {
        didSet {
            OperatorPrefs.gimbalRamp = gimbalRamp
            session.gimbalRamp = gimbalRamp
        }
    }
    var gimbalStickSensitivity: Int = OperatorPrefs.gimbalStickSensitivity {
        didSet {
            let clamped = GimbalStick.clampedSensitivity(gimbalStickSensitivity)
            if clamped != gimbalStickSensitivity {
                gimbalStickSensitivity = clamped
                return
            }
            OperatorPrefs.gimbalStickSensitivity = clamped
        }
    }
    var virtualJoystickInvertPan: Bool = OperatorPrefs.virtualJoystickInvertPan {
        didSet { OperatorPrefs.virtualJoystickInvertPan = virtualJoystickInvertPan }
    }
    var virtualJoystickInvertTilt: Bool = OperatorPrefs.virtualJoystickInvertTilt {
        didSet { OperatorPrefs.virtualJoystickInvertTilt = virtualJoystickInvertTilt }
    }
    var virtualJoystickDeadzonePercent: Int = OperatorPrefs.virtualJoystickDeadzonePercent {
        didSet {
            let clamped = GimbalStick.clampedDeadzonePercent(virtualJoystickDeadzonePercent)
            if clamped != virtualJoystickDeadzonePercent {
                virtualJoystickDeadzonePercent = clamped
                return
            }
            OperatorPrefs.virtualJoystickDeadzonePercent = clamped
        }
    }
    var virtualJoystickResponseCurve: GimbalStick.ResponseCurve =
        OperatorPrefs.virtualJoystickResponseCurve
    {
        didSet { OperatorPrefs.virtualJoystickResponseCurve = virtualJoystickResponseCurve }
    }
    var virtualJoystickSize: MonitorJoystickSize = OperatorPrefs.virtualJoystickSize {
        didSet { OperatorPrefs.virtualJoystickSize = virtualJoystickSize }
    }
    var virtualJoystickMapping: GimbalStick.Mapping {
        GimbalStick.Mapping(
            invertPan: virtualJoystickInvertPan,
            invertTilt: virtualJoystickInvertTilt,
            deadzone: GimbalStick.deadzoneFromPercent(virtualJoystickDeadzonePercent),
            curve: virtualJoystickResponseCurve)
    }
    @ObservationIgnored lazy var operatorSession = MonitorOperatorSessionModel(
        shell: shell, assist: assist, display: OperatorPrefs.display)
    var dispLive: MonitorDisplayChrome {
        get { operatorSession.live }
        set { operatorSession.live = newValue }
    }
    var dispClean: MonitorDisplayChrome {
        get { operatorSession.clean }
        set { operatorSession.clean = newValue }
    }
    var operatorSettingsTab: MonitorSettingsTab {
        get { operatorSession.settingsTab }
        set { operatorSession.settingsTab = newValue }
    }
    var chromeEditorMode: MonitorDisplayMode? {
        get { operatorSession.editingMode }
        set { operatorSession.editingMode = newValue }
    }
    var chromeEditorReturnMode: MonitorDisplayMode? {
        get { operatorSession.returnedMode }
        set { operatorSession.returnedMode = newValue }
    }
    var liveChromeInteractive: Bool { operatorSession.interactive }
    var portraitFeedAspect: PortraitFeedAspect = OperatorPrefs.portraitFeedAspect {
        didSet { OperatorPrefs.portraitFeedAspect = portraitFeedAspect }
    }
    var nativeISOHopEnabled: Bool = OperatorPrefs.nativeISOHopEnabled {
        didSet { OperatorPrefs.nativeISOHopEnabled = nativeISOHopEnabled }
    }
    var facePriorityExposureEnabled: Bool = OperatorPrefs.facePriorityExposureEnabled {
        didSet {
            OperatorPrefs.facePriorityExposureEnabled = facePriorityExposureEnabled
            session.setFacePriorityEnabled(facePriorityExposureEnabled)
        }
    }
    var portraitRailExpanded = false
    /// The app-scoped delivery owner: runs survive leaving the gallery or the player.
    let delivery = MonitorDeliveryCoordinator()
    let frameio = FrameioAccountModel(namespace: .openPocketCine)
    /// The Settings account operation, owned here so a settings rehost keeps an accepted sign-in.
    @ObservationIgnored let settingsAccount = MonitorSettingsAccountModel()
    /// The Settings support operations (reports and browser links), kept across a settings rehost.
    @ObservationIgnored let settingsSupport = MonitorSettingsSupportModel()
    /// Settings browser links through the one internet hop; the root reports background and return.
    @ObservationIgnored lazy var browserHandoff = MonitorBrowserInternetHandoff(hop: internetHop)
    var relayHost = WatcherRelayHost(
        versionMismatchReason: WatcherRelayJoin.versionMismatchReason,
        logSubsystem: "com.opencapture.openpocketcine", journal: { ControlLiveLog.line($0) })
    @ObservationIgnored private var relaySource: UUID?
    @ObservationIgnored private var relaySessionID: CameraSessionID?
    private var admitsRelaySource: Bool {
        shareThisFeed && relaySource != nil && relaySource == shell.monitor?.id
            && relaySessionID != nil && relaySessionID == shell.monitor?.session.id
            && relaySessionID == shell.control.session?.id
    }
    var relayBrowser = WatcherRelayBrowser()
    var relayClient = WatcherRelayClient()
    var isWatchingFeed = false
    var showsWatcherBrowse = false
    var shareThisFeed: Bool = OperatorPrefs.shareThisFeed
    var sharePasscode: String = WatcherRelayKeychain.app.hostPasscode
    var controlRequestsAllowed: Bool = OperatorPrefs.controlRequests {
        didSet { OperatorPrefs.controlRequests = controlRequestsAllowed }
    }
    var broadcastPriority: Int = OperatorPrefs.broadcastPriority {
        didSet {
            OperatorPrefs.broadcastPriority = broadcastPriority
            relayHost.setCeiling(broadcastPriority)
        }
    }
    var watcherRecordConfirm = false
    var watcherRecordRequest: RecordConfirmationContext?
    var watcherRecordDelivery: WatcherRelayCommandDelivery?
    @ObservationIgnored var watcherRecordAdmission: DJICommandAdmission?
    var admitsWatcherRecordDelivery: Bool {
        guard let delivery = watcherRecordDelivery, admitsRelaySource,
            watcherRecordAdmission?.admits(session.commandOwner) == true
        else { return false }
        return relayHost.admits(delivery)
    }
    var watcherRecordContext: RecordConfirmationContext {
        RecordConfirmationContext(
            mode: session.status.shootingMode, recording: session.status.isRecording,
            locked: session.isLocked, busy: session.controlBusy, phase: session.phase,
            target: session.control.target)
    }
    /// The one internet hop off the camera's Wi-Fi (A2-16): the DJI joiner leaves and rejoins,
    /// and only the session that left is ever rejoined.
    @ObservationIgnored lazy var internetHop = MonitorInternetHop<PocketHopRoute>(
        port: .init(
            onCameraNetwork: { DjiAppleWiFiJoiner.isCameraPathReady() },
            leave: { route, current in
                if let ssid = route.ssid { route.session.leaveCameraNetwork(ssid: ssid, isCurrent: current) }
                return route
            },
            admitsReturn: { [weak self] route in
                guard let self else { return false }
                return self.session === route.session && route.session.control.id == route.sessionID
            },
            rejoin: { route, current in await route.session.rejoinSoftAPAfterInternetHop(isCurrent: current) }))

    var isOnCameraAccessPoint: Bool { internetHop.onCameraNetwork }

    /// Settings reports and browser links (A2-22): the report is this app's diagnostic file, and a
    /// page opened on the camera's Wi-Fi asks, then leaves through the one internet hop.
    var settingsSupportActions: MonitorSettingsSupportActions {
        .init(
            identity: ObjectIdentifier(self), isCurrent: { [weak self] in self != nil },
            requiresInternetConsent: isOnCameraAccessPoint,
            makeReport: { [weak self] in
                guard let self, let url = DiagnosticCenter.shared.writeReport(session: self.session) else {
                    throw MonitorSettingsReportUnavailable(supportEmail: "support@openpocketcine.app")
                }
                return url
            },
            prepareBrowser: { [weak self] admission in
                guard let self else { return nil }
                return await self.browserHandoff.prepare(route: self.hopRoute, admission: admission)
            },
            open: { await UIApplication.shared.open($0) },
            internetFailure: MonitorSettingsCopy.browserInternetFailure(app: "OpenPocketCine"))
    }

    /// Frame.io sign-in from Settings: on the camera's Wi-Fi it asks, then leaves through the one
    /// internet hop and comes back (A2-23).
    var settingsAccountActions: MonitorSettingsAccountActions {
        frameio.settingsActions(
            hop: internetHop, route: { [weak self] in self?.hopRoute },
            internetFailure: MonitorSettingsCopy.accountInternetFailure)
    }

    /// Where a hop leaves from: the current session and the camera network it joined.
    var hopRoute: PocketHopRoute {
        PocketHopRoute(
            session: session, sessionID: session.control.id,
            ssid: session.joinedSSID ?? session.cachedSSID)
    }

    var currentDispMode: MonitorDisplayMode { operatorSession.mode }
    var dispChrome: MonitorDisplayChrome { operatorSession.chrome }
    var isEditingChrome: Bool { operatorSession.isEditing }

    func chrome(for mode: MonitorDisplayMode) -> MonitorDisplayChrome { operatorSession.chrome(for: mode) }

    func chromeSectionMounts(_ section: MonitorDisplayChrome.Section) -> Bool {
        return operatorSession.mounts(section)
    }

    func toggleChrome(_ section: MonitorDisplayChrome.Section, for mode: MonitorDisplayMode) {
        operatorSession.toggle(section, in: mode)
    }

    func beginChromeEditing(_ mode: MonitorDisplayMode) {
        liveGimbalPanel = .none
        operatorSession.beginEditing(mode)
    }

    func endChromeEditing() { operatorSession.finishEditing() }

    /// The pair page: no saved camera yet, or the operator chose Pair.
    var shouldShowWizard: Bool { shell.route == .pair }

    var isLive: Bool { shell.monitor != nil }

    func prepareStartup() {
        #if targetEnvironment(simulator)
            if MonitorUIReview.isActive {
                MonitorUIReview.prepare(self)
                return
            }
            presentSimulatorPreview()
        #endif
        LiveHDRDisplay.app.setEnabled(hdrDisplay)
    }

    /// Connects a saved camera over its preferred setup (debug and stress drivers).
    func reconnect(_ camera: SavedCamera) { cameras.connect(camera) }

    /// Add setup's camera scan, or `nil` when the camera is not nearby. Stamped first: the scan
    /// moves the camera to station role, so a lost reset is repaired by the next Camera Wi-Fi
    /// connect.
    func networkScan(_ camera: SavedCamera) -> (
        (@escaping @MainActor (String) -> Void) async throws -> Void
    )? {
        guard let found = session.found.first(where: { $0.id.uuidString == camera.id }) else {
            return nil
        }
        return { [weak self] onFound in
            if let self, let current = self.cameras.saved.first(where: { $0.id == camera.id }) {
                self.cameras.upsert(
                    DJIIntegration.stamping(current, movingTo: .infrastructureNetwork))
            }
            try await MultiviewProvisioner.scanNetworks(found, onFound: onFound)
        }
    }

    /// The Multiview stage takes the radio: the single-camera session lets go of it until the
    /// stage closes (`closeMultiview`).
    func openMultiview() {
        guard cameras.attempts.isEmpty else { return }
        disconnect()
    }

    func closeMultiview() {
        if cameras.connected == nil { session.startScan() }
    }

    /// Connect shows the monitor — never leftover Operator Setup, Media, or Edit view.
    func setShareThisFeed(_ on: Bool) {
        guard !session.isMultiviewBorrowed else { return }
        shareThisFeed = on
        OperatorPrefs.shareThisFeed = on
        if on {
            startRelayHost()
        } else {
            relaySource = nil
            relaySessionID = nil
            watcherRecordDelivery = nil
            watcherRecordAdmission = nil
            watcherRecordConfirm = false
            relayHost.stop()
            session.decoder.onIdentityFrame = nil
            session.decoder.onIdentityOrientation = nil
        }
    }

    func startRelayHost() {
        guard isLive, shareThisFeed, !session.isMultiviewBorrowed else { return }
        // An empty shown passcode may only mean the Keychain was locked at launch: ask it again,
        // and never broadcast unprotected while it cannot answer.
        if sharePasscode.isEmpty {
            guard let stored = WatcherRelayKeychain.app.hostPasscodeLookup().usableValue else {
                shareThisFeed = false
                OperatorPrefs.shareThisFeed = false
                session.controlNote = "Sharing could not start"
                return
            }
            sharePasscode = stored
        }
        let name = UIDevice.current.name
        let camera = session.connectedCamera?.name ?? ""
        relaySource = shell.monitor?.id
        relaySessionID = shell.monitor?.session.id
        relayHost.onCommand = { [weak self] delivery in self?.handleWatcherRelayCommand(delivery) }
        relayHost.start(
            hostName: name,
            cameraName: camera,
            passcode: sharePasscode,
            ceilingIndex: broadcastPriority,
            allowsControl: controlRequestsAllowed)
        if relayHost.encoderFailed {
            shareThisFeed = false
            OperatorPrefs.shareThisFeed = false
            session.controlNote = "Sharing could not start"
            return
        }
        relayTarget = session.control.target
        session.decoder.onIdentityOrientation = relayHost.orientationSink()
        session.decoder.onIdentityOrientation?(session.decoder.presentedPictureFlip ?? false)
        session.decoder.onIdentityFrame = relayHost.frameSink()
        relayHost.pollState({ [weak self] in self?.relayState() }, onFailure: { [weak self] in
            self?.setShareThisFeed(false)
            self?.session.controlNote = "Sharing could not start"
        })
    }

    private func relayState() -> WatcherRelayState? {
        guard admitsRelaySource else { return nil }
        let s = session.status
        let state = WatcherRelayState(
            isRecording: s.isRecording,
            format: s.videoResolution?.label ?? "",
            color: (s.isPhoto ? ColorMode.normal : s.colorMode)?.label ?? "",
            zoom: CamFov.displayLabel(factor: session.zoomReadout),
            liveFPS: session.liveFPS,
            batteryPercent: s.batteryPercent,
            cameraName: session.connectedCamera?.name ?? "",
            iso: s.isoIndex?.label ?? "\(s.iso)",
            shutter: s.shutterDenom > 0 ? "1/\(s.shutterDenom)" : "",
            allowsControlRequests: controlRequestsAllowed,
            controlOptions: .init(
                isoIndices: s.availableIsoIndices.map { Int($0.rawValue) },
                shutterDenominators: CamCapShutter.wheelDenoms(
                    available: s.availableShutterDenoms, current: s.shutterDenom),
                zoomHundredths: session.zoomStops.map { Int(($0 * 100).rounded()) }),
            cameraModel: session.connectedCamera?.model.name,
            isNano: session.bodyFamily == .nano,
            batteryReading: control.snapshot?.power.batteryReading,
            batteryExhausted: control.snapshot?.power.exhausted.value)
        return state
    }

    func handleWatcherRelayCommand(_ delivery: WatcherRelayCommandDelivery) {
        guard admitsRelaySource, relayHost.admits(delivery) else { return }
        let allowed = delivery.command
        // Watchers command the camera this host shares, not a session swapped in since.
        guard let relayTarget, session.control.target.isSameSession(as: relayTarget) else {
            return
        }
        guard let owner = session.commandOwner else { return }
        let admission = DJICommandAdmission(
            owner: owner, isCurrent: relayHost.capturedCommandAdmission(for: delivery))
        guard admission.isCurrent else { return }
        switch allowed {
        case .toggleRecording:
            guard !session.isLocked, !session.controlBusy else { return }
            if recordConfirmationEnabled, !session.status.isPhoto {
                watcherRecordRequest = watcherRecordContext
                watcherRecordDelivery = delivery
                watcherRecordAdmission = admission
                watcherRecordConfirm = true
            } else {
                session.control.shutter(admission: admission)
            }
        case .tapFocus(let x, let y, let w, let h):
            let nx = w > 0 ? Double(x) / Double(w) : 0.5
            let ny = h > 0 ? Double(y) / Double(h) : 0.5
            session.markFocus(at: CGPoint(x: nx, y: ny), admission: admission)
        case .setISO(let raw):
            if let idx = IsoIndex(rawValue: UInt8(clamping: raw)) {
                session.control.setISO(idx, admission: admission)
            }
        case .setShutterDenom(let denom):
            session.setShutterDenom(denom, admission: admission)
        case .setWhiteBalance(let mode, let kelvin, let tint):
            if mode == 0 {
                session.control.setWhiteBalanceAuto(tint: tint, admission: admission)
            } else {
                session.control.setWhiteBalanceCustom(kelvin: kelvin, tint: tint, admission: admission)
            }
        case .setColor(let raw):
            if let mode = ColorMode(rawValue: UInt8(clamping: raw)) {
                session.setColorMode(mode, admission: admission)
            }
        case .setZoom(let hundredths):
            session.setZoom(Double(hundredths) / 100.0, admission: admission)
        }
    }

    func confirmWatcherRecording() {
        guard let approved = watcherRecordRequest,
            approved == watcherRecordContext, admitsWatcherRecordDelivery, approved.canConfirm,
            let admission = watcherRecordAdmission
        else { return }
        watcherRecordRequest = nil
        watcherRecordDelivery = nil
        watcherRecordAdmission = nil
        session.control.record(start: !approved.recording, aimedAt: approved.target, admission: admission)
    }

    func noteBecameLive() {
        operatorSession.synchronize(source: shell.monitor?.id)
        captureSheet = nil
        if shareThisFeed { startRelayHost() }
        relayBrowser.stop()
    }

    /// A dropped link must not keep Operator Setup or Edit view around for the next connect.
    func noteLeftLive() {
        operatorSession.close()
        captureSheet = nil
        watchRelay.retireSource()
        watchTarget = nil
        watchCommandSource = nil
        relaySource = nil
        relaySessionID = nil
        watcherRecordDelivery = nil
        watcherRecordAdmission = nil
        relayHost.stop()
        relayTarget = nil
        session.decoder.onIdentityFrame = nil
        session.decoder.onIdentityOrientation = nil
        watcherRecordConfirm = false
    }

    func beginMediaBrowse() { session.beginMediaBrowse() }
    func endMediaBrowse() { session.endMediaBrowse() }
    func refreshMedia() { Task { await session.refreshMedia() } }

    func disconnect() {
        focusBoxLocked = false
        if shell.monitor != nil { shell.close() } else { session.disconnect() }
    }

    /// Recovery card: leave the held frame for the saved-camera list.
    func exitMonitorToOperatorMenu() {
        session.cancelSessionRecovery()
        disconnect()
    }

    /// A feed swipe jumps to a mode through the display owner (refused while locked); it does not cycle.
    func setDisplayMode(clean: Bool) {
        operatorSession.select(clean ? .clean : .live)
    }

    func activateWatchRelay() {
        guard !watchRelayActivated else { return }
        watchRelayActivated = true
        watchRelay.onToggleRecord = { [weak self] in
            self?.watchToggleRecord()
                ?? WatchCommandResult(
                    accepted: false, isRecording: false, error: WatchRelayCopy.connectFirst)
        }
        watchRelay.onCapture = { [weak self] in
            self?.watchCapture()
                ?? WatchCommandResult(
                    accepted: false, isRecording: false, error: WatchRelayCopy.connectFirst)
        }
        watchRelay.onAdmittedToggleRecord = { [weak self] admission in
            self?.watchShutter(photo: false, watchAdmission: admission)
                ?? WatchCommandResult(
                    accepted: false, isRecording: false, error: WatchRelayCopy.connectFirst)
        }
        watchRelay.onAdmittedCapture = { [weak self] admission in
            self?.watchShutter(photo: true, watchAdmission: admission)
                ?? WatchCommandResult(
                    accepted: false, isRecording: false, error: WatchRelayCopy.connectFirst)
        }
        watchRelay.onReachabilityChanged = { [weak self] in
            guard let self else { return }
            self.session.decoder.needsWatchPreview = self.watchRelay.hasCompanion
            self.publishWatchState()
        }
        session.decoder.needsWatchPreview = watchRelay.hasCompanion
        session.decoder.onWatchPreview = { [weak self] image, source, unmanaged in
            guard let self else { return }
            self.watchRelay.ingestPreview(
                image, source: source, unmanaged: unmanaged,
                mirrored: self.session.decoder.presentedPictureFlip ?? false,
                flippedVertically: self.assist.flipsVertically,
                timecode: self.liveStatus.clock,
                isRecording: self.session.status.isRecording)
        }
        session.onChromePublished = { [weak self] in
            self?.publishWatchState()
        }
        watchRelay.activate()
        publishWatchState()
    }

    func publishWatchState() {
        let target = session.control.target
        let commandSource = session.commandOwner.map {
            DJICommandAdmission(owner: $0, isCurrent: { true })
        }
        if watchTarget != target || watchCommandSource?.source != commandSource?.source
            || watchCommandSource?.owner !== commandSource?.owner
        {
            watchRelay.retireSource()
        }
        watchTarget = target
        watchCommandSource = commandSource
        watchRelay.ingestState(
            WatchRelayState.snapshot(
                status: session.status,
                timecode: liveStatus.clock,
                phase: session.phase,
                cameraName: session.connectedCamera?.name ?? "",
                feedLive: session.decoder.lastPresentedAt != nil,
                power: control.snapshot?.power ?? .unknown,
                storage: control.snapshot?.storage ?? .unknown))
    }

    // MARK: Remote shutter (A2-32)

    /// The live monitor is up front: no Settings or Media cover, no legal page and not watching a
    /// shared feed. Anywhere else the volume keys behave normally.
    var remoteShutterLiveViewFront: Bool {
        shell.monitor != nil && shell.cover == nil && !isWatchingFeed
    }

    /// One remote press toggles recording like the Record button, without the phone-side
    /// confirmation (an unseen dialog would strand the take), as on OpenZCine. The shared owner has
    /// already debounced it; an unknown or pending record state sends nothing.
    func remoteShutterRecord() {
        guard !operatorSession.locked, !session.isLocked, !session.controlBusy, !session.status.isPhoto else { return }
        control.record(start: nil)
    }

    func watchToggleRecord() -> WatchCommandResult {
        watchShutter(photo: false)
    }

    func watchCapture() -> WatchCommandResult {
        watchShutter(photo: true)
    }

    private func watchShutter(photo: Bool) -> WatchCommandResult {
        watchShutter(photo: photo, watchAdmission: nil)
    }

    private func watchShutter(photo: Bool, watchAdmission: RelayWatchCommandAdmission?)
        -> WatchCommandResult
    {
        let result = WatchCommandPolicy.answer(
            photo ? .capture : .toggleRecord,
            facts: {
                WatchCommandFacts(
                    isRecording: session.status.isRecording,
                    isBusy: session.controlBusy || session.isBrowsingMedia,
                    isLive: session.phase == .live, isPhotography: session.status.isPhoto)
            },
            shutter: {
                // Keep the target and supplied first-send admission captured by the shown source.
                guard let target = watchTarget else { return .targetChanged }
                // The phone's interface lock guards touches on the phone, not the wrist remote
                // (pre-shared behavior; the Z and Insta Watch paths agree).
                guard session.controlLinkReady else { return .notSent }
                let receipt: CommandReceipt?
                if let watchAdmission {
                    guard watchAdmission.isCurrent, let shown = watchCommandSource,
                        shown.admits(session.commandOwner)
                    else { return .targetChanged }
                    let admission = DJICommandAdmission(
                        owner: shown.owner,
                        isCurrent: { shown.isCurrent && watchAdmission.isCurrent })
                    receipt = session.control.shutter(aimedAt: target, admission: admission)
                } else {
                    receipt = session.control.shutter(aimedAt: target)
                }
                if let receipt {
                    if receipt.didNotAct {
                        return receipt.targetChanged ? .targetChanged : .notSent
                    }
                    return .sent
                }
                // The legacy photo port returns Void. Its queued operation owns controlBusy;
                // a refused photo clears it, so nil alone is never evidence of submission.
                return photo && session.controlBusy ? .sent : .notSent
            })
        publishWatchState()
        return result
    }
}

struct AppRoot: View {
    @State private var model = AppModel(connects: true)
    @State private var startup: MonitorAppStartup

    init(startup: MonitorAppStartup? = nil) {
        _startup = State(
            initialValue: startup
                ?? MonitorAppStartup(
                    reports: .init(
                        reporting: AppDiagnostics.reporting,
                        tick: { AppDiagnostics.problemReporting.tick() })))
    }
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder private var primaryExperience: some View {
        if model.showsWatcherMonitor {
            WatcherLiveView()
                .environment(model)
                .transition(.opacity)
        } else {
            LinkExperience()
                .environment(model)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    var body: some View {
        ZStack {
            MonitorTheme.background.ignoresSafeArea()
            primaryExperience

            if model.showsLaunchSplash {
                LaunchSplashOverlay(isVisible: Bindable(model).showsLaunchSplash)
                    .transition(.opacity)
                    .zIndex(100)
            }

            if model.showsWatcherBrowse, !model.isLive {
                MonitorTheme.background
                    .ignoresSafeArea()
                    .overlay {
                        WatcherBrowseView()
                            .environment(model)
                    }
                    .zIndex(90)
            }
        }
        .environment(model)
        .environment(\.font, MonitorTheme.font(16))
        .monitorHDRDisplay(.app, active: model.hdrDisplayActive, screenCaptured: Bindable(model).screenCaptured)
        .preferredColorScheme(.dark)
        .monitorAppStartup(startup, splashVisible: Bindable(model).showsLaunchSplash) { choice in
            ReliabilityConsentPrompt(onChoice: choice).environment(model)
        }
        .onAppear {
            #if DEBUG
                // Physical consent review uses an isolated preference domain;
                // the operator's saved choice is never overwritten.
                if let reviewID = ProcessInfo.processInfo.environment["OPV_CONSENT_REVIEW_ID"],
                    UUID(uuidString: reviewID) != nil
                {
                    AppDiagnostics.consent.defaults = UserDefaults(
                        suiteName: "opc.consent.review.\(reviewID)")!
                }
            #endif
            DiagnosticCenter.shared.install()
            AppModelDiagnosticsAnchor.model = model
            DiagnosticCenter.shared.onCopiedForTestFlight = { [weak model] in
                model?.session.controlNote =
                    "Diagnostics copied — paste into TestFlight feedback"
            }
            model.prepareStartup()
            model.activateWatchRelay()
        }
        .onChange(of: model.relayClient.status) { _, status in
            model.noteWatcherStatusChanged(status)
        }
        .monitorScreenWake(enabled: model.keepScreenAwake)
        .monitorRemoteShutter(enabled: model.remoteShutterEnabled,
            liveViewFront: model.remoteShutterLiveViewFront, subsystem: "OpenPocketCine") { model.remoteShutterRecord() }
        .onChange(of: model.gimbalAnalogHeld) { _, held in
            if held { model.relayHost.reclaimControl() }
        }
        .onChange(of: model.shell.monitor?.id) { _, id in
            if id != nil {
                model.noteBecameLive()
            } else {
                model.noteLeftLive()
            }
        }
        .modifier(WatcherRecordConfirmation(model: model))
        .monitorRelayControlRequest(model.relayHost.pendingControlRequest.map { request in
            .init(name: request.name, help: "",
                decline: { model.relayHost.denyControl() },
                grant: { model.relayHost.grantControl() })
        })
        .onAppear { model.assist.inspectorSceneActive = scenePhase == .active }
        .monitorShellSceneActivity(model.shell)
        .monitorBrowserHandoffReturn(model.browserHandoff)
    }
}

/// Watcher record confirmation reads `CameraStatus` in its own scope. On the
/// app root, every 5 Hz status publish re-evaluated the whole root body.
private struct WatcherRecordConfirmation: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                model.session.status.isRecording ? "Stop recording?" : "Start recording?",
                isPresented: $model.watcherRecordConfirm,
                titleVisibility: .visible
            ) {
                Button(
                    model.session.status.isRecording ? "Stop" : "Start",
                    role: model.session.status.isRecording ? .destructive : nil
                ) {
                    model.confirmWatcherRecording()
                }
                Button("Cancel", role: .cancel) {
                    model.watcherRecordRequest = nil
                    model.watcherRecordDelivery = nil
                    model.watcherRecordAdmission = nil
                }
            }
            .onChange(of: model.watcherRecordContext) { _, _ in
                model.watcherRecordConfirm = false
                model.watcherRecordRequest = nil
                model.watcherRecordDelivery = nil
                model.watcherRecordAdmission = nil
            }
    }
}

/// A saved hotspot connect waiting on the operator (Personal Hotspot is not reported on).
struct HotspotQuestion {
    let id: UUID
    /// The camera that joins the hotspot, by its card name.
    let camera: String
    let network: String
    fileprivate let continuation: CheckedContinuation<Bool, Never>
    /// The operator went to Settings: ask again when the app is back.
    var reaskOnReturn = false

    func answer(_ connect: Bool) { continuation.resume(returning: connect) }
}

/// Connection home on the shared OpenCine screens (SHELL-02): the pair page while no camera is
/// saved or the operator chose Pair, else the cameras page with the Multiview entry. Mirrors
/// OpenZCine `LinkExperience`.
struct LinkExperience: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var diagnostics: MonitorDiagnosticsShareItem?
    @State private var diagnosticsFailure: String?
    @State private var showMultiview = false
    @State private var reviewAddSetup: SavedCamera?

    var body: some View {
        AppShell(
            model: model.shell, brand: ShellBrand(name: "OpenPocketCine"),
            actions: ShellActions(
                diagnostics: {
                    switch DiagnosticCenter.shared.beginShare(session: model.session) {
                    case .ready(let item): diagnostics = item
                    case .failed(let message): diagnosticsFailure = message
                    }
                }, reportProblem: { model.isProblemReportPresented = true },
                watchFeed: {
                    if model.cameras.attempts.isEmpty { model.openWatcherBrowse() }
                },
                multiview: MultiviewQualificationPolicy.tileCount > 1
                    ? {
                        guard model.cameras.attempts.isEmpty else { return }
                        model.openMultiview()
                        showMultiview = true
                    } : nil,
                // Pair on a nearby card connects it at once, on the pair page.
                pair: {
                    model.shell.beginPairing()
                    if let sighting = model.cameras.nearby.first(where: { $0.id == model.cameras.selection }) {
                        model.cameras.connect(sighting)
                    }
                }),
            pairingFlow: model.pairingWizard().flow(
                model.cameras, onDone: { model.shell.endPairing() }, rescan: { model.session.startScan() }),
            coverPresentation: .shell
        ) { _ in
            LiveViewScreen()
        } page: { cover in
            ShellCoverPage(cover: cover)
        }
        .onChange(of: model.shell.cover) { old, next in
            if old == .media, next != .media { model.session.endMediaBrowse() }
        }
        .ignoresSafeArea()
        .overlay { MonitorOperatorDeliveryChrome(model: model.delivery.lifetime, scope: .root, remoteDisplayName: "Frame.io") }
        // The app's one share sheet, above any gallery, player or photo cover (A2-52).
        .monitorDeliverySharePresenter(model.delivery.lifetime)
        .background(StartupColors.background.ignoresSafeArea())
        .foregroundStyle(StartupColors.ink)
        .onAppear {
            #if targetEnvironment(simulator)
                switch MonitorUIReview.state {
                case "add-setup": reviewAddSetup = model.savedCameras.first
                case "multiview": showMultiview = true
                default: break
                }
            #endif
        }
        .sheet(item: $diagnostics) { item in MonitorActivityShareSheet(items: [item.url]) }
        .alert(
            "Couldn't write the diagnostics report",
            isPresented: Binding(
                get: { diagnosticsFailure != nil }, set: { if !$0 { diagnosticsFailure = nil } })
        ) {
            Button("OK", role: .cancel) { diagnosticsFailure = nil }
        } message: {
            Text(diagnosticsFailure ?? "")
        }
        // The app's one problem report, above every cover: a draft opened from Settings
        // survives the camera session ending and the cover closing (A2-24).
        .sheet(isPresented: Bindable(model).isProblemReportPresented) { ProblemReportView().environment(model) }
        // Simulator review only: the add-route slot as the cameras page presents it.
        .sheet(item: $reviewAddSetup) { camera in
            AddSetupView(camera: camera) { _ in reviewAddSetup = nil }
        }
        .fullScreenCover(
            isPresented: $showMultiview, onDismiss: { model.closeMultiview() },
            content: { MultiviewView() }
        )
        .alert(
            "Turn on Personal Hotspot",
            isPresented: Binding(
                get: { model.hotspotQuestion.map { !$0.reaskOnReturn } ?? false },
                set: {
                    if !$0, model.hotspotQuestion?.reaskOnReturn == false {
                        model.answerHotspot(false)
                    }
                }),
            presenting: model.hotspotQuestion
        ) { _ in
            Button("Open Settings") {
                model.hotspotQuestion?.reaskOnReturn = true
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Connect") { model.answerHotspot(true) }
            Button("Cancel", role: .cancel) { model.answerHotspot(false) }
        } message: { question in
            Text(
                "\(question.camera) joins this iPhone’s hotspot “\(question.network)”. Turn on Personal Hotspot and Allow Others to Join (Settings or Control Center), then tap Connect."
            )
        }
        .onChange(of: model.session.phase) { _, phase in
            if phase == .openingDatalink { LocalVPNNotice.app.noteIfActive() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Back from Settings: offer Connect again rather than guessing the hotspot is on.
            model.hotspotQuestion?.reaskOnReturn = false
            #if targetEnvironment(simulator)
                if MonitorUIReview.isActive { return }
            #endif
            // Back from Settings after Bluetooth was off or not allowed: look again.
            if case .failed = model.session.phase, model.cameras.attempts.isEmpty,
                model.cameras.connected == nil
            {
                model.session.startScan()
            }
        }
    }

}

extension LiveHDRDisplay {
    /// This app's HDR display state, read by the feed, scopes and chrome.
    static let app = LiveHDRDisplay()
}
