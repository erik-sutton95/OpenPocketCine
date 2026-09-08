import SwiftUI
import XCTest

@testable import OpenPocketCine

final class WatcherPresentationTests: XCTestCase {
    @MainActor
    func testMonitorToolsUseWatcherSamplesAndTransfer() {
        let model = AppModel()
        model.isWatchingFeed = true
        model.session.status.colorMode = .normal
        model.relayClient.state.color = "D-Log2"
        XCTAssertTrue(model.monitorSamples === model.relayClient.samples)
        XCTAssertEqual(model.monitorColorMode, .dLog2)
        XCTAssertEqual(model.monitorTransfer, .dlog2)
        model.isWatchingFeed = false
        XCTAssertTrue(model.monitorSamples === model.frameSamples)
        XCTAssertEqual(model.monitorColorMode, .normal)
    }

    /// Render the actual SwiftUI/UIKit monitor for visual review without BLE or camera I/O.
    @MainActor
    func testWatcherMonitorRendersAtPhoneAndTabletSizes() async throws {
        for (name, size) in [
            ("ipad-landscape", CGSize(width: 1194, height: 834)),
            ("iphone-portrait", CGSize(width: 402, height: 874)),
            ("iphone-landscape", CGSize(width: 874, height: 402)),
        ] {
            let model = AppModel()
            model.isWatchingFeed = true
            model.relayClient.status = .live
            model.relayClient.hostTitle = "Camera A · Pocket 4 Pro"
            model.relayClient.receivedFPS = 25
            model.relayClient.state.cameraName = "Camera A"
            model.relayClient.state.cameraModel = "Osmo Pocket 4 Pro"
            model.relayClient.state.format = "4K 25p"
            model.relayClient.state.color = "D-Log2"
            model.relayClient.state.shutter = "1/50"
            model.relayClient.state.iso = "400"
            model.relayClient.state.zoom = "1×"
            model.relayClient.state.batteryPercent = 82
            model.relayClient.state.isRecording = true
            model.assist.configureTool = nil
            let view = WatcherLiveView().environment(model)
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                controller.view.drawHierarchy(
                    in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
                "watcher-layout-\(name).png")
            try XCTUnwrap(rendered.pngData()).write(to: file)
            XCTAssertEqual(rendered.size, size)
            XCTAssertFalse(
                model.session.holdsMonitor, "Rendering a watcher must not open a camera session")
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "watcher-layout-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            window.rootViewController = nil
        }
    }
}
