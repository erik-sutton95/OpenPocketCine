#if os(iOS)
    import SwiftUI

    /// Passive vertical camera meter. The shell supplies telemetry and availability.
    public struct MonitorExposureGauge: View {
        private let value: String
        private let needleFraction: Double?

        public init(value: String, needleFraction: Double?) {
            self.value = value
            self.needleFraction = needleFraction
        }

        public var body: some View {
            VStack(spacing: 3) {
                Text(value)
                    .font(MonitorTheme.font(11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(MonitorTheme.text)
                Text("EV")
                    .font(MonitorTheme.font(8, weight: .semibold))
                    .foregroundStyle(MonitorTheme.muted)
                Canvas { context, size in
                    let top: CGFloat = 4
                    let span = max(0, size.height - 8)
                    for index in 0...18 {
                        let y = top + span * Double(index) / 18
                        let major = index.isMultiple(of: 3)
                        if span < 60, !major { continue }
                        var tick = Path()
                        tick.move(to: CGPoint(x: 0, y: y))
                        tick.addLine(to: CGPoint(x: major ? 10 : 5, y: y))
                        context.stroke(tick, with: .color(MonitorTheme.muted), lineWidth: 1)
                    }
                    for (fraction, label) in [(0.0, "+3"), (0.5, "0"), (1.0, "−3")] {
                        context.draw(
                            Text(label)
                                .font(MonitorTheme.font(8, weight: .medium))
                                .foregroundStyle(MonitorTheme.muted),
                            at: CGPoint(x: 15, y: top + span * fraction), anchor: .leading)
                    }
                    if let needleFraction, needleFraction.isFinite {
                        let y = top + span * (1 - min(1, max(0, needleFraction)))
                        let needle = Path(
                            roundedRect: CGRect(x: 0, y: y - 1, width: 13, height: 2),
                            cornerRadius: 1)
                        context.fill(needle, with: .color(MonitorTheme.accent))
                    }
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 7)
            .monitorGlass(in: RoundedRectangle(cornerRadius: 7), density: .scope)
        }
    }
#endif
