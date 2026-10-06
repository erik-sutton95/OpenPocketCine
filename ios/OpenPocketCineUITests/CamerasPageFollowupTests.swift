import XCTest

/// A single saved camera setup on the shared page. Main has no legal links on the cameras
/// pages, so the app passes none (ui-tests-2 lane).
final class CamerasPageFollowupTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "cameras"
    }

    override func tearDown() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    /// Main's setup menu has no Rename setup (a single camera Wi-Fi setup has no Forget either).
    func testASetupOffersNoRename() {
        app.launch()
        let chip = app.buttons.matching(
            NSPredicate(format: "label == %@", "Connect Travel camera over Camera Wi-Fi")
        ).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.press(forDuration: 0.8)
        XCTAssertFalse(app.buttons["Rename setup"].waitForExistence(timeout: 2))
        capture("single-setup-menu")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
