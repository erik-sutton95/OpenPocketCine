import MonitorPresentation
import Testing

struct MonitorCapturePopupLayoutTests {
    @Test func bottomDrawerStaysCenteredAcrossPhoneTabletAndCutoutOrientations() {
        for (width, height, tablet, safe) in [
            (667.0, 375.0, false, MonitorSafeArea()),
            (874, 402, false, MonitorSafeArea(leading: 62, bottom: 21)),
            (874, 402, false, MonitorSafeArea(bottom: 21, trailing: 62)),
            (744, 1133, true, MonitorSafeArea(top: 24, bottom: 20)),
            (1133, 744, true, MonitorSafeArea(top: 24, bottom: 20)),
        ] {
            let layout = MonitorCapturePopupLayout(
                viewportWidth: width, viewportHeight: height, tablet: tablet, safeArea: safe)
            #expect(layout.centerX == width / 2)
            #expect(layout.width == (tablet ? 620 : 480))
            #expect(layout.bottom == height)
            #expect(layout.maximumHeight <= height - safe.top)
        }
    }

    @Test func portraitDrawerClearsSystemRailWithoutUsingTheTappedReadoutAsAnAnchor() {
        let layout = MonitorCapturePopupLayout(
            viewportWidth: 393, viewportHeight: 852, tablet: false,
            safeArea: .init(top: 59, bottom: 34), bottomBoundary: 733)
        #expect(layout.width == 365)
        #expect(layout.centerX - layout.width / 2 == 14)
        #expect(layout.bottom == 733)
        #expect(layout.maximumHeight == 666)
        #expect(layout.bottomPadding == 40)
    }

    @Test func smallWindowsClampWidthAndScrollHeightInsidePhysicalBoundaries() {
        let layout = MonitorCapturePopupLayout(
            viewportWidth: 240, viewportHeight: 210, tablet: true,
            safeArea: .init(top: 24, leading: 22, bottom: 12, trailing: 4),
            bottomBoundary: 170, ceiling: 68)
        #expect(layout.centerX - layout.width / 2 >= 30)
        #expect(layout.centerX + layout.width / 2 <= 226)
        #expect(layout.maximumHeight == 102)
        let invalid = MonitorCapturePopupLayout(
            viewportWidth: .nan, viewportHeight: -.infinity, tablet: false,
            bottomBoundary: .infinity)
        #expect(invalid.width == 0)
        #expect(invalid.maximumHeight == 0)
    }

    @Test func wideLabelsHaveRoomForTheirEnlargedSelectedValue() {
        let numeric = MonitorDrumMetrics(options: ["100", "1600", "6400"])
        #expect(numeric.cellWidth == 108)
        #expect(numeric.selectedScale == 1.95)
        let focus = MonitorDrumMetrics(options: ["AF-S", "AF-C", "Showcase", "Lock", "Priority"])
        #expect(focus.cellWidth == 142)
        #expect(focus.selectedScale == 1.6)
        let words = MonitorDrumMetrics(options: ["Registered priority"])
        #expect(words.cellWidth > focus.cellWidth)
        #expect(words.selectedScale == 1.4)
        // Presentation must never alter the established command gesture's
        // physical distance: every choice still occupies 56 points of travel.
        #expect(MonitorDrumSelection.changedIndex(origin: 0, translation: -56, count: 5) == 1)
    }
}
