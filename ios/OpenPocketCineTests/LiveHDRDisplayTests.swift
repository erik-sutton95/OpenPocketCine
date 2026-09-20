import XCTest

@testable import OpenPocketCine

final class LiveHDRDisplayTests: XCTestCase {
    override func tearDown() {
        LiveHDRDisplay.setScreenCaptured(false)
        LiveHDRDisplay.setChromeActive(false)
        LiveHDRDisplay.setEnabled(false)
        super.tearDown()
    }

    func testGainIsOneWhenDisabled() {
        XCTAssertEqual(LiveHDRDisplay.displayGain(enabled: false, potentialHeadroom: 8), 1)
        XCTAssertEqual(LiveHDRDisplay.displayGain(enabled: false, potentialHeadroom: 1), 1)
    }

    func testGainUsesRequestedHeadroomWhenThePanelHasRoom() {
        XCTAssertEqual(
            LiveHDRDisplay.displayGain(enabled: true, potentialHeadroom: 8),
            Float(LiveHDRDisplay.requestedHeadroom))
        XCTAssertEqual(LiveHDRDisplay.requestedHeadroom, 3, accuracy: 0.001)
    }

    func testGainDoesNotExceedPanelPotential() {
        XCTAssertEqual(
            LiveHDRDisplay.displayGain(enabled: true, potentialHeadroom: 1.4), 1.4, accuracy: 0.001)
        XCTAssertEqual(LiveHDRDisplay.displayGain(enabled: true, potentialHeadroom: 1), 1)
    }

    func testNonFinitePotentialFallsBackToOne() {
        XCTAssertEqual(LiveHDRDisplay.displayGain(enabled: true, potentialHeadroom: .nan), 1)
        XCTAssertEqual(
            LiveHDRDisplay.displayGain(enabled: true, potentialHeadroom: .infinity), 1)
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

    func testHelpCopyDisambiguatesCameraHDR() {
        XCTAssertTrue(SettingsHelpCopy.hdrDisplay.contains("HDR/HLG"))
        XCTAssertTrue(SettingsHelpCopy.hdrDisplay.contains("Off by default"))
        XCTAssertTrue(SettingsHelpCopy.hdrDisplay.contains("decoded camera signal"))
        XCTAssertTrue(SettingsHelpCopy.hdrDisplay.contains("Screen recording"))
        XCTAssertFalse(SettingsHelpCopy.hdrDisplay.localizedCaseInsensitiveContains("OpenZCine"))
        XCTAssertFalse(SettingsHelpCopy.hdrDisplay.localizedCaseInsensitiveContains("Nikon"))
    }
}
