import Foundation

/// Shared local space: Calibrate Head Lock is identity (SET).
/// Look is the SET-relative nose on the sphere, not Euler Δatt yaw —
/// a nod changes Euler yaw tens of degrees with the nose still on the
/// meridian. The Pocket stick is pan+tilt only — roll is not on `0x04/0x01`.
/// Encode **linear**. Stick throw closes live `0x04/0x05` onto that pose.
public struct HeadTrack: Equatable, Sendable {
    public static let restDeg = 1.2
    public static let engageDeg = 1.8
    /// After a 1:1 close, live yaw wiggle (~2°) must not re-grab the stick.
    /// 22:24 rest/throw in the same second paused HEVC.
    public static let reengageDeg = 4.0
    /// Bang-bang: any error past rest is full stick. `/ 10°` was a 10× crawl.
    public static let fullThrowDeg = 1.2
    public static let stillRestDeg = 2.5
    /// |look-right| inside this is a nod — do not servo pan (live-yaw wiggle).
    public static let panIsolateDeg = 3.0
    public static let tiltRatePerSecond = 45.0
    public static let gyroStillRadPerSec = 0.10
    public static let calibrateStillRadPerSec = 0.08
    /// After this of still, rest the stick (look stays on the sphere).
    public static let stillHold: TimeInterval = 0.25
    /// Mimo virtual joystick full throw is 1024 ±550 (`GimbalStick.max`).
    public static let maxThrow = 1.0
    /// Below `GimbalStick.axisLinear` snap (0.02) both axes encode as center.
    /// Treat that as rest — 22:24 streamed `y=-0.01` and paused HEVC.
    public static let restThrow = 0.02

    public static func gyroMagnitude(lookRight: Double, lookUp: Double, yaw: Double = 0)
        -> Double
    {
        (lookRight * lookRight + lookUp * lookUp + yaw * yaw).squareRoot()
    }

    /// Head-turn gyro around AirPods Z (physical take: heading tracked `rotationRate.z`).
    public static func deltaLookRightDeg(yawRadPerSec: Double, dt: TimeInterval) -> Double {
        yawRadPerSec * dt * 180 / .pi
    }

    /// SET-relative heading from Euler yaw. A nod changes this tens of degrees
    /// while the nose stays on the meridian — prefer ``look(current:origin:)``.
    public static func lookRightDeg(yawRad: Double, originYawRad: Double) -> Double {
        wrapDeg(radToDeg(originYawRad - yawRad))
    }

