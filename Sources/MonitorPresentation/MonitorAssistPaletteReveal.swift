import Foundation

/// Interactive View Assist plate: tap the arrow, or press and drag it so the
/// expanding edge stays under the finger. A flick coasts to open or close.
/// 0 is collapsed, 1 is the full catalog.
public enum MonitorAssistPaletteReveal: Sendable {
    public static let snap = 0.5
    public static let slop = 8.0
    /// Flick along the expand axis, in points per second.
    public static let flick = 280.0
    /// Ballistic coast used to project a flick, in seconds.
    public static let coast = 0.22

    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return a + (b - a) * clamped
    }

    /// Portrait expands upward (−Y); landscape expands to the trailing edge (+X).
    public static func translationAlongExpand(dx: Double, dy: Double, portrait: Bool) -> Double {
        portrait ? -dy : dx
    }

    public static func progress(visible: Double, compact: Double, full: Double) -> Double {
        let span = full - compact
        guard span > 1 else { return full >= compact ? 1 : 0 }
        return min(1, max(0, (visible - compact) / span))
    }

    public static func progress(
        translationAlongExpand: Double, span: Double, fromExpanded: Bool
    ) -> Double {
        guard span > 1 else { return fromExpanded ? 1 : 0 }
        let origin = fromExpanded ? span : 0
        return min(1, max(0, (origin + translationAlongExpand) / span))
    }

    /// Keep the grabbed point on the expanding edge under the finger.
    /// Landscape: trailing edge in a leading-origin space (`finger + grabOffset`).
    public static func visibleEdge(finger: Double, grabOffset: Double, compact: Double, full: Double)
        -> Double
    {
        min(full, max(compact, finger + grabOffset))
    }

    /// Portrait expanding edge is the top, at `full - visible` in a top-origin space.
    public static func portraitGrabOffset(
        fingerY: Double, visibleHeight: Double, fullHeight: Double
    ) -> Double {
        fingerY - (fullHeight - visibleHeight)
    }

    public static func portraitVisibleHeight(
        fingerY: Double, grabOffset: Double, compact: Double, full: Double
    ) -> Double {
        min(full, max(compact, full - (fingerY - grabOffset)))
    }

    public static func projectedProgress(
        progress: Double, velocityAlongExpand: Double, span: Double
    ) -> Double {
        guard span > 1 else { return progress }
        return min(1, max(0, progress + velocityAlongExpand * coast / span))
    }

    public static func shouldOpen(
        progress: Double, velocityAlongExpand: Double, projectedProgress: Double? = nil
    ) -> Bool {
        if abs(velocityAlongExpand) >= flick { return velocityAlongExpand > 0 }
        return (projectedProgress ?? progress) >= snap
    }

    /// Tools beyond the collapsed favorites fade their glyphs only.
    public static func extraToolOpacity(progress: Double) -> Double {
        min(1, max(0, (progress - 0.08) / 0.42))
    }

    public static func landscapeCellIndex(column: Int, row: Int) -> Int {
        column * 2 + row
    }

    public static func compactToolCount(portrait: Bool) -> Int {
        portrait ? 1 : 2
    }

    /// Keep the open plate still. Ranking updates apply only after collapse.
    public static func pinnedOrder(ranked: [String], pinned: [String], frozen: Bool) -> [String] {
        guard frozen, !pinned.isEmpty else { return ranked }
        var seen: Set<String> = []
        let kept = pinned.filter { ranked.contains($0) && seen.insert($0).inserted }
        let extras = ranked.filter { seen.insert($0).inserted }
        return kept + extras
    }
}
