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
        let buffer = try Self.buffer(width: 640, height: 360)
        let image = await renderer.render(source: buffer, effects: LiveImageEffects())
        XCTAssertEqual(image?.width, 320)
        XCTAssertEqual(image?.height, 180)
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
        let started = expectation(description: "First image work started")
        let release = DispatchSemaphore(value: 0)
        let invocations = InspectorRenderInvocationCounter()
        let reference = try XCTUnwrap(
            CIContext().createCGImage(
                CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
                from: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let renderer = AssistInspectorImageRenderer { _, _ in
            if invocations.increment() == 1 { started.fulfill() }
            _ = release.wait(timeout: .now() + 3)
            return reference
        }
        let buffer = try Self.buffer(width: 8, height: 8)
        let first = Task { await renderer.render(source: buffer, effects: LiveImageEffects()) }
        await fulfillment(of: [started], timeout: 2)
        let dropped = await renderer.render(source: buffer, effects: LiveImageEffects())
        XCTAssertNil(dropped, "A busy preview must not retain a queued second source")
        XCTAssertEqual(invocations.value, 1, "Dropped work must never enter the renderer")
        first.cancel()
        release.signal()
        let cancelled = await first.value
        XCTAssertNil(cancelled, "Dismissed inspectors must never adopt completed stale work")
        XCTAssertEqual(invocations.value, 1, "Cancellation must not drain queued work")

        release.signal()
        let resumed = await renderer.render(source: buffer, effects: LiveImageEffects())
        XCTAssertNotNil(resumed, "Cancellation must release admission for the next inspector")
        XCTAssertEqual(
            invocations.value, 2, "Exactly one fresh request is admitted after cancellation")
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
