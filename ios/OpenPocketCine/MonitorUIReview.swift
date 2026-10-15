import OpenCineCore
import OpenCineDJIApple

#if targetEnvironment(simulator)
    import Foundation
    import MonitorPresentation
    import OpenCineApple
    import OpenCineCameraControls
    import OpenCineDJIApple
    import OpenPocketViewCore

    /// Deterministic simulator-only presentation fixture. Opt-in environment values
    /// never run on a physical camera or in an App Store build, never persist camera
    /// identities, and never advance the actual connection state machine.
    @MainActor
    enum MonitorUIReview {
        /// The shared typed review every app decodes (`ReviewLaunch`). Other switches (body, fit,
        /// zoom controls, motion) stay raw `OPV_UI_REVIEW_*` keys read below.
        static var launch: ReviewLaunch? { .current }
        static var screen: ReviewLaunch.Screen? { launch?.screen }
        static var isActive: Bool { launch != nil }
        /// The connection state the cameras and pair pages show: `empty`, `saved-nearby`,
        /// `connecting`, `failure`, `add-setup`, `multiview`, `pair-choose`, `pair-approve`,
        /// `pair-join`, `pair-video`, `pair-failure`, `pair-bluetooth`; none is the two saved
        /// cameras, idle.
        static var state: String { launch?.state ?? "" }
        static let studioID = "00000000-0000-0000-0000-000000000001"
        static let newID = "00000000-0000-0000-0000-000000000003"

        /// The shared cameras model's inputs for a review: a scripted DJI pipeline and a private
        /// defaults domain holding the two saved cameras as the shipping app stored them.
        /// Media favorites persist per camera. Every review starts with none, so a review that
        /// favorites a clip cannot take "Add favorite" away from the next one. Runs before the
        /// session builds its library, which reads them once.
        static func resetMediaFavorites() {
            for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("opc.media.fav.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        static func cameras() -> (any DJIConnectPort, UserDefaults) {
            // Installed-build migration checks render the real persisted records without BLE.
            if state == "stored" { return (ReviewDJIPort(state: "empty"), .standard) }
            let name = "opc.monitor.presentation.review.cameras"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            if state != "empty" {
                let past = Date.distantPast.timeIntervalSinceReferenceDate
                let records: [[String: Any]] = [
                    [
                        "id": studioID, "advertisedName": "Studio camera", "modelName": "Osmo Pocket 4 Pro",
                        "modelId": 0x22, "lastConnectedAt": past, "wifiSSID": "Studio-5G", "hotspotSSID": "Rig iPhone",
                    ],
                    [
                        "id": "00000000-0000-0000-0000-000000000002", "advertisedName": "Travel camera",
                        "modelName": "Osmo Nano", "modelId": 0x19, "lastConnectedAt": past,
                    ],
                ]
                defaults.set(try? JSONSerialization.data(withJSONObject: records), forKey: "OpenPocketCine.SavedCameras")
            }
            return (ReviewDJIPort(state: state), defaults)
        }

        /// The body the review lays out (`OPV_UI_REVIEW_BODY=nano`, else Pocket 4 Pro). It
        /// reaches the screens only as the DJI integration's capability projection.
        static var body: CameraModel? {
            guard isActive else { return nil }
            return ProcessInfo.processInfo.environment["OPV_UI_REVIEW_BODY"] == "nano"
                ? .resolve(modelId: 0x19, name: "Osmo Nano")
                : .resolve(modelId: 0x22, name: "Osmo Pocket 4 Pro")
        }

        #if DEBUG
            static var zoomControls: Bool {
                screen == .live
                    && ProcessInfo.processInfo.environment["OPV_UI_REVIEW_ZOOM_CONTROLS"]
                        == "1"
            }
        #endif

        static func prepare(_ model: AppModel) {
            if state == "stored" {
                model.showsLaunchSplash = false
                model.isPairingNewCamera = false
                return
            }
            // Presentation reviews do not send reports or inherit first-run consent.
            // Keep the operator's real choice and explicit consent reviews separate.
            if ProcessInfo.processInfo.environment["OPV_CONSENT_REVIEW_ID"] == nil,
                let defaults = UserDefaults(suiteName: "opc.monitor.presentation.review")
            {
                AppDiagnostics.consent.defaults = defaults
                AppDiagnostics.consent.setOptedIn(false)
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
            model.assist.evMeter = true
            model.assist.audioMeters = false
            model.assist.guides = false
            model.assist.grid = false
            model.assist.crosshair = false
            model.assist.mirror = false
            model.assist.configureTool = nil
            model.assist.clean = false
            // The palette ranks tools by persisted use: start every review from the first-run order.
            model.assistToolUsage = MonitorToolUsage()
            WaveformAssist.store.options = .default
            ParadeAssist.store.options = .default
            HistogramAssist.store.options = .default
            VectorscopeAssist.store.options = .default
            AudioAssist.store.options = .init()
            AssistPanelStores.app.reference.positions = FalseColorReferencePositions()
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
            status.timecodeValue = CameraTimecode(hours: 15, minutes: 39, seconds: 50, frames: 0)
            status.colorMode = .dLog2
            if let ev = launch?.meteredEV {
                // The camera meters in thirds of a stop: the nearest one it could report.
                status.meteredEv = EvComp(
                    thirds: min(max(Int((ev * 3).rounded()), EvComp.minThirds), EvComp.maxThirds))
            }
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
            // A real body lists several rates, so reviews show the frame-rate drum
            // with neighbours on both sides of the current 25p.
            status.availableVideoFormats = [
                .fps24, .fps25, .fps30, .fps48, .fps50, .fps60,
            ].map { VideoFormat(resolution: VideoResolution(rawValue: 0x10), frameRate: $0) }
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
            let cameras = model.cameras
            switch state {
            case "connecting":
                if let studio = cameras.saved.first(where: { $0.id == studioID }) {
                    cameras.connect(studio, route: studio.routes.first { $0.kind == .infrastructureNetwork }?.id)
                }
            case "failure":
                if let studio = cameras.saved.first(where: { $0.id == studioID }) { cameras.connect(studio) }
            case "pair-approve", "pair-join", "pair-video", "pair-failure":
                Task {
                    // The scripted camera appears once discovery starts.
                    while !cameras.nearby.contains(where: { $0.id == newID }) {
                        try? await Task.sleep(for: .milliseconds(20))
                    }
                    cameras.selection = newID
                    if let sighting = cameras.nearby.first(where: { $0.id == newID }) { cameras.connect(sighting) }
                }
            case "pair-bluetooth":
                model.session.phase = .failed(StartupConnectionCopy.bluetoothDenied)
            default: break
            }
            model.isPairingNewCamera = screen == .pair
            guard let launch, launch.screen != .cameras, launch.screen != .pair else { return }
            #if DEBUG
                if launch.commonControls, let body {
                    model.presentSimulatedControls(status: status, body: body)
                } else {
                    model.presentSimulatorPreview()
                }
            #else
                model.presentSimulatorPreview()
            #endif
            switch launch.screen {
            case .settings:
                if let tab = launch.settingsTab { model.operatorSettingsTab = tab }
                model.shell.open(.settings)
            case .chromeEdit: model.beginChromeEditing(model.currentDispMode)
            case .media, .playback:
                #if DEBUG
                    if launch.source == .camera, launch.connected { connectCameraMedia(model.session) }
                    opensFirstClip = launch.screen == .playback
                    Task {
                        do { try await stageMedia(launch, in: model.session) } catch {
                            assertionFailure("Could not stage the review clips: \(error)")
                        }
                        model.shell.open(.media)
                    }
                #endif
            case .cameras, .pair, .live: break
            }
        }

        #if DEBUG
            /// `ReviewLaunch(screen: .playback)`: the Media page opens its first clip once, as a tap would.
            static var opensFirstClip = false

            /// `mediaCount` generated clips (`ReviewClip`) written through the library's own cache
            /// and catalog, exactly as finished downloads leave them.
            static func stageMedia(_ launch: ReviewLaunch, in session: CameraSession) async throws {
                let cache = session.mediaLibrary.cache
                try await cache.directory.clear(preserving: [])
                let clip = FileManager.default.temporaryDirectory.appendingPathComponent("ReviewClip.mp4")
                try await ReviewClip.write(to: clip)
                let bytes = try Data(contentsOf: clip)
                // One clip a minute from 2026-09-12 12:00 UTC, named as the camera names them.
                let names = DateFormatter()
                names.locale = Locale(identifier: "en_US_POSIX")
                names.timeZone = TimeZone(identifier: "UTC")
                names.dateFormat = "'DJI_'yyyyMMddHHmmss"
                let files = (0..<launch.mediaCount).map { index in
                    let name = names.string(from: Date(timeIntervalSince1970: 1_789_214_400 + Double(index) * 60))
                        + String(format: "_%04d_D", index + 1)
                    return MediaFile(
                        path: "DCIM/DJI_001/\(name).MP4", thumbPath: "MISC/THM/DJI_001/\(name).scr",
                        handle: UInt32(index + 1), sizeBytes: UInt64(bytes.count),
                        durationSeconds: ReviewClip.seconds, resolution: "640x360", fps: 24)
                }
                let records = try cache.codec.decode(JSONEncoder().encode(files))
                for record in records {
                    for representation in record.asset.representations where representation.role == .original {
                        if let address = record.address.representations[representation.id] {
                            try cache.directory.write(bytes, at: address)
                        }
                    }
                }
                try cache.save(records)
                // The library loads its catalog once; the next read builds one over the staged clips.
                session.mediaLibraryOwner?.close()
                session.mediaLibraryOwner = nil
                session.mediaLibrary.layout = launch.layout
            }

            /// A connected camera's media page: the session is live over a datalink that is never
            /// opened, so the production gallery and player offer camera actions (delete, download)
            /// while no command reaches a network.
            static func connectCameraMedia(_ session: CameraSession) {
                session.datalink = DjiAppleDatalink(port: 0, tcpPoke: false, pairingToken: "")
                session.phase = .live
            }
        #endif
    }

    /// Simulator review only: a scripted DJI pipeline, so the shared pages show each connection
    /// state without a camera. Never connects, never stores anything.
    @MainActor
    final class ReviewDJIPort: DJIConnectPort {
        var onSightings: (([DJISighting]) -> Void)?
        var onStage: ((DJIConnectionStage, String?) -> Void)?
        /// The session's saved-hotspot ask, which this port stands in for (CameraSession+DJIConnectPort).
        var confirmHotspot: ((String) async -> Bool)?
        private let state: String

        init(state: String) { self.state = state }

        func startScan() {
            guard state != "empty", state != "connecting", state != "pair-bluetooth" else { return }
            let studio = DJISighting(
                id: MonitorUIReview.studioID, name: "Studio camera",
                model: .resolve(modelId: 0x22, name: "Osmo Pocket 4 Pro"), modelId: 0x22)
            let fresh = DJISighting(
                id: MonitorUIReview.newID, name: "OsmoPocket3-4D5E",
                model: .resolve(modelId: 0x20, name: "OsmoPocket3-4D5E"), modelId: 0x20)
            onSightings?(state.hasPrefix("pair-") && state != "pair-choose" ? [fresh] : [studio, fresh])
        }

        func stopScan() {}

        func connect(cameraID: String, setup: DJISetup, restoreAccessPoint: Bool) async throws -> DJIConnection {
            if case .phoneHotspot(let network, nil) = setup, DjiAppleSharedWiFiPath.address(hotspot: true) == nil,
                let confirmHotspot
            {
                guard await confirmHotspot(network) else { throw CancellationError() }
            }
            switch state {
            case "connecting": onStage?(.joiningWiFi, "Joining Studio-5G on this iPhone")
            case "pair-approve": onStage?(.awaitingApproval, nil)
            case "pair-join": onStage?(.joiningWiFi, "Joining camera Wi-Fi…")
            case "pair-video": onStage?(.openingDatalink, nil)
            case "failure", "pair-failure":
                onStage?(.openingDatalink, nil)
                throw CameraSession.failure(
                    .timedOut, "datalink.silent", StartupConnectionCopy.friendly("datalink handshake timed out"))
            default: break
            }
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }

        func disconnect() {}
        func forget(cameraID: String) {}
    }
#endif
