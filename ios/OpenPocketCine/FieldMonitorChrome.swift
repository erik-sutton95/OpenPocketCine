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

    var body: some View {
        let portrait = layout.presentation?.portrait == true
        Group {
            if portrait {
                ZStack {
                    if model.chromeSectionMounts(.timecode) {
                        MonitorClock(
                            model.session.status.timecodeClock,
                            fontSize: layout.presentation?.tablet == true ? 25 : 23
                        )
                    }
                    HStack {
                        tally
                        Spacer(minLength: 4)
                        Button("REC SETUP") { if !locked { model.captureSheet = .resolution } }
                            .font(MonitorTheme.font(12, weight: .semibold))
                            .foregroundStyle(.white).buttonStyle(.zcTapTarget)
                            .accessibilityLabel("Recording options")
                            .accessibilityIdentifier("monitor.capture.format")
                    }
                }
                .overlay(alignment: .topLeading) {
                    if model.chromeSectionMounts(.storage), let p = layout.presentation {
                        storageButton.offset(y: (p.tablet ? 52 : p.gauges.y) - p.status.y)
                    }
                }
            } else {
                HStack(spacing: 24) {
                    if model.chromeSectionMounts(.storage) { storageButton }
                    if model.chromeSectionMounts(.format) {
                        topButton(
                            .recFormat, value: model.session.status.videoFormat?.chipLabel ?? "—")
                    }
                    if model.chromeSectionMounts(.color) {
                        topButton(.color, value: model.session.status.colorMode?.label ?? "—")
                    }
                    if layout.viewport.width >= 800 {
                        Button(model.session.currentShootingMode?.label ?? "Video") {
                            if !locked { model.captureSheet = .mode }
                        }
                        .font(
                            MonitorTheme.font(
                                layout.presentation?.tablet == true ? 18 : 16, weight: .medium)
                        )
                        .foregroundStyle(MonitorTheme.accent).buttonStyle(.zcTapTarget)
                        .accessibilityIdentifier("monitor.capture.mode")
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 10) {
                        tally
                        if model.chromeSectionMounts(.timecode) {
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
    }

    @ViewBuilder private var tally: some View {
        if model.chromeSectionMounts(.recReadout) {
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
        let sheet: CaptureSheet = item == .color ? .color : .resolution
        return Button {
            guard !locked else { return }
            menu = nil
            model.captureSheet = model.captureSheet == sheet ? nil : sheet
        } label: {
            Text(value).font(
                MonitorTheme.font(layout.presentation?.tablet == true ? 18 : 16, weight: .medium)
            ).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(model.captureSheet == sheet ? MonitorTheme.accent : .white)
        }
        .buttonStyle(.zcTapTarget)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LiveTopPickerFramesKey.self,
                    value: [item: proxy.frame(in: .named(LiveCanvasSpace.name))])
            }
        }
        .accessibilityLabel(item == .color ? "Color mode" : "Recording format")
        .accessibilityIdentifier(
            item == .color ? "monitor.capture.color" : "monitor.capture.format"
        )
        .accessibilityValue(value)
    }
}

struct FieldMonitorAssistPalette: View {
    @Environment(AppModel.self) private var model
    var layout: LiveMonitorLayout
    var isLocked: Bool
    var otherOverlayPresented = false
    @Binding var expanded: Bool
    private var tools: [LiveAssistTool] { LiveAssistTool.toolbarCases + [.audioMeters] }

    private var shouldCollapse: Bool {
        isLocked || otherOverlayPresented || model.captureSheet != nil
            || model.captureDrum != nil || model.liveGimbalPanel != .none
            || model.liveOperatorPanel != nil || model.assist.configureTool != nil
            || model.isEditingChrome
    }

    var body: some View {
        let portrait = layout.presentation?.portrait == true
        let tablet = UIDevice.current.userInterfaceIdiom == .pad
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
            portrait: portrait, tablet: tablet, expanded: expanded, toolCount: tools.count,
            maximumWidth: maximumWidth, maximumHeight: maximumHeight)
        let frame = metrics.anchored(leading: layout.assist.minX, bottom: layout.assist.maxY)
        MonitorAssistPalette(
            tools: tools.map {
                MonitorToolItem(
                    id: $0.rawValue, title: $0.rawValue,
                    enabled: model.assist.isOn($0), hasOptions: $0.hasConfiguration)
            },
            layout: metrics, usageSeed: MonitorToolUsage.fieldMonitorSeed, expanded: $expanded,
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
            icon: { id in
                if let tool = LiveAssistTool(rawValue: id) {
                    AssistToolIcon(tool: tool, size: tablet ? 24 : 20)
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
    @State private var phonePercent = -1
    private var tablet: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        let axis =
            horizontal
            ? AnyLayout(HStackLayout(spacing: 10))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: tablet ? 5 : 3))
        axis {
            gauge(
                icon: .signal, value: nil, bars: model.session.liveSignalBars,
                color: MonitorTheme.accent
            )
            .accessibilityLabel(
                "Live link \(model.session.liveSignalBars) of 4 bars, \(model.session.liveFPS) frames per second"
            )
            gauge(
                icon: .smartphone, value: phonePercent < 0 ? "—" : String(phonePercent),
                bars: 0, color: .mint
            )
            .accessibilityLabel(
                "Phone battery \(phonePercent >= 0 ? String(phonePercent) : "unknown") percent")
            let percent = model.session.status.batteryPercent
            gauge(
                icon: .camera, value: (0...100).contains(percent) ? "\(percent)%" : "—", bars: 0,
                color: percent <= 20
                    ? MonitorTheme.recording : percent <= 40 ? LiveDesign.amber : LiveDesign.good
            )
            .accessibilityLabel(
                (0...100).contains(percent)
                    ? "Camera battery \(percent) percent" : "Camera battery unavailable"
            )
            .accessibilityIdentifier("monitor.telemetry.camera")
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updatePhone()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
        ) { _ in updatePhone() }
    }

    private func updatePhone() {
        let value = UIDevice.current.batteryLevel
        phonePercent = value < 0 ? -1 : Int((value * 100).rounded())
    }

    private func gauge(icon: OpcIcon, value: String?, bars: Int, color: Color) -> some View {
        let axis =
            horizontal ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 5))
        return axis {
            icon.frame(width: tablet ? 11 : 9, height: tablet ? 11 : 9)
            ZStack {
                RoundedRectangle(cornerRadius: 2).strokeBorder(color, lineWidth: 1)
                if let value {
                    Text(value).font(
                        MonitorTheme.font(tablet ? 9 : 8, weight: .semibold))
                } else {
                    HStack(spacing: 2) {
                        ForEach(0..<4) { index in
                            Rectangle().fill(index < bars ? color : color.opacity(0.15))
                        }
                    }.padding(3)
                }
            }.frame(width: tablet ? 33 : 28, height: tablet ? 16 : 14)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
    }
}
