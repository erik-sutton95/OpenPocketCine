import CoreVideo
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class DecoderGenerationTests: XCTestCase {
    func testResetRejectsAlreadyQueuedAssistResult() async {
        await assertRejectsQueuedResult { $0.reset() }
    }

    func testPresentationRebuildRejectsAlreadyQueuedAssistResult() async {
        await assertRejectsQueuedResult { _ = $0.rebuildPresentation() }
    }

    func testLateSuccessfulDecodeCannotEnterTheNewGeneration() async {
        let decoder = HevcDecoder()
        let oldGeneration = decoder.sourceFrameGeneration
        _ = decoder.rebuildPresentation()
        let current = ScopeTestBuffers.makeFlatBuffer(code: 180, width: 16, height: 16)
        let drained = expectation(description: "Current generation reaches processing")
        var identityFrames = 0
        decoder.onIdentityFrame = { _ in identityFrames += 1 }
        decoder.onSourceFrame = { buffer in
            XCTAssertTrue(buffer === current, "A late VT success must not reach consumers")
            drained.fulfill()
        }

        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 40, width: 16, height: 16),
            generation: oldGeneration)
        decoder.handleDecodedFrame(current, isNewSourceFrame: false)
        await fulfillment(of: [drained], timeout: 3)

        XCTAssertEqual(identityFrames, 0, "Stale source must not reach the watcher encoder")
        XCTAssertNil(decoder.lastSourceFrameAt)
    }

    func testCurrentGenerationStillPublishesNewSourceHealthAfterReset() async {
        let decoder = HevcDecoder()
        let bus = LiveFrameSampleBus()
        decoder.sampleBus = bus
        decoder.reset()
        let delivered = expectation(description: "Current source reaches processing")
        decoder.onSourceFrame = { _ in delivered.fulfill() }
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 180, width: 16, height: 16),
            generation: decoder.sourceFrameGeneration)
        await fulfillment(of: [delivered], timeout: 3)

        XCTAssertNotNil(decoder.lastSourceFrameAt)
        XCTAssertEqual(bus.decodedFrames, 1)
    }

    private func assertRejectsQueuedResult(_ invalidate: (HevcDecoder) -> Void) async {
        let decoder = HevcDecoder()
        let bus = LiveFrameSampleBus()
        decoder.sampleBus = bus
        let old = ScopeTestBuffers.makeFlatBuffer(code: 40, width: 16, height: 16)
        let sentinel = ScopeTestBuffers.makeFlatBuffer(code: 180, width: 16, height: 16)
        let drained = expectation(description: "Current cached frame drains assist results")
        var oldFrames = 0
        decoder.onSourceFrame = { buffer in
            if buffer === old { oldFrames += 1 }
            if buffer === sentinel { drained.fulfill() }
        }

        // No actor yield between source submission and invalidation: an old
        // completion cannot run on MainActor until the lifecycle changes.
        decoder.handleDecodedFrame(old)
        invalidate(decoder)
        decoder.handleDecodedFrame(sentinel, isNewSourceFrame: false)
        await fulfillment(of: [drained], timeout: 3)

        XCTAssertEqual(oldFrames, 0, "An old source must not reach presentation/Face AF")
        XCTAssertNil(decoder.lastSourceFrameAt, "Old pixels must not mark recovery healthy")
        XCTAssertNil(decoder.lastPresentedAt)
        XCTAssertEqual(bus.decodedFrames, 0, "A cached repaint is not a new camera picture")
    }
}
