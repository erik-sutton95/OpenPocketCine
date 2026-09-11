import OpenPocketViewCore
import SwiftUI

private struct MotionControlInteractionKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Bool = { true }
}

private extension EnvironmentValues {
    var motionControlCanInteract: @MainActor @Sendable () -> Bool {
        get { self[MotionControlInteractionKey.self] }
        set { self[MotionControlInteractionKey.self] = newValue }
    }
}

enum LiveGimbalPanel: Equatable {
    case none
    case sheet
    case editor
    case runPill
}

enum LiveGimbalCopy {
    static let title = "Gimbal"
    static let mode = "Mode"
    static let speed = "Speed"
    static let ramp = "Ramp"
    static let programmedMove = "Motion Control"
    static let runMove = "Start"
    static let stopMove = "Stop"
    static let set = "Set"
    static let update = "Update"
    static let clear = "Clear"
    static let accessibilityButton = "Gimbal controls"
    static let accessibilityHint = "Opens follow, speed, ramp, and motion control"
    static let holdDuration: TimeInterval = 0.3
}

struct LiveGimbalButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked

    var body: some View {
        Button {
            guard !interfaceLocked else { return }
            switch model.liveGimbalPanel {
            case .none:
                model.liveGimbalPanel = .sheet
            case .sheet:
                model.liveGimbalPanel = .none
            case .editor, .runPill:
                model.liveGimbalPanel = .sheet
            }
        } label: {
            OpcIcon.crosshair
                .frame(width: 18, height: 18)
                .foregroundStyle(LiveDesign.text)
                .frame(
                    width: LiveChromeMetrics.zoomButtonSize,
                    height: LiveChromeMetrics.zoomButtonSize
                )
                .liveChromeCircle()
        }
        .buttonStyle(.zcTapTarget)
        .opacity(interfaceLocked ? 0.4 : 1)
        .allowsHitTesting(!interfaceLocked)
        .disabled(interfaceLocked)
        .accessibilityLabel(LiveGimbalCopy.accessibilityButton)
        .accessibilityHint(LiveGimbalCopy.accessibilityHint)
        .accessibilityIdentifier("monitor.system.gimbalControls")
    }
}

/// Same host as `LiveCapturePickerHost`: slide-up glass, 10pt above the capture
/// bar, centred on the gimbal chip. Header stays on screen — overflow scrolls.
struct LiveGimbalSheetHost: View {
    @Environment(AppModel.self) private var model
    var layout: LiveMonitorLayout
    var cluster: GimbalCluster

    @State private var revealed = false
    @State private var panelHeight: CGFloat = 280

    private static let revealCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.20)
    private static let sheetWidth: CGFloat = 340

    var body: some View {
        let tile = Self.cgRect(cluster.controls)
        let bar = Self.floorBar(layout: layout, cluster: cluster)
        let ceilingY = max(
            layout.safeArea.top + LivePopupPlacement.assistTopInset,
            LivePopupPlacement.edgeMargin
        )
        let place = LivePopupPlacement.capturePicker(
            tile: tile,
            bar: bar,
            panelHeight: panelHeight,
            viewport: layout.viewport,
            safeArea: layout.safeArea,
            ceilingY: ceilingY,
            preferredWidth: Self.sheetWidth
        )
        let slide = place.maxHeight + 20

        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.liveGimbalPanel = .none }

            LiveGimbalSheet(maxHeight: place.maxHeight)
                .frame(width: place.width)
                .background(panelHeightReader)
                .opacity(revealed ? 1 : 0)
                .offset(x: place.x, y: place.y + (revealed ? 0 : slide))
        }
        .frame(width: layout.viewport.width, height: layout.viewport.height, alignment: .topLeading)
        .onAppear { scheduleReveal() }
    }

    private var panelHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { panelHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in
                    panelHeight = height
                }
        }
    }

    private func scheduleReveal() {
        DispatchQueue.main.async {
            withAnimation(Self.revealCurve) { revealed = true }
        }
    }

    /// Capture/assist bar is the floor (same as ISO). Chip-pair width must not
    /// become the card width — fall back to a full-width band at the cluster.
    private static func floorBar(layout: LiveMonitorLayout, cluster: GimbalCluster) -> CGRect {
        if layout.capture.width > 1 { return layout.capture }
        if layout.assist.width > 1 { return layout.assist }
        let zoom = cgRect(cluster.zoom)
        let button = cgRect(cluster.controls)
        let stick = cgRect(cluster.stick)
        let tops = [zoom, button, stick].filter { $0.height > 1 }.map(\.minY)
        let top = tops.min() ?? max(8, layout.viewport.height - 80)
        return CGRect(x: 0, y: top, width: layout.viewport.width, height: 1)
    }

    private static func cgRect(_ region: MonitorLayoutRegion) -> CGRect {
        CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
    }
}

