import Foundation

/// One programmed gimbal pose: live `0x04/0x05` yaw/pitch plus the zoom chip.
public struct GimbalWaypoint: Equatable, Sendable {
    public var yawDeg: Double
    public var pitchDeg: Double
    public var zoom: Double
    /// Native absolute pitch from attitude i16 @0; display pitch uses @20.
    public var nativePitchDeg: Double?

    public init(yawDeg: Double, pitchDeg: Double, zoom: Double, nativePitchDeg: Double? = nil) {
        self.yawDeg = yawDeg
        self.pitchDeg = pitchDeg
        self.zoom = max(1, zoom)
        self.nativePitchDeg = nativePitchDeg
    }

    /// Raw `0x04/0x05` yaw (±180) onto the reachable interval
    /// `[Reach.panMinDeg, Reach.panMaxDeg]` so A→B is plain subtraction and a
    /// straight line cannot cross the gap. Preserve measurements in the gap;
    /// capture/dispatch reject unreachable targets instead of inventing a pose.
    public static func unwrapYaw(_ rawDeg: Double) -> Double {
        let unwrapped = rawDeg < HeadTrack.Reach.gapMidDeg ? rawDeg + 360 : rawDeg
        return unwrapped
    }

    public func clamped() -> GimbalWaypoint {
        GimbalWaypoint(
            yawDeg: HeadTrack.Reach.clampPan(yawDeg),
            pitchDeg: HeadTrack.Reach.clampTilt(pitchDeg),
            zoom: zoom, nativePitchDeg: nativePitchDeg)
    }

    public static func from(yawTenth: Int16?, pitchTenth: Int16?, zoom: Double,
        nativePitchTenth: Int16? = nil) -> GimbalWaypoint? {
        guard let yawTenth, let pitchTenth else { return nil }
        return GimbalWaypoint(
            yawDeg: unwrapYaw(Double(yawTenth) / 10),
            pitchDeg: Double(pitchTenth) / 10,
            zoom: zoom, nativePitchDeg: nativePitchTenth.map { Double($0) / 10 })
    }
}

public enum GimbalWaypointSlot: String, CaseIterable, Sendable, Hashable {
    case a, b, c

    public var letter: String { rawValue.uppercased() }
}

/// Session-only A·B·C path. C is optional. Durations are per leg.
public struct GimbalProgram: Equatable, Sendable {
    public var a: GimbalWaypoint?
    public var b: GimbalWaypoint?
    public var c: GimbalWaypoint?
    public var durationAB: TimeInterval
    public var durationBC: TimeInterval
    public var smoothness: Double

    public static let durationStep: TimeInterval = 0.5
    public static let minDuration: TimeInterval = 0.5
    public static let maxDuration: TimeInterval = 120
    public static let defaultDuration: TimeInterval = 5
    /// Kept for older tests; UI is ±0.5s from min travel.
    public static let durationStops: [TimeInterval] = [2, 5, 10]

    public init(
        a: GimbalWaypoint? = nil,
        b: GimbalWaypoint? = nil,
        c: GimbalWaypoint? = nil,
        durationAB: TimeInterval = defaultDuration,
        durationBC: TimeInterval = defaultDuration,
        smoothness: Double = 0
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.durationAB = Self.clampedDuration(durationAB)
        self.durationBC = Self.clampedDuration(durationBC)
        self.smoothness = smoothness
    }

    public var canRun: Bool { a != nil && b != nil }

    /// Operator row: Not set / A·B / A·B·C / Partial.
    public var summary: String {
        if a != nil, b != nil, c != nil { return "A·B·C" }
        if a != nil, b != nil { return "A·B" }
        if a != nil || b != nil || c != nil { return "Partial" }
        return "Not set"
    }

    public subscript(slot: GimbalWaypointSlot) -> GimbalWaypoint? {
        get {
            switch slot {
            case .a: a
            case .b: b
            case .c: c
            }
        }
        set {
            switch slot {
            case .a: a = newValue
            case .b: b = newValue
            case .c: c = newValue
            }
        }
    }

    public static func clampedDuration(_ value: TimeInterval) -> TimeInterval {
        min(max(value, minDuration), maxDuration)
    }

    public static func snapDuration(_ value: TimeInterval) -> TimeInterval {
        let clamped = clampedDuration(value)
        return (clamped / durationStep).rounded() * durationStep
    }

    /// The duration editor has a fixed floor; native firmware owns the speed profile.
    public static func minTravelDuration(
        from: GimbalWaypoint?, to: GimbalWaypoint?
    ) -> TimeInterval {
        from == nil || to == nil ? defaultDuration : minDuration
    }

    public static func steppedDuration(
        _ value: TimeInterval, delta: TimeInterval, floor: TimeInterval
    ) -> TimeInterval {
        snapDuration(max(floor, value + delta))
    }

    public static func durationLabel(_ value: TimeInterval) -> String {
        let snap = snapDuration(value)
        if abs(snap - snap.rounded()) < 0.05 { return "\(Int(snap.rounded()))s" }
        return String(format: "%.1fs", snap)
    }

