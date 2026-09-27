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

    @Test func projectClampsToControllableBox() {
        let past = HeadTrack.Reach.project(
            lookRight: 300, lookUp: 80, yaw0: 0, pitch0: 0)
        #expect(past.yaw == HeadTrack.Reach.panMaxDeg)
        #expect(past.pitch == HeadTrack.Reach.tiltMaxDeg)
        let left = HeadTrack.Reach.project(
            lookRight: -300, lookUp: -200, yaw0: 0, pitch0: 0)
        #expect(left.yaw == HeadTrack.Reach.panMinDeg)
        #expect(left.pitch == HeadTrack.Reach.tiltMinDeg)
        let selfie = HeadTrack.Reach.project(
            lookRight: 20, lookUp: 0, yaw0: 190, pitch0: 0)
        #expect(selfie.yaw == 210)
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

    @Test func wrapDegFoldsAround180() {
        #expect(HeadTrack.wrapDeg(190) == -170)
        #expect(HeadTrack.wrapDeg(-190) == 170)
        #expect(abs(HeadTrack.wrapDeg(180)) == 180)
        #expect(HeadTrack.wrapDeg(20) == 20)
    }
}
