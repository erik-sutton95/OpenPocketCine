import XCTest

@testable import OpenPocketCine

/// iPad used to keep the system time / battery bar. The hosting controller
/// prefers hidden, and the plist has an iPad-specific key for launch.
final class SystemChromeTests: XCTestCase {
    func testInfoPlistHidesTheSystemStatusBarOnIPhoneAndIPad() throws {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "UIStatusBarHidden") as? Bool, true)
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "UIViewControllerBasedStatusBarAppearance")
                as? Bool, true)
        // `object(forInfoDictionaryKey:)` drops `~ipad` variants on iPhone. The merged
        // Info.plist inside the built app is what iPad reads at launch; the source tree
        // path does not exist inside a device bundle.
        let source = Bundle.main.bundleURL.appendingPathComponent("Info.plist")
        let raw = try XCTUnwrap(NSDictionary(contentsOf: source))
        XCTAssertEqual(raw["UIStatusBarHidden"] as? Bool, true)
        XCTAssertEqual(raw["UIStatusBarHidden~ipad"] as? Bool, true)
    }
}
