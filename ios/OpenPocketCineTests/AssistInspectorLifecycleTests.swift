import CoreVideo
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class AssistInspectorLifecycleTests: XCTestCase {
    /// Hosts the production inspector, including its native menus, scope views
    /// and cancellable image renderer. No decoder or camera session is attached.
    func testRapidTabSwitchingAndRemountingKeepsTheSelectedInspectorAlive() async throws {
        let model = AppModel()
        let size = CGSize(width: 874, height: 402)
        let probe = InspectorLifecycleProbe()
        var source: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &source),
            kCVReturnSuccess)
        let buffer = try XCTUnwrap(source)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 128, CVPixelBufferGetBytesPerRow(buffer) * 180)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        model.monitorSamples.publish(
            source: buffer, transfer: .rec709, colorMode: .normal, bundle: nil)
        var publicationCount = 0
        let publication = Task { @MainActor in
            while !Task.isCancelled {
                model.monitorSamples.publish(
                    source: buffer, transfer: .rec709, colorMode: .normal, bundle: nil)
                publicationCount += 1
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
        let host = UIHostingController(
            rootView: InspectorLifecycleHost(model: model, viewport: size, probe: probe))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            publication.cancel()
            model.assist.configureTool = nil
            model.monitorSamples.reset()
            window.isHidden = true
            window.rootViewController = nil
        }
        let tools = LiveAssistTool.settingsCases.filter(\.hasConfiguration)
        for cycle in 0..<12 {
            for tool in tools {
                model.assist.configureTool = tool
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                // One real main-run-loop transaction per input, faster than
                // human tapping while still mounting each selected tool.
                try await Task.sleep(for: .milliseconds(20))
                XCTAssertEqual(probe.selected, tool, "cycle \(cycle), tool \(tool.rawValue)")
                XCTAssertTrue(host.view.window === window)
            }
            model.assist.configureTool = nil
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertNil(probe.selected, "Dismissal must tear down the mounted inspector")
        }
        XCTAssertGreaterThan(publicationCount, tools.count * 12)
        publication.cancel()
        await publication.value
        XCTAssertEqual(probe.mounts, 12)
        XCTAssertFalse(model.session.holdsMonitor)
    }
}

@MainActor
private final class InspectorLifecycleProbe {
    var selected: LiveAssistTool?
    var mounts = 0
}

private struct InspectorLifecycleHost: View {
    var model: AppModel
    let viewport: CGSize
    let probe: InspectorLifecycleProbe

    var body: some View {
        Group {
            if let tool = model.assist.configureTool {
                AssistLongPressOverlay(
                    tool: tool, assist: model.assist, anchor: .zero, viewport: viewport,
                    onDismiss: { model.assist.configureTool = nil }
                )
                .onAppear {
                    probe.mounts += 1
                    probe.selected = tool
                }
                .onChange(of: tool) { _, selected in probe.selected = selected }
                .onDisappear { probe.selected = nil }
            }
        }
        .environment(model)
        .frame(width: viewport.width, height: viewport.height)
    }
}
