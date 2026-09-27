#if os(iOS)
    import SwiftUI

    private struct MonitorVerticalTabsKey: EnvironmentKey {
        static let defaultValue = false
    }

    extension EnvironmentValues {
        fileprivate var monitorVerticalTabs: Bool {
            get { self[MonitorVerticalTabsKey.self] }
            set { self[MonitorVerticalTabsKey.self] = newValue }
        }
    }

    /// One edge line for adjacent tabs, with no plate or individual boxes.
    /// Hosts retain typed selections, scrolling and camera actions.
    public struct MonitorTabStrip<Content: View>: View {
        private let vertical: Bool
        private let spacing: CGFloat
        private let minLength: CGFloat
        private let content: Content

        /// `minLength` stretches the baseline along the strip, e.g. a rail that
        /// spans its panel while tabs stay top/leading aligned.
        public init(
            vertical: Bool = false, spacing: CGFloat = 0, minLength: CGFloat = 0,
            @ViewBuilder content: () -> Content
        ) {
            self.vertical = vertical
            self.spacing = spacing
            self.minLength = minLength
            self.content = content()
        }

        public var body: some View {
            let layout =
                vertical
                ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
            layout { content }
                .environment(\.monitorVerticalTabs, vertical)
                .frame(
                    minWidth: !vertical && minLength > 0 ? minLength : nil,
                    minHeight: vertical && minLength > 0 ? minLength : nil,
                    alignment: vertical ? .top : .leading
                )
                .background(alignment: vertical ? .leading : .bottom) {
                    Rectangle().fill(MonitorTheme.border)
                        .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
                        .allowsHitTesting(false)
                }
        }
    }

    private struct MonitorTabSurface: ViewModifier {
        @Environment(\.monitorVerticalTabs) private var vertical
        let selected: Bool

        func body(content: Content) -> some View {
            content
                .frame(minWidth: 44, minHeight: 44)
                .overlay(alignment: vertical ? .leading : .bottom) {
                    if selected {
                        Rectangle().fill(MonitorTheme.accent)
                            .frame(width: vertical ? 2 : nil, height: vertical ? nil : 2)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
        }
    }

    extension View {
        public func monitorTabSurface(selected: Bool, separator _: Bool = true) -> some View {
            modifier(MonitorTabSurface(selected: selected))
        }
    }

    /// Press feedback keeps joined edges in place rather than scaling one tab.
    public struct MonitorTabButtonStyle: ButtonStyle {
        public init() {}
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? MonitorMotion.pressOpacity : 1)
        }
    }
#endif
