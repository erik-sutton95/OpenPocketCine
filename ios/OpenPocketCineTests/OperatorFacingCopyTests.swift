import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineCore
import OpenCineDJIApple
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Operator-facing copy must never name a sister app, another camera brand,
/// or Adobe's integrator-program name.
final class OperatorFacingCopyTests: XCTestCase {
    func testSharedTransportFailureRetainsAppCopyAndCallerFallback() {
        let denied = DjiAppleDatalink.DatalinkError.localNetworkDenied
        XCTAssertEqual(djiConnectionFailureDescription(denied), StartupConnectionCopy.localNetworkDenied)
        XCTAssertEqual(djiConnectionFailureDescription(denied, fallback: "generic"),
            StartupConnectionCopy.localNetworkDenied)
        let network = NSError(domain: "SIMULATED transport", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Existing network detail"])
        XCTAssertEqual(djiConnectionFailureDescription(network, fallback: network.localizedDescription),
            "Existing network detail")
        XCTAssertEqual(djiConnectionFailureDescription(network), "\(network)")
    }

    func testUnknownNativeQueueAgeMapsOnlyAtLegacyIncidentBoundary() {
        let unknown = DjiAppleQueueObservation()
        XCTAssertNil(unknown.ageMilliseconds)
        let legacy = FeedIncidentQueue(unknown)
        XCTAssertEqual(legacy.ageMilliseconds, 0)
        XCTAssertEqual(legacy.count, 0)
        XCTAssertEqual(FeedIncidentQueue(DjiAppleQueueObservation(bytes: 12, count: 1,
            ageMilliseconds: 18)).ageMilliseconds, 18)
    }

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
            MonitorSettingsNumberField.doneTitle,
            PeakingAssist.sensitivityHelp,
            PeakingAssist.colorHelp,
            FalseColorLooks.app.scaleHelp,
            FalseColorAssist.referenceHelp,
            WaveformAssist.brightnessHelp,
            ParadeAssist.brightnessHelp,
            HistogramAssist.trafficLightsHelp,
            HistogramAssist.compensationHelp,
            TrafficLightsAssist.compensationHelp,
            LUTAssist.exposureTitle,
            LUTAssist.exposureHelp,
            MonitorClipDeliveryCopy.openPocketCine.convertHelp,
            MonitorClipDeliveryCopy.openPocketCine.convertUnavailableHelp,
            MonitorClipDeliveryCopy.openPocketCine.notLog("SIMULATED.MP4"),
            MonitorDeliveryDestination.nativeShare.subtitle(remoteDisplayName: "Frame.io"),
            AudioAssist.helpCopy,
            CrosshairAssist.helpCopy,
            MirrorAssist.explanation,
            SettingsHelpCopy.currentTransport,
            MonitorSettingsCopy.accountHelp(service: "Frame.io"),
            MonitorSettingsCopy.shareThisFeed,
            MonitorSettingsCopy.broadcastPriority,
            MonitorSettingsCopy.watcherPasscode,
            MonitorSettingsCopy.controlRequests,
            MonitorSettingsCopy.gimbalHaptics,
            MonitorSettingsCopy.headTracking,
            HeadphoneMotionBridge.calibrateTitle,
            HeadTrackStop.gimbalMode(.fpv)?.note ?? "",
            HeadTrackStop.gimbalMode(.directionLock)?.note ?? "",
            HeadTrackStop.pastReach.note,
            MonitorSettingsCopy.joystickSensitivity,
            MonitorSettingsCopy.virtualJoystickInvertPan,
            MonitorSettingsCopy.virtualJoystickInvertTilt,
            MonitorSettingsCopy.virtualJoystickDeadzone,
            MonitorSettingsCopy.virtualJoystickResponse,
            MonitorSettingsCopy.gimbalJoystick,
            MonitorSettingsCopy.gamepad,
            MonitorSettingsCopy.keepScreenAwake,
            MonitorSettingsCopy.hdrPanel(cameraMode: "HDR/HLG color mode"),
            CaptureLists.nativeIsoHopTitle,
            CaptureLists.nativeIsoHopHelp,
            NDAssist.helpCopy,
            NDAssist.notationTitle,
            NDAssist.notationHelp,
            SettingsHelpCopy.themeHelp,
            MonitorSettingsCopy.shareDiagnostics,
            MonitorSettingsCopy.sourceHelp(app: "OpenPocketCine"),
            MonitorSettingsCopy.automaticReports,
            MonitorSettingsCopy.automaticReportsUnavailable,
            MonitorSettingsCopy.deleteSavedFeedReports,
            MonitorSettingsCopy.virtualJoystickSize,
            MonitorSettingsCopy.feedUpscaler,
            MonitorSettingsCopy.clearAllCamerasCache,
            MonitorSettingsCopy.cacheFullResolution,
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
