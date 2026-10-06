import MonitorUI
import OpenCineMedia
import XCTest

@testable import OpenPocketCine

/// The vectorscope square inside this app's scope plot rect. The scope itself is pinned in
/// OpenCineCameraControlsTests.
final class VectorscopeAssistTests: XCTestCase {
    func testPlotSquareCentresInsideScopePlotRect() {
        let size = CGSize(width: 190, height: 190)
        let plot = scopePlotRect(size, top: 26)
        let square = vectorscopePlotSquare(in: size)
        XCTAssertEqual(square.width, square.height, accuracy: 0.01)
        XCTAssertEqual(square.midX, plot.midX, accuracy: 0.01)
        XCTAssertEqual(square.midY, plot.midY, accuracy: 0.01)
        XCTAssertEqual(square.width, min(plot.width, plot.height), accuracy: 0.01)
    }
}
