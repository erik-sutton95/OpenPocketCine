import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct MediaLiveResumeTests {
    /// Exit until playback clears, enable only after, done on a live picture.
    /// An exhausted exit budget never enables: 0x09/0xa8 in gallery ACKs E0.
    @Test(arguments: [
        (1, true, false, false, MediaLiveResume.Action.exitPlayback),
        (2, true, true, false, .exitPlayback),
        (2, false, true, false, .enableLiveView),
        (3, false, true, true, .done),
        (MediaLiveResume.maxExitAttempts + 1, true, false, false, .exhausted),
    ])
    func resumeStep(
        attempt: Int, inPlayback: Bool, exitAcknowledged: Bool, pictureFresh: Bool,
        expected: MediaLiveResume.Action
    ) {
        #expect(
            MediaLiveResume.action(
                attempt: attempt, inPlayback: inPlayback, exitAcknowledged: exitAcknowledged,
                pictureFresh: pictureFresh) == expected)
    }

    @Test func successfulEnableIsNotRepeatedWhileFirstPictureIsPending() {
        var enableSent = false
        var enables = 0
        for _ in 0..<100 {
            let action = MediaLiveResume.action(
                attempt: 2, inPlayback: false, exitAcknowledged: true,
                pictureFresh: false, enableSent: enableSent)
            if action == .enableLiveView {
                enables += 1
                enableSent = true
            } else {
                #expect(action == .waitForPicture)
            }
        }
        #expect(enables == 1)
        #expect(
            MediaLiveResume.action(
                attempt: 2, inPlayback: false, exitAcknowledged: true,
                pictureFresh: false, enableSent: true, deadlineExpired: true) == .exhausted)
    }

    @Test func mediaEntryAndQuickReturnBothRetireThePreviousPictureOwner() {
        #expect(
            MediaLiveResume.isCurrentPictureOwner(
                generation: 2, currentGeneration: 2, browsing: false))
        #expect(
            !MediaLiveResume.isCurrentPictureOwner(
                generation: 2, currentGeneration: 3, browsing: true))
        #expect(
            !MediaLiveResume.isCurrentPictureOwner(
                generation: 2, currentGeneration: 4, browsing: false))
        #expect(
            MediaLiveResume.isCurrentPictureOwner(
                generation: 4, currentGeneration: 4, browsing: false))
    }

    @Test func strayPlaybackOnLiveViewSendsExit() {
        #expect(
            MediaLiveResume.strayPlaybackAction(browsing: false, inPlayback: true)
                == .exitPlayback)
        #expect(MediaLiveResume.strayPlaybackAction(browsing: true, inPlayback: true) == nil)
        #expect(MediaLiveResume.strayPlaybackAction(browsing: false, inPlayback: false) == nil)
    }

    @Test func newestPageListsWhenEnterPlaybackFails() {
        // Handbook: newest `0x00/0x26` needs no playback. Pocket 3 often ACKs
        // `0x02/0x0c` with E0 after a take; aborting the browse drops the new
        // clip and lets strayPlaybackAction exit gallery while the library is open.
        let failed = MediaBrowsePolicy.afterEnterPlayback(false)
        #expect(failed.listNewestPage)
        #expect(!failed.listOlderPages)
        #expect(failed.keepBrowsing)
        let entered = MediaBrowsePolicy.afterEnterPlayback(true)
        #expect(entered.listNewestPage)
        #expect(entered.listOlderPages)
        #expect(entered.keepBrowsing)
    }
}
