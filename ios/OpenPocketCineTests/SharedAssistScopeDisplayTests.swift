import MetalKit
import MonitorUI
import OpenCineAppKitApple
import SwiftUI
import XCTest

@testable import OpenPocketCine

// SIMULATED real shared view construction/update; physical EDR and pixels remain untested.
@MainActor
final class SharedAssistScopeDisplayTests: XCTestCase {
    override func tearDown() {
        LiveHDRDisplay.app.setScreenCaptured(false)
        LiveHDRDisplay.app.setEnabled(false)
        super.tearDown()
    }

    func testSharedWaveformViewUsesPocketHDRAndCapturePolicyOnUpdates() throws {
        try exercise(trace: true) { revision, display in
            AnyView(
                MonitorWaveformScopePlot(
                    samples: .empty, mode: .waveform(.rgb), transfer: .dlog2,
                    clipByte: 247, revision: revision, intensity: 1,
                    size: CGSize(width: 250, height: 153), configureDisplay: display))
        }
    }

    func testSharedParadeViewUsesPocketHDRAndCapturePolicyOnUpdates() throws {
        try exercise(trace: true) { revision, display in
            AnyView(
                MonitorWaveformScopePlot(
                    samples: .empty, mode: .parade(.rgb), transfer: .dlog2,
                    clipByte: 247, revision: revision, intensity: 1,
                    size: CGSize(width: 250, height: 153), configureDisplay: display))
        }
    }

    func testSharedVectorscopeViewUsesPocketHDRAndCapturePolicyOnUpdates() throws {
        try exercise(trace: false) { revision, display in
            AnyView(
                MonitorVectorscopeScopePlot(
                    points: [], revision: revision, configureDisplay: display))
        }
    }

    private func exercise(
        trace: Bool,
        plot: (UInt64, @escaping @MainActor (MTKView) -> MonitorScopeDisplayOptions) -> AnyView
    ) throws {
        try XCTSkipIf(
            !MonitorScopeTraceMetal.isAvailable, "Shared native scope pipeline unavailable")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 250, height: 153))
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        var originalView: MTKView?
        for (index, policy) in [(false, false), (true, false), (true, true), (false, false)]
            .enumerated()
        {
            LiveHDRDisplay.app.setEnabled(policy.0)
            LiveHDRDisplay.app.setScreenCaptured(policy.1)
            let configured = expectation(description: "shared scope display update \(index)")
            var observedView: MTKView?
            var options: MonitorScopeDisplayOptions?
            host.rootView = plot(UInt64(index)) { view in
                let next = scopeDisplay(view)
                if observedView == nil {
                    observedView = view
                    options = next
                    configured.fulfill()
                }
                return next
            }
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            window.layoutIfNeeded()
            wait(for: [configured], timeout: 2)
            let view = try XCTUnwrap(observedView)
            let selected = try XCTUnwrap(options)
            if let originalView {
                XCTAssertTrue(view === originalView)
            } else {
                originalView = view
            }
            let enabled = policy.0 && !policy.1
            XCTAssertEqual(selected.hdr, enabled)
            XCTAssertEqual(selected.gain, LiveHDRDisplay.app.presentGain, accuracy: 0.001)
            XCTAssertEqual(view.colorPixelFormat, enabled ? .rgba16Float : .bgra8Unorm)
            let layer = try XCTUnwrap(view.layer as? CAMetalLayer)
            XCTAssertEqual(layer.wantsExtendedDynamicRangeContent, enabled)
            XCTAssertEqual(
                layer.colorspace?.name,
                enabled ? CGColorSpace.extendedLinearDisplayP3 : nil)
            if trace {
                XCTAssertTrue(view.delegate is MonitorScopeTraceRenderer)
            } else {
                XCTAssertTrue(view.delegate is MonitorVectorscopeMetalRenderer)
            }
        }
    }
}
