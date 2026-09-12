import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Operator Setup rail tabs — Pocket subset of OpenZCine `OperatorSettingsTab`.
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
        "Experimental. Calibrate Head Lock (centered above the bottom bars) is shared forward: that AirPods pose and that gimbal pose are zero. Head turns set matching pan and tilt angles within the gimbal’s range. Roll is shown only. Needs AirPods with motion (Pro, 3, Max, or later) in your ears. Off by default. STOP clears the lock. On-screen stick, a game controller, and Motion Control takes priority."
    static let joystickSensitivity =
        "How far a stick throw moves the gimbal — on-screen and a connected game controller. Small throws crawl; full throw is fastest. 4 is the captured feel. 5 reaches full speed sooner; 1 is the slowest."
    static let gamepad =
        "A connected game controller. Left stick pans and tilts. Cross/A records. Circle/B recenters. Square/X is rotate-180. Triangle/Y tracks a face. L1/R1 jump zoom out/in. L2/R2 hold-to-zoom (deeper is faster). D-pad up/down ISO, left/right shutter. Unplug rests the stick. On-screen stick wins while you hold it."
    static let keepScreenAwake =
        "Prevents auto-lock while OpenPocketCine is open. A monitor should stay lit. iOS may still dim when the device overheats."
    static let themeHelp =
        "Charcoal field-monitor chrome with Sky Blue accents, tuned for low reflection on set."
    static let supportHelp =
        "Connection, live view, controls, and troubleshooting."
    static let reportHelp =
        "Opens a public issue form on GitHub for this project."
    static let featureHelp =
        "Start an idea in this project's feature-request discussion."
    static let sourceHelp =
        "View the OpenPocketCine project on GitHub. Opening this may leave the camera Wi-Fi if that is the only network."
    static let linkHealth =
        "How healthy the camera link is right now — delivery, not radio RSSI."
    static let clearCache =
        "Removes downloaded clip files from this phone. The clip list stays so you can cache them again from the camera."
    static let cacheFullResolution =
        "Download the original camera file when you open a clip. Off keeps only the 720p proxy to save space. Share needs the original — connect the camera if it is not cached."
    static let shareDiagnostics =
        "Saves a report with connection events, warnings, and crashes. No name, location, or Wi-Fi password. Take a screenshot for TestFlight and paste the copied text into the feedback."
}

enum OperatorSettingsTab: String, CaseIterable, Identifiable {
    case link = "Link"
    case sharing = "Sharing"
    case assist = "View Assist"
    case controls = "Controls"
    case display = "Display"
    case storage = "Storage"
    case system = "System"
    var id: String { rawValue }
}

/// OpenZCine `OperatorSettingsPanel` chrome. Live chrome presents this; home uses `homePanel`.
///
/// `safeArea` is the host-processed inset (OpenZCine `fullScreenPanelSafeArea` / standalone
/// cover): landscape zeros the clean short edge. Do not read `GeometryReader.safeAreaInsets`
/// here — this surface `ignoresSafeArea()`, so SwiftUI reports 0 and the island/trailing
/// card get only the 16pt floor.
struct SettingsRootView: View {
    /// Real device insets after the host zeros the clean landscape edge.
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var keyboardInset: CGFloat = 0
    @State private var legalKind: LegalDocumentView.Kind?
    @State private var showLUTPicker = false
    @State private var showWatcherWiFiCode = false
    @State private var confirmClearCache = false
    @State private var diagnosticsShare: DiagnosticSharePayload?

