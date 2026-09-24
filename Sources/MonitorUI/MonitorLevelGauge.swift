#if os(iOS)
    import SwiftUI

    /// LEVEL laid out like a Nikon Z virtual horizon: a slim opaque dark band with
    /// a white centreline, a cross-bar marker, zero notches and the number at the
    /// start. No glow on the band; the number keeps a faint shadow. Line, marker
    /// and number turn green when level.
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
        static let bandFill = Color.black.opacity(0.32)
        /// Off-level bead in the top-down bubble.
        public static let amber = Color(red: 0.914, green: 0.674, blue: 0.208)

        private let axis: Axis
        private let value: Double?

        /// `value` in degrees (positive right / up); `nil` draws the bare band with `—`.
        public init(axis: Axis, value: Double?) {
            self.axis = axis
            self.value = value
        }

        /// Faint text-only shadow; the band carries no glow.
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

    /// Top-down / straight-up offset: ±10° ring, 5° inner ring, centre cross,
    /// and a solid bead toward the high side, amber off level and green within
    /// `levelDeg`. Readout under the ring.
    public struct MonitorLevelBubble: View {
        public static let radius: CGFloat = 64
        public static let spanDeg = 10.0

        private let x: Double
        private let y: Double

        public init(xDeg: Double, yDeg: Double) {
            x = xDeg
            y = yDeg
        }

        public var body: some View {
            let r = Self.radius
            let span = Self.spanDeg
            let distance = (x * x + y * y).squareRoot()
            let isLevel = distance < MonitorLevelGauge.levelDeg
            let clamp = distance > span ? span / distance : 1
            let tint = isLevel ? MonitorLevelGauge.good : MonitorLevelGauge.amber
            ZStack {
                Canvas { ctx, size in
                    let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: 2 * r, height: 2 * r)),
                        with: .color(.white.opacity(0.22)), lineWidth: 2)
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: mid.x - r / 2, y: mid.y - r / 2, width: r, height: r)),
                        with: .color(.white.opacity(0.34)), lineWidth: 1)
                    var cross = Path()
                    cross.move(to: CGPoint(x: mid.x - 9, y: mid.y))
                    cross.addLine(to: CGPoint(x: mid.x + 9, y: mid.y))
                    cross.move(to: CGPoint(x: mid.x, y: mid.y - 9))
                    cross.addLine(to: CGPoint(x: mid.x, y: mid.y + 9))
                    ctx.stroke(cross, with: .color(.white.opacity(0.75)), lineWidth: 2)
                }
                .frame(width: 2 * r + 4, height: 2 * r + 4)
                Circle()
                    .fill(tint)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .offset(x: CGFloat(x * clamp / span) * r, y: -CGFloat(y * clamp / span) * r)
                Text("\(MonitorLevelGauge.label(x)) / \(MonitorLevelGauge.label(y))")
                    .font(MonitorTheme.font(11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(isLevel ? MonitorLevelGauge.good : MonitorTheme.text.opacity(0.85))
                    .fixedSize()
                    .offset(y: r + 14)
            }
            .animation(.easeOut(duration: 0.12), value: isLevel)
            .animation(.easeOut(duration: 0.09), value: x)
            .animation(.easeOut(duration: 0.09), value: y)
        }
    }
#endif
