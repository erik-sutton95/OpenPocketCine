#if os(iOS)
    import SwiftUI

    /// The floating system control shared by monitor shells. Layout supplies
    /// the visible size; the widget owns its glass, shape, state and press style.
    /// Camera actions and haptics remain with the caller.
    public struct MonitorChromeButton<Label: View>: View {
        private let title: String
        private let size: CGSize
        private let active: Bool
        private let action: () -> Void
        private let label: Label
        @Environment(\.isEnabled) private var isEnabled

        public init(
            _ title: String, size: CGSize, active: Bool = false,
            action: @escaping () -> Void, @ViewBuilder label: () -> Label
        ) {
            self.title = title
            self.size = size
            self.active = active
            self.action = action
            self.label = label()
        }

        public var body: some View {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            Button(action: action) {
                label
                    .foregroundStyle(active ? MonitorTheme.accent : MonitorTheme.text.opacity(0.86))
                    .frame(width: size.width, height: size.height)
                    .monitorGlass(in: shape)
                    .overlay {
                        if active {
                            shape.strokeBorder(MonitorTheme.accent.opacity(0.75), lineWidth: 1.5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .buttonStyle(MonitorButtonStyle())
            .opacity(isEnabled ? 1 : 0.4)
            .accessibilityLabel(title)
        }
    }
#endif
