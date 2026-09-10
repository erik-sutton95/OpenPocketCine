import Testing
@testable import OpenPocketViewCore

@Suite struct GimbalPauseTests {
    private func point(_ yaw: Double, _ pitch: Double = 0) -> GimbalWaypoint {
        GimbalWaypoint(yawDeg: yaw, pitchDeg: pitch, zoom: 1, nativePitchDeg: -pitch)
    }

    private func ready(_ program: GimbalProgram) -> GimbalMoveEngine {
        var engine = GimbalMoveEngine()
        let operation1 = engine.start(program: program, live: program.a!)
        #expect(operation1)
        for _ in 0..<200 { _ = engine.tick(dt: 0.01, live: program.a!) }
        return engine
    }

    @Test func pauseFreezesTimeAndResumeStartsAtCoastedPoseWithoutA() {
        let a = point(0), b = point(40), c = point(50)
        var engine = ready(GimbalProgram(a: a, b: b, c: c, durationAB: 4, durationBC: 2))
        for step in 1...123 { _ = engine.tick(dt: 0.01, live: point(Double(step) / 10)) }
        let operation2 = engine.pause(live: point(12.3))
        #expect(operation2)
        let paused = engine.readout(live: point(12.3))
        #expect(engine.running && engine.isPaused)
        #expect(engine.tick(dt: 100, live: point(15), telemetryAge: 100) == nil)
        #expect(engine.readout(live: point(12.3))?.elapsed == paused?.elapsed)
        let operation3 = engine.resume(live: point(15))
        #expect(operation3)
        let first = engine.tick(dt: 0.01, live: point(15))
        #expect(first?.target == b)
        #expect(abs((first?.duration ?? 0) - 2.8) < 1e-9)
        #expect(engine.readout(live: point(15))?.elapsed == 0)
        for step in 1...280 {
            _ = engine.tick(dt: 0.01, live: point(15 + 25 * Double(step) / 280))
        }
        #expect(engine.readout(live: b)?.label == "B→C")
        #expect(engine.readout(live: b)?.setDuration == 2)
    }

    @Test func repeatedPauseUsesRemainingDurationAndStopIsTerminal() {
        var engine = ready(GimbalProgram(a: point(0), b: point(40), durationAB: 4))
        for _ in 0..<100 { _ = engine.tick(dt: 0.01, live: point(10)) }
        let operation4 = engine.pause(live: point(10))
        #expect(operation4)
        let operation5 = engine.resume(live: point(12))
        #expect(operation5)
        #expect(engine.tick(dt: 0.01, live: point(12))?.duration == 3)
        for _ in 0..<50 { _ = engine.tick(dt: 0.01, live: point(17)) }
        let operation6 = engine.pause(live: point(17))
        #expect(operation6)
        let operation7 = engine.resume(live: point(18))
        #expect(operation7)
        #expect(engine.tick(dt: 0.01, live: point(18))?.duration == 2.5)
        let operation8 = engine.pause(live: point(18))
        #expect(operation8)
        engine.cancel()
        #expect(!engine.running && !engine.isPaused)
        let operation9 = engine.resume(live: point(18))
        #expect(!operation9)
        #expect(engine.tick(dt: 0.01, live: point(18)) == nil)
    }

    @Test func pauseExplicitlyMarksUnresolvedBVerification() {
        var engine = ready(GimbalProgram(a: point(0), b: point(20), c: point(30), durationAB: 2, durationBC: 2))
        for step in 1...200 { _ = engine.tick(dt: 0.01, live: point(Double(step) / 10)) }
        let operation10 = engine.pause(live: point(20))
        #expect(operation10)
        #expect(engine.verificationInterruptedByPause)
        let operation11 = engine.resume(live: point(21))
        #expect(operation11)
        #expect(engine.verificationInterruptedByPause)
        #expect(engine.tick(dt: 0.01, live: point(21))?.target == point(30))
        for _ in 0..<245 { _ = engine.tick(dt: 0.01, live: point(25)) }
        #expect(engine.failure != nil, "future final arrival must still be verified")
    }

