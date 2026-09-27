import SwiftUI
import XCTest

@testable import OpenPocketCine

/// One table for the movable scope panels. Each assist keeps its own copy of the
/// OpenZCine `MovablePanel` placement and size math, so every row runs the same checks.
final class ScopeAssistTableTests: XCTestCase {
    private struct Panel {
        let name: String
        let baseSize: CGSize
        let sharedSize: CGSize
        let storedRoundTrip: (CGPoint, CGRect) -> (x: Double, y: Double, restored: CGPoint)
        let defaultCenter: (_ feed: CGRect, _ size: CGSize, _ bounds: CGRect, EdgeInsets) -> CGPoint
        let clamp: (CGPoint, CGSize, CGRect) -> CGPoint
        let snap: (CGPoint) -> CGPoint
        let hapticCell: (CGPoint) -> Int
        let resolved:
            (_ session: CGPoint?, _ stored: CGPoint?, _ fallback: CGPoint, CGSize, CGRect) -> CGPoint
        let clampedScale: (Double) -> Double
        let panelSize: (Double) -> CGSize
        /// Literal sizes the per-scope tests pinned before the merge.
        let pinnedSizes: [(scale: Double, size: CGSize)]
    }

    private let panels: [Panel] = [
        Panel(
            name: "vectorscope", baseSize: VectorscopeAssist.baseSize,
            sharedSize: ScopePanelSize.vectorscope,
            storedRoundTrip: { center, bounds in
                let s = VectorscopeAssist.StoredCenter(center: center, in: bounds)
                return (s.xFraction, s.yFraction, s.center(in: bounds))
            },
            defaultCenter: { VectorscopeAssist.defaultCenter(feed: $0, size: $1, bounds: $2, chromeClearance: $3) },
            clamp: { VectorscopeAssist.clamp($0, size: $1, bounds: $2) },
            snap: { VectorscopeAssist.snap($0) },
            hapticCell: { VectorscopeAssist.hapticCell($0) },
            resolved: { session, stored, fallback, size, bounds in
                VectorscopeAssist.resolvedCenter(
                    session: session,
                    stored: stored.map { VectorscopeAssist.StoredCenter(center: $0, in: bounds) },
                    defaultCenter: fallback, size: size, bounds: bounds)
            },
            clampedScale: { VectorscopeAssist.Options.clampedScale($0) },
            panelSize: { VectorscopeAssist.panelSize(scale: $0) },
            pinnedSizes: [
                (1, CGSize(width: 190, height: 190)), (2, CGSize(width: 304, height: 304)),
                (0.6, CGSize(width: 114, height: 114)),
            ]),
        Panel(
            name: "waveform", baseSize: WaveformAssist.baseSize,
            sharedSize: ScopePanelSize.waveform,
            storedRoundTrip: { center, bounds in
                let s = WaveformAssist.StoredCenter(center: center, in: bounds)
                return (s.xFraction, s.yFraction, s.center(in: bounds))
            },
            defaultCenter: { WaveformAssist.defaultCenter(feed: $0, size: $1, bounds: $2, chromeClearance: $3) },
            clamp: { WaveformAssist.clamp($0, size: $1, bounds: $2) },
            snap: { WaveformAssist.snap($0) },
            hapticCell: { WaveformAssist.hapticCell($0) },
            resolved: { session, stored, fallback, size, bounds in
                WaveformAssist.resolvedCenter(
                    session: session,
                    stored: stored.map { WaveformAssist.StoredCenter(center: $0, in: bounds) },
                    defaultCenter: fallback, size: size, bounds: bounds)
            },
            clampedScale: { WaveformAssist.Options.clampedScale($0) },
            panelSize: { WaveformAssist.panelSize(scale: $0) },
            pinnedSizes: [
                (1, CGSize(width: 250, height: 153)), (1.4, CGSize(width: 350, height: 214)),
            ]),
        Panel(
            name: "parade", baseSize: ParadeAssist.baseSize, sharedSize: ScopePanelSize.parade,
            storedRoundTrip: { center, bounds in
                let s = ParadeAssist.StoredCenter(center: center, in: bounds)
                return (s.xFraction, s.yFraction, s.center(in: bounds))
            },
            defaultCenter: { ParadeAssist.defaultCenter(feed: $0, size: $1, bounds: $2, chromeClearance: $3) },
            clamp: { ParadeAssist.clamp($0, size: $1, bounds: $2) },
            snap: { ParadeAssist.snap($0) },
            hapticCell: { ParadeAssist.hapticCell($0) },
            resolved: { session, stored, fallback, size, bounds in
                ParadeAssist.resolvedCenter(
                    session: session,
                    stored: stored.map { ParadeAssist.StoredCenter(center: $0, in: bounds) },
                    defaultCenter: fallback, size: size, bounds: bounds)
            },
            clampedScale: { ParadeAssist.Options.clampedScale($0) },
            panelSize: { ParadeAssist.panelSize(scale: $0) },
            pinnedSizes: [(2, CGSize(width: 400, height: 245))]),
        Panel(
            name: "histogram", baseSize: HistogramAssist.baseSize,
            sharedSize: ScopePanelSize.histogram,
            storedRoundTrip: { center, bounds in
                let s = HistogramAssist.StoredCenter(center: center, in: bounds)
                return (s.xFraction, s.yFraction, s.center(in: bounds))
            },
            defaultCenter: { HistogramAssist.defaultCenter(feed: $0, size: $1, bounds: $2, chromeClearance: $3) },
            clamp: { HistogramAssist.clamp($0, size: $1, bounds: $2) },
            snap: { HistogramAssist.snap($0) },
            hapticCell: { HistogramAssist.hapticCell($0) },
            resolved: { session, stored, fallback, size, bounds in
                HistogramAssist.resolvedCenter(
                    session: session,
                    stored: stored.map { HistogramAssist.StoredCenter(center: $0, in: bounds) },
                    defaultCenter: fallback, size: size, bounds: bounds)
            },
            clampedScale: { HistogramAssist.Options.clampedScale($0) },
            panelSize: { HistogramAssist.panelSize(scale: $0) },
            pinnedSizes: [(0.7, CGSize(width: (250 * 0.7).rounded(), height: (77 * 0.7).rounded()))]),
        Panel(
            name: "traffic lights", baseSize: TrafficLightsAssist.baseSize,
            sharedSize: ScopePanelSize.trafficLights,
            storedRoundTrip: { center, bounds in
                let s = TrafficLightsAssist.StoredCenter(center: center, in: bounds)
                return (s.xFraction, s.yFraction, s.center(in: bounds))
            },
            defaultCenter: {
                TrafficLightsAssist.defaultCenter(feed: $0, size: $1, bounds: $2, chromeClearance: $3)
            },
            clamp: { TrafficLightsAssist.clamp($0, size: $1, in: $2) },
            snap: { TrafficLightsAssist.snap($0) },
            hapticCell: { TrafficLightsAssist.hapticCell($0) },
            resolved: { session, stored, fallback, size, bounds in
                TrafficLightsAssist.resolvedCenter(
                    session: session,
                    stored: stored.map { TrafficLightsAssist.StoredCenter(center: $0, in: bounds) },
                    defaultCenter: fallback, size: size, bounds: bounds)
            },
            clampedScale: { TrafficLightsAssist.clampedScale($0) },
            panelSize: { TrafficLightsAssist.panelSize(scale: $0) },
            pinnedSizes: [
                (1.2, CGSize(width: (74 * 1.2).rounded(), height: (168 * 1.2).rounded()))
            ]),
        Panel(
            name: "ND meter", baseSize: NDAssist.baseSize, sharedSize: ScopePanelSize.ndMeter,
            storedRoundTrip: { center, bounds in
                let s = NDAssist.StoredCenter(center: center, in: bounds)
                return (s.xFraction, s.yFraction, s.center(in: bounds))
            },
            defaultCenter: { NDAssist.defaultCenter(feed: $0, size: $1, bounds: $2, chromeClearance: $3) },
            clamp: { NDAssist.clamp($0, size: $1, in: $2) },
            snap: { NDAssist.snap($0) },
            hapticCell: { NDAssist.hapticCell($0) },
            resolved: { session, stored, fallback, size, bounds in
                NDAssist.resolvedCenter(
                    session: session,
                    stored: stored.map { NDAssist.StoredCenter(center: $0, in: bounds) },
                    defaultCenter: fallback, size: size, bounds: bounds)
            },
            clampedScale: { NDAssist.clampedScale($0) },
            panelSize: { NDAssist.panelSize(scale: $0) },
            pinnedSizes: [(1, CGSize(width: 84, height: 30))]),
    ]

