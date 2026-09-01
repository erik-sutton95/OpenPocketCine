import Foundation

/// Shared local space: Calibrate Head Lock is identity (SET).
/// Look is the SET-relative nose azimuth/elevation (`Quat.look`, +Y
/// forward) — Euler Δatt yaw wobbles during a nod at a yawed heading
/// (18:29 take: diagonal drift). Stick throw closes a **dead-reckoned
/// model** of the gimbal onto that look — live `0x04/0x05` is ~0.25 s
/// stale at ~10 Hz, and a P loop closed on it limit-cycled (17:10 take:
/// head parked at +29°, gimbal swung 27→38→27, bobbing). We command the
/// velocity, so the model knows where the gimbal is *now*; stale
/// telemetry only bleeds drift out of the model, and is adopted
/// outright once provably stationary. Target rate feeds forward so the
/// gimbal moves while the head moves. Arrival streams center for
/// `restLinger` before lifting — grab/release in the same second paused
/// HEVC (22:24 and the 18:29 stall). Encode **linear**.
public struct HeadTrack: Equatable, Sendable {
    public static let restDeg = 1.2
    public static let engageDeg = 1.8
    /// Error that maps to full stick.
    public static let fullThrowDeg = 10.0
    /// Center-hold after arrival before lifting the stick. A gesture
    /// pause re-engages inside this with no grab; only a real stop
    /// lifts. Short enough that sustained center (15–30 s) never streams.
    public static let restLinger: TimeInterval = 1.0
    public static let calibrateStillRadPerSec = 0.08
    /// Full linear stick (±550) in Fast mode slews ~67°/s on both axes —
    /// measured from the 20:55 rvi0 capture of Mimo's own stick sweeps
    /// with the camera reporting Fast (`0x04/0x50` reply `05 01 00`).
    /// The Pocket handle joystick does ~82°/s; that headroom is not
    /// reachable through ±550. The first 40°/s estimate read decaying
    /// throw as full throw. ponytail: calibration knob — retune if
    /// `pred` races or trails `body` on the HUD.
    public static let stickRateDegPerSec = 67.0
    /// `0x04/0x05` age (17:10 take: live kept slewing ~10° after err read
    /// ~0). Fresh-but-moving samples are predicted forward by this before
    /// correcting the model.
    public static let telemetryLag: TimeInterval = 0.25
    /// Fresh (changed) telemetry bleeds this fraction into the model.
    public static let freshBlend = 0.15
    /// Same tenth-deg value this long = the gimbal truly stopped there.
    public static let stableAfter: TimeInterval = 0.3
    /// Stationary telemetry pulls the model per tick (25 Hz) — heals
    /// dead-reckoning drift as a single small settle, not a hunt.
    public static let stableBlend = 0.2
    /// Commanded this many degrees with telemetry never changing → the
    /// axis feed is dead (`@20` froze during a full-stick nod). Stop
    /// correcting from it; the model still closes, so no slam.
    public static let telemetryDeadDeg = 5.0
    /// EMA per tick for the target rate used as feed-forward.
    public static let targetRateSmooth = 0.3
    /// Below this target rate the head counts as still for rest.
    public static let restRateDegPerSec = 3.0
    /// At or above this target rate a rested track re-engages early.
    public static let engageRateDegPerSec = 8.0
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
        /// Lift the stick (`endGimbalStick`). Center-hold (x=y=0,
        /// rest=false) keeps streaming center through `restLinger` —
        /// grab/release in the same second paused HEVC (22:24, 18:29).
        /// Sustained center still lifts: 25 Hz center while calibrated
        /// paused HEVC after 15–30 s.
        public var rest: Bool

