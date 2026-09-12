#if os(iOS)
    import SwiftUI

    /// The camera-independent capture drawer: a fixed header and grabber keep
    /// dismissal reachable while an unusually long capability list can scroll.
    public struct MonitorCapturePanel<Content: View>: View {
        private let title: String
        private let subtitle: String
        private let maximumHeight: CGFloat
        private let bottomPadding: CGFloat
        private let close: () -> Void
        private let content: Content
        @State private var contentHeight: CGFloat = 86

        public init(
            title: String, subtitle: String, maximumHeight: CGFloat = .infinity,
            bottomPadding: CGFloat = 12, close: @escaping () -> Void,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self.subtitle = subtitle
            self.maximumHeight = maximumHeight
            self.bottomPadding = bottomPadding
            self.close = close
            self.content = content()
        }

        public var body: some View {
            let footer = max(12, bottomPadding)
            let available = max(0, maximumHeight - 11 - 22 - 8 - footer)
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 9) {
                    Text(title).font(MonitorTheme.font(9, weight: .semibold))
                        .tracking(1.8).foregroundStyle(MonitorTheme.text)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Text(subtitle.uppercased()).font(MonitorTheme.font(8.5))
                        .tracking(1.19).foregroundStyle(MonitorTheme.faint)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(subtitle)
                    Button(action: close) {
                        MonitorIcon.x.frame(width: 13, height: 13)
                            .foregroundStyle(MonitorTheme.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MonitorButtonStyle())
                    .padding(-11)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("monitor.capture.close")
                }
                .frame(height: 22)
                ScrollView(.vertical, showsIndicators: false) {
                    content
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            contentHeight = $0
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(contentHeight <= available)
                .frame(height: min(contentHeight, available))
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, footer)
            .overlay(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.28)).frame(width: 36, height: 4)
                    .padding(.bottom, 5).allowsHitTesting(false).accessibilityHidden(true)
            }
            .monitorGlass(
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 16, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 16), density: .expanded)
        }
    }

    /// Capture tabs are individual cyan-outlined choices rather than the solid
    /// grouped segments used on an Operator Setup page.
    public struct MonitorCaptureTabs<Value: Hashable>: View {
        private let options: [Value]
        private let selection: Value?
        private let title: (Value) -> String
        private let select: (Value) -> Void

        public init(
            options: [Value], selection: Value?, title: @escaping (Value) -> String,
            select: @escaping (Value) -> Void
        ) {
            self.options = options
            self.selection = selection
            self.title = title
            self.select = select
        }

        var rows: ForEach<[MonitorCaptureTabRow], Int, MonitorCaptureTabButton> {
            let snapshot = options.enumerated().map { index, option in
                MonitorCaptureTabRow(
                    id: index, title: title(option), selected: selection == option,
                    action: { select(option) })
            }
            return Self.renderRows(snapshot)
        }

        nonisolated static func renderRows(_ rows: [MonitorCaptureTabRow])
            -> ForEach<[MonitorCaptureTabRow], Int, MonitorCaptureTabButton>
        {
            ForEach(rows, id: \.id) { row in MonitorCaptureTabButton(row: row) }
        }

        public var body: some View {
            HStack(spacing: 6) { rows }
        }
    }

    struct MonitorCaptureTabRow: Sendable {
        let id: Int
        let title: String
        let selected: Bool
        let action: @MainActor @Sendable () -> Void
    }

    struct MonitorCaptureTabButton: View {
        nonisolated let row: MonitorCaptureTabRow
        nonisolated init(row: MonitorCaptureTabRow) { self.row = row }

        var body: some View {
            Button(action: row.action) {
                Text(row.title.uppercased())
                    .font(MonitorTheme.font(11, weight: .semibold)).tracking(0.44)
                    .foregroundStyle(row.selected ? MonitorTheme.accent : MonitorTheme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 30)
                    .background(
                        row.selected
                            ? MonitorTheme.accent.opacity(0.18) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(
                                row.selected ? MonitorTheme.accent : Color.white.opacity(0.10),
                                lineWidth: 1)
                    }
                    .padding(.vertical, 7).contentShape(Rectangle())
            }
            .buttonStyle(MonitorButtonStyle())
            .accessibilityLabel(row.title)
            .accessibilityAddTraits(row.selected ? .isSelected : [])
        }
    }

    public struct MonitorCaptureToggle: View {
        private let title: String
        private let help: String
        @Binding private var isOn: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public init(_ title: String, help: String, isOn: Binding<Bool>) {
            self.title = title
            self.help = help
            _isOn = isOn
        }

        public var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(MonitorTheme.font(11.5, weight: .semibold))
                        .foregroundStyle(MonitorTheme.text)
                    Text(help).font(MonitorTheme.font(9.5)).lineSpacing(2)
                        .foregroundStyle(MonitorTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle(title, isOn: $isOn).labelsHidden()
                    .toggleStyle(
                        CaptureSwitchStyle(
                            label: title, animation: reduceMotion ? nil : .easeOut(duration: 0.16))
                    )
                    .accessibilityLabel(title).accessibilityHint(help)
            }
            .padding(.top, 9)
            .overlay(alignment: .top) { Color.white.opacity(0.08).frame(height: 1) }
        }
    }

    private struct CaptureSwitchStyle: ToggleStyle {
        let label: String
        let animation: Animation?
        func makeBody(configuration: Configuration) -> some View {
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule().fill(configuration.isOn ? MonitorTheme.accent : Color.white.opacity(0.28))
                    .frame(width: 38, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 18, height: 18).padding(2)
                    }
                    .animation(animation, value: configuration.isOn)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(MonitorButtonStyle())
            .accessibilityLabel(label)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
            .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
        }
    }
#endif