struct LiveGimbalOverlay: View {
    @Environment(AppModel.self) private var model
    var layout: LiveMonitorLayout
    var feed: CGRect

    private var bounds: CGRect {
        CGRect(
            x: max(8, layout.safeArea.leading),
            y: max(8, layout.safeArea.top),
            width: max(
                1,
                layout.viewport.width - max(8, layout.safeArea.leading)
                    - max(
                        8, layout.safeArea.trailing)),
            height: max(
                1,
                layout.viewport.height - max(8, layout.safeArea.top)
                    - max(
                        8, layout.safeArea.bottom))
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.liveGimbalPanel == .editor || model.liveGimbalPanel == .runPill
                || model.session.gimbalMoveRunning
            {
                LiveGimbalWaypointMarks(feed: feed)
                    .zIndex(0)
            }
            if model.liveGimbalPanel == .editor {
                LiveGimbalMoveEditor()
                    .frame(width: Self.editorWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(
                        LiveGimbalFloatMove(
                            stored: Bindable(model).gimbalFloatCenter,
                            sizeHint: CGSize(width: Self.editorWidth, height: 280),
                            bounds: bounds,
                            defaultCenter: defaultEditorCenter
                        )
                    )
                    .zIndex(1)
            }

            if model.liveGimbalPanel == .runPill {
                LiveGimbalRunPill()
                    .fixedSize()
                    .modifier(
                        LiveGimbalFloatMove(
                            stored: Bindable(model).gimbalFloatCenter,
                            sizeHint: CGSize(width: 200, height: 44),
                            bounds: bounds,
                            defaultCenter: defaultPillCenter,
                            immediateDrag: true
                        )
                    )
                    .zIndex(1)
            }
        }
        .frame(width: layout.viewport.width, height: layout.viewport.height, alignment: .topLeading)
    }

    private static let editorWidth: CGFloat = 340

    private var defaultEditorCenter: CGPoint {
        CGPoint(
            x: min(
                max(feed.minX + 16 + Self.editorWidth / 2, 16 + Self.editorWidth / 2),
                layout.viewport.width - 16 - Self.editorWidth / 2),
            y: min(max(feed.midY, 140), layout.viewport.height - 180))
    }

    private var defaultPillCenter: CGPoint {
        CGPoint(
            x: defaultEditorCenter.x,
            y: min(feed.maxY - 36, layout.viewport.height - 80))
    }


}

/// Long-press then drag, same hold as movable scopes (0.3 s).
private struct LiveGimbalFloatMove: ViewModifier {
    @Binding var stored: CGPoint?
    var sizeHint: CGSize
    var bounds: CGRect
    var defaultCenter: CGPoint
    var immediateDrag = false
    @State private var measured = CGSize.zero
    @State private var dragging = false
    @State private var blockedUntil: TimeInterval = 0
    @State private var origin: CGPoint?

    private var size: CGSize {
        CGSize(
            width: measured.width > 1 ? measured.width : sizeHint.width,
            height: measured.height > 1 ? measured.height : sizeHint.height)
    }

