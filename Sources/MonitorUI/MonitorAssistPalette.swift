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
        @State private var fullPaletteMounted = false
        @State private var revealed = false
        @State private var collapseTask: Task<Void, Never>?
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

        private var contentLayout: MonitorAssistPaletteLayout {
            layout.resolving(expanded: expanded || fullPaletteMounted)
        }

        public var body: some View {
            let compact = layout.resolving(expanded: false)
            let full = layout.resolving(expanded: true)
            let visible = revealed ? full : compact
            let shape = PaletteRevealShape(width: visible.width, height: visible.height)
            Group {
                if expanded || fullPaletteMounted { fullPalette } else { collapsedPalette }
            }
            .padding(MonitorAssistPaletteLayout.padding)
            .frame(
                width: contentLayout.width, height: contentLayout.height, alignment: .bottomLeading
            )
            // Only the clip changes. Labels, glyphs and cells retain their final
            // size throughout the reference's 150 ms width reveal.
            .transaction { $0.animation = nil }
            .monitorGlass(
                in: RoundedRectangle(cornerRadius: 14),
                density: expanded || fullPaletteMounted ? .expanded : .compact
            )
            .clipShape(shape)
            .contentShape(shape)
            .frame(width: layout.width, height: layout.height, alignment: .bottomLeading)
            .onAppear {
                fullPaletteMounted = expanded
                revealed = expanded
            }
            .onChange(of: expanded) { _, open in
                collapseTask?.cancel()
                if open { fullPaletteMounted = true }
                withAnimation(MonitorMotion.drawerReveal(reduceMotion)) { revealed = open }
                if !open {
                    if reduceMotion {
                        fullPaletteMounted = false
                    } else {
                        collapseTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            guard !Task.isCancelled, !expanded else { return }
                            fullPaletteMounted = false
                            collapseTask = nil
                        }
                    }
                }
            }
            .onDisappear {
                collapseTask?.cancel()
                collapseTask = nil
            }
        }

        private var quickTools: [MonitorToolItem] {
            usage.rankedIDs(in: tools.map(\.id), seed: usageSeed)
                .prefix(contentLayout.portrait ? 1 : 2)
                .compactMap { id in tools.first { $0.id == id } }
        }

        private var collapsedPalette: some View {
            let axis =
                contentLayout.portrait
                ? AnyLayout(VStackLayout(spacing: MonitorAssistPaletteLayout.spacing))
                : AnyLayout(HStackLayout(spacing: MonitorAssistPaletteLayout.spacing))
            return axis {
                if contentLayout.portrait { expansionButton(open: true) }
                VStack(spacing: MonitorAssistPaletteLayout.spacing) {
                    ForEach(quickTools) { toolButton($0, labels: false) }
                }
                if !contentLayout.portrait { expansionButton(open: true) }
            }
        }

        private var fullPalette: some View {
            let axis =
                contentLayout.portrait
                ? AnyLayout(VStackLayout(spacing: MonitorAssistPaletteLayout.spacing))
                : AnyLayout(HStackLayout(spacing: MonitorAssistPaletteLayout.spacing))
            return axis {
                if contentLayout.portrait { expansionButton(open: false) }
                ScrollView(contentLayout.portrait ? .vertical : .horizontal, showsIndicators: false)
                {
                    if contentLayout.portrait {
                        LazyVStack(spacing: MonitorAssistPaletteLayout.spacing) {
                            ForEach(tools) { toolButton($0, labels: true) }
                        }
                    } else {
                        LazyHStack(spacing: MonitorAssistPaletteLayout.spacing) {
                            ForEach(0..<contentLayout.columns, id: \.self) { column in
                                VStack(spacing: MonitorAssistPaletteLayout.spacing) {
                                    ForEach(0..<2, id: \.self) { row in
                                        let index = row * contentLayout.columns + column
                                        if tools.indices.contains(index) {
                                            toolButton(tools[index], labels: true)
                                        } else {
                                            Color.clear.frame(
                                                width: contentLayout.cellWidth,
                                                height: contentLayout.cellHeight)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: contentLayout.scrollWidth, height: contentLayout.scrollHeight)
                .scrollBounceBehavior(.basedOnSize)
                .clipped()
                if !contentLayout.portrait { expansionButton(open: false) }
            }
        }

        private func expansionButton(open: Bool) -> some View {
            Button {
                expanded = open
            } label: {
                let glyph =
                    contentLayout.portrait
                    ? (open ? MonitorIcon.chevronUp : MonitorIcon.chevronDown)
                    : (open ? MonitorIcon.chevronRight : MonitorIcon.chevronLeft)
                glyph.frame(width: 14, height: 14).foregroundStyle(MonitorTheme.muted)
                    .frame(
                        width: contentLayout.portrait ? max(0, contentLayout.width - 8) : 15,
                        height: contentLayout.portrait ? 24 : max(0, contentLayout.height - 8)
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
                    width: contentLayout.cellHeight == 52 ? 24 : 20,
                    height: contentLayout.cellHeight == 52 ? 24 : 20)
                if labels {
                    Text(tool.title).font(MonitorTheme.font(7.5, weight: .semibold))
                        .tracking(0.75).lineLimit(1)
                }
            }
            .foregroundStyle(tool.enabled ? MonitorTheme.accent : MonitorTheme.secondary)
            .frame(width: contentLayout.cellWidth, height: contentLayout.cellHeight)
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

    private struct PaletteRevealShape: Shape {
        var width: CGFloat
        var height: CGFloat
        var animatableData: AnimatablePair<CGFloat, CGFloat> {
            get { AnimatablePair(width, height) }
            set {
                width = newValue.first
                height = newValue.second
            }
        }
        func path(in rect: CGRect) -> Path {
            Path(
                roundedRect: CGRect(
                    x: rect.minX, y: rect.maxY - height,
                    width: width, height: height), cornerRadius: 14)
        }
    }
#endif
