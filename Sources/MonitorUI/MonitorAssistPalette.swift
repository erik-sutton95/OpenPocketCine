#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    public struct MonitorToolItem: Identifiable, Equatable {
        public var id: String
        public var title: String
        public var enabled: Bool
        public var hasOptions: Bool
        public init(id: String, title: String, enabled: Bool, hasOptions: Bool) {
            self.id = id
            self.title = title
            self.enabled = enabled
            self.hasOptions = hasOptions
        }
    }

    /// Intrinsic, bounded chrome. The host positions its actual rectangle; no
    /// expanded controls render outside a collapsed overlay's hit-test bounds.
    public struct MonitorAssistPalette<Icon: View>: View {
        private let tools: [MonitorToolItem]
        private let layout: MonitorAssistPaletteLayout
        private let usageSeed: [String: Int]
        private let onToggle: (String) -> Void
        private let onOptions: (String) -> Void
        private let icon: (String) -> Icon
        @Binding private var expanded: Bool
        @State private var usage = MonitorToolUsage()
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public init(
            tools: [MonitorToolItem], layout: MonitorAssistPaletteLayout,
            usageSeed: [String: Int] = [:],
            expanded: Binding<Bool>, onToggle: @escaping (String) -> Void,
            onOptions: @escaping (String) -> Void,
            @ViewBuilder icon: @escaping (String) -> Icon
        ) {
            self.tools = tools
            self.layout = layout
            self.usageSeed = usageSeed
            _expanded = expanded
            self.onToggle = onToggle
            self.onOptions = onOptions
            self.icon = icon
        }

        public var body: some View {
            Group {
                if expanded { fullPalette } else { collapsedPalette }
            }
            .padding(MonitorAssistPaletteLayout.padding)
            .frame(width: layout.width, height: layout.height, alignment: .bottomLeading)
            .monitorGlass(
                in: RoundedRectangle(cornerRadius: 14),
                density: expanded ? .expanded : .compact
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: expanded)
        }

        private var quickTools: [MonitorToolItem] {
            usage.rankedIDs(in: tools.map(\.id), seed: usageSeed)
                .prefix(layout.portrait ? 1 : 2)
                .compactMap { id in tools.first { $0.id == id } }
        }

        private var collapsedPalette: some View {
            let axis =
                layout.portrait
                ? AnyLayout(VStackLayout(spacing: MonitorAssistPaletteLayout.spacing))
                : AnyLayout(HStackLayout(spacing: MonitorAssistPaletteLayout.spacing))
            return axis {
                if layout.portrait { expansionButton(open: true) }
                VStack(spacing: MonitorAssistPaletteLayout.spacing) {
                    ForEach(quickTools) { toolButton($0, labels: false) }
                }
                if !layout.portrait { expansionButton(open: true) }
            }
        }

        private var fullPalette: some View {
            let axis =
                layout.portrait
                ? AnyLayout(VStackLayout(spacing: MonitorAssistPaletteLayout.spacing))
                : AnyLayout(HStackLayout(spacing: MonitorAssistPaletteLayout.spacing))
            return axis {
                if layout.portrait { expansionButton(open: false) }
                ScrollView(layout.portrait ? .vertical : .horizontal, showsIndicators: false) {
                    if layout.portrait {
                        LazyVStack(spacing: MonitorAssistPaletteLayout.spacing) {
                            ForEach(tools) { toolButton($0, labels: true) }
                        }
                    } else {
                        LazyHStack(spacing: MonitorAssistPaletteLayout.spacing) {
                            ForEach(0..<layout.columns, id: \.self) { column in
                                VStack(spacing: MonitorAssistPaletteLayout.spacing) {
                                    ForEach(0..<2, id: \.self) { row in
                                        let index = row * layout.columns + column
                                        if tools.indices.contains(index) {
                                            toolButton(tools[index], labels: true)
                                        } else {
                                            Color.clear.frame(
                                                width: layout.cellWidth,
                                                height: layout.cellHeight)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: layout.scrollWidth, height: layout.scrollHeight)
                .scrollBounceBehavior(.basedOnSize)
                .clipped()
                if !layout.portrait { expansionButton(open: false) }
            }
        }

        private func expansionButton(open: Bool) -> some View {
            Button {
                expanded = open
            } label: {
                let glyph =
                    layout.portrait
                    ? (open ? MonitorIcon.chevronUp : MonitorIcon.chevronDown)
                    : (open ? MonitorIcon.chevronRight : MonitorIcon.chevronLeft)
                glyph.frame(width: 14, height: 14).foregroundStyle(MonitorTheme.muted)
                    .frame(
                        width: layout.portrait ? max(0, layout.width - 8) : 15,
                        height: layout.portrait ? 24 : max(0, layout.height - 8)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(MonitorButtonStyle())
            .accessibilityLabel(open ? "Show all View Assist tools" : "Collapse View Assist tools")
            .accessibilityIdentifier(open ? "monitor.assists.expand" : "monitor.assists.collapse")
        }

        private func toolButton(_ tool: MonitorToolItem, labels: Bool) -> some View {
            let label = VStack(spacing: 2) {
                icon(tool.id).frame(
                    width: layout.cellHeight == 52 ? 24 : 20,
                    height: layout.cellHeight == 52 ? 24 : 20)
                if labels {
                    Text(tool.title).font(MonitorTheme.font(7.5, weight: .semibold)).lineLimit(1)
                }
            }
            .foregroundStyle(tool.enabled ? MonitorTheme.accent : MonitorTheme.secondary)
            .frame(width: layout.cellWidth, height: layout.cellHeight)
            .background(
                tool.enabled ? MonitorTheme.accent.opacity(0.13) : .clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
            return Group {
                if tool.hasOptions {
                    label.gesture(
                        LongPressGesture(minimumDuration: 0.42)
                            .exclusively(before: TapGesture())
                            .onEnded { gesture in
                                switch gesture {
                                case .first: showOptions(tool)
                                case .second: toggle(tool)
                                }
                            }
                    )
                } else {
                    // Bare tools have no hold action. A native button keeps a
                    // slow press as one toggle on release, with drag cancellation.
                    Button {
                        toggle(tool)
                    } label: {
                        label
                    }
                    .buttonStyle(MonitorButtonStyle())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tool.title).accessibilityValue(tool.enabled ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggle(tool) }
            .accessibilityActions {
                if tool.hasOptions {
                    Button("Options") { showOptions(tool) }
                }
            }
            .accessibilityIdentifier("monitor.assist.\(tool.id)")
        }

        private func toggle(_ tool: MonitorToolItem) {
            usage.recordUse(of: tool.id, seed: usageSeed)
            onToggle(tool.id)
        }

        private func showOptions(_ tool: MonitorToolItem) {
            guard tool.hasOptions else { return }
            usage.recordUse(of: tool.id, seed: usageSeed)
            expanded = false
            onOptions(tool.id)
        }
    }
#endif
