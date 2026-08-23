import Testing

@testable import OpenPocketViewCore

@Suite struct MonitorPortraitLayoutTests {
    private let sa = MonitorEdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    @Test func fitAspectStacksTopBarFeedControlsSystemBar() {
        let z = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fit16x9, scopeCount: 1)
        #expect(z.topBar.y == 51 && z.topBar.height == 44)
        #expect(abs(z.feed.height - 390 * 9 / 16) < 0.5)
        #expect(z.feed.y > z.topBar.maxY)
        #expect(z.scopes.height == 0)
        #expect(z.controls.y == z.feed.y + z.feed.height)
        #expect(z.systemBar.maxY <= 844 - (34 - 14))
        #expect(z.systemBar.maxY < 844)
        #expect(z.controls.maxY <= z.systemBar.y)
    }

    @Test func liveFitSixteenNineCentersOnTheScreen() {
        let z = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fit16x9, scopeCount: 0)
        #expect(abs(z.feed.height - 390 * 9 / 16) < 0.5)
        #expect(
            abs((z.feed.y + z.feed.height / 2) - 422) < 0.5,
            "16:9 well sits on the screen mid-line")
        #expect(z.feed.y > z.topBar.maxY)
        #expect(z.feed.y + z.feed.height < z.systemBar.y)
    }

    @Test func sixteenNineAspectToggleSitsUnderTheWellAboveTheRail() {
        let z = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fit16x9, scopeCount: 1, assistToolbarHeight: 58)
        let floor = z.assistToolbar.height > 1 ? z.assistToolbar.y : z.systemBar.y
        let toggle = MonitorPortraitLayout.aspectToggle(feed: z.feed, floorY: floor)
        #expect(abs(toggle.midX - (z.feed.x + z.feed.width / 2)) < 0.05)
        #expect(
            abs(toggle.maxY - (floor - MonitorPortraitLayout.aspectToggleGap)) < 0.05,
            "fit/fill sits on the assist / scope band, not under the well")
        #expect(toggle.y >= z.feed.y + z.feed.height)

        let fill = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fill, scopeCount: 0)
        let fillFloor = fill.controls.height > 1 ? fill.controls.y : fill.systemBar.y
        let fillToggle = MonitorPortraitLayout.aspectToggle(feed: fill.feed, floorY: fillFloor)
        #expect(fillToggle.maxY <= fillFloor + 0.05)
        #expect(fillToggle.maxY <= fill.systemBar.y + 0.05)
        #expect(abs(fillToggle.midX - (fill.feed.x + fill.feed.width / 2)) < 0.05)
    }

    @Test func systemBarHeightIsHundredForRecordButtonClearance() {
        #expect(MonitorPortraitLayout.systemBarHeight == 100)
    }

    @Test func fitLiveAssistToolbarSitsOnTheSystemRail() {
        let withToolbar = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fit16x9, scopeCount: 1, assistToolbarHeight: 58)
        #expect(abs(withToolbar.assistToolbar.maxY - withToolbar.systemBar.y) < 0.5)
        #expect(withToolbar.assistToolbar.height == 58)
        #expect(withToolbar.scopes.height == 0)
        #expect(withToolbar.controls.y == withToolbar.feed.y + withToolbar.feed.height)

        let withoutToolbar = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fit16x9, scopeCount: 1)
        #expect(withoutToolbar.assistToolbar.height == 0)
        #expect(withoutToolbar.scopes.height == 0)
    }

    @Test func assistToolbarIsZeroHeightInCleanAndCommand() {
        for mode in [MonitorPortraitDispMode.clean, .command] {
            let z = MonitorPortraitLayout.zones(
                viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: mode,
                aspect: .fit16x9, scopeCount: 1, assistToolbarHeight: 58)
            #expect(z.assistToolbar.height == 0)
        }
    }

    @Test func assistToolbarIsZeroHeightInFillRegardlessOfMode() {
        for mode in MonitorPortraitDispMode.allCases {
            let z = MonitorPortraitLayout.zones(
                viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: mode,
                aspect: .fill, scopeCount: 1, assistToolbarHeight: 58)
            #expect(z.assistToolbar.height == 0)
        }
    }

    @Test func scopeCountDoesNotReserveABand() {
        let none = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fit16x9, scopeCount: 0)
        let many = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fit16x9, scopeCount: 5)
        #expect(none.scopes.height == 0)
        #expect(many.scopes.height == 0)
        #expect(abs(none.feed.y - many.feed.y) < 0.05)
        #expect(abs(none.feed.height - many.feed.height) < 0.05)
    }

    @Test func fillAspectFeedIsEdgeToEdgeSpanningToSystemBar() {
        let z = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fill, scopeCount: 1)
        #expect(z.feed.y == z.topBar.maxY)
        #expect(z.feed.x == 0)
        #expect(z.feed.width == 390)
        #expect(abs((z.feed.y + z.feed.height) - z.systemBar.y) < 0.5)
        #expect(z.scopes.height == 0)
        #expect(z.controls.height == 64)
    }

    @Test func cleanCollapsesScopesAndControlsInBothAspects() {
        for aspect in [PortraitFeedAspect.fit16x9, .fill] {
            let z = MonitorPortraitLayout.zones(
                viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .clean,
                aspect: aspect, scopeCount: 2)
            #expect(z.scopes.height == 0 && z.controls.height == 0)
        }
    }

    @Test func verticalFillPillarsNineSixteenInTheFillFrame() {
        let z = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fill, scopeCount: 0, feedAspectRatio: 9.0 / 16.0)
        #expect(z.feed.y == z.topBar.maxY)
        #expect(z.feed.width == 390)
        #expect(z.controls.height == 64)
        #expect(abs((z.feed.y + z.feed.height) - z.systemBar.y) < 0.5)
    }

    @Test func verticalAspectClampsLiveFitFeedAboveTheBands() {
        let z = MonitorPortraitLayout.zones(
            viewportWidth: 390, viewportHeight: 844, safeArea: sa, mode: .live,
            aspect: .fit16x9, scopeCount: 1, assistToolbarHeight: 58,
            feedAspectRatio: 9.0 / 16.0)
        #expect(abs(z.feed.height - 571) < 0.5)
        #expect(z.feed.y == z.topBar.maxY)
        #expect(z.scopes.height == 0)
        #expect(abs(z.assistToolbar.maxY - z.systemBar.y) < 0.5)
    }

    @Test func stickSitsOnTheFeedBottomCentreWithZoomOnItsTrailingSide() {
        let feed = MonitorLayoutRegion(x: 0, y: 100, width: 390, height: 500)
        let stick = MonitorPortraitLayout.feedGimbalStick(
            feed: feed, size: 88, bottomClearance: 74)
        #expect(abs(stick.midX - feed.midX) < 0.05)
        #expect(abs(stick.maxY - (feed.maxY - 74)) < 0.05)
        #expect(stick.width == 88 && stick.height == 88)

        let zoom = MonitorPortraitLayout.feedZoomChip(
            feed: feed, beside: stick, size: 44, gap: 8, trailingInset: 10)
        #expect(abs(zoom.x - (stick.maxX + 8)) < 0.05)
        #expect(abs(zoom.midY - stick.midY) < 0.05)
        #expect(zoom.maxX <= feed.maxX - 10 + 0.05)
    }

    @Test func sixteenNineStickSitsInTheTrailingCornerWithZoomAbove() {
        let feed = MonitorLayoutRegion(x: 0, y: 200, width: 390, height: 220)
        let stick = MonitorPortraitLayout.feedGimbalStickTrailing(
            feed: feed, size: 88, bottomClearance: 16, trailingInset: 16)
        #expect(abs(stick.maxX - (feed.maxX - 16)) < 0.05)
        #expect(abs(stick.maxY - (feed.maxY - 16)) < 0.05)

        let zoom = MonitorPortraitLayout.feedZoomChipAbove(
            feed: feed, stick: stick, size: 44, gap: 8)
        #expect(abs(zoom.maxX - stick.maxX) < 0.05)
        #expect(abs(zoom.maxY - (stick.y - 8)) < 0.05)
        #expect(zoom.y >= feed.y)
    }

    @Test func sixteenNineFitParksStickAndZoomOutsideTheWell() {
        let feed = MonitorFeedFrame(x: 0, y: 200, width: 390, height: 220)
        let cluster = MonitorPortraitLayout.outsideTrailingCorner(feed: feed, floorY: 620)
        #expect(
            cluster.zoom.y >= feed.y + feed.height + MonitorPortraitLayout.outsideControlsGap - 0.05
        )
        #expect(cluster.stick.y >= cluster.zoom.maxY)
        #expect(abs(cluster.stick.maxX - (feed.x + feed.width - 16)) < 0.05)
        #expect(abs(cluster.zoom.maxX - cluster.stick.maxX) < 0.05)
        #expect(abs(cluster.stick.maxY - (620 - 16)) < 0.05, "stick parks on the toolbar band")
    }

    @Test func theExpandedRailEndsAboveTheCaptureStrip() {
        let feed = MonitorLayoutRegion(x: 0, y: 100, width: 390, height: 500)
        let rail = MonitorPortraitLayout.fillAssistRail(
            feed: feed, captureStripTop: 540, expanded: true)
        #expect(rail.x == 10)
        #expect(rail.y == 110)
        #expect(rail.width == MonitorPortraitLayout.assistRailExpandedWidth)
        #expect(rail.height == 420)
    }

    @Test func landscapeRightOrientationMirrors() {
        let islandLeading = MonitorEdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0)
        let islandTrailing = MonitorEdgeInsets(top: 0, leading: 0, bottom: 21, trailing: 59)
        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .landscapeRight, safeArea: islandLeading)
                == .mirrored)
        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .landscapeLeft, safeArea: islandTrailing)
                == .standard)
        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .unknown, safeArea: islandTrailing)
                == .mirrored)
    }

    @Test func feedMirrorFlipsAroundViewportCenter() {
        let feed = MonitorFeedFrame(x: 59, y: 0, width: 693.3, height: 390)
        let flipped = feed.mirroredHorizontally(in: 844)
        #expect(abs(flipped.x - (844 - 59 - 693.3)) < 0.05)
        #expect(flipped.width == feed.width)
    }
}
