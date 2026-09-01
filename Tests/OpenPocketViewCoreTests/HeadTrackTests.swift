import Foundation
import Testing

@testable import OpenPocketViewCore

/// Pocket plant for closed-loop tests: integrates stick × rate, publishes
/// `0x04/0x05` tenth-degree telemetry at ~10 Hz, ~0.24 s stale — the delay
/// that limit-cycled the old telemetry-closed loop (17:10 take).
private struct PocketSim {
    var yaw: Double
    var tilt: Double
    var fullStickDegPerSec = HeadTrack.stickRateDegPerSec
    var delay = 0.24
    var sampleEvery = 0.1
    var panStop: ClosedRange<Double>?
    var tiltFrozen = false
    private var t = 0.0
    private var lastSample = 0.0
    private var trail: [(t: Double, yaw: Double, tilt: Double)]
    private(set) var yawTenth: Int16
    private(set) var tiltTenth: Int16

    init(yaw: Double = 0, tilt: Double = 0) {
        self.yaw = yaw
        self.tilt = tilt
        trail = [(0, yaw, tilt)]
        yawTenth = Int16((yaw * 10).rounded())
        tiltTenth = Int16((tilt * 10).rounded())
    }

    mutating func step(x: Double, y: Double, dt: Double) {
        t += dt
        yaw += x * fullStickDegPerSec * dt
        if let panStop { yaw = min(max(yaw, panStop.lowerBound), panStop.upperBound) }
        tilt += y * fullStickDegPerSec * dt
        trail.append((t, yaw, tilt))
        guard t - lastSample >= sampleEvery else { return }
        lastSample = t
        let cut = t - delay
        let past = trail.last(where: { $0.t <= cut }) ?? trail[0]
        yawTenth = Int16((past.yaw * 10).rounded())
        if !tiltFrozen { tiltTenth = Int16((past.tilt * 10).rounded()) }
    }
}

@Suite struct HeadTrackTests {
    /// Drive the loop at the 25 Hz pump. Head looks are functions of time.
    private func run(
        _ track: inout HeadTrack, _ sim: inout PocketSim,
        seconds: Double,
        lookRight: (Double) -> Double = { _ in 0 },
        lookUp: (Double) -> Double = { _ in 0 },
        onTick: ((Double, HeadTrack.Command?, PocketSim) -> Void)? = nil
    ) {
        let dt = 0.04
        var t = 0.0
        while t < seconds {
            let cmd = track.tick(
                lookRightDeg: lookRight(t), lookUpDeg: lookUp(t),
                gimbalYawTenth: sim.yawTenth, gimbalPitchTenth: sim.tiltTenth, dt: dt)
            sim.step(x: cmd?.x ?? 0, y: cmd?.y ?? 0, dt: dt)
            t += dt
            onTick?(t, cmd, sim)
        }
    }

