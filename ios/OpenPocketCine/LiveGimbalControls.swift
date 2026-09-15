import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

private struct MotionControlInteractionKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Bool = { true }
}

extension EnvironmentValues {
    fileprivate var motionControlCanInteract: @MainActor @Sendable () -> Bool {
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
    static let dragSlop: CGFloat = 8
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
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
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

struct LiveGimbalOverlay: View {
    @Environment(AppModel.self) private var model
    var layout: LiveMonitorLayout
    var feed: CGRect
    var joystickBounds: CGRect = .zero

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
                MonitorMotionDismissBackdrop(excluding: joystickBounds) {
                    model.liveGimbalPanel = .runPill
                }
                .accessibilityLabel("Minimize motion control")
                .accessibilityIdentifier("motion.minimizeBackdrop")
                .zIndex(0.5)

                LiveGimbalMoveEditor(maximumHeight: bounds.height)
                    .frame(width: Self.editorWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(
                        LiveGimbalFloatMove(
                            stored: Bindable(model).gimbalFloatCenter,
                            sizeHint: CGSize(width: Self.editorWidth, height: 280),
                            bounds: bounds,
                            viewport: layout.viewport
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
                            sizeHint: CGSize(width: 172, height: 44),
                            bounds: bounds,
                            viewport: layout.viewport,
                            immediateDrag: true
                        )
                    )
                    .zIndex(1)
            }
        }
        .frame(width: layout.viewport.width, height: layout.viewport.height, alignment: .topLeading)
        .allowsHitTesting(model.liveGimbalPanel == .editor || model.liveGimbalPanel == .runPill)
    }

    private static let editorWidth: CGFloat = 340

}

/// Direct drag like movable scopes. The pill uses a high-priority drag so the
/// compact chrome follows the finger; the editor uses a regular drag so
/// waypoint buttons, duration dials and the smoothness slider keep theirs.
private struct LiveGimbalFloatMove: ViewModifier {
    @Binding var stored: CGPoint?
    var sizeHint: CGSize
    var bounds: CGRect
    var viewport: CGSize
    var immediateDrag = false
    @State private var measured = CGSize.zero
    @State private var dragging = false
    @State private var blockedUntil: TimeInterval = 0
    @State private var placement = MonitorFloatingDrag<CGPoint>()
    @GestureState private var pointerActive = false

    private var size: CGSize {
        CGSize(
            width: measured.width > 1 ? measured.width : sizeHint.width,
            height: measured.height > 1 ? measured.height : sizeHint.height)
    }

    private var center: CGPoint {
        let resolved = MonitorMotionPlacement.center(
            preferred: (placement.preview ?? stored).map {
                .init(x: Double($0.x), y: Double($0.y))
            },
            size: placementSize,
            viewport: .init(width: Double(viewport.width), height: Double(viewport.height)),
            bounds: placementBounds)
        return CGPoint(x: CGFloat(resolved.x), y: CGFloat(resolved.y))
    }

    private var placementSize: MonitorMotionPlacement.Size {
        .init(width: Double(size.width), height: Double(size.height))
    }

    private func clampedCenter(_ point: CGPoint) -> CGPoint {
        let resolved = MonitorMotionPlacement.clamp(
            .init(x: Double(point.x), y: Double(point.y)),
            size: placementSize, bounds: placementBounds)
        return CGPoint(x: CGFloat(resolved.x), y: CGFloat(resolved.y))
    }