    /// Update a point while preserving chosen durations above the travel floor.
    public mutating func setPoint(
        _ slot: GimbalWaypointSlot, _ point: GimbalWaypoint
    ) {
        self[slot] = point
        seedTravelDurations()
    }

    public mutating func seedTravelDurations() {
        if let a, let b {
            durationAB = max(durationAB, Self.minTravelDuration(from: a, to: b))
        }
        if let b, let c {
            durationBC = max(durationBC, Self.minTravelDuration(from: b, to: c))
        }
    }
}

/// First-order follow on analog throw. Off is a passthrough.
public struct GimbalRampFilter: Equatable, Sendable {
    public var x: Double = 0
    public var y: Double = 0

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public mutating func reset() {
        x = 0
        y = 0
    }

    public mutating func tick(
        targetX: Double, targetY: Double, ramp: GimbalRamp, dt: TimeInterval
    ) -> (Double, Double) {
        let tau = ramp.tau
        if tau <= 0 || dt <= 0 {
            x = targetX
            y = targetY
            return (x, y)
        }
        let alpha = 1 - exp(-dt / tau)
        x += (targetX - x) * alpha
        y += (targetY - y) * alpha
        return (x, y)
    }
}

/// Stick fraction → deg/s for `0x04/0x01` in Fast. Piecewise-linear, odd
/// symmetric. `pocketFast` is the calibration knob: run **Calibrate rate**
/// (iOS debug sheet) and paste the `gimbal-rate:` lines here.
public struct GimbalRateMap: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var stick: Double
        public var degPerSec: Double

        public init(stick: Double, degPerSec: Double) {
            self.stick = stick
            self.degPerSec = degPerSec
        }
    }

    public var points: [Point]

    public init(points: [Point]) {
        self.points = points.sorted { $0.stick < $1.stick }
    }

    public static let linear = GimbalRateMap(points: [
        Point(stick: 0, degPerSec: 0),
        Point(stick: 1, degPerSec: HeadTrack.stickRateDegPerSec),
    ])
    /// ponytail: linear until a device calibration lands; partial throws
    /// measured far below linear (a 5 s leg took 16 s at 32 °/s linear).
    public static let pocketFast = linear

    public var maxRate: Double { points.last?.degPerSec ?? 0 }

    public func rate(forThrow t: Double) -> Double {
        let r = Self.interp(abs(t), xs: points.map(\.stick), ys: points.map(\.degPerSec))
        return t < 0 ? -r : r
    }

    public func `throw`(forRate r: Double) -> Double {
        let s = Self.interp(abs(r), xs: points.map(\.degPerSec), ys: points.map(\.stick))
        return min(max(r < 0 ? -s : s, -1), 1)
    }

    private static func interp(_ x: Double, xs: [Double], ys: [Double]) -> Double {
        guard xs.count == ys.count, let first = xs.first, let last = xs.last else { return 0 }
        if x <= first { return ys[0] }
        if x >= last { return ys[ys.count - 1] }
        for i in 1..<xs.count where x <= xs[i] {
            let span = xs[i] - xs[i - 1]
            let u = span > 0 ? (x - xs[i - 1]) / span : 1
            return ys[i - 1] + (ys[i] - ys[i - 1]) * u
        }
        return ys[ys.count - 1]
    }
}

/// Camera-executed timed positions. The phone sends one native command per
/// leg and observes completion; it never approximates position with a stick.
public struct GimbalMoveEngine: Equatable, Sendable {
    public static let arriveDeg = 0.15
    public static let holdSeconds: TimeInterval = 2

    public struct Output: Equatable, Sendable {
        public var target: GimbalWaypoint?
        public var duration: TimeInterval = 0
        public var stop = false
        public var finished = false
    }

    public struct Readout: Equatable, Sendable {
        public var label: String
        public var phase: String
        public var setDuration: TimeInterval
        public var elapsed: TimeInterval
        public var liveYaw: Double
        public var livePitch: Double
        public var targetYaw: Double
        public var targetPitch: Double
        public var remainingDeg: Double
    }

    private struct Leg: Equatable, Sendable {
        var label: String
        var from: GimbalWaypoint
        var to: GimbalWaypoint
        var duration: TimeInterval
        var needsSubMoves: Bool { duration > 25.5 || abs(to.yawDeg - from.yawDeg) >= 180 }
    }

    private struct Observation: Equatable, Sendable {
        var time: TimeInterval
        var pose: GimbalWaypoint
    }

    private struct Checkpoint: Equatable, Sendable {
        var time: TimeInterval
        var incoming: Leg
        var outgoing: Leg?
        var outgoingAt: TimeInterval
    }

    public private(set) var running = false
    public private(set) var isPaused = false
    public private(set) var verificationInterruptedByPause = false
    private var resumeNeedsCommand = false
    public private(set) var failure: String?
    private var program = GimbalProgram()
    private var legs: [Leg] = []
    private var index = 0
    private var phase = "HOLD"
    private var clock: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var approachDuration: TimeInterval = 0
    private var approachTargets: [GimbalWaypoint] = []
    private var needsCommand = false
    private var observations: [Observation] = []
    private var checkpoints: [Checkpoint] = []
    private var lastReadout: Readout?
    private var curve: GimbalProgramCurve?
    private var nextCurveCommand: TimeInterval = 0

