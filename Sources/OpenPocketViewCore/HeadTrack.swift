import Foundation

/// Shared local space: Calibrate Head Lock is identity (SET).
/// Look is Euler Δatt yaw/pitch from that lock. Stick throw is live
/// `0x04/0x05` error onto that look. Pocket has no angle SET. Encode **linear**.
public struct HeadTrack: Equatable, Sendable {
    public static let restDeg = 1.2
    public static let engageDeg = 1.8
    public static let retargetDeg = 2.5
    public static let reengageDeg = retargetDeg
    /// Error that maps to full stick.
    public static let fullThrowDeg = 10.0
    public static let stillRestDeg = 2.5
    /// |look-right| inside this is a nod — do not servo pan (live-yaw wiggle).
    public static let panIsolateDeg = 3.0
    public static let gyroStillRadPerSec = 0.10
    public static let calibrateStillRadPerSec = 0.08
    public static let stillHold: TimeInterval = 0.25
    /// Full-stick tilt with live `@20` stuck: rest tilt (do not slam).
    /// Only arms at `|errTilt| ≥ fullThrowDeg` so a slow nod is not killed.
    public static let pitchLiveTimeout: TimeInterval = 0.55
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

    /// SET-relative heading from Euler yaw (inverted onto look-right).
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

        /// Pan around −Z then tilt around +X. Same frame as AirPods look.
        /// Twist around +Y is omitted — that is roll, not on `0x04/0x01`.
        public static func fromLook(rightDeg: Double, upDeg: Double) -> Quat {
            axisAngle(x: 0, y: 0, z: -1, deg: rightDeg)
                .multiply(axisAngle(x: 1, y: 0, z: 0, deg: upDeg))
        }

        /// SET-relative look in degrees. +right / +up from the nose (+Y).
        public static func look(from q: Quat, origin q0: Quat) -> (right: Double, up: Double) {
            let v = q0.conjugate.multiply(q).rotate((0, 1, 0))
            let right = atan2(v.x, v.y) * 180 / .pi
            let up = atan2(v.z, hypot(v.x, v.y)) * 180 / .pi
            return (right, up)
        }
    }

    /// Unit nose in SET space. +X right, +Y forward, +Z up.
    public static func nose(rightDeg: Double, upDeg: Double) -> (
        x: Double, y: Double, z: Double
    ) {
        let r = rightDeg * .pi / 180
        let u = upDeg * .pi / 180
        let cu = cos(u)
        return (sin(r) * cu, cos(r) * cu, sin(u))
    }

    /// Great-circle degrees between two noses. Roll does not appear.
    public static func geodesicDeg(
        fromRight: Double, fromUp: Double, toRight: Double, toUp: Double
    ) -> Double {
        let a = nose(rightDeg: fromRight, upDeg: fromUp)
        let b = nose(rightDeg: toRight, upDeg: toUp)
        let d = max(-1, min(1, a.x * b.x + a.y * b.y + a.z * b.z))
        return acos(d) * 180 / .pi
    }

    /// Swing-only error: pan/tilt motors plus geodesic magnitude.
    /// `pan`/`tilt` are the pan-tilt IK (Δazimuth / Δelevation). Magnitude
    /// is nose-to-nose so rest/engage is not Euler hypot.
    public static func swingError(
        fromRight: Double, fromUp: Double, toRight: Double, toUp: Double
    ) -> (pan: Double, tilt: Double, mag: Double) {
        (
            wrapDeg(toRight - fromRight),
            toUp - fromUp,
            geodesicDeg(fromRight: fromRight, fromUp: fromUp, toRight: toRight, toUp: toUp)
        )
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
    private var engaged = false
    private var tiltThrowElapsed: TimeInterval = 0
    private var pitchWhenTiltBegan: Double?
    private var tiltTelemetryDead = false

    public init() {}

    public mutating func reset() {
        isCentered = false
        engaged = false
        lookRightDeg = 0
        lookUpDeg = 0
        tiltThrowElapsed = 0
        pitchWhenTiltBegan = nil
        tiltTelemetryDead = false
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
        engaged = false
        tiltThrowElapsed = 0
        pitchWhenTiltBegan = nil
        tiltTelemetryDead = false
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
        _ = (gyroLookRight, gyroLookUp, gyroYaw)
        lookRightDeg = Self.unwrap(wrappedRight, previous: lookRightDeg)
        lookUpDeg = Self.unwrap(wrappedUp, previous: lookUpDeg)
        let target = Reach.project(
            lookRight: lookRightDeg, lookUp: lookUpDeg,
            yaw0: gimbalYaw0Deg, pitch0: gimbalPitch0Deg)
        let liveYaw = Self.tenthToDeg(gimbalYawTenth)
        let liveTilt = gimbalPitchTenth.map(Self.tenthToDeg) ?? gimbalPitch0Deg
        var errPan = Self.wrapDeg(target.yaw - liveYaw)
        if abs(lookRightDeg) <= Self.panIsolateDeg, abs(lookUpDeg) > abs(lookRightDeg) {
            errPan = 0
        }
        var errTilt = target.pitch - liveTilt
        let mag = (errPan * errPan + errTilt * errTilt).squareRoot()
        noteFrozenTilt(
            liveTilt: liveTilt, errTilt: &errTilt, dt: dt,
            tracking: engaged || mag >= Self.engageDeg)
        if mag <= Self.restDeg {
            engaged = false
            return Command(x: 0, y: 0)
        }
        if !engaged {
            if mag < Self.engageDeg { return Command(x: 0, y: 0) }
            engaged = true
        }
        var x = throwFor(errPan)
        var y = throwFor(errTilt)
        if abs(x) < Self.restThrow { x = 0 }
        if abs(y) < Self.restThrow { y = 0 }
        if x == 0, y == 0 { engaged = false }
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

    private func throwFor(_ errorDeg: Double) -> Double {
        if abs(errorDeg) < 0.5 { return 0 }
        let n = errorDeg / Self.fullThrowDeg
        return min(max(n, -Self.maxThrow), Self.maxThrow)
    }

    /// `@20` stuck during a *full-stick* nod: rest tilt so we do not slam.
    /// Slow proportional nods must not arm this.
    private mutating func noteFrozenTilt(
        liveTilt: Double, errTilt: inout Double, dt: TimeInterval, tracking: Bool
    ) {
        if tiltTelemetryDead {
            let origin = pitchWhenTiltBegan ?? gimbalPitch0Deg
            if abs(liveTilt - origin) >= 1 {
                tiltTelemetryDead = false
                tiltThrowElapsed = 0
                pitchWhenTiltBegan = nil
            } else {
                errTilt = 0
                return
            }
        }
        guard tracking, abs(errTilt) >= Self.fullThrowDeg, dt > 0 else {
            tiltThrowElapsed = 0
            pitchWhenTiltBegan = nil
            return
        }
        if pitchWhenTiltBegan == nil { pitchWhenTiltBegan = liveTilt }
        tiltThrowElapsed += dt
        if tiltThrowElapsed >= Self.pitchLiveTimeout,
            abs(liveTilt - (pitchWhenTiltBegan ?? liveTilt)) < 1
        {
            tiltTelemetryDead = true
            errTilt = 0
        }
    }
}
