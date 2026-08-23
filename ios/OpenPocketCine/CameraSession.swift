import Foundation
import CoreGraphics
import Observation
import AVFoundation
import os
import OpenPocketViewCore

/// Orchestrates the whole Phase-0 spine: scan -> GATT -> pair -> read Wi-Fi creds -> join AP ->
/// datalink -> live status. Owns the single consumer of the BLE frame stream and routes replies to
/// whoever is awaiting them. Drives `phase` and `status` for the UI.
@MainActor
@Observable
final class CameraSession {
    var phase: ConnectionPhase = .idle
    /// Latest telemetry. Control reads this immediately; SwiftUI is notified at 5 Hz
    /// unless REC / expo mode / color / format flipped (`LiveChromeThrottle`).
    /// ISO / shutter / zoom stay on the 5 Hz cadence (camera-truth, no SET guess).
    var status: CameraStatus {
        get {
            access(keyPath: \.status)
            return statusStorage
        }
        set {
            let previous = statusStorage
            statusStorage = newValue
            guard newValue != previous else { return }
            guard LiveChromeThrottle.shouldNotify(
                previous: previous, next: newValue,
                elapsed: CFAbsoluteTimeGetCurrent() - lastStatusMutation
            ) else {
                scheduleStatusFlush()
                return
            }
            publishStatusNow()
        }
    }
    var found: [FoundCamera] = []
    /// The body this session is connecting / connected to. Used to persist a saved camera.
    private(set) var connectedCamera: FoundCamera?
    /// Camera-AP SSID after a successful join. Re-read over BLE on the next connect.
    private(set) var joinedSSID: String?

    // Pipeline diagnostics — keepalive writes these at 1 Hz. Not observed by live chrome.
    @ObservationIgnored var videoPackets = 0
    @ObservationIgnored var accessUnits = 0
    @ObservationIgnored var framesEnqueued = 0
    @ObservationIgnored var droppedIncomplete = 0
    @ObservationIgnored var decoderErrors = 0
    @ObservationIgnored var hasVideoFormat = false
    @ObservationIgnored var nalTypes = ""
    @ObservationIgnored var lastKeyframeAge = "—"
    /// OpenZCine `NativeAppModel.liveFPS` — measured live-view delivery, or LINK/FAIL/RECOV.
    var liveFPS = "—"
    /// OpenZCine `NativeAppModel.liveSignalBars` — 0–4 from `LinkSignalBars` + link-health score.
    var liveSignalBars = 0
    @ObservationIgnored private var frameRate = FrameRateSampler()
    @ObservationIgnored private var signalBarsFilter = LinkSignalBars()
    @ObservationIgnored private var lastGoodFrameAt: Date?
    @ObservationIgnored private var consecutiveBadLiveFrames = 0
    @ObservationIgnored private var lastDecoderErrorCount = 0
    @ObservationIgnored private var lastReceiveErrorCount = 0
    @ObservationIgnored private var recentKeepaliveFailures = 0
    @ObservationIgnored private var rawAccessUnits = 0
    @ObservationIgnored private var rawFramesEnqueued = 0
    @ObservationIgnored private var lastIdrRequest = Date.distantPast
    @ObservationIgnored private var liveViewEnableSent = false
    @ObservationIgnored private var liveViewEnableSends = 0
    /// `0x09/0xa8` sends while `awaitingIDR` is still true. Caps the mid-session
    /// IDR retry at one extra enable so a missed keyframe cannot 1 Hz loop.
    @ObservationIgnored private var idrHoldEnableCount = 0
    /// Audio/Vocal/DSP GETs on first connect sat on UDP and lined up with the TCP RST.
    @ObservationIgnored private var audioRefreshPending = false
    /// One GET/SET of `0x8E` pid `0x0039` after first picture — turn Mimo glamour off.
    @ObservationIgnored private var glamourClearPending = false
    /// One GET of `0x8E` pid `0x003B` so the FOCUS sheet knows Default vs Lock.
    @ObservationIgnored private var focusTrackPending = false
    /// Last AF-C `0x3B` SET. Watchdog grace while the encoder may pause.
    @ObservationIgnored private var lastFocusTrackAt: Date?
    private var secondsSinceFocusTrackSet: TimeInterval? {
        lastFocusTrackAt.map { Date().timeIntervalSince($0) }
    }
    @ObservationIgnored private var feedWatchdog = FeedWatchdog()
    @ObservationIgnored private var feedRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var statusStorage = CameraStatus()
    @ObservationIgnored private var lastStatusMutation: CFAbsoluteTime = 0
    @ObservationIgnored private var statusFlushTask: Task<Void, Never>?

