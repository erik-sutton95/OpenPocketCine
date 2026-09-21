import CoreImage
import CoreVideo
import Foundation
import Observation
import OpenPocketViewCore
import Vision

/// Session-only experiment. No model download, cloud frames, or saved subject identity.
@MainActor @Observable
final class CinematicTrackingPrototype {
    enum State: Equatable {
        case idle, selecting, acquiring, tracking, holding, stopped
    }

    enum SubjectKind { case face, object }

    var settings = CinematicTrackingSettings()
    var keepComposition = false
    var showGuides = true
    private(set) var state = State.idle
    private(set) var message = "Select a person or object in the live picture."
    private(set) var box: TrackingBox?
    private(set) var confidence = 0.0
    private(set) var inferenceMilliseconds = 0.0
    private(set) var requestedPanSpeed = 0.0
    private(set) var requestedTiltSpeed = 0.0
    private(set) var subjectKind = SubjectKind.object
    var isEngaged: Bool {
        state == .selecting || state == .acquiring || state == .tracking || state == .holding
    }
    var wantsFrames: Bool { isEngaged }
    var wantsFaceDetections: Bool { isEngaged && (state == .selecting || subjectKind == .face) }
    var frameGeneration: UInt64 { generation }

    @ObservationIgnored private weak var session: CameraSession?
    @ObservationIgnored private let worker = CinematicVisionWorker()
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var token: UInt64?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var controller = CinematicTrackingController()
    private struct SourceFrame {
        let buffer: CVPixelBuffer
        let measuredAt: TimeInterval
    }
    @ObservationIgnored private var latestSelectionFrame: SourceFrame?
    @ObservationIgnored private var initialFrame: SourceFrame?
    @ObservationIgnored private var seed: TrackingBox?
    @ObservationIgnored private var lastObservation: (box: TrackingBox, time: TimeInterval)?
    @ObservationIgnored private var selectionFaces: (hits: [FaceHit], time: TimeInterval)?
    @ObservationIgnored private var faceLock: CinematicFaceLock?
    @ObservationIgnored private var motionSuspended = false
    @ObservationIgnored private var recoveryDeadline: TimeInterval?
    @ObservationIgnored private var acceptedFrames = 0
    // A cancelled job retains the occupied slot until its completion returns.
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var lastAdmission = -Double.infinity
    @ObservationIgnored private var lastHUD = -Double.infinity
    @ObservationIgnored private var lastResultAt: TimeInterval?
    @ObservationIgnored private var startedAt = 0.0
    @ObservationIgnored private var lastTickAt: TimeInterval?
    @ObservationIgnored private var raster: CGSize?
    @ObservationIgnored private var startingZoom = 1.0
    @ObservationIgnored private var startingInvert = false

    func attach(to session: CameraSession) { self.session = session }

    func select() {
        stop()
        guard let session, session.canStartCinematicTracking else {
            message = "Connect a Pocket and wait for a live picture."
            state = .stopped
            return
        }
        session.cancelProgrammedMove()
        state = .selecting
        message = "Drag a box around a person or object, or tap a face."
    }