    private var placementBounds: MonitorRect {
        MonitorRect(
            x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
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
            .environment(
                \.motionControlCanInteract,
                {
                    !dragging && ProcessInfo.processInfo.systemUptime >= blockedUntil
                }
            )
            .position(center)
            .onChange(of: bounds) { _, _ in cancelDrag() }
            .onChange(of: viewport) { _, _ in cancelDrag() }
            .onDisappear { cancelDrag() }
            .onChange(of: pointerActive) { _, active in
                if !active { cancelDrag() }
            }
            .gesture(directDrag, including: immediateDrag ? .none : .all)
            .highPriorityGesture(directDrag, including: immediateDrag ? .all : .none)
            .sensoryFeedback(trigger: dragging) { _, isDragging in
                isDragging ? .impact(flexibility: .rigid, intensity: 1) : nil
            }
    }

    private func cancelDrag() {
        placement.cancel()
        dragging = false
    }

    private var directDrag: some Gesture {
        DragGesture(minimumDistance: LiveGimbalCopy.dragSlop, coordinateSpace: .global)
            .updating($pointerActive) { _, active, _ in active = true }
            .onChanged { value in
                if !dragging {
                    dragging = true
                    placement.begin(at: center)
                }
                guard let origin = placement.origin else { return }
                placement.move(
                    to: clampedCenter(
                        CGPoint(
                            x: origin.x + value.translation.width,
                            y: origin.y + value.translation.height)
                    ))
            }
            .onEnded { _ in
                blockedUntil = ProcessInfo.processInfo.systemUptime + 0.15
                dragging = false
                placement.end { stored = $0 }
            }
            .map { _ in () }
    }

}

private struct LiveGimbalMoveEditor: View {
    var maximumHeight: CGFloat
    @Environment(AppModel.self) private var model

