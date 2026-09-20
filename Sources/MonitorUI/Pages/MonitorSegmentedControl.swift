#if os(iOS)
    import SwiftUI

    public enum MonitorSegmentedAppearance: Sendable {
        case page
        case inspector
    }

    private struct MonitorSegmentedAppearanceKey: EnvironmentKey {
        static let defaultValue = MonitorSegmentedAppearance.page
    }

    extension EnvironmentValues {
        public var monitorSegmentedAppearance: MonitorSegmentedAppearance {
            get { self[MonitorSegmentedAppearanceKey.self] }
            set { self[MonitorSegmentedAppearanceKey.self] = newValue }
        }
    }

    /// Equal choices use stable typed values; display labels never become model
    /// identifiers. Hosts supply their existing button style and optional haptic.
    public struct MonitorSegmentedControl<Value: Hashable>: View {
        @Environment(\.monitorSegmentedAppearance) private var appearance
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

        /// SwiftUI may materialize ForEach rows on AsyncRenderer. Snapshot all
        /// bindings and supplied labels here, before entering that deferred path.
        var rows:
            ForEach<[MonitorRowSnapshot<Value, MonitorSegmentButton>], Value, MonitorSegmentButton>
        {
            let selected = selection
            return MonitorSnapshotRows(options, id: \.self) { option in
                MonitorSegmentButton(
                    title: title(option), active: option == selected,
                    compact: compact, stacked: stacked, appearance: appearance,
                    action: {
                        guard option != selection else { return }
                        onSelectionFeedback()
                        selection = option
                    })
            }.rows
        }

        public var body: some View {
            HStack(spacing: 3) {
                rows
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

    struct MonitorSegmentButton: View {
        nonisolated let title: String
        nonisolated let active: Bool
        nonisolated let compact: Bool
        nonisolated let stacked: Bool
        nonisolated let appearance: MonitorSegmentedAppearance
        let action: @MainActor () -> Void
        @Environment(\.monitorHDRChromeGain) private var hdrGain

        nonisolated init(
            title: String, active: Bool, compact: Bool, stacked: Bool,
            appearance: MonitorSegmentedAppearance = .page,
            action: @escaping @MainActor () -> Void
        ) {
            self.title = title
            self.active = active
            self.compact = compact
            self.stacked = stacked
            self.appearance = appearance
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(
                        MonitorTheme.font(stacked ? 12 : 11, weight: active ? .semibold : .medium)
                    )
                    .foregroundStyle(
                        active && appearance == .inspector
                            ? Color(red: 8 / 255, green: 25 / 255, blue: 31 / 255)
                            : (active
                                ? MonitorTheme.edrText(gain: hdrGain)
                                : MonitorTheme.edrMuted(gain: hdrGain))
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(appearance == .inspector ? 0.75 : (compact ? 0.85 : 1))
                    .padding(.horizontal, stacked || compact ? 8 : 11)
                    .padding(.vertical, stacked ? 7 : 6)
                    .frame(maxWidth: compact || stacked ? .infinity : nil)
                    .frame(minHeight: stacked ? 32 : nil)
                    .background(
                        active
                            ? (appearance == .inspector
                                ? MonitorTheme.accent : MonitorTheme.surface) : Color.clear,
                        in: RoundedRectangle(cornerRadius: MonitorTheme.radius, style: .continuous)
                    )
                    .animation(.easeOut(duration: MonitorMotion.colorDuration), value: active)
            }
            .buttonStyle(MonitorButtonStyle())
            .accessibilityLabel(title)
            .accessibilityAddTraits(active ? [.isSelected] : [])
        }
    }

#endif
