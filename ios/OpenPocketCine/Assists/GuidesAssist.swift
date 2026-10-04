import MonitorUI
import SwiftUI

/// OpenZCine `AssistPanel` `.guides` body + `AspectGuideFrameView`.
///
/// Long-press options (no title-safe / action-safe - OpenZCine does not offer those):
/// - Film / Social family tabs
/// - Multi-select aspect chips for the active tab
/// - "Mask outside frame" (darkens the inverse of the union)
enum GuidesAssist {
    @MainActor
    @ViewBuilder
    static func longPressMenu(assist: LiveAssistState) -> some View {
        GuidesLongPressMenu(assist: assist)
    }

    @MainActor
    @ViewBuilder
    static func longPressMenu(_ assist: LiveAssistState) -> some View {
        GuidesLongPressMenu(assist: assist)
    }

    @MainActor
    @ViewBuilder
    static func overlay(feed: CGRect, assist: LiveAssistState, fallback: GuideAspect) -> some View {
        AspectGuideFrameView(
            selectedRatios: assist.selectedGuides.isEmpty ? [fallback] : assist.selectedGuides,
            maskEnabled: assist.guideMask,
            feed: feed
        )
    }

    /// OpenZCine `AssistConfiguration.Guides.summaryLabel`.
    static func summaryLabel(for selected: Set<GuideAspect>) -> String {
        if selected.count == 1 { return selected.first?.rawValue ?? "\u{2014}" }
        return selected.isEmpty ? "\u{2014}" : "\(selected.count) ratios"
    }

    /// Centered guide geometry comes from the common monitor UI.
    static func rectForRatio(_ feed: CGRect, _ ratio: CGFloat) -> CGRect {
        MonitorGuideGeometry.rectForRatio(feed, ratio)
    }
}

/// OpenZCine `AssistPanel` `case .guides` - family tabs, 5-column chips, mask row.
private struct GuidesLongPressMenu: View {
    @Bindable var assist: LiveAssistState

    var body: some View {
        MonitorGuidesMenu(
            family: Binding(
                get: { assist.guideFamily },
                set: {
                    assist.guideFamily = $0; assist.persist()
                }), selected: assist.selectedGuides,
            mask: Binding(
                get: { assist.guideMask },
                set: {
                    OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
                    assist.guideMask = $0; assist.persist()
                }),
            feedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            }, onToggle: { assist.toggleGuide($0) })
    }
}

/// Native guide rendering and the union mask belong to the common monitor UI.
typealias AspectGuideFrameView = MonitorAspectGuideFrames