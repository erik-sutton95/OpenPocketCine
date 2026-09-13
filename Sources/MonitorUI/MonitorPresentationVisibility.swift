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

    /// Shared lifecycle for opacity and glow pulses. The host's state stays
    /// mounted while covered; stopping uses a nonanimated transaction so an
    /// ancestor's transition cannot keep the repeating animation alive.
    struct MonitorDecorativePulse: ViewModifier {
        @Binding var pulse: Bool
        var enabled = true
        let animation: Animation?
        @Environment(\.monitorPresentationIsVisible) private var isVisible
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        @State private var appeared = false

        func body(content: Content) -> some View {
            let active = enabled && appeared && isVisible && scenePhase == .active && !reduceMotion
            content
                .onAppear { appeared = true }
                .onDisappear {
                    appeared = false
                    stop()
                }
                .onChange(of: active, initial: true) { _, active in
                    if active {
                        withAnimation(animation) { pulse = true }
                    } else {
                        stop()
                    }
                }
        }

        private func stop() {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { pulse = false }
        }
    }
#endif
