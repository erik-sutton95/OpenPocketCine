#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// Camera adapters own continuous write coalescing and final settlement.
    /// Opening the dial and rendering its lens annotations never issue commands.
    public struct MonitorZoomDial: View {
        private let viewport: CGSize
        private let safeArea: EdgeInsets
        private let attachment: MonitorZoomAttachment
        private let bottomClearance: CGFloat
        private let isPresented: Bool
        private let scale: MonitorZoomScale
        private let marks: [Double]
        private let opticalStops: [Double]
        private let caption: String
        private let label: (Double) -> String
        private let onEditing: (Bool) -> Void
        private let onClose: () -> Void
        private let haptics: Bool
        @Binding private var value: Double
        @State private var drag = MonitorZoomDrag()
        @State private var radial: MonitorZoomRadialGesture?
        @GestureState private var pointerActive = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        @State private var appeared = false
        @State private var detentTick = 0

        public init(
            viewport: CGSize, safeArea: EdgeInsets = EdgeInsets(),
            attachment: MonitorZoomAttachment = .trailing, bottomClearance: CGFloat = 0,
            isPresented: Bool = true,
            scale: MonitorZoomScale,
            marks: [Double], opticalStops: [Double] = [1], caption: String = "",
            value: Binding<Double>, label: @escaping (Double) -> String,
            onEditing: @escaping (Bool) -> Void, onClose: @escaping () -> Void,
            haptics: Bool = true
        ) {
            self.viewport = viewport
            self.safeArea = safeArea
            self.attachment = attachment
            self.bottomClearance = max(0, bottomClearance)
            self.isPresented = isPresented
            self.scale = scale
            self.marks = marks
            self.opticalStops = opticalStops
            self.caption = caption
            self._value = value
            self.label = label
            self.onEditing = onEditing
            self.onClose = onClose
            self.haptics = haptics
        }

        private var geometry: MonitorZoomGeometry {
            switch attachment {
            case .trailing:
                return MonitorZoomGeometry(
                    width: viewport.width, height: viewport.height,
                    trailingInset: safeArea.trailing > 0 ? safeArea.trailing + 6 : 0)
            case .bottom:
                return MonitorZoomGeometry(
                    width: viewport.width, height: viewport.height,
                    bottomInset: safeArea.bottom > 0 ? safeArea.bottom : 0,
                    attachment: .bottom)
            }
        }

        private var isBottom: Bool { attachment == .bottom }

        private var radius: CGFloat { geometry.radius }

        private var ink: Color {
            opticalStops.contains { abs($0 - value) < 0.05 }
                ? MonitorTheme.accent : MonitorTheme.digitalCrop
        }

        private var visible: Bool { appeared && isPresented }
        private var acceptsInput: Bool { visible && scenePhase == .active }

        public var body: some View {
            ZStack {
                Button(action: onClose) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close zoom dial")
                .opacity(visible ? 1 : 0)
                .animation(MonitorMotion.dim(reduceMotion), value: visible)

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: isBottom ? .bottom : .trailing) {
                        dial
                            .frame(
                                width: isBottom ? radius * 2 : radius,
                                height: isBottom ? radius : radius * 2)
                            .frame(
                                width: geometry.width, height: geometry.height,
                                alignment: isBottom ? .top : .leading)
                            .monitorGlass(
                                in: MonitorZoomHalfDisc(attachment: attachment), density: .zoom)
                            .clipShape(MonitorZoomHalfDisc(attachment: attachment))
                            .contentShape(MonitorZoomHalfDisc(attachment: attachment))
                            .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .updating($pointerActive) { _, active, _ in active = true }
                                    .onChanged { gesture in
                                        guard acceptsInput else {
                                            cancelPointer()
                                            return
                                        }
                                        guard
                                            geometry.canStartZoom(
                                                x: gesture.startLocation.x, y: gesture.startLocation.y)
                                        else { return }
                                        if drag.begin(at: value) {
                                            radial = MonitorZoomRadialGesture(
                                                geometry: geometry,
                                                startX: gesture.startLocation.x,
                                                startY: gesture.startLocation.y)
                                            onEditing(true)
                                        }
                                        guard let origin = drag.anchor else { return }
                                        guard
                                            let delta = radial?.angleDelta(
                                                x: gesture.location.x, y: gesture.location.y)
                                        else { return }
                                        value = scale.dragged(
                                            from: origin, angleDelta: delta, current: value)
                                    }
                                    .onEnded { _ in finishEditing() }
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Zoom dial")
                            .accessibilityValue(
                                [scale.dialLabel(value), caption].filter { !$0.isEmpty }.joined(
                                    separator: ", ")
                            )
                            .accessibilityAdjustableAction { direction in
                                guard acceptsInput else { return }
                                onEditing(true)
                                let step =
                                    direction == .increment
                                    ? MonitorZoomScale.tickIncrement : -MonitorZoomScale.tickIncrement
                                value = scale.quantized(value + step)
                                onEditing(false)
                            }
                            .accessibilityIdentifier("monitor.zoom.dial")
                            .scaleEffect(
                                visible || reduceMotion
                                    ? 1
                                    : (isPresented
                                        ? MonitorMotion.zoomDiscInScale
                                        : MonitorMotion.zoomDiscOutScale),
                                anchor: isBottom ? .bottom : .trailing
                            )
                            .offset(
                                x: isBottom || visible || reduceMotion
                                    ? 0 : radius * MonitorMotion.zoomDiscSlide,
                                y: !isBottom || visible || reduceMotion
                                    ? 0 : radius * MonitorMotion.zoomDiscSlide
                            )
                            .opacity(visible ? 1 : 0)
                            .animation(
                                visible
                                    ? MonitorMotion.discIn(reduceMotion)
                                    : MonitorMotion.discOut(reduceMotion),
                                value: visible
                            )
                    }
                    .padding(.bottom, isBottom ? bottomClearance : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: viewport.width, height: viewport.height)
            .allowsHitTesting(acceptsInput)
            .accessibilityHidden(!acceptsInput)
            .onAppear { appeared = true }
            .onChange(of: acceptsInput) { _, active in if !active { cancelPointer() } }
            .onChange(of: viewport) { _, _ in cancelPointer() }
            .onChange(of: attachment) { _, _ in cancelPointer() }
            .onChange(of: bottomClearance) { _, _ in cancelPointer() }
            .onChange(of: safeArea) { _, _ in cancelPointer() }
            .onChange(of: scale) { _, _ in cancelPointer() }
            .onChange(of: pointerActive) { _, active in if !active { finishEditing() } }
            .onChange(of: value) { old, new in
                guard pointerActive || drag.anchor != nil else { return }
                if MonitorDialHaptic.shouldTick(
                    previous: old, next: new, majors: MonitorZoomScale.wholeStops)
                {
                    detentTick += 1
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: detentTick) { _, _ in
                haptics && acceptsInput && detentTick > 0
            }
            .onDisappear {
                cancelPointer()
                appeared = false
            }
        }

        private func finishEditing() {
            radial = nil
            if drag.end() { onEditing(false) }
        }

        private func cancelPointer() {
            guard pointerActive || drag.anchor != nil else { return }
            radial = nil
            if drag.cancel() { onEditing(false) }
        }

        /// Freeze native value/label projections before SwiftUI dispatches the
        /// Canvas renderer. The drawing snapshot contains no session callbacks.
        var canvasSnapshot: MonitorZoomCanvasSnapshot {
            let zoom = value
            return MonitorZoomCanvasSnapshot(
                radius: radius, attachment: attachment, scale: scale,
                position: scale.position(scale.quantized(zoom)),
                opticalMaximum: opticalStops.max() ?? scale.minimum,
                marks: marks.filter { $0 >= scale.minimum && $0 <= scale.maximum }.map {
                    MonitorZoomCanvasMark(value: $0, fraction: scale.position($0), label: label($0))
                }, ink: ink, digitalInk: MonitorTheme.digitalCrop,
                secondaryInk: MonitorTheme.secondary,
                labelFont: MonitorTheme.font(12, weight: .semibold))
        }

        nonisolated static func canvas(_ snapshot: MonitorZoomCanvasSnapshot) -> Canvas<EmptyView> {
            Canvas { context, _ in
                let radius = snapshot.radius
                let scale = snapshot.scale
                let unit = radius / 190
                let position = snapshot.position
                let center = CGPoint(x: radius, y: radius)
                let window = Double.pi * 0.36
                let opticalMaximum = snapshot.opticalMaximum
                let bottom = snapshot.attachment == .bottom
                func point(_ angle: Double, _ distance: CGFloat) -> CGPoint {
                    if bottom {
                        return CGPoint(
                            x: center.x - sin(angle) * distance,
                            y: center.y + cos(angle) * distance)
                    }
                    return CGPoint(
                        x: center.x + cos(angle) * distance,
                        y: center.y + sin(angle) * distance)
                }
                func fade(_ delta: Double) -> Double {
                    min(1, max(0, (window - abs(delta)) / (0.3 * window)))
                }
                func stroke(_ fraction: Double, major: Bool) {
                    let delta = (fraction - position) * MonitorZoomScale.angularSpan
                    guard abs(delta) <= window else { return }
                    let angle = .pi + delta
                    let digital = scale.value(at: fraction) > opticalMaximum + 0.02
                    let color = digital ? snapshot.digitalInk : Color.white
                    var path = Path()
                    path.move(to: point(angle, 164 * unit))
                    path.addLine(to: point(angle, (major ? 143 : 155) * unit))
                    context.stroke(
                        path, with: .color(color.opacity((major ? 0.7 : 0.3) * fade(delta))),
                        lineWidth: (major ? 2.2 : 1.2) * unit)
                }
                var rim = Path()
                rim.addArc(
                    center: center, radius: 186 * unit,
                    startAngle: bottom ? .degrees(180) : .degrees(90),
                    endAngle: bottom ? .degrees(360) : .degrees(270), clockwise: false)
                context.stroke(rim, with: .color(.white.opacity(0.07)), lineWidth: 1.5 * unit)
                for fraction in MonitorZoomScale.minorTickPositions() {
                    let nearMajor = snapshot.marks.contains {
                        abs($0.fraction - fraction) < 0.012
                    }
                    if !nearMajor { stroke(fraction, major: false) }
                }
                for mark in snapshot.marks {
                    stroke(mark.fraction, major: true)
                    let delta = (mark.fraction - position) * MonitorZoomScale.angularSpan
                    guard abs(delta) <= window else { continue }
                    let opacity = fade(delta) * min(1, max(0, (abs(delta) - 0.035) / 0.075))
                    let color =
                        mark.value > opticalMaximum + 0.02
                        ? snapshot.digitalInk : snapshot.secondaryInk
                    context.draw(
                        Text(mark.label).font(snapshot.labelFont)
                            .foregroundStyle(color.opacity(opacity)),
                        at: point(.pi + delta, 124 * unit))
                }
                var marker = Path()
                if bottom {
                    marker.move(to: CGPoint(x: radius, y: 14 * unit))
                    marker.addLine(to: CGPoint(x: radius, y: 46 * unit))
                } else {
                    marker.move(to: CGPoint(x: 14 * unit, y: radius))
                    marker.addLine(to: CGPoint(x: 46 * unit, y: radius))
                }
                context.stroke(
                    marker, with: .color(snapshot.ink),
                    style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
                let dot = bottom
                    ? CGRect(
                        x: radius - 3.5 * unit, y: 48.5 * unit, width: 7 * unit, height: 7 * unit)
                    : CGRect(
                        x: 48.5 * unit, y: radius - 3.5 * unit, width: 7 * unit, height: 7 * unit)
                context.fill(Path(ellipseIn: dot), with: .color(snapshot.ink))
            }
        }

        private var dial: some View {
            ZStack(alignment: isBottom ? .top : .leading) {
                Self.canvas(canvasSnapshot)
                VStack(spacing: 5) {
                    Text(scale.dialLabel(value)).font(
                        MonitorTheme.font(radius * 0.19, weight: .bold))
                        .monospacedDigit().foregroundStyle(MonitorTheme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if !caption.isEmpty {
                        Text(caption).font(MonitorTheme.font(10)).tracking(1)
                            .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
                .frame(width: radius * 0.54)
                .offset(
                    x: isBottom ? 0 : radius * 0.42,
                    y: isBottom ? radius * 0.42 : 0)
                .allowsHitTesting(false)
            }
        }
    }

    struct MonitorZoomCanvasMark: Sendable {
        let value: Double
        let fraction: Double
        let label: String
    }

    struct MonitorZoomCanvasSnapshot: Sendable {
        let radius: CGFloat
        let attachment: MonitorZoomAttachment
        let scale: MonitorZoomScale
        let position: Double
        let opticalMaximum: Double
        let marks: [MonitorZoomCanvasMark]
        let ink: Color
        let digitalInk: Color
        let secondaryInk: Color
        let labelFont: Font
    }

    private struct MonitorZoomHalfDisc: Shape {
        var attachment: MonitorZoomAttachment = .trailing
        func path(in rect: CGRect) -> Path {
            let controlFactor = 0.5522847498
            var path = Path()
            if attachment == .bottom {
                let radius = rect.width / 2
                let control = radius * controlFactor
                let flat = rect.minY + radius
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: flat))
                path.addCurve(
                    to: CGPoint(x: rect.midX, y: rect.minY),
                    control1: CGPoint(x: rect.minX, y: flat - control),
                    control2: CGPoint(x: rect.midX - control, y: rect.minY))
                path.addCurve(
                    to: CGPoint(x: rect.maxX, y: flat),
                    control1: CGPoint(x: rect.midX + control, y: rect.minY),
                    control2: CGPoint(x: rect.maxX, y: flat - control))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.closeSubpath()
                return path
            }
            let radius = rect.height / 2
            let flatEdge = rect.minX + radius
            let control = radius * controlFactor
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: flatEdge, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.midY),
                control1: CGPoint(x: flatEdge - control, y: rect.minY),
                control2: CGPoint(x: rect.minX, y: rect.midY - control))
            path.addCurve(
                to: CGPoint(x: flatEdge, y: rect.maxY),
                control1: CGPoint(x: rect.minX, y: rect.midY + control),
                control2: CGPoint(x: flatEdge - control, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
#endif
