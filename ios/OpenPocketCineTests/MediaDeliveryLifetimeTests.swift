import OpenCineAppKit
import OpenCineCameraControls
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class MediaDeliveryLifetimeTests: XCTestCase {
    func testFrameioPreflightRejectionRestoresTheTransferredHop() async {
        let model = AppModel()
        defer { model.delivery.close(); model.session.disconnect() }
        // The popup's already-completed handoff, without leaving any Wi-Fi network: the
        // fixture has no camera or credentials to rejoin.
        let internet = model.internetHop.deliveryService(route: { model.hopRoute })
        let token = internet.begin()
        XCTAssertNotNil(token)
        let outcome = await model.delivery.run(
            records: [MediaFile](), destination: .remoteUpload, action: .systemShare, admission: .init { true },
            source: .init(
                originals: model.clipLibrary().originals, still: { _ in nil }, export: { _, _, _ in nil },
                filename: \.filename, metadata: { _ in nil }),
            includeMetadata: false, remote: nil, internet: internet, lease: token
        ) { _ in XCTFail("An empty request must fail before presenting progress") }
        guard case .failed = outcome else { return XCTFail("An empty request must fail preflight") }
        XCTAssertFalse(model.internetHop.isActive, "Preflight failure must release the transferred hop")
    }

    func testNativePreflightDoesNotAdoptAnUnrelatedHop() async {
        let model = AppModel()
        defer { model.delivery.close(); model.session.disconnect() }
        let token = model.internetHop.begin(model.hopRoute)
        let outcome = await model.delivery.run(
            records: [MediaFile](), destination: .nativeShare, action: .systemShare, admission: .init { true },
            source: .init(
                originals: model.clipLibrary().originals, still: { _ in nil }, export: { _, _, _ in nil },
                filename: \.filename, metadata: { _ in nil }),
            includeMetadata: false, remote: nil,
            internet: model.internetHop.deliveryService(route: { model.hopRoute }),
            lease: MonitorInternetHop<PocketHopRoute>.Token?.none
        ) { _ in }
        guard case .failed = outcome else { return XCTFail("An empty request must fail preflight") }
        XCTAssertTrue(model.internetHop.isActive, "Native export never owns an internet hop")
        if let token { _ = model.internetHop.end(token) }
    }
}
