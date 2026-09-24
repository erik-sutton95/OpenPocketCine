#if os(iOS)
    import SwiftUI

    /// LEVEL in the EV meter's language: slim white line, dark glow, number at the
    /// start, ±span endpoints, and a bubble ring that turns green when level.
    public struct MonitorLevelGauge: View {
        public enum Axis: Sendable { case horizontal, vertical }

        /// Strip thickness, matching the EV meter.
        public static let thickness: CGFloat = 28
        public static let maxLength: CGFloat = 180
        public static let spanDeg = 8.0
        public static let levelDeg = 0.6
        /// Same green as the app's `LiveDesign.good`.
        public static let good = Color(red: 0.18, green: 0.78, blue: 0.42)

        private let axis: Axis
        private let value: Double?

        /// `value` in degrees (positive right / up); `nil` draws the bare line with `—`.
        public init(axis: Axis, value: Double?) {
            self.axis = axis
            self.value = value
        }

        public static func label(_ value: Double?) -> String {
            guard let value else { return "—" }
            return String(format: "%+.1f°", abs(value) < 0.05 ? 0 : value)
        }

        public var body: some View {
            Canvas { context, size in
                let white = MonitorTheme.text
                let isLevel = value.map { abs($0) < Self.levelDeg } ?? false
                let tint = isLevel ? MonitorLevelGauge.good : white
                let vertical = axis == .vertical
                let length = vertical ? size.height : size.width
                let start: CGFloat = vertical ? 34 : 22
                let end = max(start, length - (vertical ? 18 : 22))
                let across = (vertical ? size.width : size.height) - (vertical ? size.width / 2 : 8)
                func point(_ t: CGFloat) -> CGPoint {
                    vertical ? CGPoint(x: size.width / 2, y: t) : CGPoint(x: t, y: across)
                }
                // Positive reads up (vertical) or right (horizontal).
                func position(_ degrees: Double) -> CGFloat {
                    let f = CGFloat((min(Self.spanDeg, max(-Self.spanDeg, degrees)) + Self.spanDeg) / (2 * Self.spanDeg))
                    return vertical ? end - (end - start) * f : start + (end - start) * f
                }
                let number = Text(Self.label(value)).font(MonitorTheme.font(10, weight: .semibold))
                    .monospacedDigit().foregroundStyle(tint)
                context.draw(number, at: CGPoint(x: size.width / 2, y: 6))
                let ends: [(String, CGPoint)] =
                    vertical
                    ? [("+8", CGPoint(x: size.width / 2, y: 23)), ("−8", CGPoint(x: size.width / 2, y: size.height - 5))]
                    : [("−8", CGPoint(x: 9, y: across)), ("+8", CGPoint(x: size.width - 9, y: across))]
                for (label, at) in ends {
                    context.draw(
                        Text(label).font(MonitorTheme.font(8, weight: .medium)).foregroundStyle(white), at: at)
                }
                let marker = value.map { position($0) }
                var line = Path()
                func segment(_ a: CGFloat, _ b: CGFloat) {
                    guard b > a else { return }
                    line.move(to: point(a))
                    line.addLine(to: point(b))
                }
                if let marker {
                    let lo = min(marker - 9, end)
                    let hi = max(marker + 9, start)
                    segment(start, lo)
                    segment(hi, end)
                } else {
                    segment(start, end)
                }
                context.stroke(line, with: .color(white.opacity(0.8)), lineWidth: 1)
                // Zero reference, like a bubble vial's centre marks.
                let zero = position(0)
                var tick = Path()
                let z = point(zero)
                if vertical {
                    tick.move(to: CGPoint(x: z.x - 5, y: z.y))
                    tick.addLine(to: CGPoint(x: z.x + 5, y: z.y))
                } else {
                    tick.move(to: CGPoint(x: z.x, y: z.y - 5))
                    tick.addLine(to: CGPoint(x: z.x, y: z.y + 5))
                }
                context.stroke(tick, with: .color(white.opacity(0.8)), lineWidth: 1)
                if let marker {
                    let c = point(marker)
                    context.stroke(
                        Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)),
                        with: .color(tint), lineWidth: 1.2)
                    if isLevel {
                        context.fill(
                            Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)),
                            with: .color(tint))
                    }
                }
            }
            .monitorReadoutShadow()
        }
    }

    /// Top-down / straight-up offset in the same language: thin ring (±span),
    /// centre cross, bubble ring that turns green when within `levelDeg`.
    public struct MonitorLevelBubble: View {
        public static let radius: CGFloat = 44
        public static let spanDeg = 10.0

        private let x: Double
        private let y: Double

        public init(xDeg: Double, yDeg: Double) {
            x = xDeg
            y = yDeg
        }

        public var body: some View {
            Canvas { context, size in
                let white = MonitorTheme.text
                let r = Self.radius
                let mid = CGPoint(x: size.width / 2, y: size.height / 2 + 8)
                let distance = (x * x + y * y).squareRoot()
                let isLevel = distance < MonitorLevelGauge.levelDeg
                let tint = isLevel ? MonitorLevelGauge.good : white
                context.draw(
                    Text("\(MonitorLevelGauge.label(x)) / \(MonitorLevelGauge.label(y))")
                        .font(MonitorTheme.font(10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(tint),
                    at: CGPoint(x: mid.x, y: 6))
                context.stroke(
                    Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: 2 * r, height: 2 * r)),
                    with: .color(white.opacity(0.8)), lineWidth: 1)
                var cross = Path()
                cross.move(to: CGPoint(x: mid.x - 5, y: mid.y))
                cross.addLine(to: CGPoint(x: mid.x + 5, y: mid.y))
                cross.move(to: CGPoint(x: mid.x, y: mid.y - 5))
                cross.addLine(to: CGPoint(x: mid.x, y: mid.y + 5))
                context.stroke(cross, with: .color(white.opacity(0.8)), lineWidth: 1)
                let clamp = distance > Self.spanDeg ? Self.spanDeg / distance : 1
                let c = CGPoint(
                    x: mid.x + CGFloat(x * clamp / Self.spanDeg) * r,
                    y: mid.y - CGFloat(y * clamp / Self.spanDeg) * r)
                context.stroke(
                    Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)),
                    with: .color(tint), lineWidth: 1.2)
                if isLevel {
                    context.fill(
                        Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)),
                        with: .color(tint))
                }
            }
            .frame(width: 2 * Self.radius + 16, height: 2 * Self.radius + 32)
            .monitorReadoutShadow()
        }
    }
#endif
