import XCTest

@testable import OpenPocketCine

@MainActor
final class CameraMediaCacheRootTests: XCTestCase {
    /// Reviews stage clips in this same cache (`MonitorUIReview.stageMedia`); there is no second root.
    func testCacheRemainsInCameraApplicationSupportDirectory() {
        let root = CameraMedia().cacheRoot(cameraID: "cache-isolation-test")
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(
            root,
            applicationSupport.appendingPathComponent(
                "OpenPocketCine/media/cache-isolation-test", isDirectory: true))
    }
}
