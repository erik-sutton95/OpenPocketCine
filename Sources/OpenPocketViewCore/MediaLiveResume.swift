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

    /// Leftover GOP packets are not a live picture. Resume is done only when a
    /// frame presented after the resume started.
    public static func isPictureFresh(lastPresentedAt: Date?, since: Date) -> Bool {
        guard let presented = lastPresentedAt else { return false }
        return presented >= since
    }
}

/// What to do after `0x02/0x0c` enter-playback. Newest list page needs no playback.
public struct MediaBrowsePolicy: Equatable, Sendable {
    public var listNewestPage: Bool
    public var listOlderPages: Bool
    public var keepBrowsing: Bool

    public init(listNewestPage: Bool, listOlderPages: Bool, keepBrowsing: Bool) {
        self.listNewestPage = listNewestPage
        self.listOlderPages = listOlderPages
        self.keepBrowsing = keepBrowsing
    }

    /// Newest `0x00/0x26` page needs no playback. Keep the browse flag so a
    /// failed `0x02/0x0c` (Pocket 3 E0 after a take) cannot arm stray exit.
    public static func afterEnterPlayback(_ entered: Bool) -> MediaBrowsePolicy {
        MediaBrowsePolicy(
            listNewestPage: true, listOlderPages: entered, keepBrowsing: true)
    }
}
