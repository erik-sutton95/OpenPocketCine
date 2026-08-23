import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// Pins OpenZCine Traffic Lights — popup rows, RGB goal-post chrome, crush/clip
/// lamps, and labels — onto PocketCine. IRE / histogram science stays in core.
final class TrafficLightsAssistTests: XCTestCase {
    func testOpenZCineCompensationStops() {
        XCTAssertEqual(
            TrafficLightsAssist.CrushClipCompensation.allCases.map(\.label),
            ["0", "0.25", "0.5", "0.75", "1.0"])
        XCTAssertEqual(
            TrafficLightsAssist.CrushClipCompensation.allCases.map(\.compactLabel),
            ["0", "¼", "½", "¾", "1"])
        XCTAssertEqual(
            TrafficLightsAssist.CrushClipCompensation.allCases.map(\.rawValue),
            [0, 2, 5, 7, 10])
        XCTAssertEqual(TrafficLightsAssist.CrushClipCompensation.zero.pixelFractionThreshold, 0)
        XCTAssertEqual(
            TrafficLightsAssist.CrushClipCompensation.quarter.pixelFractionThreshold, 0.025,
            accuracy: 1e-12)
        XCTAssertEqual(
            TrafficLightsAssist.CrushClipCompensation.half.pixelFractionThreshold, 0.05,
            accuracy: 1e-12)
        XCTAssertEqual(
            TrafficLightsAssist.CrushClipCompensation.one.pixelFractionThreshold, 0.10,
            accuracy: 1e-12)
        XCTAssertEqual(TrafficLightsAssist.CrushClipCompensation.quarter.rawValue, 2)
        XCTAssertEqual(TrafficLightsAssist.defaultCompensation, .zero)
        XCTAssertEqual(TrafficLightsAssist.longPressPanelWidth, 400)
        XCTAssertEqual(TrafficLightsAssist.compensationTitle, "Crush/Clip Compensation")
        XCTAssertEqual(
            TrafficLightsAssist.compensationHelp,
            "Stops of crush/clip tolerance before a channel indicator glows. Shared with the histogram traffic lights."
        )
        XCTAssertEqual(TrafficLightsAssist.baseSize, CGSize(width: 74, height: 168))
        XCTAssertEqual(TrafficLightsAssist.baseSize, ScopePanelSize.trafficLights)
        XCTAssertEqual(TrafficLightsAssist.scaleRange, 0.6...1.6)
        XCTAssertEqual(TrafficLightsAssist.panelID, "traffic-lights")
        XCTAssertEqual(TrafficLightsAssist.holdDuration, 0.3, accuracy: 0.001)
        XCTAssertEqual(TrafficLightsAssist.positionGrid, 4)
        XCTAssertEqual(TrafficLightsAssist.hapticGrid, 22)
        XCTAssertEqual(TrafficLightsAssist.segmentMinWidth, 46)
        XCTAssertEqual(TrafficLightsAssist.segmentMinHeight, 34)
    }

    func testMeterChromeMatchesOpenZCine() {
        XCTAssertEqual(TrafficLightsAssist.meterTitle, "TL")
        XCTAssertEqual(TrafficLightsAssist.accessibilityTitle, "Traffic Lights")
        XCTAssertEqual(TrafficLightsAssist.titleSize, 8.5)
        XCTAssertEqual(TrafficLightsAssist.titleSpacing, 6)
        XCTAssertEqual(TrafficLightsAssist.columnSpacing, 6)
        XCTAssertEqual(TrafficLightsAssist.postSpacing, 4)
        XCTAssertEqual(TrafficLightsAssist.panelPad, 8)
        XCTAssertEqual(TrafficLightsAssist.trackWidth, 11)
        XCTAssertEqual(TrafficLightsAssist.columnHeight, 108)
        XCTAssertEqual(TrafficLightsAssist.indicatorSize, 8)
        XCTAssertEqual(TrafficLightsAssist.fillsWidthMaxColumn, 44)
        XCTAssertEqual(TrafficLightsAssist.trackCorner, 2)
        XCTAssertEqual(TrafficLightsAssist.minBarHeight, 1.5)
        XCTAssertEqual(TrafficLightsAssist.centerLineFactor, 0.85, accuracy: 1e-12)
        XCTAssertEqual(TrafficLightsAssist.meterRedRGB.0, 255, accuracy: 0)
        XCTAssertEqual(TrafficLightsAssist.meterRedRGB.1, 92, accuracy: 0)
        XCTAssertEqual(TrafficLightsAssist.meterRedRGB.2, 82, accuracy: 0)
        XCTAssertEqual(TrafficLightsAssist.meterGreenRGB.0, 86, accuracy: 0)
        XCTAssertEqual(TrafficLightsAssist.meterGreenRGB.1, 235, accuracy: 0)
        XCTAssertEqual(TrafficLightsAssist.meterGreenRGB.2, 132, accuracy: 0)
        XCTAssertEqual(TrafficLightsAssist.meterBlueRGB.0, 96, accuracy: 0)
        XCTAssertEqual(TrafficLightsAssist.meterBlueRGB.1, 158, accuracy: 0)
        XCTAssertEqual(TrafficLightsAssist.meterBlueRGB.2, 255, accuracy: 0)
        XCTAssertEqual(TrafficLightsAssist.channelNames, ["red", "green", "blue"])
        XCTAssertEqual(TrafficLightsAssist.leanBalanced, "balanced")
        XCTAssertEqual(TrafficLightsAssist.leanOver, "over")
        XCTAssertEqual(TrafficLightsAssist.leanUnder, "under")
        XCTAssertEqual(TrafficLightsAssist.flagClip, "clip")
        XCTAssertEqual(TrafficLightsAssist.flagCrush, "crush")
        XCTAssertEqual(TrafficLightsAssist.balanceCenter, 0.5, accuracy: 1e-12)
        XCTAssertEqual(TrafficLightsAssist.balanceDeadZone, 0.03, accuracy: 1e-12)
    }

