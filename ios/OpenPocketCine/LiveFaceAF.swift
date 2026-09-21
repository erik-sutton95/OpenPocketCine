import CoreVideo
import Foundation
import OpenPocketViewCore
import Vision

/// Latest-frame-wins AF-C detector. Camera `0x89` is ActiveTrack only; Mimo
/// does not push a subject rect, so this runs on the live VT buffer.
/// Face ovals only. Pose / person head is off until it is reliable.
final class LiveFaceDetector: @unchecked Sendable {
    static let interval: TimeInterval = 0.04
    static let minimumConfidence: Float = 0.70

    private let queue = DispatchQueue(label: "opv.face-af", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var lastRun = -Double.infinity
    private var pending: Pending?
    private let detectFrame: @Sendable (CVPixelBuffer, Bool, Float) -> FaceDetectResult

    init(
        detectFrame: @escaping @Sendable (CVPixelBuffer, Bool, Float) -> FaceDetectResult = {
            detect(in: $0, rectanglesOnly: $1, minimumConfidence: $2)
        }
    ) {
        self.detectFrame = detectFrame
    }

    private struct Pending {
        let buffer: CVPixelBuffer
        let rectanglesOnly: Bool
        let minimumConfidence: Float
        let interval: TimeInterval
        let completion: @MainActor (FaceDetectResult) -> Void
    }

    func consider(
        _ buffer: CVPixelBuffer,
        rectanglesOnly: Bool = false,
        minimumConfidence: Float = LiveFaceDetector.minimumConfidence,
        interval: TimeInterval = LiveFaceDetector.interval,
        completion: @escaping @MainActor (FaceDetectResult) -> Void
    ) {
        // Replace the waiting frame at admission, not behind synchronous Vision
        // on its worker queue. There is one running job and one newest frame.
        lock.lock()
        pending = Pending(
            buffer: buffer, rectanglesOnly: rectanglesOnly,
            minimumConfidence: minimumConfidence, interval: max(Self.interval, interval),
            completion: completion)
        let start = !busy
        busy = true
        lock.unlock()
        if start { queue.async { [self] in pump() } }
    }

    private func pump() {
        lock.lock()
        guard let next = pending else {
            busy = false
            lock.unlock()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let wait = next.interval - (now - lastRun)
        if wait > 0 {
            lock.unlock()
            queue.asyncAfter(deadline: .now() + wait) { [self] in pump() }
            return
        }
        pending = nil
        lastRun = now
        lock.unlock()
        let result = detectFrame(next.buffer, next.rectanglesOnly, next.minimumConfidence)
        DispatchQueue.main.async { [self] in
            next.completion(result)
            // Delivery is part of the occupied slot, so a busy UI cannot grow a
            // queue of increasingly stale results either.
            queue.async { [self] in pump() }
        }
    }

    static func detect(
        in buffer: CVPixelBuffer, rectanglesOnly: Bool = false,
        minimumConfidence: Float = LiveFaceDetector.minimumConfidence
    ) -> FaceDetectResult {
        let faces = detectFaces(
            in: buffer, rectanglesOnly: rectanglesOnly, minimumConfidence: minimumConfidence)
        return FaceDetectResult(
            faces: Array(faces.sorted { score($0) > score($1) }.prefix(SceneFacePolicy.maxFaces)))
    }

    static func detectFaces(
        in buffer: CVPixelBuffer, rectanglesOnly: Bool = false,
        minimumConfidence: Float = LiveFaceDetector.minimumConfidence
    ) -> [FaceHit] {
        let request: VNImageBasedRequest =
            rectanglesOnly ? VNDetectFaceRectanglesRequest() : VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: buffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let faces = (request.results as? [VNFaceObservation]) ?? []
        let viable = faces.filter { face in
            face.confidence >= minimumConfidence
                && (rectanglesOnly || hasFaceStructure(face))
        }
        return viable.compactMap { face -> FaceHit? in
            boxHit(
                from: face.boundingBox,
                confidence: Double(face.confidence),
                structured: !rectanglesOnly && hasLandmarkStructure(face))
        }
        .sorted { score($0) > score($1) }
        .prefix(SceneFacePolicy.maxFaces)
        .map { $0 }
    }

    private static func boxHit(
        from rect: CGRect, confidence: Double, structured: Bool
    ) -> FaceHit? {
        guard
            let box = VisionFaceBox.fromVision(
                minX: Double(rect.minX),
                minY: Double(rect.minY),
                width: Double(rect.width),
                height: Double(rect.height)
            )
        else { return nil }
        return FaceHit(box: box, confidence: confidence, structured: structured)
    }

    private static func score(_ hit: FaceHit) -> Double {
        hit.confidence * hit.box.area
    }

    static func hasFaceStructure(_ face: VNFaceObservation) -> Bool {
        let landmarks = face.landmarks
        let left = landmarks?.leftEye
        let right = landmarks?.rightEye
        let nose = landmarks?.nose
        return FaceStructurePolicy.isLikelyFace(
            confidence: Double(face.confidence),
            leftEyeX: averageX(left),
            rightEyeX: averageX(right),
            leftEyePoints: left?.pointCount ?? 0,
            rightEyePoints: right?.pointCount ?? 0,
            nosePoints: nose?.pointCount ?? 0
        )
    }

    static func hasLandmarkStructure(_ face: VNFaceObservation) -> Bool {
        let landmarks = face.landmarks
        let left = landmarks?.leftEye
        let right = landmarks?.rightEye
        let nose = landmarks?.nose
        return FaceStructurePolicy.hasFaceLandmarks(
            leftEyeX: averageX(left),
            rightEyeX: averageX(right),
            leftEyePoints: left?.pointCount ?? 0,
            rightEyePoints: right?.pointCount ?? 0,
            nosePoints: nose?.pointCount ?? 0
        )
    }

    private static func averageX(_ region: VNFaceLandmarkRegion2D?) -> Double? {
        guard let region, region.pointCount > 0 else { return nil }
        let sum = region.normalizedPoints.reduce(0) { $0 + $1.x }
        return Double(sum / CGFloat(region.pointCount))
    }
}