    func start(_ selection: TrackingBox, preferFace: Bool = false) {
        guard state == .selecting, CinematicTrackingController.usable(selection),
            let session, session.canStartCinematicTracking
        else { return }
        guard let selectedFrame = latestSelectionFrame,
            ProcessInfo.processInfo.systemUptime - selectedFrame.measuredAt
                <= CinematicTrackingController.maxObservationAge
        else {
            session.controlNote = "Wait for a fresh picture, then select the subject"
            return
        }
        generation &+= 1
        let current = generation
        let face = selectionFaces.flatMap { snapshot -> FaceHit? in
            guard abs(selectedFrame.measuredAt - snapshot.time) <= 0.25 else { return nil }
            return CinematicFaceLock.selectedFace(in: selection, faces: snapshot.hits)
        }
        subjectKind = preferFace || face != nil ? .face : .object
        let selection = face?.box ?? selection
        if subjectKind == .face {
            faceLock = CinematicFaceLock(box: selection, measuredAt: selectedFrame.measuredAt)
        }
        seed = selection
        lastObservation = (selection, selectedFrame.measuredAt)
        if keepComposition {
            settings.framingX = min(max(selection.centerX, 0.1), 0.9)
            settings.framingY = min(max(selection.centerY, 0.1), 0.9)
        }
        box = selection
        state = .acquiring
        message = "Acquiring subject…"
        startedAt = ProcessInfo.processInfo.systemUptime
        initialFrame = selectedFrame
        latestSelectionFrame = nil
        // Seed with the picture the operator selected. Vision can follow the
        // subject while ActiveTrack CLEAR is acknowledged; motors still wait.
        consider(selectedFrame.buffer, measuredAt: selectedFrame.measuredAt)
        guard generation == current, isEngaged else { return }
        task = Task { @MainActor [weak self, weak session] in
            guard let self, let session, !Task.isCancelled, self.generation == current,
                self.isEngaged
            else { return }
            let prepared = await session.prepareCinematicTracking()
            guard !Task.isCancelled, self.generation == current else { return }
            guard prepared, let token = session.beginNativeSubjectTrack() else {
                self.stop(reason: "Couldn’t take gimbal control. Select the subject again.")
                return
            }
            self.token = token
            self.startingZoom = session.zoomReadout
            self.startingInvert = session.cinematicTrackingInvertPan
            self.startedAt = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled, self.generation == current {
                self.tick(now: ProcessInfo.processInfo.systemUptime)
                do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            }
        }
    }

    func stop(reason: String? = nil) {
        generation &+= 1
        task?.cancel()
        task = nil
        if let token { session?.endNativeSubjectTrack(token: token) }
        token = nil
        seed = nil
        initialFrame = nil
        latestSelectionFrame = nil
        box = nil
        lastObservation = nil
        selectionFaces = nil
        faceLock = nil
        motionSuspended = false
        recoveryDeadline = nil
        lastResultAt = nil
        lastTickAt = nil
        raster = nil
        acceptedFrames = 0
        confidence = 0
        requestedPanSpeed = 0
        requestedTiltSpeed = 0
        controller.reset()
        state = reason == nil ? .idle : .stopped
        message = reason ?? "Select a person or object in the live picture."
        worker.retire()
    }

