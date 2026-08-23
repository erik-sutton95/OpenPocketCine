import Testing

@testable import OpenPocketViewCore

@Suite struct MediaLiveResumeTests {
    @Test func exitsUntilTheCameraLeavesPlayback() {
        #expect(
            MediaLiveResume.action(
                attempt: 1, inPlayback: true, exitAcknowledged: false, pictureFresh: false)
                == .exitPlayback)
        #expect(
            MediaLiveResume.action(
                attempt: 2, inPlayback: true, exitAcknowledged: true, pictureFresh: false)
                == .exitPlayback)
    }

    @Test func enablesOnlyAfterExitClearsPlayback() {
        #expect(
            MediaLiveResume.action(
                attempt: 2, inPlayback: false, exitAcknowledged: true, pictureFresh: false)
                == .enableLiveView)
    }

    @Test func doneWhenLivePictureIsBack() {
        #expect(
            MediaLiveResume.action(
                attempt: 3, inPlayback: false, exitAcknowledged: true, pictureFresh: true)
                == .done)
    }

    @Test func stillEnablesAfterTheExitBudget() {
        #expect(
            MediaLiveResume.action(
                attempt: MediaLiveResume.maxExitAttempts + 1,
                inPlayback: true,
                exitAcknowledged: false,
                pictureFresh: false)
                == .enableLiveView)
    }

    @Test func strayPlaybackOnLiveViewSendsExit() {
        #expect(
            MediaLiveResume.strayPlaybackAction(browsing: false, inPlayback: true)
                == .exitPlayback)
        #expect(MediaLiveResume.strayPlaybackAction(browsing: true, inPlayback: true) == nil)
        #expect(MediaLiveResume.strayPlaybackAction(browsing: false, inPlayback: false) == nil)
    }
}
