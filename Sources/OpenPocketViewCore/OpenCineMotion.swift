import Foundation

// Shared gimbal trajectory math (waypoints, A·B·C programs, the smoothed curve, head-look math,
// bounded head tracking) and the typed motion seam live in OpenCineCore's OpenCineMotion.
// Re-exported so app and facade call sites keep importing only this module. OpenCineDJI declares
// the gimbal (`MotionCapabilities.pocketGimbal`, `GimbalReach.bounds`, `CameraModel.motion`); the
// app side stays here: 0x04/0x05 tenths, native-target pacing, program zoom.
@_exported import OpenCineMotion

extension HeadTrack {
    /// DJI gimbal reach (see `GimbalReach`). Kept as `HeadTrack.Reach` for call sites.
    public typealias Reach = GimbalReach
}

// Call sites from before the move, bound to the Pocket reach.
extension GimbalWaypoint {
    public static func unwrapYaw(_ rawDeg: Double) -> Double {
        unwrapYaw(rawDeg, in: HeadTrack.Reach.bounds)
    }

    public func clamped() -> GimbalWaypoint { clamped(to: HeadTrack.Reach.bounds) }

    /// Live `0x04/0x05` yaw/pitch in tenths of a degree; native pitch from attitude i16 @0.
    public static func from(yawTenth: Int16?, pitchTenth: Int16?, zoom: Double,
        nativePitchTenth: Int16? = nil) -> GimbalWaypoint? {
        guard let yawTenth, let pitchTenth else { return nil }
        return GimbalWaypoint(
            yawDeg: unwrapYaw(Double(yawTenth) / 10),
            pitchDeg: Double(pitchTenth) / 10,
            zoom: zoom, nativePitchDeg: nativePitchTenth.map { Double($0) / 10 })
    }
}

extension HeadTrackNative {
    public init() { self.init(bounds: HeadTrack.Reach.bounds) }
}
