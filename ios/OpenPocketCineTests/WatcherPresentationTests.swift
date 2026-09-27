import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class WatcherPresentationTests: XCTestCase {
    @MainActor
    func testMonitorToolsUseWatcherSamplesAndTransfer() {
        let model = AppModel()
        model.isWatchingFeed = true
        model.session.status.colorMode = .normal
        model.relayClient.state.color = "D-Log2"
        XCTAssertTrue(model.monitorSamples === model.relayClient.samples)
        XCTAssertEqual(model.monitorColorMode, .dLog2)
        XCTAssertEqual(model.monitorTransfer, .dlog2)
        model.isWatchingFeed = false
        XCTAssertTrue(model.monitorSamples === model.frameSamples)
        XCTAssertEqual(model.monitorColorMode, .normal)
        model.session.status.colorMode = .dLog2
        model.session.status.shootingMode = Int(ShootingMode.photo.rawValue)
        XCTAssertEqual(model.monitorColorMode, .normal)
        XCTAssertEqual(model.monitorTransfer, .rec709)
        XCTAssertEqual(model.session.status.colorMode, .dLog2)
        model.isWatchingFeed = true
        XCTAssertTrue(model.monitorSamples === model.relayClient.samples)
        XCTAssertEqual(model.monitorColorMode, .dLog2)
        XCTAssertEqual(model.monitorTransfer, .dlog2)
        model.isWatchingFeed = false
        model.assist.gradesClip = true
        model.assist.adoptPlaybackColor(.dLog2)
        XCTAssertEqual(model.monitorColorMode, .dLog2)
        XCTAssertEqual(model.monitorTransfer, .dlog2)
        model.assist.gradesClip = false
        XCTAssertEqual(model.monitorColorMode, .normal)
        XCTAssertEqual(model.monitorTransfer, .rec709)
    }
}