    func testColumnWidthLandscapeAndFillsWidth() {
        XCTAssertEqual(
            TrafficLightsAssist.columnWidth(fillsWidth: false, panelWidth: 74, uiScale: 1), 11)
        XCTAssertEqual(
            TrafficLightsAssist.columnWidth(fillsWidth: false, panelWidth: 300, uiScale: 1.2),
            11 * 1.2, accuracy: 1e-12)
        XCTAssertEqual(
            TrafficLightsAssist.columnWidth(fillsWidth: true, panelWidth: 300, uiScale: 1), 44)
        XCTAssertEqual(
            TrafficLightsAssist.columnWidth(fillsWidth: true, panelWidth: 120, uiScale: 1),
            (120 - 16) / 6, accuracy: 1e-12)
    }

    func testChannelDisplayMatchesOpenZCine() {
        let balanced = TrafficLightsAssist.channelDisplay(level: 0.5)
        XCTAssertEqual(balanced.side, .neutral)
        XCTAssertEqual(balanced.barFill, 0)

        let over = TrafficLightsAssist.channelDisplay(level: 0.75)
        XCTAssertEqual(over.side, .over)
        XCTAssertEqual(over.barFill, 0.5, accuracy: 1e-12)

        let under = TrafficLightsAssist.channelDisplay(level: 0.25)
        XCTAssertEqual(under.side, .under)
        XCTAssertEqual(under.barFill, 0.5, accuracy: 1e-12)

        let nearCentre = TrafficLightsAssist.channelDisplay(
            level: TrafficLightsAssist.balanceCenter + 0.02)
        XCTAssertEqual(nearCentre.side, .neutral)

        let clipped = ScopeChannelLight(clip: true, crush: false, level: 0.98)
        let crushed = ScopeChannelLight(clip: false, crush: true, level: 0.02)
        XCTAssertEqual(TrafficLightsAssist.channelDisplay(for: clipped).side, .over)
        XCTAssertEqual(TrafficLightsAssist.channelDisplay(for: crushed).side, .under)
        XCTAssertTrue(clipped.clip)
        XCTAssertTrue(crushed.crush)
    }

    func testAccessibilityValueLabelsChannelsAndLamps() {
        let reading = ScopeTrafficLightsReading(
            red: ScopeChannelLight(clip: true, crush: false, level: 0.9),
            green: ScopeChannelLight(clip: false, crush: false, level: 0.5),
            blue: ScopeChannelLight(clip: false, crush: true, level: 0.1))
        XCTAssertEqual(
            TrafficLightsAssist.accessibilityValue(for: reading),
            "red over (clip), green balanced, blue under (crush)")
    }

    func testLenientCompensationDecodeClampsLegacyStops() throws {
        let over = try JSONDecoder().decode(
            TrafficLightsAssist.CrushClipCompensation.self, from: Data("15".utf8))
        XCTAssertEqual(over, .one)
        let unknownLow = try JSONDecoder().decode(
            TrafficLightsAssist.CrushClipCompensation.self, from: Data("3".utf8))
        XCTAssertEqual(unknownLow, .zero)
        let quarter = try JSONDecoder().decode(
            TrafficLightsAssist.CrushClipCompensation.self, from: Data("2".utf8))
        XCTAssertEqual(quarter, .quarter)
        let encoded = try JSONEncoder().encode(TrafficLightsAssist.CrushClipCompensation.half)
        XCTAssertEqual(
            try JSONDecoder().decode(TrafficLightsAssist.CrushClipCompensation.self, from: encoded),
            .half)
    }

