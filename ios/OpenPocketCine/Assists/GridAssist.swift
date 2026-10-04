import MonitorUI
import SwiftUI

/// OpenZCine framing grid - `AssistConfiguration.Grid`, `FeedGridView`, and `AssistPanel` `.grid`.
///
/// Long-press options are **Thirds**, **Phi Grid**, and **Diagonal**. OpenZCine has no fourths
/// (or any other) composition grid.
enum GridAssist {
    typealias Option = MonitorGridOption

    /// OpenZCine `FeedGridView` thirds lines (`1/3`, `2/3`).
    static let thirdsFractions: [CGFloat] = [1.0 / 3, 2.0 / 3]
    /// OpenZCine phi lines (`0.382`, `0.618` - 1 − 1/φ and 1/φ, as shipped).
    static let phiFractions: [CGFloat] = [0.382, 0.618]
    /// Prototype stroke `rgba(255,255,255,.22)`, 1px.
    static let strokeOpacity: Double = 0.22
    static let strokeWidth: CGFloat = 1

    /// OpenZCine `AssistPanel` grid body - three `GridToggle` / `GlassChoice` chips.
    static func longPressMenu(assist: LiveAssistState) -> some View {
        GridLongPressMenu(assist: assist)
    }

    /// OpenZCine `FeedGridView` overlay on the de-squeezed feed rect.
    static func overlay(feed: CGRect, thirds: Bool, phi: Bool, diagonal: Bool) -> some View {
        GridOverlay(feed: feed, thirds: thirds, phi: phi, diagonal: diagonal)
    }

    static func segments(in feed: CGRect, thirds: Bool, phi: Bool, diagonal: Bool) -> [GridSegment]
    {
        MonitorGridGeometry.segments(in: feed, thirds: thirds, phi: phi, diagonal: diagonal)
    }
}

typealias GridSegment = MonitorGridSegment

private struct GridLongPressMenu: View {
    @Bindable var assist: LiveAssistState

    var body: some View {
        MonitorGridMenu(
            selected: Set(GridAssist.Option.allCases.filter(isOn)),
            feedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            }
        ) { option in
            OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            toggle(option)
        }
    }

    private func isOn(_ option: GridAssist.Option) -> Bool {
        switch option {
        case .thirds: assist.gridThirds
        case .phi: assist.gridPhi
        case .diagonal: assist.gridDiagonal
        }
    }

    private func toggle(_ option: GridAssist.Option) {
        switch option {
        case .thirds: assist.gridThirds.toggle()
        case .phi: assist.gridPhi.toggle()
        case .diagonal: assist.gridDiagonal.toggle()
        }
        assist.persist()
    }

}

private typealias GridOverlay = MonitorFeedGrid