    public init() {}

    public mutating func start(program: GimbalProgram, live: GimbalWaypoint) -> Bool {
        cancel()
        self.program = program
        verificationInterruptedByPause = false
        failure = nil
        lastReadout = nil
        guard let a = program.a, let b = program.b else {
            failure = "Set A and B before running"
            return false
        }
        guard program.smoothness.isFinite, (0...1).contains(program.smoothness) else { return false }
        let points = [a, b, live] + (program.c.map { [$0] } ?? [])
        guard points.allSatisfy({ $0.yawDeg.isFinite && $0.pitchDeg.isFinite
            && $0.zoom.isFinite && $0 == $0.clamped()
            && ($0.nativePitchDeg.map { $0.isFinite && (-180...180).contains($0) } ?? true) }) else {
            failure = "Set reachable gimbal points again"
            return false
        }
        if points.contains(where: { $0.nativePitchDeg != nil }),
            !points.allSatisfy({ $0.nativePitchDeg != nil }) {
            failure = "Set gimbal points from fresh camera feedback"
            return false
        }
        var next = [Leg(label: "A→B", from: a, to: b, duration: program.durationAB)]
        if let c = program.c {
            next.append(Leg(label: "B→C", from: b, to: c, duration: program.durationBC))
        }
        guard next.allSatisfy({ leg in
            leg.duration.isFinite && leg.duration >= GimbalProgram.minDuration
                && leg.duration <= GimbalProgram.maxDuration
                && abs(leg.duration * 10 - (leg.duration * 10).rounded()) < 1e-6
        }) else {
            failure = "Increase the move duration"
            return false
        }
        legs = next
        curve = GimbalProgramCurve(program: program)
        nextCurveCommand = 0
        index = 0
        clock = 0
        elapsed = 0
        observations = []
        checkpoints = []
        let approachSteps = max(1, Int(ceil(abs(a.yawDeg - live.yawDeg) / 120)))
        approachTargets = (1...approachSteps).map {
            Self.lerp(live, a, u: Double($0) / Double(approachSteps))
        }
        // Approach is preparation, not the user-timed take. Avoid a full-arc flick.
        approachDuration = max(GimbalProgram.minDuration,
            ceil(Self.angularDistance(live, a) / Double(approachSteps) / 120 * 10) / 10)
        needsCommand = Self.angularDistance(live, a) > Self.arriveDeg
        phase = needsCommand ? "APPROACH" : "HOLD"
        running = true
        return true
    }

    /// Pause preserves ownership and the remaining itinerary; wall time is ignored.
    public mutating func pause(live: GimbalWaypoint) -> Bool {
        guard running, !isPaused else { return false }
        verificationInterruptedByPause = verificationInterruptedByPause || !checkpoints.isEmpty
        checkpoints = []
        observations = []
        isPaused = true
        lastReadout = snapshot(live: live)
        return true
    }

    public mutating func resume(live: GimbalWaypoint) -> Bool {
        guard running, isPaused, live.yawDeg.isFinite, live.pitchDeg.isFinite,
            live.zoom.isFinite, live == live.clamped(),
            (legs[0].from.nativePitchDeg == nil || live.nativePitchDeg != nil),
            (live.nativePitchDeg.map { $0.isFinite && (-180...180).contains($0) } ?? true) else { return false }
        if phase == "APPROACH" || phase == "HOLD" {
            let interrupted = verificationInterruptedByPause
            let original = program
            guard start(program: original, live: live) else { return false }
            verificationInterruptedByPause = interrupted
            resumeNeedsCommand = true
            return true
        }
        if let curve, phase == "RUN" {
            self.curve = curve.remaining(after: elapsed, from: live)
            index = self.curve!.durationAB > 0 ? 0 : 1
        } else {
            curve = nil
            let remaining = phase == "VERIFY" ? 0.1 : max(0, legs[index].duration - elapsed)
            legs[index].from = live
            legs[index].duration = max(0.1, ceil((remaining - 1e-9) * 10) / 10)
        }
        phase = "RUN"
        clock = 0
        elapsed = 0
        nextCurveCommand = 0
        checkpoints = []
        observations = []
        isPaused = false
        resumeNeedsCommand = true
        return true
    }

    public mutating func cancel() {
        if running { lastReadout?.phase = "STOP" }
        running = false
        isPaused = false
        resumeNeedsCommand = false
        needsCommand = false
        checkpoints = []
        observations = []
    }

    /// Wake on the command deadline, not a fixed sleep after a 25 Hz tick.
    public var nextWakeInterval: TimeInterval {
        guard running else { return 0.04 }
        if let curve, phase == "RUN" {
            let boundary = min(nextCurveCommand, curve.duration)
            return boundary > elapsed + 1e-9 ? min(0.04, boundary - elapsed) : 0.04
        }
        if phase == "RUN", legs[index].needsSubMoves {
            let boundary = min(nextCurveCommand, legs[index].duration)
            return boundary > elapsed + 1e-9 ? min(0.04, boundary - elapsed) : 0.04
        }
        let end = phase == "RUN" ? legs[index].duration
            : phase == "HOLD" ? Self.holdSeconds : 0
        return end > elapsed ? min(0.04, end - elapsed) : 0.04
    }

