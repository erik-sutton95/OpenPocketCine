#if os(iOS)
    import SwiftUI

    /// Keep the original pointer sequence available to a control beneath a
    /// floating editor. The editor remains a sibling above this backdrop.
    public struct MonitorMotionDismissBackdrop: View {
        private var exclusion: CGRect
        private var dismiss: () -> Void

        public init(excluding exclusion: CGRect, onDismiss: @escaping () -> Void) {
            self.exclusion = exclusion
            self.dismiss = onDismiss
        }

        public var body: some View {
            Color.clear
                .contentShape(MotionDismissShape(exclusion: exclusion), eoFill: true)
                .onTapGesture(perform: dismiss)
                .accessibilityAddTraits(.isButton)
        }
    }

    private struct MotionDismissShape: Shape {
        var exclusion: CGRect

        func path(in rect: CGRect) -> Path {
            Path { path in
                path.addRect(rect)
                let hole = exclusion.intersection(rect)
                if !hole.isNull, !hole.isEmpty { path.addRect(hole) }
            }
        }
    }

    /// Field Monitor motion literals from the in-device HUD (CSS keyframes and
    /// `animateToolsWidth` / `morphAssist` / `morphSide` / `zoomDiscIn-Out`).
    /// Hosts should reuse these instead of one-off durations or curves.
    public enum MonitorMotion {
        public static let pressDuration: TimeInterval = 0.12
        public static let pressScale: CGFloat = 0.97
        public static let pressOpacity: Double = 0.65

        public static let drawerDuration: TimeInterval = 0.15
        public static let drawerSettle: TimeInterval = 0.18
        public static let drawerCollapsedWidth: CGFloat = 28
        public static let morphDuration: TimeInterval = 0.085

        public static let fadeDuration: TimeInterval = 0.16
        public static let dimDuration: TimeInterval = 0.18
        public static let colorDuration: TimeInterval = 0.14
        public static let lockFilterDuration: TimeInterval = 0.20

        public static let recPulseDuration: TimeInterval = 1.6
        public static let scanPulseDuration: TimeInterval = 1.4
        public static let recPulseFloor: Double = 0.25
        public static let recShapeDuration: TimeInterval = 0.22

        public static let chipPopDuration: TimeInterval = 0.22
        public static let chipPopPeak: CGFloat = 1.16
        public static let chipPopPeakFraction: Double = 0.4

        public static let zoomDiscInDuration: TimeInterval = 0.26
        public static let zoomDiscOutDuration: TimeInterval = 0.18
        public static let zoomDiscInScale: CGFloat = 0.88
        public static let zoomDiscOutScale: CGFloat = 0.90
        public static let zoomDiscSlide: CGFloat = 0.26

        /// Exact parametric representation of JS `1 - (1-k)^3`: x(t) = t.
        public static let easeOutCubic = (1.0 / 3.0, 1.0, 2.0 / 3.0, 1.0)
        /// `cubic-bezier(.2,.9,.2,1)` — chips, rec core, zoom disc in.
        public static let emphasized = (0.2, 0.9, 0.2, 1.0)
        /// `cubic-bezier(.2,.8,.2,1)` — drum type / ticks.
        public static let soft = (0.2, 0.8, 0.2, 1.0)
        /// `cubic-bezier(.22,1.2,.36,1)` — drum settle (root-owned callers).
        public static let settleCurve = (0.22, 1.2, 0.36, 1.0)
        /// `cubic-bezier(.4,0,1,1)` — zoom disc out.
        public static let discOutCurve = (0.4, 0.0, 1.0, 1.0)

        public static func press(_ reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: pressDuration)
        }

        public static func drawerReveal(_ reduceMotion: Bool) -> Animation? {
            curve(easeOutCubic, duration: drawerDuration, reduceMotion: reduceMotion)
        }

        /// Sheet-style settle: flicks keep their velocity into the spring.
        public static func drawerSpring(
            _ reduceMotion: Bool, velocity: Double = 0, span: Double = 1
        ) -> Animation? {
            if reduceMotion { return nil }
            let initial = span > 1 ? velocity / span : 0
            return .interpolatingSpring(stiffness: 220, damping: 28, initialVelocity: initial)
        }

        public static func fade(_ reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: fadeDuration)
        }

        public static func dim(_ reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: dimDuration)
        }

        public static func color(_ reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: colorDuration)
        }

        public static func recPulse(_ reduceMotion: Bool) -> Animation? {
            reduceMotion
                ? nil
                : .easeInOut(duration: recPulseDuration / 2).repeatForever(autoreverses: true)
        }

        public static func recShape(_ reduceMotion: Bool) -> Animation? {
            curve(emphasized, duration: recShapeDuration, reduceMotion: reduceMotion)
        }

        public static func chipPop(_ reduceMotion: Bool) -> Animation? {
            curve(emphasized, duration: chipPopDuration, reduceMotion: reduceMotion)
        }

        /// Zoom uses CSS ease-out independently on each `chipA/B` segment.
        /// Other chip hosts may inject their own reference easing.
        public static func chipPopScale(at progress: Double, easing: UnitCurve = .easeOut)
            -> CGFloat
        {
            let t = min(1, max(0, progress))
            if t < chipPopPeakFraction {
                return 1 + (chipPopPeak - 1) * easing.value(at: t / chipPopPeakFraction)
            }
            return chipPopPeak - (chipPopPeak - 1)
                * easing.value(at: (t - chipPopPeakFraction) / (1 - chipPopPeakFraction))
        }

        public static func discIn(_ reduceMotion: Bool) -> Animation? {
            curve(emphasized, duration: zoomDiscInDuration, reduceMotion: reduceMotion)
        }

        public static func discOut(_ reduceMotion: Bool) -> Animation? {
            curve(discOutCurve, duration: zoomDiscOutDuration, reduceMotion: reduceMotion)
        }

        public static func settle(_ reduceMotion: Bool) -> Animation? {
            curve(settleCurve, duration: 0.22, reduceMotion: reduceMotion)
        }

        public static func curve(
            _ bezier: (Double, Double, Double, Double), duration: TimeInterval,
            reduceMotion: Bool
        ) -> Animation? {
            reduceMotion
                ? nil
                : .timingCurve(bezier.0, bezier.1, bezier.2, bezier.3, duration: duration)
        }

    }
#endif
