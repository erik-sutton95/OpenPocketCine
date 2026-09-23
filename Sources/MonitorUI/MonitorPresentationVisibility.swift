#if os(iOS)
    import SwiftUI

    private struct MonitorPresentationVisibilityKey: EnvironmentKey {
        static let defaultValue = true
    }

    extension EnvironmentValues {
        /// Whether this presentation can be seen. Coverage by an opaque page is
        /// separate from scene activity and from a visible source lacking pixels.
        public var monitorPresentationIsVisible: Bool {
            get { self[MonitorPresentationVisibilityKey.self] }
            set { self[MonitorPresentationVisibilityKey.self] = newValue }
        }
    }

    extension View {
        /// Hides covered presentation without removing its state or lifecycle
        /// owners. Pages and native feed owners belong outside this modifier.
        /// Zero opacity supplies normal accessibility exclusion. Controls that
        /// explicitly force AX visibility need a coverage gate on that bounded
        /// control. An ancestor AX attachment can expand a panel's frame and
        /// override descendants that explicitly hide themselves while visible.
        public func monitorPresentationVisibility(_ isVisible: Bool) -> some View {
            modifier(MonitorPresentationVisibility(isVisible: isVisible))
        }
    }

    private struct MonitorPresentationVisibility: ViewModifier {
        let isVisible: Bool
        @Environment(\.monitorPresentationIsVisible) private var parentIsVisible

        func body(content: Content) -> some View {
            let visible = parentIsVisible && isVisible
            // Modify the existing children without inserting a layout container.
            // An enclosing stack traps their zIndex inside that new stack.
            // The modifier's structure stays fixed through coverage changes.
            content
                .environment(\.monitorPresentationIsVisible, visible)
                .opacity(visible ? 1 : 0)
                .animation(nil, value: visible)
                .allowsHitTesting(visible)
        }
    }

    /// Shared lifecycle for opacity and glow pulses. `phase` runs 0 (rest) to 1
    /// (dimmest) and back, eased, once per `period`. It is sampled on a 30 Hz
    /// timeline rather than a repeating SwiftUI animation: a repeating animation
    /// keeps the view graph and render server at the panel's full ProMotion rate
    /// (120 Hz) for as long as it runs, including a whole REC take. A 1.4-1.6 s
    /// opacity/glow pulse looks the same at 30 Hz. Covered, offscreen, inactive
    /// scenes and Reduce Motion rest at phase 0 with no timeline entries.
    struct MonitorDecorativePulse<Pulsed: View>: View {
        var period: TimeInterval
        var enabled = true
        @ViewBuilder var content: (Double) -> Pulsed
        @Environment(\.monitorPresentationIsVisible) private var isVisible
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        @State private var appeared = false
        @State private var anchor = Date()

        var body: some View {
            let active = enabled && appeared && isVisible && scenePhase == .active && !reduceMotion
            TimelineView(MonitorPulseSchedule(active: active)) { context in
                content(active ? Self.phase(context.date.timeIntervalSince(anchor), period: period) : 0)
            }
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
            .onChange(of: active) { _, active in
                if active { anchor = Date() }
            }
        }

        /// Eased triangle wave: 0 at rest, 1 at half period.
        static func phase(_ elapsed: TimeInterval, period: TimeInterval) -> Double {
            guard period > 0 else { return 0 }
            let t = elapsed.truncatingRemainder(dividingBy: period) / period
            let x = t < 0.5 ? t * 2 : 2 - t * 2
            return x * x * (3 - 2 * x)
        }
    }

    /// 30 Hz while a pulse is active; a single entry (no updates) otherwise and
    /// in the low-frequency (Always-On / background) timeline mode.
    struct MonitorPulseSchedule: TimelineSchedule {
        static let interval: TimeInterval = 1.0 / 30
        var active: Bool

        func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
            guard active, mode == .normal else {
                var once: Date? = startDate
                return AnyIterator { defer { once = nil }; return once }
            }
            var next = startDate
            return AnyIterator {
                defer { next = next.addingTimeInterval(Self.interval) }
                return next
            }
        }
    }
#endif
