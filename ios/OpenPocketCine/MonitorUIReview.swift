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

        #if DEBUG
            static var zoomControls: Bool {
                screen == "live"
                    && ProcessInfo.processInfo.environment["OPV_UI_REVIEW_ZOOM_CONTROLS"]
                        == "1"
            }
        #endif

        static func prepare(_ model: AppModel) {
            // Presentation reviews do not send reports or inherit first-run consent.
            // Keep the operator's real choice and explicit consent reviews separate.
            if ProcessInfo.processInfo.environment["OPV_CONSENT_REVIEW_ID"] == nil,
                let defaults = UserDefaults(suiteName: "opc.monitor.presentation.review")
            {
                ReliabilityReportingConsent.defaults = defaults
                ReliabilityReportingConsent.setOptedIn(false)
            }
            model.showsLaunchSplash = false
            model.assist.lutEnabled = false
            model.assist.peaking = false
            model.assist.zebra = false
            model.assist.falseColor = false
            model.assist.falseColorReference = true
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
            AudioAssist.store.options = .init()
            FalseColorReferencePositionStore.shared.positions = FalseColorReferencePositions()
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
            #if DEBUG
                if zoomControls {
                    let recordingDLog2 =
                        ProcessInfo.processInfo.environment["OPV_UI_REVIEW_ZOOM_DLOG2_RECORDING"]
                        == "1"
                    status.colorMode = recordingDLog2 ? .dLog2 : .normal
                    status.isRecording = recordingDLog2
                    status.zoomLens = CamFov.lens1x
                }
            #endif
            status.batteryPercent = 68
            status.storageFreeMb = 107 * 1024
            status.storageTotalMb = 128 * 1024
            status.shootingMode = 1
            status.videoResolution = VideoResolution(rawValue: 0x10)
            status.fps = 25
            status.availableIsoIndices = [
                .iso100, .iso200, .iso400, .iso800, .iso1600, .iso3200, .iso6400,
            ]
            status.availableShutterDenoms = [25, 50, 100, 200, 500]
            model.session.status = status
            if ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MOTION"] == "1" {
                model.session.gimbalProgram = GimbalProgram(
                    a: .init(yawDeg: 0, pitchDeg: 0, zoom: 1, nativePitchDeg: 0),
                    b: .init(yawDeg: 30, pitchDeg: 0, zoom: 1, nativePitchDeg: 0),
                    c: .init(yawDeg: 30, pitchDeg: 20, zoom: 1, nativePitchDeg: -20),
                    durationAB: 3, durationBC: 2, smoothness: 0.5)
                if ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MOTION_ZOOM"] == "1" {
                    model.session.gimbalProgram.b?.zoom = 3
                    model.session.gimbalProgram.c?.zoom = 2
                    model.session.status.zoomLens = CamFov.lens1x
                }
                if ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MOTION_RUNNING"] == "1" {
                    model.session.gimbalMoveRunning = true
                    model.session.gimbalMoveCanPause = true
                    model.session.gimbalMovePaused =
                        ProcessInfo.processInfo.environment["OPV_UI_REVIEW_MOTION_PAUSED"] == "1"
                }
            }
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
