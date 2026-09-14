import MonitorPresentation
import Testing

struct MonitorAssistPaletteRevealTests {
    @Test func tapThresholdAndFlickChooseTheSettledState() {
        #expect(!MonitorAssistPaletteReveal.shouldOpen(progress: 0.4, velocityAlongExpand: 0))
        #expect(MonitorAssistPaletteReveal.shouldOpen(progress: 0.5, velocityAlongExpand: 0))
        #expect(MonitorAssistPaletteReveal.shouldOpen(progress: 0.15, velocityAlongExpand: 300))
        #expect(!MonitorAssistPaletteReveal.shouldOpen(progress: 0.8, velocityAlongExpand: -300))
        let projected = MonitorAssistPaletteReveal.projectedProgress(
            progress: 0.2, velocityAlongExpand: 400, span: 200)
        #expect(projected > 0.5)
        #expect(
            MonitorAssistPaletteReveal.shouldOpen(
                progress: 0.2, velocityAlongExpand: 100, projectedProgress: 0.55))
    }

    @Test func extraToolsStayHiddenUntilThePlateOpens() {
        #expect(MonitorAssistPaletteReveal.extraToolOpacity(progress: 0) == 0)
        #expect(MonitorAssistPaletteReveal.extraToolOpacity(progress: 1) == 1)
        #expect(MonitorAssistPaletteReveal.compactToolCount(portrait: true) == 1)
        #expect(MonitorAssistPaletteReveal.compactToolCount(portrait: false) == 2)
    }

    @Test func grabbedEdgeStaysUnderTheFinger() {
        #expect(
            MonitorAssistPaletteReveal.visibleEdge(
                finger: 80, grabOffset: 20, compact: 90, full: 400) == 100)
        let full = 400.0
        let compact = 90.0
        let visible = 90.0
        let fingerOnChevron = (full - visible) + 12
        let grab = MonitorAssistPaletteReveal.portraitGrabOffset(
            fingerY: fingerOnChevron, visibleHeight: visible, fullHeight: full)
        #expect(grab == 12)
        let draggedUp = fingerOnChevron - 40
        let next = MonitorAssistPaletteReveal.portraitVisibleHeight(
            fingerY: draggedUp, grabOffset: grab, compact: compact, full: full)
        #expect(next == visible + 40)
        #expect(full - next == draggedUp - grab)
    }

    @Test func dragFromTheArrowScrubsThePlate() {
        #expect(
            MonitorAssistPaletteReveal.progress(
                translationAlongExpand: 50, span: 200, fromExpanded: false) == 0.25)
        #expect(
            MonitorAssistPaletteReveal.progress(
                translationAlongExpand: -50, span: 200, fromExpanded: true) == 0.75)
        #expect(
            MonitorAssistPaletteReveal.translationAlongExpand(dx: 10, dy: -40, portrait: true) == 40)
        #expect(
            MonitorAssistPaletteReveal.translationAlongExpand(dx: 10, dy: -40, portrait: false) == 10)
    }

    @Test func expandedPlateKeepsItsOrderUntilCollapse() {
        let ranked = ["LUT", "PEAK", "FALSE"]
        let pinned = ["PEAK", "FALSE", "LUT"]
        #expect(
            MonitorAssistPaletteReveal.pinnedOrder(
                ranked: ranked, pinned: pinned, frozen: true) == pinned)
        #expect(
            MonitorAssistPaletteReveal.pinnedOrder(
                ranked: ranked, pinned: pinned, frozen: false) == ranked)
        #expect(
            MonitorAssistPaletteReveal.pinnedOrder(
                ranked: ["WAVE", "PEAK"], pinned: ["PEAK", "GONE", "FALSE"], frozen: true)
                == ["PEAK", "WAVE"])
    }

    @Test func landscapeColumnsKeepTheCollapsedStackInPlace() {
        #expect(MonitorAssistPaletteReveal.landscapeCellIndex(column: 0, row: 0) == 0)
        #expect(MonitorAssistPaletteReveal.landscapeCellIndex(column: 0, row: 1) == 1)
        #expect(MonitorAssistPaletteReveal.landscapeCellIndex(column: 1, row: 0) == 2)
    }
}
