import Testing
@testable import OpenPocketViewCore

@Suite struct GimbalSafeRouteTests {
    @Test func selfieRestartDoesNotCommandAcrossTheBlockedArc() {
        let a = GimbalWaypoint(yawDeg: 28.7, pitchDeg: 0.2, zoom: 1, nativePitchDeg: -180)
        let b = GimbalWaypoint(yawDeg: 62.8, pitchDeg: -7.4, zoom: 1, nativePitchDeg: -172)
        let c = GimbalWaypoint(yawDeg: 225, pitchDeg: 0.6, zoom: 1, nativePitchDeg: -180)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: a, b: b, c: c), live: c)
        #expect(started)
        let first = engine.tick(dt: 0.04, live: c)
        #expect(first?.target != nil)
        if let target = first?.target {
            #expect(abs(target.yawDeg - c.yawDeg) < 180)
            #expect(target.yawDeg < c.yawDeg)
        }
    }
    @Test(arguments: [(225.0, 28.7, 225.0, 4.0), (-40.0, 225.0, -40.0, 4.0), (-40.0, -40.0, 225.0, 0.5), (0.0, 0.0, 30.0, 120.0), (0.0, 0.0, 225.0, 120.0)])
    func completeRoutesNeverUseTheMissingSector(startYaw: Double, aYaw: Double, bYaw: Double, legDuration: Double) {
        func pose(_ yaw: Double) -> GimbalWaypoint {
            GimbalWaypoint(yawDeg: yaw, pitchDeg: 0, zoom: 1, nativePitchDeg: -180)
        }
        let a = pose(aYaw), b = pose(bYaw)
        var live = pose(startYaw)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: a, b: b, c: a, durationAB: legDuration, durationBC: legDuration), live: live)
        #expect(started)
        var clock = 0.0, sentAt = 0.0, duration = 1.0
        var from = live, target = live
        var timedDuration = 0.0
        for _ in 0..<10000 {
            guard engine.running else { break }
            let dt = max(0.000001, engine.nextWakeInterval)
            clock += dt
            live = GimbalMoveEngine.lerp(from, target, u: (clock - sentAt) / duration)
            guard let out = engine.tick(dt: dt, live: live) else { break }
            if let next = out.target {
                if engine.readout(live: live)?.phase == "RUN" { timedDuration += out.duration }
                #expect(GimbalMoveEngine.canSendNativeTarget(from: live, to: next))
                #expect(abs(next.yawDeg - live.yawDeg) < 180)
                #expect(Commands.gimbalTimedTarget(waypoint: next, duration: out.duration) != nil)
                from = live; target = next; sentAt = clock; duration = out.duration
            }
        }
        #expect(abs(timedDuration - legDuration * 2) < 1e-6)
        #expect(clock >= legDuration * 2 + GimbalMoveEngine.holdSeconds)
        #expect(engine.failure == nil)
        #expect(engine.readout(live: live)?.phase == "DONE")
        #expect(abs(live.yawDeg - aYaw) <= 0.15)
    }

    @Test func roundedWireTargetCannotBecomeAmbiguous() {
        let live = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
        #expect(!GimbalMoveEngine.canSendNativeTarget(from: live, to: .init(yawDeg: 179.96, pitchDeg: 0, zoom: 1)))
        #expect(GimbalMoveEngine.canSendNativeTarget(from: live, to: .init(yawDeg: 179.94, pitchDeg: 0, zoom: 1)))
    }

    @Test func directGuardRejectsAmbiguousAndOutOfRangeCommands() {
        let live = GimbalWaypoint(yawDeg: 225, pitchDeg: 0, zoom: 1)
        #expect(!GimbalMoveEngine.canSendNativeTarget(from: live, to: .init(yawDeg: 28.7, pitchDeg: 0, zoom: 1)))
        #expect(!GimbalMoveEngine.canSendNativeTarget(from: live, to: .init(yawDeg: 45, pitchDeg: 0, zoom: 1)))
        #expect(GimbalMoveEngine.canSendNativeTarget(from: live, to: .init(yawDeg: 126.85, pitchDeg: 0, zoom: 1)))
        #expect(!GimbalMoveEngine.canSendNativeTarget(from: live, to: .init(yawDeg: 226, pitchDeg: 0, zoom: 1)))
    }

}
