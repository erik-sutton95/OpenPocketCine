import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct HeadTrackTests {
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

    @Test func lookingRightPansRightUntilLiveYawCatches() {
        var track = HeadTrack()
        let ok = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(ok == .centered)
        let start = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(start != nil)
        #expect(start!.x == HeadTrack.maxThrow)
        #expect(start!.y == 0)
        var cmd = start
        for _ in 0..<8 {
            cmd = track.tick(
                lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0,
                dt: 0.05)
        }
        #expect(cmd != nil)
        #expect(cmd!.x > 0, "held look must keep throwing until live yaw catches")
        let caught = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 200, gimbalPitchTenth: 0)
        #expect(caught?.rest == true)
    }

    @Test func twoDegPastLookDoesNotReverseHunt() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let first = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(first != nil)
        #expect(first!.x > 0)
        let past = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 220, gimbalPitchTenth: 0,
            dt: 0.04)
        #expect(past != nil)
        #expect(
            past!.x >= 0,
            "2° delayed overshoot must not reverse — that is the hunt")
    }

    @Test func sphereKeepsLookPastTheStopThenPicksUpFromAnotherAngle() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let stop = Int16(HeadTrack.Reach.panMaxDeg * 10)
        let past = track.tick(
            lookRightDeg: 90, lookUpDeg: 0, gimbalYawTenth: stop, gimbalPitchTenth: 0)
        #expect(past?.rest == true, "90° look sits on the +58° stop")
        let nod = track.tick(
            lookRightDeg: 90, lookUpDeg: 25, gimbalYawTenth: stop, gimbalPitchTenth: 0)
        #expect(nod != nil)
        #expect(nod!.x == 0, "still past the pan stop")
        #expect(nod!.y > 0, "a nod on the sphere still tilts")
        let back = track.tick(
            lookRightDeg: 20, lookUpDeg: 25, gimbalYawTenth: stop, gimbalPitchTenth: 0)
        #expect(back != nil)
        #expect(
            back!.x < 0, "coming back from another angle leaves the pan stop toward SET")
        #expect(back!.y > 0)
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

    @Test func nodDoesNotPanWhenLiveYawWiggles() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 50, gimbalPitchTenth: 0)
        #expect(cmd != nil)
        #expect(cmd!.y > 0)
        #expect(cmd!.x == 0, "a vertical nod must not zigzag pan when live yaw wiggles")
    }

    @Test func yawWrapsAround180() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: -1700, gimbalPitchTenth: 0)
        let cmd = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: -1700, gimbalPitchTenth: 0)
        #expect(cmd != nil)
        #expect(cmd!.x == HeadTrack.maxThrow)
    }

    @Test func lookPastPanStopRestsThenFollowsBack() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let past = HeadTrack.Reach.panMaxDeg + 40
        let stop = Int16(HeadTrack.Reach.panMaxDeg * 10)
        let slammed = track.tick(
            lookRightDeg: past, lookUpDeg: 0, gimbalYawTenth: stop, gimbalPitchTenth: 0)
        #expect(slammed?.rest == true, "projected look is the stop — do not keep throwing")
        let back = 20.0
        let recover = track.tick(
            lookRightDeg: back, lookUpDeg: 0, gimbalYawTenth: stop, gimbalPitchTenth: 0)
        #expect(recover != nil)
        #expect(recover!.x < 0, "looking back inside the box must leave the stop toward SET")
        let home = track.tick(
            lookRightDeg: back, lookUpDeg: 0, gimbalYawTenth: Int16(back * 10),
            gimbalPitchTenth: 0)
        #expect(home?.rest == true)
    }

    @Test func lookPastTiltStopRests() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let stop = Int16(HeadTrack.Reach.tiltMaxDeg * 10)
        let cmd = track.tick(
            lookRightDeg: 0, lookUpDeg: 80, gimbalYawTenth: 0, gimbalPitchTenth: stop)
        #expect(cmd?.rest == true)
    }

    @Test func fullTurnDoesNotWrapToTheOtherStop() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var right = 0.0
        var cmd: HeadTrack.Command?
        for _ in 0..<18 {
            right += 20
            cmd = track.tick(
                lookRightDeg: HeadTrack.wrapDeg(right), lookUpDeg: 0, gimbalYawTenth: 580,
                gimbalPitchTenth: 0)
        }
        #expect(abs(right - 360) < 0.001)
        #expect(cmd?.rest == true, "360° head turn stays projected on +58, not wrapped home")
        for _ in 0..<16 {
            right -= 20
            cmd = track.tick(
                lookRightDeg: HeadTrack.wrapDeg(right), lookUpDeg: 0, gimbalYawTenth: 580,
                gimbalPitchTenth: 0)
        }
        #expect(cmd != nil)
        #expect(cmd!.x < 0, "unwinding back through the box leaves the stop toward SET")
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
        #expect(
            track.tick(
                lookRightDeg: 0.4, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0
            )?.rest == true)
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

    @Test func fiftyThreeDegLookClosesOnLiveYaw() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 100, gimbalPitchTenth: -50)
        let start = track.tick(
            lookRightDeg: -53, lookUpDeg: 0, gimbalYawTenth: 100, gimbalPitchTenth: -50)
        #expect(start != nil)
        #expect(start!.x < 0, "53° left throws pan left until live yaw matches")
        let caught = track.tick(
            lookRightDeg: -53, lookUpDeg: 0, gimbalYawTenth: -430, gimbalPitchTenth: -50)
        #expect(caught?.rest == true, "SET 10° + head −53° = live −43°")
    }

    @Test func overshootLeftoverBelowLinearSnapRests() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let start = track.tick(
            lookRightDeg: 20, lookUpDeg: 0.1, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(start != nil)
        #expect(start!.x > 0)
        let leftover = track.tick(
            lookRightDeg: 20, lookUpDeg: 0.1, gimbalYawTenth: 200, gimbalPitchTenth: 0)
        #expect(
            leftover?.rest == true,
            "caught pan + leftover y=-0.01 encodes as center — lift")
    }

    @Test func liveYawWiggleAfterCloseDoesNotRegrab() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        _ = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let caught = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 200, gimbalPitchTenth: 0)
        #expect(caught?.rest == true)
        var parked: HeadTrack.Command?
        for _ in 0..<8 {
            parked = track.tick(
                lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 200, gimbalPitchTenth: 0,
                dt: 0.04)
        }
        #expect(parked?.rest == true)
        let wiggle = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 220, gimbalPitchTenth: 0,
            dt: 0.04)
        #expect(
            wiggle?.rest == true,
            "2° live-yaw wiggle after close must not rest/throw — that paused HEVC")
        let undershoot = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 180, gimbalPitchTenth: 0,
            dt: 0.04)
        #expect(
            undershoot?.rest == true,
            "2° live-yaw undershoot after a still close must not re-grab")
        let lookAgain = track.tick(
            lookRightDeg: 26, lookUpDeg: 0, gimbalYawTenth: 200, gimbalPitchTenth: 0,
            dt: 0.04, gyroYaw: 0.4)
        #expect(lookAgain != nil)
        #expect(lookAgain!.x > 0, "a 6° head turn after close must throw again")
    }

    @Test func threeDegShortOfLookKeepsThrowing() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        _ = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var cmd: HeadTrack.Command?
        for _ in 0..<10 {
            cmd = track.tick(
                lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 170, gimbalPitchTenth: 0,
                dt: 0.04)
        }
        #expect(cmd != nil)
        #expect(
            cmd!.x > 0,
            "3° short of a 20° look must not park at reengageDeg — drive until restDeg")
    }

    @Test func stillHeadParksInsteadOfHunting() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let go = track.tick(
            lookRightDeg: -8, lookUpDeg: -8, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(go != nil && go!.x < 0 && go!.y < 0)
        var cmd: HeadTrack.Command?
        for _ in 0..<10 {
            cmd = track.tick(
                lookRightDeg: -8, lookUpDeg: -8, gimbalYawTenth: -160, gimbalPitchTenth: -160,
                dt: 0.04)
        }
        #expect(cmd?.rest == true, "head still + delayed overshoot must rest, not reverse")
        let otherWay = track.tick(
            lookRightDeg: -8, lookUpDeg: -8, gimbalYawTenth: 100, gimbalPitchTenth: 80,
            dt: 0.04)
        #expect(
            otherWay?.rest == true,
            "physical take: head still −3/−5 must not bob body ±10°")
    }

    @Test func nodKeepsThrowingUntilLivePitchCatches() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var cmd = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 0, dt: 0.04)
        #expect(cmd != nil)
        #expect(cmd!.y == HeadTrack.maxThrow)
        for _ in 0..<8 {
            cmd = track.tick(
                lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 0, dt: 0.04,
                gyroLookUp: 0.3)
        }
        #expect(
            cmd?.y == HeadTrack.maxThrow,
            "pitch must keep throwing at full stick until live @20 catches — not park")
        let caught = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 200)
        #expect(caught?.rest == true)
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
        #expect(back?.rest == true)
    }

    @Test func livePitchClosesTiltOneToOne() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let start = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 50)
        #expect(start != nil)
        #expect(start!.y > 0)
        let caught = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 200)
        #expect(caught?.rest == true)
    }

    @Test func movingHeadDoesNotParkACloseSoASlowLookStaysOneToOne() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let go = track.tick(
            lookRightDeg: 4, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0,
            dt: 0.05, gyroYaw: 0.4)
        #expect(go != nil && go!.x > 0, "4° look engages")
        for step in 5...20 {
            let look = Double(step)
            let liveTenth = Int16((look - 2) * 10)
            let cmd = track.tick(
                lookRightDeg: look, lookUpDeg: 0, gimbalYawTenth: liveTenth, gimbalPitchTenth: 0,
                dt: 0.05, gyroYaw: 0.4)
            #expect(
                cmd != nil && cmd!.x > 0,
                "step \(step): a moving 20° look must not wait reengageDeg (4°) between throws")
        }
    }

    @Test func lookBackAfterCloseReturnsTowardSet() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        _ = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        _ = track.tick(
            lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 200, gimbalPitchTenth: 0)
        for _ in 0..<8 {
            _ = track.tick(
                lookRightDeg: 20, lookUpDeg: 0, gimbalYawTenth: 200, gimbalPitchTenth: 0,
                dt: 0.04)
        }
        let back = track.tick(
            lookRightDeg: 0, lookUpDeg: 0, gimbalYawTenth: 200, gimbalPitchTenth: 0,
            dt: 0.04, gyroYaw: 0.5)
        #expect(back != nil)
        #expect(
            back!.x == -HeadTrack.maxThrow,
            "looking back to SET after a 20° close must pan home — not holdOvershoot rest")
    }

    @Test func lookBackAfterNodReturnsTowardSet() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        _ = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        _ = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 200)
        for _ in 0..<8 {
            _ = track.tick(
                lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 200,
                dt: 0.04)
        }
        let back = track.tick(
            lookRightDeg: 0, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 200,
            dt: 0.04, gyroLookUp: 0.5)
        #expect(back != nil)
        #expect(
            back!.y == -HeadTrack.maxThrow,
            "looking back to SET after a 20° nod must tilt home")
    }

    @Test func frozenLivePitchRestsTilt() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        var cmd: HeadTrack.Command?
        for _ in 0..<16 {
            cmd = track.tick(
                lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 0,
                dt: 0.04, gyroLookUp: 0.3)
        }
        #expect(
            cmd?.y == 0,
            "@20 stuck at SET for pitchLiveTimeout must rest tilt (do not slam)")
        let live = track.tick(
            lookRightDeg: 0, lookUpDeg: 20, gimbalYawTenth: 0, gimbalPitchTenth: 80,
            dt: 0.04, gyroLookUp: 0.3)
        #expect(live != nil && live!.y > 0, "live @20 moving again resumes tilt close")
    }

    @Test func sixDegLookDoesNotLeaveGimbalAtTwentyOne() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let throwOut = track.tick(
            lookRightDeg: -20, lookUpDeg: -20, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(throwOut?.x == -HeadTrack.maxThrow)
        #expect(throwOut?.y == -HeadTrack.maxThrow)
        let over = track.tick(
            lookRightDeg: -6, lookUpDeg: -6, gimbalYawTenth: -210, gimbalPitchTenth: -200,
            dt: 0.04)
        #expect(over != nil)
        #expect(
            over!.x > 0,
            "physical take: head −6° / gimbal −21° must pan back, not holdOvershoot rest")
        #expect(
            over!.y > 0,
            "physical take: head −6° / gimbal −20° must tilt back")
    }

    @Test func lookingLeftTwentyClosesOnLiveYaw() {
        var track = HeadTrack()
        _ = track.center(gimbalYawTenth: 0, gimbalPitchTenth: 0)
        let start = track.tick(
            lookRightDeg: -20, lookUpDeg: 0, gimbalYawTenth: 0, gimbalPitchTenth: 0)
        #expect(start?.x == -HeadTrack.maxThrow)
        let caught = track.tick(
            lookRightDeg: -20, lookUpDeg: 0, gimbalYawTenth: -200, gimbalPitchTenth: 0)
        #expect(caught?.rest == true, "20° left is live yaw −20.0")
    }
}
