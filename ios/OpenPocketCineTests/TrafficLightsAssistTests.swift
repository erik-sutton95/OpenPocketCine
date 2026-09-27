import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// Pins OpenZCine Traffic Lights — popup rows, RGB goal-post chrome, crush/clip
/// lamps, and labels — onto PocketCine. IRE / histogram science stays in core.
final class TrafficLightsAssistTests: XCTestCase {
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

    /// HISTO and TL each carry a copy of OpenZCine `CrushClipCompensation`; one table
    /// holds both to the same stops, labels, lenient decode, and core-meter threshold.
    func testCrushClipCompensationMatchesAcrossHistoAndLights() throws {
        let histo = try Self.compensationRow(HistogramAssist.CrushClipCompensation.self)
        let lights = try Self.compensationRow(TrafficLightsAssist.CrushClipCompensation.self)
        for row in [histo, lights] {
            XCTAssertEqual(row.rawValues, [0, 2, 5, 7, 10], row.name)
            XCTAssertEqual(row.labels, ["0", "0.25", "0.5", "0.75", "1.0"], row.name)
            XCTAssertEqual(row.compactLabels, ["0", "¼", "½", "¾", "1"], row.name)
            XCTAssertEqual(row.stops, [0, 0.25, 0.5, 0.75, 1.0], row.name)
            for (index, expected) in [(0, 0), (1, 0.025), (2, 0.05), (4, 0.10)] {
                XCTAssertEqual(row.thresholds[index], expected, accuracy: 1e-12, row.name)
            }
            // Legacy stored stops: above the range saturates, unknown below falls to zero.
            for (stored, expected) in [(15, 10), (20, 10), (-1, 0), (3, 0), (2, 2), (5, 5)] {
                XCTAssertEqual(try row.decode(stored), expected, "\(row.name) decodes \(stored)")
            }
            XCTAssertEqual(row.encodedHalfRoundTrips, 5, row.name)

            // The assist supplies only the stops/10 threshold to the shared core meter.
            func red(_ crushPixels: Int, _ threshold: Double) -> ScopeChannelLight {
                var bins = [Int](repeating: 0, count: 256)
                bins[16] = crushPixels  // in the D-Log2 crush band [15…21]
                bins[128] = 100 - crushPixels
                return ScopeTrafficLights.reading(
                    red: bins, green: bins, blue: bins, transfer: .dlog2, threshold: threshold
                ).red
            }
            XCTAssertTrue(red(3, row.thresholds[0]).crush, row.name)
            XCTAssertTrue(red(3, row.thresholds[1]).crush, row.name)
            XCTAssertFalse(red(3, row.thresholds[4]).crush, row.name)
            XCTAssertTrue(red(5, row.thresholds[1]).crush, row.name)
            XCTAssertFalse(red(5, row.thresholds[1]).clip, row.name)
            XCTAssertFalse(red(5, row.thresholds[4]).crush, row.name)
        }
        XCTAssertEqual(TrafficLightsAssist.defaultCompensation, .zero)
        XCTAssertEqual(HistogramAssist.Options.default.crushClipCompensation, .zero)
    }

    private struct CompensationRow {
        let name: String
        let rawValues: [Int]
        let labels: [String]
        let compactLabels: [String]
        let stops: [Double]
        let thresholds: [Double]
        let decode: (Int) throws -> Int
        let encodedHalfRoundTrips: Int
    }

    private static func compensationRow<T: CrushClipCompensationRow>(_: T.Type) throws -> CompensationRow {
        let half = try XCTUnwrap(T(rawValue: 5))
        let roundTrip = try JSONDecoder().decode(T.self, from: JSONEncoder().encode(half))
        return CompensationRow(
            name: String(describing: T.self),
            rawValues: T.allCases.map(\.rawValue),
            labels: T.allCases.map(\.label),
            compactLabels: T.allCases.map(\.compactLabel),
            stops: T.allCases.map(\.stops),
            thresholds: T.allCases.map(\.pixelFractionThreshold),
            decode: { try JSONDecoder().decode(T.self, from: Data("\($0)".utf8)).rawValue },
            encodedHalfRoundTrips: roundTrip.rawValue)
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
}

private protocol CrushClipCompensationRow: CaseIterable, Codable, RawRepresentable
where RawValue == Int {
    var label: String { get }
    var compactLabel: String { get }
    var stops: Double { get }
    var pixelFractionThreshold: Double { get }
}

extension HistogramAssist.CrushClipCompensation: CrushClipCompensationRow {}
extension TrafficLightsAssist.CrushClipCompensation: CrushClipCompensationRow {}