    func testScaleClampAndPanelSize() {
        XCTAssertEqual(TrafficLightsAssist.clampedScale(0.2), 0.6)
        XCTAssertEqual(TrafficLightsAssist.clampedScale(2), 1.6)
        XCTAssertEqual(TrafficLightsAssist.clampedScale(1), 1)
        let size = TrafficLightsAssist.panelSize(scale: 1.2)
        XCTAssertEqual(size.width, (74 * 1.2).rounded())
        XCTAssertEqual(size.height, (168 * 1.2).rounded())
    }

    func testStoredCenterRoundTrip() {
        let bounds = CGRect(x: 10, y: 20, width: 200, height: 100)
        let center = CGPoint(x: 60, y: 70)
        let stored = TrafficLightsAssist.StoredCenter(center: center, in: bounds)
        let restored = stored.center(in: bounds)
        XCTAssertEqual(restored.x, center.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, center.y, accuracy: 0.001)
    }

    func testDefaultCenterParksInsideFullBleedFeed() {
        let bounds = CGRect(x: 0, y: 0, width: 874, height: 402)
        let feed = CGRect(x: 59, y: 0, width: 714.7, height: 402)
        let size = TrafficLightsAssist.baseSize
        let chrome = EdgeInsets(top: 60, leading: 0, bottom: 72, trailing: 100)
        let center = TrafficLightsAssist.defaultCenter(
            feed: feed, size: size, bounds: bounds, chromeClearance: chrome)
        XCTAssertEqual(center.x, feed.minX + size.width / 2, accuracy: 0.5)
        XCTAssertLessThanOrEqual(center.y + size.height / 2, bounds.maxY - chrome.bottom + 0.5)
        XCTAssertGreaterThanOrEqual(center.y - size.height / 2, bounds.minY - 0.5)
        // OpenZCine .bottomLeading: parks just inside the picture, above the
        // assist/capture strip — the lower half of a full-bleed feed.
        XCTAssertGreaterThan(center.y, feed.midY)
    }

    func testCompensationThresholdLightsCrushBand() {
        // Same core meter as HISTO; the assist supplies only the stops/10 threshold.
        var bins = [Int](repeating: 0, count: 256)
        bins[16] = 5  // in the D-Log2 crush band [15…21]
        bins[128] = 95
        let strict = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2, threshold: 0.10)
        let forgiving = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2,
            threshold: TrafficLightsAssist.CrushClipCompensation.quarter.pixelFractionThreshold)
        XCTAssertFalse(strict.red.crush)
        XCTAssertTrue(forgiving.red.crush)
        XCTAssertFalse(forgiving.red.clip)
    }

    @MainActor
    func testSharedCompensationBridgesHistoAndLights() {
        let previousLights = TrafficLightsAssist.store.compensation
        let previousHisto = HistogramAssist.store.options.crushClipCompensation
        defer {
            TrafficLightsAssist.store.compensation = previousLights
            HistogramAssist.store.options.crushClipCompensation = previousHisto
        }
        TrafficLightsAssist.setSharedCompensation(.half)
        XCTAssertEqual(TrafficLightsAssist.store.compensation, .half)
        XCTAssertEqual(HistogramAssist.store.options.crushClipCompensation, .half)
        XCTAssertEqual(TrafficLightsAssist.sharedCompensation(), .half)
        TrafficLightsAssist.setSharedCompensation(.one)
        XCTAssertEqual(HistogramAssist.store.options.crushClipCompensation, .one)
        XCTAssertEqual(TrafficLightsAssist.sharedCompensation(), .one)
    }

    func testSnapClampAndHapticGrid() {
        let snapped = TrafficLightsAssist.snap(CGPoint(x: 11, y: 7))
        XCTAssertEqual(snapped.x, 12)
        XCTAssertEqual(snapped.y, 8)
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let size = CGSize(width: 74, height: 168)
        let clamped = TrafficLightsAssist.clamp(
            CGPoint(x: -40, y: 400), size: size, in: bounds)
        XCTAssertEqual(clamped.x, size.width / 2)
        XCTAssertEqual(clamped.y, bounds.maxY - size.height / 2)
        XCTAssertEqual(
            TrafficLightsAssist.hapticCell(CGPoint(x: 22, y: 44)),
            TrafficLightsAssist.hapticCell(CGPoint(x: 23, y: 45)))
        let session = CGPoint(x: 80, y: 90)
        let resolved = TrafficLightsAssist.resolvedCenter(
            session: session,
            stored: nil,
            defaultCenter: CGPoint(x: 40, y: 40),
            size: size,
            bounds: bounds)
        XCTAssertEqual(resolved.x, session.x, accuracy: 0.001)
        XCTAssertEqual(resolved.y, session.y, accuracy: 0.001)
    }
}
