import MonitorPresentation
import MonitorUI
import OpenCineCameraControls
import OpenCineRelayApple
import OpenPocketViewCore
import SwiftUI
import UIKit
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineApple
import OpenCineFrameIOApple

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
    static let liveDisplayTitle = MonitorDisplayMode.live.settingsTitle
    static let cleanDisplayTitle = MonitorDisplayMode.clean.settingsTitle
    static let liveDisplayCaption = MonitorDisplayMode.live.settingsCaption
    static let cleanDisplayCaption = MonitorDisplayMode.clean.settingsCaption
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


struct SettingsRootView: View {
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil
    @Environment(AppModel.self) private var model

    var body: some View {
        MonitorOperatorSettingsScreen(shell: model.shell, brand: "OpenPocketCine",
            preferences: OperatorPrefs.common, display: OperatorPrefs.display, assist: model.assist,
            library: model.session.mediaLibrary, operatorSession: model.operatorSession,
            configuration: configuration)
    }

    private var configuration: MonitorOperatorSettingsConfiguration<MonitorLUTLooks> {
        let transfer = model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709
        return .init(safeArea: safeArea, phase: model.session.phase.label, isLive: model.isLive,
            sharingSubtitle: "Share this feed with OpenPocketCine devices on the same camera Wi-Fi.",
            close: { if let onClose { onClose() } else { model.shell.dismissCover() } },
            disconnect: model.disconnect, feedback: feedback, link: link, sharing: sharing, motion: motion,
            account: .init(title: "Frame.io", help: SettingsHelpCopy.frameIO, state: accountState,
                signIn: { Task { try? await model.frameio.connect() } }, signOut: model.frameio.disconnect),
            cache: cache, support: support,
            information: .init(theme: "DJI Black", protocolName: "DUML / BLE + Wi-Fi", version: Self.appVersionText,
                themeHelp: SettingsHelpCopy.themeHelp, protocolHelp: "Camera control speaks DUML over Bluetooth and the camera's Wi-Fi. No DJI SDK is bundled or required.",
                versionHelp: "Current OpenPocketCine build from the native project metadata."),
            recordConfirmation: Bindable(model).recordConfirmationEnabled, haptics: Bindable(model).hapticsEnabled,
            keepAwake: Bindable(model).keepScreenAwake, hdrDisplay: Bindable(model).hdrDisplay,
            cacheOriginals: Bindable(model).cacheFullResolution,
            hapticsHelp: SettingsHelpCopy.haptics, keepAwakeHelp: SettingsHelpCopy.keepScreenAwake,
            hdrHelp: SettingsHelpCopy.hdrDisplay, cacheHelp: SettingsHelpCopy.cacheFullResolution,
            clearHelp: SettingsHelpCopy.clearCache, exposureHelp: "Show the camera's exposure meter at the picture's left edge in DISP 1. Auto and Manual use the camera reading without changing exposure settings.",
            availableDisplay: availableDisplay, assist: model.assist, stores: .app, falseColorLooks: .app,
            palette: LiveDesign.self, operatorHaptics: .app, transfer: transfer,
            clipByte: model.monitorSamples.exposureCeiling.clipByte(transfer: transfer),
            lookLabel: model.assist.lutStatusLabel, lookCatalog: { AnyView(LUTPicker(assist: model.assist)) })
    }