    public mutating func tick(
        dt: TimeInterval, live: GimbalWaypoint, telemetryAge: TimeInterval = 0
    ) -> Output? {
        guard running, !isPaused else { return nil }
        guard dt.isFinite, dt > 0, dt <= 0.12,
            telemetryAge.isFinite, telemetryAge >= 0, telemetryAge <= 0.3,
            live.yawDeg.isFinite, live.pitchDeg.isFinite,
            (legs[0].from.nativePitchDeg == nil || live.nativePitchDeg != nil),
            (live.nativePitchDeg.map { $0.isFinite && (-180...180).contains($0) } ?? true)
        else { return stop(live: live, reason: "Move interrupted — timing or camera feedback lost") }
        if resumeNeedsCommand {
            resumeNeedsCommand = false
            if phase == "RUN" {
                if let curve {
                    nextCurveCommand = curve.duration <= 0.1 ? curve.duration : min(0.05, curve.duration - 0.1)
                    return output(live: live, target: curve.position(at: 0.1), duration: 0.1)
                }
                return startExactLeg(live: live)
            }
            if phase == "APPROACH" {
                needsCommand = false
                return output(live: live, target: approachTargets.first, duration: approachDuration)
            }
            return output(live: live)
        }
        clock += dt
        elapsed += dt
        let sampleTime = clock - telemetryAge
        if sampleTime > (observations.last?.time ?? -.infinity) + 1e-9 {
            observations.append(Observation(time: sampleTime, pose: live))
        }
        observations.removeAll { $0.time < clock - 0.8 }
        checkpoints = checkpoints.filter { !checkpointIsConsistent($0) }
        if checkpoints.contains(where: { clock - $0.time > 0.4 }) {
            return stop(live: live, reason: "Camera waypoint could not be verified")
        }
        let a = legs[0].from
        if phase == "APPROACH" {
            let approachTarget = approachTargets.first ?? a
            if needsCommand {
                needsCommand = false
                elapsed = 0
                return output(live: live, target: approachTarget, duration: approachDuration)
            }
            if elapsed >= approachDuration,
                Self.angularDistance(live, approachTarget) <= Self.arriveDeg {
                approachTargets.removeFirst()
                elapsed = 0
                if let next = approachTargets.first {
                    return output(live: live, target: next, duration: approachDuration)
                }
                phase = "HOLD"
            } else if elapsed > approachDuration + 0.5 {
                return stop(live: live, reason: "Camera did not reach A")
            }
            return output(live: live)
        }
        if phase == "HOLD" {
            if Self.angularDistance(live, a) > Self.arriveDeg {
                return stop(live: live, reason: "Camera moved before the take")
            }
            if elapsed + 1e-9 < Self.holdSeconds { return output(live: live) }
            phase = "RUN"
            elapsed = 0
            if let curve {
                nextCurveCommand = 0.05
                return output(live: live, target: curve.position(at: 0.1), duration: 0.1)
            }
            return startExactLeg(live: live)
        }
        if phase == "RUN", let curve { return tickCurve(curve, live: live) }
        if phase == "RUN" {
            let leg = legs[index]
            let streamed = leg.needsSubMoves
            if elapsed + 1e-9 < leg.duration {
                return streamed ? tickLinearLeg(live: live) : output(live: live)
            }
            if streamed, nextCurveCommand < leg.duration {
                return stop(live: live, reason: "Move interrupted — waypoint dispatch was late")
            }
            guard elapsed - leg.duration <= 0.02 + 1e-9 else {
                return stop(live: live, reason: "Move interrupted — waypoint dispatch was late")
            }
            checkpoints.append(Checkpoint(
                time: clock - (elapsed - leg.duration), incoming: leg,
                outgoing: index + 1 < legs.count ? legs[index + 1] : nil, outgoingAt: clock))
            if index + 1 < legs.count {
                index += 1
                elapsed = 0
                return startExactLeg(live: live)
            }
            phase = "VERIFY"
            elapsed = 0
            return output(live: live)
        }
        if phase == "VERIFY", elapsed >= 0.3, checkpoints.isEmpty {
            guard Self.angularDistance(live, legs[index].to) <= Self.arriveDeg else {
                return stop(live: live, reason: "Camera missed its final position")
            }
            phase = "DONE"
            running = false
            return output(live: live, finished: true)
        }
        return output(live: live)
    }

    private mutating func startExactLeg(live: GimbalWaypoint) -> Output {
        let leg = legs[index]
        if leg.needsSubMoves {
            nextCurveCommand = 0
            return sendRoutedLegPart(live: live)
        }
        return output(live: live, target: leg.to, duration: leg.duration)
    }

    private mutating func tickLinearLeg(live: GimbalWaypoint) -> Output {
        guard elapsed + 1e-9 >= nextCurveCommand else { return output(live: live) }
        guard elapsed - nextCurveCommand <= 0.02 + 1e-9 else {
            return stop(live: live, reason: "Move interrupted — waypoint dispatch was late")
        }
        return sendRoutedLegPart(live: live)
    }