    private var center: CGPoint {
        Self.clamp(stored ?? defaultCenter, size: size, bounds: bounds)
    }

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measured = proxy.size }
                        .onChange(of: proxy.size) { _, next in measured = next }
                }
            )
            .environment(\.motionControlCanInteract, {
                !dragging && ProcessInfo.processInfo.systemUptime >= blockedUntil
            })
            .position(center)
            .simultaneousGesture(drag, including: immediateDrag ? .none : .all)
            .highPriorityGesture(pillDrag, including: immediateDrag ? .all : .none)
            .sensoryFeedback(trigger: dragging) { _, isDragging in
                isDragging ? .impact(flexibility: .rigid, intensity: 1) : nil
            }
            .onAppear {
                if stored == nil { stored = defaultCenter }
            }
    }

    private var pillDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if !dragging { dragging = true; origin = center }
                guard let origin else { return }
                stored = Self.clamp(CGPoint(x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height), size: size, bounds: bounds)
            }
            .onEnded { _ in
                blockedUntil = ProcessInfo.processInfo.systemUptime + 0.15
                dragging = false; origin = nil
            }
            .map { _ in () }
    }

    private var drag: some Gesture {
        LongPressGesture(minimumDuration: LiveGimbalCopy.holdDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !dragging {
                    dragging = true
                    origin = center
                }
                guard let drag, let origin else { return }
                let proposed = CGPoint(
                    x: origin.x + drag.translation.width,
                    y: origin.y + drag.translation.height)
                stored = Self.clamp(proposed, size: size, bounds: bounds)
            }
            .onEnded { _ in
                blockedUntil = ProcessInfo.processInfo.systemUptime + 0.15
                dragging = false
                origin = nil
            }
            .map { _ in () }
    }

    private static func clamp(_ point: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        let halfW = max(size.width / 2, 20)
        let halfH = max(size.height / 2, 16)
        return CGPoint(
            x: min(
                max(point.x, bounds.minX + halfW), max(bounds.minX + halfW, bounds.maxX - halfW)),
            y: min(max(point.y, bounds.minY + halfH), max(bounds.minY + halfH, bounds.maxY - halfH))
        )
    }
}

private enum GimbalSettingsTab: String, CaseIterable {
    case mode = "Mode"
    case speed = "Speed"
    case ramp = "Ramp"
}

private struct LiveGimbalSheet: View {
    @Environment(AppModel.self) private var model
    var maxHeight: CGFloat
    @State private var selectedTab: GimbalSettingsTab = .mode

    var body: some View {
        ViewThatFits(in: .vertical) {
            sheetStack(scrolling: false)
            sheetStack(scrolling: true)
        }
        .frame(maxHeight: max(1, maxHeight), alignment: .top)
        .liveChromeGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})
    }

    @ViewBuilder
    private func sheetStack(scrolling: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(LiveGimbalCopy.title)
                    .font(LiveType.ui(size: 18, weight: .heavy, design: .default))
                    .kerning(2)
                    .textCase(.uppercase)
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                CloseButton(action: { model.liveGimbalPanel = .none })
            }

            tabBar

            if scrolling {
                ScrollView(showsIndicators: false) { tabSettings }
            } else {
                tabSettings
            }

            Rectangle().fill(LiveDesign.hairline).frame(height: 1)
            section("Gimbal tools") { programmedMoveRow }
        }
        .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
    }

    private var programmedMoveRow: some View {
        Button {
            model.liveGimbalPanel = .editor
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(LiveGimbalCopy.programmedMove).foregroundStyle(LiveDesign.text)
                    Text("Experimental")
                        .font(LiveType.ui(size: 11, weight: .medium))
                        .foregroundStyle(LiveDesign.muted)
                }
                Spacer()
                Text(model.session.gimbalProgram.summary)
                    .foregroundStyle(LiveDesign.muted)
            }
            .font(LiveType.ui(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LiveDesign.glassBright,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(LiveGimbalCopy.programmedMove)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(GimbalSettingsTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(LiveType.ui(size: 13, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? LiveDesign.text : LiveDesign.muted)
                        Rectangle()
                            .fill(selectedTab == tab ? LiveDesign.accent : LiveDesign.hairline)
                            .frame(height: 2)
                    }
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
    }

    private var tabSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch selectedTab {
            case .mode:
                chipGrid(GimbalMode.pickerOrder, selected: model.session.gimbalMode, title: { $0.label }) {
                    model.setGimbalMode($0)
                }
            case .speed:
                LiveGimbalChips(GimbalSpeed.pickerOrder, selected: model.session.gimbalSpeed, title: { $0.label }) {
                    model.session.setGimbalSpeed($0)
                }
            case .ramp:
                LiveGimbalChips(GimbalRamp.pickerOrder, selected: model.gimbalRamp, title: { $0.label }) {
                    model.gimbalRamp = $0
                }
            }
        }
        .frame(minHeight: 76, alignment: .top)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(LiveType.ui(size: 11, weight: .semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(LiveDesign.muted)
            content()
        }
    }

    private func chipGrid<T: Hashable>(
        _ items: [T], selected: T, title: @escaping (T) -> String, onSelect: @escaping (T) -> Void
    ) -> some View {
        let rows = stride(from: 0, to: items.count, by: 2).map { start in
            Array(items[start..<min(start + 2, items.count)])
        }
        return VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(rows[row], id: \.self) { item in
                        LiveGimbalChip(
                            title: title(item),
                            selected: item == selected,
                            action: { onSelect(item) }
                        )
                    }
                    if rows[row].count == 1 { Spacer(minLength: 0) }
                }
            }
        }
    }
}

