import Foundation

/// Portrait DISP math. Command exists so tests stay 1:1; the app only uses live/clean.
public enum MonitorPortraitDispMode: String, Equatable, Sendable, CaseIterable {
    case live
    case clean
    case command
}

/// Which aspect the portrait feed renders at (operator pinch, persisted).
public enum PortraitFeedAspect: String, Codable, Equatable, Sendable {
    /// Full-width strip; whole image visible (16:9 letterboxed within the portrait width).
    case fit16x9
    /// Fills topBar→systemBar; center-crop zoom.
    case fill
}

/// Zone frames for the portrait monitor layout.
public struct MonitorPortraitZones: Equatable, Sendable {
    public let topBar: MonitorLayoutRegion
    public let feed: MonitorFeedFrame
    public let scopes: MonitorLayoutRegion
    public let assistToolbar: MonitorLayoutRegion
    public let controls: MonitorLayoutRegion
    public let systemBar: MonitorLayoutRegion
}

/// Zone geometry policy for the portrait monitor layout.
public enum MonitorPortraitLayout {
    public static let topBarHeight = 44.0
    public static let topBarLift = 8.0
    public static let systemBarHeight = 100.0
    public static let systemBarBottomLift = 14.0
    public static let scopeUnitHeight = 96.0
    public static let captureBarHeight = 64.0
    public static let assistToolbarHeight = 58.0
    public static let assistRailExpandedWidth = 60.0
    public static let assistRailCollapsedSize = 44.0
    public static let assistRailEdgeInset = 10.0
    /// Fit/fill key under a landscape 16:9 well. Shares the below-feed
    /// band with the outside stick + zoom cluster.
    public static let aspectToggleSize = 40.0
    public static let aspectToggleGap = 8.0
    public static var aspectToggleSlot: Double { aspectToggleGap + aspectToggleSize }
    /// Match `LiveChromeMetrics` gimbal / zoom so the reserved band fits both.
    public static let outsideStickSize = 88.0
    public static let outsideZoomSize = 44.0
    public static let outsideControlsGap = 8.0
    public static let outsideControlsInset = 16.0
    public static var outsideControlsSlot: Double {
        outsideControlsGap + outsideZoomSize + outsideControlsGap + outsideStickSize
            + outsideControlsInset
    }
    public static var fitBelowFeedSlot: Double { max(aspectToggleSlot, outsideControlsSlot) }

    /// 16:9 live well sits on the screen mid-line, then clamps so it stays
    /// under the top bar and above the parked stick / zoom / fit-fill band.
    public static func liveFitFeedOriginY(
        viewportHeight: Double,
        feedHeight: Double,
        topBarMaxY: Double,
        chromeFloorY: Double,
        belowFeedSlot: Double = fitBelowFeedSlot
    ) -> Double {
        let feedHeight = max(0, feedHeight)
        let top = max(0, topBarMaxY)
        let keepClear = chromeFloorY - max(0, belowFeedSlot)
        let ideal = (max(0, viewportHeight) - feedHeight) / 2
        let latest = max(top, keepClear - feedHeight)
        return min(max(ideal, top), latest)
    }