    func testStoredCenterRoundTripsAsFractions() {
        let samples: [(center: CGPoint, bounds: CGRect)] = [
            (CGPoint(x: 750, y: 125), CGRect(x: 0, y: 0, width: 1000, height: 500)),
            (CGPoint(x: 184, y: 146), CGRect(x: 0, y: 0, width: 874, height: 402)),
            (CGPoint(x: 90, y: 70), CGRect(x: 10, y: 20, width: 400, height: 200)),
            (CGPoint(x: 110, y: 70), CGRect(x: 10, y: 20, width: 200, height: 100)),
            (CGPoint(x: 60, y: 70), CGRect(x: 10, y: 20, width: 200, height: 100)),
            (CGPoint(x: 80, y: 160), CGRect(x: 0, y: 0, width: 200, height: 200)),
        ]
        for panel in panels {
            for sample in samples {
                let label = "\(panel.name) \(sample.center) in \(sample.bounds)"
                let stored = panel.storedRoundTrip(sample.center, sample.bounds)
                XCTAssertEqual(
                    stored.x, Double((sample.center.x - sample.bounds.minX) / sample.bounds.width),
                    accuracy: 1e-9, label)
                XCTAssertEqual(
                    stored.y, Double((sample.center.y - sample.bounds.minY) / sample.bounds.height),
                    accuracy: 1e-9, label)
                XCTAssertEqual(stored.restored.x, sample.center.x, accuracy: 0.001, label)
                XCTAssertEqual(stored.restored.y, sample.center.y, accuracy: 0.001, label)
            }
        }
    }

