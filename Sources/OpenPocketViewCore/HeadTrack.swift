import Foundation

/// Head-look math shared by the native head-track path (`HeadTrackNative`)
/// and the iOS dials. Look is the SET-relative nose azimuth/elevation
/// (`Quat.look`, +Y forward): Euler Δatt yaw wobbles during a nod at a
/// yawed heading (18:29 take: diagonal drift).
public enum HeadTrack {
    public static let calibrateStillRadPerSec = 0.08

    public static func gyroMagnitude(lookRight: Double, lookUp: Double, yaw: Double = 0)
        -> Double
    {
        (lookRight * lookRight + lookUp * lookUp + yaw * yaw).squareRoot()
    }

    /// SET-relative gimbal pan. Live `0x04/0x05` yaw minus Calibrate Head Lock.
    public static func bodyLookRightDeg(liveYawDeg: Double, originYawDeg: Double) -> Double {
        wrapDeg(liveYawDeg - originYawDeg)
    }

    /// SET-relative gimbal tilt. Live pitch minus Calibrate Head Lock.
    public static func bodyLookUpDeg(livePitchDeg: Double, originPitchDeg: Double) -> Double {
        livePitchDeg - originPitchDeg
    }

    /// Clockwise degrees from 12 o'clock on the yaw ring. Matches `lookRightDeg`.
    public static func yawDialDeg(lookRightDeg: Double) -> Double {
        wrapDeg(lookRightDeg)
    }

    /// Clockwise degrees for an up-drawn arrow on the pitch ring. 0 look
    /// points right (3 o'clock). Nod up is counter-clockwise; nod down clockwise.
    public static func pitchDialDeg(lookUpDeg: Double) -> Double {
        wrapDeg(90 - lookUpDeg)
    }

    /// AirPods CMAttitude: +X right, +Y forward (nose), +Z up.
    /// Tracking +Z as the nose made look-right follow roll and inverted pitch.
    public struct Quat: Equatable, Sendable {
        public var w: Double
        public var x: Double
        public var y: Double
        public var z: Double

        public static let identity = Quat(w: 1, x: 0, y: 0, z: 0)

        public init(w: Double, x: Double, y: Double, z: Double) {
            self.w = w
            self.x = x
            self.y = y
            self.z = z
        }

        public var conjugate: Quat { Quat(w: w, x: -x, y: -y, z: -z) }

        public func multiply(_ r: Quat) -> Quat {
            Quat(
                w: w * r.w - x * r.x - y * r.y - z * r.z,
                x: w * r.x + x * r.w + y * r.z - z * r.y,
                y: w * r.y - x * r.z + y * r.w + z * r.x,
                z: w * r.z + x * r.y - y * r.x + z * r.w)
        }

        public func rotate(_ v: (x: Double, y: Double, z: Double)) -> (
            x: Double, y: Double, z: Double
        ) {
            let p = Quat(w: 0, x: v.x, y: v.y, z: v.z)
            let r = multiply(p).multiply(conjugate)
            return (r.x, r.y, r.z)
        }

        public static func axisAngle(x: Double, y: Double, z: Double, deg: Double) -> Quat {
            let half = deg * .pi / 360
            let s = sin(half)
            let n = (x * x + y * y + z * z).squareRoot()
            let inv = n > 0 ? s / n : 0
            return Quat(w: cos(half), x: x * inv, y: y * inv, z: z * inv)
        }

        /// SET-relative look in degrees. +right / +up from the nose (+Y).
        public static func look(from q: Quat, origin q0: Quat) -> (right: Double, up: Double) {
            let v = q0.conjugate.multiply(q).rotate((0, 1, 0))
            let right = atan2(v.x, v.y) * 180 / .pi
            let up = atan2(v.z, hypot(v.x, v.y)) * 180 / .pi
            return (right, up)
        }
    }

    /// Nose on the SET sphere. Euler Δatt yaw jumps when you nod; this does not.
    public static func look(current: Quat, origin: Quat) -> (right: Double, up: Double) {
        Quat.look(from: current, origin: origin)
    }

    /// Operator-confirmed tilt bounds in display `0x04/0x05` degrees.
    /// That push *is* gimbal space — do not sweep the stick to build a map.
    /// Pan 0 is front; the positive arc passes selfie to raw −135° (= +225°).
    /// The other endpoint is −48°; the intervening negative arc is unreachable.
    public enum Reach {
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

    public enum CenterResult: Equatable, Sendable {
        case centered
        case waitingForGimbal
        case waitingForStill
        public var ok: Bool { self == .centered }
    }

    public static func wrapDeg(_ deg: Double) -> Double {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }

    /// Keep spinning past ±180 as a continuous look, not a wrap to the other stop.
    public static func unwrap(_ wrapped: Double, previous: Double) -> Double {
        previous + wrapDeg(wrapped - previous)
    }

    public static func radToDeg(_ rad: Double) -> Double { rad * 180 / .pi }
}
