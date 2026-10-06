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

    func testSingleSetupCanBeRenamedAndCleared() {
        app.launch()
        let chip = app.buttons.matching(
            NSPredicate(format: "label == %@", "Connect Travel camera over Camera Wi-Fi")
        ).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.press(forDuration: 0.8)
        app.buttons["Rename setup"].tap()
        let dialog = app.alerts["Rename setup"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        let field = dialog.textFields.firstMatch
        field.tap()
        field.typeText(
            String(
                repeating: XCUIKeyboardKey.delete.rawValue,
                count: (field.value as? String ?? "").count))
        field.typeText("Location A")
        dialog.buttons["Save"].tap()
        let renamed = app.buttons.matching(
            NSPredicate(format: "label == %@", "Connect Travel camera over Location A")
        ).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        capture("single-setup-renamed")
        renamed.press(forDuration: 0.8)
        app.buttons["Rename setup"].tap()
        let clearField = app.alerts["Rename setup"].textFields.firstMatch
        clearField.tap()
        clearField.typeText(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Location A".count))
        app.alerts["Rename setup"].buttons["Save"].tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        capture("single-setup-default-restored")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
