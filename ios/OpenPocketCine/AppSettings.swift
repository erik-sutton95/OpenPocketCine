import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI
import UIKit


enum AppPanel: String, Identifiable {
    case settings, media, privacy, terms, licenses, notice
    var id: String { rawValue }
}

enum OpenPocketCineLinks {
    static let source = URL(string: "https://github.com/erik-sutton95/OpenPocketCine")
    static let support = URL(
        string: "https://github.com/erik-sutton95/OpenPocketCine/discussions/categories/q-a")
    static let reportProblem = URL(
        string: "https://github.com/erik-sutton95/OpenPocketCine/issues/new?template=bug_report.yml"
    )
    static let featureRequest = URL(
        string: "https://github.com/erik-sutton95/OpenPocketCine/discussions/new?category=ideas")
    static let privacy = URL(string: "https://openpocketcine.app/privacy/")
    static let terms = URL(string: "https://openpocketcine.app/terms/")
}

/// Live chrome and home both present this. `onClose` lets a cover dismiss without `homePanel`.
struct AppSettingsView: View {
    /// OpenZCine `OperatorSettingsPanel.safeArea` \u{2014} processed landscape insets from the host.
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil

    var body: some View {
        SettingsRootView(safeArea: safeArea, onClose: onClose)
    }
}

// MARK: - Shared Operator Setup / Media chrome

struct HelpBadge: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            MonitorIcon.info
                .foregroundStyle(LiveDesign.faint)
                .frame(width: 9, height: 9)
                .frame(width: 16, height: 16)
                .background(LiveDesign.background.opacity(0.5), in: Circle())
                .overlay(Circle().stroke(LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.monitorTapTarget)
        .popover(isPresented: $showing) {
            Text(text)
                .font(MonitorTheme.font(12, weight: .regular))
                .foregroundStyle(LiveDesign.text)
                .padding(12)
                .frame(width: 248)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }
}

struct SettingsInlineRow<Trailing: View>: View {
    @Environment(\.monitorInspectorHelp) private var inspectorHelp
    let title: String
    var help: String? = nil
    var showTopDivider = true
    var stacked: Bool = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            if showTopDivider {
                Rectangle().fill(LiveDesign.hairline).frame(height: 1)
            }
            if stacked {
                stackedRow
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        labelRow
                        Spacer(minLength: 12)
                        trailing
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    stackedRow
                }
            }
            if inspectorHelp == true, let help, !help.isEmpty {
                Text(help)
                    .font(MonitorTheme.font(10)).foregroundStyle(MonitorTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }
        }
    }

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            labelRow
            trailing
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var labelRow: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(
                    MonitorTheme.font(CGFloat(MonitorSettingsCardMetrics.rowTitlePointSize), weight: .semibold)
                )
                .foregroundStyle(LiveDesign.text)
                .lineLimit(stacked ? 2 : 1)
                .fixedSize(horizontal: !stacked, vertical: true)
                .layoutPriority(1)
                .accessibilityIdentifier("monitor.settings.row.title")
            if inspectorHelp == nil, let help { HelpBadge(text: help) }
            if !stacked { Spacer(minLength: 0) }
        }
    }
}

struct SettingsValueText: View {
    let value: String
    var body: some View {
        Text(value)
            .font(MonitorTheme.font(12.5, weight: .medium)).monospacedDigit()
            .foregroundStyle(LiveDesign.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct SettingsActionPill: View {
    let title: String
    var icon: MonitorIcon? = nil
    var tint: Color = LiveDesign.accent
    var background: Color = LiveDesign.accentDim
    var fillsHeight = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    icon.frame(width: 13, height: 13)
                }
                Text(title.uppercased())
                    .font(MonitorTheme.font(10.5, weight: .bold)).monospacedDigit()
                    .kerning(0.6)
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxHeight: fillsHeight ? .infinity : nil)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.monitorTapTarget)
    }
}

