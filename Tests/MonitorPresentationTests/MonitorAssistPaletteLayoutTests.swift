import MonitorPresentation
import Testing

struct MonitorAssistPaletteLayoutTests {
    @Test func portraitCollapsedPlateFitsTheChevronAndOneFavorite() {
        let compact = MonitorAssistPaletteLayout(
            portrait: true, tablet: false, expanded: false, toolCount: 15,
            maximumWidth: 80, maximumHeight: 800)
        #expect(MonitorAssistPaletteReveal.compactToolCount(portrait: true) == 1)
        #expect(MonitorAssistPaletteReveal.compactToolCount(portrait: false) == 2)
        #expect(compact.height == compact.cellHeight + 35)
        #expect(compact.width == compact.cellHeight + 8)
        let full = compact.resolving(expanded: true)
        #expect(full.height > compact.height)
        #expect(full.width == compact.width)
    }

    @Test func portraitExpansionKeepsVisibleToolsInsideItsActualHitRectangle() {
        let bottom = 648.0
        let layout = MonitorAssistPaletteLayout(
            portrait: true, tablet: false, expanded: true, toolCount: 15,
            maximumWidth: 276, maximumHeight: 874 * 0.62)
        let frame = layout.anchored(leading: 14, bottom: bottom)
        #expect(frame.maxY == bottom)
        #expect(frame.y >= 62)
        #expect(frame.width == 56)
        #expect(layout.cellWidth == layout.cellHeight)
        #expect(layout.cellWidth == MonitorSystemButtonMetrics.side(tablet: false))
        #expect(layout.scrollHeight + 35 == frame.height)
        // PEAK is the second row; its centre is hundreds of points above the
        // collapsed rail but must still be inside the expanded native view.
        let peakY = frame.y + 4 + 24 + 3 + layout.cellHeight + 3 + layout.cellHeight / 2
        #expect(peakY > frame.y && peakY < frame.maxY)
        #expect(
            layout.scrollHeight < 15 * (layout.cellHeight + 3),
            "Excess tools belong to the scroller")
    }

    /// Only the portrait catalog overflows on a phone, so only there can an
    /// offset scrolled while open strand the favorite when the plate collapses.
    /// The collapsed viewport is exactly one cell under the 24 pt chevron.
    @Test func portraitCatalogScrollsPastTheOneCellCollapsedViewport() {
        let full = MonitorAssistPaletteLayout(
            portrait: true, tablet: false, expanded: true, toolCount: 15,
            maximumWidth: 276, maximumHeight: 874 * 0.62)
        let compact = full.resolving(expanded: false)
        let catalog =
            15 * full.cellHeight + 14 * MonitorAssistPaletteLayout.spacing
        #expect(catalog > full.scrollHeight)
        #expect(compact.scrollHeight == compact.cellHeight)
        #expect(
            compact.height - 2 * MonitorAssistPaletteLayout.padding - 24 - 3 == compact.cellHeight)
        let landscape = MonitorAssistPaletteLayout(
            portrait: false, tablet: false, expanded: true, toolCount: 15,
            maximumWidth: 700, maximumHeight: 300)
        let columns = Double(landscape.columns)
        #expect(
            columns * landscape.cellWidth + (columns - 1) * MonitorAssistPaletteLayout.spacing
                <= landscape.scrollWidth)
    }

    @Test func landscapeExpansionKeepsTwoRowsAndScrollsNarrowScreens() {
        let layout = MonitorAssistPaletteLayout(
            portrait: false, tablet: false, expanded: true, toolCount: 15,
            maximumWidth: 530, maximumHeight: 300)
        #expect(layout.height == 107)
        #expect(layout.cellWidth == MonitorSystemButtonMetrics.side(tablet: false))
        #expect(layout.cellWidth == layout.cellHeight)
        #expect(layout.columns == 8)
        #expect(layout.scrollHeight == 99)
        #expect(layout.scrollWidth + MonitorAssistPaletteLayout.horizontalInsets == layout.width)
        #expect(layout.width <= 530)
        #expect(layout.iconSide == MonitorSystemButtonMetrics.iconSide(tablet: false))
        let needed = Double(layout.columns) * (layout.cellWidth + 3) - 3
        #expect(needed <= layout.scrollWidth + 0.5 || layout.width == 530)
        #expect(layout.anchored(leading: 18, bottom: 361).maxY == 361)
    }

    @Test func everySupportedCanvasBoundsTheExpandedPaletteAboveItsAnchor() {
        for dimensions in [(375.0, 667.0), (402, 874), (834, 1194), (1024, 1366)] {
            for portrait in [false, true] {
                let width = portrait ? dimensions.0 : dimensions.1
                let height = portrait ? dimensions.1 : dimensions.0
                let tablet = min(width, height) >= 600
                let geometry = FieldMonitorLayout(
                    width: width, height: height,
                    safeArea: .init(top: portrait ? 59 : 0, bottom: 34))
                let maximumWidth =
                    portrait
                    ? width - (tablet ? 140 : 126) : geometry.values.maxX - geometry.assists.x
                let maximumHeight = min(height * (portrait ? 0.62 : 1), geometry.assists.maxY - 59)
                for expanded in [false, true] {
                    let layout = MonitorAssistPaletteLayout(
                        portrait: portrait, tablet: tablet, expanded: expanded, toolCount: 15,
                        maximumWidth: maximumWidth, maximumHeight: maximumHeight)
                    let frame = layout.anchored(
                        leading: geometry.assists.x, bottom: geometry.assists.maxY)
                    #expect(frame.x >= 0 && frame.maxX <= width)
                    #expect(frame.y >= 59 && frame.maxY <= height)
                    #expect(frame.maxY == geometry.assists.maxY)
                    #expect(layout.cellHeight == geometry.settings.height)
                    #expect(layout.cellWidth == geometry.settings.width)
                    #expect(
                        layout.iconSide
                            == MonitorSystemButtonMetrics.iconSide(tablet: tablet))
                    if !expanded {
                        #expect(frame == geometry.assists)
                        if !portrait { #expect(frame.maxX < geometry.values.x) }
                    }
                    if portrait { #expect(frame.maxY < geometry.values.y) }
                }
            }
        }
    }

    @Test func playbackUsesTheLiveFieldMonitorAssistAnchor() {
        for (width, height, safe) in [
            (393.0, 852.0, MonitorSafeArea(top: 59, bottom: 34)),
            (852.0, 393.0, MonitorSafeArea(bottom: 21, trailing: 59)),
        ] {
            let geometry = FieldMonitorLayout(width: width, height: height, safeArea: safe)
            let (expanded, frame) = MonitorAssistPaletteLayout.fieldMonitor(
                geometry, toolCount: 15, safeTop: safe.top)
            let compact = expanded.resolving(expanded: false).anchored(
                leading: geometry.assists.x, bottom: geometry.assists.maxY)
            #expect(compact == geometry.assists)
            #expect(frame.maxY == geometry.assists.maxY)
            #expect(frame.x == geometry.assists.x)
        }
    }
}
