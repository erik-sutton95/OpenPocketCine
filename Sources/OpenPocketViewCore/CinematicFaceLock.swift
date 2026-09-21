import Foundation

/// Associates fresh detections with the selected face, without ranking by size
/// or confidence alone. This is a short spatial lock, not face recognition.
public struct CinematicFaceLock: Sendable {
    public static let recoveryInterval = 1.0
    public private(set) var box: TrackingBox
    public private(set) var measuredAt: TimeInterval
    public private(set) var isAmbiguous = false
    private var velocityX = 0.0
    private var velocityY = 0.0

    public init(box: TrackingBox, measuredAt: TimeInterval) {
        self.box = box
        self.measuredAt = measuredAt
    }

    /// A drag around one person can select their face. Multiple faces leave the
    /// region as an object selection; never choose the largest by accident.
    public static func selectedFace(in selection: TrackingBox, faces: [FaceHit]) -> FaceHit? {
        let candidates = faces.filter {
            CinematicTrackingController.usable($0.box)
                && selection.contains(x: $0.box.centerX, y: $0.box.centerY)
                && selection.intersectionArea($0.box) >= $0.box.area * 0.6
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    public mutating func update(
        faces: [FaceHit], measuredAt time: TimeInterval, minimumConfidence: Double
    ) -> FaceHit? {
        let dt = time - measuredAt
        guard !isAmbiguous, dt.isFinite, dt > 0, dt <= Self.recoveryInterval else { return nil }
        // Prediction is only for association, never a fabricated motor observation.
        let horizon = min(dt, 0.2)
        let x = box.centerX + velocityX * horizon
        let y = box.centerY + velocityY * horizon
        let radius = min(0.18, max(0.055, max(box.width, box.height) * 0.85))
        let candidates = faces.compactMap { hit -> (hit: FaceHit, score: Double)? in
            guard hit.confidence >= minimumConfidence,
                CinematicTrackingController.usable(hit.box)
            else { return nil }
            let ratio = hit.box.area / box.area
            let distance = hypot(hit.box.centerX - x, hit.box.centerY - y)
            guard (0.4...2.5).contains(ratio), distance <= radius else { return nil }
            let score =
                distance / radius + 0.25 * abs(log(ratio))
                + 0.2 * (1 - box.intersectionOverUnion(hit.box))
            return (hit, score)
        }.sorted { $0.score < $1.score }
        guard let best = candidates.first else { return nil }
        // Crossing/overlapping faces are ambiguous. Wait rather than swap people.
        if candidates.count > 1, candidates[1].score - best.score < 0.25 {
            isAmbiguous = true
            return nil
        }
        let alpha = min(1, dt / 0.12)
        velocityX +=
            (min(max((best.hit.box.centerX - box.centerX) / dt, -0.8), 0.8)
                - velocityX) * alpha
        velocityY +=
            (min(max((best.hit.box.centerY - box.centerY) / dt, -0.8), 0.8)
                - velocityY) * alpha
        box = best.hit.box
        measuredAt = time
        return best.hit
    }
}
