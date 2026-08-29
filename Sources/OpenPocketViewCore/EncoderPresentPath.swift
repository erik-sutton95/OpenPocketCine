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
    ///
    /// A recording-format SET on a live socket also lands new sets. Enabling
    /// then cuts the GOP (physical #148: 4K/1080 hops → `encoder format change`
    /// → Reconnecting). Skip while UDP video is alive, and debounce to
    /// `FeedWatchdog.escalateAfter`.
    public static func shouldRequestEnableAfterParameterChange(
        accessUnitHasIDR: Bool,
        udpReceiveAlive: Bool = false,
        secondsSinceLastEnable: TimeInterval? = nil
    ) -> Bool {
        if accessUnitHasIDR { return false }
        if udpReceiveAlive { return false }
        if let since = secondsSinceLastEnable, since < FeedWatchdog.escalateAfter {
            return false
        }
        return true
    }

    /// Tear VT / MediaCodec only when the raster flipped (Pocket screen flip)
    /// or this AU already cut a GOP. Zoom / FORMAT / color hops on a live 720p
    /// GOP send new VPS/SPS without an IDR. Tearing then holding IDR while
    /// skipping `0x09/0xa8` (UDP still alive) blacks the well — HUD and gimbal
    /// stay up because `0x01` and the stick never left 9004.
    public static func shouldRebuildDecoderAfterParameterChange(
        pictureSizeChanged: Bool,
        accessUnitHasIDR: Bool
    ) -> Bool {
        pictureSizeChanged || accessUnitHasIDR
    }

    /// IDR hold is for a decoder rebuild that cannot join mid-GOP. Same-raster
    /// SPS (zoom) must keep presenting P-frames.
    public static func shouldBeginIDRHoldAfterParameterChange(
        pictureSizeChanged: Bool,
        accessUnitHasIDR: Bool
    ) -> Bool {
        if accessUnitHasIDR { return false }
        return pictureSizeChanged
    }
}