    func testUnplacedPanelStartsAtCanvasCenterClearOfChrome() {
        let canvases: [(bounds: CGRect, feed: CGRect)] = [
            (CGRect(x: 0, y: 0, width: 874, height: 402), CGRect(x: 59, y: 0, width: 714.7, height: 402)),
            (CGRect(x: 0, y: 0, width: 800, height: 400), CGRect(x: 40, y: 20, width: 720, height: 360)),
        ]
        let clearance = EdgeInsets(top: 60, leading: 0, bottom: 72, trailing: 0)
        for panel in panels {
            for canvas in canvases {
                let label = "\(panel.name) in \(canvas.bounds)"
                let bounds = canvas.bounds
                let size = panel.baseSize
                let center = panel.defaultCenter(canvas.feed, size, bounds, clearance)
                XCTAssertEqual(center.x, bounds.midX, accuracy: 0.05, label)
                XCTAssertEqual(center.y, bounds.midY, accuracy: 0.05, label)
                let clamped = panel.clamp(center, size, bounds)
                XCTAssertEqual(clamped.x, center.x, accuracy: 0.01, label)
                XCTAssertEqual(clamped.y, center.y, accuracy: 0.01, label)
                XCTAssertGreaterThan(center.y, canvas.feed.minY, label)
                XCTAssertGreaterThan(center.y, clearance.top, label)
                XCTAssertGreaterThanOrEqual(center.y - size.height / 2, clearance.top + 10 - 0.5, label)
                XCTAssertGreaterThanOrEqual(center.x - size.width / 2, bounds.minX - 0.5, label)
                XCTAssertLessThanOrEqual(center.x + size.width / 2, bounds.maxX + 0.5, label)
                let assistTop = bounds.maxY - clearance.bottom
                XCTAssertLessThan(center.y + size.height / 2, assistTop, label)
                XCTAssertGreaterThan(assistTop - (center.y + size.height / 2), 8, label)
            }
        }
    }

