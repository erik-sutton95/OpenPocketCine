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

    func testSingleWeakObservationDoesNotDiscardTheSelectedSubject() async throws {
        let session = try await readySession()
        defer { session.disconnect() }
        let tracker = session.cinematicTracking
        tracker.select()
        let now = ProcessInfo.processInfo.systemUptime
        tracker.consider(ScopeTestBuffers.makeEdgeBuffer(), measuredAt: now - 0.2)
        let box = TrackingBox(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        tracker.start(box)
        for index in 0..<3 {
            tracker.adopt(
                .init(box: box, confidence: 0.95, milliseconds: 5),
                measuredAt: now - 0.15 + Double(index) * 0.05)
        }
        XCTAssertEqual(tracker.state, .tracking)
        tracker.adopt(
            .init(box: box, confidence: tracker.settings.confidence - 0.1, milliseconds: 5),
            measuredAt: now)
        XCTAssertTrue(tracker.isEngaged, "One blurred frame must not require reselection")
        XCTAssertNotNil(tracker.box)
    }

    func testFaceLockPausesStaleMotionAndRecoversOnlyTheNearbySubject() async throws {
        let session = try await readySession()
        defer { session.disconnect() }
        let tracker = session.cinematicTracking
        tracker.select()
        let start = ProcessInfo.processInfo.systemUptime
        tracker.consider(ScopeTestBuffers.makeEdgeBuffer(), measuredAt: start - 0.1)
        let selected = FaceHit(box: TrackingBox(x: 0.3, y: 0.3, width: 0.15, height: 0.2))
        let stranger = FaceHit(box: TrackingBox(x: 0.7, y: 0.3, width: 0.2, height: 0.3))
        tracker.start(selected.box, preferFace: true)
        let generation = tracker.frameGeneration
        XCTAssertEqual(tracker.subjectKind, .face)
        for index in 0..<3 {
            let time = start + Double(index) * 0.04
            tracker.considerFaces(
                [selected, stranger], measuredAt: time, generation: generation, now: time)
        }
        XCTAssertEqual(tracker.state, .tracking)
        XCTAssertTrue(tracker.maintainObservation(now: start + 0.2))
        XCTAssertFalse(tracker.maintainObservation(now: start + 0.4))
        XCTAssertEqual(tracker.state, .holding)
        XCTAssertTrue(tracker.isEngaged)
        tracker.considerFaces(
            [stranger], measuredAt: start + 0.5, generation: generation, now: start + 0.5)
        XCTAssertEqual(tracker.state, .holding)
        tracker.considerFaces(
            [selected], measuredAt: start + 0.52, generation: generation, now: start + 0.52)
        tracker.considerFaces(
            [], measuredAt: start + 0.56, generation: generation, now: start + 0.56)
        for index in 0..<3 {
            let time = start + 0.6 + Double(index) * 0.04
            tracker.considerFaces(
                [selected, stranger], measuredAt: time, generation: generation, now: time)
            if index < 2 {
                XCTAssertEqual(tracker.state, .holding, "Recovery requires consecutive matches")
            }
        }
        XCTAssertEqual(tracker.state, .tracking)
        XCTAssertTrue(tracker.maintainObservation(now: start + 0.75))
        XCTAssertFalse(tracker.maintainObservation(now: start + 1))
        tracker.considerFaces(
            [selected], measuredAt: start + 1.4, generation: generation, now: start + 1.4)
        tracker.considerFaces(
            [], measuredAt: start + 1.44, generation: generation, now: start + 1.44)
        tracker.considerFaces(
            [selected], measuredAt: start + 1.5, generation: generation, now: start + 1.5)
        XCTAssertFalse(tracker.maintainObservation(now: start + 1.8))
        XCTAssertEqual(
            tracker.state, .stopped, "Tentative matches must not extend the recovery deadline")
        tracker.considerFaces(
            [selected], measuredAt: start + 1.81, generation: generation, now: start + 1.81)
        XCTAssertEqual(tracker.state, .stopped, "An expired lock cannot restart from a late result")
    }

    func testFreshFaceSelectionUsesDetectionAndRejectsStaleOwnerAndFrame() async throws {
        let session = try await readySession()
        defer { session.disconnect() }
        let tracker = session.cinematicTracking
        tracker.select()
        let now = ProcessInfo.processInfo.systemUptime
        tracker.consider(ScopeTestBuffers.makeEdgeBuffer(), measuredAt: now)
        let face = FaceHit(box: TrackingBox(x: 0.3, y: 0.2, width: 0.1, height: 0.15))
        let previousGeneration = tracker.frameGeneration
        tracker.considerFaces([face], measuredAt: now, generation: previousGeneration, now: now)
        tracker.start(TrackingBox(x: 0.2, y: 0.1, width: 0.3, height: 0.7))
        XCTAssertEqual(
            tracker.subjectKind, .face, "A drag around one person should use face detection")
        XCTAssertEqual(tracker.box, face.box)
        for index in 1...4 {
            let time = now + Double(index) * 0.04
            tracker.considerFaces(
                [face], measuredAt: time, generation: previousGeneration, now: time)
            tracker.considerFaces(
                [face], measuredAt: time, generation: tracker.frameGeneration, now: time + 0.4)
        }
        XCTAssertEqual(tracker.state, .acquiring)
        tracker.stop()
        tracker.considerFaces([face], measuredAt: now, generation: previousGeneration, now: now)
        XCTAssertFalse(tracker.isEngaged)
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
