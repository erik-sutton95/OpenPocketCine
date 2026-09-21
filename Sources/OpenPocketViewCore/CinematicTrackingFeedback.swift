import Foundation

/// Accept bounded telemetry lag without constraining pursuit to an old position.
/// A range check bounds disagreement, but a fixed pose inside a repeatedly
/// traversed range may remain plausible. This is not an instantaneous motor pose.
struct CinematicTrackingFeedback: Sendable {
    static let allowedLag = 0.5
    private struct Target: Sendable {
        var time: TimeInterval
        var yaw: Double
        var pitch: Double
    }
    private var history: [Target] = []
    private var lastReceipt: TimeInterval?

    mutating func noteTarget(yaw: Double, pitch: Double, at time: TimeInterval) {
        history.append(Target(time: time, yaw: yaw, pitch: pitch))
        history.removeAll { time - $0.time > 1 }
        if history.count > 64 { history.removeFirst(history.count - 64) }
    }

    mutating func accepts(
        _ pose: GimbalWaypoint, receivedAt time: TimeInterval,
        settings: CinematicTrackingSettings
    ) -> Bool {
        if let lastReceipt {
            if time < lastReceipt { return false }
            if time == lastReceipt { return true }
        }
        lastReceipt = time
        guard !history.isEmpty else { return true }
        let recent = history.filter { $0.time >= time - Self.allowedLag && $0.time <= time }
        guard let first = recent.first else { return false }
        // One native horizon plus two quantization steps permits ordinary motor
        // response. Travel beyond this and the lag window ends control; do not
        // contract a lead allowance and command the camera backward.
        let tolerance = settings.maxSpeed * CinematicTrackingController.commandDuration + 0.2
        let minYaw = recent.reduce(first.yaw) { min($0, $1.yaw) }
        let maxYaw = recent.reduce(first.yaw) { max($0, $1.yaw) }
        let minPitch = recent.reduce(first.pitch) { min($0, $1.pitch) }
        let maxPitch = recent.reduce(first.pitch) { max($0, $1.pitch) }
        return
            (!settings.panEnabled
            || (minYaw - tolerance...maxYaw + tolerance).contains(pose.yawDeg))
            && (!settings.tiltEnabled
                || (minPitch - tolerance...maxPitch + tolerance).contains(pose.pitchDeg))
    }
}
