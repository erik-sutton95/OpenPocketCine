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
        "A second-screen watcher relay is not in this build. One phone talks to one Pocket."
    static let editView =
        "Opens the monitor with an eye on each element you can show or hide."
    static let frameIO =
        "Sign in to upload clips from the share popup. Frame.io needs the internet, so the phone hops off the camera Wi‑Fi for the upload."
    static let shareThisFeed =
        "A second-screen watcher relay is not in this build. One phone talks to one Pocket."
    static let broadcastPriority =
        "When sharing is available, this will trade glass-to-glass delay for a steadier stream. Not in this build."
    static let watcherPasscode =
        "When sharing is available, watchers would enter this code once. Not in this build."
    static let controlRequests =
        "When sharing is available, this would let a watcher ask to drive the camera. Not in this build."
    static let recordConfirmation =
        "Ask before starting or stopping recording to prevent mistaps."
    static let haptics =
        "Short confirmation pulses for critical switches and setting changes."
    static let joystickSensitivity =
        "How far a stick throw moves the gimbal. 4 is the current feel. 5 reaches full speed sooner; 1 is the slowest."
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
    @State private var expandedDisp: PocketDispMode?
    @State private var confirmClearCache = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            LiveDesign.background
            GeometryReader { proxy in
                let portrait = proxy.size.height > proxy.size.width

                Group {
                    if portrait {
                        VStack(alignment: .leading, spacing: 8) {
                            settingsTabStrip
                            settingsTop(stacked: true)
                            settingsContent
                        }
                    } else {
                        VStack(spacing: 8) {
                            settingsTop(
                                stacked: proxy.size.width < OperatorPanelMetrics.topStackWidth
                            )
                            .padding(
                                .leading,
                                OperatorPanelMetrics.closeButtonClearance(safeArea: safeArea))
                            HStack(alignment: .top, spacing: 8) {
                                settingsRail
                                settingsContent
                                    .layoutPriority(1)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                            }
                        }
                    }
                }
                // Fill the physical screen; inset only enough to clear the island (passed
                // safeArea.leading / .trailing) and the 16pt floor on the clean edge.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, OperatorPanelMetrics.settingsTopPadding(safeArea: safeArea))
                .padding(.leading, OperatorPanelMetrics.leadingPadding(safeArea: safeArea))
                .padding(.trailing, OperatorPanelMetrics.trailingPadding(safeArea: safeArea))
                .padding(.bottom, OperatorPanelMetrics.bottomPadding(safeArea: safeArea))
            }

            CloseButton(action: dismiss, size: OperatorPanelMetrics.closeSize)
                .padding(.leading, OperatorPanelMetrics.closeLeading)
                .padding(.top, OperatorPanelMetrics.closeTopPadding(safeArea: safeArea))
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .overlay {
            if let legalKind {
                LegalDocumentView(kind: legalKind, onClose: { self.legalKind = nil })
            }
        }
        .sheet(isPresented: $showLUTPicker) {
            LUTPicker(assist: model.assist)
        }
    }

    private func dismiss() {
        if let onClose {
            onClose()
        } else {
            model.homePanel = nil
        }
    }

    private func settingsTop(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("OpenPocketCine")
                        .font(LiveType.ui(size: 9.5, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(LiveDesign.accent)
                        .textCase(.uppercase)
                    Text("Operator Setup")
                        .font(LiveType.ui(size: 24, weight: .semibold))
                        .foregroundStyle(LiveDesign.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer()
                if !stacked { sessionControls }
            }
            if stacked { sessionControls }
        }
    }

    @ViewBuilder private var sessionControls: some View {
        if model.isLive {
            HStack(spacing: 10) {
                SettingsActionPill(
                    title: "Disconnect",
                    systemImage: "link",
                    slashesIcon: true,
                    tint: LiveDesign.rec,
                    background: LiveDesign.rec.opacity(0.16),
                    fillsHeight: true
                ) { model.disconnect() }
                SettingsLiveTile()
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            SettingsLiveTile()
        }
    }

    private var settingsRail: some View {
        VStack(spacing: 5) {
            ForEach(OperatorSettingsTab.allCases) { tab in
                settingsTabButton(tab)
            }
        }
        .padding(6)
        .frame(width: 146)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: .infinity, alignment: .top)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous))
    }

    private var settingsTabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(OperatorSettingsTab.allCases) { tab in
                    settingsTabButton(tab)
                }
            }
            .padding(6)
        }
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
        )
        .padding(.leading, 45)
    }

    private func settingsTabButton(_ tab: OperatorSettingsTab) -> some View {
        Button {
            if tab != model.operatorSettingsTab {
                OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
            }
            model.operatorSettingsTab = tab
        } label: {
            HStack(spacing: 9) {
                Capsule()
                    .fill(model.operatorSettingsTab == tab ? LiveDesign.accent : Color.clear)
                    .frame(width: 6, height: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.rawValue)
                        .font(LiveType.ui(size: 13, weight: .semibold))
                        .foregroundStyle(
                            model.operatorSettingsTab == tab ? LiveDesign.text : LiveDesign.muted
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(tabSubtitle(tab))
                        .font(LiveType.ui(size: 10.5, weight: .regular))
                        .foregroundStyle(LiveDesign.faint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 43)
            .background(
                model.operatorSettingsTab == tab ? LiveDesign.surface : Color.clear,
                in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
            )
        }
        .buttonStyle(.zcTapTarget)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.operatorSettingsTab.rawValue)
                        .font(LiveType.ui(size: 24, weight: .semibold))
                        .foregroundStyle(LiveDesign.text)
                    Text(subtitle)
                        .font(LiveType.ui(size: 12.5, weight: .regular))
                        .foregroundStyle(LiveDesign.muted)
                        .lineLimit(2)
                }
                Spacer()
                Text(pillText.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(0.6)
                    .foregroundStyle(LiveDesign.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(LiveDesign.accentDim, lineWidth: 1))
            }
            SettingsTabScrollArea(tabID: model.operatorSettingsTab.id) {
                settingsRows
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
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LiveDesign.surface,
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
        )
        .clipShape(RoundedRectangle(cornerRadius: LiveDesign.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
    }

    private var subtitle: String {
        switch model.operatorSettingsTab {
        case .link: "Connection state and link behavior."
        case .sharing: "Coming soon."
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
        case .sharing: "Coming soon"
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
        SettingsLinkHealthCard()

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
        SettingsRowCard {
            Text("Coming soon...")
                .font(LiveType.ui(size: 15, weight: .medium))
                .foregroundStyle(LiveDesign.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 18)
                .padding(.horizontal, 2)
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
        SettingsRowCard {
            SettingsSwitchInlineRow(
                title: "Record Confirmation",
                help: SettingsHelpCopy.recordConfirmation,
                showTopDivider: false,
                isOn: model.recordConfirmationEnabled
            ) { model.recordConfirmationEnabled.toggle() }
            SettingsSwitchInlineRow(
                title: "Haptics",
                help: SettingsHelpCopy.haptics,
                isOn: model.hapticsEnabled
            ) { model.hapticsEnabled.toggle() }
            SettingsInlineRow(
                title: "Joystick Sensitivity",
                help: SettingsHelpCopy.joystickSensitivity,
                stacked: true
            ) {
                GimbalStickSensitivitySlider(
                    value: Bindable(model).gimbalStickSensitivity)
            }
            SettingsSwitchInlineRow(
                title: "Keep Screen Awake",
                help: SettingsHelpCopy.keepScreenAwake,
                isOn: model.keepScreenAwake
            ) { model.keepScreenAwake.toggle() }
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
            guard let returning = model.chromeEditorReturnMode else { return }
            expandedDisp = returning
            model.chromeEditorReturnMode = nil
        }
    }

    @ViewBuilder
    private func dispSectionCard(
        _ section: PocketDispMode,
        reset: @escaping () -> Void
    ) -> some View {
        SettingsRowCard(title: section.settingsTitle, onReset: reset) {
            Button {
                OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                expandedDisp = expandedDisp == section ? nil : section
            } label: {
                HStack {
                    Text(section.settingsCaption)
                        .font(LiveType.ui(size: 11, weight: .semibold))
                        .foregroundStyle(LiveDesign.muted)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Group {
                        if expandedDisp == section {
                            OpcIcon.chevronUp
                        } else {
                            OpcIcon.chevronDown
                        }
                    }
                    .foregroundStyle(LiveDesign.faint)
                    .frame(width: 11, height: 11)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.zcTapTarget)
            if expandedDisp == section {
                dispSectionBody(section)
            }
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
            dispToggles(section == .clean ? Bindable(model).dispClean : Bindable(model).dispLive)
        }
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