    func consider(_ buffer: CVPixelBuffer, measuredAt: TimeInterval) {
        if state == .selecting {
            latestSelectionFrame = SourceFrame(buffer: buffer, measuredAt: measuredAt)
            return
        }
        guard state == .acquiring || state == .tracking || state == .holding, let seed else {
            return
        }
        let source = initialFrame ?? SourceFrame(buffer: buffer, measuredAt: measuredAt)
        let buffer = source.buffer
        let measuredAt = source.measuredAt
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= measuredAt, now - measuredAt <= CinematicTrackingController.maxObservationAge
        else {
            if initialFrame != nil { stop(reason: "Selection expired. Select the subject again.") }
            return
        }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .critical {
            stop(reason: "Phone is too warm. Let it cool, then select again.")
            return
        }
        let interval = thermal == .serious ? 0.2 : 1.0 / 15
        guard now - lastAdmission >= interval else { return }
        let size = CGSize(
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        if let raster, raster != size {
            stop(reason: "Picture format changed. Select the subject again.")
            return
        }
        raster = size
        // Faces share the existing AF detector's fresh source job. No second
        // face request or generic patch tracker runs for the selected person.
        if subjectKind == .face {
            initialFrame = nil
            return
        }
        guard !busy else { return }
        busy = true
        initialFrame = nil
        lastAdmission = now
        let current = generation
        worker.track(buffer, seed: seed, generation: current) { [weak self] result in
            guard let self else { return }
            self.busy = false
            guard self.generation == current,
                self.state == .acquiring || self.state == .tracking
                    || self.state == .holding
            else { return }
            self.adopt(result, measuredAt: measuredAt)
        }
    }

    /// Shared detector results keep their original decode timestamp and owner.
    /// Smoothed/held overlay boxes and cached repaints never feed the motors.
    func considerFaces(
        _ faces: [FaceHit], measuredAt: TimeInterval, generation: UInt64,
        milliseconds: Double = 0, now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard generation == self.generation, wantsFaceDetections,
            now >= measuredAt, now - measuredAt <= CinematicTrackingController.maxObservationAge
        else { return }
        if state == .selecting {
            selectionFaces = (faces, measuredAt)
            return
        }
        var candidateLock = faceLock
        let match = candidateLock?.update(
            faces: faces, measuredAt: measuredAt, minimumConfidence: settings.confidence)
        if candidateLock?.isAmbiguous == true {
            stop(reason: "Faces crossed. Select the person again.")
            return
        }
        let accepted = adopt(
            match.map {
                CinematicVisionWorker.Result(
                    box: $0.box, confidence: $0.confidence, milliseconds: milliseconds)
            }, measuredAt: measuredAt, now: now)
        if accepted { faceLock = candidateLock }
    }

    @discardableResult
    func adopt(
        _ result: CinematicVisionWorker.Result?, measuredAt: TimeInterval,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        guard state == .acquiring || state == .tracking || state == .holding,
            now >= measuredAt, now - measuredAt <= CinematicTrackingController.maxObservationAge
        else { return false }
        if state == .tracking || state == .holding {
            _ = maintainObservation(now: now)
            guard isEngaged else { return false }
        }
        guard let result, result.confidence >= settings.confidence,
            CinematicTrackingController.usable(result.box)
        else {
            if state == .acquiring || state == .holding { acceptedFrames = 0 }
            return false
        }
        if let lastObservation,
            measuredAt != lastObservation.time,
            !CinematicTrackingController.continuous(
                from: lastObservation.box, to: result.box, dt: measuredAt - lastObservation.time)
        {
            if state == .acquiring || state == .holding { acceptedFrames = 0 }
            return false
        }
        guard controller.observe(box: result.box, measuredAt: measuredAt, now: now) else {
            return false
        }
        lastObservation = (result.box, measuredAt)
        lastResultAt = measuredAt
        acceptedFrames += 1
        if acceptedFrames >= 3, state == .acquiring || state == .holding {
            state = .tracking
            motionSuspended = false
            recoveryDeadline = nil
            message = subjectKind == .face ? "Following selected face" : "Following selected object"
        }
        if now - lastHUD >= 0.2 || state == .acquiring {
            box = result.box
            confidence = result.confidence
            inferenceMilliseconds = result.milliseconds
            requestedPanSpeed = controller.panSpeed
            requestedTiltSpeed = controller.tiltSpeed
            lastHUD = now
        }
        return true
    }

    private func tick(now: TimeInterval) {
        if let lastTickAt, now - lastTickAt > CinematicTrackingController.maxTickGap {
            stop(reason: "Tracking paused too long. Select the subject again.")
            return
        }
        lastTickAt = now
        guard let session, let token, session.canContinueCinematicTracking,
            let pose = session.freshGimbalWaypoint
        else {
            stop(reason: "Tracking stopped. Wait for live view, then select again.")
            return
        }
        guard abs(session.zoomReadout - startingZoom) < 0.05,
            session.cinematicTrackingInvertPan == startingInvert
        else {
            stop(reason: "Camera framing changed. Select the subject again.")
            return
        }
        if state == .acquiring {
            if now - startedAt > 3 {
                stop(reason: "Couldn’t acquire this subject. Draw a tighter box.")
            }
            return
        }
        guard maintainObservation(now: now) else {
            if state == .holding, !motionSuspended {
                motionSuspended = session.suspendNativeSubjectTrack(token: token)
                if !motionSuspended {
                    stop(reason: "Gimbal control interrupted. Select the subject again.")
                }
            }
            return
        }
        guard let raster,
            let target = controller.target(
                pose: pose, now: now, settings: settings,
                pictureAspect: raster.width / max(1, raster.height), invertPan: startingInvert,
                poseReceivedAt: session.gimbalAttitudeReceivedAt),
            session.updateNativeSubjectTrack(target: target, token: token)
        else {
            stop(
                reason: controller.feedbackLost
                    ? "Gimbal couldn’t keep up. Select the subject again."
                    : "Subject or live feedback lost. Select it again to resume.")
            return
        }
    }

    /// A short detection miss keeps the lock. Stale measurements never continue
    /// driving: hold the camera while allowing a bounded, nearby recovery.
    @discardableResult
    func maintainObservation(now: TimeInterval) -> Bool {
        guard state == .tracking || state == .holding, let lastResultAt else { return false }
        let age = now - lastResultAt
        if now > (recoveryDeadline ?? (lastResultAt + CinematicFaceLock.recoveryInterval)) {
            stop(reason: "Subject lost. Select it again to resume.")
            return false
        }
        if age > CinematicTrackingController.maxObservationAge {
            if state != .holding {
                controller.reset()
                acceptedFrames = 0
                recoveryDeadline = lastResultAt + CinematicFaceLock.recoveryInterval
                state = .holding
                message = "Holding · waiting for the selected subject"
                confidence = 0
                requestedPanSpeed = 0
                requestedTiltSpeed = 0
            }
            return false
        }
        return state == .tracking
    }
}

/// Exactly one Vision job in flight, admitted by the session owner. No frame queue.
final class CinematicVisionWorker: @unchecked Sendable {
    struct Result: Sendable {
        var box: TrackingBox
        var confidence: Double
        var milliseconds: Double
    }

