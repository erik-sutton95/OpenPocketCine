import CoreImage
import Metal
import QuartzCore
import XCTest
import os

@testable import OpenPocketCine

@MainActor
final class FeedPresentationTests: XCTestCase {
    func testPresentationJournalReportsSilenceAfterAWindowOfPicture() throws {
        var metrics = FeedPresentationMetrics(startedAt: 0)
        for tick in 1...25 { metrics.notePresented(at: Double(tick) / 25) }
        let rolling = try XCTUnwrap(metrics.drain(at: 1))
        XCTAssertEqual(rolling.gpuFramesPerSecond, 25, accuracy: 0.001)
        XCTAssertEqual(rolling.maximumGapMilliseconds, 40, accuracy: 0.001)
        let frozen = try XCTUnwrap(metrics.drain(at: 3))
        XCTAssertEqual(frozen.gpuFramesPerSecond, 0, "No new completion must report zero FPS")
        XCTAssertEqual(frozen.maximumGapMilliseconds, 2_000, accuracy: 0.001)
    }

    func testPresentationJournalUsesActualElapsedWindowAndKeepsEarlierHitches() throws {
        var metrics = FeedPresentationMetrics(startedAt: 0)
        metrics.noteAcquire(milliseconds: 450)
        metrics.noteGPUCompletion(milliseconds: 180)
        for tick in 1...50 { metrics.notePresented(at: Double(tick) / 25) }
        metrics.noteAcquire(milliseconds: 2)
        metrics.noteGPUCompletion(milliseconds: 3)
        let window = try XCTUnwrap(metrics.drain(at: 2.5))
        XCTAssertEqual(window.gpuFramesPerSecond, 20, accuracy: 0.001)
        XCTAssertEqual(window.maximumGapMilliseconds, 500, accuracy: 0.001)
        XCTAssertEqual(window.maximumAcquireMilliseconds, 450)
        XCTAssertEqual(window.maximumGPUCompletionMilliseconds, 180)
        let next = try XCTUnwrap(metrics.drain(at: 3.5))
        XCTAssertEqual(next.maximumAcquireMilliseconds, 0)
        XCTAssertEqual(next.maximumGPUCompletionMilliseconds, 0)
    }

    func testDrawableWaitDoesNotBlockMainActor() async throws {
        let feed = try makeFeed()
        let finished = expectation(description: "Drawable acquisition returned")
        let heartbeatRan = OSAllocatedUnfairLock(initialState: false)
        feed.presentOperations.acquire = { _ in
            let heartbeat = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { heartbeat.signal() }
            let result = heartbeat.wait(timeout: .now() + .milliseconds(400))
            heartbeatRan.withLock { $0 = result == .success }
            finished.fulfill()
            return nil
        }
        XCTAssertTrue(feed.display(picture, timeNs: 1))
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertTrue(heartbeatRan.withLock { $0 }, "Drawable wait must leave MainActor runnable")
    }

    func testSubmissionIsNotSuccessfulPresentation() async throws {
        let feed = try makeFeed()
        let drawable = try TestFeedDrawable(layer: feed.layer as! CAMetalLayer)
        let submitted = expectation(description: "GPU submission is pending")
        let completion = OSAllocatedUnfairLock<(@Sendable (Bool) -> Void)?>(initialState: nil)
        feed.presentOperations.acquire = { _ in drawable }
        feed.presentOperations.submit = { _, _, done in
            completion.withLock { $0 = done }
            submitted.fulfill()
        }
        XCTAssertTrue(feed.display(picture, timeNs: 10))
        await fulfillment(of: [submitted], timeout: 3)
        XCTAssertFalse(feed.hasPresentedFrame)
        XCTAssertNil(feed.lastPresentedAt)
        XCTAssertEqual(feed.presentedFrames, 0)
        let done = try XCTUnwrap(completion.withLock { $0 })
        done(false)
        await Task.yield()
        XCTAssertFalse(feed.hasPresentedFrame, "Failed GPU work cannot claim a picture")
    }

