import Foundation

/// Whether the live encoder restarted with a new GOP shape (Pocket screen flip /
/// vertical mode sends new VPS/SPS/PPS). The present path must rebuild — keeping
/// the old VT session or sample-buffer layer format is a black feed until reconnect.
public enum EncoderPresentPath {
    public static func parameterSetsChanged(
        hadFormat: Bool,
        previousVPS: [UInt8]?,
        previousSPS: [UInt8]?,
        previousPPS: [UInt8]?,
        nextVPS: [UInt8]?,
        nextSPS: [UInt8]?,
        nextPPS: [UInt8]?
    ) -> Bool {
        guard hadFormat else { return false }
        return previousVPS != nextVPS || previousSPS != nextSPS || previousPPS != nextPPS
    }

    /// Aspect for the feed well. Unknown / degenerate rasters keep landscape 16:9.
    public static func feedAspect(width: Int, height: Int, fallback: Double = 16.0 / 9.0) -> Double
    {
        guard width > 1, height > 1 else { return fallback }
        return Double(width) / Double(height)
    }

    /// Pocket screen flip: the raster is taller than it is wide.
    public static func isVertical(width: Int, height: Int) -> Bool {
        width > 1 && height > 1 && height > width
    }

    /// New VPS/SPS/PPS already means the camera cut a GOP. A second
    /// `0x09/0xa8` on an AU that carries the IDR cuts it again and can
    /// leave the hold waiting through an AF-C hunt.
    public static func shouldRequestEnableAfterParameterChange(accessUnitHasIDR: Bool) -> Bool {
        !accessUnitHasIDR
    }
}
