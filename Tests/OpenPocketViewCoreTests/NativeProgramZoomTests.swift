import Foundation
import Testing
@testable import OpenPocketViewCore

@Suite struct NativeProgramZoomTests {
    @Test func zoomTraversesTheFullLinearRangeDuringTheWholeLeg() {
        for (from, to) in [(3.0, 6.0), (6.0, 3.0), (3.0, 3.01)] {
            var controller = readyController(from: from, to: to)
            var measured = from
            var previousWrite = -Double.infinity
            var samples = 0
            for tick in 0...5000 {
                let elapsed = Double(tick) / 1000
                controller.observe(lens(CamFov.pinchLens(for: measured)), at: elapsed)
                let demand = NativeProgramZoom.demand(from: from, to: to, duration: 5, elapsed: elapsed)
                if let command = controller.nativeCommand(for: demand, at: elapsed) {
                    guard case .track = command else { Issue.record("Timed leg must send lens targets"); return }
                    #expect(elapsed - previousWrite >= 0.02 - 1e-9)
                    previousWrite = elapsed
                    let bytes = command.frame.payload
                    measured = Double(UInt16(bytes[2]) | UInt16(bytes[3]) << 8) / 217
                    samples += 1
                    #expect(abs(measured - (from + (to - from) * elapsed / 5)) <= 1.0 / 217 + 1e-9)
                }
                if [50, 1250, 2500, 3750, 5000].contains(tick) {
                    let expected = from + (to - from) * elapsed / 5
                    let sampleError = abs(to - from) / 5 * NativeProgramZoom.interval + 1.0 / 217
                    #expect(abs(measured - expected) <= sampleError + 1e-9,
                        "Zoom must follow elapsed time from the beginning in both directions")
                }
            }
            #expect(samples <= 251)
        }
    }

    @Test func pathRetainsBAndReanchorsToMeasuredZoomOnResume() {
        let path = GimbalZoomPath(program: program(from: 3, to: 6, c: 4))
        #expect(path.nativeDemand(at: 1.25).command == .track(4.5))
        #expect(path.nativeDemand(at: 2.5).command == .track(6))
        #expect(path.nativeDemand(at: 3.5).command == .track(5))
        #expect(path.nativeDemand(at: 4.5).command == .track(4))
        let resumed = path.remaining(after: 1.5, from: 5.2, quantized: true)
        #expect(resumed.legs[0].duration == 1)
        #expect(resumed.nativeDemand(at: 0).command == .track(5.2))
        #expect(resumed.nativeDemand(at: 0.5).command == .track(5.6))
        #expect(resumed.nativeDemand(at: 1).command == .track(6))
    }

    @Test func invalidInputsStopAndEqualZoomDoesNotGenerateTargets() {
        #expect(NativeProgramZoom.demand(from: 3, to: 3, duration: 10, elapsed: 1).command == .stop)
        for duration in [0.0, -1, .nan, .infinity] {
            #expect(NativeProgramZoom.demand(from: 3, to: 6, duration: duration, elapsed: 0).failureReason != nil)
        }
        #expect(NativeProgramZoom.demand(from: .nan, to: 6, duration: 1, elapsed: 0).failureReason != nil)
        #expect(NativeProgramZoom.demand(from: 3, to: 6, duration: 1, elapsed: .nan).failureReason != nil)
        #expect(NativeProgramZoom.demand(from: 3, to: 6, duration: 1, elapsed: 2).command == .track(6))
        // Position control has no native rocker's minimum travel or gear speed limit.
        #expect(readyController(from: 3, to: 3.001).failureReason == nil)
    }

    @Test func transportRejectsStaleLensAndDLog2ButStopIsImmediateAfterAdmission() {
        var controller = readyController()
        let request = NativeProgramZoomDemand(command: .track(3.1), destination: 6)
        #expect(controller.nativeCommand(for: request, at: 0) == request.command)
        #expect(controller.nativeCommand(for: .init(command: .track(3.2), destination: 6), at: 0.019) == nil)
        #expect(controller.nativeCommand(for: .init(command: .track(3.2), destination: 6), at: 0.02) == .track(3.2))
        #expect(controller.nativeCommand(for: .init(command: .stop, destination: 6), at: 0.021) == .stop)
        #expect(controller.nativeCommand(for: .init(command: .stop, destination: 6), at: 0.022) == nil)
        #expect(controller.nativeFailure(at: 0.851) != nil)
        #expect(controller.nativeCommand(for: request, at: 0.9) == nil)
        controller.observe(lens(700), at: 1)
        controller.resetDispatch()
        #expect(controller.nativeCommand(for: request, at: 1.1) == request.command)
        controller.notePause(at: 2)
        controller.observe(lens(700), at: 2.1)
        controller.observe(lens(700), at: 2.5)
        #expect(controller.canResume(at: 2.5))
        #expect(!controller.canResume(at: 2.81))
        controller.observe(lens(700), at: 3.5)
        #expect(!controller.canResume(at: 3.5))
        controller.observe(push("cam_image_effect", [0, 0, ColorMode.dLog2.rawValue]), at: 3.6)
        #expect(controller.nativeCommand(for: request, at: 3.65) == nil)
    }

    @Test func preparationMustBeMeasuredBeforeTheFirstTimedTarget() {
        var controller = readyController()
        #expect(controller.nativeCommand(for: .init(command: .position(3), destination: 3), at: 0) == .position(3))
        let demand = NativeProgramZoom.demand(from: 3, to: 6, duration: 5, elapsed: 0.02)
        #expect(controller.nativeFailure(for: demand, at: 0.1) != nil)
        controller.observe(lens(868), at: 0.2)
        #expect(controller.nativeFailure(for: demand, at: 0.2) != nil)
        #expect(controller.nativeCommand(for: demand, at: 0.2) == nil)
        controller.observe(lens(652), at: 0.3)
        #expect(controller.nativeFailure(for: demand, at: 0.3) == nil)
        #expect(controller.nativeCommand(for: demand, at: 0.3) == demand.command)
    }

    @Test func duplicatesConsumeTheirSlotWithoutSpinningOrBursting() {
        var controller = readyController()
        let demand = NativeProgramZoom.demand(from: 3, to: 6, duration: 5, elapsed: 0)
        #expect(controller.nativeCommand(for: demand, at: 0) != nil)
        #expect(controller.nativeCommand(for: demand, at: 0.02) == nil)
        #expect(abs(controller.nextWakeInterval(at: 0.02) - 0.02) < 1e-9)
        #expect(!controller.canSampleNativeTarget(at: 0.039))
        #expect(controller.canSampleNativeTarget(at: 0.04))
        let changed = NativeProgramZoom.demand(from: 3, to: 6, duration: 5, elapsed: 0.04)
        #expect(controller.nativeCommand(for: changed, at: 0.04) == changed.command)
    }

    @Test func enginePreservesEndpointsThroughLoopsAndRetiresTargetsOnPause() {
        let a = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 3)
        var value = program(from: 3, to: 6, c: 4)
        value.loop = true
        value.smoothness = 0.5
        var engine = GimbalMoveEngine()
        #expect(engine.start(program: value, live: a) == true)
        var positions: [Double] = []
        for _ in 0..<2400 {
            _ = engine.tick(dt: 0.01, live: a)
            if case .track(let factor) = engine.consumeNativeZoomDemand()?.command { positions.append(factor) }
        }
        #expect(engine.running)
        #expect(positions.contains(6))
        #expect(positions.contains(4))
        #expect(positions.contains(3))
        #expect(zip(positions, positions.dropFirst()).contains { $1 > $0 })
        #expect(zip(positions, positions.dropFirst()).contains { $1 < $0 })
        #expect(engine.pause(live: a) == true)
        #expect(engine.nativeZoomDemand == nil)
        engine.cancel()
        #expect(engine.nativeZoomDemand == nil)
    }

    @Test func finalSavedAmountIsRetainedDuringVerification() {
        var engine = GimbalMoveEngine()
        let a = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 3)
        #expect(engine.start(program: program(from: 3, to: 6), live: a) == true)
        var reachedEnd = false
        for _ in 0..<1000 {
            _ = engine.tick(dt: 0.01, live: a)
            if engine.readout(live: a)?.phase == "VERIFY" {
                #expect(engine.nativeZoomDemand?.command == .track(6))
                #expect(engine.consumeNativeZoomDemand()?.command == .track(6))
                reachedEnd = true
            }
            if !engine.running { break }
        }
        #expect(reachedEnd)
        #expect(!engine.running)
    }

    private func program(from: Double, to: Double, c: Double? = nil) -> GimbalProgram {
        .init(a: .init(yawDeg: 0, pitchDeg: 0, zoom: from), b: .init(yawDeg: 0, pitchDeg: 0, zoom: to),
            c: c.map { .init(yawDeg: 0, pitchDeg: 0, zoom: $0) }, durationAB: 2.5, durationBC: 2)
    }

    private func readyController(from: Double = 3, to: Double = 6) -> GimbalProgramZoom {
        var status = CameraStatus()
        status.colorMode = .normal
        status.zoomLens = CamFov.pinchLens(for: from)
        status.shootingMode = 1
        var controller = GimbalProgramZoom(program: program(from: from, to: to),
            model: .init(name: "Osmo Pocket 4 Pro"), status: status)
        controller.observe(lens(CamFov.pinchLens(for: from)), at: 0)
        return controller
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