    func testInvalidatedGPUCompletionCannotRestoreOldPicture() async throws {
        let feed = try makeFeed()
        let drawable = try TestFeedDrawable(layer: feed.layer as! CAMetalLayer)
        let submitted = expectation(description: "Old generation submitted")
        let completion = OSAllocatedUnfairLock<(@Sendable (Bool) -> Void)?>(initialState: nil)
        feed.presentOperations.acquire = { _ in drawable }
        feed.presentOperations.submit = { _, _, done in
            completion.withLock { $0 = done }
            submitted.fulfill()
        }
        XCTAssertTrue(feed.display(picture, timeNs: 10))
        await fulfillment(of: [submitted], timeout: 3)
        feed.resetPresentation()
        let done = try XCTUnwrap(completion.withLock { $0 })
        done(true)
        await MainActor.run {}
        await Task.yield()
        XCTAssertFalse(feed.hasPresentedFrame)
        XCTAssertNil(feed.lastPresentedAt)
        XCTAssertEqual(feed.presentedFrames, 0)

        let current = expectation(description: "Current generation presents")
        feed.onPresented = { current.fulfill() }
        feed.presentOperations.submit = { _, _, completed in completed(true) }
        XCTAssertTrue(feed.display(picture, timeNs: 20))
        await fulfillment(of: [current], timeout: 3)
        XCTAssertEqual(feed.lastPresentedTimeNs, 20)
        XCTAssertEqual(feed.presentedFrames, 1, "Old completion must release the reservation")
    }

    func testInvalidationWhileAcquiringKeepsOneFlightAndUsesNewSource() async throws {
        try await assertInvalidatesAcquisition { $0.invalidatePendingPresents() }
    }

    func testResizeWhileAcquiringRejectsOldDrawable() async throws {
        try await assertInvalidatesAcquisition { feed in
            feed.frame.size = CGSize(width: 128, height: 64)
            feed.setNeedsLayout()
            feed.layoutIfNeeded()
        }
    }

    private func assertInvalidatesAcquisition(_ invalidate: (CIFeedView) -> Void) async throws {
        let feed = try makeFeed()
        let drawable = try TestFeedDrawable(layer: feed.layer as! CAMetalLayer)
        let acquiring = expectation(description: "Old acquisition is blocked")
        let release = DispatchSemaphore(value: 0)
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let committed = OSAllocatedUnfairLock(initialState: 0)
        feed.presentOperations.acquire = { _ in
            let attempt = attempts.withLock {
                $0 += 1
                return $0
            }
            if attempt == 1 {
                acquiring.fulfill()
                _ = release.wait(timeout: .now() + 2)
            }
            return drawable
        }
        feed.presentOperations.submit = { _, _, completed in
            committed.withLock { $0 += 1 }
            completed(true)
        }
        XCTAssertTrue(feed.display(picture, timeNs: 10))
        await fulfillment(of: [acquiring], timeout: 3)
        let generation = feed.debugPresentGeneration
        invalidate(feed)
        XCTAssertNotEqual(feed.debugPresentGeneration, generation)
        XCTAssertTrue(feed.display(picture, timeNs: 20))
        XCTAssertEqual(attempts.withLock { $0 }, 1)
        let current = expectation(description: "Replacement source presents")
        feed.onPresented = { current.fulfill() }
        release.signal()
        await fulfillment(of: [current], timeout: 3)
        XCTAssertEqual(committed.withLock { $0 }, 1, "Old acquired drawable must not submit")
        XCTAssertEqual(feed.lastPresentedTimeNs, 20)
    }

    func testCompletionKeepsItsBakedSourceTimeWhileNewerFrameWaits() async throws {
        let feed = try makeFeed()
        let drawable = try TestFeedDrawable(layer: feed.layer as! CAMetalLayer)
        let firstSubmitted = expectation(description: "First source submitted")
        let completions = OSAllocatedUnfairLock<[@Sendable (Bool) -> Void]>(initialState: [])
        feed.presentOperations.acquire = { _ in drawable }
        feed.presentOperations.submit = { _, _, done in
            let first = completions.withLock {
                $0.append(done)
                return $0.count == 1
            }
            if first { firstSubmitted.fulfill() }
        }
        XCTAssertTrue(feed.display(picture, timeNs: 10))
        await fulfillment(of: [firstSubmitted], timeout: 3)
        XCTAssertTrue(feed.display(picture, timeNs: 20))
        let firstPresented = expectation(description: "First source GPU completed")
        feed.onPresented = { firstPresented.fulfill() }
        let done = try XCTUnwrap(completions.withLock { $0.first })
        done(true)
        await fulfillment(of: [firstPresented], timeout: 3)
        XCTAssertEqual(feed.lastPresentedTimeNs, 10, "Newest admission must not relabel old pixels")
        XCTAssertEqual(feed.presentedFrames, 1)
    }

