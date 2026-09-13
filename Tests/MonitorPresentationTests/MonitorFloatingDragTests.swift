import XCTest

@testable import MonitorPresentation

final class MonitorFloatingDragTests: XCTestCase {
    func testReturningToOriginStillCommitsTheFinalPositionOnce() {
        var drag = MonitorFloatingDrag<Int>()
        var stores: [Int] = []
        drag.begin(at: 20)
        drag.move(to: 80)
        drag.move(to: 20)
        drag.end { stores.append($0) }
        XCTAssertEqual(stores, [20])
    }

    func testPointerSamplesStayLocalUntilOneReleaseCommit() {
        var drag = MonitorFloatingDrag<Int>()
        var stores: [Int] = []
        drag.begin(at: 0)
        for position in 1...120 {
            drag.move(to: position)
            XCTAssertEqual(drag.preview, position)
        }
        XCTAssertEqual(stores.count, 0, "Pointer samples must not invalidate the shared model")
        drag.end { stores.append($0) }
        XCTAssertEqual(stores, [120])
        drag.end { stores.append($0) }
        XCTAssertEqual(stores, [120], "A release cannot commit twice")
    }

    func testHoldAndCancellationDoNotTurnDefaultPlacementIntoAStoredPreference() {
        var drag = MonitorFloatingDrag<Int>()
        var stores: [Int] = []
        drag.begin(at: 20)
        drag.end { stores.append($0) }
        XCTAssertTrue(stores.isEmpty)
        drag.begin(at: 20)
        drag.move(to: 80)
        drag.cancel()
        drag.end { stores.append($0) }
        XCTAssertTrue(stores.isEmpty)
        XCTAssertNil(drag.preview)
    }
}