    private mutating func sendRoutedLegPart(live: GimbalWaypoint) -> Output {
        let leg = legs[index]
        let parts = max(1, Int(ceil(abs(leg.to.yawDeg - leg.from.yawDeg) / 120)),
            Int(ceil(leg.duration / 25.5)))
        let ticks = Int((leg.duration * 10).rounded())
        var endTicks = 0
        let start = nextCurveCommand
        for part in 0..<parts {
            endTicks += ticks / parts + (part < ticks % parts ? 1 : 0)
            let end = Double(endTicks) / 10
            guard end > start + 1e-9 else { continue }
            nextCurveCommand = end
            let target = part == parts - 1 ? leg.to : Self.lerp(leg.from, leg.to, u: end / leg.duration)
            return output(live: live, target: target, duration: Double(endTicks - Int((start * 10).rounded())) / 10)
        }
        return stop(live: live, reason: "Move interrupted — waypoint dispatch was late")
    }

    /// Absolute firmware targets may choose the shortest circular arc. Never
    /// send one that could cross the body's missing pan sector.
    public static func canSendNativeTarget(from live: GimbalWaypoint, to target: GimbalWaypoint) -> Bool {
        live.yawDeg.isFinite && live.pitchDeg.isFinite && target.yawDeg.isFinite
            && target.pitchDeg.isFinite && live == live.clamped() && target == target.clamped()
            && abs((target.yawDeg * 10).rounded() / 10 - live.yawDeg) < 180
    }

    private mutating func tickCurve(_ curve: GimbalProgramCurve, live: GimbalWaypoint) -> Output {
        index = elapsed >= curve.durationAB ? 1 : 0
        if elapsed + 1e-9 >= curve.duration {
            guard nextCurveCommand >= curve.duration else {
                return stop(live: live, reason: "Move interrupted — waypoint dispatch was late")
            }
            checkpoints.append(Checkpoint(time: clock - (elapsed - curve.duration),
                incoming: legs[1], outgoing: nil, outgoingAt: clock))
            phase = "VERIFY"
            elapsed = 0
            return output(live: live)
        }
        guard elapsed + 1e-9 >= nextCurveCommand else { return output(live: live) }
        guard elapsed - nextCurveCommand <= 0.02 + 1e-9 else {
            return stop(live: live, reason: "Move interrupted — waypoint dispatch was late")
        }
        let lastCommandAt = curve.duration - 0.1
        let target = nextCurveCommand >= lastCommandAt - 1e-9
            ? curve.c : curve.position(at: nextCurveCommand + 0.1)
        nextCurveCommand = nextCurveCommand >= lastCommandAt - 1e-9
            ? curve.duration : min(lastCommandAt, nextCurveCommand + 0.05)
        return output(live: live, target: target, duration: 0.1)
    }

    /// Receipt times do not share the camera acquisition clock. Exact B uses
    /// one bounded delay fit across a complete observation window; final C uses
    /// directly observed stable arrival. Neither widens the angular tolerance.
    private func checkpointIsConsistent(_ check: Checkpoint) -> Bool {
        if check.outgoing == nil {
            // Final arrival is stationary and directly observable. Receipt time
            // is not camera acquisition time: interpolating across the command
            // deadline can reject a correct endpoint solely due to radio delay.
            let settled = observations.filter { $0.time >= check.time && $0.time <= check.time + 0.4 }
                .reversed().prefix { Self.angularDistance($0.pose, check.incoming.to) <= Self.arriveDeg }
            guard let last = settled.first, let first = settled.last else { return false }
            return last.time - first.time >= 0.08 - 1e-9
        }
        guard let outgoing = check.outgoing, clock + 1e-9 >= check.time + 0.3 else { return false }
        let nearby = observations.filter { $0.time >= check.time - 0.3 && $0.time <= check.time + 0.3 }
        guard nearby.count >= 3 else { return false }
        // Each reference is affine between these delay breakpoints. Intersect
        // the angular-error circles with that time interval, rather than using
        // a quantized delay grid that rejects high-speed submillisecond delays.
        let low = max(0, nearby[0].time - check.time)
        let high = min(0.2, nearby[nearby.count - 1].time - check.time)
        guard low <= high else { return false }
        func reference(_ sample: Observation, delay: Double) -> GimbalWaypoint {
            let time = sample.time - delay
            return time < check.time
                ? Self.lerp(check.incoming.from, check.incoming.to,
                    u: 1 + (time - check.time) / check.incoming.duration)
                : Self.lerp(outgoing.from, outgoing.to, u: (time - check.outgoingAt) / outgoing.duration)
        }
        var knots = [low, high]
        for sample in nearby {
            for time in [check.time - check.incoming.duration, check.time,
                check.outgoingAt, check.outgoingAt + outgoing.duration] {
                let delay = sample.time - time
                if delay > low, delay < high { knots.append(delay) }
            }
        }
        knots.sort()
        if low == high {
            return nearby.allSatisfy { Self.angularDistance($0.pose, reference($0, delay: low)) <= Self.arriveDeg }
        }
        for (lower, upper) in zip(knots, knots.dropFirst()) where upper - lower > 1e-12 {
            let span = upper - lower
            var feasibleLow = 0.0
            var feasibleHigh = span
            for sample in nearby {
                let first = reference(sample, delay: lower)
                let last = reference(sample, delay: upper)
                let ey = sample.pose.yawDeg - first.yawDeg
                let ep = Self.pitchDelta(from: first, to: sample.pose)
                let vy = -(last.yawDeg - first.yawDeg) / span
                let vp = -Self.pitchDelta(from: first, to: last) / span
                let aa = vy * vy + vp * vp
                let bb = 2 * (ey * vy + ep * vp)
                let cc = ey * ey + ep * ep - Self.arriveDeg * Self.arriveDeg
                if aa < 1e-12 {
                    if cc > 1e-10 { feasibleHigh = -1; break }
                    continue
                }
                let discriminant = bb * bb - 4 * aa * cc
                if discriminant < -1e-9 { feasibleHigh = -1; break }
                let root = sqrt(max(0, discriminant))
                feasibleLow = max(feasibleLow, (-bb - root) / (2 * aa))
                feasibleHigh = min(feasibleHigh, (-bb + root) / (2 * aa))
                if feasibleLow > feasibleHigh { break }
            }
            if feasibleLow <= feasibleHigh {
                let delay = lower + (feasibleLow + feasibleHigh) / 2
                if nearby.allSatisfy({ Self.angularDistance($0.pose, reference($0, delay: delay)) <= Self.arriveDeg + 1e-9 }) {
                    return true
                }
            }
        }
        return false
    }

