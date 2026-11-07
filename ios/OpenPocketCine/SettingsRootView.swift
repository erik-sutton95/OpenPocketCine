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
    static let themeHelp =
        "Charcoal field-monitor chrome with Sky Blue accents, tuned for low reflection on set."
}


struct SettingsRootView: View {
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @State private var teleprompterPresented = false

    var body: some View {
        MonitorOperatorSettingsScreen(shell: model.shell, brand: "OpenPocketCine",
            preferences: OperatorPrefs.common, display: OperatorPrefs.display, assist: model.assist,
            library: model.session.mediaLibrary, operatorSession: model.operatorSession,
            configuration: configuration)
        .fullScreenCover(isPresented: $teleprompterPresented) {
            MonitorTeleprompterScreen(model: model.teleprompter,
                onClose: { teleprompterPresented = false },
                onUseScript: model.isLive ? {
                    model.assist.teleprompterEnabled = true
                    model.assist.persist()
                    teleprompterPresented = false
                    closeSettings()
                } : nil)
        }
    }

    private func closeSettings() {
        model.settingsAccount.retire()
        model.settingsSupport.retire()
        if let onClose { onClose() } else { model.shell.dismissCover() }
    }

    private var configuration: MonitorOperatorSettingsConfiguration<MonitorLUTLooks> {
        let transfer = model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709
        return .init(safeArea: safeArea, phase: model.session.phase.label, isLive: model.isLive,
            sharingSubtitle: MonitorSettingsCopy.sharingSubtitle(app: "OpenPocketCine"),
            close: closeSettings,
            disconnect: {
                model.settingsAccount.retire()
                model.settingsSupport.retire()
                model.disconnect()
            }, feedback: feedback, link: link, sharing: sharing,
            assist: .init(state: model.assist, stores: .app, falseColorLooks: .app, palette: LiveDesign.self,
                haptics: .app, transfer: transfer, clipByte: model.monitorSamples.exposureCeiling.clipByte(transfer: transfer),
                exposureHelp: "Show the camera's exposure meter at the picture's left edge in DISP 1. Auto and Manual use the camera reading without changing exposure settings.",
                lookLabel: model.assist.lutStatusLabel, lookCatalog: { AnyView(LUTPicker(assist: model.assist)) }),
            controls: .init(recordConfirmation: Bindable(model).recordConfirmationEnabled,
                haptics: .init(value: Bindable(model).hapticsEnabled, help: MonitorSettingsCopy.gimbalHaptics),
                keepAwake: .init(value: Bindable(model).keepScreenAwake, help: MonitorSettingsCopy.keepScreenAwake),
                input: .init(remoteShutter: .volumeButtons(enabled: Bindable(model).remoteShutterEnabled)),
                motion: motion, teleprompter: { teleprompterPresented = true }),
            display: .init(hdr: .init(value: Bindable(model).hdrDisplay, help: MonitorSettingsCopy.hdrPanel(cameraMode: "HDR/HLG color mode")),
                sections: availableDisplay),
            cache: .init(source: cache,
                cacheOriginals: .init(value: Bindable(model).cacheFullResolution, help: MonitorSettingsCopy.cacheFullResolution),
                clearHelp: MonitorSettingsCopy.clearAllCamerasCache),
            account: .init(title: "Frame.io", help: MonitorSettingsCopy.accountHelp(service: "Frame.io"), model: model.settingsAccount,
                actions: model.settingsAccountActions, readState: { accountState },
                consentTitle: MonitorSettingsCopy.accountConsentTitle,
                consentMessage: MonitorSettingsCopy.accountConsentMessage(service: "Frame.io"),
                consentAction: MonitorSettingsCopy.accountConsentAction),
            support: support,
            information: .init(theme: "DJI Black", protocolName: "DUML / BLE + Wi-Fi", version: Self.appVersionText,
                themeHelp: SettingsHelpCopy.themeHelp, protocolHelp: "Camera control speaks DUML over Bluetooth and the camera's Wi-Fi. No DJI SDK is bundled or required.",
                versionHelp: MonitorSettingsCopy.versionHelp(app: "OpenPocketCine")))
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
            processing: .init(upscaler: Binding(get: { FeedUpscaleSwitch.shared.upscaler },
                set: { FeedUpscaleSwitch.shared.upscaler = $0 })))
    }

    private var sharing: MonitorSettingsSharingSource {
        .init(enabled: !model.session.isMultiviewBorrowed, unavailableHelp: "Connect to one camera from Your cameras to share its feed with watchers.",
            sharing: Binding(get: { model.shareThisFeed }, set: model.setShareThisFeed),
            passcode: Bindable(model).sharePasscode, controlRequests: Bindable(model).controlRequestsAllowed,
            priority: Bindable(model).broadcastPriority,
            help: .init(sharing: MonitorSettingsCopy.shareThisFeed, passcode: MonitorSettingsCopy.watcherPasscode,
                controlRequests: MonitorSettingsCopy.controlRequests, priority: MonitorSettingsCopy.broadcastPriority),
            browseHelp: MonitorSettingsCopy.shareThisFeed, browse: model.openWatcherBrowse,
            passcodeChanged: { WatcherRelayKeychain.app.hostPasscode = $0 },
            joinCode: { AnyView(WatcherWiFiCodeSheet().environment(model)) })
    }

    private var motion: MonitorSettingsMotionSource {
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        return .init(sensitivity: capabilities.gimbal ? .init(value: Bindable(model).gimbalStickSensitivity,
                range: 1...5, help: MonitorSettingsCopy.joystickSensitivity, feedback: feedback) : nil,
            headTracking: capabilities.headTracking ? .init(value: Bindable(model).headTrackingEnabled,
                help: MonitorSettingsCopy.headTracking, feedback: feedback) : nil,
            joystick: capabilities.gimbal ? .init(
                size: .init(options: MonitorJoystickSize.allCases.map(\.label),
                    selection: Binding(get: { model.virtualJoystickSize.label }, set: { model.virtualJoystickSize = MonitorJoystickSize.fromLabel($0) }),
                    help: MonitorSettingsCopy.virtualJoystickSize, feedback: feedback),
                invertPan: .init(value: Bindable(model).virtualJoystickInvertPan,
                    help: MonitorSettingsCopy.virtualJoystickInvertPan, feedback: feedback),
                invertTilt: .init(value: Bindable(model).virtualJoystickInvertTilt,
                    help: MonitorSettingsCopy.virtualJoystickInvertTilt, feedback: feedback),
                deadZone: .init(value: Bindable(model).virtualJoystickDeadzonePercent,
                    range: GimbalStick.deadzonePercentRange, help: MonitorSettingsCopy.virtualJoystickDeadzone, suffix: "%", feedback: feedback),
                response: .init(options: GimbalStick.ResponseCurve.allCases.map(\.label),
                    selection: Binding(get: { model.virtualJoystickResponseCurve.label }, set: { model.virtualJoystickResponseCurve = GimbalStick.ResponseCurve.fromLabel($0) }),
                    help: MonitorSettingsCopy.virtualJoystickResponse, feedback: feedback), identifier: "gimbal.virtual") : nil,
            controller: .init(options: GamepadGimbalStick.allCases.map(\.label),
                selection: Binding(get: { OperatorPrefs.gimbalGamepadStick.label }, set: {
                    let next = GamepadGimbalStick.fromLabel($0)
                    guard next != OperatorPrefs.gimbalGamepadStick else { return }
                    OperatorPrefs.gimbalGamepadStick = next
                    model.gimbalPadHeld = false
                    model.session.gimbal.endStick()
                }), help: MonitorSettingsCopy.gimbalJoystick, feedback: feedback),
            controllerStatus: model.gamepadConnected ? "Connected" : "Not connected", controllerHelp: MonitorSettingsCopy.gamepad)
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
        if model.frameio.connecting || model.settingsAccount.busy { return .connecting }
        return model.frameio.isConnected ? .signedIn : .signedOut
    }
    private var cache: MonitorSettingsCacheSource { model.settingsCacheSource }
    private var support: MonitorSettingsSupportSource {
        .init(consent: Binding(get: { AppDiagnostics.reporting.isOptedIn }, set: AppDiagnostics.reporting.setConsent),
            available: AppDiagnostics.reporting.isAvailable, automaticHelp: MonitorSettingsCopy.automaticReports,
            unavailableHelp: MonitorSettingsCopy.automaticReportsUnavailable,
            sourceHelp: MonitorSettingsCopy.sourceHelp(app: "OpenPocketCine"), termsHelp: MonitorSettingsCopy.termsHelp(app: "OpenPocketCine"),
            model: model.settingsSupport, actions: model.settingsSupportActions, links: [], privacy: nil,
            source: browserDestination("settings.source", "Source Code", OpenPocketCineLinks.source),
            terms: browserDestination("settings.terms", "Terms of Use", OpenPocketCineLinks.terms),
            reportTitle: "Report a problem", reportActionTitle: "Open", diagnosticsHelp: MonitorSettingsCopy.shareDiagnostics,
            report: { model.isProblemReportPresented = true },
            shareReport: { AnyView(MonitorActivityShareSheet(items: [$0])) },
            deleteStoredReports: { AppDiagnostics.incidents.deleteStoredIncidents {} },
            deleteReportsHelp: MonitorSettingsCopy.deleteSavedFeedReports,
            supportEmail: "support@openpocketcine.app", legal: .settings)
    }
    private func browserDestination(_ id: String, _ title: String, _ url: URL?) -> MonitorSettingsBrowserDestination? {
        url.map {
            .init(id: id, title: title, url: $0,
                confirmationMessage: MonitorSettingsCopy.browserConfirmation(title: title, app: "OpenPocketCine"))
        }
    }
    static var appVersionText: String { MonitorSettingsAppInformation.version() }
}


extension AppModel {
    var settingsCacheSource: MonitorSettingsCacheSource {
        let model = self
        let session = model.session
        let revision = session.mediaCacheRevision
        let source = model.shell.monitor?.id
        // Delivery exports count and clear with the media cache (A2-58). The scope is every
        // camera's cache on this phone (A2-33), so the identity is the shared cache root.
        return model.delivery.cacheSource(.init(
            identity: .init(namespace: session.cameraMedia.mediaCacheRootPath, source: source), revision: revision,
            isCurrent: { model.session === session && model.shell.monitor?.id == source },
            count: { await session.cameraMedia.cacheByteCountAllCameras() },
            clear: { try await session.clearAllCamerasMediaCache() }))
    }
}