    var body: some View {
        MonitorPage(safeArea: safeArea) { portrait in
            settingsNavigation(portrait: portrait)
        } detail: { _ in
            settingsContent
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
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

    private func settingsNavigation(portrait: Bool) -> some View {
        VStack(alignment: .leading, spacing: portrait ? 9 : 8) {
            MonitorPageHeading(
                brand: "OpenPocketCine", title: "Operator Setup",
                backLabel: model.isLive ? "Back to live" : "Your cameras", back: dismiss
            )
            ScrollView(portrait ? .horizontal : .vertical, showsIndicators: false) {
                let layout =
                    portrait
                    ? AnyLayout(HStackLayout(spacing: 3))
                    : AnyLayout(VStackLayout(spacing: 3))
                layout {
                    ForEach(OperatorSettingsTab.allCases) { tab in
                        MonitorNavigationItem(
                            tab.rawValue, subtitle: tabSubtitle(tab),
                            selected: model.operatorSettingsTab == tab
                        ) {
                            if tab != model.operatorSettingsTab {
                                OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                            }
                            model.operatorSettingsTab = tab
                        }
                        .fixedSize(horizontal: portrait, vertical: false)
                        .accessibilityIdentifier("monitor.settings.tab.\(tab.id)")
                    }
                }
            }
            .frame(height: portrait ? 44 : nil)
            .accessibilityIdentifier("monitor.settings.tabs")
            sessionControls(portrait: portrait)
        }
    }

    private func sessionControls(portrait: Bool) -> some View {
        let layout =
            portrait
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return layout {
            HStack(spacing: 8) {
                Circle().fill(model.isLive ? Color.green : MonitorTheme.faint)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isLive ? "Active link" : "No camera connected")
                        .font(MonitorTheme.font(11.5, weight: .semibold))
                        .foregroundStyle(MonitorTheme.text)
                    Text(model.session.phase.label)
                        .font(MonitorTheme.font(9)).foregroundStyle(MonitorTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            if model.isLive {
                SettingsActionPill(
                    title: "Disconnect", icon: .link2Off,
                    tint: LiveDesign.rec, background: LiveDesign.rec.opacity(0.12)
                ) { model.disconnect() }
            }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.operatorSettingsTab.rawValue)
                        .font(MonitorTheme.font(17, weight: .semibold))
                        .foregroundStyle(LiveDesign.text)
                    Text(subtitle)
                        .font(MonitorTheme.font(10.5))
                        .foregroundStyle(LiveDesign.muted)
                        .lineLimit(2)
                }
                Spacer()
                Text(pillText.uppercased())
                    .font(MonitorTheme.font(10, weight: .bold)).monospacedDigit()
                    .kerning(0.6)
                    .foregroundStyle(LiveDesign.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(LiveDesign.accentDim, lineWidth: 1))
            }
            SettingsTabScrollArea(tabID: model.operatorSettingsTab.id) {
                MonitorCardColumns {
                    settingsRows
                }
                .padding(.bottom, keyboardInset)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification)
        ) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }
            let overlap = max(0, UIScreen.main.bounds.maxY - frame.minY)
            withAnimation(.easeOut(duration: 0.2)) { keyboardInset = overlap }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardInset = 0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var subtitle: String {
        switch model.operatorSettingsTab {
        case .link: "Connection state and link behavior."
        case .sharing: "Share this feed with OpenPocketCine devices on the same camera Wi-Fi."
        case .assist: "Behavior for live-view tools."
        case .controls: "Touch behavior and safety."
        case .display: "Live view buttons and chrome."
        case .storage: "Local cache and integrations."
        case .system: "App-level behavior."
        }
    }

    private var pillText: String {
        switch model.operatorSettingsTab {
        case .link: "Live"
        case .sharing: "Share"
        case .assist: "Assist"
        case .controls: "Touch"
        case .display: "Visibility"
        case .storage: "Data"
        case .system: "App"
        }
    }

