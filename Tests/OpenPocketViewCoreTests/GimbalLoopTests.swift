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

        mutating func tick(miss: Double = 0, dt: Double = 0.01) -> GimbalMoveEngine.Output? {
            now += dt
            live = GimbalMoveEngine.lerp(from, target, u: (now - sentAt) / duration)
            live.yawDeg += miss
            let before = engine.readout(live: live)?.label
            let out = engine.tick(dt: dt, live: live)
            let after = engine.readout(live: live)
            if (before == "A→B" && after?.label == "B→A")
                || (before == "B→C" && after?.label == "C→B")
                || (before == "B→A" && after?.label == "A→B") { turnarounds += 1 }
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
            #expect(abs(nextStart - commands[0].time - passDuration) < 0.011,
                "Turnaround dispatch must have no programmed dwell")
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

    @Test(arguments: [0.0, 1.0])
    func zoomVisitsSavedAmountsOnEveryPassEvenWithRoundedB(smoothness: Double) {
        var a = point(0)
        var b = point(30)
        var c = point(30, 20)
        a.zoom = 1
        b.zoom = 3
        c.zoom = 2
        var camera = Camera(GimbalProgram(a: a, b: b, c: c,
            durationAB: 3, durationBC: 2, smoothness: smoothness, loop: true))
        var visited: Set<Double> = []
        for _ in 0..<2200 where camera.engine.running && camera.turnarounds < 3 {
            _ = camera.tick()
            guard let zoom = camera.engine.consumeProgrammedZoomTarget(),
                let row = camera.engine.readout(live: camera.live), row.phase == "RUN" else { continue }
            let route: (Double, Double, Double)
            switch row.label {
            case "A→B": route = (1, 3, 3)
            case "B→C": route = (3, 2, 2)
            case "C→B": route = (2, 3, 2)
            case "B→A": route = (3, 1, 3)
            default: Issue.record("Unexpected zoom leg"); continue
            }
            let fraction = min(1, (row.elapsed + 0.05) / route.2)
            let expected = route.0 + (route.1 - route.0) * fraction
            #expect(abs(zoom - expected) < 1e-8 || (row.elapsed <= 0.02 && abs(zoom - route.0) < 1e-8),
                "\(row.label) t=\(row.elapsed) zoom=\(zoom) expected=\(expected)")
            if zoom == zoom.rounded() { visited.insert(zoom) }
        }
        #expect(camera.engine.failure == nil)
        #expect(camera.turnarounds == 3)
        #expect(visited == [1, 2, 3])
        let paused = camera.engine.pause(live: camera.live)
        #expect(paused)
        #expect(camera.engine.programmedZoomTarget == nil)
        camera.live.zoom = 2.4
        let resumedMove = camera.engine.resume(live: camera.live)
        #expect(resumedMove)
        let resumed = camera.engine.programmedZoomTarget!
        #expect(resumed > 2.4 && resumed < 2.5, "Resume anchors zoom at the measured amount")
        camera.engine.cancel()
        #expect(camera.engine.programmedZoomTarget == nil)
    }

    @Test func acceptedLateBoundaryCannotSkipTheZoomEndpoint() {
        var b = point(30)
        b.zoom = 3
        var camera = Camera(GimbalProgram(a: point(0), b: b, durationAB: 1, loop: true))
        for _ in 0..<400 {
            _ = camera.tick()
            _ = camera.engine.consumeProgrammedZoomTarget()
            if let row = camera.engine.readout(live: camera.live), row.phase == "RUN", row.elapsed >= 0.94 - 1e-9 { break }
        }
        #expect(camera.engine.programmedZoomTarget! < 3)
        _ = camera.tick(dt: 0.065)
        #expect(camera.turnarounds == 1)
        #expect(camera.engine.failure == nil)
        #expect(camera.engine.programmedZoomTarget == 3)
        let endpoint = camera.engine.consumeProgrammedZoomTarget()
        #expect(endpoint == 3)
        #expect(camera.engine.programmedZoomTarget! < 3)
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
                if camera.now >= 2.98 { break }
            }
            #expect(camera.turnarounds == 0)
        }
        camera.engine.cancel()
        for _ in 0..<100 { #expect(camera.tick() == nil) }
        #expect(!camera.engine.running)
        let resumed = camera.engine.resume(live: camera.live)
        #expect(!resumed)
    }

    @Test func failedTurnaroundVerificationStopsTheReturn() {
        var camera = Camera(GimbalProgram(a: point(0), b: point(30), durationAB: 1, loop: true))
        for _ in 0..<1000 where camera.engine.running { _ = camera.tick(miss: camera.now >= 3 ? 1 : 0) }
        #expect(camera.engine.failure != nil)
        #expect(!camera.engine.running)
        #expect(camera.turnarounds == 1)
        #expect(camera.commands.count == 2)
        #expect(camera.now < 3.5)
        #expect(camera.tick() == nil)
    }

    @Test(arguments: [(0.0, 0.137, 0.0, true), (1.0, 0.137, 0.0, true),
        (1.0, 0.137, 1.0, false), (1.0, 0.3, 0.0, false)])
    func movingTurnaroundQualifiesSparseFeedback(
        smoothness: Double, delay: Double, miss: Double, succeeds: Bool
    ) {
        let program = GimbalProgram(a: point(0), b: point(30), c: point(20, 20),
            durationAB: 0.5, durationBC: 1, smoothness: smoothness, loop: true)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: program, live: program.a!)
        #expect(started)
        struct Segment {
            var time: Double
            var from: GimbalWaypoint
            var to: GimbalWaypoint
            var duration: Double
        }
        var segments = [Segment(time: 0, from: program.a!, to: program.a!, duration: 1)]
        func physical(_ time: Double) -> GimbalWaypoint {
            let segment = segments.last { $0.time <= time } ?? segments[0]
            return GimbalMoveEngine.lerp(segment.from, segment.to, u: (time - segment.time) / segment.duration)
        }
        var reported = program.a!
        var reportAt = 0.0
        var labels: [String] = []
        var stoppedAt: Double?
        for step in 1...1000 {
            let now = Double(step) / 100
            if step % 10 == 6 {
                reported = physical(now - delay)
                if now - delay >= 3.4 {
                    reported.yawDeg += miss
                    reported.nativePitchDeg = reported.nativePitchDeg.map { $0 + miss }
                }
                reportAt = now
            }
            let out = engine.tick(dt: 0.01, live: reported, telemetryAge: now - reportAt)
            if let target = out?.target {
                labels.append(engine.readout(live: reported)!.label)
                segments.append(Segment(time: now, from: physical(now), to: target, duration: out!.duration))
            }
            if out?.finished == true { stoppedAt = now; break }
        }
        #expect((engine.failure == nil) == succeeds)
        #expect(engine.running == succeeds)
        if succeeds {
            #expect(labels.contains("C→B") && labels.contains("B→A"))
            #expect(segments.count > 10)
        } else {
            #expect(stoppedAt != nil)
            if miss > 0 {
                #expect(labels.contains("C→B"), "Return starts while the turnaround is qualified")
                #expect(stoppedAt! < 4, "Bad arrival must stop within the bounded verification window")
            }
        }
    }

    @Test func lateSmoothedTurnaroundStopsBeforeSendingReturn() {
        let program = GimbalProgram(a: point(0), b: point(30), c: point(30, 20),
            durationAB: 0.5, durationBC: 0.5, smoothness: 1, loop: true)
        var camera = Camera(program)
        for _ in 0..<299 { _ = camera.tick() }
        #expect(camera.turnarounds == 0)
        let out = camera.engine.tick(dt: 0.04, live: program.c!)
        #expect(out?.target == nil)
        #expect(out?.stop == true)
        #expect(camera.engine.failure == "Move interrupted — waypoint dispatch was late")
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
