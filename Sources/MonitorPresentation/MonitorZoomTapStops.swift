import Foundation

/// The adapter assigns supported stops to gestures. Continuous zoom and camera
/// command ownership are deliberately outside this presentation policy.
public struct MonitorZoomTapStops: Equatable, Sendable {
    public let singleTap: [Double]
    public let doubleTap: [Double]

    public init(supported: [Double], extended: [Double] = []) {
        let stops = Array(Set(supported.filter { $0.isFinite && $0 > 0 })).sorted()
        let extendedStops = stops.filter { extended.contains($0) }
        doubleTap = extendedStops
        singleTap = stops.filter { !extendedStops.contains($0) }
    }

    public func next(from current: Double, extended: Bool = false) -> Double? {
        let stops = extended ? doubleTap : singleTap
        guard let first = stops.first else { return nil }
        guard current.isFinite else { return first }
        // A readback within half a tenth of a displayed stop is at that stop;
        // an intermediate continuous-zoom value advances to the next one.
        return stops.first { $0 > current + 0.05 } ?? first
    }
}
