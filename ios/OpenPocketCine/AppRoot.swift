import Observation
import SwiftUI
import UIKit
import OpenPocketViewCore

/// App-level session object (OpenZCine `NativeAppModel` analogue). Owns the existing
/// `CameraSession` connection spine and the saved-camera list. Does not rewrite DUML.
@MainActor
@Observable
final class AppModel {
    var session = CameraSession()
    var savedCameras: [SavedCamera] = SavedCameraStore.load()
    /// Operator tapped “Pair new camera” from the saved list.
    var isPairingNewCamera = false
    var showsLaunchSplash = true
    var assist = LiveAssistState()
    /// Decoded-frame scopes. Filled by `HevcDecoder.handleDecodedFrame` — not camera DUML.
    var frameSamples = LiveFrameSampleBus()
    var homePanel: AppPanel?
    var captureSheet: CaptureSheet?
    var keepScreenAwake: Bool = OperatorPrefs.keepScreenAwake {
        didSet { OperatorPrefs.keepScreenAwake = keepScreenAwake }
    }
    var recordConfirmationEnabled: Bool = OperatorPrefs.recordConfirmationEnabled {
        didSet { OperatorPrefs.recordConfirmationEnabled = recordConfirmationEnabled }
    }
    var hapticsEnabled: Bool = OperatorPrefs.hapticsEnabled {
        didSet { OperatorPrefs.hapticsEnabled = hapticsEnabled }
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
    var dispLive = OperatorPrefs.dispLive {
        didSet { OperatorPrefs.dispLive = dispLive }
    }
    var dispClean = OperatorPrefs.dispClean {
        didSet { OperatorPrefs.dispClean = dispClean }
    }
    var operatorSettingsTab: OperatorSettingsTab = .link
    /// Live-monitor Media / Settings overlay. Distinct from `homePanel` (startup cover).
    var liveOperatorPanel: LiveOperatorPanel?
    /// DISP mode whose chrome the operator is editing on the monitor, or `nil` when live.
    var chromeEditorMode: PocketDispMode?
    /// Section Display settings should reopen on after Done.
    var chromeEditorReturnMode: PocketDispMode?
    /// False for a beat after live mounts so the connect tap cannot hit Settings / Media.
    var liveChromeInteractive = true
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
    var internetHopActive = false
    @ObservationIgnored private var internetHopSSID: String?
    @ObservationIgnored private var liveChromeArmTask: Task<Void, Never>?

    var isOnCameraAccessPoint: Bool { WiFiJoiner.isCameraPathReady() }

    func beginInternetHop() {
        internetHopActive = true
        internetHopSSID = session.joinedSSID ?? session.cachedSSID
        if let ssid = internetHopSSID { WiFiJoiner.leave(ssid: ssid) }
    }

    func endInternetHop() {
        internetHopActive = false
        Task { await session.rejoinSoftAPAfterInternetHop() }
    }

    func waitForInternetPath(timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if !isOnCameraAccessPoint, await Self.canReachInternet() { return true }
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

    var currentDispMode: PocketDispMode { assist.clean ? .clean : .live }

    var dispChrome: PocketDispChrome {
        chrome(for: currentDispMode)
    }

    var isEditingChrome: Bool { chromeEditorMode != nil }

    func chrome(for mode: PocketDispMode) -> PocketDispChrome {
        switch mode {
        case .live: dispLive
        case .clean: dispClean
        }
    }

    /// Whether `section` mounts right now: switched on, or force-mounted while that
    /// mode's chrome is being edited. Settings stays reachable if both modes hid it.
    func chromeSectionMounts(_ section: PocketDispChrome.Section) -> Bool {
        if let mode = chromeEditorMode, mode == currentDispMode,
            PocketDispChrome.isConfigurable(section, in: mode)
        {
            return true
        }
        if section == .railSettings, !dispLive.railSettings, !dispClean.railSettings {
            return true
        }
        return dispChrome.isVisible(section)
    }

    func toggleChrome(_ section: PocketDispChrome.Section, for mode: PocketDispMode) {
        switch mode {
        case .live: dispLive.toggle(section)
        case .clean: dispClean.toggle(section)
        }
    }

    /// Leaves Settings and switches the monitor to `mode` so badges land on the real thing.
    func beginChromeEditing(_ mode: PocketDispMode) {
        liveOperatorPanel = nil
        setDisplayMode(clean: mode == .clean)
        chromeEditorMode = mode
    }

    /// Done returns to Display settings on the section that was being edited.
    func endChromeEditing() {
        chromeEditorReturnMode = chromeEditorMode
        chromeEditorMode = nil
        operatorSettingsTab = .display
        liveOperatorPanel = .settings
    }

    var shouldShowWizard: Bool {
        CameraStartupPolicy.launchDestination(savedCameras: savedCameras) == .addCamera
            || isPairingNewCamera
    }

    var isLive: Bool {
        if session.holdsMonitor { return true }
        if case .live = session.phase { return true }
#if targetEnvironment(simulator)
        // No Pocket in Simulator — LiveViewScreen plays the D-Log2 Downloads clip.
        return true
#else
        return false
#endif
    }

    var isBusy: Bool {
        switch session.phase {
        case .idle, .scanning, .failed, .live: false
        default: true
        }
    }

    var isScanning: Bool {
        if case .scanning = session.phase { true } else { false }
    }

    func prepareStartup() {
        savedCameras = SavedCameraStore.load()
        switch CameraStartupPolicy.launchDestination(savedCameras: savedCameras) {
        case .addCamera:
            isPairingNewCamera = true
            session.startScan()
        case .savedCameras:
            isPairingNewCamera = false
            session.startScan()
        }
    }

    func pairNewCamera() {
        isPairingNewCamera = true
        session.startScan()
    }

    func cancelPairing() {
        session.disconnect()
        isPairingNewCamera = false
        session.startScan()
    }

    func reconnect(_ camera: SavedCamera) {
        session.reconnect(to: camera.id)
    }

    func forget(_ camera: SavedCamera) {
        session.forgetWifiCreds(for: camera)
        savedCameras = SavedCameras.removing(camera.id, from: savedCameras)
        SavedCameraStore.save(savedCameras)
        if savedCameras.isEmpty {
            isPairingNewCamera = true
            session.startScan()
        }
    }

    func rename(_ camera: SavedCamera, to name: String?) {
        savedCameras = SavedCameras.renaming(camera.id, to: name, in: savedCameras)
        SavedCameraStore.save(savedCameras)
    }

    /// Connect shows the monitor — never leftover Operator Setup, Media, or Edit view.
    func noteBecameLive() {
        homePanel = nil
        liveOperatorPanel = nil
        chromeEditorMode = nil
        chromeEditorReturnMode = nil
        captureSheet = nil
        liveChromeInteractive = false
        liveChromeArmTask?.cancel()
        liveChromeArmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            self?.liveChromeInteractive = true
        }
        persistConnectedCameraIfNeeded()
    }

    /// A dropped link must not keep Operator Setup or Edit view around for the next connect.
    func noteLeftLive() {
        liveChromeArmTask?.cancel()
        liveChromeArmTask = nil
        liveChromeInteractive = true
        liveOperatorPanel = nil
        chromeEditorMode = nil
        chromeEditorReturnMode = nil
        captureSheet = nil
    }

    func persistConnectedCameraIfNeeded() {
        guard case .live = session.phase, let found = session.connectedCamera else { return }
        if let ssid = session.joinedSSID {
            if CameraWifiResolution.isSSIDOwnedByAnotherCamera(
                ssid, cameraId: found.id, saved: savedCameras)
            {
                return
            }
            if CameraBodyFamily.ssidConflictsWithBody(
                ssid: ssid, modelId: found.modelId, advertisedName: found.name)
            {
                return
            }
        }
        let record = SavedCamera(
            id: found.id,
            advertisedName: found.name,
            modelName: found.model.name,
            lastSSID: session.joinedSSID,
            lastConnectedAt: Date(),
            modelId: found.modelId
        )
        savedCameras = SavedCameras.upserting(record, into: savedCameras)
        SavedCameraStore.save(savedCameras)
        isPairingNewCamera = false
    }

    func beginMediaBrowse() { session.beginMediaBrowse() }
    func endMediaBrowse() { session.endMediaBrowse() }
    func refreshMedia() { Task { await session.refreshMedia() } }

    func disconnect() {
        session.disconnect()
        frameSamples.reset()
        if CameraStartupPolicy.launchDestination(savedCameras: savedCameras) == .savedCameras {
            session.startScan()
        }
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
}

enum LiveOperatorPanel: Equatable {
    case media
    case settings
}

struct AppRoot: View {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ZCBackground()
            if model.isLive {
                LiveViewScreen()
                    .environment(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                LinkExperience()
                    .environment(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if model.showsLaunchSplash {
                LaunchSplashOverlay(isVisible: Bindable(model).showsLaunchSplash)
                    .transition(.opacity)
                    .zIndex(100)
            }

            if model.homePanel != nil, !model.isLive {
                AppPanelHost()
                    .environment(model)
                    .transition(.opacity)
                    .zIndex(80)
            }
        }
        .environment(model)
        .environment(\.font, LiveType.text(16))
        .preferredColorScheme(.dark)
        .onAppear {
            model.prepareStartup()
            UIApplication.shared.isIdleTimerDisabled = model.keepScreenAwake
        }
        .onChange(of: model.keepScreenAwake) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .task {
            try? await Task.sleep(for: LaunchSplashTiming.visibleDuration)
            withAnimation(.easeOut(duration: LaunchSplashTiming.fadeOutDuration)) {
                model.showsLaunchSplash = false
            }
        }
        .onChange(of: model.isLive) { _, live in
            if live {
                model.noteBecameLive()
            } else {
                model.noteLeftLive()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.session.noteSceneBecameActive()
            case .inactive, .background:
                model.session.noteSceneBecameInactive()
            @unknown default:
                break
            }
        }
        // scenePhase can miss a Control Center / app-switcher bounce.
        // UIKit notifications are the same signals OpenZCine uses.
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
        ) { _ in
            model.session.noteSceneBecameInactive()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            model.session.noteSceneBecameActive()
        }
    }
}

/// Connection home: first-pair wizard, or saved cameras. Mirrors OpenZCine `LinkExperience`.
struct LinkExperience: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 640
            let isPortrait = proxy.size.height > proxy.size.width
            let topPadding: CGFloat = isPortrait ? 16 : 24
            let wizardFillsViewport = model.shouldShowWizard

            VStack(alignment: .leading, spacing: 0) {
                StartupHeader(
                    title: headerTitle,
                    statusTitle: statusTitle,
                    isBusy: isBusy,
                    onPrivacy: { model.homePanel = .privacy },
                    onTerms: { model.homePanel = .terms }
                )
                    .padding(.horizontal, 20)

                if wizardFillsViewport {
                    ConnectionSetupView(compact: compact)
                        .environment(model)
                        .padding(.leading, 20)
                        .padding(.trailing, 24)
                        .padding(.top, compact ? 8 : 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    SavedCamerasView(compact: compact)
                        .environment(model)
                        .padding(.horizontal, 20)
                        .padding(.top, compact ? 14 : 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding(.top, topPadding)
            .padding(.bottom, 16)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .background(StartupColors.backdrop.ignoresSafeArea())
        .foregroundStyle(StartupColors.ink)
    }

    private var headerTitle: String {
        if model.shouldShowWizard { return "Connection setup" }
        if !model.savedCameras.isEmpty { return "Your cameras" }
        return "Find your camera"
    }

    private var statusTitle: String {
        if model.session.isReconnecting { return "Reconnecting" }
        return StartupConnectionCopy.statusTitle(
            for: model.session.phase,
            isDiscovering: model.isScanning || (model.shouldShowWizard && !model.isLive)
        )
    }

    private var isBusy: Bool { model.isBusy }
}
