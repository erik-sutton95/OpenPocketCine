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
        case idle, selecting, acquiring, tracking, stopped
    }

    var settings = CinematicTrackingSettings()
    var keepComposition = false
    var showGuides = true
    private(set) var state = State.idle
    private(set) var message = "Select a person or object in the live picture."
    private(set) var box: TrackingBox?
    private(set) var confidence = 0.0
    private(set) var inferenceMilliseconds = 0.0
    var isEngaged: Bool { state == .selecting || state == .acquiring || state == .tracking }
    var wantsFrames: Bool { isEngaged }

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
    @ObservationIgnored private var acceptedFrames = 0
    // A cancelled job retains the occupied slot until its completion returns.
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var lastAdmission = -Double.infinity
    @ObservationIgnored private var lastHUD = -Double.infinity
    @ObservationIgnored private var lastResultAt: TimeInterval?
    @ObservationIgnored private var startedAt = 0.0
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

    func start(_ selection: TrackingBox) {
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
        seed = selection
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
        lastResultAt = nil
        raster = nil
        acceptedFrames = 0
        confidence = 0
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
        guard state == .acquiring || state == .tracking, let seed, !busy else { return }
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
        busy = true
        initialFrame = nil
        lastAdmission = now
        let current = generation
        worker.track(buffer, seed: seed, generation: current) { [weak self] result in
            guard let self else { return }
            self.busy = false
            guard self.generation == current, self.state == .acquiring || self.state == .tracking
            else { return }
            self.adopt(result, measuredAt: measuredAt)
        }
    }

    private func adopt(_ result: CinematicVisionWorker.Result?, measuredAt: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - measuredAt <= CinematicTrackingController.maxObservationAge else {
            // Cold Vision startup may be slow. It cannot steer using that frame.
            if state == .tracking {
                stop(reason: "Tracking fell behind. Select the subject again.")
            }
            return
        }
        guard let result, result.confidence >= settings.confidence,
            CinematicTrackingController.usable(result.box)
        else {
            stop(reason: "Subject lost. Select it again to resume.")
            return
        }
        if let lastObservation,
            !CinematicTrackingController.continuous(
                from: lastObservation.box, to: result.box, dt: measuredAt - lastObservation.time)
        {
            stop(reason: "Subject changed or moved out of view. Select it again.")
            return
        }
        guard controller.observe(box: result.box, measuredAt: measuredAt, now: now) else { return }
        lastObservation = (result.box, measuredAt)
        lastResultAt = measuredAt
        acceptedFrames += 1
        if acceptedFrames >= 3, state == .acquiring {
            state = .tracking
            message = "Tracking on this phone"
        }
        if now - lastHUD >= 0.2 || state == .acquiring {
            box = result.box
            confidence = result.confidence
            inferenceMilliseconds = result.milliseconds
            lastHUD = now
        }
    }

    private func tick(now: TimeInterval) {
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
        guard let lastResultAt, now - lastResultAt <= CinematicTrackingController.maxObservationAge,
            let raster,
            let target = controller.target(
                pose: pose, now: now, settings: settings,
                pictureAspect: raster.width / max(1, raster.height), invertPan: startingInvert),
            session.updateNativeSubjectTrack(target: target, token: token)
        else {
            stop(reason: "Subject or live feedback lost. Select it again to resume.")
            return
        }
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