    private mutating func stop(live: GimbalWaypoint, reason: String) -> Output {
        failure = reason
        // Preserve which target failed, including an approach failure.
        lastReadout = snapshot(live: live)
        lastReadout?.phase = "STOP"
        phase = "STOP"
        running = false
        isPaused = false
        return Output(target: nil, stop: true, finished: true)
    }

    private mutating func output(
        live: GimbalWaypoint, target: GimbalWaypoint? = nil,
        duration: TimeInterval = 0, finished: Bool = false
    ) -> Output {
        if let target, !Self.canSendNativeTarget(from: live, to: target) {
            return stop(live: live, reason: "Camera moved outside the safe rotation path")
        }
        lastReadout = snapshot(live: live)
        return Output(target: target, duration: duration, finished: finished)
    }

    private func snapshot(live: GimbalWaypoint) -> Readout? {
        guard index < legs.count else { return lastReadout }
        let leg = legs[index]
        let atA = phase == "APPROACH" || phase == "HOLD"
        let target = atA ? legs[0].from : leg.to
        return Readout(label: atA ? "A" : leg.label, phase: isPaused ? "PAUSED" : phase,
            setDuration: phase == "APPROACH" ? approachDuration : phase == "HOLD" ? Self.holdSeconds : leg.duration,
            elapsed: phase == "VERIFY" || phase == "DONE" ? leg.duration
                : curve != nil && phase == "RUN" && index == 1 ? elapsed - (curve?.durationAB ?? program.durationAB) : elapsed,
            liveYaw: live.yawDeg, livePitch: live.pitchDeg,
            targetYaw: target.yawDeg, targetPitch: target.pitchDeg,
            remainingDeg: Self.angularDistance(live, target))
    }

    public func readout(live: GimbalWaypoint) -> Readout? {
        running ? snapshot(live: live) : lastReadout
    }

    public func hudText(live: GimbalWaypoint?) -> String { hudText(program: program, live: live) }

    public func hudText(program: GimbalProgram, live: GimbalWaypoint?) -> String {
        Self.formatDebug(program: program, live: live, row: live.flatMap { readout(live: $0) } ?? lastReadout)
    }

    public static func formatHud(_ row: Readout) -> String {
        formatDebug(program: GimbalProgram(), live: nil, row: row)
    }

    public static func formatDebug(program: GimbalProgram, live: GimbalWaypoint?, row: Readout?) -> String {
        func xy(_ name: String, _ point: GimbalWaypoint?) -> String {
            guard let point else { return "\(name)  --" }
            return String(format: "%@  X%+7.1f  Y%+7.1f", name, point.yawDeg, point.pitchDeg)
        }
        var lines = [xy("A", program.a), xy("B", program.b), xy("C", program.c), xy("now", live)]
        if let row {
            lines.append("\(row.label)  \(row.phase)")
            lines.append(String(format: "set %4.1fs  t %5.2fs", row.setDuration, row.elapsed))
            lines.append(String(format: "tgt  X%+7.1f  Y%+7.1f", row.targetYaw, row.targetPitch))
            lines.append(String(format: "rem %5.1f°", row.remainingDeg))
        }
        return lines.joined(separator: "\n")
    }

    public static func angularDistance(_ a: GimbalWaypoint, _ b: GimbalWaypoint) -> Double {
        hypot(b.yawDeg - a.yawDeg, pitchDelta(from: a, to: b))
    }

