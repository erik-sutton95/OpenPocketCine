import Foundation

/// Display-only dead reckoning between camera attitude reports. Never used to
/// save a waypoint, drive a motor or verify arrival.
public struct GimbalOverlayMotion: Equatable, Sendable {
    public static let predictionHorizon: TimeInterval = 0.1
    public static let staleAfter: TimeInterval = 0.3

    private struct Sample: Equatable, Sendable {
        var pose: GimbalWaypoint
        var time: TimeInterval
    }

    private var previous: Sample?
    private var latest: Sample?

    public init() {}

    public mutating func reset() {
        previous = nil
        latest = nil
    }

    public mutating func observe(_ pose: GimbalWaypoint, at time: TimeInterval) {
        guard time.isFinite, pose.yawDeg.isFinite, pose.pitchDeg.isFinite,
            pose.zoom.isFinite, latest.map({ time > $0.time }) ?? true else { return }
        previous = latest
        latest = Sample(pose: pose, time: time)
    }

    public func pose(at time: TimeInterval) -> GimbalWaypoint? {
        guard let latest, time.isFinite, time >= latest.time,
            time - latest.time <= Self.staleAfter else { return nil }
        var result = latest.pose
        // An estimated pose must not be mistaken for a captured native target.
        result.nativePitchDeg = nil
        guard let previous else { return result }
        let interval = latest.time - previous.time
        guard interval >= 0.02, interval <= Self.staleAfter else { return result }
        let ahead = min(time - latest.time, Self.predictionHorizon)
        let yawDelta = GimbalMoveEngine.wrapAngle(latest.pose.yawDeg - previous.pose.yawDeg)
        result.yawDeg += yawDelta * ahead / interval
        result.pitchDeg += (latest.pose.pitchDeg - previous.pose.pitchDeg) * ahead / interval
        return result
    }
}
