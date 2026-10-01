import Foundation

/// The DJI live-view enable (`0x09/0xa8`) decision on top of the shared parameter-set policy
/// (OpenCineMedia `EncoderPresentPath`).
extension EncoderPresentPath {
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
}
