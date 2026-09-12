import MonitorUI
import SwiftUI
import UIKit

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
        gap: CGFloat = gap,
        keyboardHeight: CGFloat = 0
    ) -> LivePopupPlacement.Box {
        LivePopupPlacement.assistOptions(
            icon: anchor,
            toolbar: toolbar.width > 1 ? toolbar : anchor,
            preferredWidth: panel.width,
            panelHeight: panel.height,
            viewport: viewport,
            safeArea: safeArea,
            ceilingY: ceilingY,
            gap: gap,
            keyboardHeight: keyboardHeight
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
        case .ndMeter: NDAssist.longPressMenu(assist: assist)
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

struct AssistIconFrameKey: PreferenceKey {
    static var defaultValue: [LiveAssistTool: CGRect] = [:]

    static func reduce(
        value: inout [LiveAssistTool: CGRect],
        nextValue: () -> [LiveAssistTool: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Shared leading inspector; native option views continue to own their existing
/// bindings and persistence. Selecting a tab never enables that assist.
struct AssistLongPressOverlay: View {
    let tool: LiveAssistTool
    var assist: LiveAssistState
    let anchor: CGRect
    var toolbar: CGRect = .zero
    let viewport: CGSize
    var safeArea: EdgeInsets = EdgeInsets()
    var ceilingY: CGFloat = 0
    var onDismiss: () -> Void
    @State private var helpVisible = false

    private var portrait: Bool { viewport.height > viewport.width }
    private var tools: [LiveAssistTool] {
        LiveAssistTool.settingsCases.filter(\.hasConfiguration)
    }

    var body: some View {
        MonitorInspector(
            title: tool.title, viewport: viewport, safeArea: safeArea,
            helpVisible: $helpVisible,
            onClose: dismiss
        ) {
            ScrollView(portrait ? .horizontal : .vertical, showsIndicators: false) {
                let axis =
                    portrait
                    ? AnyLayout(HStackLayout(spacing: 3)) : AnyLayout(VStackLayout(spacing: 3))
                axis {
                    ForEach(tools) { item in
                        Button {
                            assist.configureTool = item
                        } label: {
                            HStack(spacing: 7) {
                                AssistToolIcon(tool: item, size: 17)
                                Text(item.rawValue).font(MonitorTheme.font(9, weight: .semibold))
                            }
                            .foregroundStyle(
                                item == tool ? MonitorTheme.accent : MonitorTheme.muted
                            )
                            .frame(width: portrait ? 88 : 96, height: 44)
                            .background(
                                item == tool ? MonitorTheme.accent.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(MonitorButtonStyle()).accessibilityLabel(item.title)
                        .accessibilityAddTraits(item == tool ? .isSelected : [])
                    }
                }.padding(.horizontal, 6)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                AssistInspectorPreview(tool: tool)
                AssistLongPressChrome.menu(for: tool, assist: assist)
                    .environment(\.monitorInspectorHelp, helpVisible)
            }
        } footer: {
            AssistLongPressChrome.footer(for: tool, assist: assist)
        }
    }

    private func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        onDismiss()
    }
}
