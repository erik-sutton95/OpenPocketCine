import CoreImage
import CoreVideo
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class AssistInspectorLifecycleTests: XCTestCase {
    func testBlockedRenderKeepsItsSlotAcrossActualInspectorDismissalAndRemount() async throws {
        let model = AppModel()
        let clock = InspectorPreviewTestClock(advancesUntilFrozen: true)
        let work = InspectorLifecycleWorkProbe()
        let started = InspectorPreviewTestSignal("First mounted inspector started image work")
        let resumed = InspectorPreviewTestSignal("Remounted inspector received a fresh work slot")
        let finished = InspectorPreviewTestSignal("Blocked image work finished")
        let dismissed = InspectorPreviewTestSignal("Original inspector disappeared")
        let remounted = InspectorPreviewTestSignal("Replacement inspector appeared")
        let remountRequested = InspectorPreviewTestSignal("Replacement inspector requested work")
        let nextRequest = InspectorPreviewTestSignal(
            "Replacement inspector completed its prior request")
        let release = DispatchSemaphore(value: 0)
        let reference = try XCTUnwrap(
            CIContext().createCGImage(
                CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
                from: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let renderer = AssistInspectorImageRenderer(
            now: { clock.now },
            operation: { _, _ in
                let invocation = work.begin()
                defer {
                    work.end()
                    if invocation == 1 { finished.signal() }
                }
                if invocation == 1 {
                    // Initial SwiftUI configuration invalidation can discard a
                    // queued render. Let retries advance until real work enters.
                    clock.freezeAtLastRead()
                    started.signal()
                    XCTAssertEqual(
                        release.wait(timeout: .now() + 10), .success,
                        "Test did not release the mounted inspector's first worker")
                } else if invocation == 2 {
                    resumed.signal()
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
        try await started.wait()
        let admittedAt = clock.now
        probe.onDisappear = { dismissed.signal() }
        probe.onAppear = { remounted.signal() }

        model.assist.configureTool = nil
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await dismissed.wait()
        XCTAssertNil(probe.selected)
        clock.now = admittedAt + 100_000_000
        clock.signalNextRead(remountRequested)
        model.assist.configureTool = .zebra
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await remounted.wait()
        try await remountRequested.wait()
        XCTAssertEqual(probe.mounts, 2, "Exercise real removal/reinsertion, not just tab mutation")
        XCTAssertEqual(probe.selected, .zebra)
        XCTAssertTrue(model.inspectorPreview === renderer)
        XCTAssertEqual(work.count, 1, "Remount cannot begin another operation while CI is blocked")

        // Stay below the original admission deadline when releasing CI: rejected
        // requests cannot queue to run automatically behind the canceled work.
        release.signal()
        try await finished.wait()
        // The real remounted updateImage loop awaits render before asking for
        // another admission. Its next clock read therefore follows completion
        // of any incorrectly queued remount work, which must fail count == 1.
        // Keep time below the deadline until that caller-loop barrier arrives.
        clock.signalNextRead(nextRequest)
        try await nextRequest.wait()
        XCTAssertEqual(work.count, 1, "Rejected requests must not queue behind the worker")
        clock.now = admittedAt + 200_000_000
        try await resumed.wait()
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
    var onAppear: (() -> Void)?
    var onDisappear: (() -> Void)?
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
                    probe.onAppear?()
                }
                .onChange(of: tool) { _, selected in probe.selected = selected }
                .onDisappear {
                    probe.selected = nil
                    probe.onDisappear?()
                }
            }
        }
        .environment(model)
        .frame(width: viewport.width, height: viewport.height)
    }
}
