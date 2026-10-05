import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Operator-facing Settings help. Never name a sister app or another camera brand.
enum SettingsHelpCopy {
    static let currentTransport =
        "Pocket uses Bluetooth to pair, then the camera's own Wi-Fi for HEVC. USB-C, hotspot, and HDMI capture are not in this build."
    static let stream =
        "The Pocket sends HEVC over the camera access point. Stream quality presets are not on this body."
    static let shareFeed =
        "Watching devices join this camera’s Wi-Fi, then receive the shared picture from this phone."
    static let editView =
        "Opens the monitor with an eye on each element you can show or hide."
    static let frameIO =
        "Sign in to upload clips from the share popup. Frame.io needs the internet, so the phone hops off the camera Wi‑Fi for the upload."
    static let shareThisFeed =
        "Watching devices join this camera’s Wi-Fi, then receive the shared picture from this phone."
    static let broadcastPriority =
        "Steadier picture uses more delay when the radio is busy."
    static let watcherPasscode =
        "Watchers enter this once. Leave empty for an open feed."
    static let controlRequests =
        "A watcher can ask to record, focus, and change exposure. You grant or deny on this phone."
    static let watchAFeed =
        "Watch a feed"
    static let recordConfirmation =
        "Ask before starting or stopping recording to prevent mistaps."
    static let haptics =
        "Short confirmation pulses for switches, settings, and gimbal limits. A connected controller also rumbles at a stop."
    static let headTracking =
        "Experimental. The compass above the joystick on the right is Calibrate Head Lock: that AirPods pose and that gimbal pose are shared forward. Head turns set matching pan and tilt angles within the gimbal’s range. Roll is shown only. Needs AirPods with motion (Pro, 3, Max, or later) in your ears. Off by default. The same control becomes STOP and clears the lock. On-screen stick, a game controller, and Motion Control takes priority."
    static let joystickSensitivity =
        "How far a stick throw moves the gimbal \u{2014} on-screen and a connected game controller. Small throws crawl; full throw is fastest. 4 is the captured feel. 5 reaches full speed sooner; 1 is the slowest."
    static let virtualJoystickSize =
        "How large the on-screen stick is. Medium is the default. Large is easier to grab; Small keeps more of the picture clear."
    static let virtualJoystickInvertPan =
        "Reverse left and right on the on-screen stick. Off is the default. A game controller is unchanged."
    static let virtualJoystickInvertTilt =
        "Reverse up and down on the on-screen stick. Off is the default. A game controller is unchanged."
    static let virtualJoystickDeadzone =
        "Ignore small movements near the center. The default is 8%. Increase it to make the center less sensitive."
    static let virtualJoystickResponse =
        "Standard keeps the current feel. Linear responds evenly. Fine makes small movements gentler."
    static let gimbalJoystick =
        "Which analog stick pans and tilts. Left is the default. The other stick does not move the gimbal."
    static let gamepad =
        "A connected game controller. The selected gimbal joystick pans and tilts. Cross/A records. Circle/B recenters. Square/X is rotate-180. Triangle/Y tracks a face. L1/R1 jump zoom out/in. L2/R2 hold-to-zoom (deeper is faster). D-pad up/down ISO, left/right shutter. Unplug rests the stick. On-screen stick wins while you hold it."
    static let keepScreenAwake =
        "Prevents auto-lock while OpenPocketCine is open. A monitor should stay lit. iOS may still dim when the device overheats."
    static let hdrDisplay =
        "Outdoor panel brightness, not a grade. WAVE, HISTO, PARADE, VECTOR, zebras and false color still read the decoded camera signal \u{2014} judge exposure there, not from how bright the picture looks. Screen recording and AirPlay drop back to a normal SDR picture so the file is not HDR-boosted. This is not the camera's HDR/HLG color mode. Off by default."
    static let themeHelp =
        "Charcoal field-monitor chrome with Sky Blue accents, tuned for low reflection on set."
    static let sourceHelp =
        "View the OpenPocketCine project on GitHub. Opening this may leave the camera Wi-Fi if that is the only network."
    static let linkHealth =
        "How healthy the camera link is right now \u{2014} delivery, not radio RSSI."
    static let clearCache =
        "Removes downloaded clip files from this phone. The clip list stays so you can cache them again from the camera."
    static let cacheFullResolution =
        "Download the original camera file when you open a clip. Off keeps only the 720p proxy to save space. Share needs the original \u{2014} connect the camera if it is not cached."
    static let shareDiagnostics =
        "Saves a report with connection events, warnings, and crashes. No name, location, or Wi-Fi password. Take a screenshot for TestFlight and paste the copied text into the feedback."
    static let reliabilityReports =
        "Optional: send crash, hang, live-feed reports and session health counts to OpenCapture through Sentry. Off by default. Turn off anytime without losing app features. Uploads wait until you leave camera Wi-Fi. No footage or GPS location. Sentry receives the connection IP; stored event IP and derived geography are removed. See Reporting Privacy below."
    static let reliabilityUnavailable =
        "This build cannot send automatic reports. You can still share or delete reports stored on this phone."
    static let deleteStoredIncidents =
        "Remove local copies of saved freeze reports. Turn off Automatic error reports to clear pending uploads. Reports already sent cannot be removed here."
}

