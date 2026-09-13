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
            #expect(layout.bottomCornerRadius == (height > width ? 16 : 0))
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
        #expect(layout.bottomCornerRadius == 16)
        #expect(layout.topCornerRadius == 16)
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

    @Test func compactHoldIsDialOnlyAndDetailsKeepAccessoryChrome() {
        #expect(MonitorCapturePopupKind.compact.showsClose == false)
        #expect(MonitorCapturePopupKind.compact.showsAccessoryChrome == false)
        #expect(MonitorCapturePopupKind.compact.subtitle == "drag to set")
        #expect(MonitorCapturePopupKind.details.showsClose)
        #expect(MonitorCapturePopupKind.details.showsAccessoryChrome)
        #expect(MonitorCapturePopupKind.details.subtitle == nil)
    }

    @Test func topRecordingCategoriesParkBelowThePortraitInfoBar() {
        let hud = FieldMonitorLayout(
            width: 393, height: 852, safeArea: .init(top: 59, bottom: 34))
        let layout = MonitorCapturePopupLayout(
            viewportWidth: 393, viewportHeight: 852, tablet: false,
            safeArea: .init(top: 59, bottom: 34), bottomBoundary: hud.system.y - 12,
            edge: .top, topBoundary: hud.status.maxY + 6)
        #expect(layout.edge == .top)
        #expect(layout.top == hud.status.maxY + 6)
        #expect(layout.width == 365)
        #expect(layout.centerX == 393.0 / 2)
        #expect(layout.topPadding == 12)
        #expect(layout.bottomPadding == 14)
        #expect(layout.topCornerRadius == 16)
        #expect(layout.bottomCornerRadius == 16)
        #expect(layout.bottom == hud.system.y - 12)
    }

    @Test func topRecordingCategoriesAttachToTheLandscapeScreenTop() {
        let layout = MonitorCapturePopupLayout(
            viewportWidth: 874, viewportHeight: 402, tablet: false,
            safeArea: .init(leading: 62, bottom: 21), edge: .top, topBoundary: 0)
        #expect(layout.top == 0)
        #expect(layout.width == 480)
        #expect(layout.centerX == 437)
        #expect(layout.topPadding == 16)
        #expect(layout.bottomPadding == 14)
        #expect(layout.topCornerRadius == 0)
        #expect(layout.bottomCornerRadius == 16)
        #expect(layout.bottom == 402)
    }

    @Test func compactHoldHugsHeaderAndDrumAt128() {
        #expect(MonitorCapturePopupChrome.compactHeight(topPadding: 11) == 128)
        #expect(MonitorCapturePopupChrome.compactBottomPadding(topPadding: 11) == 1)
        #expect(MonitorCapturePopupChrome.compactBottomPadding(topPadding: 16) == 0)
        #expect(MonitorCapturePopupChrome.drumHeight == 86)
        #expect(
            MonitorCapturePopupChrome.showsRecordingCategoryTabs(portrait: true, kind: .details))
        #expect(
            !MonitorCapturePopupChrome.showsRecordingCategoryTabs(portrait: false, kind: .details))
        #expect(
            !MonitorCapturePopupChrome.showsRecordingCategoryTabs(portrait: true, kind: .compact))
        #expect(MonitorCapturePopupChrome.showsGrabber(kind: .details, edge: .bottom))
        #expect(!MonitorCapturePopupChrome.showsGrabber(kind: .details, edge: .top))
        #expect(!MonitorCapturePopupChrome.showsGrabber(kind: .compact, edge: .bottom))
    }

    @Test func readoutAndSettingsChromeKeepApprovedPhoneType() {
        #expect(MonitorReadoutTypography.valueSize(tablet: false) == 16)
        #expect(MonitorReadoutTypography.valueSize(tablet: true) == 18)
        #expect(MonitorReadoutTypography.labelSize == 9)
        #expect(MonitorReadoutTypography.labelTracking == 1.26)
        #expect(MonitorSettingsCardMetrics.titleClearance() >= 8)
        #expect(
            MonitorSettingsCardMetrics.contentOriginY()
                >= MonitorSettingsCardMetrics.titleTopPadding + 17
                    + MonitorSettingsCardMetrics.titleContentGap)
        #expect(MonitorCapturePopupChrome.dispSize == 12)
        #expect(MonitorCapturePopupChrome.dispTracking == 0.48)
        #expect(MonitorCapturePopupChrome.cameraPhoneTitle == 19)
        #expect(MonitorCapturePopupChrome.cameraTabletTitle == 24)
        #expect(MonitorCapturePopupChrome.cameraCardCorner == 13)
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
