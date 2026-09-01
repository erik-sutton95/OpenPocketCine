import Foundation

/// Leave camera playback and bring live view back — Mimo's "Back to live view".
///
/// `0x02/0x0c` `01 01 00 00` exits playback. Enable (`0x09/0xa8`) while still in
/// playback ACKs `E0`/`D6` and produces no video. Keep exiting until the
/// `0x02/0x80` playback bit clears, then enable.
public enum MediaLiveResume: Sendable {
    public static let maxExitAttempts = 8

    public enum Action: Equatable, Sendable {
        case exitPlayback
        case enableLiveView
        case done
    }

    /// One tick of the post-media resume loop.
    public static func action(
        attempt: Int,
        inPlayback: Bool,
        exitAcknowledged: Bool,
        pictureFresh: Bool
    ) -> Action {
        if pictureFresh, !inPlayback { return .done }
        if inPlayback || !exitAcknowledged {
            return .exitPlayback
        }
        if attempt > maxExitAttempts {
            return pictureFresh ? .done : .enableLiveView
        }
        return .enableLiveView
    }

    /// Keepalive while the operator is already on live view: camera still
    /// showing "Playback in progress".
    public static func strayPlaybackAction(browsing: Bool, inPlayback: Bool) -> Action? {
        guard !browsing, inPlayback else { return nil }
        return .exitPlayback
    }
}
