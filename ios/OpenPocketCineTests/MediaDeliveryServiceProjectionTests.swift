import XCTest
import OpenCineAppKit
@testable import OpenPocketCine

@MainActor
final class MediaDeliveryServiceProjectionTests: XCTestCase {
    func testStoredDestinationAndActualServiceContentStayCompatible() {
        XCTAssertEqual(MediaDeliveryDestination.frameio.rawValue, "frameio")
        XCTAssertEqual(MediaDeliveryDestination.frameio.shared, .remoteUpload)
        XCTAssertEqual(MediaDeliveryDestination(.remoteUpload), .frameio)
        XCTAssertEqual(MediaDeliveryDestination.frameio.title, "Frame.io")
        XCTAssertEqual(MediaDeliveryDestination.frameio.subtitle, "Upload to your Frame.io project")
    }
    func testRemoteCaptionAndLegacyOptionProjectIntoNeutralValues() {
        let progress = MediaDeliveryOverlayState(destination: .frameio, totalClips: 1,
            clipIndex: 1, clipFraction: 0.6, uploadCaption: "Uploading to Frame.io")
        XCTAssertEqual(progress.statusLine, "Uploading to Frame.io 60%")
        XCTAssertEqual(progress.statusLine(), "Uploading to Frame.io 60%")
        var configuration = MediaDeliveryConfiguration()
        configuration.forceFrameioReupload = true
        XCTAssertTrue(configuration.forceReupload)
        configuration.forceReupload = false
        XCTAssertFalse(configuration.forceFrameioReupload)
    }
}
