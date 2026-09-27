#if os(iOS)
    import SwiftUI

    /// Which ends of a scroll view still have content past them.
    private struct MonitorScrollEdges: Equatable {
        var start = false
        var end = false
    }

    /// Alpha-masks a scroll view's content at an edge only while more content
    /// lies that way. Nothing is painted, so the page background shows through.
    private struct MonitorScrollFade: ViewModifier {
        let axis: Axis
        let depth: CGFloat
        @State private var edges = MonitorScrollEdges()

        func body(content: Content) -> some View {
            // ponytail: iOS 17 has no scroll geometry callback, so it gets no fade.
            if #available(iOS 18.0, *) {
                content
                    .onScrollGeometryChange(for: MonitorScrollEdges.self) { geometry in
                        let vertical = axis == .vertical
                        let offset =
                            vertical
                            ? geometry.contentOffset.y + geometry.contentInsets.top
                            : geometry.contentOffset.x + geometry.contentInsets.leading
                        let remaining =
                            vertical
                            ? geometry.contentSize.height + geometry.contentInsets.bottom
                                - geometry.containerSize.height - geometry.contentOffset.y
                            : geometry.contentSize.width + geometry.contentInsets.trailing
                                - geometry.containerSize.width - geometry.contentOffset.x
                        return MonitorScrollEdges(start: offset > 1, end: remaining > 1)
                    } action: { _, next in
                        edges = next
                    }
                    .mask { mask }
            } else {
                content
            }
        }

        private var mask: some View {
            GeometryReader { proxy in
                let length = axis == .vertical ? proxy.size.height : proxy.size.width
                let fraction = length > 0 ? min(depth, length / 2) / length : 0
                LinearGradient(
                    stops: [
                        .init(color: edges.start ? .clear : .black, location: 0),
                        .init(color: .black, location: fraction),
                        .init(color: .black, location: 1 - fraction),
                        .init(color: edges.end ? .clear : .black, location: 1),
                    ],
                    startPoint: axis == .vertical ? .top : .leading,
                    endPoint: axis == .vertical ? .bottom : .trailing)
            }
        }
    }

    extension View {
        /// Apply directly to a `ScrollView` (or `List`). See `MonitorScrollFade`.
        public func monitorScrollFade(_ axis: Axis = .vertical, depth: CGFloat = 24) -> some View {
            modifier(MonitorScrollFade(axis: axis, depth: depth))
        }
    }
#endif
