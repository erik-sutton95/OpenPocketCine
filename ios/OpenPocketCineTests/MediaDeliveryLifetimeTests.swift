import XCTest

@testable import OpenPocketCine

@MainActor
final class MediaDeliveryLifetimeTests: XCTestCase {
    func testFrameioPreflightRejectionRestoresTransferredHop() async {
        let model = AppModel()
        // Simulate the popup's already-completed handoff without leaving any
        // Wi-Fi network. The fixture has no camera or credentials to rejoin.
        model.internetHopActive = true
        let request = MediaDeliveryBeginRequest(
            files: [], destination: .frameio, configuration: .init())

        let outcome = await MediaDeliveryRunner.execute(request: request, model: model) { _ in
            XCTFail("An empty request must fail before presenting progress")
        }

        guard case .failed = outcome else {
            return XCTFail("An empty request must fail preflight")
        }
        XCTAssertFalse(
            model.internetHopActive, "Preflight failure must release the transferred hop")
    }

    func testNativePreflightDoesNotAdoptUnrelatedInternetHop() async {
        let model = AppModel()
        model.internetHopActive = true
        let request = MediaDeliveryBeginRequest(
            files: [], destination: .nativeShare, configuration: .init())

        _ = await MediaDeliveryRunner.execute(request: request, model: model) { _ in }

        XCTAssertTrue(model.internetHopActive, "Native export never owns an internet hop")
        model.internetHopActive = false
    }
}