    func testSameSourceSubmittedDuringFlightDoesNotCountTwice() async throws {
        let feed = try makeFeed()
        let drawable = try TestFeedDrawable(layer: feed.layer as! CAMetalLayer)
        let firstSubmitted = expectation(description: "First source submitted")
        let repeated = expectation(description: "Duplicate source must not submit again")
        repeated.isInverted = true
        let completion = OSAllocatedUnfairLock<(@Sendable (Bool) -> Void)?>(initialState: nil)
        feed.presentOperations.acquire = { _ in drawable }
        feed.presentOperations.submit = { _, _, done in
            let first = completion.withLock { stored in
                let first = stored == nil
                if first { stored = done }
                return first
            }
            if first { firstSubmitted.fulfill() } else { repeated.fulfill() }
        }
        XCTAssertTrue(feed.display(picture, timeNs: 10))
        await fulfillment(of: [firstSubmitted], timeout: 3)
        XCTAssertTrue(feed.display(picture, timeNs: 10))
        let done = try XCTUnwrap(completion.withLock { $0 })
        done(true)
        await fulfillment(of: [repeated], timeout: 0.2)
        XCTAssertEqual(feed.presentedFrames, 1)
    }

    func testPendingReplacementKeepsThePresentedOverlayStyle() async throws {
        let feed = try makeFeed()
        let drawable = try TestFeedDrawable(layer: feed.layer as! CAMetalLayer)
        feed.presentOperations.acquire = { _ in drawable }
        feed.presentOperations.submit = { _, _, completed in completed(true) }
        let overlayPresented = expectation(description: "Overlay is GPU complete")
        feed.onPresented = { overlayPresented.fulfill() }
        XCTAssertTrue(feed.display(picture, overlay: true, timeNs: 10))
        await fulfillment(of: [overlayPresented], timeout: 3)
        XCTAssertFalse(feed.isOpaque)

        let submitted = expectation(description: "Replacement waits for GPU completion")
        let completion = OSAllocatedUnfairLock<(@Sendable (Bool) -> Void)?>(initialState: nil)
        feed.presentOperations.submit = { _, _, done in
            completion.withLock { $0 = done }
            submitted.fulfill()
        }
        XCTAssertTrue(feed.display(picture, overlay: false, timeNs: 20))
        await fulfillment(of: [submitted], timeout: 3)
        XCTAssertFalse(feed.isOpaque, "An admitted LUT must not restyle the old transparent frame")
        XCTAssertTrue(feed.lastPresentWasOverlay)
        let replacementPresented = expectation(description: "Replacement style matches its pixels")
        feed.onPresented = { replacementPresented.fulfill() }
        let done = try XCTUnwrap(completion.withLock { $0 })
        done(true)
        await fulfillment(of: [replacementPresented], timeout: 3)
        XCTAssertTrue(feed.isOpaque)
        XCTAssertFalse(feed.lastPresentWasOverlay)
    }

    private func makeFeed() throws -> CIFeedView {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal required") }
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        (feed.layer as! CAMetalLayer).drawableSize = CGSize(width: 64, height: 64)
        return feed
    }

    private var picture: CIImage {
        CIImage(color: CIColor(red: 0.2, green: 0.5, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
    }
}

private final class TestFeedDrawable: NSObject, CAMetalDrawable, @unchecked Sendable {
    let texture: MTLTexture
    let layer: CAMetalLayer

    init(layer: CAMetalLayer) throws {
        self.layer = layer
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        texture = try XCTUnwrap(layer.device?.makeTexture(descriptor: descriptor))
        super.init()
    }

    func present() {}
    func present(at presentationTime: CFTimeInterval) {}

    #if !targetEnvironment(simulator)
        var presentedTime: CFTimeInterval { 0 }
        var drawableID: Int { 1 }
        func present(afterMinimumDuration duration: CFTimeInterval) {}
        func addPresentedHandler(_ block: @escaping MTLDrawablePresentedHandler) {}
    #endif
}