    /// SET-relative nod. Physical take: att pitch more negative is nod down;
    /// stick `y+` is tilt up.
    public static func lookUpDeg(pitchRad: Double, originPitchRad: Double) -> Double {
        radToDeg(pitchRad - originPitchRad)
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

    /// Pocket 4 / 4 Pro controllable range (DJI spec) in `0x04/0x05` degrees.
    /// That push *is* gimbal space — do not sweep the stick to build a map.
    /// Pan 0 is front; + is the short side; − is the long side (selfie ~−180).
    /// The gap past +58° is not a stick wrap — 180 is `FE 09`.
    public enum Reach {
        public static let panMinDeg = -235.0
        public static let panMaxDeg = 58.0
        public static let tiltMinDeg = -120.0
        public static let tiltMaxDeg = 70.0

        public static func clampPan(_ deg: Double) -> Double {
            min(max(deg, panMinDeg), panMaxDeg)
        }

        public static func clampTilt(_ deg: Double) -> Double {
            min(max(deg, tiltMinDeg), tiltMaxDeg)
        }

        /// Unbounded SET-relative look → nearest reachable yaw/pitch.
        /// Interval expands to include SET so a lock at selfie (~−180) does not slam.
        public static func project(
            lookRight: Double, lookUp: Double, yaw0: Double, pitch0: Double
        ) -> (yaw: Double, pitch: Double) {
            let panLo = min(panMinDeg, yaw0)
            let panHi = max(panMaxDeg, yaw0)
            let tiltLo = min(tiltMinDeg, pitch0)
            let tiltHi = max(tiltMaxDeg, pitch0)
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

    public struct Command: Equatable, Sendable {
        public var x: Double
        public var y: Double
        /// Zero throw. Live shell **lifts** (`endGimbalStick`) — streaming
        /// center at 25 Hz while calibrated paused HEVC after 15–30 s.
        /// Tiny leftovers encode as center (`axisLinear` snaps |n|<0.02).
        public var rest: Bool {
            abs(x) < HeadTrack.restThrow && abs(y) < HeadTrack.restThrow
        }

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public private(set) var isCentered = false

    private var gimbalYaw0Deg = 0.0
    private var gimbalPitch0Deg = 0.0
    private var lookRightDeg = 0.0
    private var lookUpDeg = 0.0
    private var lastSignX = 0.0
    private var lastSignY = 0.0
    private var engaged = false
    /// Rested after a throw. Stay silent until the *head* moves `reengageDeg`.
    private var parked = false
    private var restLookRight = 0.0
    private var restLookUp = 0.0
    private var stillFor: TimeInterval = 0

    public init() {}

    public mutating func reset() {
        isCentered = false
        engaged = false
        parked = false
        lookRightDeg = 0
        lookUpDeg = 0
        restLookRight = 0
        restLookUp = 0
        lastSignX = 0
        lastSignY = 0
        stillFor = 0
    }

    @discardableResult
    public mutating func center(
        gimbalYawTenth: Int16?, gimbalPitchTenth: Int16?,
        gyroLookRight: Double = 0, gyroLookUp: Double = 0, gyroYaw: Double = 0
    ) -> CenterResult {
        guard let gimbalYawTenth else { return .waitingForGimbal }
        let moving =
            Self.gyroMagnitude(lookRight: gyroLookRight, lookUp: gyroLookUp, yaw: gyroYaw)
            >= Self.calibrateStillRadPerSec
        if moving { return .waitingForStill }
        gimbalYaw0Deg = Self.tenthToDeg(gimbalYawTenth)
        gimbalPitch0Deg = gimbalPitchTenth.map(Self.tenthToDeg) ?? 0
        lookRightDeg = 0
        lookUpDeg = 0
        restLookRight = 0
        restLookUp = 0
        lastSignX = 0
        lastSignY = 0
        engaged = false
        parked = false
        stillFor = 0
        isCentered = true
        return .centered
    }

    public mutating func tick(
        lookRightDeg wrappedRight: Double, lookUpDeg wrappedUp: Double,
        gimbalYawTenth: Int16?, gimbalPitchTenth: Int16?,
        dt: TimeInterval = 0, gyroLookRight: Double = 0, gyroLookUp: Double = 0,
        gyroYaw: Double = 0
    ) -> Command? {
        guard isCentered, let gimbalYawTenth else { return nil }
        let gyroMag = Self.gyroMagnitude(
            lookRight: gyroLookRight, lookUp: gyroLookUp, yaw: gyroYaw)
        let still = dt > 0 && gyroMag < Self.gyroStillRadPerSec
        lookRightDeg = Self.unwrap(wrappedRight, previous: lookRightDeg)
        lookUpDeg = Self.unwrap(wrappedUp, previous: lookUpDeg)
        let target = Reach.project(
            lookRight: lookRightDeg, lookUp: lookUpDeg,
            yaw0: gimbalYaw0Deg, pitch0: gimbalPitch0Deg)
        let liveYaw = Self.tenthToDeg(gimbalYawTenth)
        var errPan = Self.wrapDeg(target.yaw - liveYaw)
        if abs(lookRightDeg) <= Self.panIsolateDeg, abs(lookUpDeg) > abs(lookRightDeg) {
            errPan = 0
        }
        let liveTilt = gimbalPitchTenth.map(Self.tenthToDeg) ?? gimbalPitch0Deg
        let errTilt = target.pitch - liveTilt
        if still {
            stillFor += max(dt, 0)
        } else {
            stillFor = 0
        }
        var x: Double
        var y: Double
        (x, y) = gatedThrow(errPan: errPan, errTilt: errTilt)
        x = holdOvershoot(x, look: lookRightDeg, lastSign: lastSignX)
        y = holdOvershoot(y, look: lookUpDeg, lastSign: lastSignY)
        if abs(x) < Self.restThrow { x = 0 }
        if abs(y) < Self.restThrow { y = 0 }
        noteSign(x: x, y: y)
        return Command(x: x, y: y)
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

    public static func tenthToDeg(_ tenth: Int16) -> Double { Double(tenth) / 10 }

    private mutating func gatedThrow(errPan: Double, errTilt: Double) -> (Double, Double) {
        let mag = (errPan * errPan + errTilt * errTilt).squareRoot()
        if engaged {
            if mag <= Self.restDeg {
                engaged = false
                parked = true
                restLookRight = lookRightDeg
                restLookUp = lookUpDeg
                return (0, 0)
            }
        } else if parked {
            if mag <= Self.restDeg {
                restLookRight = lookRightDeg
                restLookUp = lookUpDeg
                return (0, 0)
            }
            let lookMove =
                ((lookRightDeg - restLookRight) * (lookRightDeg - restLookRight)
                + (lookUpDeg - restLookUp) * (lookUpDeg - restLookUp)).squareRoot()
            if lookMove < Self.reengageDeg || mag < Self.engageDeg {
                return (0, 0)
            }
            parked = false
            engaged = true
        } else if mag < Self.engageDeg {
            return (0, 0)
        } else {
            engaged = true
        }
        return (throwFor(errPan), throwFor(errTilt))
    }

    private func throwFor(_ errorDeg: Double) -> Double {
        if abs(errorDeg) < 0.5 { return 0 }
        return errorDeg < 0 ? -Self.maxThrow : Self.maxThrow
    }

    /// Live yaw overshot: do not reverse while the nose is still that way.
    private func holdOvershoot(_ throw: Double, look: Double, lastSign: Double) -> Double {
        if lastSign != 0, `throw` * lastSign < 0, look * lastSign >= 0 { return 0 }
        return `throw`
    }

    private mutating func noteSign(x: Double, y: Double) {
        if x != 0 { lastSignX = x < 0 ? -1 : 1 }
        if y != 0 { lastSignY = y < 0 ? -1 : 1 }
    }
}
