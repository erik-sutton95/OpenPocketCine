import CoreVideo
import MonitorPresentation
import MonitorUI
import Observation
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineCore
import OpenCineFrameIO
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
                            addRoute: { camera, done in
                                AnyView(AddSetupView(camera: camera, done: done))
                            },
                            nearbyCard: { [weak session] camera in
                                Self.nearbyCard(
                                    camera,
                                    verified: session?.found.first { $0.id.uuidString == camera.id }?.model.verified)
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
    /// Legal documents are app-owned. Settings and media have one shared cover state.
    private var legalPanel: AppPanel?
    var homePanel: AppPanel? {
        get {
            if let legalPanel { return legalPanel }
            guard shell.monitor == nil else { return nil }
            return shell.cover.map { $0 == .settings ? .settings : .media }
        }
        set {
            switch newValue {
            case .settings:
                legalPanel = nil
                shell.open(.settings)
            case .media:
                legalPanel = nil
                shell.open(.media)
            case nil:
                legalPanel = nil
                shell.dismissCover()
            default: legalPanel = newValue
            }
        }
    }
    var showsLegalPanel: Bool { legalPanel != nil }
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
    var frameioConnecting = false
    var frameioUser: FrameioUser?
    var delivery = MediaDeliveryCoordinator()
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
    /// Once accepted, transport failure belongs on the watcher screen until explicit Leave.
    var showsWatcherMonitor: Bool { isWatchingFeed }

    func noteWatcherStatusChanged(_ status: WatcherRelayClientStatus) {
        if status == .needsPasscode, isWatchingFeed {
            isWatchingFeed = false
            showsWatcherBrowse = true
            startWatcherBrowse()
        }
        if status == .live, showsWatcherBrowse {
            isWatchingFeed = true
            showsWatcherBrowse = false
            homePanel = nil
        }
    }

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
    @ObservationIgnored private var internetHopState = FrameioInternetHop()
    @ObservationIgnored private var internetHopRevision: UInt64 = 0
    @ObservationIgnored private var internetHopNotifying = false
    var internetHop: FrameioInternetHop {
        get { access(keyPath: \.internetHop); return internetHopState }
        set {
            internetHopState = newValue
            internetHopRevision &+= 1
            guard !internetHopNotifying else { return }
            internetHopNotifying = true
            defer { internetHopNotifying = false }
            var delivered: UInt64
            repeat {
                delivered = internetHopRevision
                withMutation(keyPath: \.internetHop) {}
            } while delivered != internetHopRevision
        }
    }
    var internetHopActive: Bool { internetHop.token != nil }
    @ObservationIgnored private var internetHopSSID: String?
    @ObservationIgnored private var internetHopSession: CameraSession?
    @ObservationIgnored private var internetHopSessionID: CameraSessionID?
    @ObservationIgnored private var internetHopReturnToken: FrameioInternetHop.Token?
    @ObservationIgnored private var internetHopReturnSessionID: CameraSessionID?

    var isOnCameraAccessPoint: Bool { DjiAppleWiFiJoiner.isCameraPathReady() }

    @discardableResult func beginInternetHop() -> FrameioInternetHop.Token {
        internetHopReturnToken = nil
        internetHopReturnSessionID = nil
        let capturedSession = session
        let capturedID = capturedSession.control.id
        let token = internetHop.begin()
        guard internetHop.owns(token), session === capturedSession,
            capturedSession.control.id == capturedID, internetHop.owns(token),
            session === capturedSession else { return token }
        internetHopSession = capturedSession
        internetHopSessionID = capturedID
        internetHopSSID = capturedSession.joinedSSID ?? capturedSession.cachedSSID
        if let ssid = internetHopSSID { DjiAppleWiFiJoiner.leave(ssid: ssid) }
        return token
    }

    func transferInternetHop(_ token: FrameioInternetHop.Token) -> FrameioInternetHop.Token? {
        internetHop.transfer(token)
    }

    func endInternetHop(_ token: FrameioInternetHop.Token) {
        guard internetHop.owns(token) else { return }
        let returningSession = internetHopSession
        let returningSessionID = internetHopSessionID
        internetHopSession = nil
        internetHopSessionID = nil
        internetHopSSID = nil
        internetHopReturnToken = token
        internetHopReturnSessionID = returningSessionID
        guard internetHop.end(token), internetHopReturnToken == token, internetHop.token == nil else { return }
        Task { [weak self, weak returningSession] in
            guard let self, let returningSession,
                self.consumeInternetHopReturn(token, session: returningSession) else { return }
            await returningSession.rejoinSoftAPAfterInternetHop()
        }
    }

    /// The queued native return consumes exactly one captured route/source admission.
    @discardableResult func consumeInternetHopReturn(_ token: FrameioInternetHop.Token, session returningSession: CameraSession) -> Bool {
        guard internetHop.token == nil, internetHopReturnToken == token,
            session === returningSession, let expected = internetHopReturnSessionID,
            returningSession.control.id == expected, internetHopReturnToken == token,
            internetHop.token == nil, session === returningSession else { return false }
        internetHopReturnToken = nil
        internetHopReturnSessionID = nil
        return true
    }

    func waitForInternetPath(timeoutSeconds: Double, token: FrameioInternetHop.Token) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled || !internetHop.owns(token) { return false }
            if !isOnCameraAccessPoint, await Self.canReachInternet() {
                return !Task.isCancelled && internetHop.owns(token)
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return false
    }

    private static func canReachInternet() async -> Bool {
        guard let url = URL(string: "https://ims-na1.adobelogin.com") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        return (try? await URLSession.shared.data(for: request)) != nil
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
        WatcherRelayKeychain.app.hostPasscode = sharePasscode
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
            isNano: session.bodyFamily == .nano)
        return state
    }

    func openWatcherBrowse() {
        showsWatcherBrowse = true
        relayClient.resolveEndpoint = { [weak self] name in
            self?.relayBrowser.hosts.first { $0.name == name }?.endpoint
        }
        relayClient.onReconnect = { [weak self] in self?.startWatcherBrowse() }
        startWatcherBrowse()
    }

    func startWatcherBrowse() {
        guard !isLive else { return }
        relayBrowser.start()
    }

    func joinWatcher(_ host: WatcherRelayDiscovery) {
        let code = WatcherRelayKeychain.app.rememberedPasscode(forHost: host.name)
        relayClient.join(
            endpoint: host.endpoint,
            hostName: host.name,
            passcode: code,
            watcherID: WatcherRelayKeychain.app.installID,
            deviceName: UIDevice.current.name)
    }

    func retryWatcherPasscode(_ code: String) {
        WatcherRelayKeychain.app.rememberPasscode(code, forHost: relayClient.hostTitle)
        relayClient.retryPasscode(code)
    }

    func stopWatching() {
        relayClient.leave()
        isWatchingFeed = false
        showsWatcherBrowse = false
        relayBrowser.stop()
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
        legalPanel = nil
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

    /// OpenZCine `NativeAppModel.setDisplayMode` — feed swipe jumps, it does not cycle.
    func setDisplayMode(clean: Bool) {
        guard assist.clean != clean else { return }
        assist.clean = clean
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
                timecode: self.session.status.timecodeClock,
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
                phase: session.phase,
                cameraName: session.connectedCamera?.name ?? "",
                feedLive: session.decoder.lastPresentedAt != nil))
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
        let recording = session.status.isRecording
        if session.controlBusy || session.isBrowsingMedia {
            return WatchCommandResult(
                accepted: false, isRecording: recording, error: WatchRelayCopy.busy)
        }
        guard case .live = session.phase else {
            return WatchCommandResult(
                accepted: false, isRecording: false, error: WatchRelayCopy.connectFirst)
        }
        let isPhoto = session.status.isPhoto
        if photo, !isPhoto {
            return WatchCommandResult(
                accepted: false, isRecording: recording, error: WatchRelayCopy.switchToPhoto)
        }
        if !photo, isPhoto {
            return WatchCommandResult(
                accepted: false, isRecording: recording, error: WatchRelayCopy.switchToVideo)
        }
        // Aimed at what the watch showed: another session or link is refused, not commanded.
        guard let target = watchTarget else {
            publishWatchState()
            return WatchCommandResult(
                accepted: false, isRecording: recording, error: WatchRelayCopy.cameraChanged)
        }
        let receipt: CommandReceipt?
        if let watchAdmission {
            guard watchAdmission.isCurrent, let shown = watchCommandSource,
                shown.admits(session.commandOwner)
            else {
                publishWatchState()
                return WatchCommandResult(
                    accepted: false, isRecording: recording, error: WatchRelayCopy.cameraChanged)
            }
            let admission = DJICommandAdmission(
                owner: shown.owner, isCurrent: { shown.isCurrent && watchAdmission.isCurrent })
            receipt = session.control.shutter(aimedAt: target, admission: admission)
        } else {
            receipt = session.control.shutter(aimedAt: target)
        }
        if let receipt, receipt.didNotAct {
            // Explicit start/stop; unknown record state is refused.
            publishWatchState()
            return WatchCommandResult(
                accepted: false, isRecording: recording,
                error: receipt.targetChanged ? WatchRelayCopy.cameraChanged : WatchRelayCopy.busy)
        }
        publishWatchState()
        return WatchCommandResult(accepted: true, isRecording: recording, error: nil)
    }
}

