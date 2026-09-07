import CoreImage
import OpenPocketViewCore
import UIKit
import XCTest

@testable import OpenPocketCine

final class WatchRelayTests: XCTestCase {
    func testThumbnailFromSolidImageIsNonEmpty() {
        let color = CIColor(red: 0.2, green: 0.4, blue: 0.6)
        let image = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let data = WatchRelay.thumbnailData(from: image, maxWidth: 512, quality: 0.5)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 32)
        XCTAssertNotNil(data.flatMap { UIImage(data: $0) })
    }

    func testWatchShutterCopyIsOperatorFacing() {
        for text in [
            WatchRelayCopy.openOnIPhone,
            WatchRelayCopy.connectFirst,
            WatchRelayCopy.switchToVideo,
            WatchRelayCopy.switchToPhoto,
            WatchRelayCopy.busy,
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("OpenZCine"))
            XCTAssertFalse(text.localizedCaseInsensitiveContains("Nikon"))
        }
    }
}
