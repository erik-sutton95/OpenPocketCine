#if targetEnvironment(simulator)
    import Foundation
    import OpenPocketViewCore

    /// Deterministic simulator-only presentation fixture. Opt-in environment values
    /// never run on a physical camera or in an App Store build, never persist camera
    /// identities, and never advance the actual connection state machine.
    @MainActor
    enum MonitorUIReview {
        static var screen: String? { ProcessInfo.processInfo.environment["OPV_UI_REVIEW_SCREEN"] }
        static var isActive: Bool { screen != nil }

        static func prepare(_ model: AppModel) {
            model.showsLaunchSplash = false
            model.assist.lutEnabled = false
            model.assist.peaking = false
            model.assist.zebra = false
            model.assist.falseColor = false
            model.assist.waveform = false
            model.assist.parade = false
            model.assist.histogram = false
            model.assist.vectorscope = false
            model.assist.trafficLights = false
            model.assist.ndMeter = false
            model.assist.audioMeters = false
            model.assist.guides = false
            model.assist.grid = false
            model.assist.crosshair = false
            model.assist.mirror = false
            model.assist.configureTool = nil
            model.assist.clean = false
            WaveformAssist.store.options = .default
            ParadeAssist.store.options = .default
            HistogramAssist.store.options = .default
            VectorscopeAssist.store.options = .default
            WaveformAssist.store.sessionCenter = nil
            WaveformAssist.store.sessionCenterPortrait = nil
            ParadeAssist.store.sessionCenter = nil
            ParadeAssist.store.sessionCenterPortrait = nil
            HistogramAssist.store.sessionCenter = nil
            HistogramAssist.store.sessionCenterPortrait = nil
            VectorscopeAssist.store.sessionCenter = nil
            VectorscopeAssist.store.sessionCenterPortrait = nil
            model.recordConfirmationEnabled = true
            model.portraitFeedAspect =
                ProcessInfo.processInfo.environment["OPV_UI_REVIEW_FIT"] == "1" ? .fit16x9 : .fill
            var status = CameraStatus()
            status.iso = 1600
            status.isoIndex = .iso1600
            status.shutterDenom = 50
            status.expoMode = .manual
            status.whiteBalance = .custom(kelvin: 5600, tint: 0)
            status.whiteBalanceKelvin = 5600
            status.focusMode = .continuous
            status.audioChannel = .stereo
            status.timecode = "15:39:50:00"
            status.colorMode = .dLog2
            status.batteryPercent = 68
            status.storageFreeMb = 107 * 1024
            status.storageTotalMb = 128 * 1024
            status.shootingMode = 1
            status.fps = 25
            status.availableIsoIndices = [
                .iso100, .iso200, .iso400, .iso800, .iso1600, .iso3200, .iso6400,
            ]
            status.availableShutterDenoms = [25, 50, 100, 200, 500]
            model.session.status = status
            model.session.liveSignalBars = 4
            model.session.liveFPS = "25.00"
            model.savedCameras = [
                SavedCamera(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    advertisedName: "Studio camera", modelName: "Osmo Pocket 4 Pro",
                    lastConnectedAt: .distantPast, modelId: 0x22),
                SavedCamera(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    advertisedName: "Travel camera", modelName: "Osmo Nano",
                    lastConnectedAt: .distantPast, modelId: 0x19),
            ]
            model.isPairingNewCamera = screen == "pair"
            if screen == "settings" { model.liveOperatorPanel = .settings }
            if screen == "media" { model.liveOperatorPanel = .media }
        }
    }
#endif
