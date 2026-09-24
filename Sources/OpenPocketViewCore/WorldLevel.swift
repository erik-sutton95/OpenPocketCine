import Foundation

/// Camera attitude against gravity from the `0x04/0x05` push.
///
/// `@24…@39` are float32 LE `x, w, y, z` of a unit quaternion that maps world
/// to camera (camera x forward, y up; world gravity −y). Fit on 1,014 captured
/// front/selfie frames: tilt matches display pitch `−@20` (p50 0.02°, p95 0.46°)
/// and roll stays within 1.1° while the gimbal holds the horizon. Heading is
/// free (IMU) and unused. Roll sign is not yet confirmed on a rolled handle.
public enum WorldLevel {
    public static func attitude(_ payload: [UInt8]) -> HeadTrack.Quat? {
        guard payload.count >= 40 else { return nil }
        func f32(_ o: Int) -> Double {
            let bits =
                UInt32(payload[o]) | UInt32(payload[o + 1]) << 8
                | UInt32(payload[o + 2]) << 16 | UInt32(payload[o + 3]) << 24
            return Double(Float(bitPattern: bits))
        }
        let q = HeadTrack.Quat(w: f32(28), x: f32(24), y: f32(32), z: f32(36))
        let norm = (q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z).squareRoot()
        guard norm.isFinite, abs(norm - 1) <= 1e-3 else { return nil }
        return q
    }

    /// Unit gravity (down) in the camera frame.
    public static func gravity(_ q: HeadTrack.Quat) -> (x: Double, y: Double, z: Double) {
        q.rotate((0, -1, 0))
    }

    static func deg(_ r: Double) -> Double { r * 180 / .pi }
    static func asinDeg(_ v: Double) -> Double { deg(asin(min(1, max(-1, v)))) }
}

/// Smoothed world level for the LEVEL assist and the Double-tap Level snap.
public struct LevelReading: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case unavailable
        /// Picture roll and look-up tilt from the horizon, degrees.
        case gauges(rollDeg: Double, tiltDeg: Double)
        /// Offset of the lens from plumb in picture axes (x right, y up), degrees.
        case bubble(xDeg: Double, yDeg: Double)
    }

    public static let staleAfter: TimeInterval = 1.0
    /// OpenZCine `levelAngleMinInterval` (~10 Hz), with room for push jitter.
    public static let minInterval: TimeInterval = 0.08
    public static let smoothing = 0.3
    public static let bubbleEnterDeg = 65.0
    public static let bubbleExitDeg = 60.0

    private var g: (x: Double, y: Double, z: Double)?
    private var acceptedAt: TimeInterval = -.infinity
    private var bubble = false

    public init() {}

    public static func == (a: Self, b: Self) -> Bool {
        a.acceptedAt == b.acceptedAt && a.bubble == b.bubble && a.g?.x == b.g?.x
            && a.g?.y == b.g?.y && a.g?.z == b.g?.z
    }

    public mutating func ingest(_ payload: [UInt8], now: TimeInterval) {
        guard let q = WorldLevel.attitude(payload), now.isFinite else { return }
        let sample = WorldLevel.gravity(q)
        // After a gap, start over: pre-gap gravity must not bleed into a new pose.
        if now - acceptedAt > Self.staleAfter {
            g = nil
            bubble = false
        }
        if let prev = g {
            guard now - acceptedAt >= Self.minInterval else { return }
            let k = Self.smoothing
            let x = prev.x * (1 - k) + sample.x * k
            let y = prev.y * (1 - k) + sample.y * k
            let z = prev.z * (1 - k) + sample.z * k
            let n = (x * x + y * y + z * z).squareRoot()
            g = n > 0 ? (x / n, y / n, z / n) : sample
        } else {
            g = sample
        }
        acceptedAt = now
        let tilt = abs(Self.tilt(g!))
        bubble = bubble ? tilt >= Self.bubbleExitDeg : tilt >= Self.bubbleEnterDeg
    }

    /// Smoothed look-up tilt, or `nil` when stale.
    public func tiltDeg(now: TimeInterval) -> Double? {
        guard let g, now - acceptedAt <= Self.staleAfter else { return nil }
        return Self.tilt(g)
    }

    /// Signed pitch-plane angle, look-up positive, unfolded past ±90° (lens past
    /// nadir reads −92, not −88). The snap plans and judges on this; `nil` when stale.
    public func pitchDeg(now: TimeInterval) -> Double? {
        guard let g, now - acceptedAt <= Self.staleAfter else { return nil }
        return WorldLevel.deg(atan2(-g.x, -g.y))
    }

    /// `viewFlip`: TT180 XOR MIRROR (picture-relative, like the stick), so readings follow the picture.
    public func mode(now: TimeInterval, viewFlip: Bool) -> Mode {
        guard let g, now - acceptedAt <= Self.staleAfter else { return .unavailable }
        let side = viewFlip ? -1.0 : 1.0
        if bubble {
            return .bubble(xDeg: side * -WorldLevel.asinDeg(g.z), yDeg: -WorldLevel.asinDeg(g.y))
        }
        return .gauges(rollDeg: side * WorldLevel.deg(atan2(g.z, -g.y)), tiltDeg: Self.tilt(g))
    }

    static func tilt(_ g: (x: Double, y: Double, z: Double)) -> Double {
        -WorldLevel.asinDeg(g.x)
    }
}

