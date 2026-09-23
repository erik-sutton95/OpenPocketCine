#if os(iOS)
    import SwiftUI

    /// Passive camera telemetry, drawn as a simple sun on a vertical exposure line.
    public struct MonitorExposureGauge: View {
        private let value: String
        private let needleFraction: Double?

        public init(value: String, needleFraction: Double?) {
            self.value = value
            self.needleFraction = needleFraction
        }

        public var body: some View {
            Canvas { context, size in
                let color = MonitorTheme.text
                let x = size.width / 2
                let top: CGFloat = 34
                let bottom = max(top, size.height - 18)
                let markerY = needleFraction.flatMap { fraction -> CGFloat? in
                    guard fraction.isFinite else { return nil }
                    return top + (bottom - top) * (1 - min(1, max(0, fraction)))
                }
                context.draw(
                    Text(value).font(MonitorTheme.font(10, weight: .semibold))
                        .monospacedDigit().foregroundStyle(color),
                    at: CGPoint(x: x, y: 6))
                for (label, y) in [("+3", CGFloat(23)), ("−3", size.height - 5)] {
                    context.draw(
                        Text(label).font(MonitorTheme.font(8, weight: .medium))
                            .foregroundStyle(color),
                        at: CGPoint(x: x, y: y))
                }
                var line = Path()
                if let markerY {
                    if markerY - 9 > top {
                        line.move(to: CGPoint(x: x, y: top))
                        line.addLine(to: CGPoint(x: x, y: markerY - 9))
                    }
                    if markerY + 9 < bottom {
                        line.move(to: CGPoint(x: x, y: markerY + 9))
                        line.addLine(to: CGPoint(x: x, y: bottom))
                    }
                } else {
                    line.move(to: CGPoint(x: x, y: top))
                    line.addLine(to: CGPoint(x: x, y: bottom))
                }
                context.stroke(line, with: .color(color.opacity(0.8)), lineWidth: 1)
                if let markerY {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 2.5, y: markerY - 2.5, width: 5, height: 5)),
                        with: .color(color))
                    var rays = Path()
                    for index in 0..<8 {
                        let angle = Double(index) * .pi / 4
                        rays.move(to: CGPoint(x: x + cos(angle) * 4, y: markerY + sin(angle) * 4))
                        rays.addLine(
                            to: CGPoint(x: x + cos(angle) * 6.5, y: markerY + sin(angle) * 6.5))
                    }
                    context.stroke(
                        rays, with: .color(color),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
            }
            .monitorReadoutShadow()
        }
    }
#endif
