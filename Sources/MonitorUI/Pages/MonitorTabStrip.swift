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

    /// A single shared surface for adjacent tabs. Hosts retain typed selections,
    /// scrolling and camera actions; only the strip's presentation lives here.
    public struct MonitorTabStrip<Content: View>: View {
        private let vertical: Bool
        private let content: Content

        public init(vertical: Bool = false, @ViewBuilder content: () -> Content) {
            self.vertical = vertical
            self.content = content()
        }

        public var body: some View {
            let layout =
                vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout { content }
                .environment(\.monitorVerticalTabs, vertical)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(MonitorTheme.border, lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }

    private struct MonitorTabSurface: ViewModifier {
        @Environment(\.monitorVerticalTabs) private var vertical
        let selected: Bool
        let separator: Bool

        func body(content: Content) -> some View {
            content
                .frame(minWidth: 44, minHeight: 44)
                .background(selected ? MonitorTheme.accent.opacity(0.10) : .clear)
                .overlay(alignment: vertical ? .top : .leading) {
                    if separator {
                        Rectangle().fill(MonitorTheme.border)
                            .frame(width: vertical ? nil : 1, height: vertical ? 1 : nil)
                            .allowsHitTesting(false)
                    }
                }
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
        public func monitorTabSurface(selected: Bool, separator: Bool = true) -> some View {
            modifier(MonitorTabSurface(selected: selected, separator: separator))
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
