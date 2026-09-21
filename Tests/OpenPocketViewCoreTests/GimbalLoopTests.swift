import Testing
@testable import OpenPocketViewCore

@Suite struct GimbalLoopTests {
    private func point(_ yaw: Double, _ pitch: Double = 0) -> GimbalWaypoint {
        GimbalWaypoint(yawDeg: yaw, pitchDeg: pitch, zoom: 1, nativePitchDeg: -pitch)
    }

    /// Executes native timed targets on a monotonic clock in both directions.
    private struct Camera {
        struct Command {
            var pass: Int
            var time: Double
            var label: String
            var target: GimbalWaypoint
            var duration: Double
        }
        var engine = GimbalMoveEngine()
        var live: GimbalWaypoint
        var from: GimbalWaypoint
        var target: GimbalWaypoint
        var now = 0.0
        var sentAt = 0.0
        var duration = 1.0
        var commands: [Command] = []
        var turnarounds = 0

        init(_ program: GimbalProgram) {
            live = program.a!
            from = live
            target = live
            let started = engine.start(program: program, live: live)
            #expect(started)
        }

        mutating func tick(miss: Double = 0) -> GimbalMoveEngine.Output? {
            now += 0.01
            live = GimbalMoveEngine.lerp(from, target, u: (now - sentAt) / duration)
            live.yawDeg += miss
            let before = engine.readout(live: live)?.phase
            let out = engine.tick(dt: 0.01, live: live)
            let after = engine.readout(live: live)
            if before == "VERIFY", after?.phase == "RUN" { turnarounds += 1 }
            if let next = out?.target {
                #expect(GimbalMoveEngine.canSendNativeTarget(from: live, to: next))
                #expect(after?.phase == "RUN", "Loop must not return via untimed preparation")
                commands.append(Command(pass: turnarounds, time: now, label: after!.label,
                    target: next, duration: out!.duration))
                from = live
                target = next
                sentAt = now
                duration = out!.duration
            }
            return out
        }

        mutating func advance(toPass pass: Int) {
            for _ in 0..<4000 {
                if turnarounds == pass || !engine.running { break }
                _ = tick()
            }
            #expect(turnarounds == pass)
            #expect(engine.failure == nil)
        }

        mutating func pauseAndResume() {
            let paused = engine.pause(live: live)
            #expect(paused)
            #expect(engine.tick(dt: 60, live: live) == nil)
            from = live
            target = live
            sentAt = now
            let resumed = engine.resume(live: live)
            #expect(resumed)
        }
    }

