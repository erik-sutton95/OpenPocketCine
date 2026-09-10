import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct GimbalProgramTests {
    private let a = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
    private let b = GimbalWaypoint(yawDeg: 30, pitchDeg: 10, zoom: 3)

    @Test func runNeedsAAndB() {
        var program = GimbalProgram()
        #expect(!program.canRun)
        #expect(program.summary == "Not set")
        program.a = a
        #expect(program.summary == "Partial")
        program.b = b
        #expect(program.canRun)
        #expect(program.summary == "A·B")
    }

    @Test func lockedModeSendsNoFrames() {
        #expect(GimbalControl.setModeFrames(.locked).isEmpty)
        #expect(GimbalControl.setModeFrames(.follow).count == 2)
        #expect(GimbalControl.setModeFrames(.fpv).count == 1)
    }

    @Test func getReplyKeepsFpvAndLocked() {
        let params = GimbalParamState(tiltLock: .locked, speed: .slow)
        #expect(GimbalControl.modeFromGet(params, commanded: .fpv) == .fpv)
        #expect(GimbalControl.modeFromGet(params, commanded: .locked) == .locked)
        #expect(GimbalControl.modeFromGet(params, commanded: .follow) == .tiltLocked)
        #expect(
            GimbalControl.modeFromGet(
                GimbalParamState(tiltLock: .unlocked, speed: .fast), commanded: .tiltLocked)
                == .follow)
    }

    @Test func lerpIsLinearInYawAndPitch() {
        let mid = GimbalMoveEngine.lerp(a, b, u: 0.5)
        #expect(abs(mid.yawDeg - 15) < 1e-9)
        #expect(abs(mid.pitchDeg - 5) < 1e-9)
    }

    @Test func minTravelUsesFiftyDegreeCeiling() {
        let floor = GimbalProgram.minTravelDuration(from: a, to: b)
        #expect(floor == 0.5)
    }

    @Test func engineRefusesPartialProgram() {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: a), live: a)
        #expect(!started)
    }

    @Test func telemetryYawPastTheGapUnwrapsOntoTheLongSide() {
        #expect(abs(GimbalWaypoint.unwrapYaw(-150) - 210) < 1e-9)
        #expect(abs(GimbalWaypoint.unwrapYaw(50) - 50) < 1e-9)
        let wp = GimbalWaypoint.from(yawTenth: -1500, pitchTenth: 0, zoom: 1)
        #expect(abs((wp?.yawDeg ?? 0) - 210) < 1e-9)
    }

    @Test func unwrapPreservesMeasuredAnglesInsteadOfInventingStops() {
        #expect(abs(GimbalWaypoint.unwrapYaw(90) - 90) < 1e-9)
        #expect(abs(GimbalWaypoint.unwrapYaw(100) - 100) < 1e-9)
    }

    @Test func panEndpointConventionCrossesRawWrapOnThePositiveArc() {
        #expect(GimbalWaypoint.unwrapYaw(-48) == -48)
        #expect(GimbalWaypoint.unwrapYaw(-135) == 225)
        #expect(GimbalWaypoint.unwrapYaw(-180) == 180)
        #expect(GimbalWaypoint.unwrapYaw(180) == 180)
        #expect(GimbalWaypoint.unwrapYaw(-80) == -80)
        #expect(GimbalWaypoint.unwrapYaw(-100) == 260)
    }

    @Test func lerpFromShortSideToSelfieNeverEntersTheGap() {
        let from = GimbalWaypoint(yawDeg: 50, pitchDeg: 0, zoom: 1)
        let to = GimbalWaypoint(yawDeg: 200, pitchDeg: 0, zoom: 1)
        for i in 0...80 {
            let yaw = GimbalMoveEngine.lerp(from, to, u: Double(i) / 80).yawDeg
            #expect(yaw <= HeadTrack.Reach.panMaxDeg + 1e-9)
            #expect(yaw >= HeadTrack.Reach.panMinDeg - 1e-9)
        }
    }

    @Test func overlayCentersWhenPoseMatches() {
        let mark = GimbalWaypointOverlay.project(
            waypoint: a, slot: .a, live: a, aspect: 16 / 9)
        #expect(abs(mark.nx - 0.5) < 1e-9)
        #expect(abs(mark.ny - 0.5) < 1e-9)
        #expect(mark.onScreen)
    }

    @Test func overlayIsRectilinearOnTheSphere() {
        let live = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
        let point = GimbalWaypoint(yawDeg: 30, pitchDeg: 0, zoom: 1)
        let mark = GimbalWaypointOverlay.project(
            waypoint: point, slot: .b, live: live, aspect: 16 / 9)
        let expected = 0.5 + tan(30 * .pi / 180) / (2 * tan(42 * .pi / 180))
        #expect(abs(mark.nx - expected) < 1e-9)
        #expect(mark.onScreen)
    }

    @Test func overlayFollowsLiveYawOnTheSphere() {
        let point = GimbalWaypoint(yawDeg: 20, pitchDeg: 0, zoom: 1)
        let atOrigin = GimbalWaypointOverlay.project(
            waypoint: point, slot: .b,
            live: GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1), aspect: 16 / 9)
        let afterPan = GimbalWaypointOverlay.project(
            waypoint: point, slot: .b,
            live: GimbalWaypoint(yawDeg: 20, pitchDeg: 0, zoom: 1), aspect: 16 / 9)
        #expect(atOrigin.nx > 0.5)
        #expect(abs(afterPan.nx - 0.5) < 1e-9)
    }

    @Test func overlayKeepsDistinctCapturedAnglesBeyondTheFormerPanClamp() {
        let point = GimbalWaypoint.from(yawTenth: 689, pitchTenth: -137, zoom: 1)!
        let live = GimbalWaypoint.from(yawTenth: 782, pitchTenth: -137, zoom: 1)!
        let mark = GimbalWaypointOverlay.project(waypoint: point, slot: .b, live: live, aspect: 16 / 9)
        #expect(mark.nx < 0.5)
        #expect(mark.onScreen)
        let back = GimbalWaypointOverlay.project(waypoint: point, slot: .b, live: point, aspect: 16 / 9)
        #expect(abs(back.nx - 0.5) < 1e-9)
        #expect(abs(back.ny - 0.5) < 1e-9)
    }

    @Test func overlayZoomScalesTheTangent() {
        let live = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 2)
        let point = GimbalWaypoint(yawDeg: 10, pitchDeg: 0, zoom: 1)
        let mark = GimbalWaypointOverlay.project(
            waypoint: point, slot: .b, live: live, aspect: 16 / 9)
        let expected = 0.5 + tan(10 * .pi / 180) / (2 * tan(42 * .pi / 180) / 2)
        #expect(abs(mark.nx - expected) < 1e-9)
    }

    @Test func overlayDrawsLookUpAboveCenter() {
        let mark = GimbalWaypointOverlay.project(
            waypoint: GimbalWaypoint(yawDeg: 0, pitchDeg: 10, zoom: 1),
            slot: .b, live: a, aspect: 16 / 9)
        #expect(mark.ny < 0.5)
    }

    @Test func overlayBehindTheCameraIsOffScreen() {
        let mark = GimbalWaypointOverlay.project(
            waypoint: GimbalWaypoint(yawDeg: -170, pitchDeg: 0, zoom: 1),
            slot: .b, live: a, aspect: 16 / 9)
        #expect(!mark.onScreen)
        #expect(abs(mark.nx) < 1e-9)
    }

    @Test func durationStepsByHalfSecond() {
        #expect(GimbalProgram.steppedDuration(1.5, delta: 0.5, floor: 1.0) == 2.0)
        #expect(GimbalProgram.durationLabel(1.5) == "1.5s")
    }

    @Test func nanoHasNoGimbal() {
        #expect(CameraModel(name: "Osmo Pocket 4 Pro").hasGimbal)
        #expect(!CameraModel(name: "Osmo Nano").hasGimbal)
    }
}