private struct LiveGimbalChips<T: Hashable>: View {
    let items: [T]
    let selected: T
    let onSelect: (T) -> Void
    let title: (T) -> String

    init(
        _ items: [T], selected: T, title: @escaping (T) -> String, onSelect: @escaping (T) -> Void
    ) {
        self.items = items
        self.selected = selected
        self.onSelect = onSelect
        self.title = title
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                LiveGimbalChip(
                    title: title(item),
                    selected: item == selected,
                    action: { onSelect(item) }
                )
            }
        }
    }
}

private struct LiveGimbalChip: View {
    let title: String
    let selected: Bool
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LiveType.ui(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? LiveDesign.background : LiveDesign.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 7 : 8)
                .padding(.horizontal, compact ? 4 : 0)
                .background(
                    selected ? LiveDesign.accent : LiveDesign.glassBright,
                    in: Capsule()
                )
        }
        .buttonStyle(.zcTapTarget)
    }
}

private struct LiveGimbalMoveEditor: View {
    @Environment(AppModel.self) private var model

    @Environment(\.motionControlCanInteract) private var canInteract

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(LiveGimbalCopy.programmedMove)
                    .font(LiveType.ui(size: 15, weight: .bold))
                    .foregroundStyle(LiveDesign.text)
                Spacer()
                Button {
                    guard canInteract() else { return }
                    model.liveGimbalPanel = .runPill
                } label: {
                    OpcIcon.minimize
                        .frame(width: 16, height: 16)
                        .foregroundStyle(LiveDesign.text)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.zcTapTarget)
                .accessibilityLabel("Minimize")
                CloseButton(
                    action: {
                        guard canInteract() else { return }
                        model.liveGimbalPanel = .none
                    }, size: 30)
            }

            waypointRow(.a, duration: nil, floor: nil)
            waypointRow(
                .b, duration: model.session.gimbalProgram.durationAB,
                floor: GimbalProgram.minTravelDuration(
                    from: model.session.gimbalProgram.a, to: model.session.gimbalProgram.b)
            ) { model.session.setGimbalLegDuration(ab: $0) }
            if model.session.gimbalProgram.b != nil {
            waypointRow(
                .c, duration: model.session.gimbalProgram.durationBC,
                floor: GimbalProgram.minTravelDuration(
                    from: model.session.gimbalProgram.b, to: model.session.gimbalProgram.c)
            ) { model.session.setGimbalLegDuration(bc: $0) }
            }

            if model.session.gimbalProgram.b != nil, model.session.gimbalProgram.c != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Smoothness")
                        Spacer()
                        Text("\(Int((model.session.gimbalProgram.smoothness * 100).rounded()))%")
                    }
                    Slider(value: Binding(
                        get: { model.session.gimbalProgram.smoothness },
                        set: { if canInteract() { model.session.setGimbalSmoothness($0) } }), in: 0...1, step: 0.05)
                        .tint(LiveDesign.accent)
                        .accessibilityLabel("Path smoothness")
                }
                .font(LiveType.ui(size: 12, weight: .regular))
                .foregroundStyle(LiveDesign.text)
            }

            HStack(spacing: 8) {
                Button {
                    guard canInteract() else { return }
                    model.session.clearGimbalProgram()
                } label: {
                    Text(LiveGimbalCopy.clear)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.zcTapTarget)
                .foregroundStyle(LiveDesign.muted)
                .background(LiveDesign.glassBright, in: Capsule())

                if model.session.gimbalMoveCanPause {
                    Button(model.session.gimbalMovePaused ? "Resume" : "Pause") {
                        guard canInteract() else { return }
                        model.session.pauseOrResumeProgrammedMove()
                    }
                    .buttonStyle(.zcTapTarget)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(LiveDesign.background)
                    .background(LiveDesign.accent, in: Capsule())
                    .accessibilityIdentifier("motion.pauseResume")
                }

                Button {
                    guard canInteract() else { return }
                    model.session.runProgrammedMove()
                } label: {
                    Text(
                        model.session.gimbalMoveRunning
                            ? (model.session.gimbalStartCountdown.map { "Stop · \($0)" } ?? LiveGimbalCopy.stopMove) : LiveGimbalCopy.runMove
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.zcTapTarget)
                .foregroundStyle(runEnabled ? LiveDesign.background : LiveDesign.muted)
                .background(
                    (runEnabled ? LiveDesign.accent : LiveDesign.glassBright),
                    in: Capsule()
                )
                .accessibilityIdentifier("motion.startStop")
                .disabled(!runEnabled && !model.session.gimbalMoveRunning)
                .opacity(runEnabled || model.session.gimbalMoveRunning ? 1 : 0.45)
            }
            .font(LiveType.ui(size: 14, weight: .semibold))
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 14, trailing: 14))
        .liveChromeGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private var runEnabled: Bool {
        model.session.canRunProgrammedMove || model.session.gimbalMoveRunning
    }

    private func waypointRow(
        _ slot: GimbalWaypointSlot,
        duration: TimeInterval?,
        floor: TimeInterval?,
        onDuration: ((TimeInterval) -> Void)? = nil
    ) -> some View {
        let set = model.session.gimbalProgram[slot] != nil
        return HStack(spacing: 6) {
            Text(slot.letter)
                .font(LiveType.ui(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(set ? LiveDesign.accent : LiveDesign.text)
                .frame(width: 20)
            Spacer(minLength: 4)
            if set, let duration, let onDuration, let floor {
                LiveMotionDurationDial(value: duration, floor: floor, leg: slot == .b ? "A to B" : "B to C", onDuration: onDuration)
                    .accessibilityIdentifier("motion.duration.\(slot.letter)")
            }
            Button {
                    guard canInteract() else { return }
                model.session.setGimbalWaypoint(slot)
            } label: {
                Group {
                    if set {
                        OpcIcon.refreshCw.frame(width: 17, height: 17)
                            .frame(width: 36, height: 36)
                    } else {
                        Text(LiveGimbalCopy.set)
                            .font(LiveType.ui(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                    }
                }
                .background(LiveDesign.glassBright, in: Capsule())
            }
            .buttonStyle(.zcTapTarget)
            .accessibilityIdentifier("motion.waypoint.\(slot.letter)")
            .accessibilityLabel("\(set ? LiveGimbalCopy.update : LiveGimbalCopy.set) \(slot.letter)")
            if set {
                Button {
                    guard canInteract() else { return }
                    model.session.clearGimbalWaypoint(slot)
                } label: {
                    OpcIcon.x
                        .frame(width: 12, height: 12)
                        .foregroundStyle(LiveDesign.muted)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.zcTapTarget)
                .accessibilityLabel("Clear \(slot.letter)")
            }
        }
        .foregroundStyle(LiveDesign.text)
    }

}

private struct LiveMotionDurationDial: View {
    var value: TimeInterval
    var floor: TimeInterval
    var leg: String
    var onDuration: (TimeInterval) -> Void
    @State private var origin: TimeInterval?
    @State private var scrubValue: Double?

    @Environment(\.motionControlCanInteract) private var canInteract

    var body: some View {
        VStack(spacing: 3) {
            Text(GimbalProgram.durationLabel(value))
                .font(LiveType.ui(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.16), value: value)
            ZStack(alignment: .top) {
                MotionDurationTicks(position: (scrubValue ?? value) / 0.5)
                    .mask(LinearGradient(colors: [.clear, .white, .white, .clear],
                        startPoint: .leading, endPoint: .trailing))
                Rectangle().fill(LiveDesign.accent).frame(width: 1.5, height: 11)
            }
            .frame(height: 11)
            .clipped()
        }
        .foregroundStyle(LiveDesign.text)
        .frame(width: 180, height: 44)
        .background(LiveDesign.glassBright, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 4)
            .onChanged { drag in
                guard canInteract() else { return }
                if origin == nil { origin = value }
                let raw = min(GimbalProgram.maxDuration, max(floor,
                    (origin ?? value) - Double(drag.translation.width) / 12 * 0.5))
                scrubValue = raw
                let next = GimbalProgram.steppedDuration(raw, delta: 0, floor: floor)
                if next != value { onDuration(next) }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                    origin = nil
                    scrubValue = nil
                }
            })
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(leg) duration")
        .accessibilityValue(GimbalProgram.durationLabel(value))
        .accessibilityHint("Swipe horizontally to adjust")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 0.5 : -0.5
            onDuration(GimbalProgram.steppedDuration(value, delta: delta, floor: floor))
        }
    }
}

