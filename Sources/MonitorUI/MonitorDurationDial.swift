#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// A horizontal duration ruler. The adapter supplies units, limits and write
    /// authority; dragging left increases the value. No idle timer or camera I/O.
    public struct MonitorDurationDial: View {
        private let value: Double
        private let range: ClosedRange<Double>
        private let step: Double
        private let format: (Double) -> String
        private let enabled: () -> Bool
        private let interactionIdentity: () -> AnyHashable
        private let onEditing: (Bool) -> Void
        private let onChange: (Double) -> Void
        private let haptics: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.isEnabled) private var environmentEnabled
        @State private var appeared = false
        @State private var drag = MonitorZoomDrag()
        @State private var dragIdentity: AnyHashable?
        @State private var scrubValue: Double?
        @GestureState private var pointerActive = false

        public init(
            value: Double, range: ClosedRange<Double>, step: Double,
            format: @escaping (Double) -> String, enabled: @escaping () -> Bool = { true },
            haptics: Bool = true,
            interactionIdentity: @escaping () -> AnyHashable = { AnyHashable(0) },
            onEditing: @escaping (Bool) -> Void = { _ in },
            onChange: @escaping (Double) -> Void
        ) {
            precondition(range.lowerBound.isFinite && range.upperBound.isFinite)
            precondition(step.isFinite && step > 0)
            self.range = range
            self.step = step
            self.value =
                value.isFinite
                ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
            self.format = format
            self.enabled = enabled
            self.haptics = haptics
            self.interactionIdentity = interactionIdentity
            self.onEditing = onEditing
            self.onChange = onChange
        }

        private var acceptsInput: Bool {
            appeared && enabled() && environmentEnabled && scenePhase == .active
        }

        public var body: some View {
            VStack(spacing: 3) {
                Text(format(value))
                    .font(MonitorTheme.font(14, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .animation(MonitorMotion.fade(reduceMotion), value: value)
                ZStack(alignment: .top) {
                    MonitorDurationTicks(
                        position: (scrubValue ?? value) / step,
                        minimum: range.lowerBound / step,
                        maximum: range.upperBound / step
                    )
                    .fill(MonitorTheme.muted.opacity(0.7))
                    .mask(
                        LinearGradient(
                            colors: [.clear, .white, .white, .clear],
                            startPoint: .leading, endPoint: .trailing))
                    Rectangle().fill(MonitorTheme.accent).frame(width: 1.5, height: 11)
                }
                .frame(height: 11).clipped()
            }
            .foregroundStyle(MonitorTheme.text)
            .frame(width: 180, height: 44)
            .background(MonitorTheme.raised, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .updating($pointerActive) { _, active, _ in active = true }
                    .onChanged { gesture in
                        guard acceptsInput else {
                            cancel()
                            return
                        }
                        if drag.begin(at: value) {
                            dragIdentity = interactionIdentity()
                            onEditing(true)
                        }
                        guard let origin = drag.anchor,
                            dragIdentity == interactionIdentity()
                        else {
                            cancel()
                            return
                        }
                        let raw = min(
                            range.upperBound,
                            max(
                                range.lowerBound,
                                origin - Double(gesture.translation.width) / 12 * step))
                        scrubValue = raw
                        let next = snapped(raw)
                        if next != value { onChange(next) }
                    }
                    .onEnded { _ in finish() }
            )
            .allowsHitTesting(acceptsInput)
            .opacity(enabled() && environmentEnabled ? 1 : 0.45)
            .onAppear { appeared = true }
            .onDisappear {
                cancel()
                appeared = false
            }
            .onChange(of: acceptsInput) { _, active in if !active { cancel() } }
            .onChange(of: interactionIdentity()) { _, _ in cancel() }
            .onChange(of: range) { _, _ in cancel() }
            .onChange(of: step) { _, _ in cancel() }
            .onChange(of: pointerActive) { _, active in if !active { finish() } }
            .sensoryFeedback(.impact(weight: .medium), trigger: value) { old, new in
                haptics && acceptsInput && MonitorDialHaptic.shouldTick(previous: old, next: new)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Duration")
            .accessibilityValue(format(value))
            .accessibilityHint("Swipe horizontally to adjust")
            .accessibilityAdjustableAction { direction in
                guard acceptsInput else { return }
                let next = snapped(value + (direction == .increment ? step : -step))
                guard next != value else { return }
                onEditing(true)
                onChange(next)
                onEditing(false)
            }
        }

        private func snapped(_ value: Double) -> Double {
            let ticks = ((value - range.lowerBound) / step).rounded()
            return min(range.upperBound, max(range.lowerBound, range.lowerBound + ticks * step))
        }

        private func cancel() {
            guard pointerActive || drag.anchor != nil else { return }
            if drag.cancel() { onEditing(false) }
            dragIdentity = nil
            scrubValue = nil
        }

        private func finish() {
            if drag.end() { onEditing(false) }
            dragIdentity = nil
            withAnimation(MonitorMotion.settle(reduceMotion)) { scrubValue = nil }
        }
    }

    /// Shape geometry is nonisolated, like PaletteRevealShape: native animation
    /// interpolates only numbers, with no main-actor view state or callbacks.
    private struct MonitorDurationTicks: Shape {
        var position: Double
        let minimum: Double
        let maximum: Double
        var animatableData: Double {
            get { position }
            set { position = newValue }
        }

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let radius = ceil(Double(rect.width) / 24) + 1
            let lower = max(minimum.rounded(.up), position.rounded() - radius)
            let upper = min(maximum.rounded(.down), position.rounded() + radius)
            guard lower <= upper else { return path }
            for tick in stride(from: lower, through: upper, by: 1) {
                let x = rect.midX + CGFloat(tick - position) * 12
                guard x >= rect.minX, x <= rect.maxX else { continue }
                let height: CGFloat = tick.truncatingRemainder(dividingBy: 2) == 0 ? 9 : 5
                path.addRect(CGRect(x: x, y: rect.minY, width: 1, height: height))
            }
            return path
        }
    }
#endif