    @Environment(\.motionControlCanInteract) private var canInteract

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.hidden)
                .accessibilityIdentifier("motion.editor.scroll")
                .frame(maxHeight: maximumHeight)
        }
        .frame(maxHeight: maximumHeight)
        .monitorGlass(in: RoundedRectangle(cornerRadius: 16), density: .expanded)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(LiveGimbalCopy.programmedMove)
                    .font(MonitorTheme.font(9, weight: .semibold))
                    .textCase(.uppercase).tracking(1.8)
                    .foregroundStyle(LiveDesign.text)
                    .accessibilityIdentifier("motion.editor.title")
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
                .accessibilityIdentifier("motion.minimize")
                CloseButton(
                    action: {
                        guard canInteract() else { return }
                        model.liveGimbalPanel = .none
                    }, size: 30
                )
                .accessibilityIdentifier("motion.close")
            }

            waypointRow(.a, duration: nil, floor: nil)
            waypointRow(
                .b, duration: model.session.gimbalProgram.durationAB,
                floor: GimbalProgram.minTravelDuration(
                    from: model.session.gimbalProgram.a, to: model.session.gimbalProgram.b)
            ) { model.session.setGimbalLegDuration(ab: $0) }
            waypointRow(
                .c, duration: model.session.gimbalProgram.durationBC,
                floor: GimbalProgram.minTravelDuration(
                    from: model.session.gimbalProgram.b, to: model.session.gimbalProgram.c)
            ) { model.session.setGimbalLegDuration(bc: $0) }

            if model.session.gimbalProgram.b != nil, model.session.gimbalProgram.c != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Smoothness")
                        Spacer()
                        Text("\(Int((model.session.gimbalProgram.smoothness * 100).rounded()))%")
                    }
                    Slider(
                        value: Binding(
                            get: { model.session.gimbalProgram.smoothness },
                            set: { if canInteract() { model.session.setGimbalSmoothness($0) } }),
                        in: 0...1, step: 0.05
                    )
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
                            ? (model.session.gimbalStartCountdown.map { "Stop · \($0)" }
                                ?? LiveGimbalCopy.stopMove) : LiveGimbalCopy.runMove
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.zcTapTarget)
                .foregroundStyle(runEnabled ? LiveDesign.background : LiveDesign.muted)
                .background(
                    (model.session.gimbalMoveRunning
                        ? LiveDesign.rec
                        : runEnabled ? LiveDesign.accent : LiveDesign.glassBright),
                    in: Capsule()
                )
                .accessibilityIdentifier("motion.startStop")
                .disabled(!runEnabled && !model.session.gimbalMoveRunning)
                .opacity(runEnabled || model.session.gimbalMoveRunning ? 1 : 0.45)
            }
            .font(LiveType.ui(size: 14, weight: .semibold))
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 14, trailing: 14))
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
        let point = model.session.gimbalProgram[slot]
        let set = point != nil
        return VStack(spacing: 5) {
            HStack(spacing: 9) {
                Text(slot.letter)
                    .font(MonitorTheme.font(10, weight: .bold))
                    .foregroundStyle(set ? LiveDesign.background : LiveDesign.muted)
                    .frame(width: 22, height: 22)
                    .background(set ? LiveDesign.accent : Color.white.opacity(0.1), in: Circle())
                Text(readout(point))
                    .font(MonitorTheme.font(11)).monospacedDigit()
                    .foregroundStyle(set ? LiveDesign.text : LiveDesign.faint)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("motion.waypoint.\(slot.letter).readout")
                Button {
                    guard canInteract() else { return }
                    model.session.setGimbalWaypoint(slot)
                } label: {
                    Text(set ? "RESET" : "SET")
                        .font(MonitorTheme.font(10, weight: .bold)).tracking(0.6)
                        .foregroundStyle(set ? LiveDesign.text : LiveDesign.background)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(
                            set ? LiveDesign.glassBright : LiveDesign.accent,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .frame(minWidth: 52, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.zcTapTarget)
                .accessibilityIdentifier("motion.waypoint.\(slot.letter)")
                .accessibilityLabel(
                    "\(set ? LiveGimbalCopy.update : LiveGimbalCopy.set) \(slot.letter)")
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
            if set, let duration, let onDuration, let floor {
                HStack(spacing: 6) {
                    Text(slot == .b ? "A → B duration" : "B → C duration")
                        .font(MonitorTheme.font(8.5)).tracking(0.7)
                        .foregroundStyle(LiveDesign.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    durationDial(duration, floor: floor, slot: slot, onChange: onDuration)
                }
                .padding(.top, 6)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(Color.white.opacity(set ? 0.05 : 0.028), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(
                set ? LiveDesign.accent.opacity(0.26) : Color.white.opacity(0.07))
        )
        .foregroundStyle(LiveDesign.text)
    }

    private func durationDial(
        _ value: TimeInterval, floor: TimeInterval, slot: GimbalWaypointSlot,
        onChange: @escaping (TimeInterval) -> Void
    ) -> some View {
        let cameraID = model.session.connectedCamera?.id
        let phase = model.session.phase.label
        return MonitorDurationDial(
            value: value, range: floor...GimbalProgram.maxDuration, step: 0.5,
            format: GimbalProgram.durationLabel,
            enabled: {
                canInteract() && model.liveGimbalPanel == .editor
                    && model.session.canSetGimbalConfiguration
                    && model.session.connectedCamera?.id == cameraID
                    && model.session.phase.label == phase
            },
            haptics: model.hapticsEnabled,
            interactionIdentity: {
                AnyHashable(model.session.connectedCamera?.id)
            },
            onChange: { next in
                guard canInteract(), model.liveGimbalPanel == .editor,
                    model.session.canSetGimbalConfiguration,
                    model.session.connectedCamera?.id == cameraID,
                    model.session.phase.label == phase
                else { return }
                onChange(next)
            }
        )
        .accessibilityLabel(slot == .b ? "A to B duration" : "B to C duration")
        .accessibilityIdentifier("motion.duration.\(slot.letter)")
    }

    private func readout(_ point: GimbalWaypoint?) -> String {
        guard let point else { return "Not set" }
        return String(
            format: "PAN %+.0f°  TILT %+.0f°  %.1f×", point.yawDeg, point.pitchDeg, point.zoom)
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
                        ? (model.session.gimbalStartCountdown.map { "Stop · \($0)" }
                            ?? LiveGimbalCopy.stopMove) : LiveGimbalCopy.runMove
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
                !model.session.canRunProgrammedMove && !model.session.gimbalMoveRunning
            )
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
            .accessibilityIdentifier("motion.expand")
        }
        .frame(minWidth: 172)
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
                                let mark = GimbalWaypointOverlay.project(
                                    waypoint: pose, slot: .b,
                                    live: live, aspect: aspect)
                                guard mark.onScreen else {
                                    connected = false
                                    continue
                                }
                                let point = CGPoint(
                                    x: feed.minX + CGFloat(
                                        model.assist.isVisible(.mirror) ? 1 - mark.nx : mark.nx)
                                        * feed.width,
                                    y: feed.minY + CGFloat(mark.ny) * feed.height)
                                if connected {
                                    path.addLine(to: point)
                                } else {
                                    path.move(to: point)
                                }
                                connected = true
                            }
                        }
                        .stroke(
                            LiveDesign.text.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
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
                                x: feed.minX + CGFloat(
                                    model.assist.isVisible(.mirror) ? 1 - mark.nx : mark.nx)
                                    * feed.width,
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