    public static func lerp(_ a: GimbalWaypoint, _ b: GimbalWaypoint, u: Double) -> GimbalWaypoint {
        let t = min(max(u, 0), 1)
        return GimbalWaypoint(yawDeg: a.yawDeg + (b.yawDeg - a.yawDeg) * t,
            pitchDeg: a.pitchDeg + (b.pitchDeg - a.pitchDeg) * t, zoom: a.zoom + (b.zoom - a.zoom) * t,
            nativePitchDeg: a.nativePitchDeg.flatMap { start in
                b.nativePitchDeg.map { _ in wrapAngle(start + pitchDelta(from: a, to: b) * t) }
            })
    }

    public static func wrapAngle(_ degrees: Double) -> Double {
        let remainder = (degrees + 180).truncatingRemainder(dividingBy: 360)
        return (remainder < 0 ? remainder + 360 : remainder) - 180
    }

    public static func pitchDelta(from: GimbalWaypoint, to: GimbalWaypoint) -> Double {
        if let start = from.nativePitchDeg, let end = to.nativePitchDeg {
            return wrapAngle(end - start)
        }
        return to.pitchDeg - from.pitchDeg
    }


}

/// One gimbal axis: dead-reckoned pose from the throw we streamed, corrected
/// by each fresh `0x04/0x05` packet against the model **as it was
/// `telemetryLag` ago** (so the correction does not lean on the rate map),
/// plus a learned gain `trim` from telemetry vs modelled displacement.
/// Frozen telemetry is ignored. HeadTrack's look-at loop.
public struct GimbalAxisObserver: Equatable, Sendable {
    /// Fraction of the lag-aligned innovation adopted per fresh packet.
    public static let innovationBlend = 0.35
    /// Unchanged-packet bleed time constant (HeadTrack's 0.2/tick at 25 Hz).
    public static let stableTau: TimeInterval = 0.18
    /// Gain-trim learning rate per fresh packet pair.
    public static let trimBlend = 0.3
    public static let trimRange = 0.5...2.0
    /// Minimum modelled / seen displacement between packets to learn from.
    public static let trimMinModelDeg = 0.3
    public static let trimMinLiveDeg = 0.1

    private struct Sample: Equatable, Sendable {
        var t: TimeInterval
        var model: Double
    }

    private struct Fresh: Equatable, Sendable {
        var t: TimeInterval
        var live: Double
        var past: Double
    }

    public var model = 0.0
    public var lastThrow = 0.0
    public var lastSeenTenth: Int16?
    public var lastSeenDeg = 0.0
    public var stableFor: TimeInterval = 0
    public var movedSinceFresh = 0.0
    public var dead = false
    /// Time since the throw went to zero. Past `HeadTrack.telemetryLag` a
    /// fresh packet is adopted outright so letters do not drift at rest.
    public var restingFor: TimeInterval = .infinity
    public var rateMap = GimbalRateMap.pocketFast
    /// Learned multiplier on `rateMap`: telemetry moved `trim` × what the map said.
    public var trim = 1.0
    public var prevTarget: Double?
    public var rate = 0.0
    /// Feed-forward rate: min-magnitude of instant and EMA, zero on a sign
    /// split — collapses the moment the head stops so the EMA tail cannot
    /// push past the look.
    public var ffRate = 0.0
    private var time: TimeInterval = 0
    private var history: [Sample] = []
    private var prevFresh: Fresh?

    public init() {}

    /// deg/s the model integrates for a throw.
    public func modelRate(forThrow t: Double) -> Double { rateMap.rate(forThrow: t) * trim }

    public mutating func seed(_ deg: Double) {
        let map = rateMap
        let learned = trim
        self = GimbalAxisObserver()
        rateMap = map
        trim = learned
        model = deg
        lastSeenDeg = deg
    }

    /// Dead-reckon with the throw we actually streamed last tick.
    public mutating func integrate(dt: TimeInterval) {
        guard dt > 0 else { return }
        let step = modelRate(forThrow: lastThrow) * dt
        time += dt
        model += step
        movedSinceFresh += abs(step)
        restingFor = lastThrow == 0 ? restingFor + dt : 0
        history.append(Sample(t: time, model: model))
        while let first = history.first, first.t < time - 3 * HeadTrack.telemetryLag {
            history.removeFirst()
        }
    }

    /// Model as it was at `t` (linear between samples).
    private func modelAt(_ t: TimeInterval) -> Double {
        guard let first = history.first else { return model }
        if t <= first.t { return first.model }
        for i in 1..<history.count where history[i].t >= t {
            let a = history[i - 1]
            let b = history[i]
            let span = b.t - a.t
            let u = span > 0 ? (t - a.t) / span : 1
            return a.model + (b.model - a.model) * u
        }
        return model
    }

