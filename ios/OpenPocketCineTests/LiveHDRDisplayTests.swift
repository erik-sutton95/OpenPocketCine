import XCTest

@testable import OpenPocketCine

final class LiveHDRDisplayTests: XCTestCase {
    override func tearDown() {
        LiveHDRDisplay.setScreenCaptured(false)
        LiveHDRDisplay.setChromeActive(false)
        LiveHDRDisplay.setEnabled(false)
        super.tearDown()
    }

    func testDisplayGainIsRequestedHeadroomCappedByThePanel() {
        XCTAssertEqual(LiveHDRDisplay.requestedHeadroom, 3, accuracy: 0.001)
        let cases: [(name: String, enabled: Bool, potential: CGFloat, expected: Float)] = [
            ("disabled on an HDR panel", false, 8, 1),
            ("disabled on an SDR panel", false, 1, 1),
            ("panel has room", true, 8, Float(LiveHDRDisplay.requestedHeadroom)),
            ("panel potential caps the gain", true, 1.4, 1.4),
            ("SDR panel", true, 1, 1),
            ("NaN potential falls back to one", true, .nan, 1),
            ("infinite potential falls back to one", true, .infinity, 1),
        ]
        for c in cases {
            XCTAssertEqual(
                LiveHDRDisplay.displayGain(enabled: c.enabled, potentialHeadroom: c.potential),
                c.expected, accuracy: 0.001, c.name)
        }
    }

    func testDrawableFormatIsFloatOnlyWhileEnabled() {
        XCTAssertEqual(LiveHDRDisplay.drawablePixelFormat(enabled: false), .bgra8Unorm)
        XCTAssertEqual(LiveHDRDisplay.drawablePixelFormat(enabled: true), .rgba16Float)
        XCTAssertEqual(LiveHDRDisplay.bakePixelFormat, .bgra8Unorm)
    }

    func testChromeGainFollowsThePreference() {
        LiveHDRDisplay.setScreenCaptured(false)
        LiveHDRDisplay.setEnabled(true)
        XCTAssertEqual(LiveHDRDisplay.chromeGain, LiveHDRDisplay.presentGain)
        LiveHDRDisplay.setEnabled(false)
        XCTAssertEqual(LiveHDRDisplay.chromeGain, 1)
    }

    func testScreenCaptureDisablesEffectiveHDR() {
        XCTAssertTrue(LiveHDRDisplay.isEffective(preferred: true, screenCaptured: false))
        XCTAssertFalse(LiveHDRDisplay.isEffective(preferred: true, screenCaptured: true))
        XCTAssertFalse(LiveHDRDisplay.isEffective(preferred: false, screenCaptured: false))
        LiveHDRDisplay.setScreenCaptured(false)
        LiveHDRDisplay.setEnabled(true)
        XCTAssertTrue(LiveHDRDisplay.isEnabled)
        LiveHDRDisplay.setScreenCaptured(true)
        XCTAssertFalse(LiveHDRDisplay.isEnabled)
        XCTAssertEqual(LiveHDRDisplay.presentGain, 1)
        LiveHDRDisplay.setScreenCaptured(false)
        XCTAssertTrue(LiveHDRDisplay.isEnabled)
    }
}