    @ObservationIgnored private let ble = BleLink()
    @ObservationIgnored var datalink: DatalinkDriver?
    @ObservationIgnored private var frameRouter: Task<Void, Never>?
    @ObservationIgnored private var keepaliveLoop: Task<Void, Never>?
    @ObservationIgnored private var waiters: [UInt16: FrameWaiter] = [:]
    /// Handshake replies can land in the same notification before the next waiter is registered.
    @ObservationIgnored private var pairingHold: [UInt16: Duml.Frame] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "session")
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var connectGeneration = 0
    @ObservationIgnored private var reconnectTarget: UUID?
    @ObservationIgnored private var sessionRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var sessionRecoveryGeneration = 0
    @ObservationIgnored private var recoveryCardGraceTask: Task<Void, Never>?
    @ObservationIgnored private var sessionDropStormGuard = SessionDropStormGuard()
    @ObservationIgnored private var recoveryCameraID: UUID?
    private static let recoveryCardGrace: Duration = .seconds(2.5)
    private static let recoveryAttemptDeadline: Duration = .seconds(30)
    /// True while a saved-camera tap is waiting for that peripheral to advertise.
    /// Observable so the header pill can read **Reconnecting** (OpenZCine parity).
    private(set) var isReconnecting = false
    /// Established session dropped — keep the last frame and retry automatically.
    var sessionRecovery: SessionRecoveryState = .idle
    /// Keeps `LiveViewScreen` mounted while `phase` leaves `.live` during recovery.
    var holdsMonitor = false
    /// Attempt-1 card waits this out so a 1-second blip does not flash the overlay.
    var sessionRecoveryCardGraceElapsed = false
    /// Name shown on the recovery card (captured at drop, before `connectedCamera` is cleared).
    var recoveryDeviceName = ""
    /// Watchdog is running a staged feed recover (enable → VT → UDP → rejoin).
    private(set) var feedRecovering = false
    /// Cover the feed well until a rolling picture exists (not a frozen first IDR).
    private(set) var isFeedWarming = true
    /// In-flight record / mode / param write. UI disables the rec lamp while true.
    private(set) var controlBusy = false
    /// Last camera-control reply (empty when the last command succeeded).
    var controlNote: String?
    /// Camera-library listing while the Media page is open.
    var mediaFiles: [MediaFile] = []
    var mediaFetchInProgress = false
    var mediaFetchListedCount = 0
    var mediaNote: String?
    /// While true, keepalive must not re-enable live view or recover the feed.
    var isBrowsingMedia = false
    var mediaDownloadProgress: [String: Double] = [:]
    var mediaLocalFavorites: Set<String> = []
    @ObservationIgnored let cameraMedia = CameraMedia()
    /// Last tap-to-focus point in feed-normalized 0…1. Always drawn when not tracking.
    var focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    /// Operator-drawn search rect while the camera is still hunting a subject.
    var searchBox: TrackingBox?
    /// Locked subject box. Camera floats when `0xA5` carries them; else a tight stand-in.
    var subjectBox: TrackingBox?
    /// True after `0xA5` replies `00 01 00 00`.
    var isTracking = false
    /// Local AF-C primary face from Vision. Nil in AF-S or while subject tracking.
    var faceBox: TrackingBox?
    /// Every AF-C face in the frame. Dim extras stay up while a subject is locked.
    private(set) var sceneFaces: [TrackingBox] = []
    /// What the feed should draw for AF / search / subject / face.
    var focusOverlay: FocusOverlay {
        if FaceAFPolicy.shouldHoldTapBox(secondsSinceTap: secondsSinceTapFocus) {
            let base = FocusOverlayPolicy.resolve(
                tracking: isTracking, search: searchBox, subject: subjectBox)
            switch base {
            case .search, .subject: return base
            case .focus, .face: return .focus
            }
        }
        return FaceAFPolicy.resolve(
            focusMode: status.focusMode,
            tracking: isTracking,
            search: searchBox,
            subject: subjectBox,
            face: faceBox
        )
    }
    /// Faces that are not the primary AF-C box and not the locked subject.
    var dimmedFaces: [TrackingBox] {
        let hiding: TrackingBox?
        if case .face(let box) = focusOverlay { hiding = box } else { hiding = nil }
        let occluder: TrackingBox?
        switch focusOverlay {
        case .subject(let box): occluder = box
        case .search(let box): occluder = box
        default: occluder = subjectBox
        }
        return SceneFacePolicy.dimmed(faces: sceneFaces, hiding: hiding, occluder: occluder)
    }
    /// Keep Vision running in AF-C even after ActiveTrack locks, so extras stay visible.
    /// Armed after a fresh presented picture; VT already starts at format.
    var wantsFaceAF: Bool {
        status.focusMode == .continuous && faceAFArmed
    }
    /// Face-priority EV also needs Vision, including AF-S.
    var wantsFaceDetect: Bool {
        wantsFaceAF || wantsFacePriorityMeter
    }
    var wantsFacePriorityMeter: Bool {
        OperatorPrefs.facePriorityExposureEnabled && status.expoMode == .auto
    }
    /// Side-rail lock (OpenZCine `interfaceLocked`). Disables capture-bar tiles.
    var isLocked = false
    /// Latest held gimbal stick. Nil when the operator is not touching it.
    @ObservationIgnored private var pendingGimbalAxes: (UInt16, UInt16)?
    @ObservationIgnored private var gimbalStickPump: Task<Void, Never>?
    @ObservationIgnored private var gimbalStickHeld = false
    @ObservationIgnored private var lastGimbalStickAt: Date?
    @ObservationIgnored private var nextTrackingId: UInt16 = 1
    @ObservationIgnored private var trackingPollTask: Task<Void, Never>?
    @ObservationIgnored private var trackingSawLock = false
    /// After our CLEAR, ignore leftover `0x89` briefly. Then the camera is truth.
    @ObservationIgnored private var lastOperatorClearAt: Date?
    /// Last `0x89` subject push. Silence means the body dropped the lock.
    @ObservationIgnored private var lastSubjectPushAt: Date?
    @ObservationIgnored private var lastLiveTrackingAt: Date?
    @ObservationIgnored private var lastFaceAt: Date?
    @ObservationIgnored private var lastFaceHitAt: Date?
    @ObservationIgnored private var lastTapFocusAt: Date?
    private var faceAFArmed = false
    @ObservationIgnored private var faceAFArmTask: Task<Void, Never>?
    /// First GOP has rolled past the IDR grace. Later stalls are the watchdog.
    @ObservationIgnored private var firstPictureSettled = false
    private var secondsSinceTapFocus: TimeInterval? {
        lastTapFocusAt.map { Date().timeIntervalSince($0) }
    }
    @ObservationIgnored private var faceTarget: TrackingBox?
    @ObservationIgnored private var faceTracks: [FaceTrack] = []
    @ObservationIgnored private let faceDetector = LiveFaceDetector()
    @ObservationIgnored private var lastFacePriorityEVAt = Date.distantPast
    @ObservationIgnored private var facePriorityAcquireAt: Date?
    @ObservationIgnored private var evBeforeFacePriority: EvComp?
    /// Last 1× / 3× / 6× / 12× stop from the cycle button.
    var zoomStop: Double = 1
    /// Pinch HUD between `cam_fov` pushes. Nil when fingers are up.
    var zoomPinchPreview: Double?
    /// Chip-tap target until `cam_fov` catches up. Nil when live matches.
    var zoomOptimistic: Double?

    /// Last successful SoftAP creds. Kept across disconnect — reconnect GetSSID often returns `0xE4`.
    /// Exposed so Frame.io can leave the camera AP and rejoin after upload.
    @ObservationIgnored private(set) var cachedSSID: String?
    @ObservationIgnored private var cachedPassword: String?
    @ObservationIgnored private var cachedWifiCameraId: UUID?
    /// Last `cam_expo_param` snapshot we journaled (mode / ISO / shutter / EV). Change-only.
    @ObservationIgnored private var lastLoggedExpo: (ExpoMode?, Int, Int, EvComp?)?
    /// Last `cam_fov` `@0` / lens `@14` we journaled. Change-only.
    @ObservationIgnored private var lastLoggedZoomRaw: UInt32?
    @ObservationIgnored private var lastLoggedZoomLens: UInt16?
    @ObservationIgnored private var lastZoomLogAt = Date.distantPast
    @ObservationIgnored private var lastFirstPictureLogAt = Date.distantPast
    @ObservationIgnored private var lastFirstPictureSignature = ""
    /// BLE notify timestamp. Fresh while UDP is silent ⇒ half-dead socket, rebuild UDP only.
    /// Live session was backgrounded — recover UDP/VT on the next active.
    @ObservationIgnored private var needsForegroundRecover = false
    @ObservationIgnored private var lastBleNotifyAt: Date?
    /// Hard SET settle-timeouts (no ACK, no push) inside `CameraSoftAP.commandTimeoutWindow`.
    /// Counted only for the latest mailbox generation while video is not flowing.
    @ObservationIgnored private var commandTimeoutsAt: [Date] = []
    /// Mimo model: fire-and-forget SETs, latest-wins pending. Zoom (`0xB8`)
    /// pipelines at 20 Hz without waiting for ACK. Other opcodes stay
    /// one-in-flight. Commands to different opcodes never queue behind each other.
    @ObservationIgnored private var inflight: [UInt16: InflightSend] = [:]
    @ObservationIgnored private var inflightPending: [UInt16: InflightSend] = [:]
    /// One coalesce timer per opcode so a 60 Hz pinch does not spawn 60 sleeps.
    @ObservationIgnored private var coalesceScheduled: Set<UInt16> = []
    /// Timed-out SET still eligible for a late BLE ACK (matching seq).
    @ObservationIgnored private var lateWait: [UInt16: InflightSend] = [:]
    @ObservationIgnored private var setMailbox = CameraSetMailbox()
    /// Audio GET→patch→SET round trips ride their own chain, off the SET path.
    @ObservationIgnored private var audioTail: Task<Void, Never>?
    @ObservationIgnored private var tapFocusTask: Task<Void, Never>?
    /// Set when we drop D-Log2 for telephoto so 1× can restore it.
    @ObservationIgnored private var restoreDLog2OnWide = false
    /// One tele color SET per engage — do not retry-storm 0x42.
    @ObservationIgnored private var teleColorSent = false
    @ObservationIgnored private var zoomStopTouched = false

    @ObservationIgnored private var zoomPinchAnchor = 1.0
    /// Active pinch slew (100 or 300) so we can STOP on lift / when live lands.
    @ObservationIgnored private var zoomPinchSlew: UInt16?
    /// Last lens written this pinch so we skip duplicate 0xB8.
    @ObservationIgnored private var lastPinchLens: UInt16?
    /// Last 0.1× we journaled for a pinch slider (wire is finer).
    @ObservationIgnored private var lastPinchLogTenths: Double?
    /// After a local ISO / shutter / expo SET, ignore subscribe snapshots that have not caught up.
    @ObservationIgnored private var expoPin: ExpoPin?
    @ObservationIgnored private var expoGeneration: UInt64 = 0
    @ObservationIgnored private var audioPin: AudioPin?
    /// After a local res+fps / color SET, ignore subscribe snapshots that have not caught up.
    @ObservationIgnored private var formatPin: (expected: VideoFormat, deadline: Date)?
    @ObservationIgnored private var colorPin: (expected: ColorMode, deadline: Date)?
    @ObservationIgnored let decoder = HevcDecoder()

    /// The live-view display layer, for the SwiftUI `VideoView`.
    var videoLayer: AVSampleBufferDisplayLayer { decoder.displayLayer }

    init() {
        decoder.onPresentedFrame = { [weak self] in
            self?.noteLiveFrame()
        }
        decoder.onSourceFrame = { [weak self] buffer in
            self?.considerFaceAF(buffer)
        }
        // Look/scope toggles change which decoder owns HEVC; neither side can
        // start mid-GOP, so one 0x09/0xa8 forces the IDR. 1 s floor: rapid A/B
        // toggling collapses to one enable — the keepalive IDR retry backstops it.
        decoder.onHandoffNeedsIDR = { [weak self] in
            guard let self else { return }
            if self.isBrowsingMedia { return }
            if Date().timeIntervalSince(self.lastIdrRequest) < 1 { return }
            self.sendRecoverEnable(force: true, reason: "assist VT start")
        }
        decoder.onParameterSetsChanged = { [weak self] in
            guard let self else { return }
            if self.isBrowsingMedia { return }
            self.sendRecoverEnable(force: true, reason: "encoder format change")
        }
    }

    func startScan() {
        startScan(reconnect: nil)
    }

    /// Scan for Pockets. If `id` is set, connect the matching peripheral as soon as it appears
    /// (saved-camera reconnect). Does not stop the scan before GATT connect — iOS needs the
    /// next advertisement to finish the link.
    func startScan(reconnect id: UUID?) {
        connectGeneration += 1
        abortInFlightRun()
        reconnectTarget = id
        isReconnecting = id != nil
        phase = .scanning
        found = []
        scanTask?.cancel()
        scanTask = Task {
            await ble.waitUntilPoweredOn()
            for await camera in ble.scan() {
                if Task.isCancelled { break }
                let saved = SavedCameraStore.load().first { $0.id == camera.id }
                let seen = camera.enriched(from: saved)
                if let idx = found.firstIndex(where: { $0.id == seen.id }) {
                    if FoundCameraIdentity.shouldReplace(
                        existingName: found[idx].name, existingModelId: found[idx].modelId,
                        incomingName: seen.name, incomingModelId: seen.modelId)
                    {
                        found[idx] = seen
                        if connectedCamera?.id == seen.id { connectedCamera = seen }
                    }
                } else {
                    found.append(seen)
                }
                if let target = reconnectTarget, seen.id == target {
                    reconnectTarget = nil
                    connect(seen)
                    return
                }
            }
        }
    }

    /// Reuse the existing `connect(_:)` path once the saved peripheral is seen (or immediately
    /// if this scan already listed it).
    func reconnect(to id: UUID) {
        if case .live = phase, connectedCamera?.id == id, !sessionRecovery.isRecovering {
            return
        }
        if let camera = found.first(where: { $0.id == id }) {
            connect(camera)
            return
        }
        startScan(reconnect: id)
    }

    func connect(_ camera: FoundCamera) {
        connect(camera, preserveMonitor: holdsMonitor)
    }

    private func connect(_ camera: FoundCamera, preserveMonitor: Bool) {
        let camera = camera.enriched(
            from: SavedCameraStore.load().first { $0.id == camera.id })
        if case .live = phase, connectedCamera?.id == camera.id, !sessionRecovery.isRecovering {
            return
        }
        // One `run` at a time. A second tap (or Cancel→tap) used to leave the old
        // unstructured Task sending 0x07/45 while the new one started GetSSID.
        connectGeneration += 1
        let generation = connectGeneration
        scanTask?.cancel()
        abortInFlightRun(preserveDecoder: preserveMonitor)
        reconnectTarget = nil
        isReconnecting = preserveMonitor
        connectedCamera = camera
        phase = .connectingGatt
        runTask = Task {
            defer {
                if generation == connectGeneration { runTask = nil }
            }
            do { try await run(camera) }
            catch is CancellationError { return }
            catch {
                guard generation == connectGeneration else { return }
                if Task.isCancelled { return }
                if case .idle = phase { return }   // user already hit Disconnect
                if preserveMonitor {
                    log.info(
                        "session: recovery attempt failed \(error.localizedDescription, privacy: .public)"
                    )
                    return
                }
                phase = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
                applyLinkPresentation()
            }
        }
    }

    func disconnect() {
        connectGeneration += 1
        reconnectTarget = nil
        isReconnecting = false
        cancelSessionRecovery()
        holdsMonitor = false
        scanTask?.cancel()
        abortInFlightRun()
        connectedCamera = nil
        phase = .idle
        statusFlushTask?.cancel()
        statusFlushTask = nil
        statusStorage = CameraStatus()
        publishStatusNow()
        lastLoggedExpo = nil
        lastLoggedZoomRaw = nil
        lastZoomLogAt = .distantPast
        lastFirstPictureLogAt = .distantPast
        lastFirstPictureSignature = ""
        inflight.removeAll()
        inflightPending.removeAll()
        coalesceScheduled.removeAll()
        lateWait.removeAll()
        setMailbox.reset()
        audioTail = nil
        tapFocusTask?.cancel()
        tapFocusTask = nil
        faceAFArmTask?.cancel()
        faceAFArmTask = nil
        faceAFArmed = false
        firstPictureSettled = false
        restoreDLog2OnWide = false
        teleColorSent = false
        zoomStop = 1
        zoomStopTouched = false
        zoomPinchPreview = nil
        zoomOptimistic = nil
        zoomPinchAnchor = 1
        lastPinchLens = nil
        lastPinchLogTenths = nil
        zoomPinchSlew = nil
        expoPin = nil
        expoGeneration = 0
        audioPin = nil
        formatPin = nil
        colorPin = nil
        controlBusy = false
        controlNote = nil
        focusPoint = CGPoint(x: 0.5, y: 0.5)
        stopTrackingPoll()
        searchBox = nil
        subjectBox = nil
        isTracking = false
        trackingSawLock = false
        lastOperatorClearAt = nil
        lastLiveTrackingAt = nil
        lastSubjectPushAt = nil
        lastFaceAt = nil
        lastFaceHitAt = nil
        lastTapFocusAt = nil
        faceTarget = nil
        faceBox = nil
        faceTracks = []
        sceneFaces = []
        lastFacePriorityEVAt = .distantPast
        facePriorityAcquireAt = nil
        isLocked = false
        stopGimbalStickPump()
        pendingGimbalAxes = nil
        gimbalStickHeld = false
        lastGimbalStickAt = nil
        videoPackets = 0; accessUnits = 0; framesEnqueued = 0
        droppedIncomplete = 0; decoderErrors = 0; hasVideoFormat = false
        nalTypes = ""; lastKeyframeAge = "—"
        liveViewEnableSent = false
        liveViewEnableSends = 0
        idrHoldEnableCount = 0
        audioRefreshPending = false
        glamourClearPending = false
        focusTrackPending = false
        needsForegroundRecover = false
        resetLinkHealthMeasurements()
        resetFeedWatchdog()
        resetMediaSession()
    }

    func forgetWifiCreds(for camera: SavedCamera) {
        CameraWifiKeychain.delete(
            cameraId: camera.id,
            advertisedName: camera.advertisedName,
            lastSSID: camera.lastSSID
        )
        if connectedCamera?.id == camera.id || cachedWifiCameraId == camera.id {
            cachedSSID = nil
            cachedPassword = nil
            cachedWifiCameraId = nil
        }
    }

    /// Tear down an in-flight `run` without resetting UI phase. BLE disconnect
    /// resumes a pending `ble.connect` so the old Task cannot keep writing 0x07/45.
    private func abortInFlightRun(preserveDecoder: Bool = false, preserveSoftAP: Bool = false) {
        runTask?.cancel()
        runTask = nil
        keepaliveLoop?.cancel(); frameRouter?.cancel()
        failAllWaiters(Fail.disconnected)
        pairingHold.removeAll()
        inflight.removeAll()
        inflightPending.removeAll()
        coalesceScheduled.removeAll()
        lateWait.removeAll()
        setMailbox.reset()
        commandTimeoutsAt.removeAll()
        stopGimbalStickPump()
        pendingGimbalAxes = nil
        gimbalStickHeld = false
        lastGimbalStickAt = nil
        disposeDatalink(); ble.disconnect()
        liveViewEnableSent = false
        liveViewEnableSends = 0
        idrHoldEnableCount = 0
        audioRefreshPending = false
        glamourClearPending = false
        focusTrackPending = false
        faceAFArmTask?.cancel()
        faceAFArmTask = nil
        faceAFArmed = false
        firstPictureSettled = false
        needsForegroundRecover = false
        resetFeedWatchdog()
        resetMediaSession()
        if preserveDecoder {
            decoder.flushForRecovery()
        } else {
            decoder.reset()
        }
        if !preserveSoftAP, let ssid = joinedSSID {
            WiFiJoiner.leave(ssid: ssid)
            joinedSSID = nil
        }
    }

    // ---- the flow --------------------------------------------------------------------------------

    private func run(_ camera: FoundCamera) async throws {
        var timeline = ConnectTimeline(now: ProcessInfo.processInfo.systemUptime)
        connectedCamera = camera
        rawAccessUnits = 0; rawFramesEnqueued = 0
        lastIdrRequest = Date.distantPast
        liveViewEnableSent = false
        liveViewEnableSends = 0
        idrHoldEnableCount = 0
        audioRefreshPending = true
        glamourClearPending = true
        focusTrackPending = true
        faceAFArmTask?.cancel()
        faceAFArmTask = nil
        faceAFArmed = false
        firstPictureSettled = false
        needsForegroundRecover = false
        resetLinkHealthMeasurements()
        resetFeedWatchdog()
        decoder.reset()
        // Camera is still pushing the last GOP. Hold before UDP opens so
        // leftover P-frames cannot set lastPresentedAt and skip first-picture.
        decoder.beginIDRHold()
        phase = .connectingGatt
        try await ble.connect(camera)
        timeline.mark("gatt", now: ProcessInfo.processInfo.systemUptime)
        try Task.checkCancellation()
        startFrameRouter()

        // Pair. Wake first (like Mimo), then SetPairingPIN.
        // First-time pairing shows Approve on the camera and may hold the 0x45 reply
        // until the user taps — an 8 s wait dies on "Pairing…" as "stopped responding"
        // while the camera is still waiting. 0x46 can also arrive before 0x45.
        pairingHold.removeAll()
        phase = .pairing
        ble.send(Commands.sessionWake())
        ble.send(Commands.setPairingPin(pin: camera.model.pairingToken))
        phase = .awaitingApproval
        do {
            try await completePairing()
        } catch Fail.timeout {
            throw Fail.pairingTimeout
        }
        timeline.mark("pair", now: ProcessInfo.processInfo.systemUptime)

        // After pairing the camera is still dismissing Approve / bringing the AP up.
        // Mimo waits ~100 ms then 0x53/0x10, then ~800 ms more before GetSSID.
        // Asking immediately races the 0x46 ACK and comes back empty or silent.
        // Keepalive must start now — an idle paired link dies in ~5–6 s, and the
        // old 8 s one-shot wait died as "stopped responding" for the same reason
        // pairing used to. Warm path (SoftAP still up + cached creds) skips the
        // settle sleeps; 0x53/0x10 still goes out.
        startKeepalive(ssid: nil)
        phase = .readingWifiCreds
        let skipAPSettle =
            WiFiJoiner.isCameraPathReady() && resolvedWifiCreds(for: camera).skipBle
        if !skipAPSettle {
            try await Task.sleep(for: .milliseconds(200))
        }
        log.info("creds: sending 0x53/0x10 (wake AP)")
        ble.send(Commands.session5310())
        do {
            _ = try await waitFrame(0x53, 0x10, timeout: .seconds(2))   // Pocket 3 may answer e0
        } catch Fail.timeout {
            log.info("creds: 0x53/0x10 no reply — continuing (Pocket 3 often answers e0/silent)")
        } catch Fail.disconnected {
            throw Fail.disconnectedDuring("0x53/0x10")
        }
        if !skipAPSettle {
            try await Task.sleep(for: .milliseconds(600))
        }
        try Task.checkCancellation()
        let (ssid, pass) = try await wifiCredsAfterPairing(camera)
        try assertSSIDBelongs(to: camera, ssid: ssid)
        log.info("creds: SSID \(ssid, privacy: .public) (\(pass.count) char password) body=\(camera.model.name, privacy: .public)")
        let persistHotspot = CameraSoftAP.shouldPersistHotspot(
            isSavedCamera: SavedCameraStore.load().contains { $0.id == camera.id }
                || cachedWifiCameraId == camera.id)
        persistWifiCreds(camera: camera, ssid: ssid, password: pass)

        phase = .joiningWifi
        // Both SoftAPs are 192.168.2.1. Do not wait for that subnet to vanish —
        // iOS stays associated until we apply the Nano (or Pocket) hotspot.
        let otherSSIDs = leftoverSoftAPSSIDs(besides: ssid)
        log.info(
            "wifi: switch to \(ssid, privacy: .public) kicking \(otherSSIDs.joined(separator: ","), privacy: .public)"
        )
        try await WiFiJoiner.joinCameraAP(
            ssid: ssid, passphrase: pass, wpa3: camera.model.wpa3,
            knownOtherSSIDs: otherSSIDs, persist: persistHotspot)
        joinedSSID = ssid
        timeline.mark("path", now: ProcessInfo.processInfo.systemUptime)

        phase = .openingDatalink
        let existing = datalink
        let dl: DatalinkDriver
        if let existing, CameraSoftAP.shouldReuseDatalink(isClosed: existing.isClosed) {
            dl = existing
        } else {
            dl = DatalinkDriver(port: UInt16(camera.model.datalinkPort),
                                tcpPoke: camera.model.tcpPoke,
                                pairingToken: camera.model.pairingToken)
            wireDatalink(dl)
            datalink = dl
        }
        // Handshake first (yesterday's working order). Mounting LiveView
        // before `open()` starved the UDP reader / ACK latch.
        try await openDatalinkKeepingLive(dl)
        timeline.mark("hs", now: ProcessInfo.processInfo.systemUptime)
        if liveViewEnableSent {
            timeline.mark("enable", now: ProcessInfo.processInfo.systemUptime)
        }
        log.info("\(timeline.line(), privacy: .public)")
        startKeepalive(ssid: ssid)
    }

    /// SoftAP still `192.168.2.x` after a handshake miss: rebind UDP and try
    /// again. Do not set `.failed` — that pops the operator back to pairing.
    private func openDatalinkKeepingLive(_ dl: DatalinkDriver) async throws {
        if !CameraSoftAP.shouldReuseDatalink(isClosed: dl.isClosed) {
            throw CancellationError()
        }
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                try await dl.open { [self] in
                    guard shouldCommitLiveHandshake(dl) else { return }
                    phase = .live
                    applyLinkPresentation()
                    decoder.beginIDRHold()
                    // Do not wait for the layer. First boot spends ~2 s here
                    // while P-frames pile up; 0x09/0xa8 must follow subscribe
                    // immediately so the IDR lands. Handshake is path proof —
                    // do not re-check getifaddrs (that flicker skipped enable).
                    sendInitialLiveViewEnable(
                        displayAttached: decoder.isDisplayReady, pathProven: true)
                }
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let pathReady = WiFiJoiner.isCameraPathReady()
                if CameraSoftAP.shouldKickAfterHandshakeTimeout(pathReady: pathReady) {
                    throw error
                }
                attempt += 1
                if CameraSoftAP.shouldGiveUpOpenRetry(attempts: attempt) {
                    log.info("session: handshake give-up after \(attempt) opens")
                    throw error
                }
                log.info("session: handshake miss #\(attempt) — SoftAP up, retry (no kick)")
                try? await Task.sleep(for: .milliseconds(CameraSoftAP.handshakeRetryPauseMilliseconds))
            }
        }
    }

    // ---- BLE frame routing -----------------------------------------------------------------------

    private func startFrameRouter() {
        frameRouter?.cancel()
        frameRouter = Task {
            for await frame in ble.frames {
                lastBleNotifyAt = Date()
                route(frame)
            }
            failAllWaiters(Fail.disconnected)   // BLE dropped; don't sit on a command timeout
            if case .live = phase {
                beginSessionRecovery(reason: "BLE dropped")
            }
        }
    }

    private func route(_ frame: Duml.Frame) {
        // First-time pairing approval arrives as a request; answer it or the camera drops the link.
        if frame.cmdSet == 0x07, frame.cmdId == 0x46, frame.flags == Duml.flagRequest {
            ble.send(Commands.pairApprovalAck(seq: frame.seq))
        }
        let key = Duml.opcodeKey(set: frame.cmdSet, cmd: frame.cmdId)
        if let waiter = waiters[key] {
            noteControlAck(frame, decision: "match")
            for k in waiter.keys { waiters.removeValue(forKey: k) }
            waiter.resume(returning: frame)
            return
        }
        if isLiveControlOpcode(frame) {
            routeLiveControlAck(frame, key: key)
            return
        }
        if shouldHold(frame) {
            pairingHold[key] = frame
            return
        }
    }

    /// Late BLE ACKs for the open seq are success. Superseded / flood seqs drop.
    /// Live-control replies are never parked in `pairingHold` (no chip replay).
    private func routeLiveControlAck(_ frame: Duml.Frame, key: UInt16) {
        switch setMailbox.decideAck(key: key, seq: frame.seq) {
        case .accept:
            commandTimeoutsAt.removeAll()   // an ACK landed — the uplink works
            noteControlAck(frame, decision: "inflight")
            if let send = inflight.removeValue(forKey: key) {
                finishInflight(send, key: key, reply: frame, late: false)
            } else if let send = lateWait.removeValue(forKey: key) {
                finishInflight(send, key: key, reply: frame, late: true)
            }
        case .acceptLate:
            commandTimeoutsAt.removeAll()   // late, but it landed — uplink works
            noteControlAck(frame, decision: "late")
            inflight[key] = nil
            if let send = lateWait.removeValue(forKey: key) {
                finishInflight(send, key: key, reply: frame, late: true)
            }
        case .dropSuperseded:
            noteControlAck(frame, decision: "superseded")
        case .dropUnknown:
            noteControlAck(frame, decision: "drop")
        }
    }

    private func isLiveControlOpcode(_ frame: Duml.Frame) -> Bool {
        Duml.isLiveCameraControl(set: frame.cmdSet, cmd: frame.cmdId)
    }

    private func noteControlAck(_ frame: Duml.Frame, decision: String) {
        let opcode = String(format: "0x%02X/0x%02X", frame.cmdSet, frame.cmdId)
        ControlLiveLog.line(
            "control: ack \(opcode) seq=\(frame.seq) flags=0x\(String(frame.flags, radix: 16)) payload=\(Duml.hex(frame.payload)) decision=\(decision) reply=\(Duml.isCommandReply(frame.flags))"
        )
    }

    /// Success is `0x07/0x45` `[00 01]` (already paired) or a `0x07/0x46` approval
    /// request (ACKed in `route()`). `[00 02]` means keep waiting for `0x46`.
    private func completePairing() async throws {
        let frame = try await waitFrame(matching: [(0x07, 0x45), (0x07, 0x46)], timeout: .seconds(90))
        if frame.cmdSet == 0x07, frame.cmdId == 0x45,
           frame.payload.count >= 2, frame.payload[1] == 0x02 {
            _ = try await waitFrame(0x07, 0x46, timeout: .seconds(90))
        }
    }

    func waitFrame(
        _ set: UInt8, _ cmd: UInt8,
        timeout: Duration = .seconds(8),
        consumeHold: Bool = true,
        send: (() -> Void)? = nil
    ) async throws -> Duml.Frame {
        try await waitFrame(matching: [(set, cmd)], timeout: timeout, consumeHold: consumeHold, send: send)
    }

    private func waitFrame(
        matching cmds: [(UInt8, UInt8)],
        timeout: Duration,
        consumeHold: Bool = true,
        send: (() -> Void)? = nil
    ) async throws -> Duml.Frame {
        let keys = Set(cmds.map { Duml.opcodeKey(set: $0.0, cmd: $0.1) })
        if consumeHold {
            for (set, cmd) in cmds {
                let key = Duml.opcodeKey(set: set, cmd: cmd)
                if let held = pairingHold.removeValue(forKey: key) { return held }
            }
        } else {
            // A stale ACK from a previous write must not satisfy this SET.
            for key in keys { pairingHold.removeValue(forKey: key) }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                for key in keys {
                    if let old = waiters.removeValue(forKey: key) {
                        for k in old.keys { waiters.removeValue(forKey: k) }
                        old.resume(throwing: Fail.timeout)
                    }
                }
                let waiter = FrameWaiter(keys: keys, continuation: cont)
                for key in keys { waiters[key] = waiter }
                // Register first, then write — `async let` on MainActor sent before the waiter existed.
                send?()
                // Detached so a MainActor flood cannot delay the timeout clock
                // (Audio GET then wedged Record / zoom).
                Task.detached { [weak self] in
                    try? await Task.sleep(for: timeout)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        guard let stuck = keys.lazy.compactMap({ self.waiters[$0] }).first, stuck === waiter else { return }
                        for k in stuck.keys { self.waiters.removeValue(forKey: k) }
                        stuck.resume(throwing: Fail.timeout)
                    }
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let stuck = keys.lazy.compactMap({ self.waiters[$0] }).first else { return }
                for k in stuck.keys { self.waiters.removeValue(forKey: k) }
                stuck.resume(throwing: CancellationError())
            }
        }
    }

    private func failAllWaiters(_ error: Error) {
        let pending = waiters
        waiters.removeAll()
        var seen = Set<ObjectIdentifier>()
        for waiter in pending.values {
            guard seen.insert(ObjectIdentifier(waiter)).inserted else { continue }
            waiter.resume(throwing: error)
        }
    }

    private final class FrameWaiter {
        let keys: Set<UInt16>
        private var continuation: CheckedContinuation<Duml.Frame, Error>?
        init(keys: Set<UInt16>, continuation: CheckedContinuation<Duml.Frame, Error>) {
            self.keys = keys
            self.continuation = continuation
        }
        func resume(returning frame: Duml.Frame) {
            continuation?.resume(returning: frame)
            continuation = nil
        }
        func resume(throwing error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    // ---- Camera control (Osmosis §10–14) ---------------------------------------------------------

    var currentShootingMode: ShootingMode? {
        guard (0...255).contains(status.shootingMode) else { return nil }
        return ShootingMode(rawValue: UInt8(status.shootingMode))
    }

    /// Rec lamp: start/stop video, or fire a still in Photo / SuperNight.
    /// The rec button stays disabled (`controlBusy`) until the ACK or the
    /// `rec_state` telemetry confirms — record must never lie.
    func pressShutter() {
        if currentShootingMode?.isPhoto == true {
            controlBusy = true
            fireCamera(
                Commands.shootPhoto(), name: "Photo", retransmits: false,
                onSettle: { [weak self] _ in self?.controlBusy = false })
            return
        }
        let starting = !status.isRecording
        controlBusy = true
        fireCamera(
            starting ? Commands.recordStart() : Commands.recordStop(),
            name: starting ? "Record" : "Stop",
            expect: .recording(starting),
            onSettle: { [weak self] _ in self?.controlBusy = false }
        )
    }

    func setShootingMode(_ mode: ShootingMode) {
        let previous = status.shootingMode
        status.shootingMode = Int(mode.rawValue)
        fireCamera(Commands.setShootingMode(mode), name: mode.label, onFail: { [weak self] in
            self?.status.shootingMode = previous
        })
    }

    func setIsoLimit(_ limit: IsoLimit) {
        let previous = status.isoLimit
        status.isoLimit = limit
        let base = status.colorMode?.isoAutoBase ?? 100
        fireCamera(
            Commands.setIsoLimit(limit), name: "ISO \(limit.label(base: base))",
            onFail: { [weak self] in self?.status.isoLimit = previous },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "iso: limit \(limit.label(base: base)) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    /// Snapshot EV on enable; restore it (or 0.0) on disable.
    func setFacePriorityEnabled(_ on: Bool) {
        if on {
            evBeforeFacePriority = status.evComp ?? .zero
            return
        }
        let restore = FacePriorityExposure.restoreEV(saved: evBeforeFacePriority)
        evBeforeFacePriority = nil
        lastFacePriorityEVAt = .distantPast
        facePriorityAcquireAt = nil
        guard status.expoMode == .auto, status.evComp != restore else { return }
        setEv(restore)
        ControlLiveLog.line("ev: face-priority off → \(restore.label)")
    }

    func setEv(_ ev: EvComp) {
        let previous = status.evComp
        pinExpo(ev: ev)
        status.evComp = ev
        fireCamera(
            Commands.setEv(ev), name: "EV \(ev.label)", expect: .ev(ev),
            coalesce: true,
            onFail: { [weak self] in
                self?.clearExpoPin(ev: true)
                self?.status.evComp = previous
            },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "ev: SET \(ev.label) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    func refreshIsoLimit() async {
        guard IsoLimit.shouldGet(colorMode: status.colorMode) else { return }
        enqueueAudio {
            _ = await self.requestCamera(Commands.getIsoLimit(), name: "ISO limit GET")
        }
        await audioTail?.value
    }

    func setFov(_ fov: FovSetting) {
        fireCamera(Commands.setFov(fov), name: "FOV \(fov.label)")
    }

    func setExpoMode(_ mode: ExpoMode) {
        pinExpo(mode: mode)
        fireCamera(
            Commands.setExpoMode(mode), name: "ExpoMode", expect: .expo(mode),
            onFail: { [weak self] in self?.clearExpoPin(mode: true) })
    }

    /// Journal `cam_expo_param` only when decoded fields move (not every 1–5 Hz push).
    /// Compared to last journaled snapshot, not `status` — SET ACK may optimistic-update mode.
    private func noteExpoIfChanged(_ new: CameraStatus) {
        let snap = (new.expoMode, new.iso, new.shutterDenom, new.evComp)
        if lastLoggedExpo?.0 == snap.0, lastLoggedExpo?.1 == snap.1,
           lastLoggedExpo?.2 == snap.2, lastLoggedExpo?.3 == snap.3
        {
            return
        }
        if snap.0 == nil, snap.1 < 0, snap.2 < 0, snap.3 == nil { return }
        lastLoggedExpo = snap
        let mode = snap.0?.label ?? "?"
        let iso = snap.1 >= 0 ? "\(snap.1)" : "?"
        let shutter = snap.2 >= 0 ? "1/\(snap.2)" : "?"
        let ev = snap.3?.label ?? "?"
        ControlLiveLog.line("expo: mode=\(mode) iso=\(iso) shutter=\(shutter) ev=\(ev)")
    }

    /// Chip label. Pinch preview, then the chip-tap target, then `cam_fov`.
    var zoomReadout: Double {
        CamFov.readout(
            live: status.zoomFactor, preview: zoomPinchPreview, fallback: zoomStop,
            optimistic: zoomOptimistic)
    }

    private func noteZoomIfChanged(_ new: CameraStatus) {
        guard new.zoomFactorRaw != lastLoggedZoomRaw || new.zoomLens != lastLoggedZoomLens else {
            return
        }
        lastLoggedZoomRaw = new.zoomFactorRaw
        lastLoggedZoomLens = new.zoomLens
        guard new.zoomFactorRaw > 0 || new.zoomLens != nil else { return }
        if let factor = new.zoomFactor {
            if let optimistic = zoomOptimistic, CamFov.matches(factor, optimistic) {
                zoomOptimistic = nil
            }
            if !zoomStopTouched {
                if abs(factor - CamFov.maxFactor) < 0.15 { zoomStop = 12 }
                else if abs(factor - 6) < 0.2 { zoomStop = 6 }
                else if abs(factor - 3) < 0.2 { zoomStop = 3 }
                else if factor < 2.5 { zoomStop = 1 }
            }
        }
        let now = Date()
        guard now.timeIntervalSince(lastZoomLogAt) >= 0.5 else { return }
        lastZoomLogAt = now
        let label = new.zoomFactor.map { CamFov.displayLabel(factor: $0) }
            ?? CamFov.displayLabel(raw: new.zoomFactorRaw)
        let lens = new.zoomLens.map { " lens=\($0)" } ?? ""
        ControlLiveLog.line("zoom: cam_fov @0=\(new.zoomFactorRaw)\(lens) \(label)")
    }

    /// Pinch HUD (0.1×) + slider (every distinct lens tick, ~20 Hz latest-wins).
    /// Gesture owns the chip until lift; cam_fov does not re-anchor mid-pinch.
    func updateZoomPinch(magnification: Double) {
        if zoomPinchPreview == nil {
            zoomPinchAnchor = status.zoomFactor ?? zoomOptimistic ?? zoomStop
            zoomPinchSlew = nil
            zoomOptimistic = nil
            lastPinchLens = nil
            lastPinchLogTenths = nil
        }
        let factor = CamFov.pinchFactor(anchor: zoomPinchAnchor, magnification: magnification)
        let first = zoomPinchPreview == nil
        if first { dropDLog2ForZoom(factor) }
        zoomPinchPreview = factor
        let lens = CamFov.pinchLens(for: factor)
        if lastPinchLens == lens { return }
        lastPinchLens = lens
        if first && abs(factor - zoomPinchAnchor) < 0.01 { return }
        applyPinchWrite(preview: factor)
    }

    func endZoomPinch() {
        zoomPinchSlew = nil
        if let preview = zoomPinchPreview {
            markZoomStop(preview)
            restoreDLog2IfNeeded(afterZoom: preview)
        }
        zoomPinchPreview = nil
    }

    /// Cycle button. 1× / 3× / 6× / 12× are sliders (217 / 651 / 1302 / 2604).
    func setZoom(_ factor: Double) {
        let from = CamFov.displayLabel(factor: zoomReadout)
        let to = CamFov.displayLabel(factor: factor)
        ControlLiveLog.line("zoom: setZoom \(from) → \(to) locked=\(isLocked) live=\(datalink != nil)")
        guard !isLocked else {
            controlNote = "Zoom locked"
            return
        }
        guard let write = CamFov.chipWrite(forJump: factor) else {
            controlNote = "Zoom \(to) — no command"
            ControlLiveLog.line("zoom: tap ignored — no write for \(to)")
            return
        }
        zoomPinchPreview = nil
        zoomPinchSlew = nil
        dropDLog2ForZoom(factor)
        zoomOptimistic = factor
        markZoomStop(factor)
        controlNote = "Zoom \(to)"
        fireZoom(write, target: factor, announce: true)
    }

    /// Pinch hybrid: `0A 4E` + unquantized lens. Coalesces to the newest tick.
    func setZoomSlider(_ factor: Double) {
        let position = CamFov.pinchLens(for: factor)
        let tenths = CamFov.displayTenths(factor)
        if lastPinchLogTenths != tenths {
            lastPinchLogTenths = tenths
            ControlLiveLog.line(
                "zoom: setZoomSlider \(CamFov.displayLabel(factor: factor)) lens=\(position) locked=\(isLocked) live=\(datalink != nil)"
            )
        }
        guard !isLocked else {
            controlNote = "Zoom locked"
            return
        }
        zoomPinchSlew = nil
        fireZoom(.lens(position), target: tenths, announce: false)
    }

    /// Directional slew. 100 toward 12×; 300 from 12× to the 9.15× detent.
    func setZoomSlew(_ value: UInt16) {
        let to = value == CamFov.slewTele ? 12.0 : value == CamFov.slewWide ? CamFov.slewDetent : 0
        ControlLiveLog.line(
            "zoom: setZoomSlew \(value) locked=\(isLocked) live=\(datalink != nil)"
        )
        guard !isLocked else {
            controlNote = "Zoom locked"
            return
        }
        fireZoom(.slew(value), target: to > 0 ? to : nil, announce: false)
    }

    /// Older takes sent `FF 00 00 00` after a `03 00` slew. Newer recapture omitted
    /// it (camera may ignore). Same opcode as the slew, so the per-opcode queue
    /// keeps it from overtaking.
    func setZoomStop() {
        ControlLiveLog.line(
            "zoom: setZoomStop locked=\(isLocked) live=\(datalink != nil)"
        )
        guard !isLocked else { return }
        let frame = Commands.setZoomStop()
        fireCamera(frame, name: "Zoom stop", onSettle: { [weak self] ok in
            ControlLiveLog.line(
                "zoom: SET \(Duml.hex(frame.payload)) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
        })
    }

    private func markZoomStop(_ factor: Double) {
        zoomStop = factor
        zoomStopTouched = true
    }

    private func applyPinchWrite(preview: Double) {
        setZoomSlider(preview)
    }

    /// Chip tap is urgent. Slider / pinch pipelines at 20 Hz without waiting
    /// for ACK (Mimo). D-Log2→D-Log is sent first so 0xB8 is not ignored.
    private func fireZoom(_ write: CamFov.ChipWrite, target: Double?, announce: Bool) {
        let frame: Duml.Frame
        let name: String
        switch write {
        case .lens(let position):
            frame = Commands.setZoomLens(position)
            name = target.map { "Zoom \(CamFov.displayLabel(factor: $0))" } ?? "Zoom slider"
        case .slew(let value):
            frame = Commands.setZoomSlew(value)
            name = target.map { "Zoom \(CamFov.displayLabel(factor: $0))" }
                ?? (value == CamFov.slewTele ? "Zoom 1×" : value == CamFov.slewWide ? "Zoom 3×" : "Zoom slew")
        }
        fireCamera(
            frame, name: name,
            expect: announce ? target.map { .zoom($0) } : nil,
            retransmits: announce,
            coalesce: !announce,
            onSettle: { [weak self] ok in
                guard let self else { return }
                if ok, announce { self.controlNote = name }
                ControlLiveLog.line(
                    "zoom: SET \(Duml.hex(frame.payload)) ack=\(ok ? "ok" : (self.controlNote ?? "failed"))")
            })
    }

    /// D-Log native 400 ↔ D-Log2 native 1600 when the operator is still on base.
    private func hopNativeISO(from: ColorMode?, to: ColorMode) {
        guard let next = CamCapIso.nativeISOHop(
            from: from, to: to, current: status.isoIndex,
            hopEnabled: OperatorPrefs.nativeISOHopEnabled)
        else { return }
        ControlLiveLog.line(
            "iso: native hop \(from?.label ?? "?") → \(to.label) \(status.isoIndex?.label ?? "?") → \(next.label)"
        )
        setISO(next)
    }

    /// D-Log2 rejects every zoom SET. Hop to D-Log on the first pinch / chip,
    /// before `0xB8`, and restore only when parked back at 1×.
    private func dropDLog2ForZoom(_ factor: Double) {
        guard let next = CamFov.colorMode(forZoom: factor, current: status.colorMode) else {
            restoreDLog2IfNeeded(afterZoom: factor)
            return
        }
        sendZoomColorOnce(next)
    }

    private func sendZoomColorOnce(_ next: ColorMode) {
        guard !teleColorSent else { return }
        teleColorSent = true
        restoreDLog2OnWide = true
        let from = status.colorMode
        status.colorMode = next
        colorPin = (next, Date().addingTimeInterval(2))
        controlNote = "D-Log — D-Log2 cannot zoom"
        fireCamera(
            Commands.setColorMode(next), name: "D-Log (zoom)", expect: .color(next),
            onFail: { [weak self] in
                self?.colorPin = nil
                self?.restoreDLog2OnWide = false
                self?.teleColorSent = false
            },
            onSettle: { ok in
                ControlLiveLog.line("zoom: D-Log2 → D-Log ack=\(ok ? "ok" : "failed")")
            })
        hopNativeISO(from: from, to: next)
    }

    private func restoreDLog2IfNeeded(afterZoom factor: Double) {
        guard restoreDLog2OnWide, CamFov.shouldRestoreDLog2(factor: factor) else { return }
        restoreDLog2OnWide = false
        teleColorSent = false
        let from = status.colorMode
        status.colorMode = .dLog2
        colorPin = (.dLog2, Date().addingTimeInterval(2))
        fireCamera(
            Commands.setColorMode(.dLog2), name: "D-Log2", expect: .color(.dLog2),
            onFail: { [weak self] in self?.colorPin = nil },
            onSettle: { [weak self] ok in
                ControlLiveLog.line("zoom: restore D-Log2 on 1× ack=\(ok ? "ok" : "failed")")
                if ok { self?.controlNote = "Zoom 1× · D-Log2" }
            })
        hopNativeISO(from: from, to: .dLog2)
    }

    private struct AudioPin {
        var channel: AudioChannel?
        var vocal: VocalBoost?
        var wind: WindNoiseReduction?
        var directional: DirectionalAudio?
        var deadline: Date
    }

    private struct ExpoPin {
        var generation: UInt64
        var iso: Int?
        var isoIndex: IsoIndex?
        var shutter: Int?
        var ev: EvComp?
        var mode: ExpoMode?
        var deadline: Date
    }

    private enum ControlExpect {
        case iso(IsoIndex)
        case shutter(Int)
        case ev(EvComp)
        case expo(ExpoMode)
        case focus(FocusMode)
        case wb(WhiteBalance)
        case format(VideoFormat)
        case color(ColorMode)
        case zoom(Double)
        /// Record telemetry lags the ACK by ~1 s; the settle window covers it.
        case recording(Bool)

        func confirmed(by status: CameraStatus) -> Bool {
            switch self {
            case .recording(let active):
                return status.isRecording == active
            case .iso(let idx):
                if status.isoIndex == idx { return true }
                if let value = idx.isoValue, status.iso == value { return true }
                return false
            case .shutter(let denom):
                return status.shutterDenom == denom
            case .ev(let ev):
                return status.evComp == ev
            case .expo(let mode):
                return status.expoMode == mode
            case .focus(let mode):
                return status.focusMode == mode
            case .wb(let wb):
                guard status.whiteBalance?.mode == wb.mode else { return false }
                if wb.mode == .auto { return true }
                return status.whiteBalanceKelvin == wb.kelvin
                    && status.whiteBalanceTint == wb.tint
            case .format(let format):
                if status.videoFormat == format { return true }
                return status.videoResolution == format.resolution
                    && status.fps == format.frameRate.fps
            case .color(let mode):
                return status.colorMode == mode
            case .zoom(let factor):
                guard let live = status.zoomFactor else { return false }
                return CamFov.matches(live, factor)
            }
        }
    }

    private func pinAudio(
        channel: AudioChannel? = nil,
        vocal: VocalBoost? = nil,
        wind: WindNoiseReduction? = nil,
        directional: DirectionalAudio? = nil
    ) {
        var pin = audioPin ?? AudioPin(deadline: Date().addingTimeInterval(2))
        pin.deadline = Date().addingTimeInterval(2)
        if let channel { pin.channel = channel }
        if let vocal { pin.vocal = vocal }
        if let wind { pin.wind = wind }
        if let directional { pin.directional = directional }
        audioPin = pin
    }

    private func audioPinIsEmpty(_ pin: AudioPin) -> Bool {
        pin.channel == nil && pin.vocal == nil && pin.wind == nil && pin.directional == nil
    }

    private func clearAudioPin(
        channel: Bool = false, vocal: Bool = false, wind: Bool = false, directional: Bool = false
    ) {
        guard var pin = audioPin else { return }
        if channel { pin.channel = nil }
        if vocal { pin.vocal = nil }
        if wind { pin.wind = nil }
        if directional { pin.directional = nil }
        audioPin = audioPinIsEmpty(pin) ? nil : pin
    }

    /// Drop GET / subscribe snapshots that still show the pre-SET audio row.
    private func absorbStaleAudio(_ incoming: inout CameraStatus) {
        guard var pin = audioPin else { return }
        if Date() >= pin.deadline {
            audioPin = nil
            return
        }
        if let expect = pin.channel {
            if incoming.audioChannel == expect {
                pin.channel = nil
            } else if incoming.audioChannel != nil {
                incoming.audioChannel = status.audioChannel
            }
        }
        if let expect = pin.vocal {
            if incoming.vocalBoost == expect {
                pin.vocal = nil
            } else if incoming.vocalBoost != nil {
                incoming.vocalBoost = status.vocalBoost
            }
        }
        if let expect = pin.wind {
            if incoming.windNR == expect {
                pin.wind = nil
            } else if incoming.windNR != nil {
                incoming.windNR = status.windNR
            }
        }
        if let expect = pin.directional {
            if incoming.directionalAudio == expect {
                pin.directional = nil
            } else if incoming.directionalAudio != nil {
                incoming.directionalAudio = status.directionalAudio
            }
        }
        audioPin = audioPinIsEmpty(pin) ? nil : pin
    }

    private func pinExpo(
        iso: Int? = nil, isoIndex: IsoIndex? = nil, shutter: Int? = nil,
        ev: EvComp? = nil, mode: ExpoMode? = nil
    ) {
        expoGeneration += 1
        var pin = expoPin ?? ExpoPin(generation: expoGeneration, deadline: Date().addingTimeInterval(2))
        pin.generation = expoGeneration
        pin.deadline = Date().addingTimeInterval(2)
        if iso != nil || isoIndex != nil {
            pin.iso = iso
            pin.isoIndex = isoIndex
        }
        if let shutter { pin.shutter = shutter }
        if let ev { pin.ev = ev }
        if let mode { pin.mode = mode }
        expoPin = pin
    }

    private func pinIsEmpty(_ pin: ExpoPin) -> Bool {
        pin.isoIndex == nil && pin.shutter == nil && pin.ev == nil && pin.mode == nil
    }

    private func clearExpoPin(
        iso: Bool = false, shutter: Bool = false, ev: Bool = false, mode: Bool = false
    ) {
        guard var pin = expoPin else { return }
        if iso { pin.iso = nil; pin.isoIndex = nil }
        if shutter { pin.shutter = nil }
        if ev { pin.ev = nil }
        if mode { pin.mode = nil }
        expoPin = pinIsEmpty(pin) ? nil : pin
    }

    /// Drop `cam_expo_param` snapshots that still show the pre-SET ISO / shutter / EV / mode.
    private func absorbStaleExpo(_ incoming: inout CameraStatus) {
        guard var pin = expoPin else { return }
        if Date() >= pin.deadline {
            expoPin = nil
            return
        }
        if let expectIdx = pin.isoIndex {
            let matched = incoming.isoIndex == expectIdx
                || (expectIdx.isoValue.map { incoming.iso == $0 } ?? false)
            if matched {
                pin.isoIndex = nil
                pin.iso = nil
            } else {
                incoming.isoIndex = status.isoIndex
                incoming.iso = status.iso
            }
        }
        if let expectShutter = pin.shutter {
            if incoming.shutterDenom == expectShutter {
                pin.shutter = nil
            } else {
                incoming.shutterDenom = status.shutterDenom
            }
        }
        if let expectEv = pin.ev {
            if incoming.evComp == expectEv {
                pin.ev = nil
            } else {
                incoming.evComp = status.evComp
            }
        }
        if let expectMode = pin.mode {
            if incoming.expoMode == expectMode {
                pin.mode = nil
            } else {
                incoming.expoMode = status.expoMode
            }
        }
        expoPin = pinIsEmpty(pin) ? nil : pin
    }

    private func absorbStaleFormat(_ incoming: inout CameraStatus) {
        guard let pin = formatPin else { return }
        if Date() >= pin.deadline {
            formatPin = nil
            return
        }
        if incoming.videoFormat == pin.expected
            || (incoming.videoResolution == pin.expected.resolution
                && incoming.fps == pin.expected.frameRate.fps)
        {
            formatPin = nil
            return
        }
        incoming.videoFormat = status.videoFormat
        incoming.videoResolution = status.videoResolution
        incoming.fps = status.fps
    }

    private func absorbStaleColor(_ incoming: inout CameraStatus) {
        guard let pin = colorPin else { return }
        if Date() >= pin.deadline {
            colorPin = nil
            return
        }
        if incoming.colorMode == pin.expected {
            colorPin = nil
            return
        }
        incoming.colorMode = status.colorMode
    }

    func setISO(_ index: IsoIndex) {
        pinExpo(iso: index.isoValue, isoIndex: index)
        fireCamera(
            Commands.setIsoIndex(index), name: "ISO \(index.label)", expect: .iso(index),
            coalesce: true,
            onFail: { [weak self] in self?.clearExpoPin(iso: true) },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "iso: SET \(index.label) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    /// Pass `Int` into `Commands.setShutter(denom:)` — `UInt8` cannot encode 1/256 and above.
    /// Manual-expo rides the same socket right before the shutter SET (Mimo never
    /// round-trips between them; the camera applies datagrams in arrival order).
    func setShutterDenom(_ denom: Int) {
        if status.expoMode != .manual {
            pinExpo(mode: .manual)
            fireCamera(
                Commands.setExpoMode(.manual), name: "Manual expo", expect: .expo(.manual),
                onFail: { [weak self] in self?.clearExpoPin(mode: true) })
        }
        pinExpo(shutter: denom)
        fireCamera(
            Commands.setShutter(denom: denom), name: "1/\(denom)", expect: .shutter(denom),
            coalesce: true,
            onFail: { [weak self] in self?.clearExpoPin(shutter: true) },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "shutter: SET 1/\(denom) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    func setWhiteBalanceAuto() {
        fireWhiteBalance(.auto)
    }

    func setWhiteBalanceCustom(kelvin: Int, tint: Int) {
        fireWhiteBalance(.custom(
            kelvin: min(max(kelvin, 2_000), 10_000),
            tint: min(max(tint, -100), 100)
        ))
    }

    private func fireWhiteBalance(_ wb: WhiteBalance) {
        let previous = status.whiteBalance
        let previousKelvin = status.whiteBalanceKelvin
        let previousTint = status.whiteBalanceTint
        status.whiteBalance = wb
        status.whiteBalanceKelvin = wb.mode == .auto ? -1 : wb.kelvin
        status.whiteBalanceTint = wb.mode == .auto ? 0 : wb.tint
        let name = wb.mode == .auto ? "WB Auto" : "WB \(wb.kelvin)K tint \(wb.tint)"
        let frame = wb.mode == .auto
            ? Commands.setWhiteBalanceAuto()
            : Commands.setWhiteBalanceCustom(kelvin: wb.kelvin, tint: wb.tint)
        fireCamera(
            frame, name: name, expect: .wb(wb),
            onFail: { [weak self] in
                guard let self else { return }
                self.status.whiteBalance = previous
                self.status.whiteBalanceKelvin = previousKelvin
                self.status.whiteBalanceTint = previousTint
            },
            onSettle: { [weak self] ok in
                ControlLiveLog.line("wb: SET \(name) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    var supportsTapFocus: Bool { connectedCamera?.model.supportsTapFocus ?? true }
    var supportsFocusMode: Bool { connectedCamera?.model.supportsFocusMode ?? true }

    func setFocusMode(_ mode: FocusMode) {
        guard supportsFocusMode else { return }
        let previous = status.focusMode
        status.focusMode = mode
        fireCamera(
            Commands.setFocusMode(mode), name: "Focus \(mode.label)", expect: .focus(mode),
            onFail: { [weak self] in self?.status.focusMode = previous },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "focus: SET \(mode.label) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    func setFocusTrack(_ track: FocusTrackMode) {
        guard supportsFocusMode else { return }
        let previous = status.focusTrack
        status.focusTrack = track
        lastFocusTrackAt = Date()
        // Same 0x8E waiter as audio / glamour GETs. fireCamera on this opcode
        // lets a GET steal the ACK, retransmit, and trip the feed watchdog.
        enqueueAudio {
            self.lastFocusTrackAt = Date()
            let ok = await self.requestCamera(
                Commands.setFocusTrack(track), name: "AF-C \(track.label)")
            if !ok { self.status.focusTrack = previous }
            ControlLiveLog.line(
                "focus: track \(track.label) ack=\(ok ? "ok" : (self.controlNote ?? "failed"))")
        }
    }

    func setFocusOption(_ option: FocusOption) {
        if option.focusMode == .single {
            setFocusMode(.single)
            return
        }
        if status.focusMode != .continuous {
            setFocusMode(.continuous)
        }
        if let track = option.track {
            setFocusTrack(track)
        }
    }

    func setAudioChannel(_ channel: AudioChannel) {
        pinAudio(channel: channel)
        let previous = status.audioChannel
        status.audioChannel = channel
        enqueueAudio {
            let ok = await self.requestCamera(
                Commands.setAudioChannel(channel), name: "Audio \(channel.label)")
            if !ok {
                if self.status.audioChannel == channel { self.status.audioChannel = previous }
                self.clearAudioPin(channel: true)
            }
            ControlLiveLog.line(
                "audio: channel \(channel.label) ack=\(ok ? "ok" : (self.controlNote ?? "failed"))")
        }
    }

    func setVocalBoost(_ boost: VocalBoost) {
        pinAudio(vocal: boost)
        let previous = status.vocalBoost
        status.vocalBoost = boost
        enqueueAudio {
            let ok = await self.requestCamera(
                Commands.setVocalBoost(boost), name: "Vocal \(boost.label)")
            if !ok {
                if self.status.vocalBoost == boost { self.status.vocalBoost = previous }
                self.clearAudioPin(vocal: true)
            }
            ControlLiveLog.line(
                "audio: vocal \(boost.label) ack=\(ok ? "ok" : (self.controlNote ?? "failed"))")
        }
    }

    /// GET `0xA0` blob, patch `@2`, SET `0x9F`. Never invent the blob. The GET is
    /// a true round trip, so audio patches ride their own chain — never the SET path.
    func setWindNR(_ value: WindNoiseReduction) {
        pinAudio(wind: value)
        status.windNR = value
        enqueueAudio {
            await self.patchAudioDsp(name: "Wind \(value.label)") { AudioDspBlob.patchWind($0, value) }
        }
    }

    func setDirectionalAudio(_ value: DirectionalAudio) {
        pinAudio(directional: value)
        status.directionalAudio = value
        status.windNR = .on
        enqueueAudio {
            await self.patchAudioDsp(name: "Dir \(value.label)") {
                AudioDspBlob.patchDirectional($0, value)
            }
        }
    }

    func refreshFocusTrack() async {
        enqueueAudio {
            _ = await self.requestCamera(Commands.getFocusTrack(), name: "Focus track GET")
        }
        await audioTail?.value
    }

    /// Mimo persists glamour on the camera. GET pid `0x0039` and SET enable `@5 = 00`.
    func clearGlamourIfEnabled() async {
        enqueueAudio {
            let ok = await self.requestCamera(Commands.getGlamour(), name: "Glamour GET")
            guard ok, let blob = self.status.glamourBlob, GlamourEffect.isEnabled(blob),
                let off = GlamourEffect.disabled(blob)
            else { return }
            let previous = self.status.glamourBlob
            self.status.glamourBlob = off
            self.status.glamourEnabled = false
            let setOk = await self.requestCamera(Commands.setGlamour(off), name: "Glamour off")
            if !setOk {
                self.status.glamourBlob = previous
                self.status.glamourEnabled = previous.map(GlamourEffect.isEnabled)
            }
        }
        await audioTail?.value
    }

    func refreshAudioState() async {
        enqueueAudio {
            for (frame, name) in zip(Commands.audioStateGets, ["Audio ch GET", "Vocal GET", "AudioDSP GET"]) {
                _ = await self.requestCamera(frame, name: name)
            }
        }
        await audioTail?.value
    }

    private func enqueueAudio(_ work: @escaping @MainActor () async -> Void) {
        let previous = audioTail
        audioTail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func patchAudioDsp(name: String, patch: ([UInt8]) -> [UInt8]) async {
        let got = await requestCamera(Commands.audioDspGet(), name: "AudioDSP GET")
        guard got, let blob = status.audioDspBlob, blob.count > 2 else {
            controlNote = "\(name): no DSP blob"
            ControlLiveLog.line("audio: \(name) skipped — no GET blob")
            return
        }
        let next = patch(blob)
        let previousBlob = status.audioDspBlob
        let previousAt2 = status.audioDspAt2
        let previousWind = status.windNR
        let previousDir = status.directionalAudio
        status.audioDspBlob = next
        if next.count > 2 {
            AudioDspBlob.applyByte2(next[2], to: &status)
        } else {
            status.audioDspAt2 = AudioDspBlob.at2(next)
        }
        let ok = await requestCamera(Commands.audioDspSet(next), name: name)
        if !ok {
            status.audioDspBlob = previousBlob
            status.audioDspAt2 = previousAt2
            status.windNR = previousWind
            status.directionalAudio = previousDir
            clearAudioPin(wind: true, directional: true)
        }
        ControlLiveLog.line("audio: \(name) ack=\(ok ? "ok" : (controlNote ?? "failed"))")
    }

    /// `0x02/0x18` via `Commands.setVideoFormat(resolution:frameRate:)`.
    func setVideoFormat(resolution: VideoResolution, frameRate: VideoFrameRate) {
        let format = VideoFormat(resolution: resolution, frameRate: frameRate)
        let previousFormat = status.videoFormat
        let previousRes = status.videoResolution
        let previousFps = status.fps
        status.videoResolution = format.resolution
        status.videoFormat = format
        status.fps = format.frameRate.fps
        formatPin = (format, Date().addingTimeInterval(2))
        fireCamera(
            Commands.setVideoFormat(resolution: format.resolution, frameRate: format.frameRate),
            name: format.chipLabel,
            expect: .format(format),
            onFail: { [weak self] in
                guard let self else { return }
                self.status.videoFormat = previousFormat
                self.status.videoResolution = previousRes
                self.status.fps = previousFps
                self.formatPin = nil
            })
        // Angle mode is ours: keep the chosen degrees and rewrite 1/N for the new fps.
        if OperatorPrefs.shutterUsesAngle, previousFps != status.fps, status.expoMode != .auto {
            let denom = ShutterAngle.denom(
                degrees: OperatorPrefs.shutterAngleDegrees,
                fps: status.fps,
                available: status.availableShutterDenoms)
            if denom != status.shutterDenom {
                setShutterDenom(denom)
            }
        }
    }

    var bodyFamily: CameraBodyFamily {
        connectedCamera?.model.family ?? .other
    }

    var colorModes: [ColorMode] {
        CamCapColorMode.wheel(available: status.availableColorModes, family: bodyFamily)
    }

    /// `0x02/0x42` via `Commands.setColorMode`.
    func setColorMode(_ mode: ColorMode) {
        guard colorModes.contains(mode) else { return }
        let from = status.colorMode
        colorPin = (mode, Date().addingTimeInterval(2))
        fireCamera(
            Commands.setColorMode(mode), name: mode.label(for: bodyFamily), expect: .color(mode),
            onFail: { [weak self] in self?.colorPin = nil })
        hopNativeISO(from: from, to: mode)
    }

    /// Stream `0x04/0x01` while the on-screen stick is held. No ACK — do not
    /// ride `fireCamera`. `x`/`y` are −1…1 (right / up); `GimbalStick.encode`
    /// maps that onto tilt/pan.
    func updateGimbalStick(
        x: Double, y: Double, sensitivity: Int = GimbalStick.defaultSensitivity
    ) {
        guard !isLocked else { return }
        guard datalink != nil else { return }
        let axes = GimbalStick.encode(
            x: x, y: y, invertPan: false, sensitivity: sensitivity)
        pendingGimbalAxes = axes
        lastGimbalStickAt = Date()
        if !gimbalStickHeld {
            gimbalStickHeld = true
            sendGimbalStick(axes, log: true)
            startGimbalStickPump()
        }
    }

    /// Stick double-tap (hardware joystick). Wire is Mimo's recenter button:
    /// `0x04/0x4C` `FE 08`. Mimo has no stick double-tap.
    func recenterGimbal() {
        guard !isLocked else { return }
        guard datalink != nil else { return }
        endGimbalStick()
        let frame = Commands.gimbalRecenter()
        let seq = datalink?.send(frame) ?? 0
        ControlLiveLog.line(
            "control: send Gimbal recenter 0x04/0x4C seq=\(seq) flags=0x\(String(frame.flags, radix: 16)) payload=\(Duml.hex(frame.payload)) via=datalink"
        )
        controlNote = "Gimbal re-centered"
    }

    /// Stick triple-tap. Wire is Mimo's flip control: `0x04/0x4C` `FE 09` (toggle).
    func flipGimbal() {
        guard !isLocked else { return }
        guard datalink != nil else { return }
        endGimbalStick()
        let frame = Commands.gimbalFlip()
        let seq = datalink?.send(frame) ?? 0
        ControlLiveLog.line(
            "control: send Gimbal flip 0x04/0x4C seq=\(seq) flags=0x\(String(frame.flags, radix: 16)) payload=\(Duml.hex(frame.payload)) via=datalink"
        )
        switch status.gimbalFace {
        case .selfie: controlNote = "Front"
        case .front: controlNote = "Selfie"
        case nil: controlNote = "Gimbal flipped"
        }
    }

    /// Send center and stop the stream. Always fire — the camera needs rest.
    func endGimbalStick() {
        stopGimbalStickPump()
        pendingGimbalAxes = nil
        if gimbalStickHeld { lastGimbalStickAt = Date() }
        guard gimbalStickHeld else { return }
        gimbalStickHeld = false
        sendGimbalStick((GimbalStick.center, GimbalStick.center), log: true)
    }

    private func startGimbalStickPump() {
        gimbalStickPump?.cancel()
        let interval = GimbalStick.streamInterval
        gimbalStickPump = Task { @MainActor [weak self] in
            let delay = Duration.milliseconds(Int((interval * 1_000).rounded(.up)))
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, self.gimbalStickHeld, !Task.isCancelled else { return }
                let axes = self.pendingGimbalAxes ?? (GimbalStick.center, GimbalStick.center)
                self.sendGimbalStick(axes, log: false)
            }
        }
    }

    private func stopGimbalStickPump() {
        gimbalStickPump?.cancel()
        gimbalStickPump = nil
    }

    private func sendGimbalStick(_ axes: (axis0: UInt16, axis1: UInt16), log: Bool) {
        guard datalink != nil else { return }
        let frame = Commands.gimbalStick(axis0: axes.axis0, axis1: axes.axis1)
        let seq = datalink?.send(frame) ?? 0
        if log {
            ControlLiveLog.line(
                "control: send Gimbal stick 0x04/0x01 seq=\(seq) flags=0x0 payload=\(Duml.hex(frame.payload)) via=datalink"
            )
        }
    }

    /// Feed tap: inside the AF-C face box → ActiveTrack SET with that rect.
    /// Anywhere else → tap-to-focus.
    func handleFeedTap(at normalized: CGPoint) {
        let x = min(max(Double(normalized.x), 0), 1)
        let y = min(max(Double(normalized.y), 0), 1)
        if let box = FaceTrackTap.boxIfTapped(
            overlay: focusOverlay, x: x, y: y, sceneFaces: dimmedFaces)
        {
            startTracking(box)
            return
        }
        switch LiveFeedTapPolicy.action(
            supportsTapFocus: supportsTapFocus, tappedFace: false)
        {
        case .ignore, .trackFace:
            return
        case .tapFocus:
            markFocus(at: CGPoint(x: x, y: y))
        }
    }

    /// Tap-to-focus: Mimo's four-write burst (`0x22` `02`, `0x30` xy, `0x68` `08`,
    /// `0x32` region). Glamour is `0x8E` pid `0x0039`, not `0x68`.
    func markFocus(at normalized: CGPoint) {
        guard supportsTapFocus else { return }
        cancelTracking(sendClear: isTrackingActive)
        // Hold the tap reticle so AF-C face detect cannot hide it immediately.
        lastTapFocusAt = Date()
        faceBox = nil
        faceTarget = nil
        lastFaceHitAt = nil
        let x = Float(min(max(normalized.x, 0), 1))
        let y = Float(min(max(normalized.y, 0), 1))
        focusPoint = CGPoint(x: Double(x), y: Double(y))
        guard datalink != nil else { return }
        tapFocusTask?.cancel()
        tapFocusTask = Task { @MainActor in
            await self.sendTapFocusBurst(x: x, y: y)
        }
    }

    /// Mimo sends `0x22` then `0x30` before either ACK. A second `0x22 [02]`
    /// often has no ACK — waiting 3 s for it starves `0x30` and stalls the feed.
    private func sendTapFocusBurst(x: Float, y: Float) async {
        guard datalink != nil, !Task.isCancelled else { return }
        let prepare = Commands.tapFocusPrepare()
        let seq = datalink?.send(prepare) ?? 0
        ControlLiveLog.line(
            "control: send AE spot 0x02/0x22 seq=\(seq) flags=0x\(String(prepare.flags, radix: 16)) payload=\(Duml.hex(prepare.payload)) via=datalink"
        )
        guard !Task.isCancelled else { return }
        let focused = await requestCamera(
            Commands.tapFocusPoint(x, y), name: "Focus region", timeout: .milliseconds(800))
        guard !Task.isCancelled, focused else { return }
        _ = await requestCamera(
            Commands.tapFocusLiveHint(), name: "AE hint", timeout: .milliseconds(800))
        guard !Task.isCancelled else { return }
        _ = await requestCamera(
            Commands.tapFocusCommit(x, y), name: "Focus", timeout: .milliseconds(800))
    }

    /// Drag-to-track: `0x02/0xA6` centre+size, then poll `0x02/0xA5` until lock or idle.
    func startTracking(_ box: TrackingBox) {
        if box.isTooSmall {
            noteFrameTooSmall()
            return
        }
        stopTrackingPoll()
        lastOperatorClearAt = nil
        lastLiveTrackingAt = nil
        lastSubjectPushAt = nil
        searchBox = box
        subjectBox = nil
        isTracking = false
        trackingSawLock = false
        faceBox = nil
        faceTarget = nil
        lastFaceHitAt = nil
        let id = nextTrackingId
        nextTrackingId &+= 1
        if nextTrackingId == 0 { nextTrackingId = 1 }
        guard datalink != nil else { return }
        fireCamera(
            Commands.setTrackingBox(
                id: id,
                x: Float(box.centerX),
                y: Float(box.centerY),
                width: Float(box.width),
                height: Float(box.height)
            ),
            name: "Track"
        ) { [weak self] ok in
            guard ok else { return }
            self?.beginTrackingPoll()
        }
    }

    func cancelSubjectTracking() {
        cancelTracking(sendClear: true)
    }

    func noteFrameTooSmall() {
        searchBox = nil
        subjectBox = nil
        isTracking = false
        controlNote = "Frame Too Small"
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(ControlHud.toastHoldSeconds))
            guard let self, self.controlNote == "Frame Too Small" else { return }
            self.controlNote = nil
        }
    }

    /// OpenZCine recenter: clear tracking, tap-focus frame centre.
    func resetFocusPoint() {
        guard !isLocked else { return }
        markFocus(at: CGPoint(x: 0.5, y: 0.5))
    }

    var isFocusResetAvailable: Bool {
        FocusResetPolicy.isAvailable(
            x: Double(focusPoint.x),
            y: Double(focusPoint.y),
            tracking: isTrackingActive
        )
    }

    private var isTrackingActive: Bool { isTracking || searchBox != nil || subjectBox != nil }

    private func cancelTracking(sendClear: Bool) {
        stopTrackingPoll()
        let had = isTrackingActive
        searchBox = nil
        subjectBox = nil
        isTracking = false
        trackingSawLock = false
        if sendClear { lastOperatorClearAt = Date() }
        lastLiveTrackingAt = nil
        lastSubjectPushAt = nil
        guard sendClear, had, datalink != nil else { return }
        fireCamera(Commands.clearTrackingBox(), name: "Track clear")
    }

    private func beginTrackingPoll() {
        stopTrackingPoll()
        trackingPollTask = Task { @MainActor [weak self] in
            var idleTicks = 0
            while !Task.isCancelled {
                guard let session = self, session.isTrackingActive else { return }
                session.fireCamera(
                    Commands.pollTracking(), name: "Track poll", retransmits: false)
                try? await Task.sleep(for: .milliseconds(500))
                guard let session = self else { return }
                if session.trackingSawLock,
                    TrackingClearPolicy.shouldDropForSilence(
                        lastPush: session.lastSubjectPushAt, now: Date())
                {
                    session.clearLocalTracking()
                    return
                }
                if session.isTracking {
                    idleTicks = 0
                } else if session.trackingSawLock {
                    session.clearLocalTracking()
                    return
                } else {
                    idleTicks += 1
                    if idleTicks >= 6 {
                        session.clearLocalTracking()
                        return
                    }
                }
            }
        }
    }

    private func stopTrackingPoll() {
        trackingPollTask?.cancel()
        trackingPollTask = nil
    }

    private func clearLocalTracking() {
        searchBox = nil
        subjectBox = nil
        isTracking = false
        lastLiveTrackingAt = nil
        lastSubjectPushAt = nil
        stopTrackingPoll()
    }

    /// Live subject rect. Bypasses the 5 Hz status HUD — Mimo paints this ~15 Hz.
    /// The camera is the source of truth: a body-screen lock starts here, a
    /// body-screen cancel is silence + `0xA5` idle.
    private func applyLiveTrackingPush(_ payload: [UInt8]) {
        guard TrackingClearPolicy.shouldApplyLivePush(
            operatorClearedAt: lastOperatorClearAt, now: Date())
        else { return }
        guard let box = TrackingBox.parseLivePush(payload) else { return }
        lastSubjectPushAt = Date()
        subjectBox = smoothedSubject(toward: box)
        isTracking = true
        trackingSawLock = true
        searchBox = nil
        adoptCameraFocus(x: box.centerX, y: box.centerY, fromTrackingBox: true)
        if trackingPollTask == nil { beginTrackingPoll() }
    }

    private func adoptCameraFocus(x: Double, y: Double, fromTrackingBox: Bool) {
        guard CameraFocusPolicy.shouldAdopt(
            currentX: Double(focusPoint.x), currentY: Double(focusPoint.y),
            cameraX: x, cameraY: y)
        else { return }
        focusPoint = CGPoint(x: x, y: y)
        guard !fromTrackingBox else { return }
        lastTapFocusAt = Date()
        faceBox = nil
        faceTarget = nil
        lastFaceHitAt = nil
    }

    private func absorbCameraFocus(_ s: CameraStatus) {
        guard s.hasCameraFocusPoint, !isTrackingActive else { return }
        adoptCameraFocus(x: s.focusX, y: s.focusY, fromTrackingBox: false)
    }

    private var isFaceSceneMoving: Bool {
        if gimbalStickHeld { return true }
        return FaceTrackHold.isSceneMoving(
            secondsSinceGimbal: lastGimbalStickAt.map { Date().timeIntervalSince($0) })
    }

    private func considerFaceAF(_ buffer: CVPixelBuffer) {
        guard wantsFaceDetect else {
            clearFaceAF()
            return
        }
        let moving = isFaceSceneMoving
        tickFaceBoxes(sceneMoving: moving)
        faceDetector.consider(buffer, rectanglesOnly: moving) { [weak self] result in
            self?.applyDetectedFaces(result.faces)
        }
        tickFacePriority(from: buffer)
    }

    private func tickFaceBoxes(sceneMoving: Bool) {
        let now = Date()
        faceTracks.removeAll {
            FaceTrackHold.shouldDrop(
                secondsSinceHit: now.timeIntervalSince($0.lastHit), sceneMoving: sceneMoving)
        }
        let raw = lastFaceAt.map { now.timeIntervalSince($0) } ?? (1.0 / 25.0)
        lastFaceAt = now
        let dt = min(max(raw, 1.0 / 120.0), 0.08)
        for i in faceTracks.indices {
            faceTracks[i].box = FaceTrackHold.follow(
                from: faceTracks[i].box, toward: faceTracks[i].target, dt: dt,
                sceneMoving: sceneMoving)
        }
        sceneFaces = faceTracks.map(\.box)
        if isTrackingActive {
            faceBox = nil
            return
        }
        let sinceHit = FaceTrackHold.secondsSinceHit(lastHit: lastFaceHitAt, now: now)
        if FaceTrackHold.shouldDrop(secondsSinceHit: sinceHit, sceneMoving: sceneMoving) {
            faceBox = nil
            faceTarget = nil
            lastFaceHitAt = nil
            return
        }
        guard let target = faceTarget else { return }
        faceBox = FaceTrackHold.follow(
            from: faceBox, toward: target, dt: dt, sceneMoving: sceneMoving)
    }

    private func applyDetectedFaces(_ hits: [FaceHit]) {
        guard wantsFaceDetect else {
            clearFaceAF()
            return
        }
        let now = Date()
        let moving = isFaceSceneMoving
        let heads = HeadTrackPolicy.mergeHits(hits)
        let detections = heads.map(\.box)
        let previous = faceTracks.map(\.box)
        let assigned = SceneFacePolicy.assignments(
            detections: detections,
            previous: previous,
            maxCenterDistance: HeadTrackPolicy.jumpDistance)
        var claimed = Set<Int>()
        var next: [FaceTrack] = []
        for (index, track) in faceTracks.enumerated() {
            if let det = assigned[index] {
                var updated = track
                updated.target = detections[det]
                updated.lastHit = now
                next.append(updated)
                claimed.insert(det)
            }
        }
        for (index, hit) in heads.enumerated() where !claimed.contains(index) {
            guard HeadTrackPolicy.shouldSpawn(
                detection: hit.box, existing: next.map(\.box))
            else { continue }
            next.append(FaceTrack(box: hit.box, target: hit.box, lastHit: now))
        }
        faceTracks = next
        sceneFaces = next.map(\.box)
        if isTrackingActive {
            faceBox = nil
            faceTarget = nil
            lastFaceHitAt = nil
            return
        }
        guard wantsFaceAF else {
            faceBox = nil
            faceTarget = nil
            lastFaceHitAt = nil
            return
        }
        applyPrimaryFace(hits: heads, now: now, sceneMoving: moving)
    }

    private func tickFacePriority(from buffer: CVPixelBuffer) {
        guard wantsFacePriorityMeter, !isBrowsingMedia, !status.inPlayback else { return }
        guard case .live = phase else { return }
        let now = Date()
        let boxes: [TrackingBox]
        if !sceneFaces.isEmpty {
            boxes = sceneFaces
        } else if let faceBox {
            boxes = [faceBox]
        } else {
            facePriorityAcquireAt = nil
            return
        }
        if facePriorityAcquireAt == nil {
            facePriorityAcquireAt = now
        }
        let spacing = FacePriorityExposure.interval(
            sinceAcquire: facePriorityAcquireAt, now: now)
        guard now.timeIntervalSince(lastFacePriorityEVAt) >= spacing else { return }
        guard let packed = PocketScopeSampler.copyBGRA(buffer, maxWidth: PocketScopeSampler.maxWidth)
        else { return }
        lastFacePriorityEVAt = now
        let transfer = MonitorTransfer.resolved(
            status.monitorTransfer, colorMode: status.colorMode)
        guard let encoded = FacePriorityExposure.medianEncoded(
            bytes: packed.bytes, width: packed.width, height: packed.height,
            bytesPerRow: packed.bytesPerRow, boxes: boxes, transfer: transfer)
        else { return }
        let current = status.evComp ?? .zero
        guard let next = FacePriorityExposure.nextEV(
            current: current, encoded: encoded, transfer: transfer)
        else { return }
        setEv(next)
        ControlLiveLog.line("ev: face-priority \(current.label) → \(next.label)")
    }

    private func applyPrimaryFace(
        hits: [FaceHit], now: Date, sceneMoving: Bool
    ) {
        let sinceHit = FaceTrackHold.secondsSinceHit(lastHit: lastFaceHitAt, now: now)
        let last = faceTarget ?? faceBox
        let chosen = FaceAFPick.primary(
            hits: hits, hold: nil, last: last,
            secondsSinceHit: sinceHit, sceneMoving: sceneMoving)
        guard let chosen else {
            if FaceTrackHold.shouldDrop(secondsSinceHit: sinceHit, sceneMoving: sceneMoving) {
                faceBox = nil
                faceTarget = nil
                lastFaceHitAt = nil
            }
            return
        }
        lastFaceHitAt = now
        faceTarget = chosen.box
        if faceBox == nil {
            faceBox = chosen.box
        }
    }

    private func clearFaceAF() {
        faceBox = nil
        faceTarget = nil
        lastFaceAt = nil
        lastFaceHitAt = nil
        faceTracks = []
        sceneFaces = []
        facePriorityAcquireAt = nil
    }

    private struct FaceTrack {
        var box: TrackingBox
        var target: TrackingBox
        var lastHit: Date
    }

    private func smoothedSubject(toward box: TrackingBox) -> TrackingBox {
        let now = Date()
        let dt = lastLiveTrackingAt.map { now.timeIntervalSince($0) } ?? .infinity
        lastLiveTrackingAt = now
        return TrackingBoxSmoothing.blend(from: subjectBox, toward: box, dt: dt)
    }

    private func applyTrackingPoll(_ payload: [UInt8]) {
        guard TrackingClearPolicy.shouldApplyLivePush(
            operatorClearedAt: lastOperatorClearAt, now: Date())
        else { return }
        switch TrackingPoll.parse(payload) {
        case .locked(let cameraBox):
            isTracking = true
            trackingSawLock = true
            if let cameraBox {
                subjectBox = smoothedSubject(toward: cameraBox)
            } else if subjectBox == nil, let search = searchBox {
                subjectBox = TrackingBox.subject(from: search)
            }
            searchBox = nil
        case .idle:
            isTracking = false
            if trackingSawLock {
                clearLocalTracking()
            }
        case nil:
            break
        }
    }

    /// One fire-and-forget SET. Latest-wins pending while the same opcode is in flight.
    private final class InflightSend {
        let frame: Duml.Frame
        let name: String
        let opcode: String
        let expect: ControlExpect?
        /// One-shot commands (Photo) must not fire twice on a slow ACK.
        let retransmits: Bool
        /// Slider / wheel: rate-limit and latest-wins. Chip taps are urgent.
        let coalesce: Bool
        let onFail: (@MainActor () -> Void)?
        let onSettle: (@MainActor (Bool) -> Void)?
        var retransmitted = false
        init(
            frame: Duml.Frame, name: String, expect: ControlExpect?, retransmits: Bool,
            coalesce: Bool, onFail: (@MainActor () -> Void)?, onSettle: (@MainActor (Bool) -> Void)?
        ) {
            self.frame = frame
            self.name = name
            self.opcode = String(format: "0x%02X/0x%02X", frame.cmdSet, frame.cmdId)
            self.expect = expect
            self.retransmits = retransmits
            self.coalesce = coalesce
            self.onFail = onFail
            self.onSettle = onSettle
        }
    }

    /// Retransmit after this much ACK silence (Mimo retransmits before ACK too).
    private static let retransmitAfter: Duration = .milliseconds(300)
    /// Give up the waiter and accept a late BLE ACK for the same seq.
    private static let settleAfter: Duration = .seconds(2)

    /// Latest-wins mailbox. Status chips stay on last ACK / subscribe push.
    /// Late BLE ACKs for the open seq are success; superseded seqs drop.
    private func fireCamera(
        _ frame: Duml.Frame, name: String,
        expect: ControlExpect? = nil,
        retransmits: Bool = true,
        coalesce: Bool = false,
        onFail: (@MainActor () -> Void)? = nil,
        onSettle: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard datalink != nil else {
            controlNote = "not live"
            onFail?()
            onSettle?(false)
            return
        }
        if isBrowsingMedia, frame.cmdSet == 0x02, frame.cmdId == 0x8E {
            onSettle?(false)
            return
        }
        controlNote = nil
        let key = Duml.opcodeKey(set: frame.cmdSet, cmd: frame.cmdId)
        pairingHold.removeValue(forKey: key)
        let send = InflightSend(
            frame: frame, name: name, expect: expect, retransmits: retransmits,
            coalesce: coalesce, onFail: onFail, onSettle: onSettle)
        let now = CFAbsoluteTimeGetCurrent()
        switch setMailbox.offer(key: key, urgent: !coalesce, now: now) {
        case .coalescePending:
            inflightPending[key] = send
            if inflight[key] == nil, lateWait[key] == nil {
                scheduleCoalesceLaunch(key)
            } else if CameraSetMailbox.pipelinesWhileOpen(key) {
                scheduleCoalesceLaunch(key)
            }
        case .launch:
            if let abandoned = lateWait.removeValue(forKey: key) {
                abandoned.onSettle?(false)
            }
            inflightPending.removeValue(forKey: key)
            launchInflight(send, key: key)
        }
    }

    private func launchInflight(_ send: InflightSend, key: UInt16) {
        // Pipelined zoom replaces the open send. Do not journal ack=failed —
        // the camera already has a newer slider on the wire.
        inflight[key] = nil
        setMailbox.beginLaunch(key: key, now: CFAbsoluteTimeGetCurrent())
        inflight[key] = send
        transmit(send, kind: "send")
        if send.retransmits {
            watchInflight(send, key: key, after: Self.retransmitAfter) { session, live in
                guard !live.retransmitted else { return }
                live.retransmitted = true
                session.transmit(live, kind: "retransmit")
            }
        }
        watchInflight(send, key: key, after: Self.settleAfter) { session, live in
            session.settleInflightTimeout(live, key: key)
        }
    }

    private func transmit(_ send: InflightSend, kind: String) {
        let seq = datalink?.send(send.frame) ?? 0
        let key = Duml.opcodeKey(set: send.frame.cmdSet, cmd: send.frame.cmdId)
        setMailbox.noteTransmit(key: key, seq: seq)
        ControlLiveLog.line(
            "control: \(kind) \(send.name) \(send.opcode) seq=\(seq) flags=0x\(String(send.frame.flags, radix: 16)) payload=\(Duml.hex(send.frame.payload)) via=datalink"
        )
    }

    /// Detached so a MainActor flood cannot delay the clock; identity-checked on arrival.
    private func watchInflight(
        _ send: InflightSend, key: UInt16, after delay: Duration,
        _ body: @escaping @MainActor (CameraSession, InflightSend) -> Void
    ) {
        Task.detached { [weak self] in
            try? await Task.sleep(for: delay)
            await MainActor.run { [weak self] in
                guard let self, let live = self.inflight[key], live === send else { return }
                body(self, live)
            }
        }
    }

    private func finishInflight(_ send: InflightSend, key: UInt16, reply: Duml.Frame, late: Bool) {
        inflight[key] = nil
        lateWait[key] = nil
        if send.frame.cmdId == 0xA5 { applyTrackingPoll(reply.payload) }
        let ok = finishControlReply(
            reply, name: send.name, opcode: send.opcode, expect: send.expect, late: late)
        if !ok { send.onFail?() }
        send.onSettle?(ok)
        launchPendingAfterSettle(key)
    }

    private func settleInflightTimeout(_ send: InflightSend, key: UInt16) {
        inflight[key] = nil
        let matched = send.expect?.confirmed(by: status) == true
        let result = setMailbox.timeout(key: key, subscribeMatches: matched)
        let videoFresh = datalink?.lastVideoPacketAt.map {
            Date().timeIntervalSince($0) < FeedWatchdog.stallThreshold
        } == true
        if CameraSetMailbox.timeoutImpliesUplinkFailure(result, key: key) {
            if videoFresh {
                log.info("control: SET timeout with video flowing — leave UDP")
                ControlLiveLog.line("control: \(send.name) \(send.opcode) — SET timeout, video flowing, leave UDP")
            } else {
                noteCommandTimeout()
            }
        }
        switch result {
        case .subscribeMatches:
            controlNote = nil
            ControlLiveLog.line("control: \(send.name) \(send.opcode) — subscribe already matches")
            send.onSettle?(true)
            launchPendingAfterSettle(key)
        case .waitLate:
            lateWait[key] = send
            ControlLiveLog.line("control: \(send.name) \(send.opcode) — awaiting late ACK")
        case .launchPending:
            send.onSettle?(false)
            launchPendingAfterSettle(key)
        case .idle:
            break
        }
    }

    private func launchPendingAfterSettle(_ key: UInt16) {
        switch setMailbox.pendingLaunch(key: key, now: CFAbsoluteTimeGetCurrent()) {
        case .none:
            return
        case .immediate:
            guard let next = inflightPending.removeValue(forKey: key) else { return }
            launchInflight(next, key: key)
        case .afterHold:
            scheduleCoalesceLaunch(key)
        }
    }

    private func scheduleCoalesceLaunch(_ key: UInt16) {
        guard coalesceScheduled.insert(key).inserted else { return }
        let remain = setMailbox.holdRemaining(key: key, now: CFAbsoluteTimeGetCurrent())
        let delay: Duration = remain > 0
            ? .milliseconds(Int((remain * 1_000).rounded(.up)))
            : .milliseconds(1)
        Task.detached { [weak self] in
            try? await Task.sleep(for: delay)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.coalesceScheduled.remove(key)
                let blocked = self.inflight[key] != nil
                    && !CameraSetMailbox.pipelinesWhileOpen(key)
                guard !blocked else { return }
                switch self.setMailbox.pendingLaunch(key: key, now: CFAbsoluteTimeGetCurrent()) {
                case .immediate:
                    guard let next = self.inflightPending.removeValue(forKey: key) else { return }
                    self.launchInflight(next, key: key)
                case .afterHold:
                    self.scheduleCoalesceLaunch(key)
                case .none:
                    break
                }
            }
        }
    }

    /// True request/response (pairing, Wi-Fi creds, audio GET blobs). Rides its
    /// caller's chain — never the fire-and-forget SET path.
    @discardableResult
    private func requestCamera(
        _ frame: Duml.Frame, name: String, timeout: Duration = .seconds(3)
    ) async -> Bool {
        guard datalink != nil else {
            controlNote = "not live"
            return false
        }
        if isBrowsingMedia, frame.cmdSet == 0x02, frame.cmdId == 0x8E {
            return false
        }
        let opcode = String(format: "0x%02X/0x%02X", frame.cmdSet, frame.cmdId)
        do {
            // Waiter is registered inside waitFrame *before* `send` runs. Do not `async let`
            // on MainActor — that wrote UDP before the child task could register.
            let reply = try await waitFrame(
                frame.cmdSet, frame.cmdId,
                timeout: timeout,
                consumeHold: false
            ) {
                let seq = self.datalink?.send(frame) ?? 0
                ControlLiveLog.line(
                    "control: send \(name) \(opcode) seq=\(seq) flags=0x\(String(frame.flags, radix: 16)) payload=\(Duml.hex(frame.payload)) via=datalink"
                )
            }
            return finishControlReply(reply, name: name, opcode: opcode, expect: nil, announce: false)
        } catch {
            if let note = ControlHud.timeoutNote(name: name, announce: false) {
                controlNote = note
            }
            ControlLiveLog.line("control: timeout \(name) \(opcode) — waiter saw no ACK")
            return false
        }
    }

    private func finishControlReply(
        _ reply: Duml.Frame, name: String, opcode: String, expect: ControlExpect?,
        late: Bool = false, announce: Bool = true
    ) -> Bool {
        var next = status
        _ = CameraStatusDecoder.apply(reply, to: &next)
        absorbStaleAudio(&next)
        status = next
        let parsed = CameraReply.parse(reply.payload)
        ControlLiveLog.line(
            "control: got \(name) \(opcode) seq=\(reply.seq) flags=0x\(String(reply.flags, radix: 16)) payload=\(Duml.hex(reply.payload)) success=\(parsed.isSuccess)\(late ? " late-hold" : "")"
        )
        if parsed.isSuccess {
            log.info("control: \(name, privacy: .public) ok")
            return true
        }
        if expect?.confirmed(by: status) == true {
            controlNote = nil
            ControlLiveLog.line("control: \(name) \(opcode) subscribe already matches after \(parsed.message)")
            return true
        }
        if announce { controlNote = "\(name): \(parsed.message)" }
        log.info("control: \(name, privacy: .public) \(parsed.message, privacy: .public)")
        return false
    }

    // ---- keepalive -------------------------------------------------------------------------------

    private func startKeepalive(ssid: String?) {
        keepaliveLoop?.cancel()
        keepaliveLoop = Task {
            while !Task.isCancelled {
                ble.send(Commands.sessionKeepalive())
                if ssid != nil, !holdsMonitor {
                    if !isBrowsingMedia, shouldStartUDPRebuild {
                        try? await datalink?.rebuildUDP(reason: "keepalive")
                        if liveViewEnableSent {
                            let hadVideo = FeedWatchdog.hadVideo(
                                videoPackets: datalink?.videoPackets ?? 0,
                                lastVideoPacketAge: datalink?.lastVideoPacketAt.map {
                                    Date().timeIntervalSince($0)
                                })
                            let force = CameraSoftAP.shouldForceEnableAfterUDPRebuild(hadVideo: hadVideo)
                            if force {
                                log.info("live: first-picture enable after UDP rebuild (neverGotVideo)")
                            }
                            sendRecoverEnable(
                                force: force,
                                reason: force ? "first-picture after UDP rebuild" : "keepalive after UDP rebuild")
                        }
                    }
                    datalink?.keepalive()
                    publishPipelineStats()
                    if !isBrowsingMedia {
                        recoverLiveViewIfNeeded()
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func publishPipelineStats() {
        videoPackets = datalink?.videoPackets ?? 0
        accessUnits = rawAccessUnits
        framesEnqueued = rawFramesEnqueued
        droppedIncomplete = datalink?.droppedIncomplete ?? 0
        decoderErrors = decoder.decoderErrors
        hasVideoFormat = decoder.hasFormat
        nalTypes = decoder.nalTypesSeen.sorted().map(String.init).joined(separator: ",")
        if let t = decoder.lastKeyframeAt {
            lastKeyframeAge = String(format: "%.1fs", Date().timeIntervalSince(t))
        } else {
            lastKeyframeAge = "none yet"
        }
        refreshLinkHealth()
        let presentedAge = decoder.lastPresentedAt.map { Date().timeIntervalSince($0) }
        if decoder.lastPresentedAt == nil
            || CameraSoftAP.shouldRunFirstPictureRecover(
                secondsSinceLastPresented: presentedAge,
                alreadySettled: firstPictureSettled)
        {
            let signature =
                "\(videoPackets).\(rawAccessUnits).\(hasVideoFormat).\(liveViewEnableSends).\(datalink?.receiveErrorCount ?? 0)"
            let now = Date()
            guard signature != lastFirstPictureSignature
                || now.timeIntervalSince(lastFirstPictureLogAt) >= 3
            else { return }
            lastFirstPictureSignature = signature
            lastFirstPictureLogAt = now
            let videoAge = datalink?.lastVideoPacketAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) } ?? "none"
            let statusAge = datalink?.lastStatusAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) } ?? "none"
            let write: String
            switch datalink?.lastWriteLanded {
            case true: write = "ok"
            case false: write = "fail"
            default: write = "—"
            }
            let auAge = self.datalink?.lastAccessUnitAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) } ?? "none"
            let rebuildAge = self.datalink?.secondsSinceLastRebuild.map { String(format: "%.1f", $0) } ?? "none"
            let hadVideo = FeedWatchdog.hadVideo(
                videoPackets: self.videoPackets,
                lastVideoPacketAge: self.datalink?.lastVideoPacketAt.map { Date().timeIntervalSince($0) })
            log.info("live: first-picture videoPkts=\(self.videoPackets, privacy: .public) aus=\(self.rawAccessUnits, privacy: .public) lastAU=\(auAge, privacy: .public)s drop=\(self.droppedIncomplete, privacy: .public) rxErr=\(self.datalink?.receiveErrorCount ?? 0, privacy: .public) lastVideo=\(videoAge, privacy: .public)s lastStatus=\(statusAge, privacy: .public)s lastRebuild=\(rebuildAge, privacy: .public)s hadVideo=\(hadVideo ? 1 : 0) format=\(self.hasVideoFormat ? 1 : 0) idrHold=\(self.decoder.awaitingIDR ? 1 : 0) nals=\(self.nalTypes, privacy: .public) enables=\(self.liveViewEnableSends, privacy: .public) tcp=\(self.datalink?.isTcpPokeReady == true ? 1 : 0) flow=\(self.datalink?.isFlowHealthy == true ? 1 : 0) write=\(write, privacy: .public)")
        }
    }

    /// Pocket + Nano capture (`0x09/0xa8`). Action live start is uncaptured — do not invent it.
    func startCapturedLiveView(reason: String) -> Bool {
        if isBrowsingMedia, reason != "media browse ended" { return false }
        guard connectedCamera?.model.usesCapturedLiveEnable != false else {
            log.info(
                "live: skip 0x09/0xa8 — \(self.connectedCamera?.model.name ?? "camera", privacy: .public) has no captured enable (\(reason, privacy: .public))"
            )
            if controlNote == nil {
                controlNote = "Live view for this camera is not captured yet."
            }
            return false
        }
        let nanoGate = connectedCamera?.model.usesNanoLiveViewGate == true
        if nanoGate {
            datalink?.send(Commands.nanoLiveViewGate(start: true))
        }
        if CameraSoftAP.shouldSendLiveViewPrepare(usesNanoLiveViewGate: nanoGate) {
            datalink?.send(Commands.liveViewPrepare())
        }
        datalink?.startLiveView(
            receiver: connectedCamera?.model.liveViewEnableReceiver
                ?? Commands.liveViewEnableReceiverPocket)
        return true
    }

    /// One enable after path + display are ready. Never before `192.168.2.x` exists
    /// unless handshake already proved the socket (`pathProven`).
    private func sendInitialLiveViewEnable(displayAttached: Bool, pathProven: Bool = false) {
        if isBrowsingMedia { return }
        let pathReady = pathProven || WiFiJoiner.isCameraPathReady()
        if pathProven
            ? CameraSoftAP.shouldSendLiveViewEnableAfterHandshake(alreadySent: liveViewEnableSent)
            : CameraSoftAP.shouldSendLiveViewEnable(
                pathReady: pathReady, displayAttached: displayAttached,
                alreadySent: liveViewEnableSent)
        {
            guard startCapturedLiveView(reason: "first picture") else { return }
            liveViewEnableSent = true
            liveViewEnableSends += 1
            lastIdrRequest = Date()
            idrHoldEnableCount = 1
            decoder.beginIDRHold()
            log.info("live: sent 0x09/0xa8 once (path ready, display attached) #\(self.liveViewEnableSends, privacy: .public)")
            return
        }
        // Display layout missed the wait (rare). Path is up and handshake already
        // succeeded — one enable so we are not stuck on the 5 s stall cooldown.
        if pathReady, !liveViewEnableSent {
            guard startCapturedLiveView(reason: "display wait") else { return }
            liveViewEnableSent = true
            liveViewEnableSends += 1
            lastIdrRequest = Date()
            idrHoldEnableCount = 1
            decoder.beginIDRHold()
            log.info("live: sent 0x09/0xa8 once after display wait (attached=\(displayAttached)) #\(self.liveViewEnableSends, privacy: .public)")
        } else {
            log.info("live: skipped enable pathReady=\(pathReady) attached=\(displayAttached) sent=\(self.liveViewEnableSent)")
        }
    }

    /// SET ACK silence while video is dead. Video still flowing is handled in
    /// `settleInflightTimeout` — that must not tear the socket.
    private func noteCommandTimeout() {
        let now = Date()
        commandTimeoutsAt = commandTimeoutsAt.filter {
            now.timeIntervalSince($0) < CameraSoftAP.commandTimeoutWindow
        }
        commandTimeoutsAt.append(now)
        let videoFresh = datalink?.lastVideoPacketAt.map {
            now.timeIntervalSince($0) < FeedWatchdog.stallThreshold
        } == true
        let downlinkFresh = [datalink?.lastStatusAt, datalink?.lastVideoPacketAt]
            .compactMap { $0 }
            .contains { now.timeIntervalSince($0) < CameraSoftAP.commandTimeoutWindow }
        guard CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: commandTimeoutsAt.count,
            downlinkFresh: downlinkFresh,
            videoFresh: videoFresh,
            rebuildInFlight: datalink?.isRebuilding == true || feedRecoveryTask != nil,
            secondsSinceLastRebuild: datalink?.secondsSinceLastRebuild
        ) else { return }
        if FeedWatchdog.shouldHoldForGOPReset(
            secondsSinceLastEnable: now.timeIntervalSince(lastIdrRequest),
            lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) }
        ) {
            log.info("control: SET timeouts during GOP-reset grace — leave UDP")
            return
        }
        if FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: secondsSinceFocusTrackSet) {
            log.info("control: SET timeouts during AF-C grace — leave UDP")
            return
        }
        commandTimeoutsAt.removeAll()
        log.info("control: SET timeouts with video stale — rebuild UDP")
        ControlLiveLog.line("control: SET timeouts, video stale — rebuilding UDP")
        startFeedRecovery { [weak self] in
            guard let self else { return }
            try? await self.datalink?.rebuildUDP(reason: "command timeouts")
            // Re-fire nothing — state reconciles via subscribe pushes. Video may
            // need a fresh enable on the new socket; the gate below rate-limits it.
            if self.liveViewEnableSent {
                self.sendRecoverEnable(force: false, reason: "command timeouts")
            }
        }
    }

    /// One UDP rebuild at a time. Keepalive / control must not collide with
    /// first-picture rebuild (that canceled the new socket and RST’d TCP 7001).
    private var shouldStartUDPRebuild: Bool {
        let now = Date()
        if FeedWatchdog.shouldHoldForGOPReset(
            secondsSinceLastEnable: now.timeIntervalSince(lastIdrRequest),
            lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) }
        ) {
            return false
        }
        if FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: secondsSinceFocusTrackSet) {
            return false
        }
        let videoFresh = datalink?.lastVideoPacketAt.map {
            now.timeIntervalSince($0) < FeedWatchdog.stallThreshold
        } == true
        return CameraSoftAP.shouldKeepaliveRebuildUDP(
            flowNeedsRebuild: datalink?.needsRebuild == true,
            rebuildInFlight: datalink?.isRebuilding == true || feedRecoveryTask != nil,
            secondsSinceLastRebuild: datalink?.secondsSinceLastRebuild,
            videoFresh: videoFresh,
            sawPicture: hasStableLivePicture
        )
    }

    /// First-picture enable, then the feed watchdog. Cumulative `videoPackets` is
    /// not a stall signal — after 3–5 min it stays huge even if UDP 9004 went quiet.
    /// A frozen first GOP still has `lastPresentedAt` — that must not skip recover.
    private func recoverLiveViewIfNeeded() {
        guard !isBrowsingMedia, !holdsMonitor else { return }
        if needsForegroundRecover { return }
        guard WiFiJoiner.isCameraPathReady() else { return }
        if MediaLiveResume.strayPlaybackAction(
            browsing: isBrowsingMedia, inPlayback: status.inPlayback) != nil
        {
            sendExitPlayback()
            ControlLiveLog.line("media: stray playback — sent exit")
            let hasPicture = decoder.lastPresentedAt != nil
            if !CameraSoftAP.shouldContinueFirstPictureAfterStrayPlayback(hasPicture: hasPicture) {
                return
            }
        }
        let presentedAge = decoder.lastPresentedAt.map { Date().timeIntervalSince($0) }
        if !firstPictureSettled,
            CameraSoftAP.shouldMarkFirstPictureSettled(
                secondsSinceLastPresented: presentedAge,
                secondsSinceLastEnable: Date().timeIntervalSince(lastIdrRequest))
        {
            firstPictureSettled = true
        }
        if CameraSoftAP.shouldRunFirstPictureRecover(
            secondsSinceLastPresented: presentedAge,
            alreadySettled: firstPictureSettled)
        {
            recoverFirstPictureIfNeeded()
            return
        }
        // A live receive keeps the watchdog idle, so a lost 0x09/0xa8 during an
        // IDR hold would freeze the canvas on the held frame. One extra enable
        // at 5s if this hold has only fired once; then the 60s backoff.
        if decoder.awaitingIDR {
            let bleAge = lastBleNotifyAt.map { Date().timeIntervalSince($0) }
            let videoAge = datalink?.lastVideoPacketAt.map { Date().timeIntervalSince($0) }
            let hadVideo = FeedWatchdog.hadVideo(
                videoPackets: datalink?.videoPackets ?? 0,
                lastVideoPacketAge: videoAge)
            if FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: Date().timeIntervalSince(lastIdrRequest),
                secondsSinceLastRebuild: datalink?.secondsSinceLastRebuild,
                pathReady: true,
                lastBleNotifyAge: bleAge,
                hadVideo: hadVideo,
                holdEnableCount: idrHoldEnableCount,
                lastVideoPacketAge: videoAge
            ) {
                log.info("live: still holding for IDR — re-request enable")
                sendRecoverEnable(force: true, reason: "still holding for IDR")
                return
            }
        }
        applyFeedWatchdog()
    }

    private func recoverFirstPictureIfNeeded() {
        if datalink?.isRebuilding == true || feedRecoveryTask != nil { return }
        let packets = datalink?.videoPackets ?? 0
        let since = Date().timeIntervalSince(lastIdrRequest)
        let videoAge = datalink?.lastVideoPacketAt.map { Date().timeIntervalSince($0) }
        switch CameraSoftAP.firstPictureStep(
            videoPackets: packets,
            enableSends: liveViewEnableSends,
            secondsSinceLastEnable: since,
            secondsSinceLastVideo: videoAge,
            secondsSinceLastRebuild: datalink?.secondsSinceLastRebuild,
            secondsSinceLastStatus: datalink?.lastStatusAt.map { Date().timeIntervalSince($0) }
        ) {
        case .wait:
            break
        case .resendEnable:
            // Do not route through sendRecoverEnable — inPlayback / VT-ready
            // holds skipped the only PLI and sat on Waiting for live view.
            if liveViewEnableSends == 0 {
                log.info("live: first-picture enable never sent — sending now")
                sendInitialLiveViewEnable(
                    displayAttached: decoder.isDisplayReady, pathProven: true)
                return
            }
            log.info("live: first-picture resend enable (waiting for IDR)")
            guard startCapturedLiveView(reason: "first-picture resend") else { return }
            liveViewEnableSends += 1
            lastIdrRequest = Date()
            if !decoder.awaitingIDR { idrHoldEnableCount = 0 }
            decoder.beginIDRHold()
            idrHoldEnableCount += 1
            return
        case .rebuildUDP:
            log.info("live: first-picture rebuild UDP (receive died pkts=\(packets, privacy: .public) lastVideo=\(videoAge ?? -1, format: .fixed(precision: 1), privacy: .public)s)")
            startFeedRecovery { [weak self] in
                guard let self else { return }
                try? await self.datalink?.rebuildUDP(reason: "first picture")
                _ = await self.decoder.waitUntilDisplayReady(timeout: .milliseconds(400))
                self.sendRecoverEnable(force: true, reason: "first-picture after UDP rebuild")
            }
            return
        case .rejoin:
            log.info("live: first-picture full rejoin (SoftAP bind kept)")
            startFeedRecovery { [weak self] in
                await self?.rejoinDatalinkKeepingLive()
            }
            return
        }
    }

    private func applyFeedWatchdog() {
        if needsForegroundRecover { return }
        let now = Date()
        let live: Bool
        if case .live = phase { live = true } else { live = false }
        let wentBlack = decoder.displayedImageRemoved || decoder.displayLayer.status == .failed
        let snap = FeedWatchdog.Snapshot(
            now: now.timeIntervalSinceReferenceDate,
            lastDecodedFrameAge: decoder.lastPresentedAt.map { now.timeIntervalSince($0) },
            lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) },
            lastAccessUnitAge: datalink?.lastAccessUnitAt.map { now.timeIntervalSince($0) },
            lastStatusAge: datalink?.lastStatusAt.map { now.timeIntervalSince($0) },
            flowHealthy: datalink?.isFlowHealthy ?? false,
            pathReady: WiFiJoiner.isCameraPathReady(),
            hasFormat: decoder.hasFormat,
            decoderFailed: decoder.decoderErrors > 0 || decoder.displayLayer.status == .failed,
            live: live,
            sawPicture: decoder.lastPresentedAt != nil,
            tcpPokeReady: datalink?.isTcpPokeReady ?? false,
            displayedImageRemoved: wentBlack,
            lastBleNotifyAge: lastBleNotifyAt.map { now.timeIntervalSince($0) },
            secondsSinceLastRebuild: datalink?.secondsSinceLastRebuild,
            hadVideo: FeedWatchdog.hadVideo(
                videoPackets: datalink?.videoPackets ?? 0,
                lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) }),
            secondsSinceLastEnable: now.timeIntervalSince(lastIdrRequest),
            secondsSinceFocusTrackSet: secondsSinceFocusTrackSet
        )
        let action = feedWatchdog.tick(snap)
        feedRecovering = feedWatchdog.isRecovering || feedRecoveryTask != nil
        switch action {
        case .none:
            if !FeedWatchdog.udpReceiveAlive(snap),
                FeedWatchdog.shouldHoldForGOPReset(
                    secondsSinceLastEnable: snap.secondsSinceLastEnable,
                    lastVideoPacketAge: snap.lastVideoPacketAge)
            {
                log.info(
                    "feed: hold UDP rebuild — GOP-reset grace lastEnable=\(snap.secondsSinceLastEnable ?? -1, format: .fixed(precision: 1), privacy: .public)s lastVideo=\(snap.lastVideoPacketAge ?? -1, format: .fixed(precision: 1), privacy: .public)s")
            } else if !FeedWatchdog.udpReceiveAlive(snap),
                FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: snap.secondsSinceFocusTrackSet)
            {
                log.info(
                    "feed: hold UDP rebuild — AF-C grace lastSet=\(snap.secondsSinceFocusTrackSet ?? -1, format: .fixed(precision: 1), privacy: .public)s lastVideo=\(snap.lastVideoPacketAge ?? -1, format: .fixed(precision: 1), privacy: .public)s")
                ControlLiveLog.line(
                    "feed: hold UDP rebuild — AF-C grace lastSet=\(String(format: "%.1f", snap.secondsSinceFocusTrackSet ?? -1))s")
            }
            return
        case .resendLiveViewEnable:
            log.info("\(self.feedWatchdog.stallLogLine(snap), privacy: .public)")
            ControlLiveLog.line(feedWatchdog.stallLogLine(snap))
            sendRecoverEnable(force: true, reason: "watchdog")
        case .rebuildVTSession:
            // UDP pause is not a wedged decoder. Rebuild the socket; keep VT.
            log.info("\(self.feedWatchdog.stallLogLine(snap), privacy: .public)")
            ControlLiveLog.line(feedWatchdog.stallLogLine(snap))
            rebuildUDPKeepingVT()
        case .reopenDatalink, .fullSessionRejoin:
            log.info("\(self.feedWatchdog.stallLogLine(snap), privacy: .public)")
            ControlLiveLog.line(feedWatchdog.stallLogLine(snap))
            rebuildUDPKeepingVT()
        }
    }

    /// Re-enable only after SoftAP + VT/display are ready. Holds P-frames until IDR.
    private func sendRecoverEnable(force: Bool, reason: String = "recover") {
        if isBrowsingMedia { return }
        if status.inPlayback {
            sendExitPlayback()
            ControlLiveLog.line("feed: hold enable — camera still in playback (\(reason))")
            return
        }
        let pathReady = WiFiJoiner.isCameraPathReady()
        let decoderReady = decoder.isPresentationReady
        guard FeedWatchdog.shouldSendRecoverEnable(pathReady: pathReady, decoderReady: decoderReady)
        else {
            log.info("feed: hold enable path=\(pathReady ? 1 : 0) decoder=\(decoderReady ? 1 : 0) reason=\(reason, privacy: .public)")
            return
        }
        if !force, Date().timeIntervalSince(lastIdrRequest) < FeedWatchdog.escalateAfter {
            return
        }
        lastIdrRequest = Date()
        if !decoder.awaitingIDR { idrHoldEnableCount = 0 }
        decoder.beginIDRHold()
        idrHoldEnableCount += 1
        guard startCapturedLiveView(reason: reason) else { return }
        liveViewEnableSends += 1
        log.info("live: recover 0x09/0xa8 (\(reason, privacy: .public), VT ready, hold IDR) #\(self.liveViewEnableSends, privacy: .public)")
        ControlLiveLog.line(
            "feed: recover 0x09/0xa8 reason=\(reason) #\(liveViewEnableSends)")
    }

    private func resetFeedWatchdog() {
        feedRecovering = false
        feedWatchdog = FeedWatchdog()
        feedRecoveryTask?.cancel()
        feedRecoveryTask = nil
    }

    private func resetLinkHealthMeasurements() {
        frameRate = FrameRateSampler()
        signalBarsFilter = LinkSignalBars()
        lastGoodFrameAt = nil
        consecutiveBadLiveFrames = 0
        lastDecoderErrorCount = 0
        lastReceiveErrorCount = 0
        recentKeepaliveFailures = 0
        liveFPS = "—"
        liveSignalBars = 0
        isFeedWarming = true
    }

    /// First picture is up and the GOP cut has settled. Keepalive may rebuild.
    private var hasStableLivePicture: Bool {
        guard let at = decoder.lastPresentedAt else { return false }
        return Date().timeIntervalSince(at) >= CameraSoftAP.rebuildCooldown
    }

    private func armFaceAFAfterFirstPicture() {
        guard !faceAFArmed, faceAFArmTask == nil else { return }
        faceAFArmTask = Task { @MainActor in
            // VT already starts at format. Poll for a rolling picture, then
            // unlock (no-op if already) and arm Face AF.
            while !Task.isCancelled, !self.faceAFArmed {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                let age = self.decoder.lastPresentedAt.map { Date().timeIntervalSince($0) }
                guard CameraSoftAP.isPresentedPictureFresh(secondsSinceLastPresented: age)
                else { continue }
                self.decoder.unlockHardwareDecoder()
                self.faceAFArmed = true
            }
            self.faceAFArmTask = nil
        }
    }

    private func noteLiveFrame() {
        lastGoodFrameAt = Date()
        consecutiveBadLiveFrames = 0
        if !decoder.awaitingIDR { idrHoldEnableCount = 0 }
        armFaceAFAfterFirstPicture()
        if liveViewEnableSent {
            let audio = audioRefreshPending
            let glamour = glamourClearPending
            let focus = focusTrackPending
            if (audio || glamour || focus), !isBrowsingMedia {
                audioRefreshPending = false
                glamourClearPending = false
                focusTrackPending = false
                Task {
                    if audio { await self.refreshAudioState() }
                    if glamour { await self.clearGlamourIfEnabled() }
                    if focus { await self.refreshFocusTrack() }
                }
            }
        }
        let before = frameRate.displayFPS
        frameRate.recordFrame(at: Date.timeIntervalSinceReferenceDate)
        if frameRate.displayFPS != before {
            applyLinkPresentation()
        } else {
            refreshFeedWarmup()
        }
    }

    private func refreshLinkHealth() {
        noteTransportFailures()
        applyLinkPresentation()
    }

    private func applyLinkPresentation() {
        if sessionRecovery.isRecovering {
            if liveFPS != SessionRecoveryCopy.heldFrameBadge {
                liveFPS = SessionRecoveryCopy.heldFrameBadge
            }
            refreshFeedWarmup()
            return
        }
        let measured = frameRate.displayFPS
        let label = LiveViewLink.fpsChipLabel(
            connection: phase,
            recovering: feedRecovering,
            formattedFPS: frameRate.formatted,
            measuredFPS: measured
        )
        if label != liveFPS { liveFPS = label }
        let snapshot = CameraLinkHealthScorer.score(currentLinkHealthInputs())
        let bars = signalBarsFilter.update(score: snapshot.linkHealthScore)
        if bars != liveSignalBars { liveSignalBars = bars }
        refreshFeedWarmup()
    }

    private func refreshFeedWarmup() {
        if holdsMonitor, decoder.lastPresentedAt != nil {
            if isFeedWarming { isFeedWarming = false }
            return
        }
        let next = LiveFeedWarmup.isWarming(
            hasPresentedPicture: decoder.lastPresentedAt != nil,
            measuredFPS: frameRate.displayFPS,
            rollingIntervals: frameRate.intervalCount,
            recovering: feedRecovering || feedRecoveryTask != nil,
            secondsSinceLastPresented: decoder.lastPresentedAt.map {
                Date().timeIntervalSince($0)
            }
        )
        if next != isFeedWarming { isFeedWarming = next }
    }

    private func currentLinkHealthInputs() -> CameraLinkHealthInputs {
        let measured = frameRate.displayFPS
        let linkPhase = LiveViewLink.cameraLinkPhase(
            connection: phase,
            recovering: feedRecovering,
            measuredFPS: measured
        )
        let liveFPSValue = measured > 0 ? measured : nil
        return CameraLinkHealthInputs(
            phase: linkPhase,
            ptpRoundTripMilliseconds: nil,
            liveViewFPS: liveFPSValue,
            targetLiveViewFPS: LiveViewLink.targetFPS,
            secondsSinceLastGoodFrame: lastGoodFrameAt.map { Date().timeIntervalSince($0) },
            consecutiveBadFrames: consecutiveBadLiveFrames,
            recentCommandFailures: recentKeepaliveFailures,
            isRecoveringStream: feedRecovering
        )
    }

    private func noteTransportFailures() {
        let errors = decoder.decoderErrors
        if errors > lastDecoderErrorCount {
            consecutiveBadLiveFrames += errors - lastDecoderErrorCount
        }
        lastDecoderErrorCount = errors
        let rx = datalink?.receiveErrorCount ?? 0
        if rx > lastReceiveErrorCount {
            recentKeepaliveFailures = min(4, recentKeepaliveFailures + (rx - lastReceiveErrorCount))
        } else if recentKeepaliveFailures > 0 {
            recentKeepaliveFailures -= 1
        }
        lastReceiveErrorCount = rx
        if datalink?.lastWriteLanded == false {
            recentKeepaliveFailures = max(recentKeepaliveFailures, 1)
        }
        if datalink?.isFlowHealthy == false, case .live = phase {
            recentKeepaliveFailures = max(recentKeepaliveFailures, 1)
        }
    }

    func noteSceneBecameInactive() {
        if case .live = phase { needsForegroundRecover = true }
        log.info("live: scene inactive — will recover feed on active")
    }

    func noteSceneBecameActive() {
        if isBrowsingMedia {
            needsForegroundRecover = false
            return
        }
        guard needsForegroundRecover else { return }
        if CameraSoftAP.shouldClearForegroundRecoverWithoutRebuild(holdsMonitor: holdsMonitor) {
            needsForegroundRecover = false
            return
        }
        needsForegroundRecover = false
        if case .live = phase {
            recoverAfterForeground()
            return
        }
        // BLE / run() often dies in the background. Reconnect the same camera.
        if let id = connectedCamera?.id ?? reconnectTarget {
            log.info("live: scene active — session not live, reconnect")
            reconnect(to: id)
        }
    }

    /// UDP and VT die while suspended. Watchdog will not fire if packets still
    /// arrive but the present path is dead — that is the frozen resume canvas.
    private func recoverAfterForeground() {
        let presentedAge = decoder.lastPresentedAt.map { Date().timeIntervalSince($0) }
        if !CameraSoftAP.shouldRecoverAfterForeground(secondsSinceLastPresented: presentedAge) {
            log.info("live: foreground — picture still fresh, skip rebuild")
            return
        }
        log.info("live: recover after foreground")
        firstPictureSettled = false
        decoder.prepareAfterForeground()
        startFeedRecovery { [weak self] in
            guard let self else { return }
            try? await WiFiJoiner.waitUntilCameraPathReady(timeout: 8)
            try? await self.datalink?.rebuildUDP(reason: "foreground")
            _ = await self.decoder.waitUntilDisplayReady(timeout: .milliseconds(400))
            if self.liveViewEnableSent {
                self.sendRecoverEnable(force: true, reason: "foreground")
            } else {
                self.sendInitialLiveViewEnable(
                    displayAttached: self.decoder.isDisplayReady, pathProven: true)
            }
            try? await Task.sleep(for: .seconds(CameraSoftAP.foregroundPictureGrace))
            guard !Task.isCancelled else { return }
            let stillFrozen = CameraSoftAP.shouldEscalateForegroundRecover(
                secondsSinceLastPresented: self.decoder.lastPresentedAt.map {
                    Date().timeIntervalSince($0)
                })
            if stillFrozen {
                self.log.info("live: foreground still frozen — full datalink rejoin")
                await self.rejoinDatalinkKeepingLive()
            }
        }
    }

    /// Half-dead UDP: rebuild the socket, keep VT and the last picture, keep SoftAP.
    private func rebuildUDPKeepingVT() {
        startFeedRecovery { [weak self] in
            guard let self else { return }
            try? await self.datalink?.rebuildUDP(reason: "feed watchdog")
            _ = await self.decoder.waitUntilDisplayReady(timeout: .milliseconds(400))
            self.liveViewEnableSent = true
            self.sendRecoverEnable(force: true, reason: "feed watchdog UDP rebuild")
        }
    }

    private func startFeedRecovery(_ work: @escaping @MainActor () async -> Void) {
        feedRecoveryTask?.cancel()
        feedRecovering = true
        feedRecoveryTask = Task { @MainActor in
            await work()
            self.feedRecoveryTask = nil
            if !self.feedWatchdog.isRecovering { self.feedRecovering = false }
            self.refreshFeedWarmup()
        }
        refreshFeedWarmup()
    }

    // MARK: - Session recovery (camera power cycle)

    /// Recovers an established live session that dropped — camera power-off, BLE gone —
    /// without leaving the last frame. Bounded automatic attempts, then the operator chooses.
    func beginSessionRecovery(reason: String) {
        if case .pausedAfterRepeatedDrops = sessionRecovery { return }
        if case .waitingForOperator = sessionRecovery { return }
        if sessionRecoveryTask != nil { return }
        let cameraID = connectedCamera?.id ?? recoveryCameraID ?? reconnectTarget
        guard let cameraID else {
            log.info("session: drop (\(reason, privacy: .public)) — no camera to recover")
            return
        }
        recoveryCameraID = cameraID
        if recoveryDeviceName.isEmpty {
            recoveryDeviceName =
                connectedCamera?.name
                ?? SavedCameraStore.load().first { $0.id == cameraID }?.displayName
                ?? ""
        }
        holdsMonitor = true
        abortInFlightRun(
            preserveDecoder: true, preserveSoftAP: WiFiJoiner.isCameraPathReady())
        feedRecoveryTask?.cancel()
        feedRecovering = false
        sessionRecoveryGeneration += 1
        let generation = sessionRecoveryGeneration
        if sessionDropStormGuard.noteDrop(now: ProcessInfo.processInfo.systemUptime) {
            log.info(
                "session: drop (\(reason, privacy: .public)) → storm pause after \(self.sessionDropStormGuard.dropsInWindow) drops"
            )
            abortInFlightRun(preserveDecoder: true)
            sessionRecovery = .pausedAfterRepeatedDrops(drops: sessionDropStormGuard.dropsInWindow)
            sessionRecoveryCardGraceElapsed = true
            applyLinkPresentation()
            return
        }
        log.info("session: drop (\(reason, privacy: .public)) → bounded recovery")
        sessionRecovery = SessionRecoveryPolicy.monitor.state(afterFailedAttempts: 0)
        sessionRecoveryCardGraceElapsed = false
        recoveryCardGraceTask?.cancel()
        recoveryCardGraceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.recoveryCardGrace)
            guard let self, !Task.isCancelled else { return }
            guard self.sessionRecoveryGeneration == generation else { return }
            self.sessionRecoveryCardGraceElapsed = true
        }
        sessionRecoveryTask = Task { [weak self] in
            await self?.runSessionRecovery()
            guard let self, self.sessionRecoveryGeneration == generation else { return }
            self.sessionRecoveryTask = nil
        }
        applyLinkPresentation()
    }

    func retrySessionRecovery() {
        sessionDropStormGuard.reset()
        cancelSessionRecovery(clearHoldsMonitor: false)
        beginSessionRecovery(reason: "operator retry")
    }

    func cancelSessionRecovery(clearHoldsMonitor: Bool = true) {
        sessionRecoveryGeneration += 1
        sessionRecoveryTask?.cancel()
        sessionRecoveryTask = nil
        recoveryCardGraceTask?.cancel()
        recoveryCardGraceTask = nil
        sessionRecoveryCardGraceElapsed = false
        sessionRecovery = .idle
        isReconnecting = false
        if clearHoldsMonitor {
            holdsMonitor = false
            recoveryCameraID = nil
            recoveryDeviceName = ""
        }
    }

    private func runSessionRecovery() async {
        let policy = SessionRecoveryPolicy.monitor
        var failures = 0
        while !Task.isCancelled {
            let state = policy.state(afterFailedAttempts: failures)
            sessionRecovery = state
            applyLinkPresentation()
            guard case .retrying = state else { return }
            let recovered = await attemptRecoveryConnect()
            if Task.isCancelled { return }
            if recovered {
                sessionRecovery = .idle
                holdsMonitor = false
                isReconnecting = false
                sessionRecoveryCardGraceElapsed = false
                log.info("session: recovered after \(failures) failed attempt(s)")
                applyLinkPresentation()
                return
            }
            failures += 1
            guard
                case .retry(let wait) = policy.decision(
                    afterFailedAttempts: failures, jitter: .random(in: 0...1))
            else {
                sessionRecovery = policy.state(afterFailedAttempts: failures)
                log.info("session: recovery exhausted after \(failures) attempts")
                applyLinkPresentation()
                return
            }
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func attemptRecoveryConnect() async -> Bool {
        guard let id = recoveryCameraID else { return false }
        if WiFiJoiner.isCameraPathReady(), connectedCamera != nil {
            await rejoinDatalinkKeepingLive()
            if Task.isCancelled { return false }
            if case .live = phase, datalink != nil {
                log.info("session: warm rehandshake (SoftAP up)")
                keepBleScanInterest(for: id)
                return true
            }
        }
        isReconnecting = true
        phase = .scanning
        let foundCamera = await waitForRecoveryAdvertisement(
            id: id, timeout: Self.recoveryAttemptDeadline)
        guard let foundCamera, !Task.isCancelled else { return false }
        connect(foundCamera, preserveMonitor: true)
        var elapsed: Duration = .zero
        while !Task.isCancelled, elapsed < Self.recoveryAttemptDeadline {
            if case .live = phase { return true }
            if runTask == nil, phase != .live { return false }
            try? await Task.sleep(for: .milliseconds(250))
            elapsed += .milliseconds(250)
        }
        if case .live = phase { return true }
        log.info("session: recovery attempt stalled past \(Self.recoveryAttemptDeadline)")
        abortInFlightRun(preserveDecoder: true)
        return false
    }

    /// Keep CoreBluetooth scanning for the live body after GATT drops.
    /// Does not abort SoftAP or UDP — `startScan(reconnect:)` would.
    private func keepBleScanInterest(for id: UUID) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.ble.waitUntilPoweredOn()
            for await camera in self.ble.scan() {
                if Task.isCancelled { return }
                if camera.id != id { continue }
            }
        }
    }

    private func waitForRecoveryAdvertisement(id: UUID, timeout: Duration) async -> FoundCamera? {
        await ble.waitUntilPoweredOn()
        return await withTaskGroup(of: FoundCamera?.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return nil }
                for await camera in self.ble.scan() {
                    if Task.isCancelled { return nil }
                    let saved = SavedCameraStore.load().first { $0.id == camera.id }
                    let seen = camera.enriched(from: saved)
                    if seen.id == id { return seen }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Stage 4: new UDP handshake + register + subscribe on SoftAP. BLE and
    /// `phase == .live` stay so the operator is not dumped to a black home screen.
    private func rejoinDatalinkKeepingLive() async {
        guard let camera = connectedCamera else { return }
        log.info("feed: full datalink rejoin (SoftAP bind kept)")
        disposeDatalink()
        decoder.flushForRecovery()
        liveViewEnableSent = false
        liveViewEnableSends = 0
        idrHoldEnableCount = 0
        firstPictureSettled = false
        audioRefreshPending = true
        glamourClearPending = true
        focusTrackPending = true
        do {
            try Task.checkCancellation()
            try await WiFiJoiner.waitUntilCameraPathReady(timeout: 8)
            let dl = DatalinkDriver(
                port: UInt16(camera.model.datalinkPort),
                tcpPoke: camera.model.tcpPoke,
                pairingToken: camera.model.pairingToken
            )
            wireDatalink(dl)
            datalink = dl
            decoder.beginIDRHold()
            try await dl.open { [self] in
                guard shouldCommitLiveHandshake(dl) else { return }
                if isBrowsingMedia { return }
                sendInitialLiveViewEnable(
                    displayAttached: decoder.isDisplayReady, pathProven: true)
            }
            startKeepalive(ssid: joinedSSID)
        } catch is CancellationError {
            return
        } catch {
            log.info("feed: full rejoin failed (\(error.localizedDescription, privacy: .public))")
            disposeDatalink()
        }
    }

    /// Drop the live UDP session so the next connect cannot inherit a half-closed driver.
    private func disposeDatalink() {
        let link = datalink
        datalink = nil
        guard let link else { return }
        link.onAccessUnit = nil
        link.onStatusFrame = nil
        link.close()
    }

    private func shouldCommitLiveHandshake(_ dl: DatalinkDriver) -> Bool {
        let ok = CameraSoftAP.shouldCommitLiveHandshake(
            driverOwned: datalink === dl,
            isClosed: dl.isClosed,
            isCancelled: Task.isCancelled)
        if !ok {
            log.info("live: ignore stale datalink open")
        }
        return ok
    }

    private func wireDatalink(_ dl: DatalinkDriver) {
        dl.onStatusFrame = { [weak self] frame in
            self?.applyIncomingStatus(frame)
        }
        dl.onAccessUnit = { [weak self] accessUnit in
            self?.ingestAccessUnit(accessUnit)
        }
    }

    /// Android parity: offer every datalink frame to the opcode waiter.
    /// Restricting to flags == 0xC0 dropped 0x80 / same-opcode ACKs.
    private func applyIncomingStatus(_ frame: Duml.Frame) {
        route(frame)
        if frame.cmdSet == 0x00, frame.cmdId == 0x27 {
            if isBrowsingMedia { ingestMediaListFrame(frame) }
            return
        }
        if frame.cmdSet == 0x02, frame.cmdId == 0x89 {
            applyLiveTrackingPush(frame.payload)
        }
        var s = status
        guard CameraStatusDecoder.apply(frame, to: &s) else { return }
        absorbStaleExpo(&s)
        absorbStaleAudio(&s)
        absorbStaleFormat(&s)
        absorbStaleColor(&s)
        absorbCameraFocus(s)
        noteExpoIfChanged(s)
        noteZoomIfChanged(s)
        // Scope clip ceiling follows the camera's EI; feeding it here keeps the
        // scope view bodies free of session-status reads (5 Hz re-render trap).
        ScopeExposureCeiling.syncISO(s.iso)
        status = s
        settleLateFromSubscribe()
    }

    var hasMediaDatalink: Bool { datalink != nil }

    func sendMediaFrame(_ frame: Duml.Frame) {
        _ = datalink?.send(frame)
    }

    func rejoinSoftAPAfterInternetHop() async {
        guard let ssid = cachedSSID ?? joinedSSID, let pass = cachedPassword else { return }
        let wpa3 = connectedCamera?.model.wpa3 ?? true
        try? await WiFiJoiner.join(ssid: ssid, passphrase: pass, wpa3: wpa3)
        try? await WiFiJoiner.waitUntilCameraPathReady(timeout: 20)
    }

    func sendEnterPlayback() { datalink?.enterPlayback() }
    func sendExitPlayback() { datalink?.exitPlayback() }

    func awaitMediaOpcode(
        _ set: UInt8, _ cmd: UInt8, timeout: Duration, send: (() -> Void)?
    ) async throws -> Duml.Frame {
        try await waitFrame(set, cmd, timeout: timeout, consumeHold: false, send: send)
    }

    func restartLiveViewAfterMedia() {
        guard startCapturedLiveView(reason: "media browse ended") else { return }
        liveViewEnableSent = true
        liveViewEnableSends += 1
        lastIdrRequest = Date()
        idrHoldEnableCount = 1
        decoder.beginIDRHold()
    }

    func resetMediaSession() {
        persistMediaCatalog()
        cameraMedia.resetSession()
        isBrowsingMedia = false
        mediaFetchInProgress = false
        mediaNote = nil
        mediaDownloadProgress = [:]
        loadCachedCatalogIfNeeded()
        loadMediaFavorites()
    }

    func clearMediaCache() {
        cameraMedia.resetSession()
        mediaDownloadProgress = [:]
        cameraMedia.clearCache(cameraID: mediaCameraID, preservingCatalog: true)
    }

    func mediaCacheByteCount() -> UInt64 {
        cameraMedia.cacheByteCount(cameraID: mediaCameraID)
    }

    /// Subscribe already matches a timed-out SET — treat as success, do not wait
    /// for a hold-replay ACK that would thrash the chips.
    private func settleLateFromSubscribe() {
        let hits = lateWait.filter { $0.value.expect?.confirmed(by: status) == true }
        for (key, send) in hits {
            lateWait[key] = nil
            if setMailbox.isAwaitingLate(key) {
                _ = setMailbox.timeout(key: key, subscribeMatches: true)
            }
            controlNote = nil
            send.onSettle?(true)
        }
    }

    private func ingestAccessUnit(_ accessUnit: [UInt8]) {
        rawAccessUnits += 1
        if decoder.decode(accessUnit: accessUnit) { rawFramesEnqueued += 1 }
    }

    private func publishStatusNow() {
        lastStatusMutation = CFAbsoluteTimeGetCurrent()
        statusFlushTask?.cancel()
        statusFlushTask = nil
        withMutation(keyPath: \.status) {}
    }

    private func scheduleStatusFlush() {
        guard statusFlushTask == nil else { return }
        statusFlushTask = Task { @MainActor in
            let remaining = LiveChromeThrottle.statusInterval
                - (CFAbsoluteTimeGetCurrent() - lastStatusMutation)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            statusFlushTask = nil
            withMutation(keyPath: \.status) {}
            lastStatusMutation = CFAbsoluteTimeGetCurrent()
        }
    }

    // ---- helpers ---------------------------------------------------------------------------------

    /// Hold pairing + Wi-Fi + camera-control replies that can arrive before the waiter is registered.
    /// 1-byte 0x07/07 and 0x07/0E are refusals, not success — `readWifiString` still needs
    /// them after the matching write so it can fail fast, but it drops any hold *before* send.
    private func shouldHold(_ frame: Duml.Frame) -> Bool {
        Duml.shouldHoldReply(set: frame.cmdSet, cmd: frame.cmdId)
    }

    private struct KnownWifi {
        var ssid: String?
        var password: String?
        var source: String
        var skipBle: Bool
    }

    /// Memory (this launch) or Keychain (camera id / advertised name / last SSID).
    /// Advertised BLE name is only an SSID fallback after GetSSID refuses — not enough to skip BLE.
    private func resolvedWifiCreds(for camera: FoundCamera) -> KnownWifi {
        let saved = SavedCameraStore.load().first { $0.id == camera.id }
        let advertised = camera.name.isEmpty ? saved?.advertisedName : camera.name
        let keychain = CameraWifiKeychain.load(
            cameraId: camera.id,
            advertisedName: advertised,
            lastSSID: saved?.lastSSID
        )
        let memory: CameraWifiResolution.Memory?
        if let id = cachedWifiCameraId, let ssid = cachedSSID, let pass = cachedPassword {
            memory = .init(cameraId: id, ssid: ssid, password: pass)
        } else {
            memory = nil
        }
        let resolved = CameraWifiResolution.resolve(
            cameraId: camera.id,
            savedSSID: saved?.lastSSID,
            memory: memory,
            keychainSSID: keychain?.ssid,
            keychainPassword: keychain?.password
        )
        if let ssid = resolved.ssid, ssidBelongsToAnotherBody(ssid, camera: camera) {
            log.info("creds: dropping \(resolved.source, privacy: .public) SSID \(ssid, privacy: .public) — other body")
            return KnownWifi(ssid: nil, password: nil, source: "none", skipBle: false)
        }
        return KnownWifi(
            ssid: resolved.ssid,
            password: resolved.password,
            source: resolved.source,
            skipBle: resolved.skipBle
        )
    }

    private func ssidBelongsToAnotherBody(_ ssid: String, camera: FoundCamera) -> Bool {
        if CameraWifiResolution.isSSIDOwnedByAnotherCamera(
            ssid, cameraId: camera.id, saved: SavedCameraStore.load())
        {
            return true
        }
        return CameraBodyFamily.ssidConflictsWithBody(
            ssid: ssid, modelId: camera.modelId, advertisedName: camera.name)
    }

    private func assertSSIDBelongs(to camera: FoundCamera, ssid: String) throws {
        if ssidBelongsToAnotherBody(ssid, camera: camera) {
            log.info(
                "creds: SSID \(ssid, privacy: .public) does not belong to \(camera.model.name, privacy: .public)"
            )
            throw Fail.wrongCamera
        }
    }

    private func persistWifiCreds(camera: FoundCamera, ssid: String, password: String) {
        cachedSSID = ssid
        cachedPassword = password
        cachedWifiCameraId = camera.id
        CameraWifiKeychain.save(
            cameraId: camera.id,
            advertisedName: camera.name,
            ssid: ssid,
            password: password
        )
    }

    private func leftoverSoftAPSSIDs(besides ssid: String) -> [String] {
        var names = Set<String>()
        if let joined = joinedSSID { names.insert(joined) }
        if let id = cachedWifiCameraId, id != connectedCamera?.id, let cached = cachedSSID {
            names.insert(cached)
        }
        for camera in SavedCameraStore.load() {
            if camera.id == connectedCamera?.id { continue }
            if let other = camera.lastSSID { names.insert(other) }
        }
        names.remove(ssid)
        return names.filter { !$0.isEmpty }
    }

    /// After pairing + 0x53/0x10: skip BLE when we already have both creds; otherwise
    /// GetSSID/GetPassword with stale-hold cleared and 1-byte / 0xE0–0xEF fail-fast.
    private func wifiCredsAfterPairing(_ camera: FoundCamera) async throws -> (String, String) {
        let known = resolvedWifiCreds(for: camera)
        if known.skipBle, let ssid = known.ssid, let pass = known.password {
            log.info("creds: skipping BLE GetSSID/GetPassword — \(known.source, privacy: .public) SSID \(ssid, privacy: .public)")
            return (ssid, pass)
        }

        let advertised = camera.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ssidFallback = [known.ssid, advertised.isEmpty ? nil : advertised]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        let ssid: String
        if let stored = known.ssid, !stored.isEmpty, known.password == nil {
            log.info("creds: skipping GetSSID — using \(known.source, privacy: .public) SSID \(stored, privacy: .public)")
            ssid = stored
        } else {
            do {
                ssid = try await readWifiString(
                    name: "GetSSID", set: 0x07, cmd: 0x07, cached: known.ssid
                ) { ble.send(Commands.getWifiSsid()) }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as Fail where isDisconnect(error) {
                throw Fail.disconnectedDuring("GetSSID")
            } catch {
                if let fallback = ssidFallback {
                    if CameraWifiResolution.isSSIDOwnedByAnotherCamera(
                        fallback, cameraId: camera.id, saved: SavedCameraStore.load())
                    {
                        log.info(
                            "creds: GetSSID fallback \(fallback, privacy: .public) belongs to another camera"
                        )
                        throw Fail.wrongCamera
                    }
                    log.info("creds: GetSSID refused — using SSID \(fallback, privacy: .public)")
                    ssid = fallback
                } else {
                    throw Fail.mimoSession
                }
            }
        }

        do {
            let pass = try await readWifiString(
                name: "GetPassword", set: 0x07, cmd: 0x0E, cached: known.password
            ) { ble.send(Commands.getWifiPassword()) }
            return (ssid, pass)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as Fail where isDisconnect(error) {
            throw Fail.disconnectedDuring("GetPassword")
        } catch {
            if let pass = known.password, !pass.isEmpty {
                log.info("creds: GetPassword refused — using \(known.source, privacy: .public) password")
                return (ssid, pass)
            }
            throw Fail.mimoSession
        }
    }

    /// Ask until the camera returns a non-empty Wi-Fi string. First-time pairing leaves the
    /// AP down for a few seconds; a single 8 s wait mapped that to a vague Fail.
    /// 1-byte / `0xE0…0xEF` is a refuse (Mimo still holding the AP) — use cache or fail now.
    private func readWifiString(name: String, set: UInt8, cmd: UInt8, cached: String?,
                                send: () -> Void) async throws -> String {
        let holdKey = UInt16(set) << 8 | UInt16(cmd)
        let deadline = Date().addingTimeInterval(12)
        var last: Error = Fail.commandTimeout(name)
        var attempt = 0
        while Date() < deadline {
            attempt += 1
            // Stale 0x07/07 often lands during 0x53/0x10 — do not treat it as this write's reply.
            pairingHold.removeValue(forKey: holdKey)
            log.info("creds: \(name, privacy: .public) attempt \(attempt)")
            send()
            do {
                let frame = try await waitFrame(set, cmd, timeout: .seconds(4))
                let status = frame.payload.first ?? 0xFF
                let value = Duml.unpackStatusString(frame.payload)
                if !value.isEmpty {
                    log.info("creds: \(name, privacy: .public) ok (\(value.count) chars)")
                    return value
                }
                // 1-byte or 0xE0–0xEF: camera refused. Retrying the same GET will not help.
                if frame.payload.count <= 1 || (0xE0...0xEF).contains(status) {
                    if let cached, !cached.isEmpty {
                        log.info("creds: \(name, privacy: .public) status=\(status) (\(frame.payload.count)B) — using cached value")
                        return cached
                    }
                    throw Fail.credsRefused(name, status)
                }
                log.info("creds: \(name, privacy: .public) empty reply (status=\(status))")
                last = Fail.credsEmpty(name)
            } catch Fail.timeout {
                log.info("creds: \(name, privacy: .public) attempt \(attempt) timed out")
                last = Fail.commandTimeout(name)
            } catch Fail.disconnected {
                throw Fail.disconnectedDuring(name)
            } catch is CancellationError {
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(400))
        }
        if let cached, !cached.isEmpty {
            log.info("creds: \(name, privacy: .public) giving up — using cached value")
            return cached
        }
        throw last
    }

    private func isDisconnect(_ error: Fail) -> Bool {
        switch error {
        case .disconnected, .disconnectedDuring: true
        default: false
        }
    }

    enum Fail: LocalizedError {
        case creds, timeout, pairingTimeout, disconnected
        case commandTimeout(String), credsEmpty(String), disconnectedDuring(String)
        case credsRefused(String, UInt8)
        case mimoSession
        case staleSoftAP
        case wrongCamera
        var errorDescription: String? {
            switch self {
            case .creds: "couldn't read the camera's Wi-Fi credentials"
            case .timeout: "the camera stopped responding"
            case .pairingTimeout: "pairing timed out — tap Approve on the camera if it asked"
            case .disconnected: "the camera disconnected"
            case .commandTimeout(let name): "\(name) timed out — camera didn't reply (AP still coming up?)"
            case .credsEmpty(let name): "\(name) came back empty — camera AP not up yet"
            case .disconnectedDuring(let name): "the camera disconnected while reading \(name)"
            case .credsRefused(let name, let status):
                "\(name) refused (0x\(String(status, radix: 16))) — quit Mimo, power-cycle the camera, then tap once"
            case .mimoSession:
                "camera still in a Mimo session — quit Mimo, power-cycle the camera, then tap once"
            case .staleSoftAP:
                "iPhone is still on the other camera's Wi-Fi (Pocket and Nano both use 192.168.2.1). Forget that network in Settings → Wi-Fi, then tap Connect. The other camera can stay on."
            case .wrongCamera:
                "Bluetooth reached a different camera than the one you tapped. Pocket and Nano are separate — pick the Nano or Pocket row in the list."
            }
        }
    }
}
