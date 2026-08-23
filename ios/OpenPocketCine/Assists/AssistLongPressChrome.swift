import SwiftUI

/// Shared long-press options chrome — OpenZCine `AssistPanel` +
/// `AssistOptionsPopupAnchor` (glass card above the assist bar).
enum AssistLongPressChrome {
    static let revealCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.20)
    static let gap: CGFloat = 10
    static let margin: CGFloat = 12
    static let slideSlack: CGFloat = 20

    /// OpenZCine `assistPanelWidth(for:)` — guides is wider; everything else is 400.
    static func preferredWidth(for tool: LiveAssistTool) -> CGFloat {
        tool == .guides ? 472 : 400
    }

    /// OpenZCine `AssistOptionsPopupAnchor`: park above the toolbar / icon, clamp into
    /// the safe viewport, cap height so a tall menu cannot become a centred sheet.
    static func panelBox(
        viewport: CGSize,
        anchor: CGRect,
        panel: CGSize,
        toolbar: CGRect = .zero,
        safeArea: EdgeInsets = EdgeInsets(),
        ceilingY: CGFloat = 0,
        gap: CGFloat = gap
    ) -> LivePopupPlacement.Box {
        LivePopupPlacement.assistOptions(
            icon: anchor,
            toolbar: toolbar.width > 1 ? toolbar : anchor,
            preferredWidth: panel.width,
            panelHeight: panel.height,
            viewport: viewport,
            safeArea: safeArea,
            ceilingY: ceilingY,
            gap: gap
        )
    }

    static func panelOrigin(
        viewport: CGSize,
        anchor: CGRect,
        panel: CGSize,
        margin: CGFloat = margin,
        gap: CGFloat = gap
    ) -> CGPoint {
        _ = margin
        return panelBox(viewport: viewport, anchor: anchor, panel: panel, gap: gap).origin
    }

    @MainActor
    @ViewBuilder
    static func menu(for tool: LiveAssistTool, assist: LiveAssistState) -> some View {
        switch tool {
        case .peaking: PeakingAssist.longPressMenu(assist: assist)
        case .falseColor: FalseColorAssist.longPressMenu(assist: assist)
        case .zebra: ZebraAssist.longPressMenu(assist: assist)
        case .lut: LUTAssist.longPressMenu(assist: assist)
        case .waveform: WaveformAssist.longPressMenu(assist: assist)
        case .parade: ParadeAssist.longPressMenu(assist: assist)
        case .histogram: HistogramAssist.longPressMenu(assist: assist)
        case .vectorscope: VectorscopeAssist.longPressMenu(assist: assist)
        case .trafficLights: TrafficLightsAssist.longPressMenu(assist: assist)
        case .guides: GuidesAssist.longPressMenu(assist: assist)
        case .grid: GridAssist.longPressMenu(assist: assist)
        case .crosshair: CrosshairAssist.longPressMenu(assist: assist)
        case .mirror: MirrorAssist.longPressMenu(assist: assist)
        case .audioMeters: AudioAssist.longPressMenu(assist: assist)
        case .level, .desqueeze, .evMeter, .instantReview, .magnification:
            EmptyView()
        }
    }

    /// Controls that must stay on screen when a tall menu scrolls.
    /// LUT's 50/50 lives here so landscape never hides it under the catalog.
    @MainActor
    @ViewBuilder
    static func footer(for tool: LiveAssistTool, assist: LiveAssistState) -> some View {
        switch tool {
        case .lut: LUTAssist.longPressFooter(assist: assist)
        default: EmptyView()
        }
    }
}

/// Icon frames in `LiveCanvasSpace`, used to park the popup above/below the chip.
private struct AssistPanelSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.height > value.height { value = next }
    }
}

struct AssistIconFrameKey: PreferenceKey {
    static var defaultValue: [LiveAssistTool: CGRect] = [:]