    private func feedback() { OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled) }

    private var link: MonitorSettingsLinkSource {
        .init(transport: model.isLive ? "BLE + Wi-Fi active" : "Not connected",
            transportHelp: SettingsHelpCopy.currentTransport, phase: model.session.phase.label,
            phaseHelp: "Where the BLE → Wi-Fi → datalink handshake is right now.", network: model.session.joinedSSID.flatMap { $0.isEmpty ? nil : $0 },
            networkHelp: "SSID joined for this session. The password stays in the iOS Keychain on this phone.",
            signalBars: model.session.liveSignalBars, saved: model.savedCameras.map { camera in
                let network = camera.lastSSID
                return .init(id: camera.id, name: camera.displayName,
                    detail: camera.modelName + (network.map { " · \($0)" } ?? ""), network: network)
            }, savedHelp: "Pair from the home list. Settings does not start a new pair; that stays on Your cameras.",
            processing: MonitorUpscaler.supportedOnThisDevice.count > 1 ? .init(
                options: MonitorUpscaler.supportedOnThisDevice.map(\.rawValue),
                selection: Binding(get: { FeedUpscaleSwitch.shared.upscaler.rawValue }, set: {
                    if let value = MonitorUpscaler(rawValue: $0) { FeedUpscaleSwitch.shared.upscaler = value }
                }), help: SettingsHelpCopy.feedUpscaler) : nil)
    }

    private var sharing: MonitorSettingsSharingSource {
        .init(enabled: !model.session.isMultiviewBorrowed, unavailableHelp: "Connect to one camera from Your cameras to share its feed with watchers.",
            sharing: Binding(get: { model.shareThisFeed }, set: model.setShareThisFeed),
            passcode: Bindable(model).sharePasscode, controlRequests: Bindable(model).controlRequestsAllowed,
            priority: Bindable(model).broadcastPriority,
            help: .init(sharing: SettingsHelpCopy.shareThisFeed, passcode: SettingsHelpCopy.watcherPasscode,
                controlRequests: SettingsHelpCopy.controlRequests, priority: SettingsHelpCopy.broadcastPriority),
            browseHelp: SettingsHelpCopy.shareFeed, browse: model.openWatcherBrowse,
            passcodeChanged: { WatcherRelayKeychain.app.hostPasscode = $0 },
            joinCode: { AnyView(WatcherWiFiCodeSheet().environment(model)) })
    }

    private var motion: MonitorSettingsMotionSource {
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        return .init(sensitivity: capabilities.gimbal ? .init(value: Bindable(model).gimbalStickSensitivity,
                range: 1...5, help: SettingsHelpCopy.joystickSensitivity, feedback: feedback) : nil,
            headTracking: capabilities.headTracking ? .init(value: Bindable(model).headTrackingEnabled,
                help: SettingsHelpCopy.headTracking, feedback: feedback) : nil,
            joystick: capabilities.gimbal ? .init(
                size: .init(options: MonitorJoystickSize.allCases.map(\.label),
                    selection: Binding(get: { model.virtualJoystickSize.label }, set: { model.virtualJoystickSize = MonitorJoystickSize.fromLabel($0) }),
                    help: SettingsHelpCopy.virtualJoystickSize, feedback: feedback),
                invertPan: .init(value: Bindable(model).virtualJoystickInvertPan,
                    help: SettingsHelpCopy.virtualJoystickInvertPan, feedback: feedback),
                invertTilt: .init(value: Bindable(model).virtualJoystickInvertTilt,
                    help: SettingsHelpCopy.virtualJoystickInvertTilt, feedback: feedback),
                deadZone: .init(value: Bindable(model).virtualJoystickDeadzonePercent,
                    range: GimbalStick.deadzonePercentRange, help: SettingsHelpCopy.virtualJoystickDeadzone, suffix: "%", feedback: feedback),
                response: .init(options: GimbalStick.ResponseCurve.allCases.map(\.label),
                    selection: Binding(get: { model.virtualJoystickResponseCurve.label }, set: { model.virtualJoystickResponseCurve = GimbalStick.ResponseCurve.fromLabel($0) }),
                    help: SettingsHelpCopy.virtualJoystickResponse, feedback: feedback), identifier: "gimbal.virtual") : nil,
            controller: .init(options: GamepadGimbalStick.allCases.map(\.label),
                selection: Binding(get: { OperatorPrefs.gimbalGamepadStick.label }, set: {
                    let next = GamepadGimbalStick.fromLabel($0)
                    guard next != OperatorPrefs.gimbalGamepadStick else { return }
                    OperatorPrefs.gimbalGamepadStick = next
                    model.gimbalPadHeld = false
                    model.session.gimbal.endStick()
                }), help: SettingsHelpCopy.gimbalJoystick, feedback: feedback),
            controllerStatus: model.gamepadConnected ? "Connected" : "Not connected", controllerHelp: SettingsHelpCopy.gamepad)
    }

    private var availableDisplay: Set<MonitorDisplayChrome.Section> {
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        return Set(MonitorDisplayChrome.Section.allCases.filter {
            if $0 == .zoomChip { return capabilities.zoom }
            if $0 == .gimbalStick { return capabilities.gimbal }

            return true
        })
    }
    private var accountState: MonitorAccountState {
        if !model.frameio.isConfigured { return .notConfigured }
        if model.frameio.connecting { return .connecting }
        return model.frameio.isConnected ? .signedIn : .signedOut
    }
    private var cache: MonitorSettingsCacheSource {
        let cameraID = model.session.mediaCameraID
        let revision = model.session.mediaCacheRevision
        let source = model.shell.monitor?.id
        // Delivery exports count and clear with the media cache (A2-58).
        return model.delivery.cacheSource(.init(identity: .init(namespace: cameraID, source: source), revision: revision,
            isCurrent: { model.shell.monitor?.id == source && model.session.mediaCameraID == cameraID && model.session.mediaCacheRevision == revision },
            count: { await model.session.cameraMedia.cacheByteCount(cameraID: cameraID) },
            clear: { try await model.session.clearMediaCache() }))
    }
    private var support: MonitorSettingsSupportSource {
        .init(consent: Binding(get: { AppDiagnostics.reporting.isOptedIn }, set: AppDiagnostics.reporting.setConsent),
            available: AppDiagnostics.reporting.isAvailable, automaticHelp: SettingsHelpCopy.reliabilityReports,
            unavailableHelp: SettingsHelpCopy.reliabilityUnavailable, deleteHelp: SettingsHelpCopy.deleteStoredIncidents,
            sourceHelp: SettingsHelpCopy.sourceHelp, termsHelp: "How you can use OpenPocketCine.",
            sourceURL: OpenPocketCineLinks.source, termsURL: OpenPocketCineLinks.terms,
            saveReport: { DiagnosticCenter.shared.writeReport(session: model.session) },
            deleteReports: { AppDiagnostics.incidents.deleteStoredIncidents {} },
            report: { AnyView(ProblemReportView().environment(model)) },
            document: { kind, close in
                let legal: LegalDocumentView.Kind = switch kind { case .privacy: .privacy; case .licenses: .licenses; case .notice: .notice }
                return AnyView(LegalDocumentView(kind: legal, onClose: close))
            }, shareReport: { AnyView(DiagnosticActivityShareView(items: [$0])) })
    }
    static var appVersionText: String { MonitorSettingsAppInformation.version() }
}
