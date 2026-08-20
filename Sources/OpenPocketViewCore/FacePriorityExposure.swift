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
    /// Less than one third-stop: hold.
    public static let deadbandStops = 1.0 / 3.0

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
        let deltaThirds = Int((-stops * 3).rounded())
        if deltaThirds == 0 { return nil }
        let next = EvComp(thirds: current.thirds + deltaThirds)
        return next == current ? nil : next
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
