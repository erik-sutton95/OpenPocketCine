import SwiftUI
import UIKit

/// OpenZCine landscape assist strip: bottom-left, ~⅓ width (chrome sizes the slot),
/// grouped into threes with a divider, gold edge chevrons, long-press tray.
/// AUDIO rides its own trailing section. Ignores taps when locked.
///
/// Level and De-SQ are not on this bar (Pocket has no anamorphic squeeze; horizon
/// is not shipped). Grouping matches OpenZCine `MonitorAssistStrip` after those
/// two chips are removed: LUT/PEAK/FALSE | ZEBRA/WAVE/PARADE | HISTO/VECTOR/LIGHTS
/// | GUIDES/GRID/CROSS | MIRROR | AUDIO.
struct LiveAssistBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var environmentLocked
    var isLocked = false
    @State private var edgeFades = ScrollEdgeFades(leading: false, trailing: true)
    @State private var iconFrames: [LiveAssistTool: CGRect] = [:]
    @State private var toolbarFrame: CGRect = .zero

    private var locked: Bool { isLocked || environmentLocked }
    private var assist: LiveAssistState { model.assist }

    var body: some View {
        bar
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.18), value: edgeFades)
            .onPreferenceChange(AssistIconFrameKey.self) { frames in
                iconFrames = frames
                if let tool = assist.configureTool, let frame = frames[tool], frame.width > 1 {
                    assist.longPressAnchor = frame
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { toolbarFrame = proxy.frame(in: .named(LiveCanvasSpace.name)) }
                        .onChange(of: proxy.frame(in: .named(LiveCanvasSpace.name))) { _, frame in
                            toolbarFrame = frame
                        }
                }
            }
    }

    private var bar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            toolRow
                .fixedSize(horizontal: true, vertical: false)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .modifier(ScrollEdgeReporter(edges: $edgeFades))
        .mask(edgeFades.gradient)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.leading, 7)
        .padding(.trailing, 14)
        .frame(height: LiveDesign.controlHeight)
        .liveChromeGlass(
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
        )
        .overlay(alignment: .leading) { scrollChevron(.leading) }
        .overlay(alignment: .trailing) { scrollChevron(.trailing) }
        .allowsHitTesting(!locked)
    }

    /// OpenZCine `MonitorAssistStrip.toolRow`: groups of three, AUDIO in its own last section.
    private var toolRow: some View {
        let tools = LiveAssistTool.toolbarCases
        return HStack(spacing: 2) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                if index > 0 && index.isMultiple(of: 3) {
                    assistDivider
                }
                AssistBarButton(
                    tool: tool,
                    assist: assist,
                    isLocked: locked,
                    onPresent: presentOptions
                )
            }
            if !tools.isEmpty {
                assistDivider
            }
            AssistBarButton(
                tool: .audioMeters,
                assist: assist,
                isLocked: locked,
                onPresent: presentOptions
            )
        }
    }

    private var assistDivider: some View {
        Rectangle()
            .fill(LiveDesign.hairlineStrong)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 3)
    }

    private func scrollChevron(_ edge: HorizontalEdge) -> some View {
        (edge == .leading ? OpcIcon.chevronLeft : OpcIcon.chevronRight)
            .frame(width: 12, height: 12)
            .foregroundStyle(LiveDesign.accent)
            .shadow(color: .black.opacity(0.65), radius: 4)
            .padding(.horizontal, 5)
            .opacity((edge == .leading ? edgeFades.leading : edgeFades.trailing) ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// OpenZCine `AssistToolButtonRow` → `presentAssistOptions`.
    private func presentOptions(for tool: LiveAssistTool) {
        guard !locked, tool.hasConfiguration else { return }
        AssistBarHaptics.confirm()
        assist.longPressAnchor = iconFrames[tool] ?? toolbarFrame
        assist.configureTool = tool
        if tool == .lut { assist.showLUTPicker = false }
    }
}

struct AssistBarButton: View {
    let tool: LiveAssistTool
    @Bindable var assist: LiveAssistState
    var isLocked = false
    var onPresent: (LiveAssistTool) -> Void
    @State private var buildup: Task<Void, Never>?

    var body: some View {
        AssistToolChip(tool: tool, isOn: assist.isOn(tool), compact: true)
            .contentShape(Rectangle())
            .minTapTarget()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AssistIconFrameKey.self,
                        value: [tool: proxy.frame(in: .named(LiveCanvasSpace.name))]
                    )
                }
            }
            .onTapGesture {
                guard !isLocked else { return }
                assist.toggle(tool)
            }
            .onLongPressGesture(minimumDuration: 0.25) {
                cancelBuildup()
                onPresent(tool)
            } onPressingChanged: { pressing in
                guard tool.hasConfiguration, !isLocked else { return }
                if pressing {
                    buildup = AssistBarHaptics.buildup()
                } else {
                    cancelBuildup()
                }
            }
    }

    private func cancelBuildup() {
        buildup?.cancel()
        buildup = nil
    }
}

/// OpenZCine `AssistHaptics` — escalating long-press, then a firm confirm.
enum AssistBarHaptics {
    @MainActor static func buildup() -> Task<Void, Never> {
        Task { @MainActor in
            guard OperatorPrefs.hapticsEnabled else { return }
            let generator = UIImpactFeedbackGenerator(style: .soft)
            for intensity in [0.4, 0.65, 0.9] as [CGFloat] {
                generator.prepare()
                generator.impactOccurred(intensity: intensity)
                try? await Task.sleep(for: .seconds(0.08))
                if Task.isCancelled { return }
            }
        }
    }

    @MainActor static func confirm() {
        guard OperatorPrefs.hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1.0)
    }
}

struct ScrollEdgeFades: Equatable {
    var leading: Bool
    var trailing: Bool

    var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: leading ? .clear : .black, location: 0),
                .init(color: .black, location: leading ? 0.06 : 0),
                .init(color: .black, location: trailing ? 0.94 : 1),
                .init(color: trailing ? .clear : .black, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct ScrollEdgeReporter: ViewModifier {
    @Binding var edges: ScrollEdgeFades

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: ScrollEdgeFades.self) { geometry in
                    let remaining =
                        geometry.contentSize.width - geometry.containerSize.width
                        - geometry.contentOffset.x
                    return ScrollEdgeFades(
                        leading: geometry.contentOffset.x > 6,
                        trailing: remaining > 28
                    )
                } action: { _, fades in
                    edges = fades
                }
        } else {
            content.onAppear { edges = ScrollEdgeFades(leading: true, trailing: true) }
        }
    }
}
