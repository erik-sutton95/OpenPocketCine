#if os(iOS)
    import SwiftUI

    /// Equal choices use stable typed values; display labels never become model
    /// identifiers. Hosts supply their existing button style and optional haptic.
    public struct MonitorSegmentedControl<Value: Hashable>: View {
        private let options: [Value]
        @Binding private var selection: Value
        private let compact: Bool
        private let stacked: Bool
        private let title: (Value) -> String
        private let onSelectionFeedback: () -> Void

        public init(
            options: [Value], selection: Binding<Value>, compact: Bool = false,
            stacked: Bool = false, title: @escaping (Value) -> String,
            onSelectionFeedback: @escaping () -> Void = {}
        ) {
            self.options = options
            _selection = selection
            self.compact = compact
            self.stacked = stacked
            self.title = title
            self.onSelectionFeedback = onSelectionFeedback
        }

        public var body: some View {
            HStack(spacing: 3) {
                ForEach(options, id: \.self) { option in
                    let active = option == selection
                    Button {
                        guard option != selection else { return }
                        onSelectionFeedback()
                        selection = option
                    } label: {
                        Text(title(option))
                            .font(
                                MonitorTheme.font(
                                    stacked ? 12 : 11, weight: active ? .semibold : .medium)
                            )
                            .foregroundStyle(active ? MonitorTheme.text : MonitorTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(compact ? 0.85 : 1)
                            .padding(.horizontal, stacked || compact ? 8 : 11)
                            .padding(.vertical, stacked ? 7 : 6)
                            .frame(maxWidth: compact || stacked ? .infinity : nil)
                            .frame(minHeight: stacked ? 32 : nil)
                            .background(
                                active ? MonitorTheme.surface : Color.clear,
                                in: RoundedRectangle(
                                    cornerRadius: MonitorTheme.radius, style: .continuous))
                    }
                    .accessibilityLabel(title(option))
                    .accessibilityAddTraits(active ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(
                MonitorTheme.canvas.opacity(0.5),
                in: RoundedRectangle(cornerRadius: MonitorTheme.radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MonitorTheme.radius, style: .continuous)
                    .stroke(MonitorTheme.border, lineWidth: 1))
        }
    }
#endif
