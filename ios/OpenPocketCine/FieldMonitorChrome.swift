import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Osmo presentation adapter. Reads the session's existing throttled snapshot;
/// it never schedules status work or remaps signal health / camera controls.
struct FieldMonitorStatusChrome: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var locked
    @Binding var menu: LiveTopMenu?
    var layout: LiveMonitorLayout
    @State private var storagePercent = false
    @State private var readoutOwnership = MonitorReadoutOwnership()

    var body: some View {
        let portrait = layout.presentation?.portrait == true
        Group {
            if portrait {
                ZStack {
                    if model.chromeSectionMounts(.timecode), !model.session.status.isPhoto {
                        MonitorClock(
                            model.session.status.timecodeClock,
                            fontSize: layout.presentation?.tablet == true ? 25 : 23
                        )
                    }
                    HStack {
                        tally
                        Spacer(minLength: 4)
                        // The format sits on the timecode's line at its size; the colour
                        // profile hangs smaller underneath without moving that alignment.
                        topReadout(
                            model.session.status.isPhoto ? .mode : .resolution,
                            value: model.session.status.isPhoto ? "MODE" : recSetupFormat,
                            fontSize: model.session.status.isPhoto
                                ? 12 : (layout.presentation?.tablet == true ? 25 : 23),
                            weight: model.session.status.isPhoto ? .semibold : .medium,
                            alwaysAccent: false,
                            caption: model.session.status.isPhoto ? nil : recSetupColor
                        )
                        .accessibilityLabel(
                            model.session.status.isPhoto
                                ? "Shooting mode" : "Recording options")
                    }
                }
            } else {
                HStack(spacing: 24) {
                    if model.chromeSectionMounts(.storage) { storageButton }
                    if model.chromeSectionMounts(.format) {
                        if model.session.status.isPhoto {
                            topReadout(
                                .mode,
                                value: model.session.currentShootingMode?.label(
                                    for: model.session.connectedCamera?.model) ?? "Photo",
                                fontSize: layout.presentation?.tablet == true ? 18 : 16,
                                alwaysAccent: true)
                        } else {
                            topButton(
                                .recFormat,
                                value: model.session.status.videoFormat?.chipLabel ?? "—")
                        }
                    }
                    if model.chromeSectionMounts(.color), !model.session.status.isPhoto {
                        topButton(.color, value: model.session.status.colorMode?.label ?? "—")
                    }
                    if layout.viewport.width >= 800, !model.session.status.isPhoto {
                        topReadout(
                            .mode,
                            value: model.session.currentShootingMode?.label(
                                for: model.session.connectedCamera?.model) ?? "Video",
                            fontSize: layout.presentation?.tablet == true ? 18 : 16,
                            alwaysAccent: true)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 10) {
                        tally
                        if model.chromeSectionMounts(.timecode), !model.session.status.isPhoto {
                            MonitorClock(
                                model.session.status.timecodeClock,
                                fontSize: layout.presentation?.tablet == true ? 25 : 23)
                        }
                    }
                    .padding(.trailing, layout.presentation?.recordingReadoutTrailingInset ?? 8)
                }
            }
        }
        .frame(height: layout.topDeck.height)
        .monitorReadoutShadow()
        .overlay(alignment: .topLeading) {
            if portrait, let p = layout.presentation {
                HStack(spacing: 10) {
                    if model.chromeSectionMounts(.storage) {
                        storageButton.monitorReadoutShadow()
                    }
                    // Left of the Dynamic Island; the batteries stay on the right.
                    if !p.tablet, model.chromeSectionMounts(.batteries) {
                        FieldMonitorGauges(horizontal: true, showsPower: false)
                    }
                }
                .offset(y: (p.tablet ? 52 : p.gauges.y) - p.status.y)
            }
        }
        .onChange(of: locked) { _, isLocked in
            if isLocked {
                model.captureSheet = nil
                model.captureDrum = nil
            }
        }
        .onChange(of: model.session.status.isPhoto) { _, photo in
            model.captureSheet = CaptureReadoutAdmission.retained(
                model.captureSheet, isPhoto: photo)
            if CaptureReadoutAdmission.retainedDrum(model.captureDrum?.sheet, isPhoto: photo)
                == nil
            {
                model.captureDrum = nil
            }
            if photo, model.assist.configureTool == .audioMeters {
                model.assist.configureTool = nil
            }
        }
    }

    @ViewBuilder private var tally: some View {
        if model.chromeSectionMounts(.recReadout), !model.session.status.isPhoto {
            let status = model.session.status
            HStack(spacing: 5) {
                Text(status.isRecording ? "REC" : "STBY").foregroundStyle(
                    status.isRecording ? MonitorTheme.recording : .white)
                Text(
                    String(
                        format: "%02d:%02d", status.recordElapsedSec / 60,
                        status.recordElapsedSec % 60)
                )
                .foregroundStyle(MonitorTheme.secondary)
            }
            .font(MonitorTheme.font(10, weight: .semibold)).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
            .fixedSize()
            .accessibilityLabel(status.isRecording ? "Recording" : "Standby")
            .accessibilityIdentifier("monitor.recording.readout")
        }
    }

    private var storageButton: some View {
        Button {
            storagePercent.toggle()
        } label: {
            HStack(spacing: 5) {
                OpcIcon.cardSim.frame(width: 12, height: 12)
                Text(storage).font(
                    MonitorTheme.font(
                        layout.presentation?.portrait == true
                            ? 14
                            : (layout.presentation?.tablet == true ? 18 : 16), weight: .medium)
                ).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75)
            }.foregroundStyle(.white)
        }
        .buttonStyle(.zcTapTarget).accessibilityLabel("Storage remaining").accessibilityValue(
            storage)
    }

    private var storage: String {
        let s = model.session.status
        let free = s.storageFreeMb > 0 ? s.storageFreeMb : s.sdFreeMb
        let total = s.storageTotalMb > 0 ? s.storageTotalMb : s.sdTotalMb
        if storagePercent && total > 0 {
            return "\(Int((Double(max(0, free)) / Double(total) * 100).rounded()))%"
        }
        return free > 0 ? "\(free / 1024) GB" : "—"
    }

    private func topButton(_ item: LiveTopMenu, value: String) -> some View {
        topReadout(
            item == .color ? .color : .resolution, value: value,
            fontSize: layout.presentation?.tablet == true ? 18 : 16
        )
        .accessibilityLabel(item == .color ? "Color mode" : "Recording format")
    }

    /// Current format ("4K25p"), not a generic label.
    private var recSetupFormat: String {
        model.session.status.videoFormat.map {
            "\($0.resolution.tabTitle)\($0.frameRate.drumLabel)"
        } ?? "REC SETUP"
    }

    private var recSetupColor: String? {
        model.session.status.colorMode?.label(for: model.session.bodyFamily)
    }

    private func topReadout(
        _ sheet: CaptureSheet, value: String, fontSize: CGFloat, weight: Font.Weight = .medium,
        alwaysAccent: Bool = false, caption: String? = nil
    ) -> some View {
        let isActive = model.captureSheet == sheet || model.captureDrum?.sheet == sheet
        let acceptsTouch =
            !locked && (model.captureDrum == nil || model.captureDrum?.sheet == sheet)
        return Text(value)
            .font(MonitorTheme.font(fontSize, weight: weight)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.7)
            .overlay(alignment: .bottomTrailing) {
                if let caption {
                    Text(caption)
                        .font(MonitorTheme.font(11, weight: .semibold))
                        .lineLimit(1).fixedSize()
                        // Hang below the format line (its own line height), not over it.
                        .offset(y: 18)
                }
            }
            .foregroundStyle(
                alwaysAccent || isActive ? MonitorTheme.accent : .white
            )
            .modifier(
                MonitorReadoutHitTargetModifier(
                    sheet: sheet, locked: locked, acceptsTouch: acceptsTouch,
                    ownership: $readoutOwnership
                ) { open(sheet) }
            )
            .accessibilityIdentifier(topAccessibilityID(sheet))
            .accessibilityValue(value)
    }

    private func open(_ sheet: CaptureSheet) {
        guard !locked, model.captureDrum == nil, readoutOwnership.owner == nil else { return }
        menu = nil
        model.captureDrum = nil
        model.captureSheet = CaptureReadoutAdmission.replacing(
            model.captureSheet,
            with: CaptureReadoutAdmission.opening(
                sheet, isPhoto: model.session.status.isPhoto))
    }

    private func topAccessibilityID(_ sheet: CaptureSheet) -> String {
        switch sheet {
        case .color: "monitor.capture.color"
        case .mode: "monitor.capture.mode"
        default: "monitor.capture.format"
        }
    }
}

