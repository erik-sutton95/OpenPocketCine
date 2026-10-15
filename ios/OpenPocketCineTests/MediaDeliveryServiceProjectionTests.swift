import OpenCineAppKit
import XCTest

@testable import OpenPocketCine

/// The shared destination and progress copy Pocket shows for its Frame.io service.
@MainActor
final class MediaDeliveryServiceProjectionTests: XCTestCase {
    func testRemoteDestinationNamesFrameio() {
        XCTAssertEqual(MonitorDeliveryDestination.remoteUpload.title(remoteDisplayName: "Frame.io"), "Frame.io")
        XCTAssertEqual(
            MonitorDeliveryDestination.remoteUpload.subtitle(remoteDisplayName: "Frame.io"),
            "Upload to your Frame.io project")
    }
    func testRemoteCaptionProjectsIntoTheSharedProgress() {
        let progress = MonitorDeliveryBatchProgress(destination: .remoteUpload, totalClips: 1,
            clipIndex: 1, clipFraction: 0.6, uploadCaption: "Uploading to Frame.io")
        XCTAssertEqual(progress.statusLine(), "Uploading to Frame.io 60%")
    }
}
