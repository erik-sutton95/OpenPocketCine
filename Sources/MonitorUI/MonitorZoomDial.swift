#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// Camera adapters own continuous write coalescing and final settlement.
    /// Opening the dial and rendering its lens annotations never issue commands.
    public struct MonitorZoomDial: View {
        private let viewport: CGSize
        private let safeArea: EdgeInsets
        private let scale: MonitorZoomScale
        private let marks: [Double]
        private let opticalStops: [Double]
        private let caption: String
        private let label: (Double) -> String
        private let onEditing: (Bool) -> Void
        private let onClose: () -> Void
        @Binding private var value: Double
        @State private var drag = MonitorZoomDrag()
        @GestureState private var pointerActive = false

        public init(
            viewport: CGSize, safeArea: EdgeInsets = EdgeInsets(), scale: MonitorZoomScale,
            marks: [Double], opticalStops: [Double] = [1], caption: String = "",
            value: Binding<Double>, label: @escaping (Double) -> String,
            onEditing: @escaping (Bool) -> Void, onClose: @escaping () -> Void
        ) {
            self.viewport = viewport
            self.safeArea = safeArea
            self.scale = scale
            self.marks = marks
            self.opticalStops = opticalStops
            self.caption = caption
            self._value = value
            self.label = label
            self.onEditing = onEditing
            self.onClose = onClose
        }

        private var radius: CGFloat {
            min(
                min(viewport.width, viewport.height) >= 600 ? 330 : 260,
                max(120, (viewport.height - 24) / 2))
        }

        private var trailingInset: CGFloat {
            viewport.width > viewport.height && safeArea.trailing > 0
                ? safeArea.trailing + 6 : 0
        }

        private var ink: Color {
            opticalStops.contains { abs($0 - value) < 0.05 }
                ? MonitorTheme.accent : MonitorTheme.color(0xF0B23C)
        }

        public var body: some View {
            ZStack(alignment: .trailing) {
                Button(action: onClose) {
                    Color.black.opacity(0.08).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close zoom dial")

                dial
                    .frame(width: radius, height: radius * 2)
                    .monitorGlass(in: MonitorZoomHalfDisc(), density: .expanded)
                    .clipShape(MonitorZoomHalfDisc())
                    .contentShape(MonitorZoomHalfDisc())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($pointerActive) { _, active, _ in active = true }
                            .onChanged { gesture in
                                if drag.begin(at: value) { onEditing(true) }
                                guard let origin = drag.anchor else { return }
                                value = scale.dragged(
                                    from: origin,
                                    angleDelta: angle(gesture.location)
                                        - angle(gesture.startLocation))
                            }
                            .onEnded { _ in finishEditing() }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Zoom dial")
                    .accessibilityValue(
                        [label(value), caption].filter { !$0.isEmpty }.joined(separator: ", ")
                    )
                    .accessibilityAdjustableAction { direction in
                        onEditing(true)
                        value = scale.value(
                            at: scale.position(value) + (direction == .increment ? 0.02 : -0.02))
                        onEditing(false)
                    }
                    .accessibilityIdentifier("monitor.zoom.dial")
                    .padding(.trailing, trailingInset)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            .frame(width: viewport.width, height: viewport.height)
            .onChange(of: viewport) { _, _ in cancelPointer() }
            .onChange(of: safeArea) { _, _ in cancelPointer() }
            .onChange(of: scale) { _, _ in cancelPointer() }
            .onChange(of: pointerActive) { _, active in if !active { finishEditing() } }
            .onDisappear(perform: finishEditing)
        }

        private func finishEditing() {
            if drag.end() { onEditing(false) }
        }

        private func cancelPointer() {
            guard pointerActive || drag.anchor != nil else { return }
            if drag.cancel() { onEditing(false) }
        }

        private func angle(_ point: CGPoint) -> Double {
            atan2(radius - point.x, point.y - radius)
        }

        private var dial: some View {
            ZStack(alignment: .leading) {
                Canvas { context, _ in
                    let unit = radius / 190
                    let position = scale.position(value)
                    let center = CGPoint(x: radius, y: radius)
                    let window = Double.pi * 0.36
                    let opticalMaximum = opticalStops.max() ?? scale.minimum
                    func point(_ angle: Double, _ distance: CGFloat) -> CGPoint {
                        CGPoint(
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
                        let color = digital ? MonitorTheme.color(0xF0B23C) : Color.white
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
                        startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
                    context.stroke(rim, with: .color(.white.opacity(0.07)), lineWidth: 1.5 * unit)
                    for tick in 0...48 { stroke(Double(tick) / 48, major: false) }
                    for mark in marks where mark >= scale.minimum && mark <= scale.maximum {
                        let fraction = scale.position(mark)
                        stroke(fraction, major: true)
                        let delta = (fraction - position) * MonitorZoomScale.angularSpan
                        guard abs(delta) <= window else { continue }
                        let opacity = fade(delta) * min(1, max(0, (abs(delta) - 0.035) / 0.075))
                        let color =
                            mark > opticalMaximum + 0.02
                            ? MonitorTheme.color(0xF0B23C) : MonitorTheme.secondary
                        context.draw(
                            Text(label(mark)).font(MonitorTheme.font(12, weight: .semibold))
                                .foregroundStyle(color.opacity(opacity)),
                            at: point(.pi + delta, 124 * unit))
                    }
                    var marker = Path()
                    marker.move(to: CGPoint(x: 14 * unit, y: radius))
                    marker.addLine(to: CGPoint(x: 46 * unit, y: radius))
                    context.stroke(
                        marker, with: .color(ink),
                        style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: 48.5 * unit, y: radius - 3.5 * unit,
                                width: 7 * unit, height: 7 * unit)), with: .color(ink))
                }
                VStack(spacing: 5) {
                    Text(label(value)).font(MonitorTheme.font(radius * 0.19, weight: .bold))
                        .monospacedDigit().foregroundStyle(MonitorTheme.text)
                    if !caption.isEmpty {
                        Text(caption).font(MonitorTheme.font(10)).tracking(1)
                            .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
                .frame(width: radius * 0.54)
                .offset(x: radius * 0.42)
                .allowsHitTesting(false)
            }
        }
    }

    private struct MonitorZoomHalfDisc: Shape {
        func path(in rect: CGRect) -> Path {
            let radius = rect.height / 2
            let control = radius * 0.5522847498
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.midY),
                control1: CGPoint(x: rect.maxX - control, y: rect.minY),
                control2: CGPoint(x: rect.minX, y: rect.midY - control))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: rect.minX, y: rect.midY + control),
                control2: CGPoint(x: rect.maxX - control, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
#endif