struct SettingsSwitchGraphic: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? LiveDesign.accentDim : LiveDesign.surface)
            .frame(width: 39, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? LiveDesign.accent : LiveDesign.muted)
                    .frame(width: 15, height: 15)
                    .padding(3.5)
            }
            .overlay(Capsule().stroke(isOn ? LiveDesign.accentDim : LiveDesign.hairline))
    }
}

/// OpenZCine `DisplayToggleItem` \u{2014} compact switch tile for the DISP 2 assist pin grid.
struct DisplayToggleItem: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(MonitorTheme.font(11.5, weight: .semibold))
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                Spacer(minLength: 0)
                SettingsSwitchGraphic(isOn: isOn)
                    .scaleEffect(0.86)
            }
            .padding(.horizontal, 9)
            .frame(height: 46)
            .background(
                LiveDesign.background.opacity(0.38),
                in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                    .stroke(LiveDesign.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.monitorTapTarget)
    }
}

struct SettingsSwitchInlineRow: View {
    let title: String
    var help: String? = nil
    var showTopDivider = true
    var stacked: Bool = false
    let isOn: Bool
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        SettingsInlineRow(
            title: title, help: help, showTopDivider: showTopDivider, stacked: stacked
        ) {
            Button {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
                action()
            } label: {
                SettingsSwitchGraphic(isOn: isOn)
            }
            .buttonStyle(.monitorTapTarget)
            .modifier(SettingsSwitchAccess(identifier: identifier, title: title, isOn: isOn))
        }
    }
}

private struct SettingsSwitchAccess: ViewModifier {
    let identifier: String?
    let title: String
    let isOn: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "On" : "Off")
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}

struct SettingsSegmented: View {
    let options: [String]
    let selected: String
    var compact: Bool = false
    var stacked: Bool = false
    let onSelect: (String) -> Void

    var body: some View {
        MonitorSegmentedControl(
            options: options, selection: Binding(get: { selected }, set: onSelect),
            compact: compact, stacked: stacked, title: { $0 },
            onSelectionFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            }
        )
        .buttonStyle(.monitorTapTarget)
    }
}

enum SettingsRowChrome {
    case liquidGlass
    case surface
}

struct SettingsResetButton: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    var body: some View {
        Button {
            OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
            action()
        } label: {
            MonitorIcon.refreshCw
                .foregroundStyle(LiveDesign.muted)
                .frame(width: 12, height: 12)
                .frame(width: 28, height: 28)
                .background(LiveDesign.background.opacity(0.42), in: Circle())
                .overlay(Circle().stroke(LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.monitorTapTarget)
        .accessibilityLabel("Reset to defaults")
    }
}

struct GimbalStickSensitivitySlider: View {
    @Binding var value: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 9) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: {
                        let next = GimbalStick.clampedSensitivity(Int($0.rounded()))
                        guard next != value else { return }
                        OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                        value = next
                    }),
                in: 1...5,
                step: 1
            )
            .tint(LiveDesign.accent)
            .accessibilityLabel("Joystick sensitivity")
            .accessibilityValue("\(value)")
            Text("\(value)")
                .font(MonitorTheme.font(12, weight: .medium)).monospacedDigit()
                .foregroundStyle(LiveDesign.text)
                .frame(width: 24, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

struct VirtualJoystickDeadzoneSlider: View {
    @Binding var value: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 9) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: {
                        let next = GimbalStick.clampedDeadzonePercent(Int($0.rounded()))
                        guard next != value else { return }
                        OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                        value = next
                    }),
                in: Double(
                    GimbalStick.deadzonePercentRange.lowerBound)...Double(
                        GimbalStick.deadzonePercentRange.upperBound),
                step: 1
            )
            .tint(LiveDesign.accent)
            .accessibilityIdentifier("gimbal.virtual.deadzone")
            .accessibilityLabel("Dead zone")
            .accessibilityValue("\(value)%")
            Text("\(value)%")
                .font(MonitorTheme.font(12, weight: .medium)).monospacedDigit()
                .foregroundStyle(LiveDesign.text)
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
        }
    }
}


