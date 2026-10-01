import OpenCineFrameIO
import XCTest

@testable import OpenPocketCine

/// OPTIONAL-01: Frame.io logic comes from OpenCineFrameIO, but the sign-in stays in Pocket's
/// own keychain item. Changing either value signs every operator out.
final class FrameioCredentialsTests: XCTestCase {
    func testTokenStaysInPocketKeychainNamespace() {
        XCTAssertEqual(FrameioTokenStore.service, "OpenPocketCine.frameio")
        XCTAssertEqual(FrameioTokenStore.account, "oauth-token")
    }
}