    private let queue = DispatchQueue(label: "opv.cinematic-tracking", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var generation: UInt64?
    private var handler: VNSequenceRequestHandler?
    private var request: VNTrackObjectRequest?

    func retire() {
        queue.async { [self] in
            handler = nil
            request = nil
            generation = nil
        }
    }

    func track(
        _ buffer: CVPixelBuffer, seed: TrackingBox, generation: UInt64,
        completion: @escaping @MainActor (Result?) -> Void
    ) {
        queue.async { [self] in
            let start = ProcessInfo.processInfo.systemUptime
            if self.generation != generation {
                self.generation = generation
                handler = VNSequenceRequestHandler()
                request = VNTrackObjectRequest(
                    detectedObjectObservation: VNDetectedObjectObservation(
                        boundingBox: CGRect(
                            x: seed.x, y: 1 - seed.maxY, width: seed.width, height: seed.height)))
                request?.trackingLevel = .accurate
            }
            let result: Result?
            if let request, let handler, let scaled = downsample(buffer) {
                do {
                    try handler.perform([request], on: scaled, orientation: .up)
                    if let observation = request.results?.first as? VNDetectedObjectObservation {
                        let rect = observation.boundingBox
                        let box = TrackingBox(
                            x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
                        request.inputObservation = observation
                        result = Result(
                            box: box, confidence: Double(observation.confidence),
                            milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000)
                    } else {
                        result = nil
                    }
                } catch { result = nil }
            } else {
                result = nil
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func downsample(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        let scale = min(1, 640 / Double(max(width, height)))
        var output: CVPixelBuffer?
        guard
            CVPixelBufferCreate(
                kCFAllocatorDefault, max(1, Int(Double(width) * scale)),
                max(1, Int(Double(height) * scale)),
                kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                &output) == kCVReturnSuccess, let output
        else { return nil }
        let image = CIImage(cvPixelBuffer: buffer).transformed(
            by: CGAffineTransform(scaleX: scale, y: scale))
        context.render(image, to: output)
        return output
    }
}
