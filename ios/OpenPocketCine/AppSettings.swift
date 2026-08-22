import OpenPocketViewCore
import SwiftUI
import UIKit

/// DISP 1 Live / DISP 2 Clean. Command (DISP 3) is not in this build.
enum PocketDispMode: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case live
    case clean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .clean: "Clean"
        }
    }

    var settingsTitle: String {
        switch self {
        case .live: "DISP 1 · Live"
        case .clean: "DISP 2 · Clean"
        }
    }

    var settingsCaption: String {
        switch self {
        case .live:
            "The full monitor. Set what it shows in Edit view."
        case .clean:
            "A stripped-back image. Same elements as DISP 1 — status, tool and capture bars start off. Pin which view assists stay on."
        }
    }
}

/// Per-DISP chrome map for Pocket live / clean.
struct PocketDispChrome: Equatable, Codable, Sendable {
    /// Containers first, then rail / on-feed chrome, then status-bar cells last so
    /// Edit-view badges keep the big boxes' preferred corners.
    enum Section: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
        case statusBar
        case toolBar
        case cameraValues
        case lockButton
        case batteries
        case railRecord
        case railMedia
        case railSettings
        case zoomChip
        case gimbalStick
        case focusBox
        case recReadout
        case timecode
        case format
        case color
        case storage
        case fps

        var id: String { rawValue }

        var title: String {
            switch self {
            case .statusBar: "Status Bar"
            case .toolBar: "Tool Bar"
            case .cameraValues: "Camera Values"
            case .lockButton: "Lock Button"
            case .batteries: "Batteries"
            case .railRecord: "Record"
            case .railMedia: "Media"
            case .railSettings: "Settings"
            case .zoomChip: "Zoom Chip"
            case .gimbalStick: "Gimbal Stick"
            case .focusBox: "Face Box"
            case .recReadout: "REC"
            case .timecode: "Timecode"
            case .format: "Format"
            case .color: "Color"
            case .storage: "Storage"
            case .fps: "FPS"
            }
        }
    }

    var statusBar = true
    var toolBar = true
    var cameraValues = true
    var lockButton = true
    var batteries = true
    var recReadout = true
    var timecode = true
    var format = true
    var color = true
    var storage = true
    var fps = true
    var railRecord = true
    var railMedia = true
    var railSettings = true
    var zoomChip = true
    var gimbalStick = true
    var focusBox = true

    static let liveDefaults = PocketDispChrome()

    static let cleanDefaults = PocketDispChrome(
        statusBar: false,
        toolBar: false,
        cameraValues: false,
        lockButton: false,
        batteries: true,
        recReadout: true,
        timecode: true,
        format: true,
        color: true,
        storage: true,
        fps: true,
        railRecord: true,
        railMedia: true,
        railSettings: true,
        zoomChip: true,
        gimbalStick: true,
        focusBox: true
    )

    func isVisible(_ section: Section) -> Bool {
        switch section {
        case .statusBar: statusBar
        case .toolBar: toolBar
        case .cameraValues: cameraValues
        case .lockButton: lockButton
        case .batteries: batteries
        case .railRecord: railRecord
        case .railMedia: railMedia
        case .railSettings: railSettings
        case .zoomChip: zoomChip
        case .gimbalStick: gimbalStick
        case .focusBox: focusBox
        case .recReadout: recReadout
        case .timecode: timecode
        case .format: format
        case .color: color
        case .storage: storage
        case .fps: fps
        }
    }

    mutating func toggle(_ section: Section) {
        switch section {
        case .statusBar: statusBar.toggle()
        case .toolBar: toolBar.toggle()
        case .cameraValues: cameraValues.toggle()
        case .lockButton: lockButton.toggle()
        case .batteries: batteries.toggle()
        case .railRecord: railRecord.toggle()
        case .railMedia: railMedia.toggle()
        case .railSettings: railSettings.toggle()
        case .zoomChip: zoomChip.toggle()
        case .gimbalStick: gimbalStick.toggle()
        case .focusBox: focusBox.toggle()
        case .recReadout: recReadout.toggle()
        case .timecode: timecode.toggle()
        case .format: format.toggle()
        case .color: color.toggle()
        case .storage: storage.toggle()
        case .fps: fps.toggle()
        }
    }

    /// Live and clean offer the same list — clean is DISP 1 with different defaults.
    static func isConfigurable(_ section: Section, in mode: PocketDispMode) -> Bool {
        _ = section
        _ = mode
        return true
    }

    static func configurableSections(in mode: PocketDispMode) -> [Section] {
        Section.allCases.filter { isConfigurable($0, in: mode) }
    }
}

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
    /// OpenZCine `OperatorSettingsPanel.safeArea` — processed landscape insets from the host.
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil

    var body: some View {
        SettingsRootView(safeArea: safeArea, onClose: onClose)
    }
}