    static func reduce(
        value: inout [LiveAssistTool: CGRect],
        nextValue: () -> [LiveAssistTool: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// OpenZCine `AssistPanel` shell: 16pt pad, 15pt bold uppercase header, liquid glass.
/// Header and `footer` stay pinned; only `content` scrolls when the well is short.
struct AssistLongPressPanel<Content: View, Footer: View>: View {
    let tool: LiveAssistTool
    var onClose: () -> Void
    /// Well width from `AssistOptionsPopupAnchor`. Applied before hug/glass so a
    /// wide menu (LUT) cannot push the card past the rounded trailing edge.
    var width: CGFloat? = nil
    /// Remaining height under the top deck. Header stays pinned; the body
    /// scrolls only when `shouldScroll` is set by the overlay after measuring.
    var maxHeight: CGFloat? = nil
    var shouldScroll: Bool = false
    /// When false, `footer` is not laid out so EmptyView cannot add VStack spacing.
    var showsFooter: Bool = false
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text(tool.title)
                } icon: {
                    AssistToolIcon(tool: tool, size: 15)
                }
                .font(LiveType.ui(size: 15, weight: .bold, design: .default))
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(LiveDesign.text)
                Spacer(minLength: 8)
                CloseButton(action: onClose)
            }
            // Stack first — ViewThatFits unpacks a Group as alternatives.
            // Only scroll when the measured body is taller than the well.
            // Proposing a short guess (old 160 pt default) made peaking
            // scroll even with a half-screen of free space above the bar.
            if shouldScroll {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { content }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                VStack(alignment: .leading, spacing: 0) { content }
            }
            if showsFooter {
                footer
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: maxHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: maxHeight == nil || !shouldScroll)
        .liveChromeGlass(
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})
    }
}

extension AssistLongPressPanel where Footer == EmptyView {
    init(
        tool: LiveAssistTool,
        onClose: @escaping () -> Void,
        width: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        shouldScroll: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tool: tool,
            onClose: onClose,
            width: width,
            maxHeight: maxHeight,
            shouldScroll: shouldScroll,
            showsFooter: false,
            content: content,
            footer: { EmptyView() }
        )
    }
}

/// Backdrop + slide-up reveal. OpenZCine `PlaybackAssistOptionsOverlay` /
/// `PanelHost.bottomAssistBody`, parked with `AssistLongPressChrome.panelBox`.
struct AssistLongPressOverlay: View {
    let tool: LiveAssistTool
    var assist: LiveAssistState
    let anchor: CGRect
    var toolbar: CGRect = .zero
    let viewport: CGSize
    var safeArea: EdgeInsets = EdgeInsets()
    var ceilingY: CGFloat = 0
    var onDismiss: () -> Void

    @State private var revealed = false
    @State private var panelSize = CGSize.zero

    var body: some View {
        let place = AssistLongPressChrome.panelBox(
            viewport: viewport,
            anchor: anchor,
            panel: CGSize(
                width: AssistLongPressChrome.preferredWidth(for: tool),
                height: max(panelSize.height, 1)
            ),
            toolbar: toolbar,
            safeArea: safeArea,
            ceilingY: ceilingY
        )
        // Unmeasured: offer the full well so a short menu (peaking) can hug
        // instead of ViewThatFits picking a scroll view from a 160 pt guess.
        let displayHeight =
            panelSize.height > 1 ? min(panelSize.height, place.maxHeight) : place.maxHeight
        let shouldScroll = panelSize.height > place.maxHeight + 0.5
        let slide = revealed ? 0 : displayHeight + AssistLongPressChrome.slideSlack

        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            AssistLongPressPanel(
                tool: tool, onClose: onDismiss, width: place.width,
                maxHeight: place.maxHeight,
                shouldScroll: shouldScroll,
                showsFooter: tool == .lut
            ) {
                AssistLongPressChrome.menu(for: tool, assist: assist)
            } footer: {
                AssistLongPressChrome.footer(for: tool, assist: assist)
            }
            .id(tool)
            .frame(width: place.width, alignment: .leading)
            .background { unconstrainedSizeReader }
            .frame(height: max(displayHeight, 1), alignment: .top)
            .clipped()
            .offset(x: place.x, y: place.y + slide)
            .opacity(revealed ? 1 : 0)
        }
        .frame(width: viewport.width, height: viewport.height)
        .animation(.easeInOut(duration: 0.22), value: place.x)
        .animation(.easeInOut(duration: 0.22), value: place.y)
        .onAppear(perform: scheduleReveal)
        .onChange(of: tool) { _, _ in
            panelSize = .zero
            revealed = false
            scheduleReveal()
        }
    }

    /// Hug the full menu off-screen so a later scroll frame cannot shrink the
    /// measured height and flip `shouldScroll` back off.
    private var unconstrainedSizeReader: some View {
        AssistLongPressPanel(
            tool: tool, onClose: {}, width: AssistLongPressChrome.preferredWidth(for: tool),
            maxHeight: nil, shouldScroll: false, showsFooter: tool == .lut
        ) {
            AssistLongPressChrome.menu(for: tool, assist: assist)
        } footer: {
            AssistLongPressChrome.footer(for: tool, assist: assist)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: AssistPanelSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(AssistPanelSizeKey.self) { size in
            if size.height > 1 { panelSize = size }
        }
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func scheduleReveal() {
        DispatchQueue.main.async {
            withAnimation(AssistLongPressChrome.revealCurve) {
                revealed = true
            }
        }
    }
}
