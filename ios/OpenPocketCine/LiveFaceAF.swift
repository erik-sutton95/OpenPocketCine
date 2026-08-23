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
    private var busy = false
    private var lastRun = Date.distantPast
    private var pending: Pending?

    private struct Pending {
        let buffer: CVPixelBuffer
        let rectanglesOnly: Bool
        let completion: @MainActor (FaceDetectResult) -> Void
    }

    func consider(
        _ buffer: CVPixelBuffer,
        rectanglesOnly: Bool = false,
        completion: @escaping @MainActor (FaceDetectResult) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            // Keep the newest buffer while a detect is in flight so a gimbal
            // pan is not scored against a frame that is already 200 ms old.
            self.pending = Pending(
                buffer: buffer, rectanglesOnly: rectanglesOnly, completion: completion)
            self.pump()
        }
    }

    private func pump() {
        guard !busy, let next = pending else { return }
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= Self.interval else { return }
        pending = nil
        busy = true
        lastRun = now
        let result = Self.detect(in: next.buffer, rectanglesOnly: next.rectanglesOnly)
        busy = false
        DispatchQueue.main.async { next.completion(result) }
        pump()
    }

    static func detect(
        in buffer: CVPixelBuffer, rectanglesOnly: Bool = false
    ) -> FaceDetectResult {
        let faces = detectFaces(in: buffer, rectanglesOnly: rectanglesOnly)
        return FaceDetectResult(
            faces: Array(faces.sorted { score($0) > score($1) }.prefix(SceneFacePolicy.maxFaces)))
    }

    static func detectFaces(
        in buffer: CVPixelBuffer, rectanglesOnly: Bool = false
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
