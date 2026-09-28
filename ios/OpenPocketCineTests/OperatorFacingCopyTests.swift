import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Operator-facing copy must never name a sister app, another camera brand,
/// or Adobe's integrator-program name.
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
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains("Blackmagic"),
                "operator copy names Blackmagic: \(text)")
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains("Black Magic"),
                "operator copy names Black Magic: \(text)")
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains("Camera to Cloud"),
                "operator copy uses Camera to Cloud: \(text)")
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains("Camera-to-Cloud"),
                "operator copy uses Camera-to-Cloud: \(text)")
            XCTAssertFalse(
                text.range(
                    of: #"\bC2C\b"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil,
                "operator copy uses C2C: \(text)")
        }
    }

    private static var operatorFacingCopy: [String] {
        [
            ZebraAssist.unitsHelp,
            ZebraAssist.highlightHelp,
            ZebraAssist.midtoneHelp,
            SettingsNumberField.doneTitle,
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
            MediaDeliveryCopy.convertLog,
            MediaDeliveryCopy.convertLogHelp,
            MediaDeliveryCopy.convertLogDestination,
            MediaDeliveryCopy.convertLogHelpUnavailable,
            MediaDeliveryDestination.nativeShare.subtitle,
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
            SettingsHelpCopy.frameIO,
            SettingsHelpCopy.shareThisFeed,
            SettingsHelpCopy.watchAFeed,
            SettingsHelpCopy.broadcastPriority,
            SettingsHelpCopy.watcherPasscode,
            SettingsHelpCopy.controlRequests,
            SettingsHelpCopy.recordConfirmation,
            SettingsHelpCopy.haptics,
            SettingsHelpCopy.headTracking,
            LiveHeadTrackCalibrateButton.calibrateTitle,
            SettingsHelpCopy.joystickSensitivity,
            SettingsHelpCopy.virtualJoystickInvertPan,
            SettingsHelpCopy.virtualJoystickInvertTilt,
            SettingsHelpCopy.virtualJoystickDeadzone,
            SettingsHelpCopy.virtualJoystickResponse,
            SettingsHelpCopy.gimbalJoystick,
            SettingsHelpCopy.gamepad,
            SettingsHelpCopy.keepScreenAwake,
            SettingsHelpCopy.hdrDisplay,
            CaptureLists.nativeIsoHopTitle,
            CaptureLists.nativeIsoHopHelp,
            NDAssist.helpCopy,
            NDAssist.notationTitle,
            NDAssist.notationHelp,
            SettingsHelpCopy.themeHelp,
            SettingsHelpCopy.shareDiagnostics,
            StartupConnectionCopy.shareDiagnostics,
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
            ControlHud.recordingColorLockNote,
            ControlHud.gimbalPoseNotReady,
            ControlHud.gimbalHoldStill,
            ControlHud.programmedMoveNeedAB,
            ControlHud.gimbalNeedsCalibration,
            LiveGimbalCopy.title,
            LiveGimbalCopy.mode,
            LiveGimbalCopy.speed,
            LiveGimbalCopy.ramp,
            LiveGimbalCopy.programmedMove,
            LiveGimbalCopy.runMove,
            LiveGimbalCopy.stopMove,
            StartupConnectionCopy.localNetworkDenied,
            StartupConnectionCopy.bluetoothDenied,
            StartupConnectionCopy.bluetoothOff,
            StartupConnectionCopy.bluetoothNotReady,
            StartupConnectionCopy.personalHotspotOn,
            StartupConnectionCopy.pairingDeferred,
            StartupConnectionCopy.datalinkSilent,
            StartupConnectionCopy.scanEmptyTitle,
            StartupConnectionCopy.scanEmptyHint,
            StartupConnectionCopy.preCheck,
            StartupConnectionCopy.bluetoothTimedOut,
            StartupConnectionCopy.bluetoothEnded,
            LocalVPNFilter.wizardBanner,
            LocalVPNFilter.liveHint,
            LocalVPNFilter.joinWifiPhoneStep,
            WatchRelayCopy.openOnIPhone,
            WatchRelayCopy.noCamera,
            WatchRelayCopy.waitingLive,
            WatchRelayCopy.connectFirst,
            WatchRelayCopy.switchToVideo,
            WatchRelayCopy.switchToPhoto,
            WatchRelayCopy.busy,
        ]
    }
}