    @Test func curveCutsPreserveFutureGeometryAndAbsorbCoast() {
        let program = GimbalProgram(a: point(0), b: point(30), c: point(30, 20),
            durationAB: 3, durationBC: 2, smoothness: 1)
        let original = GimbalProgramCurve(program: program)!
        for cut in [1.0, 2.5, 4.5] {
            let actual = point(12, 3)
            let rest = original.remaining(after: cut, from: actual)
            #expect(rest.position(at: 0) == actual)
            #expect(abs(rest.duration - (5 - cut)) < 1e-9)
            #expect(rest.position(at: rest.duration) == program.c)
            #expect(rest.samples().allSatisfy { $0 == $0.clamped() })
            if cut < 4 {
                #expect(rest.position(at: 4 - cut) == original.position(at: 4))
            }
            let again = rest.remaining(after: 0.1, from: point(13, 3))
            #expect(again.position(at: 0) == point(13, 3))
            #expect(abs(again.duration - (rest.duration - 0.1)) < 1e-9)
            #expect(again.position(at: again.duration) == program.c)
        }
        let exactCut = original.remaining(after: 2.5, from: original.position(at: 2.5))
        #expect(GimbalMoveEngine.angularDistance(exactCut.position(at: 0.4), original.position(at: 2.9)) < 1e-9)
    }

    @Test func curveResumeImmediatelyTargetsContinuationAndStillFinishes() {
        let program = GimbalProgram(a: point(0), b: point(30), c: point(30, 20),
            durationAB: 3, durationBC: 2, smoothness: 1)
        var engine = ready(program)
        for _ in 0..<253 { _ = engine.tick(dt: 0.01, live: point(20)) }
        let operation12 = engine.pause(live: point(20))
        #expect(operation12)
        let operation13 = engine.resume(live: point(22, 2))
        #expect(operation13)
        let first = engine.tick(dt: 0.01, live: point(22, 2))
        #expect(first?.target != program.a)
        #expect(first?.duration == 0.1)
        #expect(engine.readout(live: point(22, 2))?.elapsed == 0)
        var live = point(22, 2)
        var from = live
        var target = first!.target!
        var since = 0.0
        for _ in 0..<300 {
            since += 0.01
            live = GimbalMoveEngine.lerp(from, target, u: since / 0.1)
            guard let output = engine.tick(dt: 0.01, live: live) else { break }
            if let next = output.target { from = live; target = next; since = 0 }
            if output.finished { break }
        }
        #expect(engine.failure == nil)
        #expect(!engine.running)
    }
    @Test func preparationResumeMayReapproachAAndRejectsInvalidStoppedPose() {
        let program = GimbalProgram(a: point(0), b: point(20), durationAB: 2)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: program, live: point(10))
        #expect(started)
        _ = engine.tick(dt: 0.01, live: point(10))
        let paused = engine.pause(live: point(8))
        #expect(paused)
        let invalid = engine.resume(live: point(300))
        #expect(!invalid && engine.isPaused)
        let resumed = engine.resume(live: point(7))
        #expect(resumed)
        let first = engine.tick(dt: 0.01, live: point(7))
        #expect(first?.target == program.a)
        #expect(engine.readout(live: point(7))?.elapsed == 0)
    }

    @Test func nearFinalPauseUsesMinimumNativeDurationAndStillVerifiesArrival() {
        var engine = ready(GimbalProgram(a: point(0), b: point(40), durationAB: 4))
        for step in 1...397 { _ = engine.tick(dt: 0.01, live: point(Double(step) / 10)) }
        let paused = engine.pause(live: point(39.7))
        let resumed = engine.resume(live: point(39.9))
        #expect(paused && resumed)
        let first = engine.tick(dt: 0.01, live: point(39.9))
        #expect(first?.duration == 0.1)
        #expect(first?.target == point(40))
        for _ in 0..<50 { _ = engine.tick(dt: 0.01, live: point(40)) }
        #expect(!engine.running && engine.failure == nil)

        let curve = GimbalProgramCurve(program: GimbalProgram(a: point(0), b: point(20), c: point(30),
            durationAB: 2, durationBC: 2, smoothness: 0.5))!
        let rest = curve.remaining(after: 3.97, from: point(29.9))
        #expect(abs(rest.duration - 0.1) < 1e-9)
        #expect(rest.position(at: 0) == point(29.9))
        #expect(rest.position(at: rest.duration) == point(30))
    }

}