extension OperatorHaptics {
    /// The operator's haptics switch, read at each tap.
    static let app = OperatorHaptics { OperatorPrefs.hapticsEnabled }
}

struct SettingsRowCard<Content: View>: View {
    var title: String? = nil
    var onReset: (() -> Void)? = nil
    var chrome: SettingsRowChrome = .surface
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        onReset: (() -> Void)? = nil,
        chrome: SettingsRowChrome = .surface,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onReset = onReset
        self.chrome = chrome
        self.content = content()
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(MonitorSettingsCardMetrics.titleContentGap)) {
            if let title {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(
                            MonitorTheme.font(CGFloat(MonitorSettingsCardMetrics.titlePointSize), weight: .semibold)
                        )
                        .foregroundStyle(LiveDesign.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("monitor.settings.card.title")
                    Spacer(minLength: 0)
                    if let onReset {
                        SettingsResetButton(action: onReset)
                    }
                }
                .frame(
                    minHeight: CGFloat(MonitorSettingsCardMetrics.titleMinHeight),
                    alignment: .leading
                )
                .padding(.top, CGFloat(MonitorSettingsCardMetrics.titleTopPadding))
            }
            content
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsRowChromeStyle(chrome: chrome, shape: cardShape))
    }
}

private struct SettingsRowChromeStyle: ViewModifier {
    let chrome: SettingsRowChrome
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        switch chrome {
        case .liquidGlass:
            content.liquidGlass(in: shape)
        case .surface:
            content
                .monitorCardSurface()
        }
    }
}

struct SettingsTabScrollArea<Content: View>: View {
    let tabID: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 22)
        }
        .scrollDismissesKeyboard(.interactively)
        .monitorScrollFade()
        .id(tabID)
    }
}

struct SettingsDashScale: View {
    let title: String
    let caption: String
    let score: Int

    private var band: MonitorLinkHealthBand { .init(score: score) }

    private var bandColor: Color {
        MonitorTheme.linkHealthColor(band)
    }
    private var bandName: String {
        switch band {
        case .poor: "POOR"
        case .watch: "WATCH"
        case .stable: "STABLE"
        }
    }
    private var litCount: Int {
        switch band {
        case .poor: 4
        case .watch: 8
        case .stable: 12
        }
    }
    private var bandSlot: Int {
        switch band {
        case .poor: 0
        case .watch: 1
        case .stable: 2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(MonitorTheme.font(13, weight: .semibold))
                .foregroundStyle(LiveDesign.text)
            Text(caption)
                .font(MonitorTheme.font(11.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(LiveDesign.muted)
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { slot in
                    ZStack {
                        if slot == bandSlot { marker }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 19)
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dashColor(index))
                        .frame(height: 6)
                }
            }
            HStack(spacing: 0) {
                legend("Poor", "<50").frame(maxWidth: .infinity, alignment: .leading)
                legend("Watch", "50-79").frame(maxWidth: .infinity, alignment: .center)
                legend("Stable", "80+").frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous))
    }

    private var marker: some View {
        Text(bandName)
            .font(MonitorTheme.font(9.5, weight: .bold)).monospacedDigit()
            .kerning(0.5)
            .foregroundStyle(bandColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bandColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(bandColor, lineWidth: 1))
    }

    private func dashColor(_ index: Int) -> Color {
        guard index < litCount else { return LiveDesign.hairlineStrong }
        if index < 4 { return MonitorTheme.linkHealthColor(.poor).opacity(0.8) }
        if index < 8 { return MonitorTheme.linkHealthColor(.watch).opacity(0.85) }
        return MonitorTheme.linkHealthColor(.stable).opacity(0.9)
    }

