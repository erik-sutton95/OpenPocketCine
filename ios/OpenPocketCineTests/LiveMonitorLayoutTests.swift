import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// Golden pins from OpenZCine `MonitorLiveViewModuleLayout` on the auditor's 874×402 phone.
final class LiveMonitorLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LiveChromeMetrics.scale = 1
    }

    func testAuditorPhonePinsLeadingIsland() {
        let layout = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: true,
            mirrored: false
        )

        XCTAssertEqual(layout.feed.minX, 59, accuracy: 0.05)
        XCTAssertEqual(layout.feed.minY, 0, accuracy: 0.05)
        XCTAssertEqual(layout.feed.height, 402, accuracy: 0.05)
        XCTAssertEqual(layout.feed.width, 402 * 16 / 9, accuracy: 0.05)
        XCTAssertEqual(layout.feed.maxX, 773.7, accuracy: 0.2)

        XCTAssertEqual(layout.lock.minX, 16, accuracy: 0.05)
        XCTAssertEqual(layout.lock.minY, 17, accuracy: 0.05)
        XCTAssertEqual(layout.lock.width, 40, accuracy: 0.05)
        XCTAssertEqual(layout.lock.midY, layout.topDeck.midY, accuracy: 0.05)

        XCTAssertEqual(layout.rail.minX, 782.4, accuracy: 0.3)
        XCTAssertEqual(layout.rail.width, 82.8, accuracy: 0.05)
        XCTAssertEqual(layout.record.midX, 823.8, accuracy: 0.3)
        XCTAssertEqual(layout.record.midY, 202, accuracy: 0.3)
        XCTAssertGreaterThan(
            layout.record.minX, layout.feed.maxX - 0.5, "record sits in the black lane")

        let tally = LiveRecordingTally.borderRect(in: layout)
        XCTAssertEqual(tally.origin, .zero)
        XCTAssertEqual(
            tally.size, layout.viewport, "tally is the physical screen, not the feed well")
        XCTAssertGreaterThan(
            tally.maxX, layout.rail.maxX, "tally wraps the rail, not the 16:9 well")
        XCTAssertEqual(LiveRecordingTally.lineWidth, 4, accuracy: 0.05)
        XCTAssertEqual(LiveRecordingTally.displayCornerRadius, 52, accuracy: 0.05)

        let zoom = layout.zoomButton
        let stick = layout.gimbalStick
        XCTAssertEqual(zoom.width, 44, accuracy: 0.05)
        XCTAssertEqual(zoom.height, 44, accuracy: 0.05)
        XCTAssertEqual(zoom.maxX, stick.maxX, accuracy: 0.2)
        XCTAssertEqual(
            zoom.maxY, stick.minY - LiveChromeMetrics.gimbalStickGap, accuracy: 0.2)
        XCTAssertGreaterThanOrEqual(zoom.minX, layout.feed.minX)
        XCTAssertFalse(
            zoom.intersects(layout.record),
            "zoom stays in the gimbal cluster, not on record"
        )

        XCTAssertEqual(LiveChromeMetrics.gimbalStickOpacity, 0.55, accuracy: 0.001)
        XCTAssertEqual(stick.width, 88, accuracy: 0.05)
        XCTAssertEqual(stick.height, 88, accuracy: 0.05)
        XCTAssertEqual(stick.maxX, layout.feed.maxX - 16, accuracy: 0.2)
        XCTAssertLessThanOrEqual(stick.maxY + 0.05, layout.capture.minY)
        XCTAssertGreaterThanOrEqual(stick.minX, layout.feed.minX)
        XCTAssertGreaterThanOrEqual(stick.minY, layout.feed.minY)
        XCTAssertFalse(
            stick.intersects(zoom.insetBy(dx: -1, dy: -1)),
            "gimbal stick stays clear of the zoom chip"
        )
        XCTAssertFalse(
            stick.intersects(layout.record),
            "gimbal stick stays clear of record"
        )
    }

    func testChromeScaleFloorsCompactPhonesAndLeavesProMaxAlone() {
        XCTAssertEqual(LiveChromeMetrics.chromeScale(shortestSide: 360), 0.935, accuracy: 0.001)
        XCTAssertEqual(LiveChromeMetrics.chromeScale(shortestSide: 320), 0.935, accuracy: 0.001)
        XCTAssertEqual(LiveChromeMetrics.chromeScale(shortestSide: 424), 1, accuracy: 0.001)
        XCTAssertEqual(LiveChromeMetrics.chromeScale(shortestSide: 440), 1, accuracy: 0.001)
        XCTAssertEqual(
            LiveChromeMetrics.chromeScale(shortestSide: 410), 410 / 424, accuracy: 0.001)
    }

    /// OpenZCine `liveViewModuleFramesMirrorFeedAndChromeTogetherForLandscapeRight`.
    /// Used to pin the opposite: chrome flipped, feed parked. That left the capture
    /// cluster on the picture.
    func testLandscapeRightMirrorsFeedAndChromeTogether() {
        let width: CGFloat = 844
        let standard = LiveMonitorLayout.fit(
            viewportWidth: width,
            viewportHeight: 390,
            safeLeading: 44,
            safeTrailing: 59,
            showsBottomBars: true,
            mirrored: false
        )
        let mirrored = LiveMonitorLayout.fit(
            viewportWidth: width,
            viewportHeight: 390,
            safeLeading: 44,
            safeTrailing: 59,
            showsBottomBars: true,
            mirrored: true
        )
        assertHorizontalMirror(mirrored.feed, of: standard.feed, in: width)
        assertHorizontalMirror(mirrored.picture, of: standard.picture, in: width)
        assertHorizontalMirror(mirrored.lock, of: standard.lock, in: width)
        assertHorizontalMirror(mirrored.battery, of: standard.battery, in: width)
        assertHorizontalMirror(mirrored.rail, of: standard.rail, in: width)
        assertHorizontalMirror(mirrored.record, of: standard.record, in: width)
        assertHorizontalMirror(mirrored.assist, of: standard.assist, in: width)
        assertHorizontalMirror(mirrored.capture, of: standard.capture, in: width)
        XCTAssertEqual(mirrored.topDeck.minX, width - standard.topDeck.maxX, accuracy: 0.5)
        XCTAssertGreaterThan(mirrored.feed.minX, 0)
        XCTAssertLessThan(mirrored.topDeck.minX + 0.5, mirrored.feed.maxX)
        XCTAssertGreaterThan(mirrored.topDeck.maxX, mirrored.feed.minX)
    }

    /// Trailing island is a flush-left feed in standard space — not an extra
    /// in-arm mirror. Physical landscape-right then flips feed and chrome together.
    func testTrailingIslandFeedFlushUnlessDeviceLandscapeRight() {
        XCTAssertFalse(
            LiveMonitorLayout.shouldMirror(
                leading: 0, trailing: 59, orientation: .landscapeLeft))
        XCTAssertTrue(
            LiveMonitorLayout.shouldMirror(
                leading: 0, trailing: 59, orientation: .landscapeRight))
        XCTAssertTrue(
            LiveMonitorLayout.shouldMirror(
                leading: 0, trailing: 59, orientation: .unknown))

        let width: CGFloat = 874
        let unmirrored = LiveMonitorLayout.fit(
            viewportWidth: width,
            viewportHeight: 402,
            safeLeading: 0,
            safeTrailing: 59,
            showsBottomBars: true,
            mirrored: false
        )
        XCTAssertEqual(unmirrored.feed.minX, 0, accuracy: 0.05)

        let mirrored = LiveMonitorLayout.fit(
            viewportWidth: width,
            viewportHeight: 402,
            safeLeading: 0,
            safeTrailing: 59,
            showsBottomBars: true,
            mirrored: true
        )
        assertHorizontalMirror(mirrored.feed, of: unmirrored.feed, in: width)
        assertHorizontalMirror(mirrored.lock, of: unmirrored.lock, in: width)
        assertHorizontalMirror(mirrored.battery, of: unmirrored.battery, in: width)
        assertHorizontalMirror(mirrored.rail, of: unmirrored.rail, in: width)
        assertHorizontalMirror(mirrored.record, of: unmirrored.record, in: width)
        XCTAssertEqual(mirrored.topDeck.minX, width - unmirrored.topDeck.maxX, accuracy: 0.5)
    }

    func testClassicNotchFeedStaysInStandardSpaceUntilExitMirror() {
        let standard = LiveMonitorLayout.fit(
            viewportWidth: 896,
            viewportHeight: 414,
            safeLeading: 44,
            safeTrailing: 44,
            showsBottomBars: true,
            mirrored: false
        )
        XCTAssertEqual(standard.feed.minX, 54, accuracy: 0.5)
        let mirrored = LiveMonitorLayout.fit(
            viewportWidth: 896,
            viewportHeight: 414,
            safeLeading: 44,
            safeTrailing: 44,
            showsBottomBars: true,
            mirrored: true
        )
        XCTAssertEqual(mirrored.feed.minX, 896 - standard.feed.maxX, accuracy: 0.5)
        XCTAssertEqual(mirrored.feed.maxX, 896 - 44 - 10, accuracy: 0.5)
    }

    func testUIKitLandscapeLeftIsPhysicalLandscapeRight() {
        XCTAssertEqual(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .landscapeRight,
                safeArea: MonitorEdgeInsets(top: 0, leading: 59, bottom: 0, trailing: 0)
            ),
            .mirrored
        )
        XCTAssertEqual(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .landscapeLeft,
                safeArea: MonitorEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 59)
            ),
            .standard
        )
    }

    /// Portrait GeometryReader is often the safe-area box. Width still matches
    /// the scene, so a width-only full-bleed test used to keep that short height
    /// and leave a dead band under the system bar / Operator Setup card.
    func testPortraitSafeAreaBoxUsesPhysicalScreenHeight() {
        let screen = CGSize(width: 390, height: 844)
        let inset = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let fromInsetBox = LiveMonitorLayout.fit(
            layoutSize: CGSize(width: 390, height: 751),
            safeArea: EdgeInsets(),
            screenSize: screen,
            showsBottomBars: true
        )
        XCTAssertEqual(fromInsetBox.viewport.width, 390, accuracy: 0.05)
        XCTAssertEqual(fromInsetBox.viewport.height, 844, accuracy: 0.05)

        let recovered = LiveMonitorLayout.resolvedSafeArea(EdgeInsets(), scene: inset)
        XCTAssertEqual(recovered.top, 59, accuracy: 0.05)
        XCTAssertEqual(recovered.bottom, 34, accuracy: 0.05)

        let canvas = LiveMonitorLayout.canvasSize(
            layoutSize: CGSize(width: 390, height: 844),
            safeArea: inset,
            screenSize: screen
        )
        XCTAssertEqual(canvas.height, 844, accuracy: 0.05)
        XCTAssertEqual(canvas.width, 390, accuracy: 0.05)
    }

    func testVerticalFeedCentersAndLeavesTheRail() {
        let cinema = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: true
        )
        let vertical = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: true,
            pictureAspect: 9.0 / 16.0
        )
        XCTAssertEqual(vertical.feed.minX, cinema.feed.minX, accuracy: 0.05)
        XCTAssertEqual(vertical.feed.width, cinema.feed.width, accuracy: 0.05)
        XCTAssertEqual(vertical.record.midX, cinema.record.midX, accuracy: 0.05)
        XCTAssertEqual(vertical.rail.minX, cinema.rail.minX, accuracy: 0.05)
        XCTAssertEqual(vertical.picture.height, 402, accuracy: 0.05)
        XCTAssertEqual(vertical.picture.width, 402 * 9.0 / 16.0, accuracy: 0.5)
        XCTAssertEqual(vertical.picture.midX, 874 / 2, accuracy: 2)
        XCTAssertGreaterThan(vertical.picture.minX, vertical.feed.minX)
        XCTAssertLessThan(vertical.picture.maxX, vertical.feed.maxX)
        XCTAssertEqual(vertical.zoomButton.minX, cinema.zoomButton.minX, accuracy: 0.05)
        XCTAssertEqual(vertical.zoomButton.minY, cinema.zoomButton.minY, accuracy: 0.05)
        XCTAssertEqual(vertical.gimbalStick.minX, cinema.gimbalStick.minX, accuracy: 0.05)
        XCTAssertEqual(vertical.gimbalStick.minY, cinema.gimbalStick.minY, accuracy: 0.05)
        XCTAssertGreaterThan(vertical.zoomButton.maxX, vertical.picture.maxX)
        XCTAssertGreaterThan(vertical.gimbalStick.maxX, vertical.picture.maxX)
    }

    func testGimbalStickDropsToFeedCornerWhenBottomBarsHide() {
        let live = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: true
        )
        let clean = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: false
        )
        XCTAssertLessThanOrEqual(live.gimbalStick.maxY + 0.05, live.capture.minY)
        XCTAssertGreaterThan(clean.gimbalStick.maxY, live.gimbalStick.maxY + 20)
        XCTAssertEqual(
            clean.gimbalStick.maxY, clean.feed.maxY - LiveChromeMetrics.gimbalStickInset,
            accuracy: 0.2)
        XCTAssertEqual(
            clean.gimbalStick.maxX, clean.feed.maxX - LiveChromeMetrics.gimbalStickInset,
            accuracy: 0.2)
        XCTAssertFalse(
            clean.gimbalStick.intersects(clean.zoomButton.insetBy(dx: -1, dy: -1)))
    }

    /// iPad mini A17 Pro landscape (1133×744). 16:9 is width-constrained, so
    /// record sits on the canvas floor. The cluster parks on the right edge
    /// above record.
    func testGimbalStickStaysOnCanvasOnIPadMiniLandscape() {
        let layout = LiveMonitorLayout.fit(
            viewportWidth: 1133,
            viewportHeight: 744,
            safeLeading: 0,
            safeTrailing: 0,
            showsBottomBars: true
        )
        XCTAssertTrue(layout.isWidthConstrained)
        assertGimbalStickOnCanvas(layout)

        let clean = LiveMonitorLayout.fit(
            viewportWidth: 1133,
            viewportHeight: 744,
            safeLeading: 0,
            safeTrailing: 0,
            showsBottomBars: false
        )
        XCTAssertTrue(clean.isWidthConstrained)
        assertGimbalStickOnCanvas(clean)

        let mirrored = LiveMonitorLayout.fit(
            viewportWidth: 1133,
            viewportHeight: 744,
            safeLeading: 0,
            safeTrailing: 0,
            showsBottomBars: true,
            mirrored: true
        )
        XCTAssertTrue(mirrored.isWidthConstrained)
        assertGimbalStickOnCanvas(mirrored)
    }

    func testGimbalStickStaysOnCanvasOnIPadA16Landscape() {
        let layout = LiveMonitorLayout.fit(
            viewportWidth: 1180,
            viewportHeight: 820,
            safeLeading: 0,
            safeTrailing: 0,
            showsBottomBars: true
        )
        XCTAssertTrue(layout.isWidthConstrained)
        assertGimbalStickOnCanvas(layout)
    }

    func testAuditorPhoneScopeWellAndDeck() {
        let layout = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: true
        )
        let zoom = layout.zoomButton

        // WAVE/HISTO sit on the feed and cover the zoom chip. Record is in the
        // black rail, which is why record still worked while zoom taps died.
        // assistOverlays must not steal the chip — it is a later zIndex sibling.
        // Pinch well == feed, so the chip sits inside it and must stay above.
        XCTAssertTrue(
            layout.assistOverlay.intersects(zoom),
            "scope well covers the zoom chip"
        )
        XCTAssertFalse(
            layout.assistOverlay.intersects(layout.record),
            "record stays outside the scope well"
        )
        XCTAssertGreaterThan(layout.assistOverlay.height, 200)
        XCTAssertEqual(layout.assistOverlay.minX, layout.feed.minX, accuracy: 0.05)
        XCTAssertEqual(layout.assistOverlay.width, layout.feed.width, accuracy: 0.05)

        XCTAssertEqual(layout.topDeck.minX, 69, accuracy: 0.2)
        XCTAssertEqual(layout.topDeck.minY, 14, accuracy: 0.05)
        XCTAssertEqual(layout.topDeck.height, 46, accuracy: 0.05)
        XCTAssertEqual(layout.topDeck.width, 695, accuracy: 1.0)
        XCTAssertEqual(layout.topDeck.midX, layout.feed.midX, accuracy: 0.5)

        XCTAssertEqual(layout.assist.minX, 16, accuracy: 0.05)
        XCTAssertEqual(layout.assist.maxY, 402 - 14, accuracy: 0.05)
        XCTAssertEqual(layout.assist.height, 58, accuracy: 0.05)
        XCTAssertEqual(layout.capture.minX, layout.assist.maxX + 12, accuracy: 0.05)
        XCTAssertEqual(layout.assist.width * 2, layout.capture.width, accuracy: 0.5)

        XCTAssertEqual(layout.battery.minX, 8, accuracy: 0.05)
        XCTAssertEqual(layout.battery.minY, layout.lock.maxY + 6, accuracy: 0.05)
        XCTAssertEqual(layout.battery.width, 48, accuracy: 0.05)
        XCTAssertEqual(layout.battery.height, 40, accuracy: 0.05)
        XCTAssertLessThan(layout.battery.maxX, layout.feed.minX + 1)

        let box = TrackingBox(x: 0.20, y: 0.20, width: 0.40, height: 0.40)
        let cancel = LiveTrackingChrome.cancelRect(box: box, feed: layout.feed, mirrored: false)
        XCTAssertEqual(cancel.width, LiveTrackingChrome.cancelHitSize, accuracy: 0.05)
        XCTAssertEqual(cancel.height, LiveTrackingChrome.cancelHitSize, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(cancel.width, 44)
        let subject = CGRect(
            x: layout.feed.minX + 0.20 * layout.feed.width,
            y: layout.feed.minY + 0.20 * layout.feed.height,
            width: 0.40 * layout.feed.width,
            height: 0.40 * layout.feed.height
        )
        XCTAssertEqual(cancel.midX, subject.maxX, accuracy: 0.5)
        XCTAssertEqual(cancel.midY, subject.minY, accuracy: 0.5)

        let reset = layout.focusReset
        XCTAssertEqual(reset.width, LiveChromeMetrics.focusResetSize, accuracy: 0.05)
        XCTAssertEqual(reset.height, LiveChromeMetrics.focusResetSize, accuracy: 0.05)
        XCTAssertEqual(
            reset.midX, layout.battery.maxX + LiveChromeMetrics.focusResetGap, accuracy: 0.2)
        XCTAssertEqual(reset.midY, layout.assist.minY - 30, accuracy: 0.2)
        XCTAssertGreaterThan(reset.midX, layout.battery.maxX)
        XCTAssertLessThan(reset.maxY, layout.assist.minY)
    }

    func testChromeInsetsMatchOpenZCineZeroSafeArea() {
        let chrome = LiveMonitorLayout.chromeRect(in: CGSize(width: 874, height: 402))
        XCTAssertEqual(chrome.minX, 16)
        XCTAssertEqual(chrome.minY, 14)
        XCTAssertEqual(chrome.maxX, 874 - 18)
        XCTAssertEqual(chrome.maxY, 402 - 12)
    }

    func testTopPickerAnchorsUnderChipLikeOpenZCine() {
        XCTAssertEqual(LiveChromeMetrics.topPickerWidth, 340)
        XCTAssertEqual(LiveChromeMetrics.topPickerGap, 8)

        let width = LiveChromeMetrics.topPickerWidth
        let viewport = CGSize(width: 874, height: 402)
        let cell = CGRect(x: 220, y: 14, width: 90, height: 34)
        let leading = LiveTopPickerPlacement.leadingX(
            cellMidX: cell.midX, width: width, viewportWidth: viewport.width)
        let top = LiveTopPickerPlacement.topY(
            cellMaxY: cell.maxY, panelHeight: 280, viewportHeight: viewport.height)
        XCTAssertEqual(leading, cell.midX - width / 2, accuracy: 0.05)
        XCTAssertEqual(top, cell.maxY + 8, accuracy: 0.05)

        let leftLeading = LiveTopPickerPlacement.leadingX(
            cellMidX: 40, width: width, viewportWidth: viewport.width)
        XCTAssertEqual(leftLeading, 8, accuracy: 0.05)
        let rightLeading = LiveTopPickerPlacement.leadingX(
            cellMidX: 850, width: width, viewportWidth: viewport.width)
        XCTAssertEqual(rightLeading, viewport.width - width - 8, accuracy: 0.05)

        let island = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0)
        let islandLeading = LiveTopPickerPlacement.leadingX(
            cellMidX: 40, width: width, viewportWidth: viewport.width, safeArea: island)
        XCTAssertEqual(islandLeading, 59 + 4, accuracy: 0.05)

        let rec = LivePopupPlacement.topPicker(
            cell: cell,
            panelHeight: LiveChromeMetrics.drumPickerHeight + LiveChromeMetrics.pickerModeBarHeight,
            viewport: viewport,
            safeArea: EdgeInsets()
        )
        let color = LivePopupPlacement.topPicker(
            cell: cell,
            panelHeight: LiveChromeMetrics.drumPickerHeight,
            viewport: viewport,
            safeArea: EdgeInsets()
        )
        XCTAssertEqual(rec.y, cell.maxY + 8, accuracy: 0.05)
        XCTAssertEqual(color.y, cell.maxY + 8, accuracy: 0.05)
        XCTAssertGreaterThan(
            rec.maxHeight,
            LiveChromeMetrics.drumPickerHeight + LiveChromeMetrics.pickerModeBarHeight
        )
    }

    func testCapturePickerParksAboveBarOnTile() {
        let layout = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: true
        )
        let tile = CGRect(
            x: layout.capture.midX - 40, y: layout.capture.minY, width: 80, height: 58)
        let box = LivePopupPlacement.capturePicker(
            tile: tile,
            bar: layout.capture,
            panelHeight: 280,
            viewport: layout.viewport,
            safeArea: layout.safeArea
        )
        XCTAssertEqual(box.width, 420, accuracy: 0.05)
        XCTAssertEqual(box.y + 280, layout.capture.minY - 10, accuracy: 0.05)
        XCTAssertEqual(box.x + box.width / 2, tile.midX, accuracy: 1.0)
        XCTAssertGreaterThanOrEqual(box.x, 59 + 4)
        XCTAssertLessThanOrEqual(box.y + min(280, box.maxHeight), layout.capture.minY - 10 + 0.05)
    }

    func testCapturePickerHeightFollowsContentNotSharedWell() {
        let layout = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: true
        )
        let tile = CGRect(
            x: layout.capture.midX - 40, y: layout.capture.minY, width: 80, height: 58)
        let shutter = LivePopupPlacement.capturePicker(
            tile: tile,
            bar: layout.capture,
            panelHeight: LiveChromeMetrics.drumPickerHeight,
            viewport: layout.viewport,
            safeArea: layout.safeArea
        )
        let withTabs = LivePopupPlacement.capturePicker(
            tile: tile,
            bar: layout.capture,
            panelHeight: LiveChromeMetrics.drumPickerHeight + LiveChromeMetrics.pickerModeBarHeight,
            viewport: layout.viewport,
            safeArea: layout.safeArea
        )
        XCTAssertEqual(
            shutter.y + LiveChromeMetrics.drumPickerHeight,
            layout.capture.minY - 10,
            accuracy: 0.05
        )
        XCTAssertEqual(
            withTabs.y + LiveChromeMetrics.drumPickerHeight + LiveChromeMetrics.pickerModeBarHeight,
            layout.capture.minY - 10,
            accuracy: 0.05
        )
        XCTAssertGreaterThan(withTabs.maxHeight, LiveChromeMetrics.drumPickerHeight)
        // Both bottoms anchor to the bar, so the taller (tabbed) panel starts
        // higher on screen — smaller y.
        XCTAssertGreaterThan(shutter.y, withTabs.y)
        XCTAssertNotEqual(shutter.y, withTabs.y, accuracy: 0.05)
    }

    func testCapturePickerDoesNotGoFullBleed() {
        let box = LivePopupPlacement.capturePicker(
            tile: .zero,
            bar: CGRect(x: 20, y: 700, width: 800, height: 58),
            panelHeight: 500,
            viewport: CGSize(width: 390, height: 844),
            safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )
        XCTAssertLessThanOrEqual(box.width, 420)
        XCTAssertLessThan(box.width, 390)
        XCTAssertGreaterThanOrEqual(box.y, 59 + 4)
        XCTAssertLessThanOrEqual(box.y + min(500, box.maxHeight), 700 - 10 + 0.05)
    }

    /// OpenZCine `fullScreenPanelSafeArea` / standalone Operator Setup host.
    func testOperatorSetupLandscapeZerosCleanEdge() {
        let leadingIsland = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0)
        let liveLeading = OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: leadingIsland, isPortrait: false, mirrored: false)
        XCTAssertEqual(liveLeading.leading, 59)
        XCTAssertEqual(liveLeading.trailing, 0)
        XCTAssertEqual(OperatorPanelMetrics.leadingPadding(safeArea: liveLeading), 65)
        XCTAssertEqual(OperatorPanelMetrics.trailingPadding(safeArea: liveLeading), 16)
        XCTAssertEqual(OperatorPanelMetrics.closeButtonClearance(safeArea: liveLeading), 0)

        let trailingIsland = EdgeInsets(top: 0, leading: 0, bottom: 21, trailing: 59)
        let liveTrailing = OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: trailingIsland, isPortrait: false, mirrored: true)
        XCTAssertEqual(liveTrailing.leading, 0)
        XCTAssertEqual(liveTrailing.trailing, 59)
        XCTAssertEqual(OperatorPanelMetrics.leadingPadding(safeArea: liveTrailing), 16)
        XCTAssertEqual(OperatorPanelMetrics.trailingPadding(safeArea: liveTrailing), 65)
        XCTAssertEqual(OperatorPanelMetrics.closeButtonClearance(safeArea: liveTrailing), 45)

        let bothSides = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        let standalone = OperatorPanelMetrics.standalonePanelSafeArea(from: bothSides)
        XCTAssertEqual(standalone.leading, 59)
        XCTAssertEqual(standalone.trailing, 0)

        let portrait = OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            isPortrait: true,
            mirrored: false
        )
        XCTAssertEqual(portrait.top, 59)
        XCTAssertEqual(portrait.leading, 0)
        XCTAssertEqual(OperatorPanelMetrics.settingsTopPadding(safeArea: EdgeInsets()), 14)
    }

    func testMediaBrowserPaddingMatchesOpenZCine() {
        let landscape = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0)
        XCTAssertEqual(OperatorPanelMetrics.mediaTopPadding(safeArea: landscape), 16)
        XCTAssertEqual(
            OperatorPanelMetrics.mediaLeadingPadding(safeArea: landscape, portrait: false), 65)
        XCTAssertEqual(OperatorPanelMetrics.mediaTrailingPadding(safeArea: landscape), 20)
        XCTAssertEqual(OperatorPanelMetrics.mediaBottomPadding(safeArea: landscape), 25)

        let portrait = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        XCTAssertEqual(
            OperatorPanelMetrics.mediaLeadingPadding(safeArea: portrait, portrait: true), 16)
        XCTAssertEqual(OperatorPanelMetrics.mediaTrailingPadding(safeArea: portrait), 20)
        XCTAssertEqual(OperatorPanelMetrics.closeTopPadding(safeArea: portrait), 65)
    }

    func testTrackingBracketLeavesGapsOnEachSide() {
        let width: CGFloat = 200
        let height: CGFloat = 120
        let armX = LiveTrackingChrome.bracketArm(along: width)
        let armY = LiveTrackingChrome.bracketArm(along: height)
        XCTAssertGreaterThan(width - 2 * armX, width * 0.25)
        XCTAssertGreaterThan(height - 2 * armY, height * 0.25)
        XCTAssertGreaterThan(armX, 10)
        XCTAssertGreaterThan(armY, 10)
        let path = LiveTrackingChrome.bracketPath(in: CGSize(width: width, height: height))
        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingRect.maxX, width, accuracy: 0.5)
        XCTAssertEqual(path.boundingRect.maxY, height, accuracy: 0.5)
    }

    private func assertGimbalStickOnCanvas(
        _ layout: LiveMonitorLayout,
        file: StaticString = #file, line: UInt = #line
    ) {
        let stick = layout.gimbalStick
        let inset = LiveChromeMetrics.gimbalStickInset
        XCTAssertEqual(
            stick.width, LiveChromeMetrics.gimbalStickSize, accuracy: 0.05, file: file, line: line)
        XCTAssertGreaterThanOrEqual(stick.minX, layout.feed.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(stick.minY, layout.feed.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(
            stick.maxY, layout.viewport.height - inset + 0.05, file: file, line: line)
        XCTAssertLessThanOrEqual(
            stick.maxX, layout.viewport.width + 0.05, file: file, line: line)
        XCTAssertLessThanOrEqual(
            stick.maxY, layout.feed.maxY + 0.05, file: file, line: line)
        XCTAssertFalse(
            stick.intersects(layout.zoomButton.insetBy(dx: -1, dy: -1)),
            "gimbal stick stays clear of the zoom chip",
            file: file, line: line
        )
        XCTAssertFalse(
            stick.intersects(layout.record.insetBy(dx: -1, dy: -1)),
            "gimbal stick stays clear of record",
            file: file, line: line
        )
        let zoom = layout.zoomButton
        let gap = LiveChromeMetrics.gimbalStickGap
        XCTAssertEqual(zoom.maxX, stick.maxX, accuracy: 0.2, file: file, line: line)
        XCTAssertEqual(
            zoom.maxY, stick.minY - gap, accuracy: 0.2,
            file: file, line: line)
        XCTAssertFalse(
            zoom.intersects(layout.record.insetBy(dx: -1, dy: -1)),
            "zoom stays in the gimbal cluster, not on record",
            file: file, line: line
        )
        if layout.isWidthConstrained {
            XCTAssertEqual(
                stick.maxX, layout.feed.maxX - inset, accuracy: 0.5,
                "iPad cluster stays on the right edge",
                file: file, line: line)
            if layout.record.width > 1, layout.record.midX >= layout.feed.midX {
                XCTAssertLessThanOrEqual(
                    stick.maxY + gap, layout.record.minY + 0.05,
                    "iPad cluster sits above record",
                    file: file, line: line)
            }
        }
        if layout.showsBottomBars {
            XCTAssertLessThanOrEqual(
                stick.maxY + 0.05, layout.capture.minY, file: file, line: line)
        }
    }

    private func assertHorizontalMirror(
        _ actual: CGRect, of original: CGRect, in viewportWidth: CGFloat,
        file: StaticString = #file, line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.minX, viewportWidth - original.maxX, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.minY, original.minY, accuracy: 0.05, file: file, line: line)
        XCTAssertEqual(actual.width, original.width, accuracy: 0.05, file: file, line: line)
        XCTAssertEqual(actual.height, original.height, accuracy: 0.05, file: file, line: line)
    }
}
