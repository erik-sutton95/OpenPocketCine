#if os(iOS)
    import SwiftUI

    extension View {
        /// Local text/icon shadows keep bright footage legible without copying
        /// or darkening the camera picture beneath an entire HUD row.
        public func monitorReadoutShadow() -> some View {
            shadow(color: .black, radius: 1.5)
                .shadow(color: .black.opacity(0.92), radius: 3)
                .shadow(color: .black.opacity(0.85), radius: 1, y: 1)
        }

        /// A complete bright/dim/bright cycle, suspended offscreen or when the
        /// scene or accessibility settings disable motion.
        public func monitorPulse(period: TimeInterval) -> some View {
            modifier(MonitorOpacityPulse(period: period))
        }
    }

    private struct MonitorOpacityPulse: ViewModifier {
        let period: TimeInterval
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        @State private var appeared = false
        @State private var pulse = false

        func body(content: Content) -> some View {
            let active = appeared && scenePhase == .active && !reduceMotion
            content
                .opacity(pulse ? MonitorMotion.recPulseFloor : 1)
                .onAppear { appeared = true }
                .onDisappear { appeared = false }
                .onChange(of: active, initial: true) { _, active in
                    pulse = false
                    if active {
                        withAnimation(
                            .easeInOut(duration: period / 2).repeatForever(autoreverses: true)
                        ) {
                            pulse = true
                        }
                    }
                }
        }
    }

    /// Plain camera values remain legible over the picture without an opaque bar.
    public struct MonitorReadout<Value: View>: View {
        private let label: String
        private let active: Bool
        private let value: Value
        public init(_ label: String, active: Bool = false, @ViewBuilder value: () -> Value) {
            self.label = label
            self.active = active
            self.value = value()
        }
        public var body: some View {
            VStack(spacing: 4) {
                value.font(MonitorTheme.font(16, weight: .medium))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(active ? MonitorTheme.accent : MonitorTheme.text)
                Text(label).font(MonitorTheme.font(9, weight: .semibold)).tracking(1.26)
                    .foregroundStyle(active ? MonitorTheme.accent : MonitorTheme.muted)
                    .lineLimit(1)
            }
            .monitorReadoutShadow()
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
    }

    /// Six values become two rows on a phone in portrait. Layout consumes slots,
    /// so camera capability changes cannot leave
    /// empty columns or require brand-specific screen forks.
    public struct MonitorControlGrid: Layout {
        public var columns: Int
        public var spacing: CGFloat
        public var equalColumns: Bool
        public init(columns: Int, spacing: CGFloat = 10, equalColumns: Bool = true) {
            self.columns = max(1, columns)
            self.spacing = spacing
            self.equalColumns = equalColumns
        }
        public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
            -> CGSize
        {
            let rows = max(1, Int(ceil(Double(subviews.count) / Double(columns))))
            return CGSize(
                width: proposal.width ?? CGFloat(columns) * 80,
                height: CGFloat(rows) * 34 + CGFloat(rows - 1) * spacing)
        }
        public func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
        ) {
            let count = min(columns, max(1, subviews.count))
            if !equalColumns, subviews.count <= columns {
                let widths = subviews.map { max(44, $0.sizeThatFits(.unspecified).width) }
                let total = widths.reduce(0, +)
                let gap = min(32, max(14, (bounds.width - total) / CGFloat(max(1, count - 1))))
                let proposedWidth = total + CGFloat(max(0, count - 1)) * gap
                // Compress only when the actual labels exceed the available band.
                let scale = min(1, bounds.width / max(1, proposedWidth))
                var x = bounds.midX - proposedWidth * scale / 2
                for (index, view) in subviews.enumerated() {
                    view.place(
                        at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                        proposal: ProposedViewSize(width: widths[index] * scale, height: 34))
                    x += (widths[index] + gap) * scale
                }
                return
            }
            let cell = max(0, (bounds.width - CGFloat(count - 1) * spacing) / CGFloat(count))
            for (index, view) in subviews.enumerated() {
                view.place(
                    at: CGPoint(
                        x: bounds.minX + CGFloat(index % count) * (cell + spacing),
                        y: bounds.minY + CGFloat(index / count) * (34 + spacing)),
                    anchor: .topLeading, proposal: ProposedViewSize(width: cell, height: 34))
            }
        }
    }

    public struct MonitorRecordLamp: View {
        public var diameter: CGFloat
        public var recording: Bool
        public var photo: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        @State private var pulse = false
        @State private var appeared = false
        public init(diameter: CGFloat, recording: Bool, photo: Bool = false) {
            self.diameter = diameter
            self.recording = recording
            self.photo = photo
        }
        public var body: some View {
            let coreSize = recording ? ((diameter - 10) * 0.52).rounded() : 0
            let glow = recording && appeared && scenePhase == .active && !reduceMotion
            ZStack {
                Circle().strokeBorder(photo ? Color.white : MonitorTheme.recording, lineWidth: 4.5)
                    .padding(5)
                RoundedRectangle(cornerRadius: (coreSize * 0.24).rounded())
                    .fill(MonitorTheme.recording)
                    .frame(width: coreSize, height: coreSize)
                    .animation(MonitorMotion.recShape(reduceMotion), value: recording)
                    // Half-radius native approximation of the CSS bloom.
                    // `coreglow` changes the shadows, never the core opacity.
                    .shadow(
                        color: pulse
                            ? MonitorTheme.recording.opacity(0.3)
                            : MonitorTheme.color(0xE85A5E).opacity(0.9),
                        radius: pulse ? 2 : 6
                    )
                    .shadow(
                        color: MonitorTheme.recording.opacity(pulse ? 0.14 : 0.5),
                        radius: pulse ? 4.5 : 13)
                if photo && !recording {
                    Circle().fill(Color.white).padding(12)
                }
            }
            .frame(width: diameter, height: diameter)
            .monitorGlass(in: Circle(), density: .recording)
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
            .onChange(of: glow, initial: true) { _, active in
                pulse = false
                if active, let animation = MonitorMotion.recPulse(reduceMotion) {
                    withAnimation(animation) { pulse = true }
                }
            }
            .accessibilityHidden(true)
        }
    }

    public struct MonitorClock: View {
        private let clock: String
        private let fontSize: CGFloat
        public init(_ clock: String, fontSize: CGFloat = 23) {
            self.clock = clock
            self.fontSize = fontSize
        }
        public var body: some View {
            let split = clock.lastIndex(of: ":")
            let head = split.map { String(clock[...$0]) } ?? clock
            let tail = split.map { String(clock[clock.index(after: $0)...]) } ?? ""
            (Text(head).foregroundColor(.white) + Text(tail).foregroundColor(MonitorTheme.accent))
                .font(MonitorTheme.font(fontSize, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
                .accessibilityLabel("Timecode \(clock)")
        }
    }
#endif
