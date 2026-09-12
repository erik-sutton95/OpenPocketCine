import MonitorPresentation
import Testing

struct MonitorAssistPaletteLayoutTests {
    @Test func portraitExpansionKeepsVisibleToolsInsideItsActualHitRectangle() {
        let bottom = 648.0
        let layout = MonitorAssistPaletteLayout(
            portrait: true, tablet: false, expanded: true, toolCount: 15,
            maximumWidth: 276, maximumHeight: 874 * 0.62)
        let frame = layout.anchored(leading: 14, bottom: bottom)
        #expect(frame.maxY == bottom)
        #expect(frame.y >= 62)
        #expect(frame.width == 52)
        #expect(layout.scrollHeight + 35 == frame.height)
        // PEAK is the second row; its centre is hundreds of points above the
        // collapsed rail but must still be inside the expanded native view.
        let peakY = frame.y + 4 + 24 + 3 + 47 + 22
        #expect(peakY > frame.y && peakY < frame.maxY)
        #expect(layout.scrollHeight < 15 * 47, "Excess tools belong to the scroller")
    }

    @Test func landscapeExpansionKeepsTwoRowsAndScrollsNarrowScreens() {
        let layout = MonitorAssistPaletteLayout(
            portrait: false, tablet: false, expanded: true, toolCount: 15,
            maximumWidth: 530, maximumHeight: 300)
        #expect(layout.height == 99)
        #expect(layout.width == 530)
        #expect(layout.columns == 8)
        #expect(layout.scrollHeight == 91)
        #expect(layout.scrollWidth + 26 == layout.width)
        #expect(Double(layout.columns) * (layout.cellWidth + 3) - 3 > layout.scrollWidth)
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
                    if portrait { #expect(frame.maxY < geometry.values.y) }
                }
            }
        }
    }
}
