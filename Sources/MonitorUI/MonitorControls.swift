#if os(iOS)
    import MonitorPresentation
    import SwiftUI
    import UIKit

    extension View {
        /// Local text/icon shadows keep bright footage legible without copying
        /// or darkening the camera picture beneath an entire HUD row.
        public func monitorReadoutShadow() -> some View {
            compositingGroup()
                .shadow(color: .black, radius: 1.5)
                .shadow(color: .black.opacity(0.92), radius: 3)
                .shadow(color: .black.opacity(0.85), radius: 1, y: 1)
                // Rasterize with bloom padding so the halo fades instead of
                // clipping at the glyph bounds. Negative pad keeps layout.
                .padding(10)
                .drawingGroup()
                .padding(-10)
        }

        /// A complete bright/dim/bright cycle, suspended while covered, offscreen,
        /// or when the scene or accessibility settings disable motion.
        public func monitorPulse(period: TimeInterval) -> some View {
            modifier(MonitorOpacityPulse(period: period))
        }
    }

    private struct MonitorOpacityPulse: ViewModifier {
        let period: TimeInterval

        func body(content: Content) -> some View {
            MonitorDecorativePulse(period: period) { phase in
                content.opacity(1 - (1 - MonitorMotion.recPulseFloor) * phase)
            }
        }
    }

    /// Plain camera values remain legible over the picture without an opaque bar.
    public struct MonitorReadout<Value: View>: View {
        private let label: String
        private let active: Bool
        private let value: Value
        @Environment(\.monitorHDRChromeGain) private var hdrGain
        public init(_ label: String, active: Bool = false, @ViewBuilder value: () -> Value) {
            self.label = label
            self.active = active
            self.value = value()
        }
        public var body: some View {
            let tablet = UIDevice.current.userInterfaceIdiom == .pad
            let valueSize = CGFloat(MonitorReadoutTypography.valueSize(tablet: tablet))
            let ink = active ? MonitorTheme.edrAccent(gain: hdrGain) : MonitorTheme.edrText(gain: hdrGain)
            let caption = active ? MonitorTheme.edrAccent(gain: hdrGain) : MonitorTheme.edrMuted(gain: hdrGain)
            VStack(spacing: 4) {
                value.font(MonitorTheme.font(valueSize, weight: .medium))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(ink)
                Text(label).font(
                    MonitorTheme.font(
                        CGFloat(MonitorReadoutTypography.labelSize), weight: .semibold)
                ).tracking(CGFloat(MonitorReadoutTypography.labelTracking))
                    .foregroundStyle(caption)
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
                let gap = min(34, max(16, (bounds.width - total) / CGFloat(max(1, count - 1))))
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
        public init(diameter: CGFloat, recording: Bool, photo: Bool = false) {
            self.diameter = diameter
            self.recording = recording
            self.photo = photo
        }
        public var body: some View {
            let coreSize = recording ? ((diameter - 10) * 0.52).rounded() : 0
            MonitorDecorativePulse(period: MonitorMotion.recPulseDuration, enabled: recording) {
                pulse in
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
                            color: Self.mix(
                                MonitorTheme.color(0xE85A5E).opacity(0.9),
                                MonitorTheme.recording.opacity(0.3), pulse),
                            radius: 6 + (2 - 6) * pulse
                        )
                        .shadow(
                            color: MonitorTheme.recording.opacity(0.5 + (0.14 - 0.5) * pulse),
                            radius: 13 + (4.5 - 13) * pulse)
                    if photo && !recording {
                        Circle().fill(Color.white).padding(12)
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .monitorGlass(in: Circle(), density: .recording)
            .accessibilityHidden(true)
        }
    }

    extension MonitorRecordLamp {
        /// Linear blend for the pulsed glow (iOS 17 has no `Color.mix`).
        static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
            var (r1, g1, b1, a1, r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) =
                (0, 0, 0, 0, 0, 0, 0, 0)
            UIColor(a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            UIColor(b).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            let t = CGFloat(t)
            return Color(
                .sRGB, red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
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
