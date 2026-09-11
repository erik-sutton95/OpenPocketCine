import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct GimbalProgramCurveTests {
    private let a = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1, nativePitchDeg: 175)
    private let b = GimbalWaypoint(yawDeg: 30, pitchDeg: 0, zoom: 1, nativePitchDeg: 175)
    private let c = GimbalWaypoint(yawDeg: 30, pitchDeg: 20, zoom: 1, nativePitchDeg: 155)

    private func program(_ smoothness: Double) -> GimbalProgram {
        GimbalProgram(a: a, b: b, c: c, durationAB: 3, durationBC: 2, smoothness: smoothness)
    }

    @Test func zeroIsExactAndIncreasingSmoothnessRoundsFartherFromB() {
        #expect(GimbalProgramCurve(program: program(0)) == nil)
        let tight = GimbalProgramCurve(program: program(0.2))!
        let wide = GimbalProgramCurve(program: program(1))!
        #expect(wide.position(at: 0) == a)
        #expect(wide.position(at: 5) == c)
        #expect(GimbalMoveEngine.angularDistance(wide.position(at: 3), b)
            > GimbalMoveEngine.angularDistance(tight.position(at: 3), b))
        #expect(wide.position(at: 3).yawDeg == 27.5)
        #expect(wide.position(at: 3).pitchDeg == 2.5)
        #expect(wide.samples().allSatisfy { $0 == $0.clamped() })
    }

    @Test func angularVelocityIsContinuousAtBothBezierJoins() {
        let curve = GimbalProgramCurve(program: program(1))!
        let epsilon = 0.0001
        for time in [2.0, 4.0] {
            let left = curve.position(at: time - epsilon)
            let mid = curve.position(at: time)
            let right = curve.position(at: time + epsilon)
            #expect(abs((mid.yawDeg - left.yawDeg) / epsilon - (right.yawDeg - mid.yawDeg) / epsilon) < 0.001)
            #expect(abs((mid.pitchDeg - left.pitchDeg) / epsilon - (right.pitchDeg - mid.pitchDeg) / epsilon) < 0.001)
        }
    }

    @Test func curveStreamsThroughBAndSchedulesFinalTargetBeforeDeadline() {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: program(1), live: a)
        #expect(started)
        var live = a
        var start = a
        var target = a
        var motionAt = 0.0
        var sends: [(Double, GimbalWaypoint)] = []
        for step in 1...800 {
            let now = Double(step) * 0.01
            live = GimbalMoveEngine.lerp(start, target, u: (now - motionAt) / 0.1)
            guard let out = engine.tick(dt: 0.01, live: live) else { break }
            if let next = out.target {
                #expect(out.duration == 0.1)
                sends.append((now, next))
                start = live
                target = next
                motionAt = now
            }
            if out.finished { break }
        }
        #expect(engine.failure == nil)
        #expect(engine.readout(live: live)?.phase == "DONE")
        #expect(sends.count == 99)
        if let first = sends.first, let last = sends.last {
            #expect(abs(last.0 - first.0 - 4.9) < 1e-8)
            #expect(last.1 == c)
            for pair in zip(sends, sends.dropFirst()) {
                #expect(abs(pair.1.0 - pair.0.0 - 0.05) < 1e-8)
            }
        }
        #expect(!sends.contains { $0.1 == b })
    }

    @Test func schedulerCannotSkipTheFinalCCommand() {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: program(1), live: a)
        #expect(started)
        for _ in 0..<689 { _ = engine.tick(dt: 0.01, live: a) }
        let skipped = engine.tick(dt: 0.11, live: c)
        #expect(skipped?.stop == true)
        #expect(engine.failure == "Move interrupted — waypoint dispatch was late")
    }

    @Test func curveCannotContinueAfterAStalledScheduler() {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: program(1), live: a)
        #expect(started)
        for _ in 0..<200 { _ = engine.tick(dt: 0.01, live: a) }
        let late = engine.tick(dt: 0.09, live: a)
        #expect(late?.stop == true)
        #expect(late?.target == nil)
    }
}