    /// Head swings 20° right and parks. 17:10 take: the telemetry-closed
    /// loop blew ~9° past and bobbed (body 27.9→38.3→27.5→26.3). The
    /// model-closed loop must arrive without a swing-back cycle.
    @Test func swingToTwentySettlesWithoutBobbing() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var sim = PocketSim()
        var maxYaw = 0.0
        var flips = 0
        var lastSign = 0
        run(
            &track, &sim, seconds: 3,
            lookRight: { min(20, 100 * $0) },
            onTick: { _, cmd, sim in
                maxYaw = max(maxYaw, sim.yaw)
                let sign = (cmd?.x ?? 0) > 0 ? 1 : (cmd?.x ?? 0) < 0 ? -1 : 0
                if sign != 0, lastSign != 0, sign != lastSign { flips += 1 }
                if sign != 0 { lastSign = sign }
            })
        #expect(maxYaw < 23, "overshoot past a parked 20° look is the bob")
        #expect(abs(sim.yaw - 20) < 1.5, "gimbal must arrive at the look")
        #expect(flips <= 1, "sign flip after arrival is reverse-hunt")
        var rested = true
        run(
            &track, &sim, seconds: 1, lookRight: { _ in 20 },
            onTick: { _, cmd, _ in
                if cmd?.rest != true { rested = false }
            })
        #expect(rested, "parked head and arrived gimbal must hold rest")
    }

    /// A slow deliberate pan must track 1:1 the whole way — never park at
    /// engage hysteresis mid-motion, never lag more than a few degrees.
    @Test func slowRampTracksWithoutParking() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var sim = PocketSim()
        var parked = false
        run(
            &track, &sim, seconds: 1.0,
            lookRight: { 30 * $0 },
            onTick: { t, cmd, sim in
                guard t > 0.3 else { return }
                if cmd?.x ?? 0 <= 0 { parked = true }
                #expect(30 * t - sim.yaw < 8, "ramp lag beyond 8° is not following")
            })
        #expect(!parked, "a moving look must keep the stick thrown")
        run(&track, &sim, seconds: 2, lookRight: { _ in 30 })
        #expect(abs(sim.yaw - 30) < 1.5)
    }

    /// `@20` froze during a full-stick nod (physical take). Dead telemetry
    /// must stop correcting the model — the nod still closes and rests, and
    /// the tilt must not slam toward the stop.
    @Test func frozenTiltTelemetryClosesWithoutSlam() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var sim = PocketSim()
        sim.tiltFrozen = true
        var maxTilt = 0.0
        run(
            &track, &sim, seconds: 3,
            lookUp: { min(20, 100 * $0) },
            onTick: { _, _, sim in maxTilt = max(maxTilt, sim.tilt) })
        #expect(maxTilt < 25, "frozen @20 must not slam tilt past the look")
        #expect(abs(sim.tilt - 20) < 2, "model still closes the nod")
        var rested = true
        run(
            &track, &sim, seconds: 1, lookUp: { _ in 20 },
            onTick: { _, cmd, _ in
                if cmd?.rest != true { rested = false }
            })
        #expect(rested, "frozen telemetry must not re-arm a closed nod")
    }

    /// Plant ~25% slower than the model prior: dead-reckoning rests
    /// early, stationary telemetry pulls the model home, and the
    /// leftover closes as a nudge — the sky arrow must reach the look.
    @Test func slowerPlantNudgesHomeAfterStableTelemetry() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var sim = PocketSim()
        sim.fullStickDegPerSec = HeadTrack.stickRateDegPerSec * 0.75
        run(&track, &sim, seconds: 5, lookRight: { min(20, 100 * $0) })
        #expect(abs(sim.yaw - 20) < 1.5, "stable live short of the look must nudge home")
    }

    /// Plant ~20% faster than the model prior: physical overshoot
    /// stays small and stationary telemetry brings it back without a hunt.
    @Test func fasterPlantComesBackWithoutHunting() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var sim = PocketSim()
        sim.fullStickDegPerSec = HeadTrack.stickRateDegPerSec * 1.2
        var maxYaw = 0.0
        run(
            &track, &sim, seconds: 5, lookRight: { min(20, 100 * $0) },
            onTick: { _, _, sim in maxYaw = max(maxYaw, sim.yaw) })
        #expect(maxYaw < 25, "20% rate error must not become a slam")
        #expect(
            abs(sim.yaw - 20) < HeadTrack.engageDeg + 0.3,
            "parked error beyond the re-engage band is a real miss")
        var travel = 0.0
        var last = sim.yaw
        run(
            &track, &sim, seconds: 1.5, lookRight: { _ in 20 },
            onTick: { _, _, sim in
                travel += abs(sim.yaw - last)
                last = sim.yaw
            })
        #expect(travel < 2, "settled loop must not keep sawing")
    }

    /// A look past the +58° pan stop pins the target at the stop: arrive,
    /// rest, no pressing. Looking back inside the box leaves the stop.
    @Test func lookPastPanStopRestsThenFollowsBack() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var sim = PocketSim()
        sim.panStop = HeadTrack.Reach.panMinDeg...HeadTrack.Reach.panMaxDeg
        run(&track, &sim, seconds: 4, lookRight: { min(90, 120 * $0) })
        #expect(abs(sim.yaw - HeadTrack.Reach.panMaxDeg) < 1.5, "projected look is the stop")
        var rested = true
        run(
            &track, &sim, seconds: 1, lookRight: { _ in 90 },
            onTick: { _, cmd, _ in
                if cmd?.rest != true { rested = false }
            })
        #expect(rested, "pinned at the stop must rest, not press")
        run(&track, &sim, seconds: 4, lookRight: { max(20, 90 - 120 * $0) })
        #expect(abs(sim.yaw - 20) < 1.5, "looking back inside the box leaves the stop")
    }

    /// Head turns the other way before arrival: new destination, reverse.
    @Test func retargetTurnsAroundBeforeArrival() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let go = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(go?.x == HeadTrack.maxThrow)
        let around = track.tick(
            lookRightDeg: -15, lookUpDeg: 0, gimbalYawTenth: 80, gimbalPitchTenth: 0)
        #expect(
            around?.x == -HeadTrack.maxThrow,
            "head turns the other way before arrival: new destination, reverse")
    }

    @Test func axisDialsFollowLook() {
        #expect(HeadTrack.yawDialDeg(lookRightDeg: 90) == 90)
        #expect(HeadTrack.yawDialDeg(lookRightDeg: -45) == -45)
        #expect(HeadTrack.pitchDialDeg(lookUpDeg: 0) == 90, "level look points right")
        #expect(HeadTrack.pitchDialDeg(lookUpDeg: 30) == 60, "nod up from 3 o'clock")
        #expect(HeadTrack.pitchDialDeg(lookUpDeg: -20) == 110, "nod down from 3 o'clock")
        #expect(abs(HeadTrack.yawDialDeg(lookRightDeg: 270) - -90) < 0.001)
        #expect(HeadTrack.bodyLookRightDeg(liveYawDeg: 30, originYawDeg: 10) == 20)
        #expect(
            abs(HeadTrack.bodyLookRightDeg(liveYawDeg: -170, originYawDeg: 170) - 20) < 0.001,
            "gimbal pan wraps the same as head yaw")
        #expect(HeadTrack.bodyLookUpDeg(livePitchDeg: 25, originPitchDeg: 5) == 20)
        #expect(
            HeadTrack.yawDialDeg(
                lookRightDeg: HeadTrack.bodyLookRightDeg(liveYawDeg: 90, originYawDeg: 0)) == 90)
        #expect(
            HeadTrack.pitchDialDeg(
                lookUpDeg: HeadTrack.bodyLookUpDeg(livePitchDeg: 30, originPitchDeg: 0)) == 60)
    }

    @Test func tickIsNilUntilCentered() {
        var track = HeadTrack()
        #expect(
            track.tick(lookRightDeg: 0, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
                == nil)
        let missing = track.center(gimbalYawTenth: nil, gimbalPitchTenth: 0)
        #expect(missing == .waitingForGimbal)
        let yawOnly = track.center(gimbalYawTenth: 0, gimbalPitchTenth: nil)
        #expect(yawOnly == .centered)
        track.reset()
        let ok = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(ok == .centered)
        let cmd = track.tick(
            lookRightDeg: 0, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(cmd?.rest == true, "SET pose must not throw — a slam at center is a frame bug")
        #expect(cmd?.x == 0 && cmd?.y == 0)
    }

    @Test func restMeansTheShellLifts() {
        let rest = HeadTrack.Command(x: 0, y: 0)
        #expect(rest.rest, "shell must endGimbalStick — 25 Hz center paused HEVC")
        #expect(!HeadTrack.Command(x: 0.2, y: 0).rest)
        #expect(!HeadTrack.Command(x: 0, y: -0.1).rest)
        #expect(
            HeadTrack.Command(x: 0, y: -0.01).rest,
            "y=-0.01 encodes as center (axisLinear snap) — 22:24 streamed that and paused HEVC")
    }

    @Test func heldLookClosesEvenWhenGyroIsQuiet() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: 90, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0,
            dt: 0.04)
        #expect(cmd != nil)
        #expect(
            cmd!.x == HeadTrack.maxThrow,
            "a 90° look must throw even if the head already stopped")
    }

    @Test func yawGyroCountsAsMovingForCalibrate() {
        var track = HeadTrack()
        let moving = track.center(
            gimbalYawTenth: 0, gimbalPitchTenth: 0, gyroYaw: HeadTrack.calibrateStillRadPerSec * 2)
        #expect(moving == .waitingForStill)
        #expect(!track.isCentered)
    }

    @Test func lookingLeftPansLeft() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: -20, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(cmd != nil)
        #expect(cmd!.x == -HeadTrack.maxThrow)
    }

    @Test func lookingUpTiltsUp() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(cmd != nil)
        #expect(cmd!.y == HeadTrack.maxThrow)
        #expect(cmd!.x == 0)
    }

    /// 18:29 take: rest→throw in the same second paused HEVC. Arrival must
    /// stream center through `restLinger`; a head move inside the linger
    /// resumes throw with no lift in between; only a real stop lifts.
    @Test func arrivalLingersBeforeLiftAndResumesWithoutRegrab() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var sim = PocketSim()
        run(&track, &sim, seconds: 1.5, lookRight: { min(20, 100 * $0) })
        var sawLift = false
        var resumed = false
        run(
            &track, &sim, seconds: 0.5, lookRight: { t in 20 + 80 * t },
            onTick: { _, cmd, _ in
                if cmd?.rest == true { sawLift = true }
                if abs(cmd?.x ?? 0) > 0 { resumed = true }
            })
        #expect(resumed, "a head move during the linger resumes throw")
        #expect(!sawLift, "no lift between arrival and the next gesture — that chatter paused HEVC")
        run(&track, &sim, seconds: 0.9, lookRight: { _ in 60 })
        var holds = 0
        var lifts = 0
        run(
            &track, &sim, seconds: 1.5, lookRight: { _ in 60 },
            onTick: { _, cmd, _ in
                if cmd?.rest == true {
                    lifts += 1
                } else if cmd?.x == 0, cmd?.y == 0 {
                    holds += 1
                }
            })
        #expect(holds > 5, "arrival streams center before lifting")
        #expect(lifts > 0, "a real stop still lifts after the linger")
    }

    @Test func yawWrapsAround180() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: -1700, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: -1700, gimbalPitchTenth: 0)
        #expect(cmd != nil)
        #expect(cmd!.x == HeadTrack.maxThrow)
    }

    @Test func projectClampsToControllableBox() {
        let past = HeadTrack.Reach.project(
            lookRight: 90, lookUp: 80, yaw0: 0, pitch0: 0)
        #expect(past.yaw == HeadTrack.Reach.panMaxDeg)
        #expect(past.pitch == HeadTrack.Reach.tiltMaxDeg)
        let left = HeadTrack.Reach.project(
            lookRight: -300, lookUp: -200, yaw0: 0, pitch0: 0)
        #expect(left.yaw == HeadTrack.Reach.panMinDeg)
        #expect(left.pitch == HeadTrack.Reach.tiltMinDeg)
        let selfie = HeadTrack.Reach.project(
            lookRight: 20, lookUp: 0, yaw0: -170, pitch0: 0)
        #expect(selfie.yaw == -150)
    }

    @Test func unwrapKeepsSpinningPast180() {
        #expect(HeadTrack.unwrap(170, previous: 160) == 170)
        #expect(HeadTrack.unwrap(-170, previous: 170) == 190)
        #expect(HeadTrack.unwrap(10, previous: 350) == 370)
    }

    @Test func noseLookNodHasNoPan() {
        let origin = HeadTrack.Quat.identity
        let nod = HeadTrack.Quat.axisAngle(x: 1, y: 0, z: 0, deg: 25)
        let look = HeadTrack.Quat.look(from: nod, origin: origin)
        #expect(abs(look.right) < 0.01, "a pure nod must not invent look-right")
        #expect(abs(look.up - 25) < 0.01)
        let pan = HeadTrack.Quat.axisAngle(x: 0, y: 0, z: -1, deg: 25)
        let side = HeadTrack.Quat.look(from: pan, origin: origin)
        #expect(abs(side.up) < 0.01)
        #expect(abs(side.right - 25) < 0.01)
        let pan90 = HeadTrack.Quat.axisAngle(x: 0, y: 0, z: -1, deg: 90)
        let side90 = HeadTrack.Quat.look(from: pan90, origin: origin)
        #expect(abs(side90.right - 90) < 0.01, "a 90° head turn is 90° on the sphere")
        let still = HeadTrack.Quat.look(from: origin, origin: origin)
        #expect(abs(still.right) < 0.001 && abs(still.up) < 0.001)
        let roll = HeadTrack.Quat.axisAngle(x: 0, y: 1, z: 0, deg: 40)
        let rolled = HeadTrack.Quat.look(from: roll, origin: origin)
        #expect(abs(rolled.right) < 1, "yaw is not roll")
        #expect(abs(rolled.up) < 1)
        let nodDown = HeadTrack.Quat.axisAngle(x: -1, y: 0, z: 0, deg: 25)
        let down = HeadTrack.Quat.look(from: nodDown, origin: origin)
        #expect(abs(down.right) < 0.01, "a nod down must not invent look-right")
        #expect(abs(down.up + 25) < 0.01, "nod down is negative look-up")
        let yawed = HeadTrack.Quat.axisAngle(x: 0, y: 0, z: -1, deg: 30)
        let nodAfter = yawed.multiply(HeadTrack.Quat.axisAngle(x: 1, y: 0, z: 0, deg: 40))
        let kept = HeadTrack.look(current: nodAfter, origin: origin)
        #expect(abs(kept.right - 30) < 1.5, "a nod must not add Euler yaw onto look-right")
        #expect(abs(kept.up - 40) < 1.5)
    }

    @Test func deadzoneThenHysteresis() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(
            track.tick(
                lookRightDeg: 1.2, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0
            )?.rest == true)
        let moving = track.tick(
            lookRightDeg: 4, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(moving != nil)
        #expect(moving!.x > 0)
        let still = track.tick(
            lookRightDeg: 2, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(still != nil)
        #expect(still!.x > 0)
        let arrived = track.tick(
            lookRightDeg: 0.4, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(arrived?.x == 0 && arrived?.y == 0)
        #expect(arrived?.rest == false, "arrival center-holds through the linger")
        var last: HeadTrack.Command?
        for _ in 0..<30 {
            last = track.tick(
                lookRightDeg: 0.4, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0,
                dt: 0.04)
        }
        #expect(last?.rest == true, "a real stop lifts once the linger expires")
    }

    @Test func resetClearsCenter() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        track.reset()
        #expect(!track.isCentered)
        #expect(
            track.tick(lookRightDeg: 0, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
                == nil)
    }

    @Test func centerRejectsAMovingHead() {
        var track = HeadTrack()
        let moving = track.center(
            gimbalYawTenth: 0, gimbalPitchTenth: 0,
            gyroLookRight: HeadTrack.calibrateStillRadPerSec * 2)
        #expect(moving == .waitingForStill)
        #expect(!track.isCentered)
        let still = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(still == .centered)
    }

    @Test func gyroYawLookRightIsOneToOne() {
        let dt = 0.125
        var right = 0.0
        for _ in 0..<16 {
            right += HeadTrack.deltaLookRightDeg(yawRadPerSec: .pi / 4, dt: dt)
        }
        #expect(abs(right - 90) < 0.5, "2 s of +π/4 gyro-Z is a 90° look-right")
    }

    @Test func yaw90AroundHeadUpIsLookRightOnTheNose() {
        let q0 = HeadTrack.Quat.identity
        let q = HeadTrack.Quat.axisAngle(x: 0, y: 0, z: -1, deg: 90)
        let look = HeadTrack.Quat.look(from: q, origin: q0)
        #expect(abs(look.right - 90) < 0.5, "90° around up (+Z) toward +X is look-right")
        #expect(abs(look.up) < 0.5)
    }

    @Test func nodDownIsLookDown() {
        let up = HeadTrack.lookUpDeg(pitchRad: -0.2, originPitchRad: 0)
        #expect(up < 0, "att pitch more negative is nod down; stick y+ is tilt up")
        #expect(abs(up + HeadTrack.radToDeg(0.2)) < 0.01)
    }

    @Test func attitudeYawIsOneToOnePan() {
        let right = HeadTrack.lookRightDeg(yawRad: -.pi / 2, originYawRad: 0)
        #expect(abs(right - 90) < 0.01, "inverted Δatt yaw is look-right")
        let left = HeadTrack.lookRightDeg(yawRad: .pi / 3, originYawRad: 0)
        #expect(abs(left + 60) < 0.01)
    }

    @Test func twoDegLagIsProportionalNotBangBang() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: 2, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(cmd != nil)
        #expect(cmd!.x > HeadTrack.restThrow)
        #expect(
            abs(cmd!.x - 2 / HeadTrack.fullThrowDeg) < 0.001,
            "2° lag is error/fullThrowDeg, not bang-bang")
        #expect(cmd!.x < HeadTrack.maxThrow)
    }

    @Test func eightDegLagIsFullStick() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: HeadTrack.fullThrowDeg, lookUpDeg: 0, gimbalYawTenth: 0,
            gimbalPitchTenth: 0)
        #expect(cmd?.x == HeadTrack.maxThrow)
    }

    @Test func catchUpThrowMatchesMimoFullStick() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: 90, lookUpDeg: 40, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(cmd != nil)
        #expect(abs(cmd!.x) == 1.0, "Mimo virtual joystick full throw is ±550")
        #expect(abs(cmd!.y) == 1.0)
        #expect(HeadTrack.maxThrow == 1.0)
    }

    @Test func wrapDegFoldsAround180() {
        #expect(HeadTrack.wrapDeg(190) == -170)
        #expect(HeadTrack.wrapDeg(-190) == 170)
        #expect(abs(HeadTrack.wrapDeg(180)) == 180)
        #expect(HeadTrack.wrapDeg(20) == 20)
    }

    @Test func smallTiltRidesWithPan() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: 10, lookUpDeg: 1, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(cmd != nil)
        #expect(cmd!.x > 0)
        #expect(cmd!.y > 0, "a 1° nod must not die behind a 10° pan")
        #expect(abs(cmd!.x - min(10 / HeadTrack.fullThrowDeg, HeadTrack.maxThrow)) < 0.001)
        #expect(abs(cmd!.y - 1 / HeadTrack.fullThrowDeg) < 0.001)
    }

    @Test func lookingBackTiltsTheOtherWay() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let up = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(up?.y == HeadTrack.maxThrow)
        let back = track.tick(
            lookRightDeg: 0, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(back?.x == 0 && back?.y == 0, "matched look center-holds the stick")
    }

    @Test func fromLookReconstructsTheNose() {
        let origin = HeadTrack.Quat.identity
        let q = HeadTrack.Quat.fromLook(rightDeg: 20, upDeg: -15)
        let look = HeadTrack.Quat.look(from: q, origin: origin)
        #expect(abs(look.right - 20) < 0.01)
        #expect(abs(look.up + 15) < 0.01)
        let rolled = q.multiply(HeadTrack.Quat.axisAngle(x: 0, y: 1, z: 0, deg: 40))
        let still = HeadTrack.Quat.look(from: rolled, origin: origin)
        #expect(abs(still.right - 20) < 0.5, "twist around the nose is not look-right")
        #expect(abs(still.up + 15) < 0.5, "twist around the nose is not look-up")
    }

    @Test func geodesicIsNoseToNoseNotEulerHypot() {
        #expect(
            abs(HeadTrack.geodesicDeg(fromRight: 0, fromUp: 0, toRight: 20, toUp: 0) - 20) < 0.01)
        #expect(
            abs(HeadTrack.geodesicDeg(fromRight: 0, fromUp: 0, toRight: 0, toUp: -25) - 25) < 0.01)
        #expect(HeadTrack.geodesicDeg(fromRight: 12, fromUp: -8, toRight: 12, toUp: -8) < 0.001)
        let combined = HeadTrack.geodesicDeg(fromRight: 0, fromUp: 0, toRight: 20, toUp: 20)
        #expect(combined > 20)
        #expect(combined < hypot(20.0, 20.0), "great-circle is shorter than Euler hypot")
        let swing = HeadTrack.swingError(fromRight: 0, fromUp: 0, toRight: 20, toUp: -10)
        #expect(abs(swing.pan - 20) < 0.01, "pan-tilt IK is still Δazimuth")
        #expect(abs(swing.tilt + 10) < 0.01)
        #expect(
            abs(
                swing.mag
                    - HeadTrack.geodesicDeg(fromRight: 0, fromUp: 0, toRight: 20, toUp: -10))
                < 0.001)
    }

    @Test func swingCloseDoesNotDriveRoll() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: 0, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(cmd?.rest == true, "matched noses rest — roll is not on 0x04/0x01")
    }
}
