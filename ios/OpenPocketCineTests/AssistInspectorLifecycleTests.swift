import CoreImage
import CoreVideo
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class AssistInspectorLifecycleTests: XCTestCase {
    func testBlockedRenderKeepsItsSlotAcrossActualInspectorDismissalAndRemount() async throws {
        let model = AppModel()
        let clock = InspectorPreviewTestClock()
        let work = InspectorLifecycleWorkProbe()
        let started = expectation(description: "First mounted inspector started image work")
        let resumed = expectation(description: "Remounted inspector received a fresh work slot")
        let release = DispatchSemaphore(value: 0)
        let reference = try XCTUnwrap(
            CIContext().createCGImage(
                CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
                from: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let renderer = AssistInspectorImageRenderer(
            now: { clock.now },
            operation: { _, _ in
                let invocation = work.begin()
                defer { work.end() }
                if invocation == 1 {
                    started.fulfill()
                    _ = release.wait(timeout: .now() + 5)
                } else if invocation == 2 {
                    resumed.fulfill()
                }
                return reference
            })
        model.inspectorPreview = renderer
        var source: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &source),
            kCVReturnSuccess)
        model.monitorSamples.publish(
            source: try XCTUnwrap(source), transfer: .rec709, colorMode: .normal, bundle: nil)
        let size = CGSize(width: 874, height: 402)
        let probe = InspectorLifecycleProbe()
        let host = UIHostingController(
            rootView: InspectorLifecycleHost(model: model, viewport: size, probe: probe)
                .environment(\.scenePhase, .active))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            release.signal()
            model.assist.configureTool = nil
            model.monitorSamples.reset()
            window.isHidden = true
            window.rootViewController = nil
        }
        model.assist.configureTool = .peaking
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await fulfillment(of: [started], timeout: 2)

        model.assist.configureTool = nil
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(probe.selected)
        clock.now = 100_000_000
        model.assist.configureTool = .zebra
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(probe.mounts, 2, "Exercise real removal/reinsertion, not just tab mutation")
        XCTAssertEqual(probe.selected, .zebra)
        XCTAssertTrue(model.inspectorPreview === renderer)
        XCTAssertEqual(work.count, 1, "Remount cannot begin another operation while CI is blocked")

        // Stay below the original admission deadline when releasing CI: rejected
        // requests cannot queue to run automatically behind the canceled work.
        release.signal()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(work.count, 1, "Rejected requests must not queue behind the worker")
        clock.now = 200_000_000
        await fulfillment(of: [resumed], timeout: 2)
        XCTAssertEqual(work.count, 2)
        XCTAssertEqual(work.maximumConcurrent, 1)
        XCTAssertFalse(model.session.holdsMonitor)
    }

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

private final class InspectorLifecycleWorkProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations = 0
    private var running = 0
    private var maximum = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocations
    }

    var maximumConcurrent: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximum
    }

    func begin() -> Int {
        lock.lock()
        defer { lock.unlock() }
        invocations += 1
        running += 1
        maximum = max(maximum, running)
        return invocations
    }

    func end() {
        lock.lock()
        defer { lock.unlock() }
        running -= 1
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
