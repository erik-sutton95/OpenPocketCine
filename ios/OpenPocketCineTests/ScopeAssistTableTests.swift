import XCTest

@testable import OpenPocketCine

/// Trace brightness of the scope assists. Panel placement and sizing are shared
/// (OpenCine `MonitorScopePanelCenteringTests`).
final class ScopeAssistTableTests: XCTestCase {
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
}