// MARK: - Shared Operator Setup / Media chrome

struct CloseButton: View {
    var action: () -> Void
    var size: CGFloat = 34

    var body: some View {
        Button(action: action) {
            OpcIcon.x
                .frame(width: size * 0.38, height: size * 0.38)
                .foregroundStyle(LiveDesign.text)
                .frame(width: size, height: size)
                .glassCircle(interactive: true)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Close")
    }
}

struct HelpBadge: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            OpcIcon.info
                .foregroundStyle(LiveDesign.faint)
                .frame(width: 9, height: 9)
                .frame(width: 16, height: 16)
                .background(LiveDesign.background.opacity(0.5), in: Circle())
                .overlay(Circle().stroke(LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
        .popover(isPresented: $showing) {
            Text(text)
                .font(LiveType.ui(size: 12, weight: .regular))
                .foregroundStyle(LiveDesign.text)
                .padding(12)
                .frame(width: 248)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }
}

struct SettingsInlineRow<Trailing: View>: View {
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
                .font(LiveType.ui(size: 12.5, weight: .semibold))
                .foregroundStyle(LiveDesign.text)
                .lineLimit(stacked ? 2 : 1)
                .fixedSize(horizontal: !stacked, vertical: false)
                .layoutPriority(1)
            if let help { HelpBadge(text: help) }
            if !stacked { Spacer(minLength: 0) }
        }
    }
}

