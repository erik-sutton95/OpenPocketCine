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
/// are integer multiples. Blend adjacent gears once through the middle of a leg,
/// avoiding both repeated position targets and stop/start pulse modulation.
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
        let movingDuration = min(duration, distance / slowestLogRate)
        let averageGear = distance / (slowestLogRate * movingDuration)
        let low = min(7, max(1, Int(floor(averageGear + 1e-9))))
        var fastDuration = low == 7 ? 0 : max(0, distance / slowestLogRate - Double(low) * movingDuration)
        var slowDuration = movingDuration - fastDuration
        let minimum = GimbalProgramZoom.interval
        var segments: [(gear: Int, duration: TimeInterval)] = []
        if fastDuration <= 1e-9 {
            segments = [(low, movingDuration)]
        } else {
            // Keep every rate span at least one dispatch interval. A very short
            // fast middle borrows time from the slow span and delays the start;
            // integrated log distance and the waypoint deadline stay unchanged.
            if fastDuration < minimum {
                fastDuration = minimum
                slowDuration = (distance / slowestLogRate - Double(low + 1) * fastDuration) / Double(low)
            }
            if slowDuration < minimum {
                segments = [(low + 1, distance / (Double(low + 1) * slowestLogRate))]
            } else if slowDuration < 2 * minimum {
                segments = [(low, slowDuration), (low + 1, fastDuration)]
            } else {
                segments = [(low, slowDuration / 2), (low + 1, fastDuration), (low, slowDuration / 2)]
            }
        }
        let activeDuration = segments.reduce(0) { $0 + $1.duration }
        guard segments.allSatisfy({ $0.duration >= minimum - 1e-9 }) else {
            stopped.failureReason = "Increase the zoom difference between points"
            return stopped
        }
        var boundary = max(0, duration - activeDuration)
        if elapsed < boundary - 1e-9 {
            stopped.nextChange = boundary - elapsed
            return stopped
        }
        for segment in segments {
            boundary += segment.duration
            if elapsed < boundary - 1e-9 {
                return .init(command: .rate(speed: UInt8(71 + segment.gear), increasing: to > from),
                    destination: to, nextChange: boundary - elapsed)
            }
        }
        return stopped
    }
}