        public init(x: Double, y: Double, rest: Bool? = nil) {
            self.x = x
            self.y = y
            self.rest =
                rest ?? (abs(x) < HeadTrack.restThrow && abs(y) < HeadTrack.restThrow)
        }
    }

    /// One gimbal axis of the observer: dead-reckoned pose plus telemetry
    /// bleed, and the target-rate EMA that feeds forward.
    private struct AxisState: Equatable, Sendable {
        var model = 0.0
        var lastThrow = 0.0
        var lastSeenTenth: Int16?
        var stableFor: TimeInterval = 0
        var movedSinceFresh = 0.0
        var dead = false
        var prevTarget: Double?
        var rate = 0.0
        /// Feed-forward rate: min-magnitude of instant and EMA, zero on a
        /// sign split — collapses the moment the head stops so the EMA tail
        /// cannot push past the look.
        var ffRate = 0.0

        mutating func seed(_ deg: Double) {
            self = AxisState()
            model = deg
        }

        /// Dead-reckon with the throw we actually streamed last tick.
        mutating func integrate(dt: TimeInterval) {
            guard dt > 0 else { return }
            let step = lastThrow * HeadTrack.stickRateDegPerSec * dt
            model += step
            movedSinceFresh += abs(step)
        }

        mutating func observe(tenth: Int16?, dt: TimeInterval) {
            guard let tenth else { return }
            let live = HeadTrack.tenthToDeg(tenth)
            if tenth != lastSeenTenth {
                lastSeenTenth = tenth
                stableFor = 0
                dead = false
                movedSinceFresh = 0
                // Fresh but stale by `telemetryLag` — predict it forward by
                // our own commanded motion before bleeding it in.
                let predicted =
                    live + lastThrow * HeadTrack.stickRateDegPerSec * HeadTrack.telemetryLag
                model += HeadTrack.freshBlend * HeadTrack.wrapDeg(predicted - model)
                return
            }
            stableFor += dt
            if movedSinceFresh >= HeadTrack.telemetryDeadDeg { dead = true }
            guard !dead, stableFor >= HeadTrack.stableAfter else { return }
            model += HeadTrack.stableBlend * HeadTrack.wrapDeg(live - model)
        }

        mutating func noteTarget(_ target: Double, dt: TimeInterval) {
            defer { prevTarget = target }
            guard dt > 0, let prev = prevTarget else { return }
            let instant = HeadTrack.wrapDeg(target - prev) / dt
            rate += HeadTrack.targetRateSmooth * (instant - rate)
            ffRate =
                instant.sign == rate.sign
                ? (abs(instant) < abs(rate) ? instant : rate) : 0
        }
    }

    public private(set) var isCentered = false

    private var gimbalYaw0Deg = 0.0
    private var gimbalPitch0Deg = 0.0
    private var lookRightDeg = 0.0
    private var lookUpDeg = 0.0
    private var engaged = false
    private var holding = false
    private var restingFor: TimeInterval = 0
    private var pan = AxisState()
    private var tilt = AxisState()

    /// Observer pose for the HUD/log — where the model believes the gimbal
    /// is right now, ahead of stale `0x04/0x05`.
    public var modelYawDeg: Double { pan.model }
    public var modelTiltDeg: Double { tilt.model }

    public init() {}

    public mutating func reset() {
        isCentered = false
        engaged = false
        holding = false
        restingFor = 0
        lookRightDeg = 0
        lookUpDeg = 0
        pan = AxisState()
        tilt = AxisState()
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
        holding = false
        restingFor = 0
        pan.seed(gimbalYaw0Deg)
        tilt.seed(gimbalPitch0Deg)
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
        pan.integrate(dt: dt)
        tilt.integrate(dt: dt)
        pan.observe(tenth: gimbalYawTenth, dt: dt)
        tilt.observe(tenth: gimbalPitchTenth, dt: dt)
        // Feed-forward from the projected target, not the raw look — a look
        // pinned past a Reach stop must not keep pushing into it.
        pan.noteTarget(target.yaw, dt: dt)
        tilt.noteTarget(target.pitch, dt: dt)
        let errPan = Self.wrapDeg(target.yaw - pan.model)
        let errTilt = target.pitch - tilt.model
        let mag = (errPan * errPan + errTilt * errTilt).squareRoot()
        let still =
            abs(pan.rate) < Self.restRateDegPerSec && abs(tilt.rate) < Self.restRateDegPerSec
        let moving =
            abs(pan.rate) >= Self.engageRateDegPerSec
            || abs(tilt.rate) >= Self.engageRateDegPerSec
        if mag <= Self.restDeg, still {
            engaged = false
            return idle(dt: dt)
        }
        if !engaged {
            if mag < Self.engageDeg, !moving { return idle(dt: dt) }
            engaged = true
        }
        var x = throwFor(errPan) + pan.ffRate / Self.stickRateDegPerSec
        var y = throwFor(errTilt) + tilt.ffRate / Self.stickRateDegPerSec
        x = min(Swift.max(x, -Self.maxThrow), Self.maxThrow)
        y = min(Swift.max(y, -Self.maxThrow), Self.maxThrow)
        if abs(x) < Self.restThrow { x = 0 }
        if abs(y) < Self.restThrow { y = 0 }
        if x == 0, y == 0 {
            engaged = false
            return idle(dt: dt)
        }
        holding = true
        restingFor = 0
        pan.lastThrow = x
        tilt.lastThrow = y
        return Command(x: x, y: y, rest: false)
    }

    /// Zero throw. While `holding`, stream center for `restLinger` before
    /// lifting so a gesture pause is not a grab/release cycle.
    private mutating func idle(dt: TimeInterval) -> Command {
        pan.lastThrow = 0
        tilt.lastThrow = 0
        guard holding else { return Command(x: 0, y: 0, rest: true) }
        restingFor += dt
        guard restingFor >= Self.restLinger else { return Command(x: 0, y: 0, rest: false) }
        holding = false
        return Command(x: 0, y: 0, rest: true)
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
}
