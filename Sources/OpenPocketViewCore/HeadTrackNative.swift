import Foundation

/// Shared-forward head lock mapped directly to camera-native angular targets.
/// The 100 ms native horizon is independent of programmed-path speed limits.
public struct HeadTrackNative: Equatable, Sendable {
    public static let commandDuration: TimeInterval = 0.1
    public static let maxHeadSampleAge: TimeInterval = 0.2
    public private(set) var origin: GimbalWaypoint?
    public private(set) var lastTarget: GimbalWaypoint?
    private var lookRight = 0.0
    private var lookUp = 0.0

    public init() {}

    public var isCentered: Bool { origin != nil }

    public mutating func reset() {
        origin = nil
        lastTarget = nil
        lookRight = 0
        lookUp = 0
    }

    public static func headSampleIsFresh(measuredAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let measuredAt, measuredAt.isFinite, now.isFinite else { return false }
        let age = now - measuredAt
        return age >= 0 && age <= maxHeadSampleAge
    }

    public mutating func center(
        pose: GimbalWaypoint?, gyroLookRight: Double = 0,
        gyroLookUp: Double = 0, gyroYaw: Double = 0
    ) -> HeadTrack.CenterResult {
        guard let pose, let nativePitch = pose.nativePitchDeg,
            pose.yawDeg.isFinite, pose.pitchDeg.isFinite, pose.zoom.isFinite,
            nativePitch.isFinite, (-180...180).contains(nativePitch), pose == pose.clamped()
        else { return .waitingForGimbal }
        guard gyroLookRight.isFinite, gyroLookUp.isFinite, gyroYaw.isFinite,
            HeadTrack.gyroMagnitude(lookRight: gyroLookRight, lookUp: gyroLookUp, yaw: gyroYaw)
                < HeadTrack.calibrateStillRadPerSec
        else { return .waitingForStill }
        origin = pose
        lastTarget = pose
        lookRight = 0
        lookUp = 0
        return .centered
    }

    public mutating func target(lookRightDeg: Double, lookUpDeg: Double) -> GimbalWaypoint? {
        guard let origin, let nativePitch = origin.nativePitchDeg,
            lookRightDeg.isFinite, lookUpDeg.isFinite else { return nil }
        lookRight = HeadTrack.unwrap(lookRightDeg, previous: lookRight)
        lookUp = HeadTrack.unwrap(lookUpDeg, previous: lookUp)
        let projected = HeadTrack.Reach.project(
            lookRight: lookRight, lookUp: lookUp, yaw0: origin.yawDeg, pitch0: origin.pitchDeg)
        let point = GimbalWaypoint(
            yawDeg: projected.yaw, pitchDeg: projected.pitch, zoom: origin.zoom,
            nativePitchDeg: GimbalMoveEngine.wrapAngle(nativePitch - (projected.pitch - origin.pitchDeg)))
        lastTarget = point
        return point
    }
}

/// Fences queued motion callbacks across stop/start and rejects old measurements.
public struct HeadTrackNativeSampleGate: Equatable, Sendable {
    private var generation: UInt64 = 0
    private var active = false

    public init() {}

    public mutating func begin() -> UInt64 {
        generation &+= 1
        active = true
        return generation
    }

    public mutating func invalidate() {
        generation &+= 1
        active = false
    }

    public func isCurrent(_ token: UInt64) -> Bool { active && token == generation }

    public func accepts(_ token: UInt64, measuredAt: TimeInterval, now: TimeInterval) -> Bool {
        isCurrent(token) && HeadTrackNative.headSampleIsFresh(measuredAt: measuredAt, now: now)
    }
}