    public static func zones(
        viewportWidth: Double,
        viewportHeight: Double,
        safeArea: MonitorEdgeInsets,
        mode: MonitorPortraitDispMode,
        aspect: PortraitFeedAspect,
        scopeCount _: Int,  // overlays no longer reserve a band
        assistToolbarHeight: Double = 0,
        feedAspectRatio: Double = 16.0 / 9.0
    ) -> MonitorPortraitZones {
        let viewportWidth = max(0, viewportWidth)
        let viewportHeight = max(0, viewportHeight)
        let feedAspectRatio = feedAspectRatio > 0 ? feedAspectRatio : 16.0 / 9.0

        let topBar = MonitorLayoutRegion(
            x: 0,
            y: max(0, max(0, safeArea.top) - topBarLift),
            width: viewportWidth,
            height: topBarHeight
        )

        let systemBarBottomInset = max(0, max(0, safeArea.bottom) - systemBarBottomLift)
        let systemBar = MonitorLayoutRegion(
            x: 0,
            y: max(0, viewportHeight - systemBarBottomInset - systemBarHeight),
            width: viewportWidth,
            height: systemBarHeight
        )

        switch aspect {
        case .fit16x9:
            let naturalFeedHeight = viewportWidth / feedAspectRatio
            func clampedFeedHeight(reservedBelow: Double) -> Double {
                guard feedAspectRatio < 1 else { return naturalFeedHeight }
                let available = max(0, systemBar.y - topBar.maxY - reservedBelow)
                return min(naturalFeedHeight, available)
            }
            let feedHeight = naturalFeedHeight
            let feed = MonitorFeedFrame(
                x: 0, y: topBar.maxY, width: viewportWidth, height: feedHeight)

            switch mode {
            case .command:
                let scopes = MonitorLayoutRegion(
                    x: 0, y: feed.y + feed.height, width: viewportWidth, height: 0)
                let assistToolbar = MonitorLayoutRegion(
                    x: 0, y: scopes.maxY, width: viewportWidth, height: 0)
                let controls = MonitorLayoutRegion(
                    x: 0, y: topBar.maxY, width: viewportWidth,
                    height: max(0, systemBar.y - topBar.maxY))
                return MonitorPortraitZones(
                    topBar: topBar, feed: feed, scopes: scopes, assistToolbar: assistToolbar,
                    controls: controls, systemBar: systemBar)

            case .clean:
                let cleanSpan = max(0, systemBar.y - topBar.maxY)
                let cleanHeight = clampedFeedHeight(reservedBelow: 0)
                let cleanFeed = MonitorFeedFrame(
                    x: 0, y: topBar.maxY + max(0, (cleanSpan - cleanHeight) / 2),
                    width: viewportWidth, height: cleanHeight)
                let scopes = MonitorLayoutRegion(
                    x: 0, y: cleanFeed.y + cleanFeed.height, width: viewportWidth, height: 0)
                let assistToolbar = MonitorLayoutRegion(
                    x: 0, y: scopes.maxY, width: viewportWidth, height: 0)
                let controls = MonitorLayoutRegion(
                    x: 0, y: scopes.maxY, width: viewportWidth, height: 0)
                return MonitorPortraitZones(
                    topBar: topBar, feed: cleanFeed, scopes: scopes, assistToolbar: assistToolbar,
                    controls: controls, systemBar: systemBar)

            case .live:
                // Scopes overlay the feed — they do not reserve a band that
                // shoves the 16:9 well and parked stick/zoom upward.
                let toolbarHeight = max(0, assistToolbarHeight)
                let chromeFloor = systemBar.y - toolbarHeight
                let feedHeight = clampedFeedHeight(reservedBelow: toolbarHeight)
                let liveY = liveFitFeedOriginY(
                    viewportHeight: viewportHeight,
                    feedHeight: feedHeight,
                    topBarMaxY: topBar.maxY,
                    chromeFloorY: chromeFloor)
                let liveFeed = MonitorFeedFrame(
                    x: 0, y: liveY, width: viewportWidth, height: feedHeight)
                // Toolbar sits on the system rail (vertical-fill style), not
                // glued under the 16:9 strip.
                let assistToolbar = MonitorLayoutRegion(
                    x: 0, y: systemBar.y - toolbarHeight, width: viewportWidth,
                    height: toolbarHeight)
                let scopes = MonitorLayoutRegion(
                    x: 0, y: assistToolbar.y, width: viewportWidth, height: 0)
                let controls = MonitorLayoutRegion(
                    x: 0, y: liveFeed.y + liveFeed.height, width: viewportWidth,
                    height: max(0, assistToolbar.y - (liveFeed.y + liveFeed.height)))
                return MonitorPortraitZones(
                    topBar: topBar, feed: liveFeed, scopes: scopes, assistToolbar: assistToolbar,
                    controls: controls, systemBar: systemBar)
            }

        case .fill:
            let span = max(0, systemBar.y - topBar.maxY)
            let feedHeight = min(viewportWidth * 16 / 9, span)
            let feed = MonitorFeedFrame(
                x: 0, y: topBar.maxY, width: viewportWidth, height: feedHeight)
            let scopes = MonitorLayoutRegion(
                x: 0, y: feed.y + feed.height, width: viewportWidth, height: 0)
            let assistToolbar = MonitorLayoutRegion(
                x: 0, y: scopes.maxY, width: viewportWidth, height: 0)
            let controlsHeight = mode == .clean ? 0 : min(captureBarHeight, feed.height)
            let controls = MonitorLayoutRegion(
                x: 0, y: feed.y + feed.height - controlsHeight, width: viewportWidth,
                height: controlsHeight)
            return MonitorPortraitZones(
                topBar: topBar, feed: feed, scopes: scopes, assistToolbar: assistToolbar,
                controls: controls, systemBar: systemBar)
        }
    }

