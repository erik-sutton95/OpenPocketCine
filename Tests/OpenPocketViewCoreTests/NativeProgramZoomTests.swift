import Foundation
import Testing
@testable import OpenPocketViewCore

@Suite struct NativeProgramZoomTests {
    @Test func rockerCommandsMatchTheSuccessfulMimoCapture() {
        #expect(NativeProgramZoomCommand.rate(speed: 72, increasing: true).frame.payload == [1, 0x48, 1, 0])
        #expect(NativeProgramZoomCommand.rate(speed: 73, increasing: false).frame.payload == [1, 0x49, 0, 0])
        #expect(NativeProgramZoomCommand.stop.frame.payload == [0xff, 0, 0, 0])
        #expect(NativeProgramZoomCommand.rate(speed: 72, increasing: true).frame.flags == 0x40)
    }

    @Test func timedLegBlendsNativeSpeedsWithoutPositionStepsOrStopPulses() {
        let dt = 0.0005
        var distance = 0.0
        var commands: [NativeProgramZoomCommand] = []
        for i in 0..<5000 {
            let command = NativeProgramZoom.demand(from: 3, to: 6, duration: 2.5, elapsed: Double(i) * dt).command
            guard case .rate(let speed, let increasing) = command else {
                Issue.record("Timed movement must use a native rate throughout"); return
            }
            #expect(increasing)
            distance += Double(speed - 71) * NativeProgramZoom.slowestLogRate * dt
            if commands.last != command { commands.append(command) }
        }
        #expect(commands == [.rate(speed: 72, increasing: true), .rate(speed: 73, increasing: true),
            .rate(speed: 72, increasing: true)])
        #expect(abs(3 * exp(distance) - 6) < 0.002)
        #expect(NativeProgramZoom.demand(from: 3, to: 6, duration: 2.5, elapsed: 2.5).command == .stop)
    }

    @Test func longLegWaitsThenZoomsContinuouslyToItsDeadline() {
        let duration = 10.0
        let delay = duration - log(2) / NativeProgramZoom.slowestLogRate
        #expect(NativeProgramZoom.demand(from: 6, to: 3, duration: duration, elapsed: delay - 0.001).command == .stop)
        #expect(NativeProgramZoom.demand(from: 6, to: 3, duration: duration, elapsed: delay + 0.001).command
            == .rate(speed: 72, increasing: false))
        #expect(NativeProgramZoom.demand(from: 6, to: 3, duration: duration, elapsed: 9.99).command
            == .rate(speed: 72, increasing: false))
        #expect(NativeProgramZoom.demand(from: 3, to: 3, duration: 2, elapsed: 1).command == .stop)
    }

    @Test func nativePathRetainsBAndUsesMeasuredZoomAfterResume() {
        let a = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 3)
        let b = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 6)
        let c = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 4)
        let path = GimbalZoomPath(program: .init(a: a, b: b, c: c, durationAB: 2.5, durationBC: 2))
        #expect(path.nativeDemand(at: 2.499).destination == 6)
        #expect(path.nativeDemand(at: 2.5).destination == 4)
        #expect(path.nativeDemand(at: 2.5).command == .stop, "The smaller B-C change waits for its continuous window")
        #expect(path.nativeDemand(at: 4).command == .rate(speed: 72, increasing: false))
        let continuous = GimbalZoomPath(program: .init(a: a, b: b,
            c: .init(yawDeg: 0, pitchDeg: 0, zoom: 3), durationAB: 2.5, durationBC: 2.5))
        #expect(continuous.nativeDemand(at: 2.5 - 5e-10).command == .rate(speed: 72, increasing: false))
        let resumed = path.remaining(after: 1.5, from: 5.2, quantized: true)
        #expect(resumed.legs[0].from == 5.2)
        #expect(resumed.legs[0].duration == 1)
        #expect(resumed.nativeDemand(at: 0).command == .stop)
        #expect(resumed.nativeDemand(at: 0.9).command == .rate(speed: 72, increasing: true))
    }

    @Test func transportRefreshesRatesAndRejectsStaleLensColorAndImpossibleTiming() {
        let model = CameraModel(name: "Osmo Pocket 4 Pro")
        let program = GimbalProgram(a: .init(yawDeg: 0, pitchDeg: 0, zoom: 3),
            b: .init(yawDeg: 0, pitchDeg: 0, zoom: 6), durationAB: 2.5)
        var status = CameraStatus()
        status.colorMode = .normal
        status.zoomLens = 651
        status.shootingMode = 1
        var controller = GimbalProgramZoom(program: program, model: model, status: status)
        let request = NativeProgramZoomDemand(command: .rate(speed: 72, increasing: true), destination: 6)
        #expect(controller.nativeCommand(for: request, at: 0) == nil)
        controller.observe(lens(651), at: 0)
        #expect(controller.nativeCommand(for: request, at: 0) == request.command)
        #expect(controller.nativeCommand(for: request, at: 0.049) == nil)
        #expect(controller.nativeCommand(for: request, at: 0.05) == request.command)
        #expect(controller.nativeCommand(for: request, at: 0.8) == request.command)
        #expect(controller.nativeFailure(at: 0.851) != nil)
        #expect(controller.nativeCommand(for: request, at: 0.9) == nil)
        controller.observe(lens(700), at: 1)
        let stop = NativeProgramZoomDemand(command: .stop, destination: 6)
        #expect(controller.nativeCommand(for: stop, at: 1) == .stop)
        #expect(controller.nativeCommand(for: stop, at: 1.1) == nil)
        controller.resetDispatch()
        #expect(controller.nativeCommand(for: request, at: 1.1) == request.command)
        controller.notePause(at: 2)
        controller.observe(lens(700), at: 2.1)
        controller.observe(lens(700), at: 2.5)
        #expect(controller.canResume(at: 2.5), "Two 2.5 Hz lens reports can establish a settled pause")
        #expect(!controller.canResume(at: 2.81))
        controller.observe(lens(700), at: 3.5)
        #expect(!controller.canResume(at: 3.5), "A missing-report gap must restart stability")
        controller.observe(push("cam_image_effect", [0, 0, ColorMode.dLog2.rawValue]), at: 3.6)
        #expect(controller.nativeCommand(for: request, at: 3.65) == nil)
        var fast = program
        fast.a?.zoom = 1
        fast.b?.zoom = 12
        fast.durationAB = 0.5
        #expect(GimbalProgramZoom(program: fast, model: model, status: status).failureReason
            == "Increase the move duration for this zoom range")
        #expect(!GimbalProgramZoom(program: program, model: .init(name: "Osmo Pocket 3"), status: status).usesNativeRate)
        #expect(NativeProgramZoom.demand(from: 1, to: 6, duration: 0.1, elapsed: 0).failureReason
            == "Increase the move duration for this zoom range")
    }

    @Test func engineUsesNativeRatesDuringBothDirectionsAndNoCommandsWhilePaused() {
        let a = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 3)
        let b = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 6)
        var engine = GimbalMoveEngine()
        #expect(engine.start(program: .init(a: a, b: b, durationAB: 2.5, loop: true), live: a) == true)
        #expect(engine.nativeZoomDemand?.command == .position(3))
        var directions = Set<Bool>()
        for _ in 0..<710 {
            _ = engine.tick(dt: 0.01, live: a)
            if case .rate(_, let increasing) = engine.nativeZoomDemand?.command { directions.insert(increasing) }
        }
        #expect(engine.running)
        #expect(directions == [true, false])
        #expect(engine.pause(live: a) == true)
        #expect(engine.nativeZoomDemand == nil)
        engine.cancel()
        #expect(engine.nativeZoomDemand == nil)
    }

    @Test func nativeSchedulerKeepsExactTransitionsAtRealDispatchCadence() {
        // Includes tiny ideal fast/slow spans that must be coalesced, and both directions.
        for exponent in [log(2), 0.208 * 2.51, 0.208 * 4.99] {
            for increasing in [true, false] {
                let from = increasing ? 3 : 3 * exp(exponent)
                let to = increasing ? 3 * exp(exponent) : 3
                let program = GimbalProgram(a: .init(yawDeg: 0, pitchDeg: 0, zoom: from),
                    b: .init(yawDeg: 0, pitchDeg: 0, zoom: to), durationAB: 2.5)
                var status = CameraStatus()
                status.colorMode = .normal
                status.zoomLens = 651
                status.shootingMode = 1
                var controller = GimbalProgramZoom(program: program,
                    model: .init(name: "Osmo Pocket 4 Pro"), status: status)
                var time = 0.0
                var integral = 0.0
                var previousTime = 0.0
                var previousRate = 0.0
                var lastRateAt = -Double.infinity
                var steps = 0
                while time < 2.5 + 1e-9, steps < 1000 {
                    integral += previousRate * (time - previousTime)
                    previousTime = time
                    controller.observe(lens(651), at: time)
                    let demand = NativeProgramZoom.demand(from: from, to: to, duration: 2.5, elapsed: time)
                    #expect(demand.failureReason == nil)
                    if let command = controller.nativeCommand(for: demand, at: time) {
                        switch command {
                        case .rate(let speed, _):
                            #expect(time - lastRateAt >= 0.05 - 1e-8)
                            lastRateAt = time
                            previousRate = Double(speed - 71) * NativeProgramZoom.slowestLogRate
                        case .stop: previousRate = 0
                        case .position: Issue.record("Timed leg sent an absolute target")
                        }
                    }
                    steps += 1
                    if time >= 2.5 - 1e-9 { break }
                    time = min(2.5, time + min(0.04, controller.nextWakeInterval(at: time)))
                }
                #expect(steps < 1000, "Scheduler must not spin at an expired refresh deadline")
                #expect(abs(integral - exponent) < 1e-7)
                #expect(previousRate == 0, "STOP must dispatch at the waypoint, outside the refresh gate")
            }
        }
        #expect(NativeProgramZoom.timingFailure(from: 3, to: 3.01, duration: 2.5)
            == "Increase the zoom difference between points")
        #expect(NativeProgramZoom.demand(from: 3, to: 3.01, duration: 0.2, elapsed: 0).failureReason != nil)
    }

    @Test func nativeStartRequiresMeasuredPreparationAfterThePositionCommand() {
        let program = GimbalProgram(a: .init(yawDeg: 0, pitchDeg: 0, zoom: 3),
            b: .init(yawDeg: 0, pitchDeg: 0, zoom: 6), durationAB: 2.5)
        var status = CameraStatus()
        status.colorMode = .normal
        status.zoomLens = 651
        status.shootingMode = 1
        var controller = GimbalProgramZoom(program: program,
            model: .init(name: "Osmo Pocket 4 Pro"), status: status)
        controller.observe(lens(651), at: 0)
        #expect(controller.nativeCommand(for: .init(command: .position(3), destination: 3), at: 0) == .position(3))
        let demand = NativeProgramZoom.demand(from: 3, to: 6, duration: 2.5, elapsed: 0)
        #expect(controller.nativeFailure(for: demand, at: 0.1) != nil, "Receipt before setup is not proof")
        controller.observe(lens(868), at: 0.2)
        #expect(controller.nativeFailure(for: demand, at: 0.2) != nil, "Wrong starting zoom must fail")
        #expect(controller.nativeCommand(for: demand, at: 0.2) == nil)
        controller.observe(lens(652), at: 0.3)
        #expect(controller.nativeFailure(for: demand, at: 0.3) == nil)
        #expect(controller.nativeCommand(for: demand, at: 0.3) == demand.command)
    }

    private func push(_ name: String, _ value: [UInt8]) -> Duml.Frame {
        .init(sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0, cmdId: 0x99,
            payload: SubscribePush.pack(name: name, value: value))
    }

    private func lens(_ lens: UInt16) -> Duml.Frame {
        var value = [UInt8](repeating: 0, count: 16)
        value[14] = UInt8(lens & 0xff)
        value[15] = UInt8(lens >> 8)
        return push("cam_lens_state", value)
    }
}