    /// `deg` defaults to `tenth / 10`; the pose observer passes unwrapped yaw.
    /// A fresh packet is an observation of the pose `telemetryLag` ago and is
    /// blended once. An unchanged packet after `stableAfter` is a slow or
    /// still head: bleed toward it on a time constant, whatever the call
    /// rate (HeadTrack calls per tick, the pose observer per packet).
    /// Frozen = the model moved `telemetryDeadDeg` with no change.
    public mutating func observe(tenth: Int16?, deg: Double? = nil, dt: TimeInterval) {
        guard let tenth else { return }
        let live = deg ?? HeadTrack.tenthToDeg(tenth)
        if tenth != lastSeenTenth {
            lastSeenTenth = tenth
            lastSeenDeg = live
            stableFor = 0
            dead = false
            movedSinceFresh = 0
            if restingFor > HeadTrack.telemetryLag {
                model = live
                history.removeAll()
                prevFresh = nil
                return
            }
            // Stale by `telemetryLag`: compare with the model as it was then,
            // learn the gain from the displacement since the previous fresh
            // packet, and bleed the innovation into the model now.
            let past = modelAt(time - HeadTrack.telemetryLag)
            if let p = prevFresh, time - p.t <= HeadTrack.telemetryLag {
                let dLive = HeadTrack.wrapDeg(live - p.live)
                let dModel = past - p.past
                if abs(dModel) >= Self.trimMinModelDeg, abs(dLive) >= Self.trimMinLiveDeg {
                    let r = dLive / dModel
                    if r > 0 {
                        let want = min(
                            max(trim * r, Self.trimRange.lowerBound), Self.trimRange.upperBound)
                        trim += Self.trimBlend * (want - trim)
                    }
                }
            }
            prevFresh = Fresh(t: time, live: live, past: past)
            model += Self.innovationBlend * HeadTrack.wrapDeg(live - past)
            return
        }
        stableFor += dt
        if movedSinceFresh >= HeadTrack.telemetryDeadDeg { dead = true }
        guard !dead, stableFor >= HeadTrack.stableAfter else { return }
        let alpha = 1 - exp(-max(dt, 0) / Self.stableTau)
        model += alpha * HeadTrack.wrapDeg(live - model)
    }

    public mutating func noteTarget(_ target: Double, dt: TimeInterval) {
        defer { prevTarget = target }
        guard dt > 0, let prev = prevTarget else { return }
        let instant = HeadTrack.wrapDeg(target - prev) / dt
        rate += HeadTrack.targetRateSmooth * (instant - rate)
        ffRate = instant.sign == rate.sign ? (abs(instant) < abs(rate) ? instant : rate) : 0
    }
}

/// Project a stored yaw/pitch onto the live picture. Each waypoint is a
/// direction on the unit sphere in gimbal space; as live `0x04/0x05`
/// yaw/pitch change, that sphere rotates with the camera.
public enum GimbalWaypointOverlay {
    /// Pocket 3 is 20 mm equivalent on the full 3:2 sensor width:
    /// 2·atan(18/20) = 84°. Knob — verify with a letter on a frame-edge feature.
    public static let wideHFovDeg = 84.0
    /// Waypoint pitch is look-up positive (`GimbalStick.pitchTenthDeg`). +1
    /// draws look-up above center. Flip if a device disagrees.
    public static let pitchUpSign = 1.0

    public struct Mark: Equatable, Sendable {
        public var slot: GimbalWaypointSlot
        public var nx: Double
        public var ny: Double
        public var onScreen: Bool

        public init(slot: GimbalWaypointSlot, nx: Double, ny: Double, onScreen: Bool) {
            self.slot = slot
            self.nx = nx
            self.ny = ny
            self.onScreen = onScreen
        }
    }

    /// Digital zoom scales the image, i.e. the tangent, not the angle.
    public static func tanHalfHFov(zoom: Double) -> Double {
        tan(wideHFovDeg / 2 * .pi / 180) / max(zoom, 1)
    }

    public static func project(
        waypoint: GimbalWaypoint,
        slot: GimbalWaypointSlot,
        live: GimbalWaypoint,
        aspect: Double
    ) -> Mark {
        let tanH = tanHalfHFov(zoom: live.zoom)
        let tanV = tanH / max(aspect, 0.1)
        let dYaw = (waypoint.yawDeg - live.yawDeg) * .pi / 180
        let tp = pitchUpSign * waypoint.pitchDeg * .pi / 180
        let cp = pitchUpSign * live.pitchDeg * .pi / 180
        // Target direction with the camera yaw removed: (right, up, forward).
        let x = sin(dYaw) * cos(tp)
        let y = sin(tp)
        let z = cos(dYaw) * cos(tp)
        // Remove the camera pitch (rotation about the right axis).
        let yc = y * cos(cp) - z * sin(cp)
        let zc = y * sin(cp) + z * cos(cp)
        guard zc > 1e-6 else {
            return Mark(slot: slot, nx: x >= 0 ? 1 : 0, ny: 0.5, onScreen: false)
        }
        let nx = 0.5 + (x / zc) / (2 * tanH)
        let ny = 0.5 - (yc / zc) / (2 * tanV)
        let onScreen = nx >= 0 && nx <= 1 && ny >= 0 && ny <= 1
        return Mark(
            slot: slot,
            nx: min(max(nx, 0), 1),
            ny: min(max(ny, 0), 1),
            onScreen: onScreen)
    }

    public static func marks(
        program: GimbalProgram, live: GimbalWaypoint, aspect: Double
    ) -> [Mark] {
        GimbalWaypointSlot.allCases.compactMap { slot in
            guard let point = program[slot] else { return nil }
            return project(waypoint: point, slot: slot, live: live, aspect: aspect)
        }
    }
}