struct AppRoot: View {
    @State private var model = AppModel(connects: true)
    @State private var showReliabilityPrompt = false
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
            #if targetEnvironment(simulator)
                if MonitorMediaReview.isActive {
                    MonitorMediaReviewView()
                } else {
                    primaryExperience
                }
            #else
                primaryExperience
            #endif

            if model.showsLaunchSplash {
                LaunchSplashOverlay(isVisible: Bindable(model).showsLaunchSplash)
                    .transition(.opacity)
                    .zIndex(100)
            }

            if model.showsLegalPanel, !model.isWatchingFeed {
                AppPanelHost()
                    .environment(model)
                    .transition(.opacity)
                    .zIndex(80)
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
        .environment(
            \.monitorHDRChromeGain,
            model.hdrDisplayActive ? CGFloat(LiveHDRDisplay.app.presentGain) : 1
        )
        .background {
            HDRChromeHost(display: .app, enabled: model.hdrDisplayActive).allowsHitTesting(false)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)
        ) { _ in
            model.screenCaptured = UIScreen.main.isCaptured
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showReliabilityPrompt) {
            ReliabilityConsentPrompt { enabled in
                AppDiagnostics.reporting.setConsent(enabled)
                showReliabilityPrompt = false
            }.environment(model)
        }
        .task {
            while !Task.isCancelled {
                AppDiagnostics.problemReporting.tick()
                try? await Task.sleep(for: .seconds(2))
            }
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
            model.screenCaptured = UIScreen.main.isCaptured
            UIApplication.shared.isIdleTimerDisabled = model.keepScreenAwake
        }
        .onChange(of: model.relayClient.status) { _, status in
            model.noteWatcherStatusChanged(status)
        }
        .onChange(of: model.keepScreenAwake) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .task {
            try? await Task.sleep(for: LaunchSplashTiming.visibleDuration)
            withAnimation(.easeOut(duration: LaunchSplashTiming.fadeOutDuration)) {
                model.showsLaunchSplash = false
            }
            if AppDiagnostics.reporting.isAvailable && !AppDiagnostics.consent.hasDecision {
                showReliabilityPrompt = true
            }
        }
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
        .confirmationDialog(
            "Allow \(model.relayHost.pendingControlRequest?.name ?? "a watcher") to control the camera?",
            isPresented: Binding(
                get: { model.relayHost.pendingControlRequest != nil },
                set: { if !$0 { model.relayHost.denyControl() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Grant") { model.relayHost.grantControl() }
            Button("Deny", role: .cancel) { model.relayHost.denyControl() }
        }
        .onAppear { model.assist.inspectorSceneActive = scenePhase == .active }
        .onChange(of: scenePhase) { _, phase in
            AppDiagnostics.problemReporting.tick()
        }
        .monitorShellSceneActivity(model.shell)
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
    @State private var orientation = InterfaceOrientationObserver()
    @State private var diagnostics: DiagnosticSharePayload?
    @State private var showProblemReport = false
    @State private var showMultiview = false
    @State private var reviewAddSetup: SavedCamera?

    var body: some View {
        AppShell(
            // Main's setup chip menu: Forget only, no Rename setup.
            model: model.shell, brand: ShellBrand(name: "OpenPocketCine", renamesSetups: false),
            actions: ShellActions(
                diagnostics: {
                    if let url = DiagnosticCenter.shared.beginShare(session: model.session) {
                        diagnostics = DiagnosticSharePayload(url: url)
                    }
                }, reportProblem: { showProblemReport = true },
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
            safeArea: { proxy in
                Self.pageSafeArea(
                    proxy.safeAreaInsets, window: windowGeometry.safeArea,
                    portrait: proxy.size.height > proxy.size.width,
                    orientation: orientation.orientation)
            },
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
        .background(StartupColors.background.ignoresSafeArea())
        .foregroundStyle(StartupColors.ink)
        .onAppear {
            orientation.start()
            #if targetEnvironment(simulator)
                switch MonitorUIReview.state {
                case "add-setup": reviewAddSetup = model.savedCameras.first
                case "multiview": showMultiview = true
                default: break
                }
            #endif
        }
        .onDisappear { orientation.stop() }
        .sheet(item: $diagnostics) { payload in DiagnosticActivityShareView(items: [payload.url]) }
        .sheet(isPresented: $showProblemReport) { ProblemReportView().environment(model) }
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

    /// The camera pages' safe area: landscape mirrors the larger cutout so the list stays centered.
    static func pageSafeArea(
        _ proposed: EdgeInsets, window: EdgeInsets, portrait: Bool,
        orientation: MonitorDeviceOrientation
    ) -> EdgeInsets {
        let raw = LiveMonitorLayout.resolvedSafeArea(proposed, scene: window)
        guard !portrait else { return raw }
        return OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: raw, isPortrait: false,
            mirrored: LiveMonitorLayout.shouldMirror(
                leading: raw.leading, trailing: raw.trailing, orientation: orientation))
    }
}

extension LiveHDRDisplay {
    /// This app's HDR display state, read by the feed, scopes and chrome.
    static let app = LiveHDRDisplay()
}
