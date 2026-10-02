import XCTest

/// The shared page's app-owned legal destinations and a single saved camera setup.
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

    func testLegalDocumentsReturnToSavedAndFirstPairPages() {
        for state in ["saved-nearby", "empty"] {
            app.launchEnvironment["OPV_UI_REVIEW_STATE"] = state
            app.launch()
            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
                XCUIDevice.shared.orientation = orientation
                let landscape = orientation != .portrait
                let rotated = NSPredicate { _, _ in
                    (self.app.frame.width > self.app.frame.height) == landscape
                }
                expectation(for: rotated, evaluatedWith: app)
                waitForExpectations(timeout: 10)
                for kind in ["privacy", "terms"] {
                    let link = app.buttons["legal.\(kind)"]
                    XCTAssertTrue(link.waitForExistence(timeout: 10))
                    XCTAssertTrue(link.isHittable)
                    XCTAssertGreaterThanOrEqual(link.frame.height, 44)
                    XCTAssertGreaterThanOrEqual(link.frame.minX, 0)
                    XCTAssertLessThanOrEqual(link.frame.maxX, app.frame.maxX)
                    XCTAssertLessThanOrEqual(link.frame.maxY, app.frame.maxY)
                    capture("\(state)-\(orientation.rawValue)-links")
                    link.tap()
                    let close = app.buttons["Close"].firstMatch
                    XCTAssertTrue(close.waitForExistence(timeout: 5))
                    XCTAssertTrue(app.staticTexts[kind.capitalized].exists)
                    capture("\(state)-\(orientation.rawValue)-\(kind)")
                    close.tap()
                    XCTAssertTrue(link.waitForExistence(timeout: 5))
                    XCTAssertTrue(link.isHittable)
                }
            }
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
