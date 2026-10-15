import OpenCineFrameIOApple
import XCTest

@testable import OpenPocketCine

/// OPTIONAL-01 and A2-57: the shared Frame.io account keeps Pocket's own keychain item,
/// destination key and history key. Changing one signs every operator out or forgets their
/// project.
@MainActor final class FrameioCredentialsTests: XCTestCase {
    func testTokenDestinationAndHistoryStayInPocketNamespaces() {
        let model = AppModel()
        defer { model.session.disconnect() }
        XCTAssertEqual(model.frameio.tokens.service, "OpenPocketCine.frameio")
        XCTAssertEqual(model.frameio.tokens.account, "oauth-token")
        XCTAssertEqual(model.frameio.destinations.key, "opc.frameio.destination.v1")
        XCTAssertEqual(FrameioHostNamespace.openPocketCine.historyKey, "opc.frameio.uploaded.v1")
    }
}
