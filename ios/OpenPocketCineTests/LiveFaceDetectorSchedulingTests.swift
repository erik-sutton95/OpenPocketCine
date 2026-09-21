import CoreVideo
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class LiveFaceDetectorSchedulingTests: XCTestCase {
    func testSlowDetectionKeepsOnlyTheNewestWaitingFrameAndItsConfidence() async {
        let started = expectation(description: "First analysis entered")
        let delivered = expectation(description: "First and newest frames delivered")
        delivered.expectedFulfillmentCount = 2
        let probe = BlockedDetector(started: started)
        let detector = LiveFaceDetector { buffer, _, confidence in
            probe.detect(buffer, confidence: confidence)
        }
        var frames: [Int] = []
        detector.consider(ScopeTestBuffers.makeFlatBuffer(code: 80, width: 32, height: 32)) { _ in
            frames.append(32)
            delivered.fulfill()
        }
        await fulfillment(of: [started], timeout: 3)
        for width in 33...60 {
            detector.consider(
                ScopeTestBuffers.makeFlatBuffer(code: 80, width: width, height: 32),
                minimumConfidence: 0.45
            ) { _ in
                frames.append(width)
                delivered.fulfill()
            }
        }
        probe.release.signal()
        await fulfillment(of: [delivered], timeout: 3)
        XCTAssertEqual(frames, [32, 60], "Slow inference must not replay a queue of old pictures")
        XCTAssertEqual(probe.samples.map(\.0), [32, 60])
        XCTAssertEqual(probe.samples.last?.1, 0.45)
    }

    private final class BlockedDetector: @unchecked Sendable {
        let release = DispatchSemaphore(value: 0)
        private let started: XCTestExpectation
        private let lock = NSLock()
        private var values: [(Int, Float)] = []
        var samples: [(Int, Float)] { lock.withLock { values } }

        init(started: XCTestExpectation) { self.started = started }

        func detect(_ buffer: CVPixelBuffer, confidence: Float) -> FaceDetectResult {
            let width = CVPixelBufferGetWidth(buffer)
            lock.withLock { values.append((width, confidence)) }
            if width == 32 {
                started.fulfill()
                _ = release.wait(timeout: .now() + 3)
            }
            return FaceDetectResult(faces: [])
        }
    }
}
