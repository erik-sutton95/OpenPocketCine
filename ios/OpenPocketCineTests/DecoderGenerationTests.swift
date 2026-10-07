import CoreVideo
import OpenCineApple
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
        decoder.onSourceFrame = { lease in
            XCTAssertTrue(
                lease.pixelBuffer === current, "A late VT success must not reach consumers")
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

    func testSourceFrameLeaseIsLentForTheCallbackOnly() async {
        let decoder = HevcDecoder()
        let delivered = expectation(description: "Source frame lent")
        var lent: DecodedFrameLease?
        decoder.onSourceFrame = { lease in
            XCTAssertNotNil(lease.pixelBuffer)
            XCTAssertEqual(Int(lease.generation.value), decoder.sourceFrameGeneration)
            lent = lease
            delivered.fulfill()
        }
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 120, width: 16, height: 16))
        await fulfillment(of: [delivered], timeout: 3)
        XCTAssertEqual(
            lent?.isReleased, true, "Consumers keep pixels by taking their own reference")
    }

    func testResetInsideSourceFrameCallbackRejectsTheRestOfTheOldCompletion() async {
        await assertRejectsCallbackReentry(resetFromSourceFrame: true, close: false)
    }

    func testResetInsideSourceAdvancedCallbackCannotRefreshTheNewSource() async {
        await assertRejectsCallbackReentry(resetFromSourceFrame: false, close: false)
    }

    func testCloseInsideSourceFrameCallbackCannotRepublishSourceHealth() async {
        await assertRejectsCallbackReentry(resetFromSourceFrame: true, close: true)
    }

    func testResetInsideMirrorCallbackCannotCommitTheOldOrientation() {
        assertRejectsMirrorReentry(close: false)
    }

    func testCloseInsideMirrorCallbackCannotCommitTheOldOrientation() {
        assertRejectsMirrorReentry(close: true)
    }

    func testCurrentMirrorCallbackStillCommitsItsObservedOrientation() {
        let decoder = HevcDecoder()
        decoder.preparePixelBufferSource(transfer: .rec709)
        var mirrors: [Bool] = []
        var orientations: [Bool] = []
        decoder.applyPictureMirror = { mirrors.append($0) }
        decoder.onIdentityOrientation = { orientations.append($0) }

        _ = decoder.enqueueDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 120, width: 16, height: 16))

        XCTAssertEqual(mirrors, [false])
        XCTAssertEqual(orientations, [false])
        XCTAssertEqual(decoder.presentedPictureFlip, false)
        decoder.close()
    }

    private func assertRejectsMirrorReentry(close: Bool) {
        let decoder = HevcDecoder()
        decoder.preparePixelBufferSource(transfer: .rec709)
        let source = decoder.sourceToken
        var mirrors = 0
        var orientations: [Bool] = []
        decoder.onIdentityOrientation = { orientations.append($0) }
        decoder.applyPictureMirror = { _ in
            mirrors += 1
            if close {
                decoder.close()
            } else {
                decoder.reset()
                decoder.preparePixelBufferSource(transfer: .rec709)
            }
        }

        XCTAssertFalse(
            decoder.enqueueDecodedFrame(
                ScopeTestBuffers.makeFlatBuffer(code: 40, width: 16, height: 16)))

        XCTAssertEqual(mirrors, 1, "The test must exercise the native mirror callback")
        XCTAssertNotEqual(decoder.sourceToken, source)
        XCTAssertNil(decoder.presentedPictureFlip)
        XCTAssertEqual(orientations, [])
        XCTAssertNil(decoder.lastPresentedAt)
        decoder.close()
    }

    private func assertRejectsCallbackReentry(
        resetFromSourceFrame: Bool, close: Bool
    ) async {
        let decoder = HevcDecoder()
        let bus = LiveFrameSampleBus()
        decoder.sampleBus = bus
        decoder.preparePixelBufferSource(transfer: .rec709)
        let oldToken = decoder.sourceToken
        let old = ScopeTestBuffers.makeFlatBuffer(code: 40, width: 16, height: 16)
        let reentered = expectation(description: "The consumer retires the delivered source")
        var advanced = 0
        var previews = 0
        var presented = 0
        decoder.onPreviewFrame = { _, _, _ in previews += 1 }
        decoder.onPresentedFrame = { presented += 1 }
        let retire = {
            if close {
                decoder.close()
            } else {
                decoder.reset()
                decoder.preparePixelBufferSource(transfer: .rec709)
            }
            reentered.fulfill()
        }
        decoder.onSourceFrame = { lease in
            XCTAssertTrue(lease.pixelBuffer === old)
            if resetFromSourceFrame { retire() }
        }
        decoder.onSourceAdvanced = {
            advanced += 1
            if !resetFromSourceFrame { retire() }
        }
        decoder.handleDecodedFrame(old)
        await fulfillment(of: [reentered], timeout: 3)

        // The callback and the rest of its synchronous MainActor completion have
        // returned before this continuation can inspect the replacement source.
        XCTAssertNotEqual(decoder.sourceToken, oldToken)
        XCTAssertEqual(advanced, resetFromSourceFrame ? 0 : 1)
        XCTAssertNil(decoder.lastSourceFrameAt, "Old pixels cannot make a replacement healthy")
        XCTAssertNil(decoder.lastPresentedAt, "Old pixels cannot present after retirement")
        XCTAssertEqual(decoder.sourcePresentations, 0)
        XCTAssertEqual(bus.decodedFrames, 0)
        XCTAssertNil(bus.sourcePixelBuffer)
        XCTAssertEqual(previews, 0, "Retired frames cannot refill external previews")
        XCTAssertEqual(presented, 0)

        if close {
            XCTAssertNil(decoder.sourceToken)
            decoder.reset()
            XCTAssertNil(decoder.sourceToken, "Close remains terminal after callback reentry")
            return
        }
        let successor = ScopeTestBuffers.makeFlatBuffer(code: 180, width: 16, height: 16)
        let delivered = expectation(description: "The replacement still accepts its own frames")
        decoder.onSourceFrame = { lease in
            XCTAssertTrue(lease.pixelBuffer === successor)
            delivered.fulfill()
        }
        decoder.onSourceAdvanced = nil
        decoder.handleDecodedFrame(successor)
        await fulfillment(of: [delivered], timeout: 3)
        XCTAssertNotNil(decoder.lastSourceFrameAt)
        XCTAssertEqual(bus.decodedFrames, 1)
        XCTAssertTrue(bus.sourcePixelBuffer === successor)
        decoder.close()
    }

    private func assertRejectsQueuedResult(_ invalidate: (HevcDecoder) -> Void) async {
        let decoder = HevcDecoder()
        let bus = LiveFrameSampleBus()
        decoder.sampleBus = bus
        let old = ScopeTestBuffers.makeFlatBuffer(code: 40, width: 16, height: 16)
        let sentinel = ScopeTestBuffers.makeFlatBuffer(code: 180, width: 16, height: 16)
        let drained = expectation(description: "Current cached frame drains assist results")
        var oldFrames = 0
        decoder.onSourceFrame = { lease in
            if lease.pixelBuffer === old { oldFrames += 1 }
            if lease.pixelBuffer === sentinel { drained.fulfill() }
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
