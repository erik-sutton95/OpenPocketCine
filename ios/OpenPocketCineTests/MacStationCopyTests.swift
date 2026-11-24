import XCTest

@testable import OpenPocketCine

/// The Mac module's words when the camera joined the Mac's network but cannot be found there.
@MainActor
final class MacStationCopyTests: XCTestCase {
    func testMacNotFoundNamesTheNetworkTheCauseAndTheWiFi7Quirk() {
        let text = CameraSession.Fail.macStationCameraMissing("Studio")
        XCTAssertTrue(text.hasPrefix("The camera joined Studio but this Mac cannot reach it."), text)
        XCTAssertTrue(text.contains("guest networks"), text)
        XCTAssertTrue(text.contains("MLO"), "Pocket 4 Pro on Wi-Fi 7 routers: \(text)")
    }
}
