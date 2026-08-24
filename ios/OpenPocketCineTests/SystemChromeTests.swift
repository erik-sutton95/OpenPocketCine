import XCTest

@testable import OpenPocketCine

/// iPad used to keep the system time / battery bar. The hosting controller
/// prefers hidden, and the plist has an iPad-specific key for launch.
final class SystemChromeTests: XCTestCase {
    func testInfoPlistHidesTheSystemStatusBarOnIPhoneAndIPad() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "UIStatusBarHidden") as? Bool, true)
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "UIStatusBarHidden~ipad") as? Bool, true)
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "UIViewControllerBasedStatusBarAppearance")
                as? Bool, true)
    }
}
