import CoreImage
import CoreVideo
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class AssistInspectorPreviewTests: XCTestCase {
    func testInspectorRequestsSamplingWithoutEnablingPictureEffects() {
        let original = LiveImageEffects()
        let image = original.withInspectorDemand(.peaking)
        XCTAssertTrue(image.needsSample)
        XCTAssertFalse(image.needsGPUFeed)
        XCTAssertFalse(image.needsScopes)
        XCTAssertFalse(image.faceAF)
        XCTAssertFalse(image.peaking)
        XCTAssertFalse(original.needsSample)

        var activeHistogram = original
        activeHistogram.histogram = true
        let scope = activeHistogram.withInspectorDemand(.waveform)
        XCTAssertEqual(scope.activeScopeCount, 2)
        XCTAssertTrue(scope.histogram)
        XCTAssertTrue(scope.waveform)
        XCTAssertFalse(scope.needsGPUFeed)
    }

    func testScopeDemandBelongsToTheVisibleSourceAndEndsOnDismiss() {
        let assist = LiveAssistState()
        assist.waveform = false
        assist.configureTool = .waveform
        XCTAssertFalse(assist.isOn(.waveform))
        XCTAssertFalse(assist.isVisible(.waveform))
        XCTAssertTrue(assist.effects.waveform)
        XCTAssertFalse(assist.playbackEffects.waveform)
        assist.gradesClip = true
        XCTAssertFalse(assist.effects.waveform, "Playback must not demand a hidden live scope")
        XCTAssertTrue(assist.playbackEffects.waveform)
        assist.configureTool = nil
        XCTAssertFalse(assist.effects.waveform)
        XCTAssertFalse(assist.playbackEffects.waveform)
    }

    func testImageSamplingBelongsToTheActiveInspectorAndStopsWhenInactive() {
        let assist = LiveAssistState()
        assist.configureTool = .peaking
        XCTAssertTrue(assist.effects.inspectorSample)
        XCTAssertFalse(assist.playbackEffects.inspectorSample)
        assist.gradesClip = true
        XCTAssertFalse(assist.effects.inspectorSample)
        XCTAssertTrue(assist.playbackEffects.inspectorSample)
        assist.inspectorSceneActive = false
        XCTAssertFalse(assist.effects.inspectorSample)
        XCTAssertFalse(assist.playbackEffects.inspectorSample)
        assist.configureTool = .waveform
        assist.waveform = false
        assist.playbackVisibleTools = []
        XCTAssertFalse(assist.effects.waveform)
        XCTAssertFalse(assist.playbackEffects.waveform)
        assist.inspectorSceneActive = true
        XCTAssertTrue(assist.playbackEffects.waveform)
        XCTAssertFalse(assist.effects.waveform)
    }

    func testImagePreviewForcesOnlyTheSelectedWarningWithoutChangingMainEnablement() {
        let assist = LiveAssistState()
        assist.peaking = false
        assist.falseColor = false
        assist.zebra = true
        let preview = AssistInspectorPreviewPolicy.imageEffects(
            assist: assist, tool: .peaking, transfer: .dlog2)
        XCTAssertTrue(preview.peaking)
        XCTAssertFalse(preview.zebra)
        XCTAssertFalse(preview.falseColor)
        XCTAssertEqual(preview.colorMode, .dLog2)
        XCTAssertFalse(preview.inspectorSample)
        XCTAssertFalse(assist.peaking)
        XCTAssertTrue(assist.zebra)
    }

    func testPreviewImageIsBoundedBeforeRendering() async throws {
        let renderer = AssistInspectorImageRenderer()
        let owner = UUID()
        renderer.activate(owner: owner)
        let buffer = try Self.buffer(width: 640, height: 360)
        let result = await renderer.render(
            owner: owner, source: buffer, effects: { LiveImageEffects() })
        XCTAssertEqual(result?.image.width, 320)
        XCTAssertEqual(result?.image.height, 180)
    }

    func testObservedPreviewOptionsIncludeDisabledPictureToolSettings() {
        let assist = LiveAssistState()
        assist.lutEnabled = false
        assist.splitComparison = false
        let beforeSplit = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .lut, transfer: .rec709)
        assist.splitComparison = true
        let afterSplit = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .lut, transfer: .rec709)
        XCTAssertNotEqual(beforeSplit, afterSplit)
        XCTAssertTrue(afterSplit.splitComparison)
        XCTAssertEqual(afterSplit.lutDimension, 0, "Observation must not prepare a preview LUT")

        assist.desqueezeFactor = 1.33
        let beforeStretch = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .desqueeze, transfer: .rec709)
        assist.desqueezeFactor = 2
        let afterStretch = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .desqueeze, transfer: .rec709)
        XCTAssertNotEqual(beforeStretch, afterStretch)
        XCTAssertEqual(afterStretch.desqueezeFactor, 2)
    }

    func testLUTPreviewResolvesTheSelectedLookWhileMainLUTRemainsOff() {
        let assist = LiveAssistState()
        assist.lutEnabled = false
        assist.lutSelection = .creativeMono
        assist.refreshLUTCube()
        assist.configureTool = .lut
        XCTAssertEqual(assist.effects.lutDimension, 0)
        let preview = AssistInspectorPreviewPolicy.imageEffects(
            assist: assist, tool: .lut, transfer: .rec709)
        XCTAssertGreaterThan(preview.lutDimension, 1)
        XCTAssertFalse(preview.lutRGBA.isEmpty)
        XCTAssertFalse(assist.lutEnabled)
        XCTAssertEqual(assist.effects.lutDimension, 0)
        assist.configureTool = nil
        XCTAssertFalse(assist.effects.inspectorSample)
    }

    func testBusyPreviewDropsNewWorkAndCancelledWorkCannotPublish() async throws {
        let started = InspectorPreviewTestSignal("First image work started")
        let release = DispatchSemaphore(value: 0)
        let invocations = InspectorRenderInvocationCounter()
        let clock = InspectorPreviewTestClock()
        let reference = try XCTUnwrap(
            CIContext().createCGImage(
                CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
                from: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let renderer = AssistInspectorImageRenderer(
            now: { clock.now },
            operation: { _, _ in
                if invocations.increment() == 1 {
                    started.signal()
                    XCTAssertEqual(
                        release.wait(timeout: .now() + 10), .success,
                        "Test did not release the first worker; a rejected request may have queued")
                }
                return reference
            })
        let owner = UUID()
        let remountedOwner = UUID()
        renderer.activate(owner: owner)
        let buffer = try Self.buffer(width: 8, height: 8)
        let first = Task {
            await renderer.render(owner: owner, source: buffer, effects: { LiveImageEffects() })
        }
        defer {
            first.cancel()
            release.signal()
        }
        try await started.wait()
        let dropped = await renderer.render(
            owner: owner, source: buffer, effects: { LiveImageEffects() })
        XCTAssertNil(dropped, "A busy preview must not retain a queued second source")
        XCTAssertEqual(invocations.value, 1, "Dropped work must never enter the renderer")
        first.cancel()
        renderer.deactivate(owner: owner)
        renderer.activate(owner: remountedOwner)
        clock.now = 200_000_000
        let remounted = await renderer.render(
            owner: remountedOwner, source: buffer, effects: { LiveImageEffects() })
        XCTAssertNil(remounted, "Cancellation/remount must not release the running operation")
        XCTAssertEqual(invocations.value, 1)
        release.signal()
        let cancelled = await first.value
        XCTAssertNil(cancelled, "Dismissed inspectors must never adopt completed stale work")
        XCTAssertEqual(invocations.value, 1, "Cancellation must not drain queued work")

        let resumed = await renderer.render(
            owner: remountedOwner, source: buffer, effects: { LiveImageEffects() })
        XCTAssertNotNil(resumed, "Cancellation must release admission for the next inspector")
        XCTAssertEqual(
            invocations.value, 2, "Exactly one fresh request is admitted after cancellation")
    }

    func testRapidInspectorSwitchesKeepTheOriginalAdmissionClock() async throws {
        let clock = InspectorPreviewTestClock()
        let invocations = InspectorRenderInvocationCounter()
        var preparations = 0
        let prepare: @MainActor () -> LiveImageEffects = {
            preparations += 1
            return LiveImageEffects()
        }
        let reference = try Self.referenceImage()
        let renderer = AssistInspectorImageRenderer(
            now: { clock.now },
            operation: { _, _ in
                _ = invocations.increment()
                return reference
            })
        let buffer = try Self.buffer(width: 8, height: 8)
        let firstOwner = UUID()
        renderer.activate(owner: firstOwner)
        let first = await renderer.render(
            owner: firstOwner, source: buffer, effects: prepare)
        XCTAssertNotNil(first)
        renderer.deactivate(owner: firstOwner)
        let earlyTimes: [UInt64] = [20_000_000, 80_000_000, 120_000_000, 199_999_999]
        for time in earlyTimes {
            clock.now = time
            let owner = UUID()
            renderer.activate(owner: owner)
            let result = await renderer.render(
                owner: owner, source: buffer, effects: prepare)
            XCTAssertNil(result, "Tab changes must not restart the 200 ms budget")
            renderer.deactivate(owner: owner)
        }
        XCTAssertEqual(invocations.value, 1)
        XCTAssertEqual(preparations, 1, "Rejected tabs must not prepare a preview LUT either")
        clock.now = 200_000_000
        let owner = UUID()
        renderer.activate(owner: owner)
        let next = await renderer.render(owner: owner, source: buffer, effects: prepare)
        XCTAssertNotNil(next)
        XCTAssertEqual(invocations.value, 2)
        XCTAssertEqual(preparations, 2)
        XCTAssertFalse(renderer.isCurrent(try XCTUnwrap(first)))
    }

    func testSourceAndOptionChangesDiscardWorkAlreadyInsideTheRenderer() async throws {
        let clock = InspectorPreviewTestClock()
        let release = DispatchSemaphore(value: 0)
        let optionStarted = expectation(description: "Option render started")
        let sourceStarted = expectation(description: "Source render started")
        let invocations = InspectorRenderInvocationCounter()
        let reference = try Self.referenceImage()
        let renderer = AssistInspectorImageRenderer(
            now: { clock.now },
            operation: { _, _ in
                if invocations.increment() == 1 {
                    optionStarted.fulfill()
                } else {
                    sourceStarted.fulfill()
                }
                _ = release.wait(timeout: .now() + 3)
                return reference
            })
        let buffer = try Self.buffer(width: 8, height: 8)
        let owner = UUID()
        renderer.activate(owner: owner)
        let optionTask = Task {
            await renderer.render(owner: owner, source: buffer, effects: { LiveImageEffects() })
        }
        await fulfillment(of: [optionStarted], timeout: 2)
        renderer.invalidate(owner: owner)
        release.signal()
        let optionResult = await optionTask.value
        XCTAssertNil(optionResult, "Old option epochs must not publish")

        clock.now = 200_000_000
        let sourceTask = Task {
            await renderer.render(owner: owner, source: buffer, effects: { LiveImageEffects() })
        }
        await fulfillment(of: [sourceStarted], timeout: 2)
        renderer.invalidate(owner: owner)
        release.signal()
        let sourceResult = await sourceTask.value
        XCTAssertNil(sourceResult, "Old source epochs must not publish")
    }

    func testPlaybackPreviewWaitsForTheClipAndNeverFallsBackToCameraSource() throws {
        let bus = LiveFrameSampleBus()
        let camera = try Self.buffer(width: 8, height: 8)
        let clip = try Self.buffer(width: 16, height: 8)
        bus.publish(source: camera, transfer: .rec709, colorMode: .normal, bundle: nil)
        bus.usesPlaybackSource = true
        XCTAssertNil(bus.inspectorSource)
        bus.playbackSourcePixelBuffer = clip
        bus.playbackSourceTransfer = .dlog2
        XCTAssertTrue(bus.inspectorSource?.buffer === clip)
        XCTAssertEqual(bus.inspectorSource?.transfer, .dlog2)
        bus.clearPlaybackSource()
        XCTAssertNil(bus.inspectorSource)
        bus.usesPlaybackSource = false
        XCTAssertTrue(bus.inspectorSource?.buffer === camera)
        bus.reset()
        XCTAssertNil(bus.inspectorSource)
    }

    private static func referenceImage() throws -> CGImage {
        try XCTUnwrap(
            CIContext().createCGImage(
                CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
                from: CGRect(x: 0, y: 0, width: 1, height: 1)))
    }

    private static func buffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        XCTAssertEqual(result, kCVReturnSuccess)
        let source = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(source, [])
        if let address = CVPixelBufferGetBaseAddress(source) {
            memset(address, 200, CVPixelBufferGetBytesPerRow(source) * height)
        }
        CVPixelBufferUnlockBaseAddress(source, [])
        return source
    }
}

