import Testing
@testable import OpenPocketViewCore

@Suite struct GimbalLoopTests {
    private func point(_ yaw: Double, _ pitch: Double = 0) -> GimbalWaypoint {
        GimbalWaypoint(yawDeg: yaw, pitchDeg: pitch, zoom: 1, nativePitchDeg: -pitch)
    }

    /// Executes native timed targets, including the return to A, on a monotonic clock.
    private struct Camera {
        var engine = GimbalMoveEngine()
        var live: GimbalWaypoint
        var from: GimbalWaypoint
        var target: GimbalWaypoint
        var now = 0.0
        var sentAt = 0.0
        var duration = 1.0
        var commands: [(phase: String, target: GimbalWaypoint, duration: Double)] = []
        var cycles = 0

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
            let after = engine.readout(live: live)?.phase ?? ""
            if before == "VERIFY", after == "APPROACH" || after == "HOLD" { cycles += 1 }
            if let next = out?.target {
                #expect(GimbalMoveEngine.canSendNativeTarget(from: live, to: next))
                commands.append((after, next, out!.duration))
                from = live
                target = next
                sentAt = now
                duration = out!.duration
            }
            return out
        }
    }

    @Test(arguments: [(false, 0.0), (true, 0.0), (true, 0.5)])
    func repeatsWholeProgramAfterVerifiedFinish(hasC: Bool, smoothness: Double) {
        let program = GimbalProgram(a: point(0), b: point(30), c: hasC ? point(30, 20) : nil,
            durationAB: 3, durationBC: 2, smoothness: smoothness, loop: true)
        var camera = Camera(program)
        for _ in 0..<3000 {
            let out = camera.tick()
            #expect(out?.finished == false)
            if camera.cycles == 3 || !camera.engine.running { break }
        }
        #expect(camera.cycles == 3)
        #expect(camera.engine.failure == nil)
        #expect(camera.engine.running)
        #expect(camera.commands.filter { $0.phase == "APPROACH" && $0.target == program.a }.count == 2)
        let ends = camera.commands.filter { $0.phase == "RUN" && $0.target == (program.c ?? program.b) }
        #expect(ends.count == 3)
        if smoothness == 0 {
            #expect(camera.commands.filter { $0.phase == "RUN" && $0.target == program.b }
                .allSatisfy { $0.duration == program.durationAB })
        }
        let takeDuration = program.durationAB + (hasC ? program.durationBC : 0)
        #expect(camera.now >= 3 * (takeDuration + GimbalMoveEngine.holdSeconds + 0.3))
    }

    @Test func loopDefaultsOffAndFinishesOnce() {
        let program = GimbalProgram(a: point(0), b: point(30), durationAB: 1)
        #expect(!program.loop)
        var camera = Camera(program)
        for _ in 0..<1000 where camera.engine.running { _ = camera.tick() }
        #expect(camera.cycles == 0)
        #expect(camera.commands.count == 1)
        #expect(!camera.engine.running)
        #expect(camera.engine.failure == nil)
    }

    @Test func wideReturnUsesReachableSubdivisions() {
        let program = GimbalProgram(a: point(-40), b: point(225), durationAB: 4, loop: true)
        var camera = Camera(program)
        for _ in 0..<2000 {
            _ = camera.tick()
            if camera.cycles == 2 || !camera.engine.running { break }
        }
        #expect(camera.cycles == 2)
        #expect(camera.engine.failure == nil)
        let returns = camera.commands.filter { $0.phase == "APPROACH" }
        #expect(returns.count == 3)
        #expect(returns.last?.target == program.a)
    }

    @Test(arguments: [0.0, 0.5])
    func resumedTakeRepeatsOriginalFullPath(smoothness: Double) {
        let program = GimbalProgram(a: point(0), b: point(30), c: point(30, 20),
            durationAB: 3, durationBC: 2, smoothness: smoothness, loop: true)
        var camera = Camera(program)
        for _ in 0..<300 { _ = camera.tick() }
        let paused = camera.engine.pause(live: camera.live)
        #expect(paused)
        #expect(camera.engine.tick(dt: 60, live: camera.live) == nil)
        let resumed = camera.engine.resume(live: camera.live)
        #expect(resumed)
        for _ in 0..<1200 {
            _ = camera.tick()
            if camera.cycles == 1 || !camera.engine.running { break }
        }
        let boundary = camera.commands.count
        for _ in 0..<1200 {
            _ = camera.tick()
            if camera.cycles == 2 || !camera.engine.running { break }
        }
        #expect(camera.cycles == 2)
        #expect(camera.engine.failure == nil)
        let nextTake = camera.commands.dropFirst(boundary).filter { $0.phase == "RUN" }
        if smoothness == 0 {
            #expect(nextTake.map(\.target) == [program.b!, program.c!])
            #expect(nextTake.map(\.duration) == [3, 2])
        } else {
            #expect(nextTake.first?.target == GimbalProgramCurve(program: program)?.position(at: 0.1))
            #expect(nextTake.last?.target == program.c)
            #expect(nextTake.count == 99)
        }
    }

    @Test(arguments: ["VERIFY", "APPROACH", "HOLD"])
    func stopDuringBoundaryOrReturnCannotRestart(phase: String) {
        var camera = Camera(GimbalProgram(a: point(0), b: point(30), durationAB: 1, loop: true))
        for _ in 0..<1200 {
            _ = camera.tick()
            if camera.engine.readout(live: camera.live)?.phase == phase,
                phase == "VERIFY" || camera.cycles == 1 { break }
        }
        #expect(camera.engine.readout(live: camera.live)?.phase == phase)
        camera.engine.cancel()
        for _ in 0..<100 { #expect(camera.tick() == nil) }
        #expect(!camera.engine.running)
        let resumed = camera.engine.resume(live: camera.live)
        #expect(!resumed)
    }

    @Test func failedFinalVerificationDoesNotLoop() {
        var camera = Camera(GimbalProgram(a: point(0), b: point(30), durationAB: 1, loop: true))
        for _ in 0..<1000 where camera.engine.running {
            _ = camera.tick(miss: camera.now >= 3 ? 1 : 0)
        }
        #expect(camera.engine.failure != nil)
        #expect(!camera.engine.running)
        #expect(camera.cycles == 0)
        #expect(camera.commands.count == 1)
        #expect(camera.tick() == nil)
    }

    @Test func lostFeedbackOnReturnStopsInsteadOfRetrying() {
        var camera = Camera(GimbalProgram(a: point(0), b: point(30), durationAB: 1, loop: true))
        for _ in 0..<1000 {
            _ = camera.tick()
            if camera.cycles == 1 { break }
        }
        #expect(camera.cycles == 1)
        let out = camera.engine.tick(dt: 0.01, live: camera.live, telemetryAge: 0.31)
        #expect(out?.stop == true)
        #expect(out?.finished == true)
        #expect(camera.engine.failure != nil)
        #expect(camera.tick() == nil)
    }
}