/// Same 44×44pt pad/unpad hit region as `zcTapTarget`. Gesture and backdrop
/// frames attach to the expanded region; negative padding restores layout.
enum MonitorReadoutHitTarget {
    static let minimumSize: CGFloat = 44

    static func padding(for size: CGSize, minSize: CGFloat = minimumSize) -> CGSize {
        CGSize(
            width: size == .zero ? 0 : max(0, (minSize - size.width) / 2),
            height: size == .zero ? 0 : max(0, (minSize - size.height) / 2)
        )
    }
}

private struct MonitorReadoutHitTargetSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct MonitorReadoutHitTargetModifier: ViewModifier {
    var sheet: CaptureSheet
    var locked: Bool
    var acceptsTouch: Bool
    @Binding var ownership: MonitorReadoutOwnership
    var onOpen: () -> Void
    @State private var measuredSize: CGSize = .zero

    func body(content: Content) -> some View {
        let pad = MonitorReadoutHitTarget.padding(for: measuredSize)
        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MonitorReadoutHitTargetSizeKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(MonitorReadoutHitTargetSizeKey.self) { measuredSize = $0 }
            .padding(.horizontal, pad.width)
            .padding(.vertical, pad.height)
            .contentShape(Rectangle())
            .modifier(
                CaptureReadoutGesture(
                    sheet: sheet, locked: locked, ownership: $ownership, onTap: onOpen)
            )
            .disabled(locked)
            .allowsHitTesting(acceptsTouch)
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(LiveCanvasSpace.name))
                    Color.clear
                        .preference(key: LiveCaptureTileFramesKey.self, value: [sheet: frame])
                        .preference(
                            key: LiveTopPickerFramesKey.self,
                            value: topMenuFrame(frame))
                }
            }
            .padding(.horizontal, -pad.width)
            .padding(.vertical, -pad.height)
    }

    private func topMenuFrame(_ frame: CGRect) -> [LiveTopMenu: CGRect] {
        switch sheet {
        case .color: [.color: frame]
        case .resolution: [.recFormat: frame]
        default: [:]
        }
    }
}

