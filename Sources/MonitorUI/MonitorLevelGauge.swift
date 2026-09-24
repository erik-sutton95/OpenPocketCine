#if os(iOS)
    import SwiftUI

    /// LEVEL in the EV meter's type, laid out like a Nikon Z virtual horizon:
    /// a slim dark band with a white centreline, a cross-bar marker, zero notches,
    /// and the number at the start. Centreline, marker and number turn green when level.
    public struct MonitorLevelGauge: View {
        public enum Axis: Sendable { case horizontal, vertical }

        /// Strip thickness, matching the EV meter.
        public static let thickness: CGFloat = 28
        public static let maxLength: CGFloat = 180
        public static let spanDeg = 8.0
        public static let levelDeg = 0.6
        /// Same green as the app's `LiveDesign.good`.
        public static let good = Color(red: 0.18, green: 0.78, blue: 0.42)
        static let band: CGFloat = 8
        static let bandFill = Color.black.opacity(0.45)

        private let axis: Axis
        private let value: Double?

        /// `value` in degrees (positive right / up); `nil` draws the bare band with `—`.
        public init(axis: Axis, value: Double?) {
            self.axis = axis
            self.value = value
        }

        /// Faint text-only shadow; the band itself carries no glow.
        static func drawReadout(_ text: Text, at point: CGPoint, in context: inout GraphicsContext) {
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.6), radius: 1.5))
                layer.draw(text, at: point)
            }
        }

        public static func label(_ value: Double?) -> String {
            guard let value else { return "—" }
            return String(format: "%+.1f°", abs(value) < 0.05 ? 0 : value)
        }

        public var body: some View {
            Canvas { context, size in
                let white = MonitorTheme.text
                let isLevel = value.map { abs($0) < Self.levelDeg } ?? false
                let tint = isLevel ? Self.good : white
                let vertical = axis == .vertical
                let length = vertical ? size.height : size.width
                let start: CGFloat = vertical ? 18 : 4
                let end = max(start, length - 4)
                let across = vertical ? size.width / 2 : size.height - 8
                func point(_ t: CGFloat, _ off: CGFloat = 0) -> CGPoint {
                    vertical ? CGPoint(x: across + off, y: t) : CGPoint(x: t, y: across + off)
                }
                // Positive reads up (vertical) or right (horizontal).
                func position(_ degrees: Double) -> CGFloat {
                    let f = CGFloat(
                        (min(Self.spanDeg, max(-Self.spanDeg, degrees)) + Self.spanDeg) / (2 * Self.spanDeg))
                    let inset = Self.band / 2
                    return vertical ? end - inset - (end - start - 2 * inset) * f : start + inset + (end - start - 2 * inset) * f
                }
                Self.drawReadout(
                    Text(Self.label(value)).font(MonitorTheme.font(10, weight: .semibold))
                        .monospacedDigit().foregroundStyle(tint),
                    at: CGPoint(x: size.width / 2, y: 6), in: &context)
                let h = Self.band / 2
                let bandRect =
                    vertical
                    ? CGRect(x: across - h, y: start, width: Self.band, height: end - start)
                    : CGRect(x: start, y: across - h, width: end - start, height: Self.band)
                context.fill(Path(roundedRect: bandRect, cornerRadius: h), with: .color(Self.bandFill))
                var centre = Path()
                centre.move(to: point(start + h))
                centre.addLine(to: point(end - h))
                context.stroke(centre, with: .color(tint.opacity(isLevel ? 1 : 0.8)), lineWidth: 1)
                // Zero notches just outside the band.
                let zero = position(0)
                var notches = Path()
                for side: CGFloat in [-1, 1] {
                    notches.move(to: point(zero, side * (h + 1)))
                    notches.addLine(to: point(zero, side * (h + 4)))
                }
                context.stroke(notches, with: .color(white.opacity(0.8)), lineWidth: 1)
                if let value {
                    let m = position(value)
                    var bar = Path()
                    bar.move(to: point(m, -(h + 2)))
                    bar.addLine(to: point(m, h + 2))
                    context.stroke(bar, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
    }

    /// Top-down / straight-up offset in the same language: dark disc band, white
    /// cross, cross-bar marker; green when within `levelDeg`.
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
                MonitorLevelGauge.drawReadout(
                    Text("\(MonitorLevelGauge.label(x)) / \(MonitorLevelGauge.label(y))")
                        .font(MonitorTheme.font(10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(tint),
                    at: CGPoint(x: mid.x, y: 6), in: &context)
                context.fill(
                    Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: 2 * r, height: 2 * r)),
                    with: .color(MonitorLevelGauge.bandFill))
                var cross = Path()
                cross.move(to: CGPoint(x: mid.x - r + 4, y: mid.y))
                cross.addLine(to: CGPoint(x: mid.x + r - 4, y: mid.y))
                cross.move(to: CGPoint(x: mid.x, y: mid.y - r + 4))
                cross.addLine(to: CGPoint(x: mid.x, y: mid.y + r - 4))
                context.stroke(cross, with: .color(tint.opacity(isLevel ? 1 : 0.8)), lineWidth: 1)
                let clamp = distance > Self.spanDeg ? Self.spanDeg / distance : 1
                let c = CGPoint(
                    x: mid.x + CGFloat(x * clamp / Self.spanDeg) * (r - 6),
                    y: mid.y - CGFloat(y * clamp / Self.spanDeg) * (r - 6))
                context.stroke(
                    Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)),
                    with: .color(tint), lineWidth: 2)
            }
            .frame(width: 2 * Self.radius + 16, height: 2 * Self.radius + 32)
        }
    }
#endif
