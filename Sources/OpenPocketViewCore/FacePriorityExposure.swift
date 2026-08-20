import Foundation

/// Auto-expo face meter. The body still takes EV thirds (`setEv`); we pick the
/// stop from Vision boxes on the encoded live tap.
///
/// Target is 18% gray (WAVE’s middle-gray line) so D-Log / D-Log2 stay honest.
/// Several faces use the median of per-face medians. No face → no write.
public enum FacePriorityExposure: Sendable {
    /// Skip a face with fewer tap samples than this.
    public static let minSamples = 8
    /// Walk the tap at the same stride WAVE uses.
    public static let sampleStride = 2
    /// Hold inside two thirds of a stop so skin noise does not hunt EV.
    public static let deadbandStops = 2.0 / 3.0
    /// One third-stop per write. Camera EV has not settled if we jump the whole error.
    public static let maxStepThirds = 1
    /// Fast third-stop writes while a face is still acquiring.
    public static let acquireDuration: TimeInterval = 2.5
    /// Spacing during `acquireDuration` after a face first appears.
    public static let acquireInterval: TimeInterval = 0.4
    /// Spacing after acquire so EV does not hunt once the face is in.
    public static let settleInterval: TimeInterval = 1.0

    /// EV write spacing. Fast for the first 2.5 s a face is in frame, then 1 s.
    public static func interval(sinceAcquire: Date?, now: Date) -> TimeInterval {
        guard let sinceAcquire else { return acquireInterval }
        if now.timeIntervalSince(sinceAcquire) < acquireDuration {
            return acquireInterval
        }
        return settleInterval
    }

    /// Median encoded luma (0…1) of pixels inside `boxes`. Nil if nothing usable.
    public static func medianEncoded(
        bytes: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        boxes: [TrackingBox],
        transfer: MonitorTransfer
    ) -> Double? {
        let weights = LiveColorScience.lumaWeights(transfer)
        var faceMedians: [Double] = []
        faceMedians.reserveCapacity(boxes.count)
        for box in boxes {
            var samples: [Double] = []
            let x0 = max(0, Int((box.minX * Double(width)).rounded(.down)))
            let y0 = max(0, Int((box.minY * Double(height)).rounded(.down)))
            let x1 = min(width, Int((box.maxX * Double(width)).rounded(.up)))
            let y1 = min(height, Int((box.maxY * Double(height)).rounded(.up)))
            guard x1 > x0, y1 > y0 else { continue }
            var y = y0
            while y < y1 {
                let rowStart = y * bytesPerRow
                var x = x0
                while x < x1 {
                    let i = rowStart + x * 4
                    if i + 2 < bytes.count {
                        let b = Double(bytes[i])
                        let g = Double(bytes[i + 1])
                        let r = Double(bytes[i + 2])
                        let luma =
                            weights.red * r + weights.green * g + weights.blue * b
                        samples.append(min(1, max(0, luma / 255)))
                    }
                    x += sampleStride
                }
                y += sampleStride
            }
            if samples.count >= minSamples, let median = median(samples) {
                faceMedians.append(median)
            }
        }
        return median(faceMedians)
    }

    /// Next EV third, or `nil` when already inside the deadband / unchanged.
    public static func nextEV(
        current: EvComp,
        encoded: Double,
        transfer: MonitorTransfer
    ) -> EvComp? {
        let stops = LiveColorScience.stops(encoded: encoded, transfer: transfer)
        guard stops.isFinite else { return nil }
        if abs(stops) < deadbandStops { return nil }
        var deltaThirds = Int((-stops * 3).rounded())
        if deltaThirds == 0 { return nil }
        deltaThirds = min(max(deltaThirds, -maxStepThirds), maxStepThirds)
        let next = EvComp(thirds: current.thirds + deltaThirds)
        return next == current ? nil : next
    }

    /// EV to write when Face Priority turns off.
    public static func restoreEV(saved: EvComp?) -> EvComp {
        saved ?? .zero
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