    @Test(arguments: [false, true])
    func alternatesSavedPointsWithMatchingLegDurations(hasC: Bool) {
        let program = GimbalProgram(a: point(0), b: point(30), c: hasC ? point(30, 20) : nil,
            durationAB: 3, durationBC: 2, loop: true)
        var camera = Camera(program)
        camera.advance(toPass: 3)
        #expect(camera.engine.running)
        for pass in 0..<3 {
            let commands = camera.commands.filter { $0.pass == pass }
            let reverse = pass == 1
            #expect(commands.map(\.target) == (hasC
                ? [program.b!, reverse ? program.a! : program.c!]
                : [reverse ? program.a! : program.b!]))
            #expect(commands.map(\.duration) == (hasC ? (reverse ? [2, 3] : [3, 2]) : [3]))
            #expect(commands.map(\.label) == (hasC
                ? (reverse ? ["C→B", "B→A"] : ["A→B", "B→C"])
                : [reverse ? "B→A" : "A→B"]))
            let nextStart = camera.commands.first { $0.pass == pass + 1 }!.time
            let passDuration = hasC ? 5.0 : 3.0
            #expect(abs(nextStart - commands[0].time - passDuration - 0.3) < 0.011,
                "Only endpoint verification separates timed passes; no extra hold or approach")
        }
    }

    @Test func smoothReturnRetracesCurveWithReversedTiming() {
        let program = GimbalProgram(a: point(0), b: point(30), c: point(30, 20),
            durationAB: 3, durationBC: 2, smoothness: 0.5, loop: true)
        let reverse = GimbalProgram(a: program.c, b: program.b, c: program.a,
            durationAB: 2, durationBC: 3, smoothness: 0.5)
        let forwardCurve = GimbalProgramCurve(program: program)!
        let reverseCurve = GimbalProgramCurve(program: reverse)!
        var camera = Camera(program)
        camera.advance(toPass: 3)
        for pass in 0..<3 {
            let curve = pass == 1 ? reverseCurve : forwardCurve
            let commands = camera.commands.filter { $0.pass == pass }
            #expect(commands.count == 99)
            #expect(commands.last?.target == (pass == 1 ? program.a : program.c))
            for command in commands {
                let time = command.time - commands[0].time + 0.1
                #expect(GimbalMoveEngine.angularDistance(command.target, curve.position(at: time)) < 1e-8)
                #expect(command.duration == 0.1)
            }
        }
        for step in 0...100 {
            let time = Double(step) / 20
            #expect(GimbalMoveEngine.angularDistance(
                forwardCurve.position(at: time), reverseCurve.position(at: 5 - time)) < 1e-8)
        }
    }

    @Test func loopDefaultsOffAndFinishesOnce() {
        let program = GimbalProgram(a: point(0), b: point(30), durationAB: 1)
        #expect(!program.loop)
        var camera = Camera(program)
        for _ in 0..<1000 where camera.engine.running { _ = camera.tick() }
        #expect(camera.turnarounds == 0)
        #expect(camera.commands.count == 1)
        #expect(!camera.engine.running)
        #expect(camera.engine.failure == nil)
    }

    @Test func wideReverseUsesTimedReachableSubdivisions() {
        let program = GimbalProgram(a: point(-40), b: point(225), durationAB: 4, loop: true)
        var camera = Camera(program)
        camera.advance(toPass: 2)
        for pass in 0..<2 {
            let commands = camera.commands.filter { $0.pass == pass }
            #expect(commands.count == 3)
            #expect(abs(commands.reduce(0) { $0 + $1.duration } - 4) < 1e-8)
            #expect(commands.last?.target == (pass == 0 ? program.b : program.a))
        }
    }

    @Test(arguments: [0.0, 0.5])
    func pauseDuringReversePreservesDirectionAndRestoresFullForwardPass(smoothness: Double) {
        let program = GimbalProgram(a: point(0), b: point(30), c: point(30, 20),
            durationAB: 3, durationBC: 2, smoothness: smoothness, loop: true)
        var camera = Camera(program)
        camera.advance(toPass: 1)
        for _ in 0..<100 { _ = camera.tick() }
        #expect(camera.engine.readout(live: camera.live)?.label == "C→B")
        camera.pauseAndResume()
        camera.advance(toPass: 3)
        let reverse = camera.commands.filter { $0.pass == 1 }
        #expect(reverse.last?.target == program.a)
        let original = camera.commands.filter { $0.pass == 0 }
        let nextForward = camera.commands.filter { $0.pass == 2 }
        #expect(nextForward.map(\.target) == original.map(\.target))
        #expect(nextForward.map(\.duration) == original.map(\.duration))
    }

    @Test(arguments: [false, true])
    func stopAtTurnaroundCannotRestart(afterReversal: Bool) {
        var camera = Camera(GimbalProgram(a: point(0), b: point(30), durationAB: 1, loop: true))
        if afterReversal {
            camera.advance(toPass: 1)
        } else {
            for _ in 0..<1000 {
                _ = camera.tick()
                if camera.engine.readout(live: camera.live)?.phase == "VERIFY" { break }
            }
            #expect(camera.engine.readout(live: camera.live)?.phase == "VERIFY")
        }
        camera.engine.cancel()
        for _ in 0..<100 { #expect(camera.tick() == nil) }
        #expect(!camera.engine.running)
        let resumed = camera.engine.resume(live: camera.live)
        #expect(!resumed)
    }

    @Test func failedFinalVerificationDoesNotReverse() {
        var camera = Camera(GimbalProgram(a: point(0), b: point(30), durationAB: 1, loop: true))
        for _ in 0..<1000 where camera.engine.running { _ = camera.tick(miss: camera.now >= 3 ? 1 : 0) }
        #expect(camera.engine.failure != nil)
        #expect(!camera.engine.running)
        #expect(camera.turnarounds == 0)
        #expect(camera.commands.count == 1)
        #expect(camera.tick() == nil)
    }

    @Test func lostFeedbackDuringReverseStopsInsteadOfRetrying() {
        var camera = Camera(GimbalProgram(a: point(0), b: point(30), durationAB: 1, loop: true))
        camera.advance(toPass: 1)
        let out = camera.engine.tick(dt: 0.01, live: camera.live, telemetryAge: 0.31)
        #expect(out?.stop == true && out?.finished == true)
        #expect(camera.engine.failure != nil)
        #expect(camera.tick() == nil)
    }
}
