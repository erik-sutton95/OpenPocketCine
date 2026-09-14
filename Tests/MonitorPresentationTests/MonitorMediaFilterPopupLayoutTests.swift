import MonitorPresentation
import Testing

struct MonitorMediaFilterPopupLayoutTests {
    @Test func landscapeCardClearsTrailingIslandAndHomeIndicator() {
        let card = MonitorMediaFilterPopupLayout.card(
            viewportWidth: 956, viewportHeight: 440,
            safeTop: 0, safeLeading: 59, safeBottom: 21, safeTrailing: 59)
        #expect(card.maxY <= 440 - 21)
        #expect(card.maxX <= 956 - 59)
        #expect(card.y >= 10 + MonitorMediaFilterPopupLayout.belowPageTop)
        #expect(card.height < MonitorMediaFilterPopupLayout.preferredHeight)
        #expect(card.width == 320)
    }

    @Test func landscapeCardClearsTheIslandWhenThePageZerosTheCleanEdge() {
        let card = MonitorMediaFilterPopupLayout.card(
            viewportWidth: 956, viewportHeight: 440,
            safeTop: 0, safeLeading: 59, safeBottom: 21, safeTrailing: 0)
        #expect(card.maxX <= 956 - 59)
        #expect(card.maxY <= 440 - 21)
        #expect(card.height < MonitorMediaFilterPopupLayout.preferredHeight)
    }

    @Test func compactLandscapeCardFitsAboveTheHomeIndicator() {
        let card = MonitorMediaFilterPopupLayout.card(
            viewportWidth: 852, viewportHeight: 393,
            safeTop: 0, safeLeading: 59, safeBottom: 21, safeTrailing: 0)
        #expect(card.maxX <= 852 - 59)
        #expect(card.maxY <= 393 - 21)
        #expect(card.height <= 393 - 66 - 21)
        #expect(card.height < MonitorMediaFilterPopupLayout.preferredHeight)
    }

    @Test func portraitCardClearsTheIsland() {
        let card = MonitorMediaFilterPopupLayout.card(
            viewportWidth: 440, viewportHeight: 956,
            safeTop: 59, safeLeading: 0, safeBottom: 34, safeTrailing: 0)
        #expect(card.y >= 59 + 10 + MonitorMediaFilterPopupLayout.belowPageTop)
        #expect(card.maxY <= 956 - 34)
        #expect(card.height == MonitorMediaFilterPopupLayout.preferredHeight)
    }
}