public enum WorldLevelTarget: Sendable, Equatable {
    case horizon, plumbDown, plumbUp

    public var tiltDeg: Double {
        switch self {
        case .horizon: 0
        case .plumbDown: -90
        case .plumbUp: 90
        }
    }

    public static func nearest(tiltDeg: Double) -> Self {
        if abs(tiltDeg) < 45 { return .horizon }
        return tiltDeg < 0 ? .plumbDown : .plumbUp
    }

    public var successNote: String {
        switch self {
        case .horizon: "Leveled to world"
        case .plumbDown: "Leveled top-down"
        case .plumbUp: "Leveled straight up"
        }
    }
}

/// One-shot `0x04/0x14` move to the nearest world target, judged on the
/// smoothed world tilt. Roll is not commanded (mode `05` ignores it).
public struct WorldLevelSnap: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case pending
        case arrived
        /// Judged more than `LevelReading.staleAfter` past the deadline (attitude
        /// stopped mid-move): drop silently, never a late toast or stop.
        case expired
        /// Remaining error to 0.1°, or `nil` when the reading went stale.
        case failed(errorDeg: Double?)
    }

    public static let toleranceDeg = 0.5
    public static let settleGrace: TimeInterval = 1.5
    public static let noLevelData = "No level data"
    public static let fpvRollNote = " · roll follows the handle in FPV"
    /// No live native pitch, or yaw in the unreachable pan gap.
    public static let unreachableNote = "Couldn't level from this pose"

    public let target: WorldLevelTarget
    public let deadline: TimeInterval

    /// 0.1 s per 2°, clamped 0.5…3.0 s on the 0.1 s wire grid.
    public static func duration(distanceDeg: Double) -> TimeInterval {
        min(3.0, max(0.5, (abs(distanceDeg) * 0.5).rounded() / 10))
    }

    /// Native pitch moves opposite to look-up tilt (`native = 180 − tilt`), so
    /// the live native reading plus the world error gives the target.
    public static func plan(tiltDeg: Double, pose: GimbalWaypoint, now: TimeInterval)
        -> (snap: WorldLevelSnap, frame: Duml.Frame)?
    {
        guard tiltDeg.isFinite, let native = pose.nativePitchDeg, native.isFinite else { return nil }
        let target = WorldLevelTarget.nearest(tiltDeg: tiltDeg)
        let error = target.tiltDeg - tiltDeg
        var goal = native - error
        while goal > 180 { goal -= 360 }
        while goal < -180 { goal += 360 }
        let duration = duration(distanceDeg: error)
        guard
            let frame = Commands.gimbalTimedTarget(
                yawDeg: pose.yawDeg, nativePitchDeg: (goal * 10).rounded() / 10,
                duration: duration)
        else { return nil }
        return (WorldLevelSnap(target: target, deadline: now + duration + settleGrace), frame)
    }

    /// `tiltDeg` is the unfolded `LevelReading.pitchDeg`.
    public func evaluate(tiltDeg: Double?, now: TimeInterval) -> Outcome {
        if now - deadline > LevelReading.staleAfter { return .expired }
        guard let tiltDeg else { return .failed(errorDeg: nil) }
        let error = abs(tiltDeg - target.tiltDeg)
        if error <= Self.toleranceDeg { return .arrived }
        return now >= deadline ? .failed(errorDeg: (error * 10).rounded() / 10) : .pending
    }

    public static func failureNote(errorDeg: Double?) -> String {
        guard let errorDeg else { return noLevelData }
        return String(format: "Couldn't level: %.1f° off", errorDeg)
    }
}