struct FieldMonitorAssistPalette: View {
    @Environment(AppModel.self) private var model
    var layout: LiveMonitorLayout
    var isLocked: Bool
    var otherOverlayPresented = false
    @Binding var expanded: Bool
    var onExpansionActivityChange: (Bool) -> Void = { _ in }
    private var tools: [LiveAssistTool] {
        if model.session.status.isPhoto {
            return LiveAssistTool.toolbarCases
        }
        return LiveAssistTool.toolbarCases + [.audioMeters]
    }

    private var shouldCollapse: Bool {
        isLocked || otherOverlayPresented || model.captureSheet != nil
            || model.captureDrum != nil || model.liveGimbalPanel != .none
            || model.liveOperatorPanel != nil || model.assist.configureTool != nil
            || model.isEditingChrome
    }

    static func visibleFrame(in layout: LiveMonitorLayout, toolCount: Int, expanded: Bool) -> CGRect
    {
        let (metrics, frame) = geometry(in: layout, toolCount: toolCount)
        return metrics.resolving(expanded: expanded)
            .anchored(leading: frame.x, bottom: frame.maxY).cgRect
    }

    private static func geometry(
        in layout: LiveMonitorLayout, toolCount: Int
    ) -> (layout: MonitorAssistPaletteLayout, frame: MonitorRect) {
        if let presentation = layout.presentation {
            return MonitorAssistPaletteLayout.fieldMonitor(
                presentation, toolCount: toolCount, safeTop: layout.safeArea.top)
        }
        let tablet = UIDevice.current.userInterfaceIdiom == .pad
        let portrait = layout.viewport.height > layout.viewport.width
        let maximumWidth =
            portrait
            ? layout.viewport.width - (tablet ? 140 : 126)
            : layout.capture.maxX - layout.assist.minX
        let maximumHeight =
            portrait
            ? min(
                layout.viewport.height * 0.62,
                layout.assist.maxY - max(layout.safeArea.top, 8))
            : layout.assist.maxY - max(layout.safeArea.top, 8)
        let metrics = MonitorAssistPaletteLayout(
            portrait: portrait, tablet: tablet, expanded: true, toolCount: toolCount,
            maximumWidth: maximumWidth, maximumHeight: maximumHeight)
        return (
            metrics,
            metrics.anchored(leading: layout.assist.minX, bottom: layout.assist.maxY)
        )
    }