struct SettingsValueText: View {
    let value: String
    var body: some View {
        Text(value)
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .foregroundStyle(LiveDesign.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct SettingsActionPill: View {
    let title: String
    var systemImage: String? = nil
    var slashesIcon = false
    var tint: Color = LiveDesign.accent
    var background: Color = LiveDesign.accentDim
    var fillsHeight = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .overlay {
                            if slashesIcon {
                                ZStack {
                                    Capsule()
                                        .fill(background)
                                        .frame(width: 4.2, height: 19)
                                    Capsule()
                                        .fill(tint)
                                        .frame(width: 1.7, height: 19)
                                }
                                .rotationEffect(.degrees(-45))
                            }
                        }
                }
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
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
        .buttonStyle(.zcTapTarget)
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

/// OpenZCine `DisplayToggleItem` — compact switch tile for the DISP 2 assist pin grid.
struct DisplayToggleItem: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(LiveType.ui(size: 11.5, weight: .semibold, design: .default))
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
        .buttonStyle(.zcTapTarget)
    }
}

struct SettingsSwitchInlineRow: View {
    let title: String
    var help: String? = nil
    var showTopDivider = true
    var stacked: Bool = false
    let isOn: Bool
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
            .buttonStyle(.zcTapTarget)
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
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let active = option == selected
                Button {
                    guard option != selected else { return }
                    OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
                    onSelect(option)
                } label: {
                    Text(option)
                        .font(
                            LiveType.ui(
                                size: stacked ? 12 : 11, weight: active ? .semibold : .medium)
                        )
                        .foregroundStyle(active ? LiveDesign.text : LiveDesign.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(compact ? 0.85 : 1)
                        .padding(.horizontal, stacked || compact ? 8 : 11)
                        .padding(.vertical, stacked ? 7 : 6)
                        .frame(maxWidth: compact || stacked ? .infinity : nil)
                        .frame(minHeight: stacked ? 32 : nil)
                        .background(
                            active ? LiveDesign.surface : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                        )
                }
                .buttonStyle(.zcTapTarget)
            }
        }
        .padding(3)
        .background(
            LiveDesign.background.opacity(0.5),
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
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
            OpcIcon.refreshCw
                .foregroundStyle(LiveDesign.muted)
                .frame(width: 12, height: 12)
                .frame(width: 28, height: 28)
                .background(LiveDesign.background.opacity(0.42), in: Circle())
                .overlay(Circle().stroke(LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
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
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(LiveDesign.text)
                .frame(width: 24, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

enum OperatorSettingsHaptics {
    @MainActor
    static func selection(enabled: Bool) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}

struct SettingsRowCard<Content: View>: View {
    var title: String? = nil
    var onReset: (() -> Void)? = nil
    var chrome: SettingsRowChrome = .liquidGlass
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        onReset: (() -> Void)? = nil,
        chrome: SettingsRowChrome = .liquidGlass,
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
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(LiveType.ui(size: 13, weight: .semibold))
                        .foregroundStyle(LiveDesign.text)
                    Spacer(minLength: 0)
                    if let onReset {
                        SettingsResetButton(action: onReset)
                    }
                }
                .frame(minHeight: 24, alignment: .topLeading)
                .padding(.top, 11)
                .padding(.bottom, 2)
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
                .background(LiveDesign.surface, in: shape)
                .overlay(shape.stroke(LiveDesign.hairline, lineWidth: 1))
        }
    }
}

private struct SettingsScrollFooterMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SettingsTabScrollArea<Content: View>: View {
    let tabID: String
    @ViewBuilder var content: Content
    @State private var moreBelow = false

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    content
                    Color.clear
                        .frame(height: 1)
                        .background(
                            GeometryReader { footer in
                                Color.clear.preference(
                                    key: SettingsScrollFooterMinYKey.self,
                                    value: footer.frame(in: .named("opc.settingsScroll")).maxY
                                )
                            }
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 22)
            }
            .scrollDismissesKeyboard(.interactively)
            .coordinateSpace(name: "opc.settingsScroll")
            .onPreferenceChange(SettingsScrollFooterMinYKey.self) { footerMaxY in
                moreBelow = footerMaxY > viewport.size.height + 6
            }
            .overlay(alignment: .bottom) {
                ScrollMoreCue()
                    .opacity(moreBelow ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .id(tabID)
    }
}

struct ScrollMoreCue: View {
    var body: some View {
        VStack(spacing: 1) {
            Spacer(minLength: 0)
            Text("MORE")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .kerning(1.2)
                .foregroundStyle(LiveDesign.muted)
            OpcIcon.chevronDown
                .foregroundStyle(LiveDesign.muted)
                .frame(width: 8, height: 8)
        }
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(
            LinearGradient(
                colors: [LiveDesign.surface.opacity(0), LiveDesign.surface],
                startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
    }
}

struct SettingsDashScale: View {
    let title: String
    let caption: String
    let score: Int

    private enum Band { case poor, watch, stable }
    private var band: Band { score >= 80 ? .stable : (score >= 50 ? .watch : .poor) }
    /// Watch band — orange, not the DJI sky-blue accent.
    private static let watch = Color(red: 0.96, green: 0.52, blue: 0.12)

    private var bandColor: Color {
        switch band {
        case .poor: LiveDesign.rec
        case .watch: Self.watch
        case .stable: LiveDesign.good
        }
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
                .font(LiveType.ui(size: 13, weight: .semibold))
                .foregroundStyle(LiveDesign.text)
            Text(caption)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
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
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .kerning(0.5)
            .foregroundStyle(bandColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bandColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(bandColor, lineWidth: 1))
    }

    private func dashColor(_ index: Int) -> Color {
        guard index < litCount else { return LiveDesign.hairlineStrong }
        if index < 4 { return LiveDesign.rec.opacity(0.8) }
        if index < 8 { return Self.watch.opacity(0.85) }
        return LiveDesign.good.opacity(0.9)
    }

    private func legend(_ name: String, _ sub: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(LiveType.ui(size: 10, weight: .semibold))
                .foregroundStyle(LiveDesign.muted)
            Text(sub)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(LiveDesign.faint)
        }
    }
}

struct SettingsLinkHealthCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bars = model.session.liveSignalBars
        let score = min(100, max(0, bars * 25))
        SettingsDashScale(title: "Link Health", caption: caption, score: score)
    }

    private var caption: String {
        if !model.isLive { return "No live path." }
        switch model.session.liveSignalBars {
        case 3...: return "Link is clean. · Stable"
        case 2: return "Some loss on the link. · Watch"
        case 1: return "Link is weak. · Poor"
        default: return "Waiting for the link."
        }
    }
}

struct SettingsLiveTile: View {
    @Environment(AppModel.self) private var model
    @State private var displayedFPS = "—"
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
        let transport = isLinked ? "BLE + Wi-Fi" : "—"
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
                    .font(LiveType.ui(size: 12, weight: .semibold))
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                    .fixedSize()
                Text(isLinked ? detail : model.session.phase.label)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
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
            displayedFPS = compact.isEmpty ? "—" : compact
            lastFPSCommit = now
            return
        }
        guard now - lastFPSCommit >= 0.5 else { return }
        displayedFPS = compact.isEmpty ? "—" : compact
        lastFPSCommit = now
    }
}

