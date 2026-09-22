#if os(iOS)
    import SwiftUI

    /// Passive six-stop meter. The shell supplies the measured value and its availability.
    public struct MonitorExposureGauge: View {
        private let value: String
        private let needleFraction: Double?
        private let estimated: Bool

        public init(value: String, needleFraction: Double?, estimated: Bool = false) {
            self.value = value
            self.needleFraction = needleFraction
            self.estimated = estimated
        }

        public var body: some View {
            GeometryReader { proxy in
                let scale = min(proxy.size.width / 220, proxy.size.height / 64)
                VStack(spacing: 4 * scale) {
                    HStack {
                        Text(estimated ? "EV ≈" : "EV")
                            .font(MonitorTheme.font(10 * scale, weight: .semibold))
                            .tracking(scale)
                            .foregroundStyle(MonitorTheme.muted)
                        Spacer()
                        Text(value)
                            .font(MonitorTheme.font(15 * scale, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(MonitorTheme.text)
                    }
                    Canvas { context, size in
                        let mid = size.height / 2
                        for index in 0...18 {
                            let x = size.width * Double(index) / 18
                            let major = index.isMultiple(of: 3)
                            var tick = Path()
                            tick.move(to: CGPoint(x: x, y: mid - (major ? 5 : 2.5) * scale))
                            tick.addLine(to: CGPoint(x: x, y: mid + (major ? 5 : 2.5) * scale))
                            context.stroke(tick, with: .color(MonitorTheme.muted), lineWidth: scale)
                        }
                        if let needleFraction, needleFraction.isFinite {
                            let x = size.width * min(1, max(0, needleFraction))
                            let needle = Path(
                                roundedRect: CGRect(
                                    x: x - scale, y: 0, width: 2 * scale, height: size.height),
                                cornerRadius: scale)
                            context.fill(needle, with: .color(MonitorTheme.accent))
                        }
                    }
                    .frame(height: 12 * scale)
                    HStack {
                        Text("−3")
                        Spacer()
                        Text("0")
                        Spacer()
                        Text("+3")
                    }
                    .font(MonitorTheme.font(8 * scale, weight: .medium))
                    .foregroundStyle(MonitorTheme.muted)
                }
                .padding(.horizontal, 12 * scale)
                .padding(.vertical, 6 * scale)
            }
            .monitorGlass(in: RoundedRectangle(cornerRadius: 10), density: .scope)
        }
    }
#endif
