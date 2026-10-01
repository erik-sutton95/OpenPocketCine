import Foundation

/// DJI Pocket gimbal reach. Operator-confirmed tilt bounds in display `0x04/0x05` degrees.
/// That push *is* gimbal space — do not sweep the stick to build a map.
/// Pan 0 is front; the positive arc passes selfie to raw −135° (= +225°).
/// The other endpoint is −48°; the intervening negative arc is unreachable.
public enum GimbalReach {
    public static let panMinDeg = -48.0
    public static let panMaxDeg = 225.0
    public static let tiltMinDeg = -44.0
    public static let tiltMaxDeg = 70.0

    /// Middle of the unreachable arc in raw `0x04/0x05` yaw. Raw yaw past
    /// below it is the long side, reached by panning positive past selfie.
    public static var gapMidDeg: Double { (panMaxDeg + panMinDeg - 360) / 2 }

    public static func clampPan(_ deg: Double) -> Double {
        min(max(deg, panMinDeg), panMaxDeg)
    }

    public static func clampTilt(_ deg: Double) -> Double {
        min(max(deg, tiltMinDeg), tiltMaxDeg)
    }

    /// Unbounded SET-relative look → nearest reachable yaw/pitch.
    /// Tilt bounds never expand to include an invalid shared-forward pose.
    public static func project(
        lookRight: Double, lookUp: Double, yaw0: Double, pitch0: Double
    ) -> (yaw: Double, pitch: Double) {
        let panLo = panMinDeg
        let panHi = panMaxDeg
        let tiltLo = tiltMinDeg
        let tiltHi = tiltMaxDeg
        return (
            min(max(yaw0 + lookRight, panLo), panHi),
            min(max(pitch0 + lookUp, tiltLo), tiltHi)
        )
    }
}
