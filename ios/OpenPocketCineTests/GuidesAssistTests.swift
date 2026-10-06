import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Guide selection on this app's assist state. The guide lists and frames are pinned in
/// OpenCineCameraControlsTests.
final class GuidesAssistTests: XCTestCase {
    @MainActor
    func testToggleAddsAndRemoves() {
        let assist = LiveAssistState()
        assist.selectedGuides = [.cinema]
        assist.toggleGuide(.wide)
        XCTAssertEqual(assist.selectedGuides, [.cinema, .wide])
        assist.toggleGuide(.cinema)
        XCTAssertEqual(assist.selectedGuides, [.wide])
        XCTAssertTrue(assist.guides)
        assist.toggleGuide(.wide)
        XCTAssertTrue(assist.selectedGuides.isEmpty)
        XCTAssertFalse(assist.guides)
    }
}
