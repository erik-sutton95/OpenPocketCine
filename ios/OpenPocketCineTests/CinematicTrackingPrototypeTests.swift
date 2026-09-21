import CoreVideo
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class CinematicTrackingPrototypeTests: XCTestCase {
    private func readySession() async throws -> CameraSession {
        let decoder = HevcDecoder()
        decoder.effects.faceAF = true
        decoder.unlockHardwareDecoder()
        let session = CameraSession(borrowing: decoder)
        let frame = expectation(description: "Fresh decoded picture")
        decoder.onSourceFrame = { _ in frame.fulfill() }
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
        await fulfillment(of: [frame], timeout: 3)
        session.updateMultiview(
            camera: FoundCamera(
                id: UUID(), name: "OsmoPocket4P-Test",
                model: .resolve(modelId: 0x22, name: "OsmoPocket4P-Test"), modelId: 0x22),
            driver: DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: ""),
            status: CameraStatus())
        session.receiveMultiview(
            .init(
                sender: 0, receiver: 0, seq: 1, flags: 0, cmdSet: 4, cmdId: 5,
                payload: [UInt8](repeating: 0, count: 22)))
        // Populate a standalone session fixture without opening a camera connection.
        session.isMultiviewBorrowed = false
        XCTAssertTrue(session.canStartCinematicTracking)
        return session
    }

    func testSelectionYieldsToManualControlsAndInactiveScene() async throws {
        for action in ["stick", "mode", "recenter", "inactive", "disconnect"] {
            let session = try await readySession()
            defer { session.disconnect() }
            session.cinematicTracking.select()
            XCTAssertEqual(session.cinematicTracking.state, .selecting)
            XCTAssertNil(session.beginNativeHeadTrack(), "Head updates cannot steal phone tracking")
            switch action {
            case "stick": session.updateGimbalStick(x: 0.5, y: 0)
            case "mode": session.setGimbalMode(.follow)
            case "recenter": session.recenterGimbal()
            case "inactive": session.noteSceneBecameInactive()
            default: session.disconnect()
            }
            XCTAssertFalse(session.cinematicTracking.isEngaged, action)
            XCTAssertFalse(session.cinematicTracking.wantsFrames, action)
        }
    }

    func testStopDuringCameraPreparationCannotStartLater() async throws {
        let session = try await readySession()
        defer { session.disconnect() }
        let tracker = session.cinematicTracking
        tracker.select()
        tracker.consider(
            ScopeTestBuffers.makeEdgeBuffer(), measuredAt: ProcessInfo.processInfo.systemUptime)
        tracker.start(TrackingBox(x: 0.3, y: 0.3, width: 0.2, height: 0.2))
        XCTAssertEqual(tracker.state, .acquiring)
        tracker.stop()
        await Task.yield()
        XCTAssertEqual(tracker.state, .idle)
        XCTAssertFalse(session.canContinueCinematicTracking)
        XCTAssertNil(tracker.box)
    }

    func testCachedAndRetiredDecoderFramesCannotDriveTracking() async {
        let decoder = HevcDecoder()
        let oldGeneration = decoder.sourceFrameGeneration
        _ = decoder.rebuildPresentation()
        let drained = expectation(description: "Cached repaint is processed")
        var trackingFrames = 0
        decoder.onTrackingFrame = { _, _ in trackingFrames += 1 }
        decoder.onSourceFrame = { _ in drained.fulfill() }
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 50, width: 32, height: 32),
            generation: oldGeneration)
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 150, width: 32, height: 32),
            isNewSourceFrame: false)
        await fulfillment(of: [drained], timeout: 3)
        XCTAssertEqual(trackingFrames, 0)
    }

    func testVisionTracksSyntheticObjectWithoutChangingCoordinateOrigin() async throws {
        let worker = CinematicVisionWorker()
        defer { worker.retire() }
        let seed = TrackingBox(x: 0.25, y: 0.2, width: 0.25, height: 0.3)
        for step in 0..<3 {
            let done = expectation(description: "Vision observation")
            let x = seed.x + Double(step) * 0.015
            let frame = texturedObject(x: x)
            var result: CinematicVisionWorker.Result?
            worker.track(frame, seed: seed, generation: 1) { value in
                result = value
                done.fulfill()
            }
            await fulfillment(of: [done], timeout: 10)
            let observation = try XCTUnwrap(result)
            XCTAssertGreaterThan(observation.confidence, 0.3)
            XCTAssertEqual(observation.box.centerX, x + 0.125, accuracy: 0.04)
            XCTAssertEqual(observation.box.centerY, 0.35, accuracy: 0.04)
        }
    }

    private func texturedObject(x: Double) -> CVPixelBuffer {
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 25, width: 320, height: 180)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let left = Int(x * 320)
        for row in 36..<90 {
            for column in left..<(left + 80) {
                let value = UInt8(80 + ((column - left) * 31 + row * 47) % 170)
                let offset = row * stride + column * 4
                bytes[offset] = value
                bytes[offset + 1] = 255 - value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
            }
        }
        return buffer
    }
}
