import MonitorUI
import SwiftUI

/// OpenZCine framing grid — `AssistConfiguration.Grid`, `FeedGridView`, and `AssistPanel` `.grid`.
///
/// Long-press options are **Thirds**, **Phi Grid**, and **Diagonal**. OpenZCine has no fourths
/// (or any other) composition grid.
enum GridAssist {
    enum Option: String, CaseIterable, Identifiable {
        case thirds = "Thirds"
        case phi = "Phi Grid"
        case diagonal = "Diagonal"

        var id: String { rawValue }
    }

    /// OpenZCine `FeedGridView` thirds lines (`1/3`, `2/3`).
    static let thirdsFractions: [CGFloat] = [1.0 / 3, 2.0 / 3]
    /// OpenZCine phi lines (`0.382`, `0.618` — 1 − 1/φ and 1/φ, as shipped).
    static let phiFractions: [CGFloat] = [0.382, 0.618]
    /// Prototype stroke `rgba(255,255,255,.22)`, 1px.
    static let strokeOpacity: Double = 0.22
    static let strokeWidth: CGFloat = 1

    /// OpenZCine `AssistPanel` grid body — three `GridToggle` / `GlassChoice` chips.
    static func longPressMenu(assist: LiveAssistState) -> some View {
        GridLongPressMenu(assist: assist)
    }

    /// OpenZCine `FeedGridView` overlay on the de-squeezed feed rect.
    static func overlay(feed: CGRect, thirds: Bool, phi: Bool, diagonal: Bool) -> some View {
        GridOverlay(feed: feed, thirds: thirds, phi: phi, diagonal: diagonal)
    }

    static func segments(
        in feed: CGRect,
        thirds: Bool,
        phi: Bool,
        diagonal: Bool
    ) -> [GridSegment] {
        var lines: [GridSegment] = []
        if thirds { appendFractions(feed, thirdsFractions, to: &lines) }
        if phi { appendFractions(feed, phiFractions, to: &lines) }
        if diagonal {
            lines.append(
                GridSegment(
                    from: CGPoint(x: feed.minX, y: feed.minY),
                    to: CGPoint(x: feed.maxX, y: feed.maxY)
                )
            )
            lines.append(
                GridSegment(
                    from: CGPoint(x: feed.maxX, y: feed.minY),
                    to: CGPoint(x: feed.minX, y: feed.maxY)
                )
            )
        }
        return lines
    }

    private static func appendFractions(
        _ feed: CGRect,
        _ fractions: [CGFloat],
        to lines: inout [GridSegment]
    ) {
        for fraction in fractions {
            let x = feed.minX + feed.width * fraction
            let y = feed.minY + feed.height * fraction
            lines.append(
                GridSegment(
                    from: CGPoint(x: x, y: feed.minY),
                    to: CGPoint(x: x, y: feed.maxY)
                )
            )
            lines.append(
                GridSegment(
                    from: CGPoint(x: feed.minX, y: y),
                    to: CGPoint(x: feed.maxX, y: y)
                )
            )
        }
    }
}

struct GridSegment: Equatable, Sendable {
    var from: CGPoint
    var to: CGPoint
}

private struct GridLongPressMenu: View {
    @Bindable var assist: LiveAssistState

    var body: some View {
        VStack(spacing: 0) {
            MonitorSnapshotRows(GridAssist.Option.allCases) { option in
                SettingsSwitchInlineRow(
                    title: option.rawValue, showTopDivider: option != .thirds,
                    isOn: isOn(option)
                ) {
                    OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
                    toggle(option)
                }
            }
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

private struct GridOverlay: View {
    let feed: CGRect
    var thirds: Bool
    var phi: Bool
    var diagonal: Bool

    var body: some View {
        Path { path in
            for segment in GridAssist.segments(
                in: feed, thirds: thirds, phi: phi, diagonal: diagonal
            ) {
                path.move(to: segment.from)
                path.addLine(to: segment.to)
            }
        }
        .stroke(Color.white.opacity(GridAssist.strokeOpacity), lineWidth: GridAssist.strokeWidth)
    }
}