    /// Gimbal stick on the feed's bottom centre, above `bottomClearance`
    /// (capture strip + gap in fill).
    public static func feedGimbalStick(
        feed: MonitorLayoutRegion,
        size: Double,
        bottomClearance: Double
    ) -> MonitorLayoutRegion {
        let size = max(0, size)
        return MonitorLayoutRegion(
            x: feed.x + max(0, (feed.width - size) / 2),
            y: feed.maxY - max(0, bottomClearance) - size,
            width: size,
            height: size
        )
    }

    /// Stick in the feed's trailing-bottom corner.
    public static func feedGimbalStickTrailing(
        feed: MonitorLayoutRegion,
        size: Double,
        bottomClearance: Double,
        trailingInset: Double
    ) -> MonitorLayoutRegion {
        let size = max(0, size)
        return MonitorLayoutRegion(
            x: feed.maxX - max(0, trailingInset) - size,
            y: feed.maxY - max(0, bottomClearance) - size,
            width: size,
            height: size
        )
    }

    /// Zoom chip above the stick, trailing-aligned to the stick (screen edge).
    public static func feedZoomChipAbove(
        feed: MonitorLayoutRegion,
        stick: MonitorLayoutRegion,
        size: Double,
        gap: Double
    ) -> MonitorLayoutRegion {
        let size = max(0, size)
        let x = min(max(feed.x, stick.maxX - size), feed.maxX - size)
        let y = max(feed.y, stick.y - max(0, gap) - size)
        return MonitorLayoutRegion(x: x, y: y, width: size, height: size)
    }

    /// Fit/fill key: bottom centre, parked on `floorY` (assist toolbar / scopes).
    /// Stays at or below the 16:9 well.
    public static func aspectToggle(
        feed: MonitorFeedFrame,
        floorY: Double,
        size: Double = aspectToggleSize,
        gap: Double = aspectToggleGap
    ) -> MonitorLayoutRegion {
        let size = max(0, size)
        let gap = max(0, gap)
        let feedBottom = feed.y + feed.height
        let parked = floorY - gap - size
        // Fit: floor is below the well — sit on the toolbar band.
        // Fill: floor is the capture strip inside the well — stay on the picture.
        let y = floorY > feedBottom ? max(feedBottom + gap, parked) : max(feed.y, parked)
        return MonitorLayoutRegion(
            x: feed.x + max(0, (feed.width - size) / 2),
            y: y,
            width: size,
            height: size
        )
    }

    /// 16:9 fit: stick + zoom sit outside the well, trailing, on `floorY`
    /// (just above the assist toolbar). Zoom stacks above the stick.
    public static func outsideTrailingCorner(
        feed: MonitorFeedFrame,
        floorY: Double,
        stickSize: Double = outsideStickSize,
        zoomSize: Double = outsideZoomSize,
        gap: Double = outsideControlsGap,
        inset: Double = outsideControlsInset
    ) -> (stick: MonitorLayoutRegion, zoom: MonitorLayoutRegion) {
        let cluster = GimbalCluster.belowWell(
            well: MonitorLayoutRegion(
                x: feed.x, y: feed.y, width: feed.width, height: feed.height),
            floorY: floorY,
            stickSize: stickSize,
            zoomSize: zoomSize,
            gap: gap,
            inset: inset)
        return (cluster.stick, cluster.zoom)
    }

    /// Zoom chip to the trailing side of the stick, vertically centred on it.
    public static func feedZoomChip(
        feed: MonitorLayoutRegion,
        beside stick: MonitorLayoutRegion,
        size: Double,
        gap: Double,
        trailingInset: Double
    ) -> MonitorLayoutRegion {
        let size = max(0, size)
        let x = min(stick.maxX + max(0, gap), feed.maxX - max(0, trailingInset) - size)
        return MonitorLayoutRegion(
            x: max(feed.x, x),
            y: stick.midY - size / 2,
            width: size,
            height: size
        )
    }

    public static func fillAssistRail(
        feed: MonitorLayoutRegion,
        captureStripTop: Double?,
        expanded: Bool
    ) -> MonitorLayoutRegion {
        let edge = assistRailEdgeInset
        let feedBottom = feed.maxY
        let railBottom = captureStripTop.map { min(max($0, feed.y), feedBottom) } ?? feedBottom
        let top = feed.y + edge
        let width = expanded ? assistRailExpandedWidth : assistRailCollapsedSize
        let height = expanded ? max(0, railBottom - top - edge) : assistRailCollapsedSize
        let y = expanded ? top : max(top, railBottom - height - edge)
        return MonitorLayoutRegion(x: feed.x + edge, y: y, width: width, height: height)
    }
}
