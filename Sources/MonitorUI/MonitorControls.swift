#if os(iOS)
    import SwiftUI

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
            VStack(spacing: 2) {
                value.font(MonitorTheme.font(17, weight: .semibold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(active ? MonitorTheme.accent : MonitorTheme.text)
                Text(label).font(MonitorTheme.font(8.5, weight: .bold)).tracking(1.1)
                    .foregroundStyle(active ? MonitorTheme.accent : MonitorTheme.muted)
                    .lineLimit(1)
            }
            .shadow(color: .black.opacity(0.85), radius: 2, y: 1)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
    }

    /// Six values become two rows on a phone in portrait (or a short landscape
    /// canvas). Layout consumes slots, so camera capability changes cannot leave
    /// empty columns or require brand-specific screen forks.
    public struct MonitorControlGrid: Layout {
        public var columns: Int
        public var spacing: CGFloat
        public init(columns: Int, spacing: CGFloat = 10) {
            self.columns = max(1, columns)
            self.spacing = spacing
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
        @State private var pulse = false
        public init(diameter: CGFloat, recording: Bool, photo: Bool = false) {
            self.diameter = diameter
            self.recording = recording
            self.photo = photo
        }
        public var body: some View {
            ZStack {
                Circle().fill(MonitorTheme.raised)
                Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                Circle().strokeBorder(photo ? Color.white : MonitorTheme.recording, lineWidth: 4.5)
                    .padding(5)
                if recording {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(MonitorTheme.recording)
                        .frame(width: diameter * 0.32, height: diameter * 0.32)
                        .opacity(reduceMotion ? 1 : (pulse ? 0.68 : 1))
                } else if photo {
                    Circle().fill(Color.white).padding(12)
                }
            }
            .frame(width: diameter, height: diameter)
            .onChange(of: recording, initial: true) { _, active in
                pulse = false
                if active && !reduceMotion {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
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
                .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
                .accessibilityLabel("Timecode \(clock)")
        }
    }
#endif
