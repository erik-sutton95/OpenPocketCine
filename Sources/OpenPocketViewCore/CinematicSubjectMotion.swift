import Foundation

/// Estimate subject bearing velocity after removing the camera's own motion.
/// Bounded histories and a short regression window reject detector/pose quantization.
/// Receipt clocks are not exposure clocks: the 80 ms alignment is an estimate.
struct CinematicSubjectMotion: Sendable {
    private struct Sample: Sendable {
        var time: TimeInterval
        var yaw: Double
        var pitch: Double
    }
    private var poses: [Sample] = []
    private var bearings: [Sample] = []
    private(set) var yawRate = 0.0
    private(set) var pitchRate = 0.0

    mutating func notePose(_ pose: GimbalWaypoint, receivedAt time: TimeInterval) {
        guard time.isFinite, poses.last.map({ time > $0.time }) ?? true else { return }
        poses.append(Sample(time: time, yaw: pose.yawDeg, pitch: pose.pitchDeg))
        poses.removeAll { time - $0.time > 0.8 }
        if poses.count > 64 { poses.removeFirst(poses.count - 64) }
    }

    mutating func observe(imageYaw: Double, imagePitch: Double, measuredAt time: TimeInterval) {
        guard let pose = pose(at: time - 0.08),
            bearings.last.map({ time > $0.time }) ?? true
        else { return }
        let previousTime = bearings.last?.time
        let interval = time - (previousTime ?? time)
        bearings.append(
            Sample(time: time, yaw: pose.yaw + imageYaw, pitch: pose.pitch + imagePitch))
        let window = min(0.65, max(0.24, interval * 3.1))
        bearings.removeAll { time - $0.time > window }
        if bearings.count > 16 { bearings.removeFirst(bearings.count - 16) }
        guard let first = bearings.first, bearings.count >= 3, time - first.time >= 0.075 else {
            yawRate = 0
            pitchRate = 0
            return
        }
        let count = Double(bearings.count)
        let meanTime = bearings.reduce(0) { $0 + ($1.time - time) } / count
        let meanYaw = bearings.reduce(0) { $0 + $1.yaw } / count
        let meanPitch = bearings.reduce(0) { $0 + $1.pitch } / count
        var denominator = 0.0
        var yawSlope = 0.0
        var pitchSlope = 0.0
        for sample in bearings {
            let t = sample.time - time - meanTime
            denominator += t * t
            yawSlope += t * (sample.yaw - meanYaw)
            pitchSlope += t * (sample.pitch - meanPitch)
        }
        guard denominator > 1e-9 else { return }
        let alpha = -expm1(-interval / 0.08)
        yawRate += (min(max(yawSlope / denominator, -120), 120) - yawRate) * alpha
        pitchRate += (min(max(pitchSlope / denominator, -120), 120) - pitchRate) * alpha
    }

    private func pose(at time: TimeInterval) -> Sample? {
        guard let first = poses.first, let last = poses.last else { return nil }
        if time <= first.time { return first }
        for index in 1..<poses.count where poses[index].time >= time {
            let a = poses[index - 1]
            let b = poses[index]
            let fraction = (time - a.time) / (b.time - a.time)
            return Sample(
                time: time, yaw: a.yaw + (b.yaw - a.yaw) * fraction,
                pitch: a.pitch + (b.pitch - a.pitch) * fraction)
        }
        return last
    }
}
