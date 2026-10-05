import Foundation

// The link-health scorer and `LinkSignalBars` are shared from OpenCineMedia.

/// Pocket mapping onto OpenZCine's FPS chip labels + `CameraLinkHealthScorer` phase.
///
/// SoftAP HEVC live view is 1280×720 at ~25 fps (`docs/protocol-notes.md`). That is the
/// delivery target for bars — not `CameraStatus.fps`, which is the recording format already
/// shown on the Rec chip. There is no SoftAP RSSI on the bus (and iOS cannot read it).
public enum LiveViewLink {
    public static let targetFPS: Double = 25

    public static func cameraLinkPhase(
        connection: ConnectionPhase,
        recovering: Bool,
        measuredFPS: Double
    ) -> CameraLinkPhase {
        if case .failed = connection { return .disconnected }
        if measuredFPS > 0 { return recovering ? .recovering : .streaming }
        switch connection {
        case .idle: return .disconnected
        case .live: return .connectedIdle
        default: return .connecting
        }
    }

    public static func fpsChipLabel(
        connection: ConnectionPhase,
        recovering: Bool,
        formattedFPS: String,
        measuredFPS: Double
    ) -> String {
        if case .failed = connection { return "FAIL" }
        if recovering { return "RECOV" }
        if measuredFPS > 0 { return formattedFPS }
        switch connection {
        case .idle: return "—"
        default: return "LINK"
        }
    }
}

/// Cover the feed well until a **rolling** picture exists.
/// After that, a stall, AF-C hunt, or in-flight recover keeps the last frame —
/// putting the waiting plate back is the mid-session “Waiting for live-view” hang.
public enum LiveFeedWarmup {
    /// ~⅓ s at 25 fps. Two leftover GOP frames must not lift the plate.
    public static let minimumRollingIntervals = 8

    public static func isWarming(
        hasPresentedPicture: Bool,
        measuredFPS: Double = 0,
        rollingIntervals: Int = 0,
        recovering: Bool = false,
        secondsSinceLastPresented: TimeInterval? = nil,
        stall: TimeInterval = FeedPresentPolicy.freezeThreshold
    ) -> Bool {
        _ = recovering
        _ = secondsSinceLastPresented
        _ = stall
        if !hasPresentedPicture { return true }
        if measuredFPS <= 0 { return true }
        if rollingIntervals < minimumRollingIntervals { return true }
        return false
    }
}
