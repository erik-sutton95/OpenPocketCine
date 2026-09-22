import Testing
@testable import OpenPocketViewCore

@Suite struct GimbalLoopVerificationTests {
    @Test(arguments: [(false, 0.12), (true, 0.0), (true, 0.12)])
    func nativeEndpointEasingReachesEveryTargetWithoutVerificationFailure(loop: Bool, rampSeconds: Double) {
        let result = run(loop: loop, rampSeconds: rampSeconds)
        #expect(result.engine.failure == nil, "Exact endpoint arrival must not fail because firmware eases motor speed")
        if loop { #expect(result.turns >= 2) }
    }

    @Test(arguments: 0..<10)
    func easedArrivalAcrossTelemetryPhases(phase: Int) {
        let result = run(phase: phase, nativePitchB: 174.8)
        #expect(result.engine.failure == nil)
        #expect(result.turns >= 2)
    }

    private enum BadFeedback: CaseIterable {
        case missedEndpoint, offPath, overshoot, wrongApproach, lateralApproach, wrongDeparture, stalled, lateArrival, stale
    }

    @Test(arguments: BadFeedback.allCases)
    private func badTurnaroundStillStops(feedback: BadFeedback) {
        let result = run(feedback: feedback)
        #expect(result.engine.failure != nil)
        #expect(!result.engine.running)
        #expect(result.turns == 1)
        if feedback != .stale {
            #expect(result.engine.failure == "Camera waypoint could not be verified")
        }
    }

    private func run(
        loop: Bool = true, rampSeconds: Double = 0.12, phase: Int = 6,
        nativePitchB: Double = -177.2, feedback: BadFeedback? = nil
    ) -> (engine: GimbalMoveEngine, turns: Int) {
        let a = GimbalWaypoint(yawDeg: 172.1, pitchDeg: -5.6, zoom: 1, nativePitchDeg: -177.2)
        let b = GimbalWaypoint(yawDeg: 130.4, pitchDeg: -4.6, zoom: 1, nativePitchDeg: nativePitchB)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: .init(a: a, b: b, durationAB: 3.5, loop: loop), live: a)
        #expect(started)
        struct Command {
            var at: Double
            var from: GimbalWaypoint
            var to: GimbalWaypoint
            var duration: Double
        }
        var commands = [Command(at: 0, from: a, to: a, duration: 1)]
        func physical(_ time: Double) -> GimbalWaypoint {
            let command = commands.last { $0.at <= time } ?? commands[0]
            let t = max(0, min(command.duration, time - command.at))
            let ramp = min(rampSeconds, command.duration / 2)
            let speed = 1 / (command.duration - ramp)
            let fraction: Double
            if t < ramp {
                fraction = speed * t * t / (2 * ramp)
            } else if t > command.duration - ramp {
                let left = command.duration - t
                fraction = 1 - speed * left * left / (2 * ramp)
            } else {
                fraction = speed * (t - ramp / 2)
            }
            return GimbalMoveEngine.lerp(command.from, command.to, u: fraction)
        }
        var reported = a
        var receipt = 0.0
        var turns = 0
        for step in 1...1300 {
            let now = Double(step) / 100
            let boundary = commands.count > 1 ? commands[1].at + commands[1].duration : Double.infinity
            let relative = now - boundary
            if step % 10 == phase, !(feedback == .stale && relative >= 0) {
                reported = physical(now - 0.06)
                receipt = now
                if relative >= -0.3, relative <= 0.4 {
                    switch feedback {
                    case .missedEndpoint:
                        reported.yawDeg = max(reported.yawDeg, b.yawDeg + 0.4)
                    case .offPath where relative > -0.15 && relative < -0.1:
                        reported.nativePitchDeg! += 0.7
                    case .overshoot where relative > -0.05 && relative < 0:
                        reported.yawDeg = b.yawDeg - 0.7
                    case .wrongApproach where relative > -0.05 && relative < 0:
                        reported.yawDeg = b.yawDeg + 5
                    case .lateralApproach where relative > -0.15 && relative < -0.1:
                        reported = b
                        reported.yawDeg += 0.3
                        reported.nativePitchDeg! += 0.15
                    case .lateralApproach where relative > -0.05 && relative < 0:
                        reported = b
                        reported.yawDeg += 0.46
                    case .wrongDeparture where relative > 0.2 && relative < 0.3:
                        reported.yawDeg = b.yawDeg + 0.3
                    case .stalled where relative >= 0:
                        reported = b
                    case .lateArrival:
                        reported = physical(now - 0.3)
                    default: break
                    }
                }
            }
            let output = engine.tick(dt: 0.01, live: reported, telemetryAge: now - receipt)
            if let target = output?.target {
                let actual = physical(now)
                if commands.count > 1 {
                    #expect(GimbalMoveEngine.angularDistance(actual, commands.last!.to) < 1e-8,
                        "Camera reached the requested endpoint before reversing")
                    turns += 1
                }
                commands.append(Command(at: now, from: actual, to: target, duration: output!.duration))
            }
            if output?.finished == true { break }
        }
        return (engine, turns)
    }
}