    var body: some View {
        @Bindable var model = model
        let (metrics, frame) = Self.geometry(in: layout, toolCount: tools.count)
        MonitorAssistPalette(
            tools: tools.map {
                MonitorToolItem(
                    id: $0.rawValue, title: $0.rawValue,
                    enabled: model.assist.isOn($0), hasOptions: $0.hasConfiguration)
            },
            layout: metrics, usageSeed: MonitorToolUsage.fieldMonitorSeed,
            usage: $model.assistToolUsage, expanded: $expanded,
            onToggle: { id in
                guard !shouldCollapse, let tool = LiveAssistTool(rawValue: id) else { return }
                model.assist.toggle(tool)
            },
            onOptions: { id in
                guard !shouldCollapse, let tool = LiveAssistTool(rawValue: id) else { return }
                model.assist.longPressAnchor = CGRect(
                    x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                model.assist.configureTool = tool
            },
            onExpansionActivityChange: onExpansionActivityChange,
            icon: { id in
                if let tool = LiveAssistTool(rawValue: id) {
                    AssistToolIcon(tool: tool, size: nil)
                }
            }
        )
        .chromeEditable(.toolBar, editing: model.chromeEditorMode)
        .position(x: frame.midX, y: frame.midY)
        .frame(
            width: layout.viewport.width, height: layout.viewport.height,
            alignment: .topLeading
        )
        .onChange(of: model.assist.clean) { _, value in if value { expanded = false } }
        .onChange(of: shouldCollapse) { _, value in if value { expanded = false } }
        .onChange(of: expanded) { _, value in if value && shouldCollapse { expanded = false } }
    }
}

struct FieldMonitorGauges: View {
    @Environment(AppModel.self) private var model
    var horizontal = false
    /// Portrait phones split the row around the Dynamic Island: the link pill sits
    /// left of it with storage, the batteries stay on the right.
    var showsLink = true
    var showsPower = true
    @State private var phonePercent = -1
    /// One link pill: tap swaps signal bars and feed fps.
    @State private var showsFPS = false
    private var tablet: Bool { Self.tablet }
    private static var tablet: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        let axis =
            horizontal
            ? AnyLayout(HStackLayout(spacing: 6))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: tablet ? 5 : 4))
        let bars = model.session.liveSignalBars
        // Signal / fps stay in the accent; the bar count carries the health.
        let linkColor = MonitorTheme.accent
        axis {
            if showsLink {
                Button {
                    showsFPS.toggle()
                } label: {
                    Self.gauge(
                        icon: showsFPS ? .gauge : .signal, value: showsFPS ? fpsValue : nil,
                        bars: bars, color: linkColor)
                }
                .buttonStyle(.zcTapTarget)
                .accessibilityLabel(
                    "Live link \(bars) of 4 bars, feed \(model.session.liveFPS) frames per second"
                )
                .accessibilityHint(showsFPS ? "Shows signal strength" : "Shows feed frame rate")
                .accessibilityIdentifier("monitor.telemetry.signal")
            }
            if showsPower {
                Self.gauge(
                    icon: .smartphone, value: phonePercent < 0 ? "—" : "\(phonePercent)%",
                    bars: 0, color: Self.batteryColor(phonePercent)
                )
                .accessibilityLabel(
                    "Phone battery \(phonePercent >= 0 ? String(phonePercent) : "unknown") percent")
                let percent = model.session.status.batteryPercent
                Self.gauge(
                    icon: .camera, value: (0...100).contains(percent) ? "\(percent)%" : "—",
                    bars: 0, color: Self.batteryColor(percent)
                )
                .accessibilityLabel(
                    (0...100).contains(percent)
                        ? "Camera battery \(percent) percent" : "Camera battery unavailable"
                )
                .accessibilityIdentifier("monitor.telemetry.camera")
            }
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updatePhone()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
        ) { _ in updatePhone() }
    }

    /// Phone and camera batteries share one scale.
    static func batteryColor(_ percent: Int) -> Color {
        guard (0...100).contains(percent) else { return LiveDesign.text }
        return percent <= 20
            ? MonitorTheme.recording : percent <= 40 ? LiveDesign.amber : LiveDesign.good
    }

    /// Whole frames with a unit; RECOV / LINK / — pass through.
    private var fpsValue: String {
        let label = model.session.liveFPS
        return Double(label).map { "\(Int($0.rounded())) fps" } ?? label
    }

    private func updatePhone() {
        let value = UIDevice.current.batteryLevel
        phonePercent = value < 0 ? -1 : Int((value * 100).rounded())
    }

    /// Multiview tiles: the camera battery pill without its glyph.
    static func cameraBattery(_ percent: Int) -> some View {
        gauge(
            icon: nil, value: (0...100).contains(percent) ? "\(percent)%" : "—", bars: 0,
            color: batteryColor(percent)
        )
        .accessibilityLabel(
            (0...100).contains(percent)
                ? "Camera battery \(percent) percent" : "Camera battery unavailable")
    }

    /// One glass pill per gauge: white icon, status color on the value only.
    private static func gauge(icon: OpcIcon?, value: String?, bars: Int, color: Color)
        -> some View
    {
        let height: CGFloat = tablet ? 22 : 20
        return HStack(spacing: 4) {
            if let icon {
                icon.frame(width: tablet ? 12 : 11, height: tablet ? 12 : 11)
                    .foregroundStyle(LiveDesign.text)
            }
            if let value {
                Text(value)
                    .font(MonitorTheme.font(tablet ? 11 : 10, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(color)
            } else {
                HStack(spacing: 1.5) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 0.75)
                            .fill(index < bars ? color : color.opacity(0.2))
                            .frame(width: 3.5, height: tablet ? 10 : 9)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        // One width for every pill, sized for the widest value ("25 fps", or
        // "100%" without the glyph) so values never jitter.
        .frame(
            width: icon == nil ? (tablet ? 44 : 40) : (tablet ? 64 : 58), height: height,
            alignment: .leading)
        // Same glass as the Live View buttons, as a small rounded-rectangle pill.
        .monitorGlass(in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .ignore)
    }
}