    func testSnapClampAndHapticGrid() {
        let snaps: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 11, y: 23), CGPoint(x: 12, y: 24)),
            (CGPoint(x: 11, y: 7), CGPoint(x: 12, y: 8)),
            (CGPoint(x: 10.4, y: 21.6), CGPoint(x: 12, y: 20)),
        ]
        let clamps: [(bounds: CGRect, size: CGSize, point: CGPoint, expected: CGPoint)] = [
            (CGRect(x: 0, y: 0, width: 400, height: 300), CGSize(width: 100, height: 80),
             CGPoint(x: -20, y: 900), CGPoint(x: 50, y: 260)),
            (CGRect(x: 0, y: 0, width: 400, height: 200), CGSize(width: 100, height: 50),
             CGPoint(x: -20, y: 400), CGPoint(x: 50, y: 175)),
            (CGRect(x: 0, y: 0, width: 200, height: 200), CGSize(width: 74, height: 168),
             CGPoint(x: -40, y: 400), CGPoint(x: 37, y: 116)),
            (CGRect(x: 0, y: 0, width: 200, height: 200), CGSize(width: 84, height: 30),
             CGPoint(x: -40, y: 400), CGPoint(x: 42, y: 185)),
        ]
        for panel in panels {
            for (point, expected) in snaps {
                let snapped = panel.snap(point)
                XCTAssertEqual(snapped.x, expected.x, accuracy: 0.01, "\(panel.name) snap \(point)")
                XCTAssertEqual(snapped.y, expected.y, accuracy: 0.01, "\(panel.name) snap \(point)")
            }
            for row in clamps {
                let clamped = panel.clamp(row.point, row.size, row.bounds)
                XCTAssertEqual(clamped.x, row.expected.x, accuracy: 0.05, "\(panel.name) clamp \(row.size)")
                XCTAssertEqual(clamped.y, row.expected.y, accuracy: 0.05, "\(panel.name) clamp \(row.size)")
            }
            XCTAssertEqual(panel.hapticCell(CGPoint(x: 44, y: 22)), 2 &* 100_000 &+ 1, panel.name)
            XCTAssertEqual(panel.hapticCell(CGPoint(x: 22, y: 44)), 1 &* 100_000 &+ 2, panel.name)
            XCTAssertEqual(
                panel.hapticCell(CGPoint(x: 22, y: 44)), panel.hapticCell(CGPoint(x: 23, y: 45)),
                panel.name)
        }
    }

    func testResolvedCenterPrefersSessionThenStoredThenDefault() {
        let fixtures:
            [(bounds: CGRect, size: CGSize, fallback: CGPoint, stored: CGPoint, session: CGPoint)] = [
                (CGRect(x: 0, y: 0, width: 400, height: 300), CGSize(width: 100, height: 80),
                 CGPoint(x: 80, y: 80), CGPoint(x: 200, y: 150), CGPoint(x: 120, y: 110)),
                // resolvedCenter clamps every source; the fallback must fit the panel
                // (half-size 125 x 76.5) to survive unchanged.
                (CGRect(x: 0, y: 0, width: 800, height: 400), CGSize(width: 250, height: 153),
                 CGPoint(x: 150, y: 100), CGPoint(x: 300, y: 120), CGPoint(x: 400, y: 200)),
                (CGRect(x: 0, y: 0, width: 400, height: 200), CGSize(width: 40, height: 20),
                 CGPoint(x: 20, y: 10), CGPoint(x: 200, y: 100), CGPoint(x: 80, y: 60)),
                (CGRect(x: 0, y: 0, width: 200, height: 200), CGSize(width: 74, height: 168),
                 CGPoint(x: 50, y: 100), CGPoint(x: 100, y: 110), CGPoint(x: 80, y: 90)),
                (CGRect(x: 0, y: 0, width: 200, height: 200), CGSize(width: 84, height: 30),
                 CGPoint(x: 50, y: 40), CGPoint(x: 80, y: 160), CGPoint(x: 90, y: 40)),
            ]
        for panel in panels {
            for f in fixtures {
                let label = "\(panel.name) \(f.size)"
                let fromSession = panel.resolved(f.session, f.stored, f.fallback, f.size, f.bounds)
                XCTAssertEqual(fromSession.x, f.session.x, accuracy: 0.001, label)
                XCTAssertEqual(fromSession.y, f.session.y, accuracy: 0.001, label)
                let fromStored = panel.resolved(nil, f.stored, f.fallback, f.size, f.bounds)
                XCTAssertEqual(fromStored.x, f.stored.x, accuracy: 0.001, label)
                XCTAssertEqual(fromStored.y, f.stored.y, accuracy: 0.001, label)
                let fromDefault = panel.resolved(nil, nil, f.fallback, f.size, f.bounds)
                XCTAssertEqual(fromDefault.x, f.fallback.x, accuracy: 0.001, label)
                XCTAssertEqual(fromDefault.y, f.fallback.y, accuracy: 0.001, label)
            }
        }
    }

    func testScaleClampAndPanelSizeRoundBaseTimesScale() {
        let scales: [(Double, Double)] = [
            (0.01, 0.6), (0.2, 0.6), (1, 1), (1.1, 1.1), (2, 1.6), (3, 1.6), (99, 1.6),
        ]
        for panel in panels {
            XCTAssertEqual(panel.baseSize, panel.sharedSize, panel.name)
            XCTAssertEqual(panel.panelSize(1), panel.baseSize, panel.name)
            for (input, expected) in scales {
                XCTAssertEqual(panel.clampedScale(input), expected, accuracy: 1e-12, "\(panel.name) \(input)")
                XCTAssertEqual(
                    panel.panelSize(input),
                    CGSize(
                        width: (panel.baseSize.width * expected).rounded(),
                        height: (panel.baseSize.height * expected).rounded()),
                    "\(panel.name) size at \(input)")
            }
            for pinned in panel.pinnedSizes {
                XCTAssertEqual(panel.panelSize(pinned.scale), pinned.size, "\(panel.name) \(pinned.scale)")
            }
        }
        XCTAssertEqual(HistogramAssist.Options(scale: 0.01).scale, 0.6)
    }

    func testTraceBrightnessClampsAndScalesIntensity() {
        let scopes: [(name: String, clamp: (Int) -> Int, intensity: (Int) -> Double, unity: Double)] = [
            ("vectorscope", VectorscopeAssist.Options.clampedBrightness, VectorscopeAssist.intensity, 1),
            ("waveform", WaveformAssist.Options.clampedBrightness, WaveformAssist.intensity, 0.25),
            ("parade", ParadeAssist.Options.clampedBrightness, ParadeAssist.intensity, 1),
        ]
        for scope in scopes {
            XCTAssertEqual(scope.clamp(-10), 0, scope.name)
            XCTAssertEqual(scope.clamp(250), 200, scope.name)
            XCTAssertEqual(scope.clamp(999), 200, scope.name)
            XCTAssertEqual(scope.intensity(0), 0, scope.name)
            XCTAssertEqual(scope.intensity(50), scope.unity / 2, accuracy: 1e-12, scope.name)
            XCTAssertEqual(scope.intensity(100), scope.unity, accuracy: 1e-12, scope.name)
            XCTAssertEqual(scope.intensity(200), scope.unity * 2, accuracy: 1e-12, scope.name)
        }
    }

    func testOptionsDecodeMissingKeysAsDefaults() throws {
        let empty = Data("{}".utf8)
        let decoder = JSONDecoder()

        let vector = try decoder.decode(VectorscopeAssist.Options.self, from: empty)
        XCTAssertEqual(vector.zoom, .x1)
        XCTAssertEqual(vector.brightness, 100)
        XCTAssertEqual(vector.scale, 1)
        XCTAssertNil(vector.storedCenter)

        let wave = try decoder.decode(
            WaveformAssist.Options.self, from: Data(#"{"brightness":150}"#.utf8))
        XCTAssertEqual(wave.mode, .rgb)
        XCTAssertEqual(wave.brightness, 150)
        XCTAssertEqual(wave.scale, 1)
        XCTAssertNil(wave.storedCenter)
        XCTAssertNil(wave.storedCenterPortrait)

        let parade = try decoder.decode(ParadeAssist.Options.self, from: empty)
        XCTAssertEqual(parade.mode, .rgb)
        XCTAssertEqual(parade.brightness, 100)
        XCTAssertEqual(parade.scale, 1)
        XCTAssertTrue(parade.guides.clip)
        XCTAssertNil(parade.storedCenter)

        let histogram = try decoder.decode(HistogramAssist.Options.self, from: empty)
        var legacyDefaults = HistogramAssist.Options.default
        legacyDefaults.hasCustomScale = true
        XCTAssertEqual(histogram, legacyDefaults)
        let scaled = try decoder.decode(
            HistogramAssist.Options.self, from: Data(#"{"scale":0.7,"trafficLights":false}"#.utf8))
        XCTAssertEqual(scaled.scale, 0.7, accuracy: 1e-12)
        XCTAssertFalse(scaled.trafficLights)
        XCTAssertEqual(scaled.crushClipCompensation, .zero)
    }
}