/// Animates only during a drag or detent settle; no permanent display timer.
private struct MotionDurationTicks: View, Animatable {
    var position: Double
    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let radius = Int(ceil(size.width / 24)) + 1
            let center = Int(position.rounded())
            for tick in max(1, center - radius)...min(Int(GimbalProgram.maxDuration * 2), center + radius) {
                let x = size.width / 2 + CGFloat(Double(tick) - position) * 12
                guard x >= 0, x <= size.width else { continue }
                let height: CGFloat = tick.isMultiple(of: 2) ? 9 : 5
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: height)),
                    with: .color(LiveDesign.muted.opacity(0.7)))
            }
        }
    }
}

private struct LiveGimbalRunPill: View {
    @Environment(AppModel.self) private var model

    @Environment(\.motionControlCanInteract) private var canInteract

    var body: some View {
        HStack(spacing: 0) {
            if model.session.gimbalMoveCanPause {
                Button(model.session.gimbalMovePaused ? "Resume" : "Pause") {
                    guard canInteract() else { return }
                    model.session.pauseOrResumeProgrammedMove()
                }
                .font(LiveType.ui(size: 13, weight: .bold))
                .foregroundStyle(LiveDesign.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .buttonStyle(.zcTapTarget)
                .accessibilityIdentifier("motion.pauseResume")
            }
            Button {
                    guard canInteract() else { return }
                model.session.runProgrammedMove()
            } label: {
                Text(
                    model.session.gimbalMoveRunning
                        ? (model.session.gimbalStartCountdown.map { "Stop · \($0)" } ?? LiveGimbalCopy.stopMove) : LiveGimbalCopy.runMove
                )
                .font(LiveType.ui(size: 13, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(LiveDesign.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .buttonStyle(.zcTapTarget)
            .accessibilityIdentifier("motion.startStop")
            .disabled(
                !model.session.canRunProgrammedMove && !model.session.gimbalMoveRunning)
            .opacity(
                model.session.canRunProgrammedMove || model.session.gimbalMoveRunning ? 1 : 0.45)

            Button {
                    guard canInteract() else { return }
                model.liveGimbalPanel = .editor
            } label: {
                OpcIcon.maximize
                    .frame(width: 16, height: 16)
                    .foregroundStyle(LiveDesign.text)
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.zcTapTarget)
            .accessibilityLabel("Expand motion control")
        }
        .liveChromeGlass(in: Capsule(), interactive: true)
    }
}

struct LiveGimbalWaypointMarks: View {
    @Environment(AppModel.self) private var model
    var feed: CGRect

    var body: some View {
        TimelineView(.periodic(from: .now, by: GimbalStick.streamInterval)) { _ in
            let live = model.session.overlayGimbalWaypoint
            let aspect = feed.width > 1 ? Double(feed.width / max(feed.height, 1)) : 16 / 9
            ZStack(alignment: .topLeading) {
                if let live {
                    if let curve = GimbalProgramCurve(program: model.session.gimbalProgram) {
                        Path { path in
                            var connected = false
                            for pose in curve.samples() {
                                let mark = GimbalWaypointOverlay.project(waypoint: pose, slot: .b,
                                    live: live, aspect: aspect)
                                guard mark.onScreen else { connected = false; continue }
                                let point = CGPoint(x: feed.minX + CGFloat(model.assist.isVisible(.mirror) ? 1 - mark.nx : mark.nx) * feed.width,
                                    y: feed.minY + CGFloat(mark.ny) * feed.height)
                                if connected { path.addLine(to: point) } else { path.move(to: point) }
                                connected = true
                            }
                        }
                        .stroke(LiveDesign.text.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                    }
                    ForEach(
                        GimbalWaypointOverlay.marks(
                            program: model.session.gimbalProgram, live: live, aspect: aspect),
                        id: \.slot
                    ) { mark in
                        Text(mark.slot.letter)
                            .font(LiveType.ui(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(LiveDesign.text)
                            .frame(width: 26, height: 26)
                            .background(
                                LiveDesign.accent.opacity(mark.onScreen ? 0.92 : 0.45), in: Circle()
                            )
                            .shadow(color: .black.opacity(0.45), radius: 2)
                            .position(
                                x: feed.minX + CGFloat(model.assist.isVisible(.mirror) ? 1 - mark.nx : mark.nx) * feed.width,
                                y: feed.minY + CGFloat(mark.ny) * feed.height
                            )
                            .opacity(mark.onScreen ? 1 : 0.7)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
