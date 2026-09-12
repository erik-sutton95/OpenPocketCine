#if os(iOS)
    import SwiftUI

    private struct MonitorInspectorHelpKey: EnvironmentKey {
        static let defaultValue: Bool? = nil
    }

    extension EnvironmentValues {
        /// Nil keeps ordinary settings help badges; an inspector chooses inline
        /// guidance with true, or a quiet controls-only presentation with false.
        public var monitorInspectorHelp: Bool? {
            get { self[MonitorInspectorHelpKey.self] }
            set { self[MonitorInspectorHelpKey.self] = newValue }
        }
    }
#endif
