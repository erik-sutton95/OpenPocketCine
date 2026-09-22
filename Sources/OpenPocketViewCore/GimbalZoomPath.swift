import Foundation

/// Zoom visits each saved amount even when the angular path rounds B.
struct GimbalZoomPath: Equatable, Sendable {
    struct Leg: Equatable, Sendable {
        var from: Double
        var to: Double
        var duration: TimeInterval
    }
    var legs: [Leg]
    var duration: TimeInterval { legs.reduce(0) { $0 + $1.duration } }
    var end: Double { legs.last?.to ?? 1 }

    init(program: GimbalProgram) {
        legs = []
        if let a = program.a, let b = program.b {
            legs.append(Leg(from: a.zoom, to: b.zoom, duration: program.durationAB))
            if let c = program.c {
                legs.append(Leg(from: b.zoom, to: c.zoom, duration: program.durationBC))
            }
        }
    }

    func position(at time: TimeInterval, lookAhead: TimeInterval = 0.05) -> Double {
        var time = max(0, time)
        for leg in legs {
            if time < leg.duration - 1e-9 {
                let fraction = min(1, (time + lookAhead) / leg.duration)
                return leg.from + (leg.to - leg.from) * fraction
            }
            time -= leg.duration
        }
        return end
    }

    func nativeDemand(at time: TimeInterval) -> NativeProgramZoomDemand {
        var remaining = max(0, time)
        for leg in legs {
            if remaining < leg.duration - 1e-9 {
                return NativeProgramZoom.demand(from: leg.from, to: leg.to,
                    duration: leg.duration, elapsed: remaining)
            }
            remaining = max(0, remaining - leg.duration)
        }
        return .init(command: .track(end), destination: end)
    }

    func remaining(after time: TimeInterval, from zoom: Double, quantized: Bool) -> Self {
        var result = self
        var consumed = max(0, time)
        while result.legs.count > 1, consumed >= result.legs[0].duration - 1e-9 {
            consumed -= result.legs.removeFirst().duration
        }
        guard !result.legs.isEmpty else { return result }
        let remaining = max(0, result.legs[0].duration - consumed)
        result.legs[0].duration = quantized ? max(0.1, ceil((remaining - 1e-9) * 10) / 10) : remaining
        let total = result.duration
        if total < 0.1 { result.legs[0].duration += 0.1 - total }
        result.legs[0].from = zoom
        return result
    }
}