    private func tabSubtitle(_ tab: OperatorSettingsTab) -> String {
        switch tab {
        case .link: "Connection"
        case .sharing: "SHARE"
        case .assist: "Scopes & overlays"
        case .controls: "Dials and safety"
        case .display: "Live view"
        case .storage: "Cache & accounts"
        case .system: "App behavior"
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

        SettingsRowCard(title: "Connection") {
            SettingsInlineRow(
                title: "Current Transport",
                help: SettingsHelpCopy.currentTransport,
                showTopDivider: false
            ) {
                SettingsValueText(value: model.isLive ? "BLE + Wi-Fi active" : "Not connected")
            }
            SettingsInlineRow(
                title: "Phase",
                help: "Where the BLE → Wi-Fi → datalink handshake is right now."
            ) {
                SettingsValueText(value: model.session.phase.label)
            }
            if let ssid = model.session.joinedSSID, !ssid.isEmpty {
                SettingsInlineRow(
                    title: "Camera Wi-Fi",
                    help:
                        "SSID joined for this session. The password stays in the iOS Keychain on this phone."
                ) {
                    SettingsValueText(value: ssid)
                }
            }
        }

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

        SettingsRowCard(title: "Your cameras") {
            if model.savedCameras.isEmpty {
                SettingsInlineRow(
                    title: "Saved",
                    help:
                        "Pair from the home list. Settings does not start a new pair — that stays on Your cameras.",
                    showTopDivider: false
                ) {
                    SettingsValueText(value: "None")
                }
            } else {
                ForEach(Array(model.savedCameras.enumerated()), id: \.element.id) { index, camera in
                    SettingsInlineRow(
                        title: camera.displayName,
                        help: camera.modelName + (camera.lastSSID.map { " · \($0)" } ?? ""),
                        showTopDivider: index > 0
                    ) {
                        SettingsValueText(value: camera.lastSSID ?? "Saved")
                    }
                }
            }
        }
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
            SettingsRowCard {
                SettingsSwitchInlineRow(
                    title: "Share this feed",
                    help: SettingsHelpCopy.shareThisFeed,
                    showTopDivider: false,
                    isOn: model.shareThisFeed
                ) {
                    model.setShareThisFeed(!model.shareThisFeed)
                }
                SettingsInlineRow(
                    title: "Join camera Wi-Fi",
                    help:
                        "On the watching device, scan this code with Camera, join the Wi-Fi, then open Watch a feed."
                ) {
                    Button("Show Wi-Fi code") { showWatcherWiFiCode = true }
                        .font(LiveType.ui(size: 13, weight: .medium))
                }
                SettingsInlineRow(
                    title: "Watcher passcode",
                    help: SettingsHelpCopy.watcherPasscode
                ) {
                    SecureField("Optional", text: Bindable(model).sharePasscode)
                        .font(LiveType.ui(size: 13, weight: .medium))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: model.sharePasscode) { _, value in
                            WatcherRelayKeychain.hostPasscode = value
                        }
                }
                SettingsSwitchInlineRow(
                    title: "Control requests",
                    help: SettingsHelpCopy.controlRequests,
                    isOn: model.controlRequestsAllowed
                ) {
                    model.controlRequestsAllowed.toggle()
                }
                SettingsInlineRow(
                    title: "Broadcast priority",
                    help: SettingsHelpCopy.broadcastPriority,
                    stacked: true
                ) {
                    SettingsSegmented(
                        options: ["Quality", "High", "Medium", "Steady"],
                        selected: ["Quality", "High", "Medium", "Steady"][
                            min(model.broadcastPriority, 3)],
                        compact: true
                    ) { option in
                        let order = ["Quality", "High", "Medium", "Steady"]
                        if let i = order.firstIndex(of: option) {
                            model.broadcastPriority = i
                        }
                    }
                }
            }
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    assistToolCard("False Color", reset: resetFalseColor) {
                        FalseColorAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Waveform", reset: resetWaveform) {
                        WaveformAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Histogram", reset: resetHistogram) {
                        HistogramAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Peaking", reset: resetPeaking) {
                        PeakingAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                VStack(spacing: 8) {
                    assistToolCard("Zebra", reset: resetZebra) {
                        ZebraAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Parade", reset: resetParade) {
                        ParadeAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Vectorscope", reset: resetVectorscope) {
                        VectorscopeAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                    assistToolCard("Traffic Lights", reset: resetTrafficLights) {
                        TrafficLightsAssist.longPressMenu(assist: model.assist, compact: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            VStack(spacing: 8) {
                assistToolCard("False Color", reset: resetFalseColor) {
                    FalseColorAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Zebra", reset: resetZebra) {
                    ZebraAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Waveform", reset: resetWaveform) {
                    WaveformAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Parade", reset: resetParade) {
                    ParadeAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Histogram", reset: resetHistogram) {
                    HistogramAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Vectorscope", reset: resetVectorscope) {
                    VectorscopeAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Peaking", reset: resetPeaking) {
                    PeakingAssist.longPressMenu(assist: model.assist, compact: true)
                }
                assistToolCard("Traffic Lights", reset: resetTrafficLights) {
                    TrafficLightsAssist.longPressMenu(assist: model.assist, compact: true)
                }
            }
        }

        SettingsRowCard(title: "LUT") {
            SettingsInlineRow(
                title: "Look",
                help: "Looks apply on this phone. The file on the camera is unchanged.",
                showTopDivider: false
            ) {
                SettingsValueText(value: lutLabel)
            }
            SettingsInlineRow(title: "Choose look") {
                SettingsActionPill(title: "Open") { showLUTPicker = true }
            }
        }
    }

    @ViewBuilder
    private func assistToolCard<Content: View>(
        _ title: String, reset: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsRowCard(title: title, onReset: reset) { content() }
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
        SettingsRowCard(title: "Touch & safety") {
            SettingsSwitchInlineRow(
                title: "Record confirmation", help: SettingsHelpCopy.recordConfirmation,
                showTopDivider: false, isOn: model.recordConfirmationEnabled
            ) { model.recordConfirmationEnabled.toggle() }
            SettingsSwitchInlineRow(
                title: "Haptics", help: SettingsHelpCopy.haptics, isOn: model.hapticsEnabled
            ) { model.hapticsEnabled.toggle() }
            SettingsSwitchInlineRow(
                title: "Keep screen awake", help: SettingsHelpCopy.keepScreenAwake,
                isOn: model.keepScreenAwake
            ) { model.keepScreenAwake.toggle() }
        }
        let capabilities = OsmoMonitorPresentation.capabilities(model.session)
        if capabilities.gimbal {
            SettingsRowCard(title: "Gimbal") {
                SettingsInlineRow(
                    title: "Joystick sensitivity", help: SettingsHelpCopy.joystickSensitivity,
                    showTopDivider: false, stacked: true
                ) {
                    GimbalStickSensitivitySlider(value: Bindable(model).gimbalStickSensitivity)
                }
                if capabilities.headTracking {
                    SettingsSwitchInlineRow(
                        title: "Head Tracking (Experimental)", help: SettingsHelpCopy.headTracking,
                        isOn: model.headTrackingEnabled
                    ) { model.headTrackingEnabled.toggle() }
                }
            }
        }
        SettingsRowCard(title: "Controller") {
            SettingsInlineRow(
                title: "Gamepad", help: SettingsHelpCopy.gamepad, showTopDivider: false
            ) {
                SettingsValueText(value: model.gamepadConnected ? "Connected" : "Not connected")
            }
        }
    }

    // MARK: - Display (honest: rail-owned)

    @ViewBuilder private var displayRows: some View {
        Group {
            dispSectionCard(
                .live,
                reset: { model.dispLive = .liveDefaults }
            )
            dispSectionCard(
                .clean,
                reset: { model.dispClean = .cleanDefaults }
            )
        }
        .onAppear {
            model.chromeEditorReturnMode = nil
        }
    }

    @ViewBuilder
    private func dispSectionCard(
        _ section: PocketDispMode,
        reset: @escaping () -> Void
    ) -> some View {
        SettingsRowCard(title: section.settingsTitle, onReset: reset) {
            Text(section.settingsCaption)
                .font(MonitorTheme.font(10.5)).foregroundStyle(MonitorTheme.muted)
                .padding(.vertical, 5)
            dispSectionBody(section)
        }
    }

    @ViewBuilder
    private func dispSectionBody(_ section: PocketDispMode) -> some View {
        if model.isLive {
            SettingsActionPill(title: "Edit view") {
                model.beginChromeEditing(section)
            }
            .padding(.vertical, 8)
            .accessibilityHint(SettingsHelpCopy.editView)
        } else {
            Text("Connect to arrange this on the monitor.")
                .font(LiveType.ui(size: 11, weight: .semibold))
                .foregroundStyle(LiveDesign.muted)
                .padding(.vertical, 6)
        }
        dispToggles(section == .clean ? Bindable(model).dispClean : Bindable(model).dispLive)
        if section == .clean {
            cleanViewPinBlock
        }
    }

    @ViewBuilder
    private var cleanViewPinBlock: some View {
        Text("View assists that stay on in clean view")
            .font(LiveType.ui(size: 11, weight: .semibold))
            .foregroundStyle(LiveDesign.muted)
            .padding(.top, 8)
        CleanViewPinStrip()
    }

    @ViewBuilder
    private func dispToggles(_ chrome: Binding<PocketDispChrome>) -> some View {
        SettingsSwitchInlineRow(
            title: "Status Bar",
            help: "REC, timecode, format, and FPS along the top of the feed.",
            showTopDivider: true,
            isOn: chrome.wrappedValue.statusBar
        ) { chrome.wrappedValue.statusBar.toggle() }
        SettingsSwitchInlineRow(
            title: "Tool Bar",
            help: "The view-assist strip under the feed.",
            isOn: chrome.wrappedValue.toolBar
        ) { chrome.wrappedValue.toolBar.toggle() }
        SettingsSwitchInlineRow(
            title: "Camera Values",
            help: "ISO, shutter, white balance, and the rest of the capture strip.",
            isOn: chrome.wrappedValue.cameraValues
        ) { chrome.wrappedValue.cameraValues.toggle() }
        SettingsSwitchInlineRow(
            title: "Lock Button",
            help: "Side-rail lock. Remounts while the interface is locked.",
            isOn: chrome.wrappedValue.lockButton
        ) { chrome.wrappedValue.lockButton.toggle() }
        SettingsSwitchInlineRow(
            title: "Batteries",
            help: "Phone and camera battery cluster.",
            isOn: chrome.wrappedValue.batteries
        ) { chrome.wrappedValue.batteries.toggle() }
        SettingsSwitchInlineRow(
            title: "REC",
            help: "Standby / recording chip on the status bar.",
            isOn: chrome.wrappedValue.recReadout
        ) { chrome.wrappedValue.recReadout.toggle() }
        SettingsSwitchInlineRow(
            title: "Timecode",
            help: "Running timecode on the status bar.",
            isOn: chrome.wrappedValue.timecode
        ) { chrome.wrappedValue.timecode.toggle() }
        SettingsSwitchInlineRow(
            title: "Format",
            help: "Recording resolution and frame rate.",
            isOn: chrome.wrappedValue.format
        ) { chrome.wrappedValue.format.toggle() }
        SettingsSwitchInlineRow(
            title: "Color",
            help: "Color mode chip on the status bar.",
            isOn: chrome.wrappedValue.color
        ) { chrome.wrappedValue.color.toggle() }
        SettingsSwitchInlineRow(
            title: "Storage",
            help: "Remaining media time on the status bar.",
            isOn: chrome.wrappedValue.storage
        ) { chrome.wrappedValue.storage.toggle() }
        SettingsSwitchInlineRow(
            title: "FPS",
            help: "Live-view rate and link bars.",
            isOn: chrome.wrappedValue.fps
        ) { chrome.wrappedValue.fps.toggle() }
        SettingsSwitchInlineRow(
            title: "Record",
            help: "Rail record lamp. Stays available while rolling.",
            isOn: chrome.wrappedValue.railRecord
        ) { chrome.wrappedValue.railRecord.toggle() }
        SettingsSwitchInlineRow(
            title: "Media",
            help: "Rail media button.",
            isOn: chrome.wrappedValue.railMedia
        ) { chrome.wrappedValue.railMedia.toggle() }
        SettingsSwitchInlineRow(
            title: "Settings",
            help: "Rail settings button. Always an escape hatch.",
            isOn: chrome.wrappedValue.railSettings
        ) { chrome.wrappedValue.railSettings.toggle() }
        SettingsSwitchInlineRow(
            title: "Zoom Chip",
            help: "Live zoom readout on the feed.",
            isOn: chrome.wrappedValue.zoomChip
        ) { chrome.wrappedValue.zoomChip.toggle() }
        SettingsSwitchInlineRow(
            title: "Gimbal Stick",
            help: "On-screen gimbal stick.",
            isOn: chrome.wrappedValue.gimbalStick
        ) { chrome.wrappedValue.gimbalStick.toggle() }
        SettingsSwitchInlineRow(
            title: "AF Box",
            help: "Focus and face-tracking brackets on the feed.",
            isOn: chrome.wrappedValue.focusBox
        ) { chrome.wrappedValue.focusBox.toggle() }
    }

    // MARK: - Storage

    @ViewBuilder private var storageRows: some View {
        SettingsRowCard {
            SettingsInlineRow(
                title: "Frame.io",
                help: SettingsHelpCopy.frameIO,
                showTopDivider: false
            ) {
                frameioStatusControl
            }
        }
        SettingsRowCard {
            SettingsSwitchInlineRow(
                title: "Full Resolution Caching",
                help: SettingsHelpCopy.cacheFullResolution,
                showTopDivider: false,
                isOn: model.cacheFullResolution
            ) {
                model.cacheFullResolution.toggle()
            }
            SettingsInlineRow(
                title: "Local Media Cache",
                help: "Originals and playback proxies downloaded from the camera."
            ) {
                SettingsValueText(value: cacheSizeLabel)
            }
            SettingsInlineRow(
                title: "Clear Cache",
                help: SettingsHelpCopy.clearCache
            ) {
                Button {
                    confirmClearCache = true
                } label: {
                    Text("Clear")
                        .font(LiveType.ui(size: 13, weight: .semibold))
                        .foregroundStyle(LiveDesign.rec)
                }
                .buttonStyle(.zcTapTarget)
            }
        }
        .confirmationDialog(
            "Clear cache?",
            isPresented: $confirmClearCache,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                model.session.clearMediaCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes downloaded clip files from this phone. The clip list is kept.")
        }
    }

    @ViewBuilder private var frameioStatusControl: some View {
        if !model.isFrameioConfigured {
            SettingsValueText(value: "Not configured")
        } else if model.frameioConnecting {
            ProgressView().controlSize(.small).tint(LiveDesign.accent)
        } else if model.isFrameioConnected {
            Button {
                model.disconnectFrameio()
            } label: {
                Text("Log out")
                    .font(LiveType.ui(size: 13, weight: .semibold))
                    .foregroundStyle(LiveDesign.accent)
            }
            .buttonStyle(.zcTapTarget)
        } else {
            Button {
                Task {
                    try? await model.connectFrameio()
                }
            } label: {
                Text("Sign in")
                    .font(LiveType.ui(size: 13, weight: .semibold))
                    .foregroundStyle(LiveDesign.accent)
            }
            .buttonStyle(.zcTapTarget)
        }
    }

    private var cacheSizeLabel: String {
        let bytes = model.session.mediaCacheByteCount()
        if bytes == 0 { return "Empty" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - System

    @ViewBuilder private var systemRows: some View {
        SettingsRowCard(title: "Help & Feedback") {
            SettingsInlineRow(
                title: "Support",
                help: SettingsHelpCopy.supportHelp,
                showTopDivider: false
            ) {
                SettingsActionPill(title: "Open") {
                    if let url = OpenPocketCineLinks.support { openURL(url) }
                }
            }
            SettingsInlineRow(title: "Share Diagnostics", help: SettingsHelpCopy.shareDiagnostics) {
                SettingsActionPill(title: "Share") {
                    if let url = DiagnosticCenter.shared.beginShare(session: model.session) {
                        diagnosticsShare = DiagnosticSharePayload(url: url)
                    }
                }
            }
            SettingsInlineRow(title: "Report a Problem", help: SettingsHelpCopy.reportHelp) {
                SettingsActionPill(title: "Report") {
                    if let url = OpenPocketCineLinks.reportProblem { openURL(url) }
                }
            }
            SettingsInlineRow(title: "Request a Feature", help: SettingsHelpCopy.featureHelp) {
                SettingsActionPill(title: "Request") {
                    if let url = OpenPocketCineLinks.featureRequest { openURL(url) }
                }
            }
        }

        SettingsRowCard(title: "Project & Legal") {
            SettingsInlineRow(
                title: "Source Code",
                help: SettingsHelpCopy.sourceHelp,
                showTopDivider: false
            ) {
                SettingsActionPill(title: "Open") {
                    if let url = OpenPocketCineLinks.source { openURL(url) }
                }
            }
            SettingsInlineRow(title: "Privacy", help: "What this app stores on this phone.") {
                SettingsActionPill(title: "Open") {
                    if let url = OpenPocketCineLinks.privacy { openURL(url) }
                }
            }
            SettingsInlineRow(title: "Terms", help: "How you can use OpenPocketCine.") {
                SettingsActionPill(title: "Open") {
                    if let url = OpenPocketCineLinks.terms { openURL(url) }
                }
            }
            SettingsInlineRow(title: "Licenses", help: "Apache 2.0 and third-party notices.") {
                SettingsActionPill(title: "Open") { legalKind = .licenses }
            }
            SettingsInlineRow(title: "NOTICE", help: "Attribution shipped with the app.") {
                SettingsActionPill(title: "Open") { legalKind = .notice }
            }
        }

        SettingsRowCard(title: "App Information") {
            SettingsInlineRow(
                title: "Theme",
                help: SettingsHelpCopy.themeHelp,
                showTopDivider: false
            ) {
                SettingsValueText(value: "DJI Black")
            }
            SettingsInlineRow(
                title: "Protocol Implementation",
                help:
                    "Camera control speaks DUML over Bluetooth and the camera's Wi-Fi. No DJI SDK is bundled or required."
            ) {
                SettingsValueText(value: "DUML / BLE + Wi-Fi")
            }
            SettingsInlineRow(
                title: "App Version",
                help: "Current OpenPocketCine build from the native project metadata."
            ) {
                SettingsValueText(value: Self.appVersionText)
            }
        }
    }

    static var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// One switch per cinema view-assist tool — the DISP 2 keep list.
struct CleanViewPinStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 7)], spacing: 7) {
            ForEach(LiveAssistTool.cleanPinCases) { tool in
                DisplayToggleItem(
                    title: tool.displaySettingsTitle,
                    isOn: model.assist.cleanViewPinnedTools.contains(tool)
                ) {
                    OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                    model.assist.toggleCleanViewPin(tool)
                }
                .accessibilityLabel("Keep \(tool.displaySettingsTitle) in clean view")
                .accessibilityValue(
                    model.assist.cleanViewPinnedTools.contains(tool) ? "On" : "Off")
            }
        }
    }
}
