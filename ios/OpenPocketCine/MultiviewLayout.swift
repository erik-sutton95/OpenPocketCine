import CoreGraphics
import MonitorPresentation

/// Persisted native selection; all stage geometry belongs to the shared presentation
/// package. Fit/Fill changes the picture inside each tile, never decoder identity.
enum MultiviewLayout: String, CaseIterable {
    case grid = "2 × 2 grid"
    case centerStage = "Center stage"

    func presentation(
        in size: CGSize, safeArea: MonitorSafeArea = .init(), selected: Int,
        topControlInset: CGFloat = 0
    )
        -> MultiviewPresentationLayout
    {
        MultiviewPresentationLayout(
            width: size.width, height: size.height, safeArea: safeArea,
            arrangement: self == .grid ? .grid : .centerStage, selected: selected,
            topControlInset: topControlInset)
    }
}