    private func legend(_ name: String, _ sub: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(MonitorTheme.font(10, weight: .semibold))
                .foregroundStyle(LiveDesign.muted)
            Text(sub)
                .font(MonitorTheme.font(9, weight: .regular)).monospacedDigit()
                .foregroundStyle(LiveDesign.faint)
        }
    }
}

struct SettingsLinkHealthCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        MonitorSettingsLinkHealthCard(isLive: model.isLive, signalBars: model.session.liveSignalBars)
    }
}

struct SettingsLiveTile: View {
    @Environment(AppModel.self) private var model
    @State private var displayedFPS = "\u{2014}"
    @State private var lastFPSCommit: CFAbsoluteTime = 0

    private var isLinked: Bool { model.isLive }

    private var tint: Color {
        guard isLinked else { return LiveDesign.faint }
        switch model.session.liveSignalBars {
        case 3...: return LiveDesign.good
        case 2: return LiveDesign.accent
        case 1: return LiveDesign.rec
        default: return model.session.hasVideoFormat ? LiveDesign.accent : LiveDesign.faint
        }
    }

    private var litBars: Int {
        guard isLinked else { return 0 }
        if model.session.liveSignalBars > 0 { return model.session.liveSignalBars }
        return model.session.hasVideoFormat ? 2 : 1
    }

    private var detail: String {
        let name =
            model.session.connectedCamera?.name
            ?? model.savedCameras.first?.displayName
            ?? "Pocket"
        let transport = isLinked ? "BLE + Wi-Fi" : "\u{2014}"
        return "\(name) · \(transport) · \(displayedFPS) FPS"
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.7), radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(isLinked ? "Active Link" : "No Link")
                    .font(MonitorTheme.font(12, weight: .semibold))
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                    .fixedSize()
                Text(isLinked ? detail : model.session.phase.label)
                    .font(MonitorTheme.font(10.5, weight: .medium)).monospacedDigit()
                    .foregroundStyle(LiveDesign.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            index < litBars
                                ? tint.opacity(0.52 + Double(index) * 0.12)
                                : LiveDesign.hairline
                        )
                        .frame(width: 3, height: CGFloat(6 + index * 3))
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: litBars)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LiveDesign.surface,
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
        .onAppear { commitFPS(model.session.liveFPS) }
        .onChange(of: model.session.liveFPS) { _, next in
            commitFPS(next)
        }
    }

    private func commitFPS(_ incoming: String) {
        let compact = incoming.hasSuffix(".00") ? String(incoming.dropLast(3)) : incoming
        let now = CFAbsoluteTimeGetCurrent()
        if lastFPSCommit == 0 || now - lastFPSCommit >= 0.5
            || compact != displayedFPS
                && (Double(compact) == nil || Double(displayedFPS) == nil)
        {
            displayedFPS = compact.isEmpty ? "\u{2014}" : compact
            lastFPSCommit = now
            return
        }
        guard now - lastFPSCommit >= 0.5 else { return }
        displayedFPS = compact.isEmpty ? "\u{2014}" : compact
        lastFPSCommit = now
    }
}

struct AppPanelChrome<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("OPENPOCKETCINE")
                        .font(MonitorTheme.font(10, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(StartupColors.muted)
                    Text(title)
                        .font(MonitorTheme.font(17, weight: .bold))
                        .foregroundStyle(StartupColors.ink)
                }
                Spacer()
                Button("Done", action: onClose)
                    .font(MonitorTheme.font(16, weight: .semibold))
                    .foregroundStyle(StartupColors.darkText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        StartupColors.accent,
                        in: RoundedRectangle(cornerRadius: MonitorTheme.radius)
                    )
                    .buttonStyle(.monitorTapTarget)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
            .monitorScrollFade()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StartupColors.backdrop.ignoresSafeArea())
        .foregroundStyle(StartupColors.ink)
        .preferredColorScheme(.dark)
    }
}