typealias OperatorSettingsTab = MonitorSettingsTab

struct SettingsRootView: View {
    /// Real device insets after the host zeros the clean landscape edge.
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var legalKind: LegalDocumentView.Kind?
    @State private var showLUTPicker = false
    @State private var showWatcherWiFiCode = false
    @State private var confirmClearCache = false
    @State private var cacheBytes: UInt64?
    private struct CacheSizeRequest: Equatable {
        var cameraID: String
        var revision: UInt64
    }
    private var cacheSizeRequest: CacheSizeRequest {
        CacheSizeRequest(
            cameraID: model.session.mediaCameraID, revision: model.session.mediaCacheRevision)
    }
    @State private var clearingCache = false
    @State private var cacheClearFailed = false
    @State private var diagnosticsShare: DiagnosticSharePayload?
    @State private var showProblemReport = false
    @State private var showDiagnosticOptions = false
    @State private var supportError = false
    @State private var reliabilityOptIn = ReliabilityReporting.isOptedIn
    @State private var gimbalGamepadStick = OperatorPrefs.gimbalGamepadStick

    var body: some View {
        MonitorSettingsPage(
            safeArea: safeArea, brand: "OpenPocketCine",
            selection: Bindable(model).operatorSettingsTab, tabSpacing: 0,
            isLive: model.isLive, phaseLabel: model.session.phase.label,
            sharingSubtitle: "Share this feed with OpenPocketCine devices on the same camera Wi-Fi.",
            feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) },
            onClose: dismiss, disconnect: model.disconnect
        ) { _ in
            settingsRows
        }
        .overlay {
            if let legalKind {
                LegalDocumentView(kind: legalKind, onClose: { self.legalKind = nil })
            }
        }
        .sheet(isPresented: $showWatcherWiFiCode) {
            WatcherWiFiCodeView().environment(model)
        }
        .sheet(isPresented: $showLUTPicker) {
            LUTPicker(assist: model.assist)
        }
        .sheet(isPresented: $showProblemReport) {
            ProblemReportView().environment(model)
        }
        .alert("Report unavailable", isPresented: $supportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Email support@opencapture.org. You can save a report under Diagnostic options.")
        }
        .sheet(item: $diagnosticsShare) { payload in
            DiagnosticActivityShareView(items: [payload.url])
        }
    }

    private func dismiss() {
        if let onClose {
            onClose()
        } else {
            model.homePanel = nil
        }
    }

    @ViewBuilder private var settingsRows: some View {
        switch model.operatorSettingsTab {
        case .link: linkRows
        case .sharing: sharingRows
        case .assist: assistRows
        case .controls: controlsRows
        case .display: displayRows
        case .storage: storageRows
        case .system: systemRows
        }
    }

    // MARK: - Link

    @ViewBuilder private var linkRows: some View {
        SettingsLinkHealthCard().monitorFullWidthCard()

        MonitorConnectionSettings(
            transport: model.isLive ? "BLE + Wi-Fi active" : "Not connected",
            transportHelp: SettingsHelpCopy.currentTransport,
            phase: model.session.phase.label,
            phaseHelp: "Where the BLE → Wi-Fi → datalink handshake is right now.",
            network: model.session.joinedSSID.flatMap { $0.isEmpty ? nil : $0 },
            networkHelp: "SSID joined for this session. The password stays in the iOS Keychain on this phone.")

        if FeedUpscaler.supportedOnThisDevice.count > 1 {
            SettingsRowCard(title: "Processing") {
                SettingsInlineRow(
                    title: "Feed Upscaler",
                    help: SettingsHelpCopy.feedUpscaler,
                    showTopDivider: false
                ) {
                    SettingsSegmented(
                        options: FeedUpscaler.supportedOnThisDevice.map(\.rawValue),
                        selected: FeedUpscaleSwitch.shared.upscaler.rawValue,
                        compact: true
                    ) { value in
                        guard let choice = FeedUpscaler(rawValue: value) else { return }
                        FeedUpscaleSwitch.shared.upscaler = choice
                    }
                }
            }
        }

        MonitorSavedCameraSettings(cameras: model.savedCameras.map { camera in
            let network = camera.lastSSID
            return .init(id: camera.id, name: camera.displayName,
                detail: camera.modelName + (network.map { " · \($0)" } ?? ""), network: network)
        }, emptyHelp: "Pair from the home list. Settings does not start a new pair; that stays on Your cameras.")
    }

    // MARK: - Sharing

    @ViewBuilder private var sharingRows: some View {
        if model.session.isMultiviewBorrowed {
            SettingsRowCard {
                SettingsInlineRow(
                    title: "Sharing unavailable in Multiview",
                    help:
                        "Connect to one camera from Your cameras to share its feed with watchers.",
                    showTopDivider: false
                ) {
                    EmptyView()
                }
            }
        } else if model.isLive {
            let priorities = ["Quality", "High", "Medium", "Steady"]
            MonitorFeedSharingSettings(
                sharing: Binding(get: { model.shareThisFeed }, set: model.setShareThisFeed),
                passcode: Bindable(model).sharePasscode,
                controlRequests: Bindable(model).controlRequestsAllowed,
                priority: Binding(get: { priorities[min(model.broadcastPriority, 3)] }, set: {
                    if let index = priorities.firstIndex(of: $0) { model.broadcastPriority = index }
                }), priorities: priorities,
                help: .init(sharing: SettingsHelpCopy.shareThisFeed,
                    passcode: SettingsHelpCopy.watcherPasscode,
                    controlRequests: SettingsHelpCopy.controlRequests,
                    priority: SettingsHelpCopy.broadcastPriority),
                showWiFiCode: { showWatcherWiFiCode = true },
                passcodeChanged: { WatcherRelayKeychain.hostPasscode = $0 },
                feedback: { OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled) })
        } else {
            SettingsRowCard {
                SettingsInlineRow(
                    title: SettingsHelpCopy.watchAFeed,
                    help: SettingsHelpCopy.shareFeed,
                    showTopDivider: false
                ) {
                    SettingsActionPill(title: "Browse") { model.openWatcherBrowse() }
                }
            }
        }
    }

    // MARK: - View Assist

    @ViewBuilder private var assistRows: some View {
        let transfer = model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709
        let clipByte = model.monitorSamples.exposureCeiling.clipByte(transfer: transfer)
        let feedback = { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }
        MonitorViewAssistSettings(sections: [
            .falseColor(PocketSettingsAssistMenus.falseColor(assist: model.assist, compact: true,
                transfer: transfer, clipByte: clipByte), reset: { feedback(); resetFalseColor() }),
            .zebra(ZebraAssist.longPressMenu(assist: model.assist, compact: true)
                .commonMenu(transfer: transfer, clipByte: clipByte), reset: { feedback(); resetZebra() }),
            .waveform(WaveformAssist.longPressMenu(assist: model.assist, compact: true).commonMenu,
                reset: { feedback(); resetWaveform() }),
            .parade(ParadeAssist.longPressMenu(assist: model.assist, compact: true).commonMenu,
                reset: { feedback(); resetParade() }),
            .histogram(HistogramAssist.longPressMenu(assist: model.assist, compact: true).commonMenu,
                reset: { feedback(); resetHistogram() }),
            .vectorscope(VectorscopeAssist.longPressMenu(assist: model.assist, compact: true).commonMenu,
                reset: { feedback(); resetVectorscope() }),
            .peaking(PeakingAssist.longPressMenu(assist: model.assist, compact: true).commonMenu,
                reset: { feedback(); resetPeaking() }),
            .trafficLights(TrafficLightsAssist.longPressMenu(assist: model.assist, compact: true).commonMenu,
                reset: { feedback(); resetTrafficLights() }),
        ]).buttonStyle(.monitorTapTarget).monitorFullWidthCard()

        MonitorExposureMeterSettings(isOn: model.assist.evMeter,
            help: "Show the camera's exposure meter at the picture's left edge in DISP 1. Auto and Manual use the camera reading without changing exposure settings.",
            feedback: { OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled) },
            onToggle: { model.assist.toggle(.evMeter) })

        MonitorLookSettings(look: lutLabel,
            help: "Looks apply on this phone. The file on the camera is unchanged.",
            onOpen: { showLUTPicker = true })
    }

    private func resetFalseColor() {
        model.assist.falseColorScale = FalseColorAssist.Options.default.scale
        model.assist.falseColorReference = FalseColorAssist.Options.default.referenceEnabled
        model.assist.persist()
    }

    private func resetZebra() {
        model.assist.zebraOptions = .default
        model.assist.persist()
    }

    private func resetWaveform() {
        WaveformAssist.store.options = .default
    }

    private func resetParade() {
        ParadeAssist.store.options = .default
    }

    private func resetHistogram() {
        HistogramAssist.store.options = .default
    }

    private func resetVectorscope() {
        VectorscopeAssist.store.options = .default
    }

    private func resetPeaking() {
        PeakingAssist.reset(model.assist)
    }

    private func resetTrafficLights() {
        model.assist.crushClipCompensation = TrafficLightsAssist.defaultCompensation
        model.assist.persist()
    }

    private var lutLabel: String {
        model.assist.lutStatusLabel
    }

    // MARK: - Controls

    @ViewBuilder private var controlsRows: some View {
        MonitorOperatorSafetySettings(
            recordConfirmation: Bindable(model).recordConfirmationEnabled,
            haptics: Bindable(model).hapticsEnabled,
            keepScreenAwake: Bindable(model).keepScreenAwake,
            hapticsHelp: SettingsHelpCopy.haptics,
            keepScreenAwakeHelp: SettingsHelpCopy.keepScreenAwake,
            feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }
        )
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        let preferenceFeedback = {
            OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
        }
        if capabilities.gimbal {
            MonitorGimbalSettings(
                sensitivity: .init(value: Bindable(model).gimbalStickSensitivity, range: 1...5,
                    help: SettingsHelpCopy.joystickSensitivity,
                    feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }),
                headTracking: capabilities.headTracking
                    ? .init(value: Bindable(model).headTrackingEnabled,
                        help: SettingsHelpCopy.headTracking, feedback: preferenceFeedback) : nil)
            MonitorJoystickSettings(
                size: .init(options: MonitorJoystickSize.allCases.map(\.label),
                    selection: Binding(get: { model.virtualJoystickSize.label },
                        set: { model.virtualJoystickSize = MonitorJoystickSize.fromLabel($0) }),
                    help: SettingsHelpCopy.virtualJoystickSize, feedback: preferenceFeedback),
                invertPan: .init(value: Bindable(model).virtualJoystickInvertPan,
                    help: SettingsHelpCopy.virtualJoystickInvertPan, feedback: preferenceFeedback),
                invertTilt: .init(value: Bindable(model).virtualJoystickInvertTilt,
                    help: SettingsHelpCopy.virtualJoystickInvertTilt, feedback: preferenceFeedback),
                deadZone: .init(value: Bindable(model).virtualJoystickDeadzonePercent,
                    range: GimbalStick.deadzonePercentRange, help: SettingsHelpCopy.virtualJoystickDeadzone,
                    suffix: "%", feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }),
                response: .init(options: GimbalStick.ResponseCurve.allCases.map(\.label),
                    selection: Binding(get: { model.virtualJoystickResponseCurve.label },
                        set: { model.virtualJoystickResponseCurve = GimbalStick.ResponseCurve.fromLabel($0) }),
                    help: SettingsHelpCopy.virtualJoystickResponse, feedback: preferenceFeedback),
                identifierPrefix: "gimbal.virtual")
        }
        MonitorControllerSettings(
            stick: .init(options: GamepadGimbalStick.allCases.map(\.label),
                selection: Binding(get: { gimbalGamepadStick.label }, set: { value in
                    let next = GamepadGimbalStick.fromLabel(value)
                    if next != OperatorPrefs.gimbalGamepadStick {
                        OperatorPrefs.gimbalGamepadStick = next
                        gimbalGamepadStick = next
                        model.gimbalPadHeld = false
                        model.session.gimbal.endStick()
                    }
                }), help: SettingsHelpCopy.gimbalJoystick, feedback: preferenceFeedback),
            status: model.gamepadConnected ? "Connected" : "Not connected", statusHelp: SettingsHelpCopy.gamepad)
    }

    // MARK: - Display (honest: rail-owned)

    @ViewBuilder private var displayRows: some View {
        Group {
            MonitorPanelSettings(
                hdrDisplay: Bindable(model).hdrDisplay, help: SettingsHelpCopy.hdrDisplay,
                feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }
            )
            MonitorDisplaySections(sections: PocketDispMode.allCases.map { mode in
                MonitorDisplaySection(
                    id: mode.rawValue, title: mode.settingsTitle, caption: mode.settingsCaption,
                    reset: {
                        OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                        if mode == .clean { model.dispClean = .cleanDefaults }
                        else { model.dispLive = .liveDefaults }
                    },
                    editHint: SettingsHelpCopy.editView,
                    edit: model.isLive ? { model.beginChromeEditing(mode) } : nil,
                    unavailableEditHelp: "Connect to arrange this on the monitor.",
                    visibility: displayVisibility(mode),
                    pinsTitle: "View assists that stay on in clean view",
                    pins: mode == .clean ? cleanPins : [], style: .controls)
            })
        }
        .onAppear { model.chromeEditorReturnMode = nil }
    }

    private func displayVisibility(_ mode: PocketDispMode) -> [MonitorDisplayToggle] {
        let chrome = mode == .clean ? Bindable(model).dispClean : Bindable(model).dispLive
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        let values: [(String, String, WritableKeyPath<PocketDispChrome, Bool>, Bool)] = [
            ("Status Bar", "REC, timecode, format, and FPS along the top of the feed.", \.statusBar, true),
            ("Tool Bar", "The view-assist strip under the feed.", \.toolBar, true),
            ("Camera Values", "ISO, shutter, white balance, and the rest of the capture strip.", \.cameraValues, true),
            ("Lock Button", "Side-rail lock. Remounts while the interface is locked.", \.lockButton, true),
            ("Batteries", "Phone and camera battery cluster.", \.batteries, true),
            ("REC", "Standby / recording chip on the status bar.", \.recReadout, true),
            ("Timecode", "Running timecode on the status bar.", \.timecode, true),
            ("Format", "Recording resolution and frame rate.", \.format, true),
            ("Color", "Color mode chip on the status bar.", \.color, true),
            ("Storage", "Remaining media time on the status bar.", \.storage, true),
            ("FPS", "Live-view rate and link bars.", \.fps, true),
            ("Record", "Rail record lamp. Stays available while rolling.", \.railRecord, true),
            ("Media", "Rail media button.", \.railMedia, true),
            ("Settings", "Rail settings button. Always an escape hatch.", \.railSettings, true),
            ("Zoom Chip", "Live zoom readout on the feed.", \.zoomChip, capabilities.zoom),
            ("Gimbal Stick", "On-screen gimbal stick.", \.gimbalStick, capabilities.gimbal),
            ("AF Box", "Focus and face-tracking brackets on the feed.", \.focusBox, true),
        ]
        return values.filter { $0.3 }.map { title, help, field, _ in
            MonitorDisplayToggle(id: mode.rawValue + "." + title, title: title,
                isOn: chrome.wrappedValue[keyPath: field], help: help) {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
                chrome.wrappedValue[keyPath: field].toggle()
            }
        }
    }

    private var cleanPins: [MonitorDisplayToggle] {
        LiveAssistTool.cleanPinCases.map { tool in
            MonitorDisplayToggle(id: "clean.pin." + tool.rawValue,
                title: tool.displaySettingsTitle,
                isOn: model.assist.cleanViewPinnedTools.contains(tool),
                accessibilityLabel: "Keep \(tool.displaySettingsTitle) in clean view") {
                OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                model.assist.toggleCleanViewPin(tool)
            }
        }
    }

    // MARK: - Storage

    @ViewBuilder private var storageRows: some View {
        MonitorAccountSettings(title: "Frame.io", help: SettingsHelpCopy.frameIO,
            state: frameioAccountState,
            signIn: { Task { try? await model.connectFrameio() } },
            signOut: { model.disconnectFrameio() })
        MonitorCacheSettings(
            cacheOriginals: Binding(get: { model.cacheFullResolution }, set: { model.cacheFullResolution = $0 }),
            sizeLabel: cacheSizeLabel, clearing: clearingCache,
            cacheHelp: SettingsHelpCopy.cacheFullResolution,
            scopeHelp: "Originals and playback proxies downloaded from the camera.",
            clearHelp: SettingsHelpCopy.clearCache,
            feedback: { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) },
            clear: { confirmClearCache = true })
        .confirmationDialog(
            "Clear cache?",
            isPresented: $confirmClearCache,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                clearingCache = true
                Task {
                    do { try await model.session.clearMediaCache() } catch {
                        cacheClearFailed = true
                    }
                    clearingCache = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes downloaded clip files from this phone. The clip list is kept.")
        }
        .disabled(clearingCache)
        .task(id: cacheSizeRequest) {
            let request = cacheSizeRequest
            cacheBytes = nil
            let bytes = await model.session.cameraMedia.cacheByteCount(cameraID: request.cameraID)
            guard !Task.isCancelled, cacheSizeRequest == request else { return }
            cacheBytes = bytes
        }
        .alert("Could not clear the cache. Try again.", isPresented: $cacheClearFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private var frameioAccountState: MonitorAccountState {
        if !model.isFrameioConfigured { return .notConfigured }
        if model.frameioConnecting { return .connecting }
        return model.isFrameioConnected ? .signedIn : .signedOut
    }

    private var cacheSizeLabel: String {
        guard let bytes = cacheBytes else { return "Checking…" }
        if bytes == 0 { return "Empty" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - System

    @ViewBuilder private var systemRows: some View {
        MonitorSupportSettings(
            automaticReports: Binding(get: { reliabilityOptIn }, set: {
                reliabilityOptIn = $0; ReliabilityReporting.setConsent($0)
            }), available: ReliabilityReporting.isAvailable,
            automaticHelp: SettingsHelpCopy.reliabilityReports,
            unavailableHelp: SettingsHelpCopy.reliabilityUnavailable,
            report: { showProblemReport = true }, privacy: { legalKind = .privacy })
        MonitorDiagnosticSettings(expanded: $showDiagnosticOptions,
            deleteHelp: SettingsHelpCopy.deleteStoredIncidents,
            save: {
                if let url = DiagnosticCenter.shared.writeReport(session: model.session) {
                    diagnosticsShare = DiagnosticSharePayload(url: url)
                } else { supportError = true }
            }, delete: { FeedIncidentRuntime.deleteStoredIncidents {} })

        MonitorProjectLegalSettings(
            sourceHelp: SettingsHelpCopy.sourceHelp, termsHelp: "How you can use OpenPocketCine.",
            source: { if let url = OpenPocketCineLinks.source { openURL(url) } },
            privacy: { legalKind = .privacy },
            terms: { if let url = OpenPocketCineLinks.terms { openURL(url) } },
            licenses: { legalKind = .licenses }, notice: { legalKind = .notice })
        MonitorAppInformationSettings(
            theme: "DJI Black", protocolName: "DUML / BLE + Wi-Fi", version: Self.appVersionText,
            themeHelp: SettingsHelpCopy.themeHelp,
            protocolHelp: "Camera control speaks DUML over Bluetooth and the camera's Wi-Fi. No DJI SDK is bundled or required.",
            versionHelp: "Current OpenPocketCine build from the native project metadata.")
    }

    static var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