enum OperatorPanelMetrics {
    static let closeSize: CGFloat = 37
    static let closeLeading: CGFloat = 16
    static let topStackWidth: CGFloat = 560

    static func topPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.top + 6, 16)
    }

    /// OpenZCine `OperatorSettingsPanel` top floor is 14, not the shared 16 used by Media/Legal.
    static func settingsTopPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.top + 6, 14)
    }

    static func closeTopPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.top + 6, 22)
    }

    static func leadingPadding(safeArea: EdgeInsets, floor: CGFloat = 16) -> CGFloat {
        max(safeArea.leading + 6, floor)
    }

    static func trailingPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.trailing + 6, 16)
    }

    static func bottomPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.bottom + 4, 12)
    }

    /// OpenZCine `MediaBrowserView` padding — trailing floor is 20, bottom floor 14.
    static func mediaTopPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.top + 6, 16)
    }

    static func mediaLeadingPadding(safeArea: EdgeInsets, portrait: Bool) -> CGFloat {
        max(safeArea.leading + 6, portrait ? 16 : 64)
    }

    static func mediaTrailingPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.trailing + 6, 20)
    }

    static func mediaBottomPadding(safeArea: EdgeInsets) -> CGFloat {
        max(safeArea.bottom + 4, 14)
    }

    /// Extra leading inset so a landscape title clears the floating close button.
    static func closeButtonClearance(safeArea: EdgeInsets) -> CGFloat {
        max(0, (closeLeading + closeSize + 8) - leadingPadding(safeArea: safeArea))
    }

    /// OpenZCine `MonitorFullScreenPanelOverlay.fullScreenPanelSafeArea`.
    /// Landscape zeros the clean short edge so the surface hugs that bezel while clearing
    /// the Dynamic Island on the side it sits. Portrait passes the insets through.
    static func fullScreenPanelSafeArea(
        from insets: EdgeInsets,
        isPortrait: Bool,
        mirrored: Bool
    ) -> EdgeInsets {
        guard !isPortrait else { return insets }
        return EdgeInsets(
            top: insets.top,
            leading: mirrored ? 0 : insets.leading,
            bottom: insets.bottom,
            trailing: mirrored ? insets.trailing : 0
        )
    }

    /// OpenZCine standalone Operator Setup host (`NativeAppRoot` ~13136).
    /// iOS reports the landscape island lane on both short edges; zero the smaller side.
    static func standalonePanelSafeArea(from insets: EdgeInsets) -> EdgeInsets {
        let islandOnLeading = insets.leading >= insets.trailing
        return EdgeInsets(
            top: insets.top,
            leading: islandOnLeading ? insets.leading : 0,
            bottom: insets.bottom,
            trailing: islandOnLeading ? 0 : insets.trailing
        )
    }

    /// SwiftUI reports 0 after a parent `ignoresSafeArea`; the window still has the island lane.
    /// Keep a one-sided SwiftUI cutout even when UIKit reports the lane on both short edges.
    @MainActor
    static func resolvedDeviceSafeArea(_ proposed: EdgeInsets) -> EdgeInsets {
        let window = LiveMonitorLayout.sceneSafeArea
        let proposedCut = max(proposed.leading, proposed.trailing)
        let windowCut = max(window.leading, window.trailing)
        if proposedCut >= LiveChromeMetrics.cutoutMinimum || proposedCut >= windowCut {
            return proposed
        }
        return window
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
                        .font(LiveType.ui(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(StartupColors.muted)
                    Text(title)
                        .font(LiveType.ui(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(StartupColors.ink)
                }
                Spacer()
                Button("Done", action: onClose)
                    .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(StartupColors.darkText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        StartupColors.accent,
                        in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                    )
                    .buttonStyle(.zcTapTarget)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StartupColors.backdrop.ignoresSafeArea())
        .foregroundStyle(StartupColors.ink)
        .preferredColorScheme(.dark)
    }
}
