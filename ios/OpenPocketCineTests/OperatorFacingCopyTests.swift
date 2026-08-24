import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Operator-facing copy must never name a sister app or another camera brand.
final class OperatorFacingCopyTests: XCTestCase {
    func testHelpCopyDoesNotNameSisterApps() {
        let facing = Self.operatorFacingCopy
        XCTAssertFalse(facing.isEmpty)
        for text in facing {
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains("OpenZCine"),
                "operator copy names OpenZCine: \(text)")
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains("Nikon"),
                "operator copy names Nikon: \(text)")
        }
    }

    private static var operatorFacingCopy: [String] {
        [
            ZebraAssist.unitsHelp,
            ZebraAssist.highlightHelp,
            ZebraAssist.midtoneHelp,
            PeakingAssist.sensitivityHelp,
            PeakingAssist.colorHelp,
            FalseColorAssist.scaleHelp,
            FalseColorAssist.referenceHelp,
            WaveformAssist.brightnessHelp,
            ParadeAssist.brightnessHelp,
            HistogramAssist.trafficLightsHelp,
            HistogramAssist.compensationHelp,
            TrafficLightsAssist.compensationHelp,
            LUTAssist.exposureTitle,
            LUTAssist.exposureHelp,
            MediaDeliveryCopy.bakeLUT,
            MediaDeliveryCopy.bakeLUTHelpUnavailable,
            MediaDeliveryCopy.bakeLUTHelp(statusLabel: "Auto · D-Log2 → Rec.709"),
            MediaDeliveryCopy.bakeExposure,
            MediaDeliveryCopy.bakeExposureHelp,
            AudioAssist.helpCopy,
            CrosshairAssist.helpCopy,
            MirrorAssist.explanation,
            SettingsHelpCopy.currentTransport,
            SettingsHelpCopy.stream,
            SettingsHelpCopy.shareFeed,
            SettingsHelpCopy.editView,
            PocketDispMode.live.settingsTitle,
            PocketDispMode.clean.settingsTitle,
            PocketDispMode.live.settingsCaption,
            PocketDispMode.clean.settingsCaption,
            "Editing Live",
            "Tap an eye to show or hide it",
            "View assists that stay on in clean view",
            "Live view for this camera is not captured yet.",
            "Resolution · Framerate",
            "Color",
            "Show view assists",
            "Fit feed in frame",
            "Fill frame with feed",
            "Recording options",
            "Bluetooth reached a different camera than the one you tapped. Pocket and Nano are separate — pick the Nano or Pocket row in the list.",
            "couldn't switch from other camera — tap Connect again",
            SettingsHelpCopy.frameIO,
            SettingsHelpCopy.shareThisFeed,
            SettingsHelpCopy.broadcastPriority,
            SettingsHelpCopy.watcherPasscode,
            SettingsHelpCopy.controlRequests,
            SettingsHelpCopy.recordConfirmation,
            SettingsHelpCopy.haptics,
            SettingsHelpCopy.joystickSensitivity,
            SettingsHelpCopy.keepScreenAwake,
            CaptureLists.nativeIsoHopTitle,
            CaptureLists.nativeIsoHopHelp,
            SettingsHelpCopy.themeHelp,
            SettingsHelpCopy.supportHelp,
            SettingsHelpCopy.reportHelp,
            SettingsHelpCopy.featureHelp,
            SettingsHelpCopy.sourceHelp,
            SettingsHelpCopy.linkHealth,
            SettingsHelpCopy.feedUpscaler,
            SettingsHelpCopy.clearCache,
            SettingsHelpCopy.cacheFullResolution,
            MediaLibraryCopy.proxyTag,
            MediaLibraryCopy.proxyHelp,
            MediaLibraryCopy.filterEmpty,
            MediaLibraryCopy.emptyAll,
            MediaLibraryCopy.emptyFavorites,
            MediaLibraryCopy.emptyVideos,
            MediaLibraryCopy.emptyPhotos,
            MediaLibraryCopy.disconnected,
            MediaLibraryCopy.disconnectedEmptyCache,
            MediaOperatorCopy.clipNotCached,
            MediaOperatorCopy.listing,
            MediaOperatorCopy.notConnected,
            MediaOperatorCopy.playbackFailed,
            MediaOperatorCopy.noClips,
            MediaOperatorCopy.listFailed,
            MediaOperatorCopy.notDeletable,
            MediaOperatorCopy.deleteFailed,
            MediaOperatorCopy.downloadFailed,
            MediaOperatorCopy.thumbFailed,
            MediaOperatorCopy.clipOpenFailed,
            MediaOperatorCopy.clipLoading,
            SessionRecoveryCopy.title(.retrying(attempt: 1, maxAttempts: 8)),
            SessionRecoveryCopy.detail(
                .retrying(attempt: 3, maxAttempts: 8), deviceName: "Pocket 4 Pro"),
            SessionRecoveryCopy.detail(
                .waitingForOperator(attemptsMade: 8), deviceName: "Pocket 4 Pro"),
            SessionRecoveryCopy.detail(
                .pausedAfterRepeatedDrops(drops: 3), deviceName: "Pocket 4 Pro"),
            SessionRecoveryCopy.heldFrameBadge,
        ]
    }
}