/// Deterministic monotonic time for both worker and real inspector mount tests.
final class InspectorPreviewTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: UInt64 = 0
    private var advancesUntilFrozen: Bool
    private var nextRead: InspectorPreviewTestSignal?

    init(advancesUntilFrozen: Bool = false) {
        self.advancesUntilFrozen = advancesUntilFrozen
    }

    /// Freeze at the clock value used for admission, not at delayed worker entry.
    func freezeAtLastRead() {
        lock.lock()
        advancesUntilFrozen = false
        lock.unlock()
    }

    func signalNextRead(_ signal: InspectorPreviewTestSignal) {
        lock.lock()
        nextRead = signal
        lock.unlock()
    }

    var now: UInt64 {
        get {
            lock.lock()
            defer { lock.unlock() }
            if advancesUntilFrozen { time = DispatchTime.now().uptimeNanoseconds }
            nextRead?.signal()
            nextRead = nil
            return time
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            time = newValue
        }
    }
}

/// The render closure runs on its worker queue while assertions run on main.
private final class InspectorRenderInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

/// Wait for the worker's event, not a presumed utility-queue scheduling delay.
/// The finite fallback throws out of the test before cancellation assertions
/// can manufacture a cascade; each caller releases blocked work in defer.
final class InspectorPreviewTestSignal: Sendable {
    private let name: String
    private let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(_ name: String) {
        self.name = name
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = pair.stream
        continuation = pair.continuation
    }

    func signal() {
        continuation.yield(())
        continuation.finish()
    }

    func wait() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in self.events { return }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw WaitFailure(event: self.name)
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private struct WaitFailure: Error, CustomStringConvertible {
        let event: String
        var description: String { "Inspector synchronization event did not arrive: \(event)" }
    }
}
