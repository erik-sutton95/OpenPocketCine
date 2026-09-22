import Foundation

/// Camera-owned continuous zoom. Positions are used only to prepare the take.
public enum NativeProgramZoomCommand: Equatable, Sendable {
    case position(Double)
    case rate(speed: UInt8, increasing: Bool)
    case stop

    public var frame: Duml.Frame {
        switch self {
        case .position(let factor): return Commands.setZoom(factor: factor)
        case .rate(let speed, let increasing): return Commands.setZoomRate(speed, increasing: increasing)
        case .stop: return Commands.setZoomStop()
        }
    }
}

public struct NativeProgramZoomDemand: Equatable, Sendable {
    public var command: NativeProgramZoomCommand
    public var destination: Double
    public var failureReason: String?
    public var nextChange: TimeInterval

    public init(command: NativeProgramZoomCommand, destination: Double, failureReason: String? = nil,
        nextChange: TimeInterval = .infinity) {
        self.command = command
        self.destination = destination
        self.failureReason = failureReason
        self.nextChange = nextChange
    }
}

/// Pocket 4 Pro's measured slowest logarithmic zoom rate; higher native gears
/// are integer multiples. Keep one gear for the entire moving portion of a leg:
/// changing gears produces a visible velocity step, even with continuous zoom.
public enum NativeProgramZoom {
    public static let slowestLogRate = 0.208
    public static let slowestSpeed: UInt8 = 72
    public static let fastestSpeed: UInt8 = 78

    public static func minimumDuration(from: Double, to: Double) -> TimeInterval {
        guard from.isFinite, to.isFinite, from >= 1, to >= 1 else { return .infinity }
        return abs(log(to / from)) / (7 * slowestLogRate)
    }

    public static func timingFailure(from: Double, to: Double, duration: TimeInterval) -> String? {
        guard abs(from - to) > 1e-6 else { return nil }
        if duration + 1e-9 < minimumDuration(from: from, to: to) {
            return "Increase the move duration for this zoom range"
        }
        if abs(log(to / from)) / slowestLogRate < GimbalProgramZoom.interval - 1e-9
            || duration < GimbalProgramZoom.interval - 1e-9 {
            return "Increase the zoom difference between points"
        }
        return nil
    }

    public static func demand(from: Double, to: Double, duration: TimeInterval, elapsed: TimeInterval)
        -> NativeProgramZoomDemand
    {
        var stopped = NativeProgramZoomDemand(command: .stop, destination: to,
            nextChange: max(0, duration - elapsed))
        stopped.failureReason = timingFailure(from: from, to: to, duration: duration)
        guard from.isFinite, to.isFinite, duration.isFinite, elapsed.isFinite,
            from >= 1, to >= 1, duration > 0, elapsed >= 0, elapsed < duration,
            abs(from - to) > 1e-6, stopped.failureReason == nil
        else { return stopped }
        let distance = abs(log(to / from))
        // Use the slowest gear that can reach the waypoint by its deadline.
        // The waiting interval preserves the requested gimbal duration without
        // a mid-zoom gear change, position correction or start/stop modulation.
        let gear = min(7, max(1, Int(ceil(distance / (slowestLogRate * duration) - 1e-9))))
        let movingDuration = distance / (Double(gear) * slowestLogRate)
        guard movingDuration >= GimbalProgramZoom.interval - 1e-9 else {
            stopped.failureReason = "Increase the zoom difference between points"
            return stopped
        }
        let delay = max(0, duration - movingDuration)
        if elapsed < delay - 1e-9 {
            stopped.nextChange = delay - elapsed
            return stopped
        }
        return .init(command: .rate(speed: UInt8(71 + gear), increasing: to > from),
            destination: to, nextChange: duration - elapsed)
    }
}
