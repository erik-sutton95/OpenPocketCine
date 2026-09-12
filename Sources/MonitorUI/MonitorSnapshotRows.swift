#if os(iOS)
    import SwiftUI

    /// Eager rows for small, bounded control collections. SwiftUI can materialize
    /// ForEach content on AsyncRenderer, so native bindings and label callbacks
    /// are evaluated here on MainActor and never inside its deferred closure.
    /// Use ordinary lazy containers for unbounded content such as media catalogs.
    public struct MonitorSnapshotRows<ID: Hashable, Content: View>: View {
        private let snapshots: [MonitorRowSnapshot<ID, Content>]

        public init<Data: RandomAccessCollection>(
            _ data: Data, id: KeyPath<Data.Element, ID>,
            @ViewBuilder content: (Data.Element) -> Content
        ) {
            snapshots = data.map { MonitorRowSnapshot(id: $0[keyPath: id], content: content($0)) }
        }

        public init<Data: RandomAccessCollection>(
            _ data: Data, @ViewBuilder content: (Data.Element) -> Content
        ) where Data.Element: Identifiable, ID == Data.Element.ID {
            self.init(data, id: \.id, content: content)
        }

        public var body: some View { rows }

        // Typed so native regression tests can drive the actual deferred content
        // boundary off-main, matching SwiftUI's renderer without rendering a UI.
        var rows: ForEach<[MonitorRowSnapshot<ID, Content>], ID, Content> {
            Self.makeRows(snapshots)
        }

        private nonisolated static func makeRows(
            _ snapshots: [MonitorRowSnapshot<ID, Content>]
        ) -> ForEach<[MonitorRowSnapshot<ID, Content>], ID, Content> {
            ForEach(snapshots, id: \.id) { $0.content }
        }
    }

    struct MonitorRowSnapshot<ID: Hashable, Content: View> {
        let id: ID
        let content: Content
    }
#endif
