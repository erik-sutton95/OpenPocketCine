import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct GimbalRepeatabilityTests {
    private let a = GimbalWaypoint(yawDeg: -20, pitchDeg: 1.5, zoom: 1)
    private let b = GimbalWaypoint(yawDeg: 25.3, pitchDeg: -28.2, zoom: 1)
    private let c = GimbalWaypoint(yawDeg: 24.6, pitchDeg: -0.5, zoom: 1)

    /// A native camera executes the absolute target and duration itself. No
    /// joystick transfer function or operator calibration participates.
    @Test func cameraExecutesABCOncePerLegWithSparseFeedback() {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: a, b: b, c: c, durationAB: 5, durationBC: 4), live: a)
        #expect(started)
        var live = a
        var reported = a
        var reportAt = 0.0
        var motionStart = a
        var motionTarget = a
        var motionAt = 0.0
        var motionDuration = 1.0
        var sends: [(Double, GimbalWaypoint, Double)] = []
        for step in 0..<400 {
            let now = Double(step) * 0.04
            live = GimbalMoveEngine.lerp(motionStart, motionTarget, u: (now - motionAt) / motionDuration)
            if Int((now + 1e-6) * 10) > Int((reportAt + 1e-6) * 10) {
                reported = live
                reportAt = now
            }
            guard let out = engine.tick(dt: 0.04, live: reported, telemetryAge: now - reportAt) else { break }
            if let target = out.target {
                sends.append((now, target, out.duration))
                motionStart = live
                motionTarget = target
                motionAt = now
                motionDuration = out.duration
            }
            if out.finished { break }
        }
        #expect(engine.failure == nil)
        #expect(!engine.running)
        #expect(sends.count == 2)
        if sends.count == 2 {
            #expect(sends[0].1 == b && sends[1].1 == c)
            #expect(sends[0].2 == 5 && sends[1].2 == 4)
            #expect(abs(sends[1].0 - sends[0].0 - 5) < 0.040001)
        }
        #expect(GimbalMoveEngine.angularDistance(live, c) <= 0.15)
    }

    @Test(arguments: [(0.06, 0.0, true), (0.06, 0.4, false), (0.5, 0.0, false)])
    func finalPositionUsesFreshSettledReports(delay: Double, miss: Double, succeeds: Bool) {
        let origin = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1, nativePitchDeg: -175)
        let end = GimbalWaypoint(yawDeg: 100, pitchDeg: 20, zoom: 1, nativePitchDeg: 165)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: origin, b: end, durationAB: 5), live: origin)
        #expect(started)
        var reported = origin
        var reportAt = 0.0
        var motionAt: Double?
        for step in 1...800 {
            let now = Double(step) * 0.01
            if step % 10 == 6 {
                if let motionAt {
                    reported = GimbalMoveEngine.lerp(origin, end, u: (now - delay - motionAt) / 5)
                    if now - delay >= motionAt + 5 { reported.yawDeg -= miss }
                }
                reportAt = now
            }
            let out = engine.tick(dt: 0.01, live: reported, telemetryAge: now - reportAt)
            if out?.target != nil { motionAt = now }
            if out?.finished == true { break }
        }
        #expect(!engine.running)
        #expect((engine.failure == nil) == succeeds)
    }

    /// Reproduces the user's starting layout. The old controller crawled at
    /// fractional stick throws and failed at A; now one native command seeks A.
    @Test func approachNeedsNoWaypointUpdateOrCalibration() {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: a, b: b), live: c)
        #expect(started)
        let command = engine.tick(dt: 0.04, live: c)
        #expect(command?.target == a)
        #expect(command?.duration == GimbalProgram.minDuration)
        for _ in 0..<80 { _ = engine.tick(dt: 0.04, live: a) }
        #expect(engine.failure == nil)
        #expect(engine.readout(live: a)?.phase == "RUN")
    }

    @Test func unsupportedOrBlockedCameraCannotPretendApproachSucceeded() {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: a, b: b), live: c)
        #expect(started)
        var last: GimbalMoveEngine.Output?
        for _ in 0..<100 {
            if let out = engine.tick(dt: 0.04, live: c) { last = out }
        }
        #expect(last?.stop == true)
        #expect(engine.failure == "Camera did not reach A")
        #expect(engine.readout(live: c)?.label == "A")
    }

    @Test(arguments: [(0.06, 0.0, true, false, false), (0.12, 0.0, true, false, false),
        (0.06, 0.4, false, false, false), (0.3, 0.0, false, false, false),
        (0.06, 0.4, false, true, false), (0.0605, 0.0, true, false, true)])
    func boundaryFitsBoundedFeedbackDelayWithoutWideningPositionTolerance(
        delay: Double, miss: Double, succeeds: Bool, lateOnly: Bool, fast: Bool
    ) {
        let origin = GimbalWaypoint(yawDeg: fast ? 0 : 20, pitchDeg: 0, zoom: 1, nativePitchDeg: 175)
        let middle = GimbalWaypoint(yawDeg: fast ? 200 : 60, pitchDeg: 0, zoom: 1, nativePitchDeg: 175)
        let end = GimbalWaypoint(yawDeg: fast ? 0 : 100, pitchDeg: 0, zoom: 1, nativePitchDeg: 175)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: origin, b: middle, c: end,
            durationAB: fast ? 0.5 : 2, durationBC: fast ? 0.5 : 2), live: origin)
        #expect(started)
        var segments: [(at: Double, from: GimbalWaypoint, to: GimbalWaypoint, duration: Double)] = [(0, origin, origin, 1)]
        func physical(_ time: Double) -> GimbalWaypoint {
            let leg = segments.last { $0.at <= time } ?? segments[0]
            return GimbalMoveEngine.lerp(leg.from, leg.to, u: (time - leg.at) / leg.duration)
        }
        var reported = origin
        var reportAt = 0.0
        for step in 1...800 {
            let now = Double(step) * 0.01
            if step % 10 == 6 {
                reported = physical(now - delay)
                if lateOnly ? (now >= 4.2 && now <= 4.3) : now >= 3.7 { reported.nativePitchDeg = 175 + miss }
                reportAt = now
            }
            let out = engine.tick(dt: 0.01, live: reported, telemetryAge: now - reportAt)
            if let target = out?.target {
                segments.append((now, physical(now), target, out!.duration))
            }
            if out?.finished == true { break }
        }
        #expect(!engine.running)
        #expect((engine.failure == nil) == succeeds)
    }

    @Test func reachingBEarlyDoesNotVerifyItsDeadline() {
        let origin = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
        let end = GimbalWaypoint(yawDeg: 10, pitchDeg: 0, zoom: 1)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: origin, b: end, c: origin,
            durationAB: 1, durationBC: 1), live: origin)
        #expect(started)
        for step in 1...120 {
            let now = Double(step) * 0.04
            var yaw = now <= 2 ? 0 : now <= 3 ? (now - 2) * 10 : max(0, (4 - now) * 10)
            if abs(now - 2.92) < 0.001 { yaw = 10 }
            if now >= 2.96, now < 3.5 { yaw -= 1 }
            _ = engine.tick(dt: 0.04, live: GimbalWaypoint(yawDeg: yaw, pitchDeg: 0, zoom: 1))
        }
        #expect(engine.failure == "Camera waypoint could not be verified")
    }

    @Test func lateBoundaryCannotSilentlyStretchTheTake() {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: a, b: b, c: c,
            durationAB: 5, durationBC: 4), live: a)
        #expect(started)
        for _ in 0..<50 { _ = engine.tick(dt: 0.04, live: a) }
        for _ in 0..<124 { _ = engine.tick(dt: 0.04, live: b) }
        let out = engine.tick(dt: 0.08, live: b)
        #expect(out?.stop == true)
        #expect(out?.target == nil)
        #expect(engine.failure == "Move interrupted — waypoint dispatch was late")
    }

    @Test func minimumDurationDoesNotImposeAnArtificialSpeedCap() {
        let from = GimbalWaypoint(yawDeg: 100, pitchDeg: -40, zoom: 1)
        let to = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
        #expect(GimbalProgram.minTravelDuration(from: from, to: to) == 0.5)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: from, b: to, durationAB: 0.5), live: from)
        #expect(started)
    }

    @Test(arguments: [0.31, Double.nan, Double.infinity])
    func missingFeedbackStopsNativeMotion(age: Double) {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: a, b: b), live: a)
        #expect(started)
        let out = engine.tick(dt: 0.04, live: a, telemetryAge: age)
        #expect(out?.stop == true && out?.finished == true)
    }

    @Test func canceledMoveCannotSendAnotherNativeTarget() {
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: a, b: b), live: c)
        #expect(started)
        _ = engine.tick(dt: 0.04, live: c)
        engine.cancel()
        let later = engine.tick(dt: 0.04, live: c)
        #expect(later == nil)
    }

    @Test func editingPointPreservesDuration() {
        var program = GimbalProgram(a: a, b: b, durationAB: 10)
        program.setPoint(.b, c)
        #expect(program.durationAB == 10)
    }

    @Test func antipodalPitchResidualsCannotCancelIntoSuccess() {
        let origin = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1, nativePitchDeg: 0)
        var engine = GimbalMoveEngine()
        let started = engine.start(program: GimbalProgram(a: origin, b: origin, c: origin,
            durationAB: 1, durationBC: 1), live: origin)
        #expect(started)
        var reported = origin
        var reportedAt = 0.0
        for step in 1...120 {
            let now = Double(step) * 0.04
            if step != 75 {
                reported = origin
                reported.nativePitchDeg = step == 74 ? 179.9 : step == 76 ? -179.9 : 0
                reportedAt = now
            }
            _ = engine.tick(dt: 0.04, live: reported, telemetryAge: now - reportedAt)
        }
        #expect(engine.failure == "Camera waypoint could not be verified")
    }

    @Test func nativeRunCannotFallBackToDisplayPitch() {
        let native = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1, nativePitchDeg: 0)
        let displayOnly = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
        var engine = GimbalMoveEngine()
        let mixed = engine.start(program: GimbalProgram(a: native, b: displayOnly), live: native)
        #expect(!mixed)
        let started = engine.start(program: GimbalProgram(a: native, b: native), live: native)
        #expect(started)
        let out = engine.tick(dt: 0.04, live: displayOnly)
        #expect(out?.stop == true)
    }

    @Test func nativePitchCaptureAndWrapKeepTheShortPath() {
        let from = GimbalWaypoint.from(yawTenth: -104, pitchTenth: -297,
            zoom: 1, nativePitchTenth: -1510)
        #expect(from?.pitchDeg == -29.7)
        #expect(from?.nativePitchDeg == -151)
        #expect(from?.clamped().nativePitchDeg == -151)
        let low = GimbalWaypoint(yawDeg: 0, pitchDeg: 1, zoom: 1, nativePitchDeg: 179)
        let high = GimbalWaypoint(yawDeg: 0, pitchDeg: -1, zoom: 1, nativePitchDeg: -179)
        #expect(GimbalMoveEngine.pitchDelta(from: low, to: high) == 2)
        #expect(GimbalMoveEngine.angularDistance(low, high) == 2)
        #expect(GimbalMoveEngine.lerp(low, high, u: 0.5).nativePitchDeg == -180)
        let sameNative = GimbalWaypoint(yawDeg: 0, pitchDeg: -0.8, zoom: 1, nativePitchDeg: -179)
        #expect(GimbalMoveEngine.angularDistance(high, sameNative) == 0)
    }

    @Test func nativePacketUsesCapturedAbsolutePitchAndTenthsSeconds() {
        let frame = Commands.gimbalTimedTarget(yawDeg: 25.3, nativePitchDeg: -151, duration: 5)
        #expect(frame?.cmdSet == 4 && frame?.cmdId == 0x14)
        #expect(frame?.flags == Duml.flagNotify)
        #expect(frame?.payload == [253, 0, 0, 0, 26, 250, 5, 50])
        #expect(Commands.gimbalTimedStop().payload == [0, 0, 0, 0, 0, 0, 4, 1])
        #expect(Commands.gimbalTimedTarget(yawDeg: 999, nativePitchDeg: 0, duration: 1) == nil)
        #expect(Commands.gimbalTimedTarget(yawDeg: 0, nativePitchDeg: 0, duration: .nan) == nil)
        #expect(Commands.gimbalTimedTarget(yawDeg: 0, nativePitchDeg: 0, duration: 1.01) == nil)
    }
}
