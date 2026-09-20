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

    /// Intrinsic, bounded chrome. The host positions the expanded rectangle;
    /// the clip and content shape keep collapsed hits on the compact plate.
    public struct MonitorAssistPalette<Icon: View>: View {
        private let tools: [MonitorToolItem]
        private let layout: MonitorAssistPaletteLayout
        private let usageSeed: [String: Int]
        private let onToggle: (String) -> Void
        private let onOptions: (String) -> Void
        private let icon: (String) -> Icon
        @Binding private var expanded: Bool
        @Binding private var usage: MonitorToolUsage
        @State private var progress: Double = 0
        @State private var dragging = false
        @State private var grabOffset: Double = 0
        @State private var pinnedIDs: [String] = []
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.monitorHDRChromeGain) private var hdrGain

        public init(
            tools: [MonitorToolItem], layout: MonitorAssistPaletteLayout,
            usageSeed: [String: Int] = [:],
            usage: Binding<MonitorToolUsage>,
            expanded: Binding<Bool>, onToggle: @escaping (String) -> Void,
            onOptions: @escaping (String) -> Void,
            @ViewBuilder icon: @escaping (String) -> Icon
        ) {
            self.tools = tools
            self.layout = layout
            self.usageSeed = usageSeed
            _usage = usage
            _expanded = expanded
            self.onToggle = onToggle
            self.onOptions = onOptions
            self.icon = icon
        }

        public var body: some View {
            let compact = layout.resolving(expanded: false)
            let full = layout.resolving(expanded: true)
            let t = min(1, max(0, progress))
            let visibleW = MonitorAssistPaletteReveal.lerp(compact.width, full.width, t)
            let visibleH = MonitorAssistPaletteReveal.lerp(compact.height, full.height, t)
            let shape = PaletteRevealShape(width: visibleW, height: visibleH)
            ZStack(alignment: .bottomLeading) {
                // Portrait clips the bottom of this full-size host. Keep the
                // tool stack in a visibleH plate so the collapsed favorite
                // sits under the chevron instead of above the clip.
                toolGrid(full: full, labels: t)
                    .frame(
                        width: full.portrait ? visibleW : full.width,
                        height: full.portrait ? visibleH : full.height,
                        alignment: .topLeading)
                expansionControl(
                    compact: compact, full: full, visibleWidth: visibleW, visibleHeight: visibleH)
                    .offset(
                        x: full.portrait
                            ? MonitorAssistPaletteLayout.padding
                            : visibleW - MonitorAssistPaletteLayout.padding
                                - MonitorAssistPaletteLayout.expansionButtonWidth,
                        y: full.portrait
                            ? -(visibleH - MonitorAssistPaletteLayout.padding - 24)
                            : -MonitorAssistPaletteLayout.padding)
            }
            .frame(width: full.width, height: full.height, alignment: .bottomLeading)
            .coordinateSpace(name: "assistPalette")
            .monitorGlass(
                in: RoundedRectangle(cornerRadius: 14),
                density: t > 0.5 ? .expanded : .compact
            )
            .clipShape(shape)
            .contentShape(shape)
            .sensoryFeedback(.impact(weight: .medium), trigger: expanded)
            .onAppear {
                progress = expanded ? 1 : 0
                pinnedIDs = rankedIDs
            }
            .onChange(of: expanded) { _, open in
                guard !dragging else { return }
                if open, pinnedIDs.isEmpty { pinnedIDs = rankedIDs }
                withAnimation(MonitorMotion.drawerSpring(reduceMotion)) { progress = open ? 1 : 0 }
            }
            .onChange(of: progress) { _, value in
                if !expanded, !dragging, value <= 0.02 { pinnedIDs = rankedIDs }
            }
            .onChange(of: layout.portrait) { _, _ in
                dragging = false
                progress = expanded ? 1 : 0
            }
        }

        private var rankedIDs: [String] {
            usage.rankedIDs(in: tools.map(\.id), seed: usageSeed)
        }

        private var displayTools: [MonitorToolItem] {
            let frozen = expanded || dragging || progress > 0.02
            return MonitorAssistPaletteReveal.pinnedOrder(
                ranked: rankedIDs, pinned: pinnedIDs, frozen: frozen
            )
            .compactMap { id in tools.first { $0.id == id } }
        }

        private func toolGrid(full: MonitorAssistPaletteLayout, labels: Double) -> some View {
            let items = displayTools
            return Group {
                if full.portrait {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: MonitorAssistPaletteLayout.spacing) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, tool in
                                toolButton(tool, index: index, full: full, labels: labels)
                            }
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: MonitorAssistPaletteLayout.spacing) {
                            ForEach(0..<full.columns, id: \.self) { column in
                                VStack(spacing: MonitorAssistPaletteLayout.spacing) {
                                    ForEach(0..<2, id: \.self) { row in
                                        let index = MonitorAssistPaletteReveal.landscapeCellIndex(
                                            column: column, row: row)
                                        if items.indices.contains(index) {
                                            toolButton(
                                                items[index], index: index, full: full, labels: labels)
                                        } else {
                                            Color.clear.frame(
                                                width: full.cellWidth, height: full.cellHeight)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(
                width: full.scrollWidth,
                height: full.portrait ? nil : full.scrollHeight,
                alignment: .topLeading)
            .frame(maxHeight: full.scrollHeight)
            .scrollBounceBehavior(.basedOnSize)
            .padding(MonitorAssistPaletteLayout.padding)
            .padding(.top, full.portrait ? 24 + MonitorAssistPaletteLayout.spacing : 0)
            .padding(
                .trailing,
                full.portrait
                    ? 0
                    : MonitorAssistPaletteLayout.expansionButtonWidth
                        + MonitorAssistPaletteLayout.spacing)
        }

        private func expansionControl(
            compact: MonitorAssistPaletteLayout, full: MonitorAssistPaletteLayout,
            visibleWidth: Double, visibleHeight: Double
        ) -> some View {
            let open = progress < 0.5
            let glyph =
                full.portrait
                ? (open ? MonitorIcon.chevronUp : MonitorIcon.chevronDown)
                : (open ? MonitorIcon.chevronRight : MonitorIcon.chevronLeft)
            return glyph.frame(width: 14, height: 14).foregroundStyle(MonitorTheme.muted)
                .frame(width: full.portrait ? nil : 15)
                .frame(
                    width: full.portrait
                        ? max(0, visibleWidth - 8)
                        : MonitorAssistPaletteLayout.expansionButtonWidth,
                    height: full.portrait ? 24 : max(0, visibleHeight - 8),
                    alignment: full.portrait ? .center : .leading
                )
                .contentShape(Rectangle())
                .gesture(revealDrag(compact: compact, full: full, visibleWidth: visibleWidth, visibleHeight: visibleHeight))
                .accessibilityLabel(
                    open ? "Show all View Assist tools" : "Collapse View Assist tools"
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    expanded.toggle()
                }
                .accessibilityIdentifier(open ? "monitor.assists.expand" : "monitor.assists.collapse")
        }

        private func revealDrag(
            compact: MonitorAssistPaletteLayout, full: MonitorAssistPaletteLayout,
            visibleWidth: Double, visibleHeight: Double
        ) -> some Gesture {
            DragGesture(minimumDistance: 0, coordinateSpace: .named("assistPalette"))
                .onChanged { value in
                    let distance = hypot(
                        Double(value.translation.width), Double(value.translation.height))
                    let finger = full.portrait ? Double(value.location.y) : Double(value.location.x)
                    if !dragging {
                        guard distance >= MonitorAssistPaletteReveal.slop else { return }
                        dragging = true
                        if full.portrait {
                            grabOffset = MonitorAssistPaletteReveal.portraitGrabOffset(
                                fingerY: finger, visibleHeight: visibleHeight,
                                fullHeight: full.height)
                        } else {
                            grabOffset = visibleWidth - finger
                        }
                    }
                    if full.portrait {
                        let height = MonitorAssistPaletteReveal.portraitVisibleHeight(
                            fingerY: finger, grabOffset: grabOffset,
                            compact: compact.height, full: full.height)
                        progress = MonitorAssistPaletteReveal.progress(
                            visible: height, compact: compact.height, full: full.height)
                    } else {
                        let width = MonitorAssistPaletteReveal.visibleEdge(
                            finger: finger, grabOffset: grabOffset,
                            compact: compact.width, full: full.width)
                        progress = MonitorAssistPaletteReveal.progress(
                            visible: width, compact: compact.width, full: full.width)
                    }
                }
                .onEnded { value in
                    if !dragging {
                        expanded.toggle()
                        return
                    }
                    dragging = false
                    let span =
                        full.portrait ? full.height - compact.height : full.width - compact.width
                    let velocity = MonitorAssistPaletteReveal.translationAlongExpand(
                        dx: Double(value.velocity.width), dy: Double(value.velocity.height),
                        portrait: full.portrait)
                    let projected = MonitorAssistPaletteReveal.projectedProgress(
                        progress: progress, velocityAlongExpand: velocity, span: span)
                    let open = MonitorAssistPaletteReveal.shouldOpen(
                        progress: progress, velocityAlongExpand: velocity,
                        projectedProgress: projected)
                    expanded = open
                    withAnimation(
                        MonitorMotion.drawerSpring(reduceMotion, velocity: velocity, span: span)
                    ) {
                        progress = open ? 1 : 0
                    }
                }
        }

        private func toolButton(
            _ tool: MonitorToolItem, index: Int, full: MonitorAssistPaletteLayout, labels: Double
        ) -> some View {
            let compactCount = MonitorAssistPaletteReveal.compactToolCount(portrait: full.portrait)
            let extraOpacity = MonitorAssistPaletteReveal.extraToolOpacity(progress: labels)
            let shown = index < compactCount ? 1.0 : extraOpacity
            let labelOpacity = min(1, max(0, (labels - 0.7) / 0.3))
            let label = ZStack {
                icon(tool.id).frame(width: full.iconSide, height: full.iconSide)
                Text(tool.title).font(MonitorTheme.font(7.5, weight: .semibold))
                    .tracking(0.75).lineLimit(1)
                    .offset(y: full.cellHeight / 2 - 8)
                    .opacity(labelOpacity)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(
                tool.enabled
                    ? MonitorTheme.edrAccent(gain: hdrGain)
                    : MonitorTheme.edrSecondary(gain: hdrGain))
            .frame(width: full.cellWidth, height: full.cellHeight)
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
            .opacity(shown)
            .allowsHitTesting(shown > 0.35)
            .accessibilityHidden(shown < 0.35)
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
