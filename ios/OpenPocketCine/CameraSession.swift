import AVFoundation
import CoreBluetooth
import CoreGraphics
import Foundation
import MonitorUI
import Observation
import OpenCineAppKit
import OpenCineCameraControls
import class OpenCineCore.LocalVPNNotice
import struct OpenCineCore.SavedCamera
import OpenCineDJIApple
import OpenPocketViewCore
import UIKit
import os
import OpenCineMedia

/// Composes the DJI Apple connection/exchange/heartbeat owners with native picture, saved
/// credentials and operator policy. Drives the app's phase/status and remaining recovery policy.
@MainActor
@Observable
final class CameraSession {

    var phase: ConnectionPhase = .idle {
        didSet {
            if oldValue != phase {
                onChromePublished?()
                controlSeam?.sessionDidChange()
                connectPhaseChanged()
            }
        }
    }
    /// Watch relay and other chrome observers. Fires after a status publish or phase change.
    @ObservationIgnored var onChromePublished: (() -> Void)?
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
            if let lock = autoExposureLock, !lock.holds(newValue) { autoExposureLock = nil }
            // A pending AWB Lock is judged once the camera answers its Custom SET.
            if let lock = autoWhiteBalanceLock, !editorReconciliation.hasWhiteBalance, !lock.holds(newValue) {
                autoWhiteBalanceLock = nil
            }
            guard newValue != previous else { return }
            controlSeam?.sessionDidChange()
            guard
                LiveChromeThrottle.shouldNotify(
                    previous: previous, next: newValue,
                    elapsed: CFAbsoluteTimeGetCurrent() - lastStatusMutation
                )
            else {
                scheduleStatusFlush()
                return
            }
            publishStatusNow()
        }
    }
    var found: [DjiAppleSighting] = [] {
        didSet { onSightings?(found.map(Self.sighting)) }
    }
    /// A scan has run 20 s without a camera. The pair page then lists what to check.
    var scanLooksEmpty = false
    /// The shared connection flow's port (`DJIIntegration`, SHELL-02) listens here.
    @ObservationIgnored var onSightings: (([DJISighting]) -> Void)?
    @ObservationIgnored var onStage: ((DJIConnectionStage, String?) -> Void)?
    /// The app's saved cameras (the shared document): Wi-Fi credentials, the other-camera SSID
    /// guard and the station role a setup may have left.
    @ObservationIgnored var savedCameras: () -> [SavedCamera] = { [] }
    /// Asks the operator to turn Personal Hotspot on before a hotspot connect; `false` cancels.
    @ObservationIgnored var confirmHotspot: ((String) async -> Bool)?
    /// Why the last connect failed, for the port's typed failure.
    @ObservationIgnored var lastConnectError: Error?
    @ObservationIgnored var phaseWaiters: [CheckedContinuation<Void, Never>] = []
    /// The body this session is connecting / connected to. Used to persist a saved camera.
    private(set) var connectedCamera: DjiAppleSighting?
    /// Camera-AP SSID after a successful join. Re-read over BLE on the next connect.
    private(set) var joinedSSID: String?
    /// Setup for the next connect (#406); session recovery reuses it. Disconnect resets it.
    var connectionSetup: CameraConnectionSetup = .cameraWiFi
    /// Wi-Fi or Hotspot address that answered with this body's BLE identity.
    private(set) var stationHost: String?
    /// Network a Wi-Fi or Hotspot setup moved the camera onto.
    private(set) var stationSSID: String?
    /// Network of the Wi-Fi or Hotspot setup the next connect moves the camera onto.
    @ObservationIgnored var stationNetwork: String?
    /// Hotspot provisioning step; the camera card shows it as the step's live text.
    private(set) var setupProgress: String? {
        didSet { if setupProgress != oldValue { connectPhaseChanged() } }
    }

    /// Only used by the host's explicit Show Wi-Fi code sheet. Never advertised or logged.
    var watcherWiFiJoinCode: String? {
        guard let camera = connectedCamera, cachedWifiCameraId == camera.id,
            let ssid = joinedSSID, ssid == cachedSSID, let password = cachedPassword
        else { return nil }
        return CameraWiFiQRCode.payload(ssid: ssid, password: password)
    }

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
    /// Observable mirror of the decoded raster (`HevcDecoder` is not observable).
    private(set) var pictureAspect: CGFloat = LiveChromeMetrics.feedAspect
    private(set) var isVerticalPicture = false
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
    /// Pocket 3: one 1080→boot-4K SET after a black first picture. Not P4.
    @ObservationIgnored private lazy var firstPictureFormat = makeFirstPictureFormat()
    private var firstPictureFormatPoked: Bool { firstPictureFormat.snapshot.poked }
    /// One `0x09/0xa8` write in flight. Overlapping enables are a black well.
    @ObservationIgnored private var incidentSessionActive = false
    @ObservationIgnored private var incidentPrevious: (at: Double, counts: [Int])?
    @ObservationIgnored private var incidentSocketGeneration = 0
    @ObservationIgnored var incidentSettingsCovered = false

    /// `0x09/0xa8` sends while `awaitingIDR` is still true. Caps the mid-session
    /// IDR retry at one extra enable so a missed keyframe cannot 1 Hz loop.
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
    /// Last zoom `0xB8` SET. Same grace as AF-C while the lens slews.
    @ObservationIgnored private var lastZoomSetAt: Date?
    private var secondsSinceZoomSet: TimeInterval? {
        [lastZoomSetAt.map { Date().timeIntervalSince($0) }, datalink?.secondsSinceNativeZoomSet]
            .compactMap { $0 }.min()
    }
    private var secondsSinceGimbalThrow: TimeInterval? {
        gimbal.lastThrowAt.map { Date().timeIntervalSince($0) }
    }
    @ObservationIgnored private var feedWatchdog = FeedWatchdog()
    @ObservationIgnored private var lastFeedFreezeLogAt: Date?
    @ObservationIgnored lazy var pictureRecovery = makePictureRecovery()
    @ObservationIgnored private var liveViewSource: DjiAppleLiveViewScope?
    private var liveViewHistory: DjiAppleLiveViewHistory {
        pictureRecovery.liveViewHistory
    }
    @ObservationIgnored private let pictureRecoveryTiming: DjiApplePictureRecoveryTiming
    @ObservationIgnored private var foregroundCheckTask: Task<Void, Never>?
    @ObservationIgnored private var foregroundGeneration = 0
    @ObservationIgnored private var statusStorage = CameraStatus()
    @ObservationIgnored private(set) var cameraReportedCapture = CameraStatus()
    @ObservationIgnored private var lastStatusMutation: CFAbsoluteTime = 0
    @ObservationIgnored private var statusFlushTask: Task<Void, Never>?

    @ObservationIgnored private let ble = DjiAppleBluetoothLink(host: .pocket)
    @ObservationIgnored var datalink: DjiAppleDatalink? {
        didSet {
            if oldValue !== datalink {
                controlExchange.endpoint = .init(bluetooth: ble, datalink: datalink)
                sessionHeartbeat.endpoint = .init(bluetooth: ble, datalink: datalink)
                controlSeam?.linkDidChange()
            }
        }
    }
    /// OpenCineCore seam for ISO, white balance and record (CORE-02). UI controls submit here.
    var control: DJICameraSessionAdapter {
        controlBinding.session
    }
    @ObservationIgnored private lazy var controlBinding = makeControlSessionBinding()
    private var controlSeam: DJICameraSessionAdapter? { controlBinding.cached }
    @ObservationIgnored private lazy var controlExchange = makeControlExchange()
    @ObservationIgnored lazy var sessionHeartbeat = makeSessionHeartbeat()
    @ObservationIgnored private let heartbeatTiming: DjiAppleHeartbeatTiming
    /// Last pid `0x38` GET reply. BLE fallback fires when this goes stale.
    @ObservationIgnored private var lastSelfieFlipReplyAt: Date?
    @ObservationIgnored private let log = Logger(
        subsystem: "com.opencapture.openpocketcine", category: "session")
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanHintTask: Task<Void, Never>?
    @ObservationIgnored private lazy var connectionRun = makeConnectionRun()
    #if DEBUG
        @ObservationIgnored var connectionNativePeers: ConnectionNativePeers?
        @ObservationIgnored var sessionRecoveryNativePeers: SessionRecoveryNativePeers?
        /// DEBUG watchdog/adopter probe clock; nil uses the normal wall clock.
        /// Recipe/repair timing is the immutable pictureRecoveryTiming passed at init.
        @ObservationIgnored var liveViewDonorTiming: DjiApplePictureRecoveryTiming?
    #endif
    private var connectionTransport: DjiAppleConnectionTransport {
        #if DEBUG
            if let trace = connectionNativePeers { return trace.transport }
        #endif
        return .init(bluetooth: ble, host: .pocket)
    }
    private var connectionTiming: DjiAppleConnectionTiming {
        #if DEBUG
            if let trace = connectionNativePeers { return trace.timing }
        #endif
        return .continuous
    }
    @ObservationIgnored private var reconnectTarget: UUID?
    @ObservationIgnored private lazy var recoveryEpisode = makeRecoveryEpisode()
    @ObservationIgnored private var recoverySnapshotStorage = DjiAppleRecoveryEpisode.Snapshot()
    @ObservationIgnored private var recoveryDeviceNameStorage = ""
    /// Also used by saved-camera discovery outside an automatic episode.
    private(set) var isReconnecting: Bool {
        get { access(keyPath: \.isReconnecting); return recoverySnapshotStorage.reconnecting }
        set {
            guard recoverySnapshotStorage.reconnecting != newValue else { return }
            recoverySnapshotStorage.reconnecting = newValue
            withMutation(keyPath: \.isReconnecting) {}
        }
    }
    /// Saved-list row that owns the current connection attempt, including discovery.
    private(set) var connectionTargetID: UUID?
    /// Compatibility projections publish after authoritative storage, so synchronous
    /// observation cannot let canceled A overwrite a successor B's recovery presentation.
    var sessionRecovery: SessionRecoveryState {
        get { access(keyPath: \.sessionRecovery); return recoverySnapshotStorage.state }
        set {
            guard recoverySnapshotStorage.state != newValue else { return }
            recoverySnapshotStorage.state = newValue
            withMutation(keyPath: \.sessionRecovery) {}
        }
    }
    var holdsMonitor: Bool {
        get { access(keyPath: \.holdsMonitor); return recoverySnapshotStorage.holdsPicture }
        set {
            guard recoverySnapshotStorage.holdsPicture != newValue else { return }
            recoverySnapshotStorage.holdsPicture = newValue
            withMutation(keyPath: \.holdsMonitor) {}
        }
    }
    var sessionRecoveryCardGraceElapsed: Bool {
        get { access(keyPath: \.sessionRecoveryCardGraceElapsed); return recoverySnapshotStorage.cardGraceElapsed }
        set {
            guard recoverySnapshotStorage.cardGraceElapsed != newValue else { return }
            recoverySnapshotStorage.cardGraceElapsed = newValue
            withMutation(keyPath: \.sessionRecoveryCardGraceElapsed) {}
        }
    }
    /// App content, captured at drop before the connected identity is cleared.
    var recoveryDeviceName: String {
        get { access(keyPath: \.recoveryDeviceName); return recoveryDeviceNameStorage }
        set {
            guard recoveryDeviceNameStorage != newValue else { return }
            recoveryDeviceNameStorage = newValue
            withMutation(keyPath: \.recoveryDeviceName) {}
        }
    }
    /// Watchdog is running a staged feed recover (enable → VT → UDP → rejoin).
    private(set) var feedRecovering = false
    /// Cover the feed well until a rolling picture exists (not a frozen first IDR).
    private(set) var isFeedWarming = true
    /// In-flight record / mode / param write. UI disables the rec lamp while true.
    private(set) var controlBusy = false
    /// Last camera-control reply (empty when the last command succeeded).
    var controlNote: String?
    /// Live extra-mirror (TT180 && Flip off). Shell XORs MIRROR assist.
    var gimbalPoseViewFlip = false
    /// Pocket 3-axis only. Nano hides the gimbal button and sheet.
    var hasGimbal: Bool { connectedCamera?.model.hasGimbal ?? false }
    /// Nano is a fixed 1× prime: no zoom chrome and no zoom SET from any input.
    var supportsZoom: Bool { connectedCamera?.model.supportsZoom ?? false }
    var gimbalMode: GimbalMode = .follow
    var gimbalSpeed: GimbalSpeed = .defaultSpeed
    var gimbalRamp: GimbalRamp = OperatorPrefs.gimbalRamp
    var gimbalDoubleTap: GimbalDoubleTap = OperatorPrefs.gimbalDoubleTap
    var gimbalProgram = GimbalProgram()
    var gimbalMoveRunning = false
    var gimbalMovePaused = false
    var gimbalMoveCanPause = false
    var gimbalStartCountdown: Int?
    private(set) var gimbalControlSceneActive = true
    /// Pose-only stick invert (TT180). Shell XORs MIRROR assist.
    var gimbalPoseInvertPan = false
    /// Increments on a rising-edge gimbal-limit contact. Shell plays haptics.
    var gimbalLimitPulse: UInt = 0
    var gimbalLimitContact: GimbalLimitWatch.Contact = []
    var gimbalLimitPanSign: Double = 0
    var gimbalLimitTiltSign: Double = 0
    /// Camera-library listing while the Media page is open.
    var mediaLibraryOwner: MonitorMediaLibraryModel<MediaFile>?
    @ObservationIgnored var mediaLibraryCameraID: String?
    var mediaFiles: [MediaFile] {
        mediaLibraryOwner?.records.map { record in
            var file = record.payload; file.isStarred = record.favorite; return file
        } ?? []
    }
    var mediaFetchInProgress: Bool { mediaLibraryOwner.map { $0.acquiringSource || $0.fetching } ?? false }
    var mediaFetchListedCount: Int { mediaLibraryOwner?.fetchedCount ?? 0 }
    var mediaOperationNote: String?
    var mediaNote: String? {
        get { mediaOperationNote ?? mediaLibraryOwner?.note }
        set { mediaOperationNote = newValue }
    }
    /// While true, keepalive must not re-enable live view or recover the feed.
    var isBrowsingMedia: Bool {
        get { mediaLibraryOwner?.browsing ?? false }
        set { if newValue { mediaLibrary.begin() } else { mediaLibraryOwner?.close() } }
    }
    /// The camera body is showing its own gallery during an established live
    /// session. Like DJI Mimo, the live screen opens Media while this is true and
    /// closes it (returning the camera to live) when it turns false (#273).
    private(set) var cameraGalleryOpen = false
    @ObservationIgnored private var cameraGalleryAwayTicks = 0
    var mediaDownloadProgress: [String: Double] {
        Dictionary((mediaLibraryOwner?.hostProgress ?? [:]).map { ($0.key.rawValue, $0.value) },
            uniquingKeysWith: { _, latest in latest })
    }
    var mediaIOCacheRevision: UInt64 = 0
    var mediaCacheRevision: UInt64 { mediaIOCacheRevision &+ (mediaLibraryOwner?.cacheRevision ?? 0) }
    @ObservationIgnored let cameraMedia: CameraMedia
    /// Last tap-to-focus point in feed-normalized 0…1. Always drawn when not tracking.
    var focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    /// Feed long-press AE lock. Any status that no longer `holds` it clears it.
    private(set) var autoExposureLock: AutoExposureLock?
    /// WB Mode AWB Lock. Cleared like `autoExposureLock` when status stops holding it.
    private(set) var autoWhiteBalanceLock: AutoWhiteBalanceLock?
    /// Operator-drawn search rect while the camera is still hunting a subject.
    var searchBox: TrackingBox? {
        access(keyPath: \.searchBox)
        return subjectTracking.snapshot.searchBox
    }
    /// Locked subject box. Camera floats when `0xA5` carries them; else a tight stand-in.
    var subjectBox: TrackingBox? {
        access(keyPath: \.subjectBox)
        return subjectTracking.snapshot.subjectBox
    }
    /// True after `0xA5` replies `00 01 00 00`.
    var isTracking: Bool {
        access(keyPath: \.isTracking)
        return subjectTracking.snapshot.tracking
    }
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
    /// HEVC silent, a repair in flight, or clocks wiped after a live GOP.
    var isLiveVideoStale: Bool {
        let recovering =
            feedRecovering || pictureRecovery.isBusy || datalink?.isRebuilding == true
        let videoAge = datalink?.lastVideoPacketAt.map { Date().timeIntervalSince($0) }
        let had = FeedWatchdog.hadVideo(
            videoPackets: datalink?.videoPackets ?? 0, lastVideoPacketAge: videoAge)
        return FeedWatchdog.shouldTreatLiveVideoAsStale(
            lastVideoPacketAge: videoAge, hadVideo: had, recovering: recovering)
    }
    @ObservationIgnored private lazy var subjectTracking = makeSubjectTracking()
    @ObservationIgnored private let subjectTrackingTiming: DjiAppleTrackingTiming
    @ObservationIgnored private var lastFaceAt: Date?
    @ObservationIgnored private var lastFaceHitAt: Date?
    @ObservationIgnored private var lastTapFocusAt: Date?
    /// Operator tap only; camera-adopted points do not start the stale-echo hold.
    @ObservationIgnored private var lastFocusTapAt: Date?
    @ObservationIgnored private var feedDoubleTap = FeedDoubleTapTrack()
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
    @ObservationIgnored private lazy var zoomGesture = makeZoomGesture()
    var zoomStop: Double {
        access(keyPath: \.zoomStop)
        return zoomGesture.snapshot.stop
    }
    var zoomStops: [Double] {
        connectedCamera?.model.activeZoomStops(
            resolution: status.videoResolution, shootingMode: status.shootingMode)
            ?? CamFov.jumps
    }
    var zoomMax: Double { zoomStops.last ?? 1 }
    var zoomPinchPreview: Double? {
        access(keyPath: \.zoomPinchPreview)
        return zoomGesture.snapshot.preview
    }
    var zoomOptimistic: Double? {
        access(keyPath: \.zoomOptimistic)
        return zoomGesture.snapshot.optimistic
    }

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
    private var controlGeneration: Int { controlExchange.generation }
    /// Audio GET→patch→SET round trips ride their own chain, off the SET path.
    @ObservationIgnored private lazy var cameraSettings = makeCameraSettings()
    @ObservationIgnored private lazy var editorReconciliation = makeEditorReconciliation()
    @ObservationIgnored private lazy var tapFocus = makeTapFocus()
    @ObservationIgnored private lazy var zoomColor = makeZoomColor()
    /// Shared owner commits actual hop state before notifying native observation.
    var zoomColorHopPending: Bool {
        access(keyPath: \.zoomColorHopPending)
        return zoomColor.snapshot.hopPending
    }
    /// After a local ISO / shutter / expo SET, ignore subscribe snapshots that have not caught up.
    /// After a local res+fps / color SET, ignore subscribe snapshots that have not caught up.
    /// FORMAT sheet: skip reseat while `0x02/0x18` is in flight.
    var isFormatPinActive: Bool { editorReconciliation.hasFormat }
    /// Requested white balance remains separate from actual camera status.
    var pendingWhiteBalance: WhiteBalance? {
        access(keyPath: \.pendingWhiteBalance)
        return editorReconciliation.requestedWhiteBalance
    }
    @ObservationIgnored let decoder: HevcDecoder
    /// Stick, mode/speed pins, pose, level, head-track targets and programmed moves.
    @ObservationIgnored private(set) lazy var gimbal = DjiAppleGimbalControl(host: self)
    var isMultiviewBorrowed = false
    private(set) var isMultiviewControlsOnly = false
    @ObservationIgnored var multiviewControlAdmission: (() -> Bool)?
    var admitsMultiviewControl: Bool {
        !isMultiviewControlsOnly || multiviewControlAdmission?() == true
    }

    /// A camera SET can go on the wire now (the `fireCamera` admission rule).
    var controlLinkReady: Bool {
        admitsMultiviewControl && datalink != nil && datalink?.isRebuilding != true
    }

    /// The live-view display layer, for the SwiftUI `VideoView`.
    var videoLayer: AVSampleBufferDisplayLayer { decoder.displayLayer }

    init(
        borrowing sharedDecoder: HevcDecoder? = nil, cameraMedia: CameraMedia? = nil,
        controlsOnly: Bool = false, heartbeatTiming: DjiAppleHeartbeatTiming? = nil,
        pictureRecoveryTiming: DjiApplePictureRecoveryTiming? = nil,
        subjectTrackingTiming: DjiAppleTrackingTiming? = nil
    ) {
        self.heartbeatTiming = heartbeatTiming ?? .continuous
        self.pictureRecoveryTiming = pictureRecoveryTiming ?? .continuous
        self.subjectTrackingTiming = subjectTrackingTiming ?? .continuous
        self.cameraMedia = cameraMedia ?? CameraMedia()
        self.decoder = sharedDecoder ?? HevcDecoder()
        if sharedDecoder != nil, controlsOnly {
            isMultiviewBorrowed = true
            isMultiviewControlsOnly = true
            return
        }
        gimbal.syncPose()
        if sharedDecoder != nil {
            isMultiviewBorrowed = true
            self.decoder.onSourceFrame = { [weak self] lease in
                if let buffer = lease.pixelBuffer { self?.considerFaceAF(buffer) }
            }
            return
        }
        decoder.sourceCalibrationProvider = { [weak self] in
            guard let self, self.cameraReportedCapture.iso > 0 else { return nil }
            return self.cameraReportedCapture.iso
        }
        self.decoder.onPresentedFrame = { [weak self] in
            self?.noteLiveFrame()
        }
        decoder.onSourceFrame = { [weak self] lease in
            if let buffer = lease.pixelBuffer { self?.considerFaceAF(buffer) }
        }
        // Look/scope toggles change which decoder owns HEVC; neither side can
        // start mid-GOP, so one 0x09/0xa8 forces the IDR. 1 s floor: rapid A/B
        // toggling collapses to one enable — the keepalive IDR retry backstops it.
        decoder.onHandoffNeedsIDR = { [weak self] in
            guard let self else { return }
            if self.isBrowsingMedia { return }
            let since = Date().timeIntervalSince(self.liveViewHistory.lastAcceptedEnableWallTime)
            guard
                FeedWatchdog.shouldSendEnableForAssistVTStart(
                    secondsSinceLastEnable: since,
                    hasPresentedPicture: self.decoder.lastPresentedAt != nil,
                    liveViewEnableSends: self.liveViewHistory.locallyAcceptedEnables)
            else { return }
            self.sendRecoverEnable(force: true, reason: "assist VT start")
        }
        decoder.onPictureSizeChanged = { [weak self] in
            guard let self else { return }
            if self.pictureAspect != self.decoder.pictureAspect {
                self.pictureAspect = self.decoder.pictureAspect
            }
            if self.isVerticalPicture != self.decoder.isVerticalPicture {
                self.isVerticalPicture = self.decoder.isVerticalPicture
            }
        }
        decoder.onParameterSetsChanged = { [weak self] in
            guard let self else { return }
            if self.isBrowsingMedia { return }
            let now = Date()
            let videoAge = self.datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) }
            let auAge = self.datalink?.lastAccessUnitAt.map { now.timeIntervalSince($0) }
            let videoAlive =
                (videoAge ?? .infinity) < FeedWatchdog.stallThreshold
                || (auAge ?? .infinity) < FeedWatchdog.stallThreshold
            guard
                EncoderPresentPath.shouldRequestEnableAfterParameterChange(
                    accessUnitHasIDR: false,
                    udpReceiveAlive: videoAlive,
                    secondsSinceLastEnable: now.timeIntervalSince(self.liveViewHistory.lastAcceptedEnableWallTime)
                )
            else { return }
            self.sendRecoverEnable(force: false, reason: "encoder format change")
        }
    }

    /// Borrow the tile's transport and decoder; Multiview remains the sole repair owner.
    func updateMultiview(camera: DjiAppleSighting, driver: DjiAppleDatalink?, status: CameraStatus) {
        guard isMultiviewBorrowed else { return }
        if connectedCamera?.id != camera.id {
            controlBinding.beginConnection()
            cameraReportedCapture = CameraStatus()
        }
        connectedCamera = camera
        datalink = driver
        // Tile settings are decoded reports; editor pins live only in this borrowed session.
        cameraReportedCapture = status
        self.status = status
        controlSeam?.sessionDidChange()
        phase = .live
        hasVideoFormat = decoder.hasFormat
        isFeedWarming = decoder.lastPresentedAt == nil
    }
    /// Hand the pose back to the tile so a Live View pan or TT180 survives close.
    var multiviewPose: GimbalStickMapping { gimbal.stickMapping }
    func adoptMultiviewPose(_ pose: GimbalStickMapping) {
        guard isMultiviewBorrowed, !isMultiviewControlsOnly else { return }
        gimbal.adoptPose(pose)
    }
    func noteMultiviewFrame() {
        guard isMultiviewBorrowed, !isMultiviewControlsOnly else { return }
        noteLiveFrame()
    }
    func receiveMultiview(_ frame: Duml.Frame) {
        guard isMultiviewBorrowed else { return }
        applyIncomingStatus(frame)
        guard !isMultiviewControlsOnly else { return }
        // Per tile status frame: an unchanged write re-renders the tile chrome.
        let warming = decoder.lastPresentedAt == nil
        if warming != isFeedWarming { isFeedWarming = warming }
    }
    func releaseMultiview() {
        guard isMultiviewBorrowed else { return }
        controlBinding.retire(.requested)
        cameraReportedCapture = CameraStatus()
        editorReconciliation.clearFormat()
        if isMultiviewControlsOnly {
            // Detach only this editor's commands. The tile keeps its transport,
            // decoder callbacks, frame samples, pose and recovery ownership.
            datalink = nil
            multiviewControlAdmission = nil
            phase = .idle
            cameraSettings.retire()
            controlExchange.retire(CancellationError())
            return
        }
        gimbal.endStick(cancelMove: true)
        subjectTracking.stopPolling()
        tapFocus.retire()
        faceAFArmTask?.cancel()
        controlExchange.retire(CancellationError())
        datalink = nil
    }

    func startScan() {
        startScan(reconnect: nil)
    }

    /// Scan for Pockets. If `id` is set, connect the matching peripheral as soon as it appears
    /// (saved-camera reconnect). Does not stop the scan before GATT connect — iOS needs the
    /// next advertisement to finish the link.
    func startScan(reconnect id: UUID?) {
        if id != nil, !holdsMonitor {
            controlBinding.beginConnection()
            cameraReportedCapture = CameraStatus()
        }
        abortInFlightRun()
        reconnectTarget = id
        connectionTargetID = id
        isReconnecting = id != nil
        phase = .scanning
        found = []
        scanLooksEmpty = false
        scanTask?.cancel()
        scanHintTask?.cancel()
        scanTask = Task {
            guard await ble.waitUntilPoweredOn(), !Task.isCancelled else {
                if !Task.isCancelled {
                    ControlLiveLog.line("ble: scan blocked \(ble.stateSummary)")
                    phase = .failed(ble.unavailableReason)
                }
                return
            }
            scanHintTask = Task {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, phase == .scanning, found.isEmpty else { return }
                ControlLiveLog.line("ble: no camera after 20 s of scanning \(ble.stateSummary)")
                scanLooksEmpty = true
            }
            for await camera in ble.scan() {
                if Task.isCancelled { break }
                let seen = camera.enriched(from: saved(camera.id))
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

    /// Discovery stops only while nothing connects: a scan that finds the camera to connect keeps
    /// running, and a connect in flight is never touched.
    func stopScan() {
        guard !connectionRun.isRunning, reconnectTarget == nil, phase == .scanning || phase == .idle else {
            return
        }
        scanTask?.cancel()
        scanHintTask?.cancel()
        ble.stopScan()
        if phase == .scanning { phase = .idle }
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

    func connect(_ camera: DjiAppleSighting) {
        connect(camera, preserveMonitor: holdsMonitor)
    }

    private func connect(_ camera: DjiAppleSighting, preserveMonitor: Bool) {
        guard !isMultiviewBorrowed else { return }
        let camera = camera.enriched(from: saved(camera.id))
        if case .live = phase, connectedCamera?.id == camera.id, !sessionRecovery.isRecovering {
            return
        }
        guard let route = prepareConnectionNative(camera, preserveMonitor: preserveMonitor) else { return }
        connectionRun.replace(target: recoverySighting(camera), route: route, preservingSource: preserveMonitor)
    }

    /// Permissions, saved app identity and native source lifetime remain host policy.
    /// An episode supplies captured authority; ordinary explicit connect preserves its path.
    private func prepareConnectionNative(_ camera: DjiAppleSighting, preserveMonitor: Bool,
        recoveryAttempt: DjiAppleRecoveryEpisode.Attempt? = nil) -> DJIConnectionRoute? {
        let isCurrent = { recoveryAttempt?.isCurrent ?? true }
        guard isCurrent(), !isMultiviewBorrowed else { return nil }
        if !preserveMonitor {
            controlBinding.beginConnection()
            guard isCurrent() else { return nil }
            cameraReportedCapture = CameraStatus()
        }
        AppDiagnostics.reporting.setCameraSessionActive(true)
        guard isCurrent() else { return nil }
        LocalVPNNotice.app.noteIfActive()
        guard isCurrent() else { return nil }
        LocalNetworkAccess.requestEarly()
        guard isCurrent() else { return nil }
        scanTask?.cancel()
        scanHintTask?.cancel()
        abortInFlightRun(preserveDecoder: preserveMonitor, recoveryAttempt: recoveryAttempt)
        guard isCurrent() else { return nil }
        reconnectTarget = nil
        isReconnecting = preserveMonitor
        guard isCurrent() else { return nil }
        connectedCamera = camera
        guard isCurrent() else { return nil }
        if !incidentSessionActive { beginFeedIncidentSession(cameraFamily: camera.model.name) }
        guard isCurrent() else { return nil }
        connectionTargetID = camera.id
        guard isCurrent() else { return nil }
        phase = .connectingGatt
        guard isCurrent() else { return nil }
        return switch connectionSetup {
        case .cameraWiFi: .cameraAccessPoint
        case .wifi: .infrastructureNetwork
        case .phoneHotspot: .phoneHotspot
        }
    }

    func disconnect() {
        if isMultiviewBorrowed {
            releaseMultiview()
            return
        }
        controlBinding.retire(.requested)
        cameraReportedCapture = CameraStatus()
        // Before the link closes: do not leave the camera on Fast for the next session.
        gimbal.restorePrepNow()
        AppDiagnostics.reporting.setCameraSessionActive(false)
        AppDiagnostics.incidents.endSession(now: ProcessInfo.processInfo.systemUptime)
        incidentSessionActive = false
        incidentPrevious = nil
        reconnectTarget = nil
        connectionTargetID = nil
        isReconnecting = false
        cancelSessionRecovery()
        holdsMonitor = false
        scanTask?.cancel()
        abortInFlightRun()
        connectedCamera = nil
        connectionSetup = .cameraWiFi
        stationNetwork = nil
        stationHost = nil
        stationSSID = nil
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
        cameraSettings.retire()
        tapFocus.retire()
        faceAFArmTask?.cancel()
        faceAFArmTask = nil
        faceAFArmed = false
        firstPictureSettled = false
        zoomGesture.reset()
        editorReconciliation.retire()
        autoExposureLock = nil
        autoWhiteBalanceLock = nil
        resetGimbalPoseForNewStream()
        gimbal.resetControls()
        controlBusy = false
        controlNote = nil
        focusPoint = CGPoint(x: 0.5, y: 0.5)
        subjectTracking.reset()
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
        gimbal.dropStick()
        videoPackets = 0
        accessUnits = 0
        framesEnqueued = 0
        droppedIncomplete = 0
        decoderErrors = 0
        hasVideoFormat = false
        nalTypes = ""
        lastKeyframeAge = "—"
        if let source = liveViewSource { pictureRecovery.retireLiveView(scope: source) }
        liveViewSource = nil
        firstPictureFormat.reset()
        audioRefreshPending = false
        glamourClearPending = false
        focusTrackPending = false
        needsForegroundRecover = false
        resetLinkHealthMeasurements()
        resetFeedWatchdog()
        resetMediaSession()
    }

    func forgetWifiCreds(for camera: SavedCamera) {
        guard let id = UUID(uuidString: camera.id) else { return }
        forgetWifiCreds(cameraId: id, advertisedName: camera.advertisedName, ssid: camera.lastSSID)
    }

    /// The saved camera of a peripheral, from the shared document.
    func saved(_ id: UUID) -> SavedCamera? {
        savedCameras().first { $0.id == id.uuidString }
    }

    private func forgetWifiCreds(cameraId: UUID, advertisedName: String?, ssid: String?) {
        #if DEBUG
            if let trace = connectionNativePeers { trace.forget(); return }
        #endif
        CameraWifiKeychain.delete(
            cameraId: cameraId, advertisedName: advertisedName, lastSSID: ssid)
        if connectedCamera?.id == cameraId || cachedWifiCameraId == cameraId {
            cachedSSID = nil
            cachedPassword = nil
            cachedWifiCameraId = nil
        }
    }

    /// Tear down an in-flight `run` without resetting UI phase. BLE disconnect
    /// resumes a pending `ble.connect` so the old Task cannot keep writing 0x07/45.
    private func abortInFlightRun(preserveDecoder: Bool = false, preserveSoftAP: Bool = false,
        recoveryAttempt: DjiAppleRecoveryEpisode.Attempt? = nil) {
        let isCurrent = { recoveryAttempt?.isCurrent ?? true }
        guard isCurrent() else { return }
        sessionHeartbeat.resetPathGrace()
        guard isCurrent() else { return }
        setupProgress = nil
        guard isCurrent() else { return }
        foregroundGeneration += 1
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        gimbal.cancelProgrammedMove(ifCurrent: isCurrent)
        guard isCurrent() else { return }
        if let recoveryAttempt {
            guard recoveryAttempt.retireCapturedConnectionRun() else { return }
        } else {
            connectionRun.retire()
        }
        sessionHeartbeat.stop()
        guard isCurrent() else { return }
        lastSelfieFlipReplyAt = nil
        controlExchange.stopBLEDrain()
        guard isCurrent() else { return }
        controlExchange.retire(Fail.disconnected)
        guard isCurrent() else { return }
        commandTimeoutsAt.removeAll()
        gimbal.dropStick(ifCurrent: isCurrent)
        guard isCurrent() else { return }
        disposeDatalink(ifCurrent: isCurrent)
        guard isCurrent() else { return }
        ble.disconnect()
        guard isCurrent() else { return }
        if let source = liveViewSource { pictureRecovery.retireLiveView(scope: source) }
        liveViewSource = nil
        firstPictureFormat.reset()
        audioRefreshPending = false
        glamourClearPending = false
        focusTrackPending = false
        faceAFArmTask?.cancel()
        faceAFArmTask = nil
        faceAFArmed = false
        guard isCurrent() else { return }
        firstPictureSettled = false
        needsForegroundRecover = false
        resetFeedWatchdog(ifCurrent: isCurrent)
        guard isCurrent() else { return }
        resetMediaSession(ifCurrent: isCurrent)
        guard isCurrent() else { return }
        if preserveDecoder {
            decoder.flushForRecovery()
        } else {
            decoder.reset()
        }
        guard isCurrent() else { return }
        if !preserveSoftAP, let ssid = joinedSSID {
            DjiAppleWiFiJoiner.leave(ssid: ssid)
            guard isCurrent() else { return }
            joinedSSID = nil
        }
    }

    // ---- the flow --------------------------------------------------------------------------------

    private func makeConnectionRun() -> DjiAppleConnectionRun {
        DjiAppleConnectionRun(transport: connectionTransport, exchange: controlExchange,
            heartbeat: sessionHeartbeat, credentials: .init(
                savedPath: { [weak self] target, route in
                    guard let self, let camera = self.connectionCamera(target) else { return .init() }
                    let saved = self.saved(camera.id)
                    let setup: CameraConnectionSetup = route == .phoneHotspot ? .phoneHotspot
                        : route == .infrastructureNetwork ? .wifi : .cameraWiFi
                    let networkSSID = setup.movesCamera ? self.stationNetwork ?? saved?.ssid(for: setup) : nil
                    let network = networkSSID.flatMap { self.connectionRunStationNetwork(ssid: $0) }
                    return .init(isSaved: saved != nil, mayBeInStationRole: saved?.mayBeInStationRole == true,
                        station: network.map { .init(ssid: $0.ssid, password: $0.password) })
                }, resolveWiFi: { [weak self] target in
                    guard let self, let camera = self.connectionCamera(target) else { return .init() }
                    let known = self.resolvedWifiCreds(for: camera)
                    return .init(ssid: known.ssid, password: known.password,
                        source: known.source, skipBLE: known.skipBle)
                }, joinPolicy: { [weak self] target, ssid, isSaved in
                    guard let self, let id = UUID(uuidString: target.id) else { return .init() }
                    return .init(persist: CameraSoftAP.shouldPersistHotspot(
                        isSavedCamera: isSaved || self.cachedWifiCameraId == id),
                        otherSSIDs: self.leftoverSoftAPSSIDs(besides: ssid))
                }, validateSSID: { [weak self] target, ssid, use in
                    guard let self, let camera = self.connectionCamera(target) else { throw CancellationError() }
                    switch use {
                    case .fallback:
                        if CameraWifiResolution.isSSIDOwnedByAnotherCamera(
                            ssid, cameraId: target.id, saved: self.savedCameras()) { throw Fail.wrongCamera }
                    case .join: try self.assertSSIDBelongs(to: camera, ssid: ssid)
                    }
                }, persist: { [weak self] target, ssid, password in
                    guard let self, let camera = self.connectionCamera(target) else { return }
                    self.persistWifiCreds(camera: camera, ssid: ssid, password: password)
                }, rejectCached: { [weak self] target, ssid in
                    guard let self, let id = UUID(uuidString: target.id) else { return }
                    self.forgetWifiCreds(cameraId: id, advertisedName: target.name, ssid: ssid)
                }), native: .init(observe: { [weak self] in
                    guard let self else { return .init() }
                    return .init(ownsConnection: !self.isMultiviewBorrowed, endpoint: self.connectionRunEndpoint,
                        path: .init(joinedSSID: self.joinedSSID, stationSSID: self.stationSSID,
                            stationHost: self.stationHost), initialLiveViewEnableSent: self.liveViewHistory.initialAccepted)
                }, prepare: { [weak self] target, _, attempt in
                    guard let self, let camera = self.connectionCamera(target), attempt.isCurrent else { return }
                    self.prepareConnectionSource(camera, attempt: attempt)
                }, attach: { [weak self] endpoint, _, attempt in
                    self?.attachConnectionEndpoint(endpoint, attempt: attempt)
                }, registered: { [weak self] endpoint, _, attempt in
                    self?.registerConnectionEndpoint(endpoint, attempt: attempt)
                }), timing: connectionTiming, event: { [weak self] event in
                    self?.connectionRunEvent(event)
                }, journal: { ControlLiveLog.line($0) },
            info: { [weak self] line in self?.log.info("\(line, privacy: .public)") })
    }

    private func connectionCamera(_ target: DJISighting) -> DjiAppleSighting? {
        guard let id = UUID(uuidString: target.id) else { return nil }
        return DjiAppleSighting(id: id, name: target.name, model: target.model, modelId: target.modelId)
    }

    private func prepareConnectionSource(_ camera: DjiAppleSighting, attempt: DjiAppleConnectionRun.Attempt) {
        guard attempt.isCurrent, !isMultiviewBorrowed else { return }
        connectedCamera = camera
        guard attempt.isCurrent else { return }
        status.meteredEv = nil
        guard attempt.isCurrent else { return }
        rawAccessUnits = 0
        rawFramesEnqueued = 0
        guard let source = pictureRecovery.prepareLiveViewSource(run: attempt,
            recipe: .captured(from: camera.model)), attempt.isCurrent else { return }
        liveViewSource = source
        firstPictureFormat.reset()
        audioRefreshPending = true
        glamourClearPending = true
        focusTrackPending = true
        faceAFArmTask?.cancel()
        faceAFArmTask = nil
        faceAFArmed = false
        guard attempt.isCurrent else { return }
        firstPictureSettled = false
        needsForegroundRecover = false
        resetLinkHealthMeasurements(ifCurrent: { attempt.isCurrent })
        guard attempt.isCurrent else { return }
        resetFeedWatchdog(ifCurrent: { attempt.isCurrent })
        guard attempt.isCurrent else { return }
        // Session recovery holds the last frame (Android parity). `reset()` is
        // `flushAndRemoveImage` — abortInFlightRun already flushed for recovery.
        if !holdsMonitor { decoder.reset() }
        guard attempt.isCurrent else { return }
        resetGimbalPoseForNewStream()
        guard attempt.isCurrent else { return }
        // Camera is still pushing the last GOP. Hold before UDP opens so
        // leftover P-frames cannot set lastPresentedAt and skip first-picture.
        decoder.beginIDRHold()
        guard attempt.isCurrent else { return }
    }

    private func connectionRunEvent(_ event: DjiAppleConnectionRun.Event) {
        guard let runID = connectionRun.currentRunID else { return }
        switch event {
        case .stage(let stage, let text):
            let next: ConnectionPhase = switch stage {
            case .scanning: .scanning
            case .connectingBluetooth: .connectingGatt
            case .pairing: .pairing
            case .awaitingApproval: .awaitingApproval
            case .readingWiFi: .readingWifiCreds
            case .joiningWiFi, .findingCamera: .joiningWifi
            case .openingDatalink: .openingDatalink
            }
            phase = next
            // Phase observers may synchronously disconnect or replace this run.
            guard connectionRun.currentRunID == runID else { return }
            setupProgress = text
        case .progress(let text): setupProgress = text
        case .path(let path):
            joinedSSID = path.joinedSSID
            guard connectionRun.currentRunID == runID else { return }
            stationSSID = path.stationSSID
            guard connectionRun.currentRunID == runID else { return }
            stationHost = path.stationHost
        case .finished(let result, let preservingSource):
            setupProgress = nil
            guard connectionRun.currentRunID == runID else { return }
            guard case .failure(let error) = result, !(error is CancellationError) else { return }
            let failure = Self.legacyConnectionRunError(error)
            if failure is CancellationError { return }
            if case .idle = phase { return }
            if preservingSource {
                ControlLiveLog.line("session: recovery attempt failed phase=\(phase) \(failure.localizedDescription)")
                return
            }
            lastConnectError = failure
            let why = djiConnectionFailureDescription(failure)
            ControlLiveLog.line("session: connect failed at \(phase.label) \u{2014} \(why)")
            phase = .failed(why)
            guard connectionRun.currentRunID == runID else { return }
            applyLinkPresentation()
        }
    }

    private var connectionRunEndpoint: (any DjiAppleConnectionEndpoint)? {
        #if DEBUG
            if let peers = connectionNativePeers { return peers.currentEndpoint() }
        #endif
        return datalink
    }
    private func attachConnectionEndpoint(_ endpoint: (any DjiAppleConnectionEndpoint)?,
        attempt: DjiAppleConnectionRun.Attempt) {
        guard attempt.isCurrent, !isMultiviewBorrowed else { return }
        #if DEBUG
            if let peers = connectionNativePeers { peers.attach(endpoint); return }
        #endif
        guard let endpoint else { disposeDatalink(ifCurrent: { attempt.isCurrent }); return }
        guard let driver = endpoint as? DjiAppleDatalink else { return }
        wireDatalink(driver)
        guard attempt.isCurrent else { return }
        datalink = driver
    }
    private func registerConnectionEndpoint(_ endpoint: any DjiAppleConnectionEndpoint,
        attempt: DjiAppleConnectionRun.Attempt) {
        guard attempt.isCurrent, !isMultiviewBorrowed, connectionRunEndpoint === endpoint else { return }
        if let driver = endpoint as? DjiAppleDatalink, let source = liveViewSource {
            guard pictureRecovery.bindLiveView(endpoint: driver, recovery: .init(datalink: driver),
                scope: source), attempt.isCurrent else { return }
        }
        #if DEBUG
            if let peers = connectionNativePeers { peers.registered(endpoint, attempt); return }
        #endif
        phase = .live
        guard attempt.isCurrent, datalink === endpoint else { return }
        applyLinkPresentation()
        guard attempt.isCurrent, datalink === endpoint else { return }
        beginIDRHoldIfNeeded()
        guard attempt.isCurrent, datalink === endpoint else { return }
        // Registered/subscribed boundary remains synchronous before one initial enable.
        sendInitialLiveViewEnable(displayAttached: decoder.isDisplayReady, pathProven: true)
    }
    private func connectionRunStationNetwork(ssid: String) -> MultiviewNetworkStore.Network? {
        #if DEBUG
            if let peers = connectionNativePeers { return peers.stationNetwork }
        #endif
        return MultiviewNetworkStore.load(ssid: ssid, hotspot: usesHotspot)
    }

    private var usesHotspot: Bool { connectionSetup == .phoneHotspot }

    /// Camera path for the active setup: the SoftAP subnet, the operator's Wi-Fi, or this
    /// phone's hotspot bridge.
    private func cameraPathReady() -> Bool {
        connectionSetup.movesCamera
            ? connectionTransport.network.stationPathReady(usesHotspot)
            : connectionTransport.network.cameraPathReady()
    }

    private func makeDatalink(_ camera: DjiAppleSighting, host: String? = nil) -> DjiAppleDatalink {
        let host = host ?? (connectionSetup.movesCamera ? stationHost : nil)
        return DjiAppleDatalink(
            port: UInt16(camera.model.datalinkPort), tcpPoke: camera.model.tcpPoke,
            pairingToken: camera.model.pairingToken, stationHost: host,
            stationHotspot: host != nil && usesHotspot,
            subscriptionKeys: Commands.subscriptionKeys(for: camera.model), host: .pocket)
    }

    // ---- BLE frame routing -----------------------------------------------------------------------

    private func makeFirstPictureFormat() -> DjiAppleFirstPictureFormat {
        DjiAppleFirstPictureFormat(
            binding: { [weak self] in
                guard let self else { return .init() }
                return .init(
                    endpoint: self.datalink.map(ObjectIdentifier.init),
                    controlGeneration: self.controlGeneration)
            },
            facts: { [weak self] in
                guard let self else {
                    return .init(status: .init(), browsing: true, formatPinned: false)
                }
                return .init(
                    status: self.status, browsing: self.isBrowsingMedia,
                    formatPinned: self.editorReconciliation.hasFormat)
            },
            setFormat: { [weak self] format in
                self?.setVideoFormat(
                    resolution: format.resolution, frameRate: format.frameRate, fromOperator: false)
            },
            enable: { [weak self] in
                _ = self?.pictureRecovery.requestLiveView(
                    .firstPictureFormat, reason: "first-picture format poke")
            },
            event: { [weak self] event in
                guard let self else { return }
                switch event {
                case .changed: break
                case .preparing(let original, let kick, let legal, let count):
                    self.log.info(
                        "live: Pocket 3 first-picture format poke \(original.chipLabel, privacy: .public) → \(kick.chipLabel, privacy: .public) → \(original.chipLabel, privacy: .public) legal=\(legal ? 1 : 0) formats=\(count, privacy: .public)"
                    )
                    ControlLiveLog.line(
                        "feed: Pocket 3 format poke \(original.chipLabel) → \(kick.chipLabel) → \(original.chipLabel) legal=\(legal ? 1 : 0) formats=\(count)"
                    )
                }
            })
    }

    private func makeZoomGesture() -> DjiAppleZoomGesture {
        DjiAppleZoomGesture(
            binding: { [weak self] in
                guard let self else { return .init() }
                return .init(endpoint: self.datalink.map(ObjectIdentifier.init),
                    controlGeneration: self.controlGeneration)
            },
            facts: { [weak self] in
                guard let self else {
                    return .init(status: .init(), stops: CamFov.jumps, supportsZoom: false, locked: true)
                }
                return .init(status: self.status, stops: self.zoomStops,
                    supportsZoom: self.supportsZoom, locked: self.isLocked)
            }, color: zoomColor,
            sendStop: { [weak self] frame, completion in
                guard let self else { completion(false); return }
                self.fireCamera(frame, name: "Zoom stop", onSettle: completion)
            }, event: { [weak self] event in
                guard let self else { return }
                let authority = self.zoomGesture.authority
                switch event {
                case .changed(let previous, let next, let revision):
                    if previous.stop != next.stop {
                        self.withMutation(keyPath: \.zoomStop) {}
                        guard self.zoomGesture.revision == revision else { return }
                    }
                    if previous.preview != next.preview {
                        self.withMutation(keyPath: \.zoomPinchPreview) {}
                        guard self.zoomGesture.revision == revision else { return }
                    }
                    if previous.optimistic != next.optimistic {
                        self.withMutation(keyPath: \.zoomOptimistic) {}
                    }
                case .cancelProgrammedMove:
                    if self.gimbalMoveRunning { self.gimbal.cancelProgrammedMove() }
                case .chipRequested(let from, let to):
                    ControlLiveLog.line(
                        "zoom: setZoom \(from) → \(to) locked=\(self.isLocked) live=\(self.datalink != nil)")
                case .unavailableChip(let to):
                    self.controlNote = "Zoom \(to): no command"
                    guard self.zoomGesture.admits(authority) else { return }
                    ControlLiveLog.line("zoom: tap ignored, no write for \(to)")
                case .chipPreparing(let to):
                    self.controlNote = "Zoom \(to)"
                case .sliderRequested(let factor, let position):
                    ControlLiveLog.line(
                        "zoom: setZoomSlider \(CamFov.displayLabel(factor: factor)) lens=\(position) locked=\(self.isLocked) live=\(self.datalink != nil)")
                case .slewRequested(let value):
                    ControlLiveLog.line(
                        "zoom: setZoomSlew \(value) locked=\(self.isLocked) live=\(self.datalink != nil)")
                case .stopRequested:
                    ControlLiveLog.line(
                        "zoom: setZoomStop locked=\(self.isLocked) live=\(self.datalink != nil)")
                case .stopPreparing:
                    self.lastZoomSetAt = Date()
                case .stopSettled(let frame, let ok):
                    ControlLiveLog.line(
                        "zoom: SET \(Duml.hex(frame.payload)) ack=\(ok ? "ok" : (self.controlNote ?? "failed"))")
                case .locked:
                    self.controlNote = "Zoom locked"
                case .recordingBlocked:
                    self.controlNote = ControlHud.recordingColorLockNote
                    guard self.zoomGesture.admits(authority) else { return }
                    ControlLiveLog.line("zoom: blocked \u{2014} color hop while recording")
                }
            })
    }

    private func makeZoomColor() -> DjiAppleZoomColor {
        DjiAppleZoomColor(
            binding: { [weak self] in
                guard let self else { return .init() }
                return .init(
                    endpoint: self.datalink.map(ObjectIdentifier.init),
                    controlGeneration: self.controlGeneration)
            },
            facts: { [weak self] in
                guard let self else {
                    return .init(
                        status: .init(), model: nil, supportsZoom: false, previewing: false,
                        locked: true)
                }
                return .init(
                    status: self.status, model: self.connectedCamera?.model,
                    supportsZoom: self.supportsZoom, previewing: self.zoomPinchPreview != nil,
                    locked: self.isLocked)
            },
            send: { [weak self] request, event in
                guard let self else {
                    event(.stage(.notSent))
                    event(.failed)
                    event(.settled(false))
                    return
                }
                self.fireCamera(
                    request.frame, name: request.name, expect: request.expectation,
                    retransmits: request.retransmits, coalesce: request.coalesce, admission: request.admission,
                    onStage: { event(.stage($0)) }, onFail: { event(.failed) },
                    onSettle: { event(.settled($0)) })
            },
            event: { [weak self] event in
                guard let self else { return }
                let authority = self.zoomColor.authority
                switch event {
                case .changed(let previous, let next, let revision):
                    if previous.hopPending != next.hopPending {
                        self.withMutation(keyPath: \.zoomColorHopPending) {}
                        guard self.zoomColor.revision == revision else { return }
                    }
                case .hopRetry:
                    ControlLiveLog.line("zoom: D-Log hop timed out \u{2014} resend 0x42")
                case .hopPreparing:
                    self.editorReconciliation.clearColor()
                    guard self.zoomColor.admits(authority) else { return }
                    self.controlNote = "D-Log \u{2014} D-Log2 cannot zoom"
                    guard self.zoomColor.admits(authority) else { return }
                    ControlLiveLog.line("zoom: hold 0xB8 until D-Log2 → D-Log")
                case .nativeISO(let from, let to):
                    self.hopNativeISO(from: from, to: to)
                case .hopFailed:
                    self.editorReconciliation.clearColor()
                case .hopSettled(let success):
                    ControlLiveLog.line("zoom: D-Log2 → D-Log ack=\(success ? "ok" : "failed")")
                case .confirmed:
                    self.editorReconciliation.holdColor(.dLog)
                    guard self.zoomColor.admits(authority) else { return }
                    ControlLiveLog.line("zoom: D-Log2 → D-Log body confirmed")
                case .restoredPreparing:
                    self.status.colorMode = .dLog2
                    guard self.zoomColor.admits(authority) else { return }
                    self.editorReconciliation.holdColor(.dLog2)
                case .restoreFailed:
                    self.editorReconciliation.clearColor()
                case .restoreSettled(let success):
                    ControlLiveLog.line(
                        "zoom: restore D-Log2 on 1× ack=\(success ? "ok" : "failed")")
                    if success { self.controlNote = "Zoom 1× · D-Log2" }
                case .flushed(let factor):
                    _ = self.zoomGesture.flushed(factor)
                case .slewCleared:
                    break
                case .recordingBlocked:
                    self.controlNote = ControlHud.recordingColorLockNote
                    guard self.zoomColor.admits(authority) else { return }
                    ControlLiveLog.line("zoom: blocked \u{2014} color hop while recording")
                case .locked:
                    self.controlNote = "Zoom locked"
                case .zoomPreparing:
                    self.lastZoomSetAt = Date()
                case .zoomSettled(let frame, let name, let announce, let success):
                    if success, announce { self.controlNote = name }
                    guard self.zoomColor.admits(authority) else { return }
                    ControlLiveLog.line(
                        "zoom: SET \(Duml.hex(frame.payload)) ack=\(success ? "ok" : (self.controlNote ?? "failed"))"
                    )
                }
            }, admittedNativeISO: { [weak self] from, to, admission in
                self?.hopNativeISO(from: from, to: to, suppliedAdmission: admission)
            })
    }

    private func makeTapFocus() -> DjiAppleTapFocus {
        DjiAppleTapFocus(
            binding: { [weak self] in
                guard let self else { return .init() }
                return .init(
                    endpoint: self.datalink.map(ObjectIdentifier.init),
                    controlGeneration: self.controlGeneration)
            },
            sendPrepare: { [weak self] frame in self?.datalink?.sendUntracked(frame) ?? 0 },
            request: { [weak self] frame, name, timeout in
                guard let self else { return false }
                return await self.requestCamera(frame, name: name, timeout: timeout)
            },
            prepared: { prepare, seq in
                ControlLiveLog.line(
                    "control: send AE spot 0x02/0x22 seq=\(seq) flags=0x\(String(prepare.flags, radix: 16)) payload=\(Duml.hex(prepare.payload)) via=datalink"
                )
            }, sendAdmittedPrepare: { [weak self] frame, admission in
                guard let self, self.controlLinkReady, admission.admits(self.commandOwner) else { return .skipped }
                return self.datalink?.sendUntracked(frame, admission: admission) ?? .skipped
            }, admittedRequest: { [weak self] frame, name, timeout, admission in
                guard let self else { return false }
                return await self.requestCamera(frame, name: name, timeout: timeout, admission: admission)
            })
    }

    /// Integration owns pending editor reconciliation; camera reports and native wire remain host policy.
    private func makeEditorReconciliation() -> DjiAppleEditorReconciliation {
        DjiAppleEditorReconciliation(binding: { [weak self] in
            guard let self else { return .init() }
            return .init(endpoint: self.datalink.map(ObjectIdentifier.init),
                controlGeneration: self.controlGeneration)
        }, whiteBalanceChanged: { [weak self] _, _ in
            guard let self else { return }
            self.withMutation(keyPath: \.pendingWhiteBalance) {}
        })
    }

    private func makeCameraSettings() -> DjiAppleCameraSettings {
        DjiAppleCameraSettings(
            binding: { [weak self] in
                guard let self else { return .init() }
                return .init(
                    endpoint: self.datalink.map(ObjectIdentifier.init),
                    controlGeneration: self.controlGeneration)
            },
            request: { [weak self] frame, name in
                guard let self else { return false }
                return await self.requestCamera(frame, name: name)
            },
            audio: { [weak self] in
                guard let self, !Task.isCancelled,
                    DjiAppleCameraSettings.requestControlGeneration.map({ $0 == self.controlGeneration }) ?? true
                else { return .init() }
                // The captured GET cache is updated before editor callbacks. A retired
                // presentation cannot discard its actual bytes. Operator rollback flags
                // keep their original status values; only the raw blob/at2 come from GET.
                let reported = self.cameraReportedCapture
                return .init(
                    blob: reported.audioDspBlob ?? self.status.audioDspBlob,
                    at2: reported.audioDspBlob != nil ? reported.audioDspAt2 : self.status.audioDspAt2,
                    wind: self.status.windNR, directional: self.status.directionalAudio)
            }, glamour: { [weak self] in
                guard let self, !Task.isCancelled,
                    DjiAppleCameraSettings.requestControlGeneration.map({ $0 == self.controlGeneration }) ?? true
                else { return nil }
                return self.cameraReportedCapture.glamourBlob ?? self.status.glamourBlob
            },
            event: { [weak self] event in
                guard let self else { return }
                switch event {
                case .channelCompleted(let channel, let previous, let ok, let authority):
                    guard self.cameraSettings.admits(authority) else { return }
                    if !ok {
                        if self.status.audioChannel == channel {
                            self.status.audioChannel = previous
                        }
                        guard self.cameraSettings.admits(authority) else { return }
                        self.editorReconciliation.clearAudioPin(channel: true)
                    }
                    ControlLiveLog.line(
                        "audio: channel \(channel.label) ack=\(ok ? "ok" : (self.controlNote ?? "failed"))"
                    )
                case .vocalCompleted(let boost, let previous, let ok, let authority):
                    guard self.cameraSettings.admits(authority) else { return }
                    if !ok {
                        if self.status.vocalBoost == boost { self.status.vocalBoost = previous }
                        guard self.cameraSettings.admits(authority) else { return }
                        self.editorReconciliation.clearAudioPin(vocal: true)
                    }
                    ControlLiveLog.line(
                        "audio: vocal \(boost.label) ack=\(ok ? "ok" : (self.controlNote ?? "failed"))"
                    )
                case .focusPreparing(let authority):
                    guard self.cameraSettings.admits(authority) else { return }
                    self.lastFocusTrackAt = Date()
                case .focusCompleted(let track, let previous, let pinID, let ok, let authority):
                    guard self.cameraSettings.admits(authority) else { return }
                    if !ok, self.editorReconciliation.hasFocusTrackRequest(id: pinID) {
                        self.editorReconciliation.clearFocusTrack()
                        guard self.cameraSettings.admits(authority) else { return }
                        self.status.focusTrack = previous
                    }
                    ControlLiveLog.line(
                        "focus: track \(track.label) ack=\(ok ? "ok" : (self.controlNote ?? "failed"))"
                    )
                case .missingDSP(let name, let authority):
                    guard self.cameraSettings.admits(authority) else { return }
                    self.controlNote = "\(name): no DSP blob"
                    ControlLiveLog.line("audio: \(name) skipped — no GET blob")
                case .dspPrepared(let facts, let authority):
                    self.applyAudioDSPFacts(facts, authority: authority)
                case .dspRejected(let facts, let authority):
                    self.applyAudioDSPFacts(facts, authority: authority)
                    guard self.cameraSettings.admits(authority) else { return }
                    self.editorReconciliation.clearAudioPin(wind: true, directional: true)
                case .dspCompleted(let name, let ok, let authority):
                    guard self.cameraSettings.admits(authority) else { return }
                    ControlLiveLog.line(
                        "audio: \(name) ack=\(ok ? "ok" : (self.controlNote ?? "failed"))")
                case .glamourPrepared(let blob, let authority):
                    guard self.cameraSettings.admits(authority) else { return }
                    self.status.glamourBlob = blob
                    guard self.cameraSettings.admits(authority) else { return }
                    self.status.glamourEnabled = false
                case .glamourRejected(let previous, let authority):
                    guard self.cameraSettings.admits(authority) else { return }
                    self.status.glamourBlob = previous
                    guard self.cameraSettings.admits(authority) else { return }
                    self.status.glamourEnabled = previous.map(GlamourEffect.isEnabled)
                }
            })
    }

    private func applyAudioDSPFacts(
        _ facts: DjiAppleAudioDSPFacts,
        authority: DjiAppleCameraSettings.Authority
    ) {
        guard cameraSettings.admits(authority) else { return }
        status.audioDspBlob = facts.blob
        guard cameraSettings.admits(authority) else { return }
        status.audioDspAt2 = facts.at2
        guard cameraSettings.admits(authority) else { return }
        status.windNR = facts.wind
        guard cameraSettings.admits(authority) else { return }
        status.directionalAudio = facts.directional
    }

    /// ActiveTrack packet and polling ownership is integration-owned; native faces/focus stay here.
    private func makeSubjectTracking() -> DjiAppleSubjectTracking {
        DjiAppleSubjectTracking(
            binding: { [weak self] in
                guard let self else { return .init() }
                return .init(
                    endpoint: self.datalink.map(ObjectIdentifier.init),
                    controlGeneration: self.controlExchange.generation)
            },
            send: { [weak self] frame, name, retransmits, settle in
                self?.fireCamera(frame, name: name, retransmits: retransmits, onSettle: settle)
            }, timing: subjectTrackingTiming,
            event: { [weak self] event in
                guard let self else { return }
                switch event {
                case .changed(let previous, let next, let revision):
                    // The owner committed its snapshot before any synchronous observation callback.
                    if previous.searchBox != next.searchBox {
                        self.withMutation(keyPath: \.searchBox) {}
                        guard self.subjectTracking.revision == revision else { return }
                    }
                    if previous.subjectBox != next.subjectBox {
                        self.withMutation(keyPath: \.subjectBox) {}
                        guard self.subjectTracking.revision == revision else { return }
                    }
                    if previous.tracking != next.tracking {
                        self.withMutation(keyPath: \.isTracking) {}
                    }
                case .preparing(let authority):
                    guard self.subjectTracking.admits(authority) else { return }
                    self.faceBox = nil
                    guard self.subjectTracking.admits(authority) else { return }
                    self.faceTarget = nil
                    guard self.subjectTracking.admits(authority) else { return }
                    self.lastFaceHitAt = nil
                case .tooSmall(let authority):
                    guard self.subjectTracking.admits(authority) else { return }
                    self.noteFrameTooSmall()
                case .focus(let x, let y):
                    self.adoptCameraFocus(x: x, y: y, fromTrackingBox: true)
                }
            }, sendAdmitted: { [weak self] frame, name, retransmits, admission, settle in
                guard let self else { settle(false); return }
                self.fireCamera(frame, name: name, retransmits: retransmits,
                    admission: admission, onSettle: settle)
            })
    }

    /// Packet workflows live in the shared owner; host policy and presentation stay here.
    private func makeControlExchange() -> DjiAppleControlExchange {
        #if DEBUG
            if let trace = connectionNativePeers {
                return DjiAppleControlExchange(endpoint: .init(writeBLE: { trace.transport.bluetooth.send($0) },
                    writeDatalink: { _ in .skipped }), timing: trace.exchangeTiming,
                    context: { .init() })
            }
        #endif
        return DjiAppleControlExchange(
            endpoint: .init(bluetooth: ble, datalink: datalink),
            context: { [weak self] in
                guard let self else { return .init() }
                return .init(
                    canTransmit: self.admitsMultiviewControl,
                    browsingMedia: self.isBrowsingMedia, controlsOnly: self.isMultiviewControlsOnly,
                    reported: self.cameraReportedCapture, legacySettlement: self.status)
            },
            event: { [weak self] event in
                guard let self else { return }
                switch event {
                case .bleActivity:
                    self.lastBleNotifyAt = Date()
                case .bleEnded:
                    if case .live = self.phase {
                        if self.liveVideoIsFresh(), let camera = self.connectedCamera {
                            self.reconnectBleKeepingLive(camera)
                        } else {
                            self.beginSessionRecovery(reason: "BLE dropped", trigger: .bleDropped)
                        }
                    }
                case .selfieFlip(let frame):
                    _ = self.applySelfieFlipReply(frame)
                case .replyReceived:
                    self.commandTimeoutsAt.removeAll()
                case .reply(let frame, let request, let late):
                    if frame.cmdId == 0xa5 { self.subjectTracking.receivePoll(frame.payload) }
                    _ = self.finishControlReply(
                        frame, name: request.name,
                        opcode: String(format: "0x%02X/0x%02X", frame.cmdSet, frame.cmdId),
                        expect: request.expectation, late: late)
                case .refused(let name, let message):
                    self.controlNote = "\(name): \(message)"
                case .legacySettlementMatched:
                    self.controlNote = nil
                case .timeoutEvidence(let request, _):
                    guard !self.isMultiviewBorrowed else { return }
                    let videoFresh =
                        self.datalink?.lastVideoPacketAt.map {
                            Date().timeIntervalSince($0) < FeedWatchdog.stallThreshold
                        } == true
                    let opcode = String(
                        format: "0x%02X/0x%02X", request.frame.cmdSet, request.frame.cmdId)
                    if videoFresh {
                        self.log.info("control: SET timeout with video flowing \u{2014} leave UDP")
                        ControlLiveLog.line(
                            "control: \(request.name) \(opcode) \u{2014} SET timeout, video flowing, leave UDP"
                        )
                    } else if self.datalink?.lastWriteLanded == false {
                        self.log.info(
                            "control: SET timeout after skipped UDP write \u{2014} leave UDP")
                        ControlLiveLog.line(
                            "control: \(request.name) \(opcode) \u{2014} SET timeout, write skipped, leave UDP"
                        )
                    } else {
                        self.noteCommandTimeout()
                    }
                }
            }, journal: { ControlLiveLog.line($0) })
    }

    private func startFrameRouter() {
        controlExchange.startBLEDrain(connectionTransport.bluetooth.frames())
    }

    private func liveVideoIsFresh() -> Bool {
        cameraPathReady()
            && datalink?.lastVideoPacketAt.map {
                Date().timeIntervalSince($0) < FeedWatchdog.stallThreshold
            } == true
    }

    /// Video, telemetry and commands ride UDP 9004. A BLE drop (seen returning
    /// from Control Center, 2026-09-22) used to tear down a healthy 25 fps
    /// stream for a full BLE re-pair and Wi-Fi re-join. Reconnect BLE beside
    /// the live picture; the watchdog still owns any later datalink stall.
    private func reconnectBleKeepingLive(_ camera: DjiAppleSighting) {
        ControlLiveLog.line("session: BLE dropped with live video; reconnecting BLE only")
        recordFeedBreadcrumb(.pathChange, detail: "bleDroppedVideoLive")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.ble.connect(camera)
                guard case .live = self.phase else { return }
                self.startFrameRouter()
                ControlLiveLog.line("session: BLE reconnected beside live video")
            } catch {
                guard case .live = self.phase else { return }
                ControlLiveLog.line("session: BLE reconnect failed (\(error.localizedDescription))")
                if !self.liveVideoIsFresh() {
                    self.beginSessionRecovery(reason: "BLE dropped", trigger: .bleDropped)
                }
            }
        }
    }

    private func route(_ frame: Duml.Frame) {
        controlExchange.receive(frame)
    }

    /// UDP ACK-pump GET and BLE fallback both land here. Do not complete 0x8E waiters.
    @discardableResult
    private func applySelfieFlipReply(_ frame: Duml.Frame) -> Bool {
        guard
            CameraParam.isSelfieFlipGetReply(
                set: frame.cmdSet, cmd: frame.cmdId, payload: frame.payload),
            let parsed = CameraParam.parseGetReply(frame.payload)
        else { return false }
        lastSelfieFlipReplyAt = Date()
        datalink?.noteSelfieFlipReply()
        let next = SelfieFlip(rawValue: parsed.value)
        let changed = next != status.selfieFlip
        ControlLiveLog.line(
            "flip: rx \(next?.label ?? "nil") seq=\(frame.seq) flags=0x\(String(frame.flags, radix: 16)) payload=\(Duml.hex(frame.payload)) changed=\(changed ? 1 : 0)"
        )
        if changed {
            var s = status
            s.selfieFlip = next
            status = s
            ControlLiveLog.line(
                "control: Selfie Flip \(next?.label ?? "nil") extra-mirror=\(gimbal.stickMapping.commanded180 && !(next?.isOn ?? false) ? 1 : 0)"
            )
            decoder.invalidatePictureFlipPresentation()
        }
        gimbal.syncPose()
        return true
    }

    func waitFrame(
        _ set: UInt8, _ cmd: UInt8,
        timeout: Duration = .seconds(8),
        consumeHold: Bool = true,
        send: (() -> Void)? = nil
    ) async throws -> Duml.Frame {
        try await waitFrame(
            matching: [(set, cmd)], timeout: timeout, consumeHold: consumeHold, send: send)
    }

    private func waitFrame(
        matching cmds: [(UInt8, UInt8)], timeout: Duration,
        consumeHold: Bool = true, send: (() -> Void)? = nil
    ) async throws -> Duml.Frame {
        let request = controlExchange.request(
            matching: cmds, timeout: timeout, consumeHold: consumeHold, send: send)
        do { return try await request.value() } catch DjiAppleControlExchange.Error.timeout {
            throw Fail.timeout
        } catch DjiAppleControlExchange.Error.disconnected { throw Fail.disconnected }
    }

    // ---- Camera control (Osmosis §10–14) ---------------------------------------------------------

    var currentShootingMode: ShootingMode? {
        ShootingMode.fromStatus(status.shootingMode)
    }

    /// Fire a still in Photo. Record lamp, gamepad, Watch and watcher toggles reach this
    /// through `control.shutter()`, which resolves video to an explicit start or stop.
    func takePhoto() { takePhoto(suppliedAdmission: nil) }
    func takePhoto(admission: DJICommandAdmission) { takePhoto(suppliedAdmission: admission) }

    private func takePhoto(suppliedAdmission admission: DJICommandAdmission?) {
        guard admission?.admits(commandOwner) ?? true else { return }
        let frame = CaptureCommand.frame(
            mode: currentShootingMode, model: connectedCamera?.model,
            isRecording: status.isRecording)
        controlBusy = true
        fireCamera(
            frame, name: "Photo", retransmits: false, admission: admission,
            onSettle: { [weak self] _ in self?.controlBusy = false })
    }

    /// Explicit start or stop. Callers go through `control`, which checks the reported
    /// state first. SuperNight / Low-Light is video. Pocket 3 TimeLapse uses `0x02/0x01`.
    /// The rec button stays disabled (`controlBusy`) until the ACK or the
    /// `rec_state` telemetry confirms — record must never lie.
    func setRecording(_ start: Bool, onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setRecording(start, suppliedAdmission: nil, onStage: onStage)
    }
    func setRecording(_ start: Bool, admission: DJICommandAdmission,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setRecording(start, suppliedAdmission: admission, onStage: onStage)
    }

    private func setRecording(_ start: Bool, suppliedAdmission admission: DJICommandAdmission?, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
        guard admission?.admits(commandOwner) ?? true else { onStage?(.notSent); return }
        let mode = currentShootingMode
        let frame = CaptureCommand.frame(
            mode: mode, model: connectedCamera?.model, isRecording: !start)
        controlBusy = true
        let name: String
        if connectedCamera?.model.isPocket3 == true, mode?.usesShutterTriggerOnPocket3 == true {
            name = start ? "TimeLapse" : "Stop"
        } else {
            name = start ? "Record" : "Stop"
        }
        fireCamera(
            frame, name: name, expect: .recording(start), admission: admission, onStage: onStage,
            onSettle: { [weak self] _ in self?.controlBusy = false }
        )
    }

    func setShootingMode(_ mode: ShootingMode) {
        guard !isMultiviewControlsOnly || (admitsMultiviewControl && !status.isRecording) else {
            return
        }
        // Return the old mode to Auto before leaving it; the camera keeps Manual per mode.
        unlockAutoExposure()
        editorReconciliation.advanceCaptureGeneration()
        let modeGeneration = editorReconciliation.captureGeneration
        let sessionGeneration = controlGeneration
        let previousMode = status.shootingMode
        let previousFormats = status.availableVideoFormats
        let previousShutter = status.availableShutterDenoms
        let previousIso = status.availableIsoIndices
        let previousColor = status.availableColorModes
        let wire = Int(mode.wireByte(for: connectedCamera?.model))
        let pin = editorReconciliation.holdShootingMode(wire)
        var next = status
        if previousMode != wire {
            next.clearModeDependentCapabilities()
        }
        next.shootingMode = wire
        status = next
        guard editorReconciliation.isPending(pin) else { return }
        editorReconciliation.clearFormat()
        fireCamera(
            Commands.setShootingMode(mode, model: connectedCamera?.model), name: mode.label,
            onFail: { [weak self] in
                guard let self, self.editorReconciliation.isPending(pin),
                    self.editorReconciliation.captureGeneration == modeGeneration,
                    self.controlGeneration == sessionGeneration,
                    self.status.shootingMode == wire
                else { return }
                self.editorReconciliation.advanceCaptureGeneration()
                _ = self.editorReconciliation.reject(pin)
                self.editorReconciliation.clearFormat()
                self.status.shootingMode = previousMode
                self.status.availableVideoFormats = previousFormats
                self.status.availableShutterDenoms = previousShutter
                self.status.availableIsoIndices = previousIso
                self.status.availableColorModes = previousColor
            })
    }

    func setIsoLimit(_ limit: IsoLimit) {
        let previous = status.isoLimit
        let pin = editorReconciliation.holdIsoLimit(limit)
        status.isoLimit = limit
        guard editorReconciliation.isPending(pin) else { return }
        let base = (status.colorMode ?? .normal).isoAutoBase(for: connectedCamera?.model) ?? 100
        fireCamera(
            Commands.setIsoLimit(limit), name: "ISO \(limit.label(base: base))",
            onFail: { [weak self] in
                guard let self, self.editorReconciliation.isPending(pin) else { return }
                _ = self.editorReconciliation.reject(pin)
                self.status.isoLimit = previous
            },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "iso: limit \(limit.label(base: base)) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))"
                )
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

    func setEv(_ ev: EvComp, onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setEv(ev, suppliedAdmission: nil, onStage: onStage)
    }
    func setEv(_ ev: EvComp, admission: DJICommandAdmission,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setEv(ev, suppliedAdmission: admission, onStage: onStage)
    }

    private func setEv(_ ev: EvComp, suppliedAdmission admission: DJICommandAdmission?, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
        guard admission?.admits(commandOwner) ?? true else { onStage?(.notSent); return }
        let previous = status.evComp
        editorReconciliation.pinExpo(ev: ev)
        status.evComp = ev
        fireCamera(
            Commands.setEv(ev), name: "EV \(ev.label)", expect: .ev(ev),
            coalesce: true, admission: admission, onStage: onStage,
            onFail: { [weak self] in
                self?.editorReconciliation.clearExpoPin(ev: true)
                self?.status.evComp = previous
            },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "ev: SET \(ev.label) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    func refreshIsoLimit() async {
        guard IsoLimit.shouldGet(colorMode: status.colorMode) else { return }
        cameraSettings.refreshIsoLimit()
        await cameraSettings.waitForPending()
    }

    func setFov(_ fov: FovSetting) {
        fireCamera(Commands.setFov(fov), name: "FOV \(fov.label)")
    }

    func setExpoMode(_ mode: ExpoMode) {
        // Manual from AE-L keeps the pinned values; the camera is already Manual.
        if mode == .manual, autoExposureLock != nil, status.expoMode == .manual {
            autoExposureLock = nil
            return
        }
        autoExposureLock = nil
        if mode != .manual {
            editorReconciliation.clearFormatAngle()
            editorReconciliation.clearExpoPin(shutter: true)
        }
        let previous = status.expoMode
        editorReconciliation.pinExpo(mode: mode)
        status.expoMode = mode
        fireCamera(
            Commands.setExpoMode(mode), name: "ExpoMode", expect: .expo(mode),
            onFail: { [weak self] in
                self?.editorReconciliation.clearExpoPin(mode: true)
                self?.status.expoMode = previous
            })
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

    var zoomReadout: Double {
        access(keyPath: \.zoomStop)
        access(keyPath: \.zoomPinchPreview)
        access(keyPath: \.zoomOptimistic)
        _ = zoomColorHopPending
        return zoomGesture.readout
    }
    private var fallbackZoomStop: Double {
        access(keyPath: \.zoomStop)
        return zoomGesture.fallback
    }
    var zoomDialReadout: Double {
        access(keyPath: \.zoomStop)
        access(keyPath: \.zoomPinchPreview)
        access(keyPath: \.zoomOptimistic)
        return zoomGesture.dialReadout
    }

    private func noteZoomIfChanged(_ new: CameraStatus) {
        zoomGesture.observe(new)
        guard new.zoomFactorRaw != lastLoggedZoomRaw || new.zoomLens != lastLoggedZoomLens else {
            return
        }
        lastLoggedZoomRaw = new.zoomFactorRaw
        lastLoggedZoomLens = new.zoomLens
        guard new.zoomFactorRaw > 0 || new.zoomLens != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastZoomLogAt) >= 0.5 else { return }
        lastZoomLogAt = now
        let label =
            new.zoomFactor.map { CamFov.displayLabel(factor: $0) }
            ?? CamFov.displayLabel(raw: new.zoomFactorRaw)
        let lens = new.zoomLens.map { " lens=\($0)" } ?? ""
        ControlLiveLog.line("zoom: cam_fov @0=\(new.zoomFactorRaw)\(lens) \(label)")
    }

    /// Pinch HUD (0.1×) + slider (every distinct lens tick, ~20 Hz latest-wins).
    /// Gesture owns the chip until lift; cam_fov does not re-anchor mid-pinch.
    func updateZoomPinch(magnification: Double) {
        zoomGesture.updatePinch(magnification: magnification)
    }

    func endZoomPinch() { zoomGesture.endPinch() }

    /// Cycle button. Body stops are sliders (Pro 217 / 651 / 1302 / 2604).
    func setZoom(_ factor: Double, onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        zoomGesture.chip(factor, onStage: onStage)
    }

    func setZoom(_ factor: Double, admission: DJICommandAdmission,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        guard admission.admits(commandOwner) else { onStage?(.notSent); return }
        zoomGesture.chip(factor, admission: admission, onStage: onStage)
    }

    /// Pinch hybrid: `0A 4E` + unquantized lens. Coalesces to the newest tick.
    func setZoomSlider(_ factor: Double, onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        zoomGesture.slider(factor, onStage: onStage)
    }

    func setZoomSlider(_ factor: Double, admission: DJICommandAdmission,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        guard admission.admits(commandOwner) else { onStage?(.notSent); return }
        zoomGesture.slider(factor, admission: admission, onStage: onStage)
    }

    /// Directional slew. 100 toward 12×; 300 from 12× to the 9.15× detent.
    func setZoomSlew(_ value: UInt16) { zoomGesture.slew(value) }

    /// Older takes sent `FF 00 00 00` after a `03 00` slew. Newer recapture omitted
    /// it (camera may ignore). Same opcode as the slew, so the per-opcode queue
    /// keeps it from overtaking.
    func setZoomStop() { zoomGesture.stop() }

    /// D-Log native 400 ↔ D-Log2 native 1600 when the operator is still on base.
    private func hopNativeISO(from: ColorMode?, to: ColorMode) { hopNativeISO(from: from, to: to, suppliedAdmission: nil) }

    private func hopNativeISO(from: ColorMode?, to: ColorMode, suppliedAdmission admission: DJICommandAdmission?) {
        guard admission?.admits(commandOwner) ?? true else { return }
        guard
            let next = CamCapIso.nativeISOHop(
                from: from, to: to, current: status.isoIndex,
                hopEnabled: OperatorPrefs.nativeISOHopEnabled)
        else { return }
        ControlLiveLog.line(
            "iso: native hop \(from?.label ?? "?") → \(to.label) \(status.isoIndex?.label ?? "?") → \(next.label)"
        )
        if let admission { setISO(next, admission: admission) } else { setISO(next) }
    }

    func setISO(_ index: IsoIndex, onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setISO(index, suppliedAdmission: nil, onStage: onStage)
    }
    func setISO(_ index: IsoIndex, admission: DJICommandAdmission,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setISO(index, suppliedAdmission: admission, onStage: onStage)
    }

    private func setISO(_ index: IsoIndex, suppliedAdmission admission: DJICommandAdmission?, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
        guard admission?.admits(commandOwner) ?? true else { onStage?(.notSent); return }
        editorReconciliation.pinExpo(iso: index.isoValue, isoIndex: index)
        fireCamera(
            Commands.setIsoIndex(index), name: "ISO \(index.label)", expect: .iso(index),
            coalesce: true, admission: admission, onStage: onStage,
            onFail: { [weak self] in self?.editorReconciliation.clearExpoPin(iso: true) },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "iso: SET \(index.label) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    /// Pass `Int` into `Commands.setShutter(denom:)` — `UInt8` cannot encode 1/256 and above.
    /// Manual-expo rides the same socket right before the shutter SET (Mimo never
    /// round-trips between them; the camera applies datagrams in arrival order).
    func setShutterDenom(_ denom: Int,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil, ensureManual: Bool = true) {
        setShutterDenom(denom, suppliedAdmission: nil, onStage: onStage, ensureManual: ensureManual)
    }
    func setShutterDenom(_ denom: Int, admission: DJICommandAdmission,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil, ensureManual: Bool = true) {
        setShutterDenom(denom, suppliedAdmission: admission, onStage: onStage, ensureManual: ensureManual)
    }

    private func setShutterDenom(_ denom: Int, suppliedAdmission admission: DJICommandAdmission?, onStage: (@MainActor (ControlWireEvent) -> Void)?, ensureManual: Bool) {
        guard admission?.admits(commandOwner) ?? true else { onStage?(.notSent); return }
        // A direct speed choice supersedes an angle waiting for FORMAT.
        editorReconciliation.clearFormatAngle()
        if ensureManual, status.expoMode != .manual {
            editorReconciliation.pinExpo(mode: .manual)
            fireCamera(
                Commands.setExpoMode(.manual), name: "Manual expo", expect: .expo(.manual), admission: admission,
                onFail: { [weak self] in self?.editorReconciliation.clearExpoPin(mode: true) })
        }
        editorReconciliation.pinExpo(shutter: denom)
        fireCamera(
            Commands.setShutter(denom: denom), name: "1/\(denom)", expect: .shutter(denom),
            coalesce: true, admission: admission, onStage: onStage,
            onFail: { [weak self] in self?.editorReconciliation.clearExpoPin(shutter: true) },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "shutter: SET 1/\(denom) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    /// Angle is operator intent, never a value inferred back from delayed telemetry.
    func setShutterAngle(_ degrees: Double) {
        guard admitsMultiviewControl, datalink != nil, datalink?.isRebuilding != true else {
            controlNote = "not live"
            return
        }
        guard !status.isPhoto else { return }
        editorReconciliation.expireFormatForOperatorAngle()
        let angle = ShutterAngle.nearestDegrees(degrees)
        OperatorPrefs.shutterAngleDegrees = angle
        let denom = ShutterAngle.denom(
            degrees: angle, fps: status.fps, available: status.availableShutterDenoms)
        if editorReconciliation.hasFormat, status.expoMode == .manual, !status.isPhoto {
            editorReconciliation.holdFormatAngle(angle)
            editorReconciliation.pinExpo(shutter: denom)
            status.shutterDenom = denom
            return
        }
        let previous = status.shutterDenom
        status.shutterDenom = denom
        setShutterDenom(denom)
        if controlNote == "not live" { status.shutterDenom = previous }
    }

    private func rematchShutterAngle(_ degrees: Double?) {
        guard let degrees, OperatorPrefs.shutterUsesAngle,
            status.expoMode == .manual, !status.isPhoto, admitsMultiviewControl,
            datalink != nil, datalink?.isRebuilding != true
        else { return }
        let denom = ShutterAngle.denom(
            degrees: degrees, fps: status.fps, available: status.availableShutterDenoms)
        status.shutterDenom = denom
        let note = controlNote
        setShutterDenom(denom)
        if controlNote == nil { controlNote = note }
    }

    var canLockAutoExposure: Bool {
        autoExposureLock == nil && AutoExposureLock.capture(status) != nil
    }

    /// Pins the applied Auto exposure as Manual (no captured native AE lock).
    /// Manual rides the same socket right before ISO and shutter.
    @discardableResult
    func lockAutoExposure() -> Bool {
        guard autoExposureLock == nil, admitsMultiviewControl, datalink != nil,
            datalink?.isRebuilding != true, let lock = AutoExposureLock.capture(status)
        else { return false }
        setExpoMode(.manual)
        setISO(lock.isoIndex)
        setShutterDenom(lock.shutterDenom)
        autoExposureLock = lock
        ControlLiveLog.line("ae-lock: ISO \(lock.isoIndex.label) 1/\(lock.shutterDenom)")
        return true
    }

    func unlockAutoExposure() {
        guard autoExposureLock != nil else { return }
        setExpoMode(.auto)
    }

    var canLockAutoWhiteBalance: Bool { WhiteBalance.lockingAuto(status) != nil }

    /// Pins the live Auto Kelvin as Custom (no captured native AWB lock). The
    /// optimistic Custom lands first, so the lock never sees a stale Auto.
    func lockAutoWhiteBalance() {
        guard autoWhiteBalanceLock == nil, let wb = WhiteBalance.lockingAuto(status) else { return }
        setWhiteBalanceCustom(kelvin: wb.kelvin, tint: wb.tint)
        if pendingWhiteBalance == wb || status.whiteBalance == wb {
            autoWhiteBalanceLock = AutoWhiteBalanceLock(kelvin: wb.kelvin)
        }
    }

    /// Camera-reported status with the pending white-balance request laid over it, for WB
    /// controls and for composing the next WB request. `status` itself stays reported.
    var whiteBalanceDisplayStatus: CameraStatus {
        var display = status
        guard let wb = pendingWhiteBalance else { return display }
        display.whiteBalance = wb
        if wb.mode == .custom { display.whiteBalanceKelvin = wb.kelvin }
        display.whiteBalanceTint = wb.tint
        return display
    }

    func setWhiteBalanceAuto(tint: Int? = nil, onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setWhiteBalanceAuto(tint: tint, suppliedAdmission: nil, onStage: onStage)
    }
    func setWhiteBalanceAuto(tint: Int?, admission: DJICommandAdmission,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setWhiteBalanceAuto(tint: tint, suppliedAdmission: admission, onStage: onStage)
    }

    private func setWhiteBalanceAuto(tint: Int?, suppliedAdmission admission: DJICommandAdmission?, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
        guard admission?.admits(commandOwner) ?? true else { onStage?(.notSent); return }
        autoWhiteBalanceLock = nil
        let next = min(max(tint ?? whiteBalanceDisplayStatus.whiteBalanceTint ?? 0, -100), 100)
        fireWhiteBalance(.auto(tint: next), onStage: onStage, admission: admission)
    }

    func setWhiteBalanceCustom(kelvin: Int, tint: Int,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setWhiteBalanceCustom(kelvin: kelvin, tint: tint, suppliedAdmission: nil, onStage: onStage)
    }
    func setWhiteBalanceCustom(kelvin: Int, tint: Int, admission: DJICommandAdmission,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setWhiteBalanceCustom(kelvin: kelvin, tint: tint, suppliedAdmission: admission, onStage: onStage)
    }

    private func setWhiteBalanceCustom(kelvin: Int, tint: Int, suppliedAdmission admission: DJICommandAdmission?, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
        guard admission?.admits(commandOwner) ?? true else { onStage?(.notSent); return }
        let wb = WhiteBalance.custom(
            kelvin: min(max(kelvin, 2_000), 10_000), tint: min(max(tint, -100), 100))
        // Custom from AWB Lock keeps the locked value; the camera is already there.
        if autoWhiteBalanceLock != nil, status.whiteBalance == wb {
            autoWhiteBalanceLock = nil
            onStage?(.confirmed)
            return
        }
        autoWhiteBalanceLock = nil
        fireWhiteBalance(wb, onStage: onStage, admission: admission)
    }

    /// The request is held as `pendingWhiteBalance` until the camera reports it; `status`
    /// keeps the camera's own value so confirmation can never be self-fulfilling.
    private func fireWhiteBalance(
        _ wb: WhiteBalance, onStage: (@MainActor (ControlWireEvent) -> Void)?, admission: DJICommandAdmission? = nil
    ) {
        let pin = editorReconciliation.holdWhiteBalance(wb)
        guard editorReconciliation.isPending(pin) else {
            onStage?(.notSent)
            return
        }
        let name =
            wb.mode == .auto
            ? "WB Auto tint \(wb.tint)"
            : "WB \(wb.kelvin)K tint \(wb.tint)"
        let frame =
            wb.mode == .auto
            ? Commands.setWhiteBalanceAuto(tint: wb.tint)
            : Commands.setWhiteBalanceCustom(kelvin: wb.kelvin, tint: wb.tint)
        fireCamera(
            frame, name: name, expect: .wb(wb),
            coalesce: true, admission: admission, onStage: onStage,
            onFail: { [weak self] in
                guard let self, self.editorReconciliation.isPending(pin) else { return }
                _ = self.editorReconciliation.reject(pin)
            },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "wb: SET \(name) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    var supportsTapFocus: Bool { connectedCamera?.model.supportsTapFocus ?? true }
    var supportsFocusMode: Bool { connectedCamera?.model.supportsFocusMode ?? true }
    var supportsAperture: Bool { connectedCamera?.model.supportsAperture ?? false }

    /// Action 6 `0x8E` pid `0x0044`. HUD holds the request; the subscribe push corrects it.
    func setApertureStrategy(_ strategy: ApertureStrategy) {
        guard supportsAperture else { return }
        status.apertureStrategy = strategy
        fireCamera(
            strategy.setFrame, name: "Aperture \(strategy.label)",
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "aperture: SET \(strategy.label) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))"
                )
            })
    }

    func setFocusMode(_ mode: FocusMode, onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setFocusMode(mode, suppliedAdmission: nil, onStage: onStage)
    }
    func setFocusMode(_ mode: FocusMode, admission: DJICommandAdmission,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil) {
        setFocusMode(mode, suppliedAdmission: admission, onStage: onStage)
    }

    private func setFocusMode(_ mode: FocusMode, suppliedAdmission admission: DJICommandAdmission?, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
        guard admission?.admits(commandOwner) ?? true else { onStage?(.notSent); return }
        guard supportsFocusMode else {
            onStage?(.notSent)
            return
        }
        let previous = status.focusMode
        let pin = editorReconciliation.holdFocusMode(mode)
        status.focusMode = mode
        guard editorReconciliation.isPending(pin) else {
            onStage?(.notSent)
            return
        }
        fireCamera(
            Commands.setFocusMode(mode), name: "Focus \(mode.label)", expect: .focus(mode),
            admission: admission, onStage: onStage,
            onFail: { [weak self] in
                guard let self, self.editorReconciliation.isPending(pin) else { return }
                _ = self.editorReconciliation.reject(pin)
                self.status.focusMode = previous
            },
            onSettle: { [weak self] ok in
                ControlLiveLog.line(
                    "focus: SET \(mode.label) ack=\(ok ? "ok" : (self?.controlNote ?? "failed"))")
            })
    }

    func setFocusTrack(_ track: FocusTrackMode) {
        guard supportsFocusMode else { return }
        let previous = status.focusTrack
        let pin = editorReconciliation.holdFocusTrack(track)
        status.focusTrack = track
        guard editorReconciliation.isPending(pin) else { return }
        lastFocusTrackAt = Date()
        // Same 0x8E waiter as audio / glamour GETs. The integration serializes the request.
        cameraSettings.setFocusTrack(track, previous: previous, pinID: pin.id)
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
        editorReconciliation.pinAudio(channel: channel)
        let previous = status.audioChannel
        status.audioChannel = channel
        cameraSettings.setChannel(channel, previous: previous)
    }

    func setVocalBoost(_ boost: VocalBoost) {
        editorReconciliation.pinAudio(vocal: boost)
        let previous = status.vocalBoost
        status.vocalBoost = boost
        cameraSettings.setVocalBoost(boost, previous: previous)
    }

    /// GET `0xA0` blob, patch `@2`, SET `0x9F`. Never invent the blob. The GET is
    /// a true round trip, so audio patches ride their own chain — never the SET path.
    func setWindNR(_ value: WindNoiseReduction) {
        editorReconciliation.pinAudio(wind: value)
        status.windNR = value
        cameraSettings.setWind(value)
    }

    func setDirectionalAudio(_ value: DirectionalAudio) {
        editorReconciliation.pinAudio(directional: value)
        status.directionalAudio = value
        status.windNR = .on
        cameraSettings.setDirectional(value)
    }

    func refreshFocusTrack() async {
        cameraSettings.refreshFocus()
        await cameraSettings.waitForPending()
    }

    /// Mimo persists glamour on the camera. GET pid `0x0039` and SET enable `@5 = 00`.
    func clearGlamourIfEnabled() async {
        cameraSettings.clearGlamour()
        await cameraSettings.waitForPending()
    }

    func refreshAudioState() async {
        cameraSettings.refreshAudio()
        await cameraSettings.waitForPending()
    }

    /// `0x02/0x18` via `Commands.setVideoFormat(resolution:frameRate:)`.
    func setVideoFormat(
        resolution: VideoResolution, frameRate: VideoFrameRate, fromOperator: Bool = true
    ) {
        guard !isMultiviewControlsOnly || (admitsMultiviewControl && !status.isRecording) else {
            return
        }
        guard currentShootingMode?.offersVideoFormat != false else { return }
        let format = VideoFormat(resolution: resolution, frameRate: frameRate)
        if fromOperator,
            !CamCapVideoFormat.allowsOperatorSet(
                format, available: status.availableVideoFormats,
                model: connectedCamera?.model, shootingMode: status.shootingMode)
        {
            return
        }
        let previousFormat = status.videoFormat
        let previousRes = status.videoResolution
        let previousFps = status.fps
        let previousShutter = status.shutterDenom
        let angle =
            ShutterAngle.rematchesFormat(
                usesAngle: OperatorPrefs.shutterUsesAngle, manual: status.expoMode == .manual,
                isPhoto: status.isPhoto, previousFps: previousFps, nextFps: format.frameRate.fps,
                alreadyPending: editorReconciliation.requestedFormatAngle != nil)
            ? editorReconciliation.requestedFormatAngle ?? OperatorPrefs.shutterAngleDegrees : nil
        editorReconciliation.advanceFormatGeneration()
        let requestGeneration = editorReconciliation.formatGeneration
        let modeGeneration = editorReconciliation.captureGeneration
        let sessionGeneration = controlGeneration
        // The dependent shutter has a bounded confirmation window beyond the
        // normal two-second FORMAT projection; no separate command task owns it.
        editorReconciliation.holdFormat(format, shutterAngle: angle)
        var next = status
        next.videoResolution = format.resolution
        next.videoFormat = format
        next.fps = format.frameRate.fps
        if let angle {
            let denom = ShutterAngle.denom(
                degrees: angle, fps: next.fps, available: next.availableShutterDenoms)
            editorReconciliation.pinExpo(shutter: denom)
            next.shutterDenom = denom
        }
        status = next
        fireCamera(
            Commands.setVideoFormat(
                resolution: format.resolution, frameRate: format.frameRate,
                shootingMode: VideoFormat.formatSetMode(
                    model: connectedCamera?.model, statusMode: currentShootingMode)),
            name: format.chipLabel,
            expect: .format(format),
            onFail: { [weak self] in
                guard let self, self.editorReconciliation.formatGeneration == requestGeneration,
                    self.editorReconciliation.captureGeneration == modeGeneration,
                    self.controlGeneration == sessionGeneration
                else { return }
                self.status.videoFormat = previousFormat
                self.status.videoResolution = previousRes
                self.status.fps = previousFps
                if self.editorReconciliation.requestedFormatAngle != nil {
                    self.status.shutterDenom = previousShutter
                    self.editorReconciliation.clearExpoPin(shutter: true)
                }
                self.editorReconciliation.clearFormat()
            })
        // The matching format subscribe owns the shutter rematch. A parallel
        // shutter SET can land on the old encoder and be reset by FORMAT.
        if controlNote == nil {
            controlNote = CamFov.ceilingNote(
                size: format.resolution.sizeTitle,
                held: zoomCycleFrom,
                stops: connectedCamera?.model.activeZoomStops(
                    resolution: format.resolution, shootingMode: status.shootingMode) ?? [])
        }
    }

    var bodyFamily: CameraBodyFamily {
        connectedCamera?.model.family ?? .other
    }

    var colorModes: [ColorMode] {
        if let model = connectedCamera?.model {
            return CamCapColorMode.wheel(available: status.availableColorModes, model: model)
        }
        return CamCapColorMode.wheel(available: status.availableColorModes, family: bodyFamily)
    }

    /// `0x02/0x42` via `Commands.setColorMode`.
    func setColorMode(_ mode: ColorMode) { setColorMode(mode, suppliedAdmission: nil) }
    func setColorMode(_ mode: ColorMode, admission: DJICommandAdmission) {
        setColorMode(mode, suppliedAdmission: admission)
    }

    private func setColorMode(_ mode: ColorMode, suppliedAdmission admission: DJICommandAdmission?) {
        guard admission?.admits(commandOwner) ?? true else { return }
        if status.isRecording, mode != status.colorMode {
            controlNote = ControlHud.recordingColorLockNote
            return
        }
        guard colorModes.contains(mode) else { return }
        if gimbalMoveRunning { gimbal.cancelProgrammedMove() }
        let from = status.colorMode
        guard zoomColor.manualColorSelected(mode) else { return }
        editorReconciliation.holdColor(mode)
        fireCamera(
            Commands.setColorMode(mode, model: connectedCamera?.model),
            name: mode.label(for: bodyFamily), expect: .color(mode), admission: admission,
            onFail: { [weak self] in self?.editorReconciliation.clearColor() })
        hopNativeISO(from: from, to: mode, suppliedAdmission: admission)
        if mode == .dLog { zoomGesture.confirmIfReady() }
    }

    /// Feed tap: inside the AF-C face box → ActiveTrack SET with that rect.
    /// A second tap on the same spot → ActiveTrack there (Mimo / on-camera).
    /// Anywhere else → tap-to-focus.
    func handleFeedTap(at normalized: CGPoint) {
        let x = min(max(Double(normalized.x), 0), 1)
        let y = min(max(Double(normalized.y), 0), 1)
        if let box = FaceTrackTap.boxIfTapped(
            overlay: focusOverlay, x: x, y: y, sceneFaces: dimmedFaces)
        {
            feedDoubleTap.reset()
            startTracking(box)
            return
        }
        if let box = feedDoubleTap.register(
            x: x, y: y, at: Date.timeIntervalSinceReferenceDate)
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
    func markFocus(at normalized: CGPoint) { markFocus(at: normalized, suppliedAdmission: nil) }
    func markFocus(at normalized: CGPoint, admission: DJICommandAdmission) {
        markFocus(at: normalized, suppliedAdmission: admission)
    }

    private func markFocus(at normalized: CGPoint, suppliedAdmission admission: DJICommandAdmission?) {
        guard admission?.admits(commandOwner) ?? true else { return }
        guard supportsTapFocus else { return }
        if let admission { subjectTracking.cancel(sendClear: isTrackingActive, admission: admission) }
        else { subjectTracking.cancel(sendClear: isTrackingActive) }
        // Hold the tap reticle so AF-C face detect cannot hide it immediately.
        lastTapFocusAt = Date()
        lastFocusTapAt = Date()
        faceBox = nil
        faceTarget = nil
        lastFaceHitAt = nil
        let x = Float(min(max(normalized.x, 0), 1))
        let y = Float(min(max(normalized.y, 0), 1))
        focusPoint = CGPoint(x: Double(x), y: Double(y))
        guard datalink != nil else { return }
        if let admission { tapFocus.start(x: x, y: y, admission: admission) }
        else { tapFocus.start(x: x, y: y) }
    }

    /// Drag-to-track: `0x02/0xA6` centre+size, then poll `0x02/0xA5` until lock or idle.
    func startTracking(_ box: TrackingBox) {
        gimbal.cancelProgrammedMove()
        subjectTracking.start(box)
    }

    func cancelSubjectTracking() {
        subjectTracking.cancel(sendClear: true)
    }

    func handleGamepadAction(_ action: GamepadOperatorAction) {
        switch action {
        case .record:
            guard !controlBusy else { return }
            control.shutter()
        case .recenter:
            gimbal.performDoubleTap()
        case .flip:
            gimbal.flip()
        case .track:
            handleGamepadTrackToggle()
        case .zoomChipIn:
            setZoom(CamFov.nextJump(from: zoomCycleFrom, stops: zoomStops))
        case .zoomChipOut:
            setZoom(CamFov.previousJump(from: zoomCycleFrom, stops: zoomStops))
        case .isoUp:
            nudgeGamepadIso(steps: 1)
        case .isoDown:
            nudgeGamepadIso(steps: -1)
        case .shutterOpen:
            nudgeGamepadShutter(steps: 1)
        case .shutterClose:
            nudgeGamepadShutter(steps: -1)
        }
    }

    private var zoomCycleFrom: Double {
        zoomPinchPreview ?? zoomOptimistic ?? status.zoomFactor ?? fallbackZoomStop
    }

    private func nudgeGamepadIso(steps: Int) {
        guard let current = status.isoIndex else { return }
        let available =
            status.availableIsoIndices.isEmpty ? IsoIndex.allCases : status.availableIsoIndices
        guard let next = IsoIndex.stepped(from: current, stops: steps, available: available) else {
            return
        }
        setISO(next)
    }

    private func nudgeGamepadShutter(steps: Int) {
        let current = status.shutterDenom
        guard
            let next = CamCapShutter.steppedDenom(
                from: current, steps: steps, available: status.availableShutterDenoms)
        else { return }
        if GamepadShutterSync.shouldPersistPreferredAngle(
            usesAngle: OperatorPrefs.shutterUsesAngle,
            isPhoto: status.isPhoto,
            expoIsAuto: status.expoMode == .auto),
            let angle = GamepadShutterSync.preferredAngle(afterDenom: next, fps: status.fps)
        {
            OperatorPrefs.shutterAngleDegrees = angle
        }
        setShutterDenom(next)
    }

    /// Triangle/Y (discussion #159 left that face free): track the AF-C face, or cancel.
    func handleGamepadTrackToggle() {
        guard !isLocked else { return }
        switch GamepadFaceTrack.action(
            trackingActive: isTrackingActive,
            overlay: focusOverlay,
            sceneFaces: sceneFaces)
        {
        case .cancel:
            cancelSubjectTracking()
        case .track(let box):
            startTracking(box)
        case .none:
            break
        }
    }

    func noteFrameTooSmall() {
        subjectTracking.rejectSmallBox()
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

    private var isTrackingActive: Bool { subjectTracking.snapshot.active }

    private func adoptCameraFocus(x: Double, y: Double, fromTrackingBox: Bool) {
        guard
            CameraFocusPolicy.shouldAdopt(
                currentX: Double(focusPoint.x), currentY: Double(focusPoint.y),
                cameraX: x, cameraY: y,
                secondsSinceTap: fromTrackingBox
                    ? nil : lastFocusTapAt.map { Date().timeIntervalSince($0) })
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
        if gimbal.stickHeld { return true }
        return FaceTrackHold.isSceneMoving(
            secondsSinceGimbal: gimbal.lastStickAt.map { Date().timeIntervalSince($0) })
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
        setSceneFaces(faceTracks.map(\.box))
        if isTrackingActive {
            setFaceBox(nil)
            return
        }
        let sinceHit = FaceTrackHold.secondsSinceHit(lastHit: lastFaceHitAt, now: now)
        if FaceTrackHold.shouldDrop(secondsSinceHit: sinceHit, sceneMoving: sceneMoving) {
            setFaceBox(nil)
            faceTarget = nil
            lastFaceHitAt = nil
            return
        }
        guard let target = faceTarget else { return }
        setFaceBox(
            FaceTrackHold.follow(
                from: faceBox, toward: target, dt: dt, sceneMoving: sceneMoving))
    }

    // Face boxes are written per decoded frame. Unchanged writes still notify
    // every focus overlay reader, so publish only real motion.
    private func setFaceBox(_ box: TrackingBox?) {
        if faceBox != box { faceBox = box }
    }

    private func setSceneFaces(_ boxes: [TrackingBox]) {
        if sceneFaces != boxes { sceneFaces = boxes }
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
            guard
                HeadTrackPolicy.shouldSpawn(
                    detection: hit.box, existing: next.map(\.box))
            else { continue }
            next.append(FaceTrack(box: hit.box, target: hit.box, lastHit: now))
        }
        faceTracks = next
        setSceneFaces(next.map(\.box))
        if isTrackingActive {
            setFaceBox(nil)
            faceTarget = nil
            lastFaceHitAt = nil
            return
        }
        guard wantsFaceAF else {
            setFaceBox(nil)
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
        guard
            let packed = ScopeSampler.copyBGRA(buffer, maxWidth: ScopeSampler.maxWidth)
        else { return }
        lastFacePriorityEVAt = now
        let transfer = MonitorTransfer.resolved(
            LiveMonitorColorScience.transfer(status: status),
            colorMode: LiveMonitorColorScience.colorMode(
                isPhoto: status.isPhoto, colorMode: status.colorMode))
        guard
            let encoded = FacePriorityExposure.medianEncoded(
                bytes: packed.bytes, width: packed.width, height: packed.height,
                bytesPerRow: packed.bytesPerRow, boxes: boxes, transfer: transfer)
        else { return }
        let current = status.evComp ?? .zero
        guard
            let next = FacePriorityExposure.nextEV(
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
                setFaceBox(nil)
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
        setFaceBox(nil)
        faceTarget = nil
        lastFaceAt = nil
        lastFaceHitAt = nil
        faceTracks = []
        setSceneFaces([])
        facePriorityAcquireAt = nil
    }

    private struct FaceTrack {
        var box: TrackingBox
        var target: TrackingBox
        var lastHit: Date
    }

    /// One fire-and-forget SET. Latest-wins pending while the same opcode is in flight.
    private func fireCamera(
        _ frame: Duml.Frame, name: String, expect: DjiAppleControlExpectation? = nil,
        retransmits: Bool = true, coalesce: Bool = false, admission: DJICommandAdmission? = nil,
        onStage: (@MainActor (ControlWireEvent) -> Void)? = nil,
        onFail: (@MainActor () -> Void)? = nil,
        onSettle: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard !Task.isCancelled, admission?.admits(commandOwner) ?? true, controlLinkReady else {
            controlNote = "not live"
            onStage?(.notSent)
            onFail?()
            onSettle?(false)
            return
        }
        if isBrowsingMedia, frame.cmdSet == 2, frame.cmdId == 0x8e {
            onStage?(.notSent)
            onSettle?(false)
            return
        }
        controlNote = nil
        controlExchange.submit(
            .init(
                frame, name: name, expectation: expect,
                retransmits: retransmits, coalesce: coalesce, admission: admission)
        ) { event in
            switch event {
            case .stage(let stage): onStage?(stage)
            case .failed: onFail?()
            case .settled(let success): onSettle?(success)
            }
        }
    }

    /// True request/response (pairing, Wi-Fi creds, audio GET blobs). Rides its
    /// caller's chain — never the fire-and-forget SET path.
    @discardableResult
    private func requestCamera(
        _ frame: Duml.Frame, name: String, timeout: Duration = .seconds(3),
        logSend: Bool = true, admission: DJICommandAdmission? = nil
    ) async -> Bool {
        let generation = controlGeneration
        guard !Task.isCancelled, admission?.admits(commandOwner) ?? true,
            DjiAppleCameraSettings.requestControlGeneration.map({ $0 == generation }) ?? true
        else { return false }
        guard admitsMultiviewControl, datalink != nil, datalink?.isRebuilding != true else {
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
            let send: () -> Bool = { [self] in
                guard admitsMultiviewControl else { return false }
                let sequence: UInt16
                if let admission {
                    guard admission.admits(commandOwner), let datalink,
                        case .queued(let queued) = datalink.send(frame, admission: admission)
                    else { return false }
                    sequence = queued
                } else { sequence = datalink?.send(frame) ?? 0 }
                if logSend {
                    ControlLiveLog.line(
                        "control: send \(name) \(opcode) seq=\(sequence) flags=0x\(String(frame.flags, radix: 16)) payload=\(Duml.hex(frame.payload)) via=datalink"
                    )
                }
                return true
            }
            let reply: Duml.Frame
            if admission != nil {
                let registered = controlExchange.request(matching: [(frame.cmdSet, frame.cmdId)],
                    timeout: timeout, consumeHold: false, send: nil)
                guard send() else { registered.cancel(); return false }
                reply = try await registered.value()
            } else {
                reply = try await waitFrame(frame.cmdSet, frame.cmdId, timeout: timeout,
                    consumeHold: false) { _ = send() }
            }
            guard !Task.isCancelled, controlGeneration == generation else { return false }
            return finishControlReply(
                reply, name: name, opcode: opcode, expect: nil, announce: false)
        } catch {
            guard !Task.isCancelled, controlGeneration == generation else { return false }
            if logSend {
                if let note = ControlHud.timeoutNote(name: name, announce: false) {
                    controlNote = note
                }
                ControlLiveLog.line("control: timeout \(name) \(opcode) — waiter saw no ACK")
            }
            return false
        }
    }

    private func finishControlReply(
        _ reply: Duml.Frame, name: String, opcode: String, expect: DjiAppleControlExpectation?,
        late: Bool = false, announce: Bool = true
    ) -> Bool {
        let receiptSource = editorReconciliation.authority
        let parsed = CameraReply.parse(reply.payload)
        _ = CameraStatusDecoder.apply(
            reply, to: &cameraReportedCapture, model: connectedCamera?.model)
        controlSeam?.sessionDidChange()
        guard !Task.isCancelled, editorReconciliation.admitsSource(receiptSource) else { return false }
        var next = status
        _ = CameraStatusDecoder.apply(reply, to: &next, model: connectedCamera?.model)
        var reported = CameraStatus()
        _ = CameraStatusDecoder.apply(reply, to: &reported, model: connectedCamera?.model)
        let editor = editorReconciliation.project(incoming: next, reported: reported,
            committed: status, origin: .acknowledgment)
        // The valid captured wire receipt and permission to publish this editor
        // projection are separate. A successor request can retire the projection.
        if editorReconciliation.admits(editor.authority) {
            if editor.formatExpired { controlNote = "Frame rate unconfirmed; choose the shutter angle again" }
            if editorReconciliation.admits(editor.authority) { status = editor.status }
            if editorReconciliation.admits(editor.authority) { rematchShutterAngle(editor.rematchAngle) }
        }
        guard !Task.isCancelled, editorReconciliation.admitsSource(receiptSource) else { return false }
        ControlLiveLog.line(
            "control: got \(name) \(opcode) seq=\(reply.seq) flags=0x\(String(reply.flags, radix: 16)) payload=\(Duml.hex(reply.payload)) success=\(parsed.isSuccess)\(late ? " late-hold" : "")"
        )
        if parsed.isSuccess {
            log.info("control: \(name, privacy: .public) ok")
            return true
        }
        if expect?.matchesLegacySettlement(by: status) == true {
            controlNote = nil
            guard !Task.isCancelled, editorReconciliation.admitsSource(receiptSource) else { return false }
            ControlLiveLog.line(
                "control: \(name) \(opcode) subscribe already matches after \(parsed.message)")
            return true
        }
        if announce { controlNote = "\(name): \(parsed.message)" }
        guard !Task.isCancelled, editorReconciliation.admitsSource(receiptSource) else { return false }
        log.info("control: \(name, privacy: .public) \(parsed.message, privacy: .public)")
        return false
    }

    // ---- keepalive -------------------------------------------------------------------------------

    private func makeSessionHeartbeat() -> DjiAppleSessionHeartbeat {
        DjiAppleSessionHeartbeat(
            endpoint: .init(bluetooth: ble, datalink: datalink), timing: heartbeatTiming,
            context: { [weak self] in
                guard let self else { return .init() }
                return .init(
                    live: self.phase == .live,
                    ownedConnection: !self.isMultiviewBorrowed && self.connectedCamera != nil,
                    pathReady: self.cameraPathReady(), sceneActive: self.gimbalControlSceneActive,
                    holdsMonitor: self.holdsMonitor, browsingMedia: self.isBrowsingMedia,
                    sessionRecovering: self.sessionRecovery.isRecovering,
                    foregroundChecking: self.foregroundCheckTask != nil,
                    feedRepairing: self.pictureRecovery.isBusy,
                    formatPoking: self.firstPictureFormat.snapshot.running)
            }, event: { [weak self] event in
                guard let self else { return }
                switch event {
                case .cameraPathLost:
                    self.beginSessionRecovery(reason: "camera Wi-Fi lost", trigger: .softAPLost)
                case .heldMonitorMaintenance:
                    self.publishPipelineStats()
                    if self.phase == .live, self.gimbalControlSceneActive, !self.isBrowsingMedia {
                        self.recoverFirstPictureIfNeeded(allowTransportRecovery: false)
                    }
                case .liveMonitorMaintenance:
                    if !self.isBrowsingMedia, self.shouldStartUDPRebuild {
                        self.gimbal.endStick(cancelMove: true)
                        self.startFeedRecovery { [weak self] attempt in
                            await self?.repairDatalink(reason: "keepalive", attempt: attempt)
                        }
                    }
                    self.publishPipelineStats()
                    self.followCameraGallery()
                    if !self.isBrowsingMedia { self.recoverLiveViewIfNeeded() }
                }
            }, journal: { ControlLiveLog.line($0) })
    }

    func startKeepalive(ssid: String?) {
        guard !isMultiviewBorrowed else { return }
        sessionHeartbeat.start(monitorMaintenanceEnabled: ssid != nil)
    }

    private func beginFeedIncidentSession(cameraFamily: String) {
        incidentSessionActive = true
        incidentPrevious = nil
        let info = Bundle.main.infoDictionary ?? [:]
        AppDiagnostics.incidents.beginSession(
            FeedIncidentSessionContext(
                sessionID: UUID().uuidString,
                appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
                appBuild: info["CFBundleVersion"] as? String ?? "unknown",
                sourceRevision: info["OPCSourceRevision"] as? String ?? "unknown",
                osName: "iOS", osVersion: UIDevice.current.systemVersion,
                hardwareClass: DiagnosticCenter.machineIdentifier,
                cameraFamily: cameraFamily,
                testSource: AppDiagnostics.origin.currentTestSource(),
                buildIdentity: AppDiagnostics.origin.currentBuildIdentity()))
    }

    func recordFeedBreadcrumb(_ kind: FeedIncidentBreadcrumbKind, detail: String = "") {
        AppDiagnostics.incidents.recordBreadcrumb(
            FeedIncidentBreadcrumb(
                monotonicAt: ProcessInfo.processInfo.systemUptime, kind: kind, detail: detail))
    }

    private func recordFeedRepair(_ action: String, phase: FeedRepairPhase, reason: String? = nil) {
        AppDiagnostics.incidents.recordRepair(
            FeedRepairRecord(
                monotonicAt: ProcessInfo.processInfo.systemUptime, action: action, phase: phase,
                reason: reason))
    }

    private func publishFeedIncidentSnapshot() {
        guard incidentSessionActive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let wall = Date()
        let decode = decoder.incidentDecodeSnapshot
        let counts = [
            datalink?.videoPackets ?? 0, datalink?.accessUnits ?? 0,
            decode.submitted, decode.accepted, decode.output, decode.assistOutput,
            decoder.incidentPresentations, datalink?.incidentACKs ?? 0,
        ]
        let previous = incidentPrevious
        let elapsed = previous.map { now - $0.at } ?? 0
        let rates = counts.enumerated().map { index, count -> Double in
            guard let previous, elapsed > 0 else { return 0 }
            return Double(max(0, count - previous.counts[index])) / elapsed
        }
        incidentPrevious = (now, counts)
        let currentError = decoder.isDecoderWedged
        AppDiagnostics.incidents.noteDecoderGeneration(decoder.sourceFrameGeneration)
        AppDiagnostics.incidents.ingestSnapshot(
            FeedIncidentSnapshot(
                monotonicNow: now, wallClock: wall,
                rates: FeedIncidentRates(
                    packetHz: rates[0], accessUnitHz: rates[1],
                    decodeSubmitHz: rates[2], decodeAcceptHz: rates[3], decodedOutputHz: rates[4],
                    assistOutputHz: rates[5], presentHz: rates[6], ackHz: rates[7]),
                ages: FeedIncidentAges(
                    packetAge: datalink?.lastVideoPacketAt.map { wall.timeIntervalSince($0) },
                    accessUnitAge: datalink?.lastAccessUnitAt.map { wall.timeIntervalSince($0) },
                    decodeAcceptAge: decode.acceptedAge, decodedOutputAge: decode.outputAge,
                    assistOutputAge: decode.assistOutputAge,
                    presentAge: decoder.monitorPresentedAt.map { wall.timeIntervalSince($0) },
                    statusAge: datalink?.lastStatusAt.map { wall.timeIntervalSince($0) },
                    sendErrorAge: datalink?.lastSendError.map { wall.timeIntervalSince($0.at) },
                    sendErrorCode: datalink?.lastSendError?.code,
                    uplinkReplyAge: datalink?.lastSelfieFlipReplyAt.map {
                        wall.timeIntervalSince($0)
                    }),
                queue: datalink.map { FeedIncidentQueue($0.incidentQueue) } ?? FeedIncidentQueue(),
                decoder: FeedIncidentDecoder(
                    generation: decoder.sourceFrameGeneration,
                    formatGeneration: decoder.vtRebuildCount,
                    codec: decoder.incidentCodec,
                    width: Int(decoder.pictureSize.width), height: Int(decoder.pictureSize.height),
                    lastStatus: decoder.lastDecodeStatus, lastFlags: decoder.lastDecodeFlags,
                    origin: decoder.lastDecodeOrigin == "submit"
                        ? .sync
                        : FeedDecoderErrorOrigin(rawValue: decoder.lastDecodeOrigin) ?? .none,
                    errorClass: currentError ? "nativeDecoder" : nil,
                    errorCount: decoder.decoderErrors,
                    decoderFailed: currentError,
                    errorAge: decoder.lastDecodeErrorAt.map { wall.timeIntervalSince($0) },
                    receivedIrap: decoder.sawKeyframe,
                    awaitingIrap: decoder.awaitingIDR,
                    hasDecodableReferences: decoder.canReleaseIDRHold,
                    lastIrapAge: decoder.lastIrapAt.map { wall.timeIntervalSince($0) },
                    lastSuccessfulOutputAge: decode.outputAge),
                lifecycle: FeedIncidentLifecycle(
                    foreground: gimbalControlSceneActive, settingsCovered: incidentSettingsCovered,
                    playbackActive: status.inPlayback || isBrowsingMedia,
                    connected: connectedCamera != nil,
                    liveEstablished: decoder.lastPresentedAt != nil,
                    thermalState: String(ProcessInfo.processInfo.thermalState.rawValue),
                    memoryWarning: DiagnosticCenter.shared.hadRecentMemoryWarning(),
                    lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    sceneActive: gimbalControlSceneActive,
                    assistState: decoder.effects.replacesIdentityFeed ? "replacement" : "identity",
                    outputObservable: decoder.videoToolboxActive,
                    presentationExpected: !incidentSettingsCovered),
                watchdogAction: feedWatchdog.stage.rawValue,
                ingress: datalink?.incidentIngress))
    }

    private func publishPipelineStats() {
        publishFeedIncidentSnapshot()
        ControlLiveLog.line(decoder.takePipelineTimingLine())
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
                "\(videoPackets).\(rawAccessUnits).\(hasVideoFormat).\(liveViewHistory.locallyAcceptedEnables).\(datalink?.receiveErrorCount ?? 0)"
            let now = Date()
            guard
                signature != lastFirstPictureSignature
                    || now.timeIntervalSince(lastFirstPictureLogAt) >= 3
            else { return }
            lastFirstPictureSignature = signature
            lastFirstPictureLogAt = now
            let videoAge =
                datalink?.lastVideoPacketAt.map {
                    String(format: "%.1f", Date().timeIntervalSince($0))
                } ?? "none"
            let statusAge =
                datalink?.lastStatusAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) }
                ?? "none"
            let write: String
            switch datalink?.lastWriteLanded {
            case true: write = "ok"
            case false: write = "fail"
            default: write = "—"
            }
            let auAge =
                self.datalink?.lastAccessUnitAt.map {
                    String(format: "%.1f", Date().timeIntervalSince($0))
                } ?? "none"
            let rebuildAge =
                self.datalink?.secondsSinceLastRebuild.map { String(format: "%.1f", $0) } ?? "none"
            let hadVideo = FeedWatchdog.hadVideo(
                videoPackets: self.videoPackets,
                lastVideoPacketAge: self.datalink?.lastVideoPacketAt.map {
                    Date().timeIntervalSince($0)
                })
            log.info(
                "live: first-picture videoPkts=\(self.videoPackets, privacy: .public) aus=\(self.rawAccessUnits, privacy: .public) lastAU=\(auAge, privacy: .public)s drop=\(self.droppedIncomplete, privacy: .public) rxErr=\(self.datalink?.receiveErrorCount ?? 0, privacy: .public) lastVideo=\(videoAge, privacy: .public)s lastStatus=\(statusAge, privacy: .public)s lastRebuild=\(rebuildAge, privacy: .public)s hadVideo=\(hadVideo ? 1 : 0) format=\(self.hasVideoFormat ? 1 : 0) idrHold=\(self.decoder.awaitingIDR ? 1 : 0) nals=\(self.nalTypes, privacy: .public) enables=\(self.liveViewHistory.locallyAcceptedEnables, privacy: .public) tcp=\(self.datalink?.isTcpPokeReady == true ? 1 : 0) flow=\(self.datalink?.isFlowHealthy == true ? 1 : 0) write=\(write, privacy: .public)"
            )
        }
    }

    #if DEBUG
        /// Read-only local history. Date.distantPast remains the donor sentinel;
        /// these are app operation facts, never camera receipt/picture evidence.
        struct LiveViewDonorHistory {
            let initialAccepted: Bool
            let locallyAcceptedEnables: Int
            let lastEnableWallTime: Date
            let idrHoldEnableCount: Int
            let gateInFlight: Bool
            let watchdogStage: FeedWatchdog.Stage
        }
        var liveViewDonorHistory: LiveViewDonorHistory {
            .init(initialAccepted: liveViewHistory.initialAccepted,
                locallyAcceptedEnables: liveViewHistory.locallyAcceptedEnables, lastEnableWallTime: liveViewHistory.lastAcceptedEnableWallTime,
                idrHoldEnableCount: liveViewHistory.idrHoldEnableCount, gateInFlight: liveViewHistory.gateInFlight,
                watchdogStage: feedWatchdog.stage)
        }
        /// Calls the current admitted owner through the app compatibility projection.
        /// No readiness override; original donor bodies/results are archived separately.
        @discardableResult
        func donorRecoverLiveView(force: Bool, reason: String) -> Bool {
            sendRecoverEnable(force: force, reason: reason)
        }
        private func liveViewDonorDate() -> Date {
            guard let timing = liveViewDonorTiming else { return Date() }
            return Date(timeIntervalSinceReferenceDate: timing.wallNow())
        }
    #endif

    private func beginIDRHoldIfNeeded() {
        #if DEBUG
        let presented = decoder.lastPresentedAt.map { liveViewDonorDate().timeIntervalSince($0) }
        #else
        let presented = decoder.lastPresentedAt.map { Date().timeIntervalSince($0) }
        #endif
        if CameraSoftAP.shouldBeginIDRHoldOnEnable(
            hasPresentedPicture: CameraSoftAP.isPresentedPictureFresh(
                secondsSinceLastPresented: presented))
        {
            decoder.beginIDRHold()
        }
    }

    /// Pocket, Nano and Action 6 capture (`0x09/0xa8`). Other Action / 360 live start is
    /// uncaptured — do not invent it.
    func startCapturedLiveView(reason: String) -> Bool {
        guard !isMultiviewBorrowed else { return false }
        if datalink == nil {
            // Explicit legacy local acceptance: no run/endpoint/history or wire evidence.
            return (!isBrowsingMedia || reason == "media browse ended")
                && connectedCamera?.model.usesCapturedLiveEnable != false
        }
        let purpose: DjiAppleLiveViewPurpose = reason == "media browse ended"
            ? .capturedMediaReturnRecipe : .capturedRecipe
        return locallyAccepted(pictureRecovery.requestLiveView(purpose, reason: reason))
    }

    private func locallyAccepted(_ outcome: DjiAppleLiveViewOutcome) -> Bool {
        if case .locallyAccepted = outcome { return true }
        return false
    }

    /// One captured owner operation after path or handshake admission.
    private func sendInitialLiveViewEnable(displayAttached: Bool, pathProven: Bool = false) {
        _ = pictureRecovery.requestLiveView(.initial(pathProven: pathProven, displayAttached: displayAttached),
            reason: pathProven || displayAttached ? "first picture" : "display wait")
    }

    /// SET ACK silence while video is dead. Video still flowing is handled in
    /// `settleInflightTimeout` — that must not tear the socket.
    private func noteCommandTimeout() {
        let now = Date()
        commandTimeoutsAt = commandTimeoutsAt.filter {
            now.timeIntervalSince($0) < CameraSoftAP.commandTimeoutWindow
        }
        commandTimeoutsAt.append(now)
        let videoFresh =
            datalink?.lastVideoPacketAt.map {
                now.timeIntervalSince($0) < FeedWatchdog.stallThreshold
            } == true
        let statusFresh =
            datalink?.lastStatusAt.map {
                now.timeIntervalSince($0) < FeedWatchdog.stallThreshold
            } == true
        let downlinkFresh = [datalink?.lastStatusAt, datalink?.lastVideoPacketAt]
            .compactMap { $0 }
            .contains { now.timeIntervalSince($0) < CameraSoftAP.commandTimeoutWindow }
        guard
            CameraSoftAP.shouldRebuildAfterCommandTimeouts(
                timeoutsInWindow: commandTimeoutsAt.count,
                downlinkFresh: downlinkFresh,
                videoFresh: videoFresh,
                rebuildInFlight: datalink?.isRebuilding == true || pictureRecovery.isBusy,
                secondsSinceLastRebuild: datalink?.secondsSinceLastRebuild,
                statusFresh: statusFresh
            )
        else { return }
        if FeedWatchdog.shouldHoldForGOPReset(
            secondsSinceLastEnable: now.timeIntervalSince(liveViewHistory.lastAcceptedEnableWallTime),
            lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) }
        ) {
            log.info("control: SET timeouts during GOP-reset grace — leave UDP")
            return
        }
        if FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: secondsSinceFocusTrackSet) {
            log.info("control: SET timeouts during AF-C grace — leave UDP")
            return
        }
        if CamFov.shouldHoldWatchdog(
            secondsSinceSet: secondsSinceZoomSet, pinchActive: zoomPinchPreview != nil)
        {
            log.info("control: SET timeouts during zoom grace — leave UDP")
            return
        }
        if GimbalStick.shouldHoldWatchdog(
            secondsSinceThrow: secondsSinceGimbalThrow,
            lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) },
            stickHeld: gimbal.stickHeld)
        {
            log.info("control: SET timeouts during gimbal grace — leave UDP")
            return
        }
        if FeedWatchdog.shouldHoldForCameraSet(
            secondsSinceSet: datalink?.secondsSinceLastCommand,
            lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) })
        {
            log.info("control: SET timeouts during SET grace — leave UDP")
            return
        }
        commandTimeoutsAt.removeAll()
        log.info("control: SET timeouts with video stale — rebuild UDP")
        ControlLiveLog.line("control: SET timeouts, video stale — rebuilding UDP")
        gimbal.endStick(cancelMove: true)
        startFeedRecovery { [weak self] attempt in
            await self?.repairDatalink(reason: "command timeouts", attempt: attempt)
        }
    }

    /// One UDP rebuild at a time. Keepalive / control must not collide with
    /// first-picture rebuild (that canceled the new socket and RST’d TCP 7001).
    private var shouldStartUDPRebuild: Bool {
        guard cameraMedia.resumeLiveTask == nil else { return false }
        let now = Date()
        if FeedWatchdog.shouldHoldForGOPReset(
            secondsSinceLastEnable: now.timeIntervalSince(liveViewHistory.lastAcceptedEnableWallTime),
            lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) }
        ) {
            return false
        }
        if FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: secondsSinceFocusTrackSet) {
            return false
        }
        if CamFov.shouldHoldWatchdog(
            secondsSinceSet: secondsSinceZoomSet, pinchActive: zoomPinchPreview != nil)
        {
            return false
        }
        if GimbalStick.shouldHoldWatchdog(
            secondsSinceThrow: secondsSinceGimbalThrow,
            lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) },
            stickHeld: gimbal.stickHeld)
        {
            return false
        }
        if FeedWatchdog.shouldHoldForCameraSet(
            secondsSinceSet: datalink?.secondsSinceLastCommand,
            lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) })
        {
            return false
        }
        let videoFresh =
            datalink?.lastVideoPacketAt.map {
                now.timeIntervalSince($0) < FeedWatchdog.stallThreshold
            } == true
        let statusFresh =
            datalink?.lastStatusAt.map {
                now.timeIntervalSince($0) < FeedWatchdog.stallThreshold
            } == true
        return CameraSoftAP.shouldKeepaliveRebuildUDP(
            flowNeedsRebuild: datalink?.needsRebuild == true,
            rebuildInFlight: datalink?.isRebuilding == true || pictureRecovery.isBusy,
            secondsSinceLastRebuild: datalink?.secondsSinceLastRebuild,
            videoFresh: videoFresh,
            sawPicture: hasStableLivePicture,
            statusFresh: statusFresh,
            secondsSinceLastEnable: now.timeIntervalSince(liveViewHistory.lastAcceptedEnableWallTime),
            pathReady: cameraPathReady()
        )
    }

    /// First-picture enable, then the feed watchdog. Cumulative `videoPackets` is
    /// not a stall signal — after 3–5 min it stays huge even if UDP 9004 went quiet.
    /// A frozen first GOP still has `lastPresentedAt` — that must not skip recover.
    /// 1 Hz. Playback before any picture is stray (a previous session left the
    /// camera there) and keeps the exit below; playback after picture is the
    /// operator opening the camera's gallery, which used to be kicked back to
    /// live within a second.
    private func followCameraGallery() {
        if phase == .live, decoder.lastPresentedAt != nil, status.inPlayback {
            cameraGalleryAwayTicks = 0
            if !cameraGalleryOpen {
                ControlLiveLog.line("media: camera gallery open — following")
                cameraGalleryOpen = true
            }
        } else if cameraGalleryOpen {
            cameraGalleryAwayTicks += 1
            if cameraGalleryAwayTicks >= 3 || phase != .live {
                ControlLiveLog.line("media: camera gallery closed — returning to live")
                cameraGalleryOpen = false
            }
        }
    }

    private func recoverLiveViewIfNeeded() {
        guard !isBrowsingMedia, !holdsMonitor, cameraMedia.resumeLiveTask == nil else { return }
        // Media opens on the next UI pass; exit and repairs must not fight it.
        if cameraGalleryOpen { return }
        if needsForegroundRecover { return }
        if datalink?.isRebuilding == true || pictureRecovery.isBusy { return }
        guard cameraPathReady() else { return }
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
                secondsSinceLastEnable: Date().timeIntervalSince(liveViewHistory.lastAcceptedEnableWallTime))
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
        applyFeedWatchdog()
    }

    private func logFirstPictureObserve(
        step: CameraSoftAP.FirstPictureStep,
        packets: Int,
        deferred: Bool
    ) {
        let original = VideoFormat.firstPictureOriginal(
            format: status.videoFormat,
            resolution: status.videoResolution,
            fps: status.fps)
        let kick = VideoFormat.firstPictureEncoderKick(
            from: original, available: status.availableVideoFormats)
        let known = VideoFormat.hasKnownRecordingFormat(
            format: status.videoFormat,
            resolution: status.videoResolution,
            fps: status.fps,
            availableCount: status.availableVideoFormats.count)
        let legal =
            status.availableVideoFormats.isEmpty
            || status.availableVideoFormats.contains(kick)
        let presented =
            decoder.lastPresentedAt.map {
                String(format: "%.1f", Date().timeIntervalSince($0))
            } ?? "none"
        let videoAge =
            datalink?.lastVideoPacketAt.map {
                String(format: "%.1f", Date().timeIntervalSince($0))
            } ?? "none"
        let model = connectedCamera?.model.name ?? "none"
        let needs = connectedCamera?.model.needsFirstPictureFormatPoke == true
        let line =
            "feed: first-picture step=\(step.rawValue) defer=\(deferred ? 1 : 0) needsPoke=\(needs ? 1 : 0) poked=\(firstPictureFormatPoked ? 1 : 0) inFlight=\(firstPictureFormat.snapshot.running ? 1 : 0) known=\(known ? 1 : 0) model=\(model) boot=\(original.chipLabel) kick=\(kick.chipLabel) legal=\(legal ? 1 : 0) formats=\(status.availableVideoFormats.count) enables=\(liveViewHistory.locallyAcceptedEnables) videoPkts=\(packets) lastVideo=\(videoAge)s presented=\(presented)s decoderFmt=\(decoder.hasFormat ? 1 : 0) idrHold=\(decoder.awaitingIDR ? 1 : 0)"
        let signature =
            "\(step.rawValue).\(deferred).\(needs).\(firstPictureFormatPoked).\(known).\(packets).\(liveViewHistory.locallyAcceptedEnables).\(decoder.hasFormat)"
        let now = Date()
        guard
            signature != lastFirstPictureSignature
                || now.timeIntervalSince(lastFirstPictureLogAt) >= 3
        else { return }
        lastFirstPictureSignature = signature
        lastFirstPictureLogAt = now
        log.info("\(line, privacy: .public)")
        ControlLiveLog.line(line)
    }

    private func recoverFirstPictureIfNeeded(
        allowTransportRecovery: Bool = true, currentRepairOwnsFirstPicture: Bool = false
    ) {
        if datalink?.isRebuilding == true
            || (pictureRecovery.isBusy && !currentRepairOwnsFirstPicture)
        {
            return
        }
        let packets = datalink?.videoPackets ?? 0
        let since = Date().timeIntervalSince(liveViewHistory.lastAcceptedEnableWallTime)
        let videoAge = datalink?.lastVideoPacketAt.map { Date().timeIntervalSince($0) }
        let step = CameraSoftAP.firstPictureStep(
            videoPackets: packets,
            enableSends: liveViewHistory.locallyAcceptedEnables,
            secondsSinceLastEnable: since,
            secondsSinceLastVideo: videoAge,
            secondsSinceLastRebuild: datalink?.secondsSinceLastRebuild,
            secondsSinceLastStatus: datalink?.lastStatusAt.map { Date().timeIntervalSince($0) },
            needsRecordingFormatPoke: connectedCamera?.model.needsFirstPictureFormatPoke == true,
            alreadyPokedRecordingFormat: firstPictureFormatPoked,
            recordingFormatPokeInFlight: firstPictureFormat.snapshot.running,
            isRecording: status.isRecording,
            hasPresentedPicture: CameraSoftAP.isPresentedPictureFresh(
                secondsSinceLastPresented: decoder.lastPresentedAt.map {
                    Date().timeIntervalSince($0)
                }))
        let known = VideoFormat.hasKnownRecordingFormat(
            format: status.videoFormat,
            resolution: status.videoResolution,
            fps: status.fps,
            availableCount: status.availableVideoFormats.count)
        let deferPoke =
            step == .pokeRecordingFormat
            && CameraSoftAP.shouldDeferRecordingFormatPoke(
                hasKnownRecordingFormat: known,
                secondsSinceLastEnable: since)
        logFirstPictureObserve(step: step, packets: packets, deferred: deferPoke)
        switch step {
        case .wait:
            break
        case .pokeRecordingFormat:
            if deferPoke { return }
            firstPictureFormat.start()
            return
        case .resendEnable:
            // Do not route through sendRecoverEnable — inPlayback / VT-ready
            // holds skipped the only PLI and sat on Waiting for live view.
            if liveViewHistory.locallyAcceptedEnables == 0 {
                log.info("live: first-picture enable never sent — sending now")
                sendInitialLiveViewEnable(
                    displayAttached: decoder.isDisplayReady, pathProven: true)
                return
            }
            log.info("live: first-picture resend enable (waiting for IDR)")
            guard locallyAccepted(pictureRecovery.requestLiveView(.firstPictureResend,
                reason: "first-picture resend")) else { return }
            recordFeedRepair(
                "enable", phase: .locallySent, reason: FeedRepairRecord.firstPictureReason)
            return
        case .rebuildUDP:
            guard allowTransportRecovery else { return }
            log.info(
                "live: first-picture rebuild UDP (receive died pkts=\(packets, privacy: .public) lastVideo=\(videoAge ?? -1, format: .fixed(precision: 1), privacy: .public)s)"
            )
            startFeedRecovery { [weak self] attempt in
                await self?.repairDatalink(reason: "first picture", attempt: attempt)
            }
            return
        case .rejoin:
            guard allowTransportRecovery else { return }
            log.info("live: first-picture full rejoin (SoftAP bind kept)")
            startFeedRecovery { [weak self] attempt in
                await self?.rejoinDatalinkKeepingLive(attempt: attempt)
            }
            return
        }
    }

    private func applyFeedWatchdog() {
        if needsForegroundRecover { return }
        if datalink?.isRebuilding == true || pictureRecovery.isBusy { return }
        #if DEBUG
        let now = liveViewDonorDate()
        #else
        let now = Date()
        #endif
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
            pathReady: cameraPathReady(),
            hasFormat: decoder.hasFormat,
            decoderFailed: decoder.isDecoderWedged || decoder.displayLayer.status == .failed,
            live: live,
            sawPicture: decoder.lastPresentedAt != nil,
            tcpPokeReady: datalink?.isTcpPokeReady ?? false,
            displayedImageRemoved: wentBlack,
            lastBleNotifyAge: lastBleNotifyAt.map { now.timeIntervalSince($0) },
            secondsSinceLastRebuild: datalink?.secondsSinceLastRebuild,
            hadVideo: FeedWatchdog.hadVideo(
                videoPackets: datalink?.videoPackets ?? 0,
                lastVideoPacketAge: datalink?.lastVideoPacketAt.map { now.timeIntervalSince($0) }),
            secondsSinceLastEnable: now.timeIntervalSince(liveViewHistory.lastAcceptedEnableWallTime),
            secondsSinceFocusTrackSet: secondsSinceFocusTrackSet,
            secondsSinceZoomSet: secondsSinceZoomSet,
            zoomPinchActive: zoomPinchPreview != nil,
            secondsSinceGimbalThrow: secondsSinceGimbalThrow,
            gimbalStickHeld: gimbal.stickHeld,
            secondsSinceCameraSet: datalink?.secondsSinceLastCommand,
            lastDecoderOutputAge: decoder.nativeOutputAge,
            decoderOutputExpected: decoder.nativeOutputExpected,
            referenceRecoveryNeeded: decoder.referenceRecoveryNeeded,
            secondsSinceLastIrap: decoder.lastIrapAt.map { now.timeIntervalSince($0) },
            repairReady: decoder.isDisplayReady && !isBrowsingMedia && !status.inPlayback
                && !liveViewHistory.gateInFlight
        )
        let watchdogBeforeTick = feedWatchdog
        let action = feedWatchdog.tick(snap)
        let recovering = feedWatchdog.isRecovering || pictureRecovery.isBusy
        if recovering != feedRecovering { feedRecovering = recovering }
        switch action {
        case .none:
            if decoder.awaitingIDR, decoder.canReleaseIDRHold,
                FeedWatchdog.shouldReleaseIDRHold(
                    awaitingIDR: true,
                    udpReceiveAlive: FeedWatchdog.udpReceiveAlive(snap),
                    secondsSinceLastEnable: snap.secondsSinceLastEnable,
                    hasPresentedPicture: decoder.lastPresentedAt != nil)
            {
                decoder.endIDRHold()
                log.info("feed: release IDR hold — UDP alive, picture on layer")
            }
            if FeedWatchdog.udpReceiveAlive(snap), decoder.isPresentFrozen {
                let now = Date()
                if lastFeedFreezeLogAt.map({ now.timeIntervalSince($0) >= 2 }) ?? true {
                    lastFeedFreezeLogAt = now
                    log.info(
                        "feed: freeze lastFrame=\(snap.lastDecodedFrameAge ?? -1, format: .fixed(precision: 1), privacy: .public)s (UDP alive — keep picture)"
                    )
                    ControlLiveLog.line(decoder.processedFeed?.debugLine ?? "feed: freeze")
                    logFeedObserve(snap: snap, watchdog: action)
                }
            }
            if !FeedWatchdog.udpReceiveAlive(snap),
                FeedWatchdog.shouldHoldForGOPReset(
                    secondsSinceLastEnable: snap.secondsSinceLastEnable,
                    lastVideoPacketAge: snap.lastVideoPacketAge)
            {
                log.info(
                    "feed: hold UDP rebuild — GOP-reset grace lastEnable=\(snap.secondsSinceLastEnable ?? -1, format: .fixed(precision: 1), privacy: .public)s lastVideo=\(snap.lastVideoPacketAge ?? -1, format: .fixed(precision: 1), privacy: .public)s"
                )
                logFeedObserve(snap: snap, watchdog: action)
            } else if !FeedWatchdog.udpReceiveAlive(snap),
                FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: snap.secondsSinceFocusTrackSet)
            {
                log.info(
                    "feed: hold UDP rebuild — AF-C grace lastSet=\(snap.secondsSinceFocusTrackSet ?? -1, format: .fixed(precision: 1), privacy: .public)s lastVideo=\(snap.lastVideoPacketAge ?? -1, format: .fixed(precision: 1), privacy: .public)s"
                )
                ControlLiveLog.line(
                    "feed: hold UDP rebuild — AF-C grace lastSet=\(String(format: "%.1f", snap.secondsSinceFocusTrackSet ?? -1))s"
                )
                logFeedObserve(snap: snap, watchdog: action)
            } else if !FeedWatchdog.udpReceiveAlive(snap),
                CamFov.shouldHoldWatchdog(
                    secondsSinceSet: snap.secondsSinceZoomSet,
                    pinchActive: snap.zoomPinchActive)
            {
                log.info(
                    "feed: hold UDP rebuild — zoom grace lastSet=\(snap.secondsSinceZoomSet ?? -1, format: .fixed(precision: 1), privacy: .public)s lastVideo=\(snap.lastVideoPacketAge ?? -1, format: .fixed(precision: 1), privacy: .public)s"
                )
                ControlLiveLog.line(
                    "feed: hold UDP rebuild — zoom grace lastSet=\(String(format: "%.1f", snap.secondsSinceZoomSet ?? -1))s"
                )
                logFeedObserve(snap: snap, watchdog: action)
            } else if !FeedWatchdog.udpReceiveAlive(snap),
                GimbalStick.shouldHoldWatchdog(
                    secondsSinceThrow: snap.secondsSinceGimbalThrow,
                    lastVideoPacketAge: snap.lastVideoPacketAge,
                    stickHeld: snap.gimbalStickHeld)
            {
                ControlLiveLog.line(
                    "feed: hold enable — gimbal stick held=\(snap.gimbalStickHeld ? 1 : 0) lastThrow=\(String(format: "%.1f", snap.secondsSinceGimbalThrow ?? -1))s"
                )
                logFeedObserve(snap: snap, watchdog: action)
            } else if !FeedWatchdog.udpReceiveAlive(snap),
                FeedWatchdog.shouldHoldForCameraSet(
                    secondsSinceSet: snap.secondsSinceCameraSet,
                    lastVideoPacketAge: snap.lastVideoPacketAge)
            {
                ControlLiveLog.line(
                    "feed: hold repair — SET grace lastSet=\(String(format: "%.1f", snap.secondsSinceCameraSet ?? -1))s"
                )
                logFeedObserve(snap: snap, watchdog: action)
            }
            return
        case .resendLiveViewEnable:
            gimbal.endStick(cancelMove: true)
            let line =
                feedWatchdog.stallLogLine(snap) + " stickHeld=\(gimbal.stickHeld ? 1 : 0)"
            log.info("\(line, privacy: .public)")
            ControlLiveLog.line(line)
            logFeedObserve(snap: snap, watchdog: action)
            datalink?.reRegister()
            if !sendRecoverEnable(force: true, reason: "watchdog") {
                feedWatchdog = watchdogBeforeTick
            }
        case .rebuildVTSession:
            gimbal.endStick(cancelMove: true)
            let referenceLossOnly = snap.referenceRecoveryNeeded
            let reason = referenceLossOnly ? "referenceLoss" : "outputSilence"
            recordFeedRepair("decoder", phase: .requested, reason: reason)
            ControlLiveLog.line("recovery: action=decoder effect=requested reason=\(reason)")
            logFeedObserve(snap: snap, watchdog: action)
            let pictureOwner = cameraMedia.resumeID
            startFeedRecovery { [weak self] attempt in
                guard let self, attempt.isCurrent, self.isLivePictureRepairCurrent(pictureOwner) else { return }
                let result = await attempt.repairNativeOutput(referenceLossOnly: referenceLossOnly,
                    pictureIntent: pictureOwner)
                guard attempt.isCurrent, self.isLivePictureRepairCurrent(pictureOwner) else { return }
                switch result {
                case .unspent:
                    self.feedWatchdog = watchdogBeforeTick
                case .blockedReadiness:
                    self.recordFeedRepair("decoder", phase: .blocked, reason: "notReady")
                    ControlLiveLog.line("recovery: action=decoder effect=blocked reason=notReady")
                case .restored:
                    self.recordFeedRepair("decoder", phase: .pictureRestored, reason: "outputResumed")
                    ControlLiveLog.line("recovery: action=decoder effect=freshPicture reason=outputResumed")
                    self.feedWatchdog = FeedWatchdog()
                case .presentationOnly:
                    self.recordFeedRepair("decoder", phase: .blocked, reason: "presentationOnly")
                    ControlLiveLog.line("recovery: action=decoder effect=blocked reason=presentationOnly")
                    self.feedWatchdog = FeedWatchdog()
                case .fullRejoinRequired:
                    AppDiagnostics.incidents.noteExhausted(now: ProcessInfo.processInfo.systemUptime)
                    ControlLiveLog.line("recovery: action=decoder effect=exhausted reason=pictureDeadline")
                    self.recordFeedRepair("rejoin", phase: .requested, reason: "pictureDeadline")
                    await self.rejoinDatalinkKeepingLive(attempt: attempt)
                case .endpointRepair, .superseded: break
                }
            }
        case .reopenDatalink:
            gimbal.endStick(cancelMove: true)
            log.info("\(self.feedWatchdog.stallLogLine(snap), privacy: .public)")
            ControlLiveLog.line(feedWatchdog.stallLogLine(snap))
            logFeedObserve(snap: snap, watchdog: action)
            recordFeedRepair("endpoint", phase: .requested, reason: "watchdog")
            rebuildUDPKeepingVT()
        case .fullSessionRejoin:
            // Last rung: the session-preserving rebuild did not bring 9004
            // back. New handshake on the same SoftAP, last frame held. This
            // used to map to another UDP rebuild — a camera that dropped the
            // session never answered, and Reconnecting stayed up (#218).
            gimbal.endStick(cancelMove: true)
            log.info("\(self.feedWatchdog.stallLogLine(snap), privacy: .public)")
            ControlLiveLog.line(feedWatchdog.stallLogLine(snap))
            logFeedObserve(snap: snap, watchdog: action)
            ControlLiveLog.line("feed: watchdog full datalink rejoin")
            recordFeedRepair("rejoin", phase: .requested, reason: "watchdog")
            startFeedRecovery { [weak self] attempt in
                await self?.rejoinDatalinkKeepingLive(attempt: attempt)
            }
        }
    }

    /// Classify-then-repair vs what the watchdog actually did. Observation only.
    private func logFeedObserve(snap: FeedWatchdog.Snapshot, watchdog: FeedWatchdog.Action) {
        let line = LinkDiagnoser.observeLine(snap: snap, watchdog: watchdog)
        log.info("\(line, privacy: .public)")
        ControlLiveLog.line(line)
    }

    /// Re-enable only after SoftAP + VT/display are ready. Holds P-frames until IDR.
    @discardableResult
    private func sendRecoverEnable(force: Bool, reason: String = "recover") -> Bool {
        locallyAccepted(pictureRecovery.requestLiveView(.recover(force: force), reason: reason))
    }

    func resetFeedWatchdog() { resetFeedWatchdog(ifCurrent: { true }) }

    private func resetFeedWatchdog(ifCurrent: () -> Bool) {
        guard ifCurrent() else { return }
        feedRecovering = false
        guard ifCurrent() else { return }
        feedWatchdog = FeedWatchdog()
        pictureRecovery.cancel()
        guard ifCurrent() else { return }
        lastFeedFreezeLogAt = nil
    }

    private func resetLinkHealthMeasurements(ifCurrent: () -> Bool = { true }) {
        guard ifCurrent() else { return }
        frameRate = FrameRateSampler()
        signalBarsFilter = LinkSignalBars()
        lastGoodFrameAt = nil
        consecutiveBadLiveFrames = 0
        lastDecoderErrorCount = 0
        lastReceiveErrorCount = 0
        recentKeepaliveFailures = 0
        liveFPS = "\u{2014}"
        guard ifCurrent() else { return }
        liveSignalBars = 0
        guard ifCurrent() else { return }
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
        if !decoder.awaitingIDR, let source = liveViewSource { pictureRecovery.notePresentedSource(scope: source) }
        armFaceAFAfterFirstPicture()
        if liveViewHistory.initialAccepted {
            let audio = audioRefreshPending
            let glamour = glamourClearPending
            let focus = focusTrackPending
            if audio || glamour || focus, !isBrowsingMedia {
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

    func refreshLinkHealth(at timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        frameRate.age(at: timestamp)
        noteTransportFailures()
        applyLinkPresentation()
    }

    private func applyLinkPresentation(ifCurrent: () -> Bool = { true }) {
        guard ifCurrent() else { return }
        if sessionRecovery.isRecovering {
            if liveFPS != SessionRecoveryCopy.heldFrameBadge {
                liveFPS = SessionRecoveryCopy.heldFrameBadge
            }
            guard ifCurrent() else { return }
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
        guard ifCurrent() else { return }
        let snapshot = CameraLinkHealthScorer.score(currentLinkHealthInputs())
        let bars = signalBarsFilter.update(score: snapshot.linkHealthScore)
        if bars != liveSignalBars { liveSignalBars = bars }
        guard ifCurrent() else { return }
        refreshFeedWarmup()
    }

    private func refreshFeedWarmup() {
        if holdsMonitor, decoder.lastPresentedAt != nil {
            if isFeedWarming { isFeedWarming = false }
            return
        }
        // FPS aging reports a stall; it must not restart first-picture warmup
        // and cover the held image. New sessions re-arm this gate in
        // resetLinkHealthMeasurements, while recovery keeps its own chrome.
        if !isFeedWarming, decoder.lastPresentedAt != nil { return }
        let next = LiveFeedWarmup.isWarming(
            hasPresentedPicture: decoder.lastPresentedAt != nil,
            measuredFPS: frameRate.displayFPS,
            rollingIntervals: frameRate.intervalCount,
            recovering: feedRecovering || pictureRecovery.isBusy,
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
        sessionHeartbeat.resetPathGrace()
        recordFeedBreadcrumb(.sceneActivity, detail: "inactive")
        gimbalControlSceneActive = false
        gimbal.cancelProgrammedMove()
        foregroundGeneration += 1
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        if case .live = phase { needsForegroundRecover = true }
    }

    func noteSceneBecameActive() {
        recordFeedBreadcrumb(.sceneActivity, detail: "active")
        gimbalControlSceneActive = true
        guard needsForegroundRecover else { return }
        needsForegroundRecover = false
        // The session owner is already reconnecting. It must not compete with a
        // second foreground repair when the hotspot approval returns to the app.
        guard !sessionRecovery.isRecovering, !isMultiviewBorrowed else { return }
        guard !isBrowsingMedia, cameraMedia.resumeLiveTask == nil else { return }
        guard phase == .live else {
            if let id = connectedCamera?.id ?? reconnectTarget {
                reconnect(to: id)
            }
            return
        }
        foregroundGeneration += 1
        let generation = foregroundGeneration
        let pictureOwner = cameraMedia.resumeID
        foregroundCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.foregroundGeneration == generation { self.foregroundCheckTask = nil }
            }
            let currentSSID = await DjiAppleWiFiJoiner.currentSSID()
            guard !Task.isCancelled, self.foregroundGeneration == generation else { return }
            await self.recoverAfterForeground(currentSSID: currentSSID, pictureOwner: pictureOwner)
        }
    }

    /// Fresh traffic on the expected SoftAP survives a short scene bounce. A
    /// missing/changed network needs the same BLE → Wi-Fi → UDP spine as Connect.
    /// Repainting a held LUT image is not evidence that the source recovered.
    private func recoverAfterForeground(currentSSID: String?, pictureOwner: Int) async {
        guard isLivePictureRepairCurrent(pictureOwner) else { return }
        let now = Date()
        let pathReady = cameraPathReady()
        // The hotspot host is not associated to any Wi-Fi, so its SSID says nothing.
        let expectedSSID = connectionSetup == .cameraWiFi ? joinedSSID : stationSSID
        let wrongNetwork =
            !usesHotspot && (currentSSID.map { !$0.isEmpty && $0 != expectedSSID } ?? false)
        let videoFresh =
            datalink?.lastVideoPacketAt.map {
                now.timeIntervalSince($0) < FeedWatchdog.stallThreshold
            } == true
        ControlLiveLog.line(
            "session: foreground path=\(pathReady ? 1 : 0) identity=\(wrongNetwork ? "changed" : currentSSID == nil ? "unknown" : "same") videoFresh=\(videoFresh ? 1 : 0) pictureFresh=\(hasFreshRecoveryPicture(since: now.addingTimeInterval(-FeedWatchdog.stallThreshold), now: now) ? 1 : 0)"
        )
        guard !wrongNetwork else {
            beginSessionRecovery(reason: "foreground camera network changed", trigger: .softAPLost)
            return
        }
        // Wi-Fi reassociates after suspension. The 1 Hz path check owns the
        // absent path with its 8 s grace; tearing BLE down here reconnected
        // on nearly every return from another app.
        guard pathReady else { return }
        if hasFreshRecoveryPicture(
            since: now.addingTimeInterval(-FeedWatchdog.stallThreshold), now: now)
        {
            return
        }
        // A watchdog repair that started before the scene event retains ownership.
        // The next keepalive tick can escalate it after this check releases the slot.
        guard !pictureRecovery.isBusy, datalink?.isRebuilding != true else { return }
        var videoResumed = videoFresh
        let resumeDeadline = now.addingTimeInterval(FeedWatchdog.stallThreshold)
        while !videoResumed, Date() < resumeDeadline {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard isLivePictureRepairCurrent(pictureOwner) else { return }
            videoResumed =
                datalink?.lastVideoPacketAt.map {
                    Date().timeIntervalSince($0) < FeedWatchdog.stallThreshold
                } == true
        }
        // The path may have dropped during the wait; its 8 s grace owns that.
        guard cameraPathReady(), !sessionRecovery.isRecovering else { return }
        guard videoResumed else {
            // Suspension usually leaves only the UDP endpoint stale. Renegotiate
            // it with BLE and the picture kept; its failure escalates to the
            // full session spine.
            ControlLiveLog.line("session: foreground video stale, renegotiating endpoint")
            startFeedRecovery { [weak self] attempt in
                await self?.repairDatalink(reason: "foreground", attempt: attempt)
            }
            return
        }
        ControlLiveLog.line("session: foreground fresh video, repairing presentation")
        decoder.prepareAfterForeground()
        gimbal.endStick(cancelMove: true)
        if decoder.nativeOutputExpected {
            // This task suppresses keepalive/watchdog ticks while it exists.
            // Release it so the existing native-output repair owner can run;
            // waiting here cannot revive an invalid VT session and would force
            // a full reconnect before the watchdog ever sees the stall.
            ControlLiveLog.line("session: foreground native output handed to watchdog")
            return
        }
        let repaired = await waitForRecoveryPicture(
            since: now, timeout: .seconds(CameraSoftAP.foregroundPictureGrace),
            pictureOwner: pictureOwner)
        guard !Task.isCancelled, isLivePictureRepairCurrent(pictureOwner) else { return }
        if !repaired {
            beginSessionRecovery(
                reason: "foreground presentation did not resume", trigger: .datalinkLost)
        }
    }

    /// A replacement endpoint needs a handshake; retain the held picture and SoftAP.
    private func rebuildUDPKeepingVT() {
        startFeedRecovery { [weak self] attempt in
            await self?.repairDatalink(reason: "feed watchdog", attempt: attempt)
        }
    }

    /// Native preparation stays app-owned; the shared attempt owns negotiation and picture wait.
    func repairDatalink(
        reason: String,
        pictureDeadline: Duration = .seconds(2 * CameraSoftAP.foregroundPictureGrace),
        attempt: DjiApplePictureRecovery.Attempt
    ) async {
        guard let driver = datalink else { return }
        _ = await attempt.repairEndpoint(.init(datalink: driver), reason: reason,
            pictureIntent: cameraMedia.resumeID, timeout: pictureDeadline)
    }

    private func makePictureRecovery() -> DjiApplePictureRecovery {
        DjiApplePictureRecovery(connectionRun: connectionRun, context: { [weak self] in
            guard let self else { return .init() }
            return .init(rebuilding: self.datalink?.isRebuilding == true,
                endpointIdentity: self.datalink.map { ObjectIdentifier($0) },
                pictureIntent: self.cameraMedia.resumeID, browsingMedia: self.isBrowsingMedia,
                holdsMonitor: self.holdsMonitor, sessionRecovering: self.sessionRecovery.isRecovering,
                ownsConnection: !self.isMultiviewBorrowed)
        }, native: .init(prepare: { [weak self] in
            guard let self else { return Date.timeIntervalSinceReferenceDate }
            self.gimbal.endStick(cancelMove: true)
            return self.prepareForDatalinkRecovery().timeIntervalSinceReferenceDate
        }, prepareScoped: { [weak self] scope in
            guard let self, scope.isCurrent else { return Date.timeIntervalSinceReferenceDate }
            self.gimbal.endStick(cancelMove: true, ifCurrent: { scope.isCurrent })
            guard scope.isCurrent else { return Date.timeIntervalSinceReferenceDate }
            return self.prepareForDatalinkRecovery(ifCurrent: { scope.isCurrent }).timeIntervalSinceReferenceDate
        }, enable: {}, probe: { [weak self] in
            self?.recoverFirstPictureIfNeeded(
                allowTransportRecovery: false, currentRepairOwnsFirstPicture: true)
        }, picture: { [weak self] since, now in
            guard let self else { return .init() }
            return .init(fresh: self.hasFreshRecoveryPicture(
                since: Date(timeIntervalSinceReferenceDate: since),
                now: Date(timeIntervalSinceReferenceDate: now)),
                lastPresentedAt: self.decoder.lastPresentedAt?.timeIntervalSinceReferenceDate)
        }), liveViewNative: .init(observeOutput: { [weak self] since, now in
            guard let self else { return nil }
            return .init(pathReady: self.cameraPathReady(), playbackBlocked: self.status.inPlayback,
                presentationReady: self.decoder.isPresentationReady, awaitingIDR: self.decoder.awaitingIDR,
                nativeOutputExpected: self.decoder.nativeOutputExpected,
                nativeOutputAge: self.decoder.nativeOutputAge,
                lastIrapWallTime: self.decoder.lastIrapAt?.timeIntervalSinceReferenceDate,
                picture: .init(fresh: self.hasFreshRecoveryPicture(
                    since: Date(timeIntervalSinceReferenceDate: since),
                    now: Date(timeIntervalSinceReferenceDate: now)),
                    lastPresentedAt: self.decoder.lastPresentedAt?.timeIntervalSinceReferenceDate))
        }, perform: { [weak self] effect, scope in
            self?.performLiveViewNative(effect, scope: scope)
        }, rebuildOutput: { [weak self] referenceLossOnly, scope in
            guard let self, scope.isCurrent else { return false }
            return self.decoder.rebuildPresentationIfNeeded(referenceLossOnly: referenceLossOnly)
        }), timing: pictureRecoveryTiming, event: { [weak self] event, scope in
            guard let self, scope.isCurrent else { return }
            switch event {
            case .admitted:
                self.status.meteredEv = nil
                guard scope.isCurrent else { return }
                self.feedRecovering = true
                guard scope.isCurrent else { return }
                self.refreshFeedWarmup()
            case .released:
                if !self.feedWatchdog.isRecovering { self.feedRecovering = false }
                guard scope.isCurrent else { return }
                self.refreshFeedWarmup()
            case .endpointInitialPolicyCompleted:
                // Original native.enable reset this even when initial policy refused.
                // The event is local workflow completion, not a wire receipt.
                self.feedWatchdog = FeedWatchdog()
            case .endpointRepairRequested(let requests):
                self.recordFeedRepair("endpoint", phase: .requested, reason: "keyframeUnanswered")
                ControlLiveLog.line("recovery: action=endpoint effect=requested reason=keyframeUnanswered requests=\(requests)")
            case .restored:
                ControlLiveLog.line("feed: endpoint recovery has fresh picture")
            case .holdForWatchdog(let cycles):
                ControlLiveLog.line("feed: endpoint recovery picture deadline expired")
                ControlLiveLog.line("feed: keep BLE, video still arriving; watchdog owns the stall cycle=\(cycles)")
                self.recordFeedRepair("session", phase: .blocked, reason: "videoLive")
                guard scope.isCurrent else { return }
                self.feedWatchdog = FeedWatchdog()
            case .escalateSession:
                ControlLiveLog.line("feed: endpoint recovery picture deadline expired")
                self.beginSessionRecovery(reason: "endpoint recovery has no fresh picture", trigger: .datalinkLost)
            case .negotiationFailed(let reason):
                ControlLiveLog.line("feed: endpoint negotiation failed (\(reason))")
                self.beginSessionRecovery(reason: "endpoint negotiation failed", trigger: .datalinkLost)
            }
        })
    }

    private func performLiveViewNative(_ effect: DjiAppleLiveViewNativeEffect,
        scope: DjiAppleLiveViewScope) {
        guard scope.isCurrent else { return }
        switch effect {
        case .prepareRecover:
            recordFeedRepair("enable", phase: .requested)
            ControlLiveLog.line("recovery: action=enable effect=requested")
            gimbal.endStick(cancelMove: true, ifCurrent: { scope.isCurrent })
        case .prepareMediaReturn:
            status.meteredEv = nil
        case .exitPlayback:
            sendExitPlayback()
        case .holdPicture(let always):
            if always { decoder.beginIDRHold() } else { beginIDRHoldIfNeeded() }
        case .requestFinished(let purpose, let reason, let outcome):
            switch outcome {
            case .blocked(.uncaptured):
                log.info("live: skip 0x09/0xa8 \u{2014} \(self.connectedCamera?.model.name ?? "camera", privacy: .public) has no captured enable (\(reason, privacy: .public))")
                if controlNote == nil { controlNote = "Live view for this camera is not captured yet." }
                guard scope.isCurrent else { return }
            case .blocked(.overlap):
                log.info("live: skip overlapping 0x09/0xa8 (\(reason, privacy: .public))")
            default: break
            }
            guard scope.isCurrent else { return }
            switch purpose {
            case .recover:
                switch outcome {
                case .locallyAccepted(let history):
                    log.info("live: recover 0x09/0xa8 (\(reason, privacy: .public), VT ready, hold IDR) #\(history.locallyAcceptedEnables, privacy: .public)")
                    ControlLiveLog.line("feed: recover 0x09/0xa8 reason=\(reason) #\(history.locallyAcceptedEnables)")
                    recordFeedRepair("enable", phase: .locallySent)
                    ControlLiveLog.line("recovery: action=enable effect=sent")
                case .blocked(let block):
                    let detail: String
                    switch block {
                    case .mediaBrowsing: detail = "mediaBrowsing"
                    case .playback:
                        detail = "playback"
                        ControlLiveLog.line("feed: hold enable \u{2014} camera still in playback (\(reason))")
                    case .pathNotReady, .presentationNotReady:
                        let pathReady = block == .presentationNotReady
                        let decoderReady = self.decoder.isPresentationReady
                        guard scope.isCurrent else { return }
                        log.info("feed: hold enable path=\(pathReady ? 1 : 0) decoder=\(decoderReady ? 1 : 0) reason=\(reason, privacy: .public)")
                        detail = pathReady ? "decoderNotReady" : "pathNotReady"
                    case .cooldown: detail = "cooldown"
                    default: detail = "enableGate"
                    }
                    recordFeedRepair("enable", phase: .blocked, reason: detail)
                case .superseded: break
                }
            case .initial(let pathProven, let displayAttached):
                if case .locallyAccepted(let history) = outcome {
                    if pathProven || displayAttached {
                        log.info("live: sent 0x09/0xa8 once (path ready, display attached) #\(history.locallyAcceptedEnables, privacy: .public)")
                    } else {
                        log.info("live: sent 0x09/0xa8 once after display wait (attached=\(displayAttached)) #\(history.locallyAcceptedEnables, privacy: .public)")
                    }
                } else if outcome == .blocked(.alreadyAccepted) || outcome == .blocked(.pathNotReady) {
                    let pathReady = pathProven || self.cameraPathReady()
                    guard scope.isCurrent else { return }
                    log.info("live: skipped enable pathReady=\(pathReady) attached=\(displayAttached) sent=\(self.liveViewHistory.initialAccepted)")
                }
            default: break
            }
        }
    }

    private func prepareForDatalinkRecovery(ifCurrent: () -> Bool = { true }) -> Date {
        // The held picture may return before this endpoint's first exposure report.
        guard ifCurrent() else { return Date() }
        status.meteredEv = nil
        guard ifCurrent() else { return Date() }
        // The new handshake restarts DUML sequence numbering. Old retries,
        // pending sliders, and GET continuations belong to the retired session.
        controlSeam?.linkDidChange()
        guard ifCurrent() else { return Date() }
        commandTimeoutsAt.removeAll()
        cameraSettings.retire()
        tapFocus.retire()
        subjectTracking.stopPolling()
        guard ifCurrent() else { return Date() }
        controlExchange.retire(CancellationError(), notifySets: true)
        guard ifCurrent() else { return Date() }
        decoder.flushForRecovery()
        guard ifCurrent() else { return Date() }
        firstPictureFormat.reset()
        guard ifCurrent() else { return Date() }
        firstPictureSettled = false
        audioRefreshPending = true
        glamourClearPending = true
        focusTrackPending = true
        return Date()
    }

    func isLivePictureRepairCurrent(_ generation: Int) -> Bool {
        MediaLiveResume.isCurrentPictureOwner(
            generation: generation, currentGeneration: cameraMedia.resumeID,
            browsing: isBrowsingMedia)
    }

    /// Changing presentation intent does not cancel a negotiated endpoint's I/O.
    /// Its old picture deadline yields by generation, then media return claims
    /// this same serialized repair slot with a new probe and one enable.
    func retireLivePictureRecoveryForMedia() {
        feedWatchdog = FeedWatchdog()
    }

    var hasFeedRecoveryInFlight: Bool {
        pictureRecovery.isBusy || datalink?.isRebuilding == true
    }

    func claimMediaLiveRecovery(
        token: Int, work: @escaping @MainActor () async -> Void
    ) async {
        await pictureRecovery.claim(pictureIntent: token) { _ in await work() }
    }

    @discardableResult
    func startFeedRecovery(
        _ work: @escaping @MainActor (DjiApplePictureRecovery.Attempt) async -> Void
    ) -> Bool {
        pictureRecovery.start(work)
    }

    // MARK: - Session recovery (camera power cycle)

    private func makeRecoveryEpisode() -> DjiAppleRecoveryEpisode {
        let timing: DjiAppleRecoveryTiming
        #if DEBUG
            if let peers = sessionRecoveryNativePeers {
                timing = .init(monotonicNow: peers.now, uptime: peers.uptime,
                    wallNow: { peers.wallNow().timeIntervalSinceReferenceDate },
                    sleep: peers.sleep, jitter: peers.jitter)
            } else { timing = .continuous }
        #else
            timing = .continuous
        #endif
        return DjiAppleRecoveryEpisode(connectionRun: connectionRun,
            discovery: .init(waitUntilPoweredOn: { [weak self] in
                guard let self else { return false }
                #if DEBUG
                    if let peers = self.sessionRecoveryNativePeers { return await peers.waitUntilPoweredOn() }
                #endif
                return await self.ble.waitUntilPoweredOn()
            }, scan: { [weak self] in
                guard let self else { return AsyncStream { $0.finish() } }
                let cameras: AsyncStream<DjiAppleSighting>
                #if DEBUG
                    if let peers = self.sessionRecoveryNativePeers { cameras = peers.scan() }
                    else { cameras = self.ble.scan() }
                #else
                    cameras = self.ble.scan()
                #endif
                return AsyncStream { continuation in
                    let task = Task { @MainActor in
                        for await camera in cameras {
                            guard !Task.isCancelled else { break }
                            continuation.yield(self.recoverySighting(camera))
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }, stopScan: { [weak self] in
                guard let self else { return }
                #if DEBUG
                    if let peers = self.sessionRecoveryNativePeers { peers.stopScan(); return }
                #endif
                self.ble.stopScan()
            }, enrich: { [weak self] sighting in
                guard let self, let camera = self.connectionCamera(sighting) else { return sighting }
                return self.recoverySighting(camera.enriched(from: self.saved(camera.id)))
            }), native: .init(observe: { [weak self] in
                guard let self else { return .init() }
                var source = self.decoder.lastSourceFrameAt
                var presented = self.decoder.monitorPresentedAt
                #if DEBUG
                    if let peers = self.sessionRecoveryNativePeers {
                        let picture = peers.picture(); source = picture.sourceAt; presented = picture.presentedAt
                    }
                #endif
                return .init(ownsConnection: !self.isMultiviewBorrowed,
                    stage: Self.recoveryStage(self.phase), sourceAt: source?.timeIntervalSinceReferenceDate,
                    presentedAt: presented?.timeIntervalSinceReferenceDate)
            }, cleanup: { [weak self] kind, attempt in
                self?.cleanupRecoveryNative(kind, attempt: attempt)
            }, scanning: { [weak self] attempt in
                guard let self, attempt.isCurrent else { return }
                self.phase = .scanning
                guard attempt.isCurrent else { return }
                ControlLiveLog.line("session: recovery scanning for saved camera")
            }, prepare: { [weak self] sighting, attempt in
                guard let self, attempt.isCurrent, let camera = self.connectionCamera(sighting) else { return nil }
                return self.prepareConnectionNative(camera, preserveMonitor: true, recoveryAttempt: attempt)
            }), timing: timing, changed: { [weak self] value, id in
                self?.publishRecovery(value, episodeID: id)
            })
    }

    private func recoverySighting(_ camera: DjiAppleSighting) -> DJISighting {
        .init(id: camera.id.uuidString, name: camera.name, model: camera.model, modelId: camera.modelId)
    }

    private static func recoveryStage(_ phase: ConnectionPhase) -> DjiAppleRecoveryEpisode.Stage {
        switch phase {
        case .joiningWifi: .joiningWiFi
        case .openingDatalink: .openingDatalink
        case .live: .live
        default: .other
        }
    }

    private func cleanupRecoveryNative(_ kind: DjiAppleRecoveryEpisode.Cleanup,
        attempt: DjiAppleRecoveryEpisode.Attempt) {
        guard attempt.isCurrent, !isMultiviewBorrowed else { return }
        if case .initialDrop = kind {
            AppDiagnostics.incidents.noteUnexpectedDisconnect(now: ProcessInfo.processInfo.systemUptime)
            guard attempt.isCurrent else { return }
            recordFeedRepair("session", phase: .requested, reason: String(describing: attempt.trigger))
            guard attempt.isCurrent else { return }
            let preserveSoftAP = cameraPathReady()
            guard attempt.isCurrent else { return }
            abortInFlightRun(preserveDecoder: true, preserveSoftAP: preserveSoftAP, recoveryAttempt: attempt)
            guard attempt.isCurrent else { return }
            pictureRecovery.cancel()
            guard attempt.isCurrent else { return }
            feedRecovering = false
            guard attempt.isCurrent else { return }
            ControlLiveLog.line("session: drop (\(attempt.reason)) → bounded recovery")
        } else {
            if case .failedAttempt = kind {
                if case .retrying(let count, _) = sessionRecovery {
                    ControlLiveLog.line("session: recovery attempt failed attempt=\(count) phase=\(phase)")
                }
            }
            abortInFlightRun(preserveDecoder: true, recoveryAttempt: attempt)
        }
    }

    /// Install the complete snapshot before any observable notification. If a callback
    /// cancels A and admits B, every remaining A notification/presentation action retires.
    private func publishRecovery(_ value: DjiAppleRecoveryEpisode.Snapshot, episodeID: UUID?) {
        let isCurrent = {
            self.recoveryEpisode.currentEpisodeID == episodeID && self.recoveryEpisode.snapshot == value
                && self.recoverySnapshotStorage == value
        }
        guard recoveryEpisode.currentEpisodeID == episodeID, recoveryEpisode.snapshot == value else { return }
        let previous = recoverySnapshotStorage
        let previousName = recoveryDeviceNameStorage
        recoverySnapshotStorage = value
        if value.holdsPicture, recoveryDeviceNameStorage.isEmpty, let target = value.targetID,
            let id = UUID(uuidString: target) {
            let name = connectedCamera?.name ?? saved(id)?.displayName ?? ""
            guard isCurrent() else { return }
            recoveryDeviceNameStorage = name
        } else if value.targetID == nil { recoveryDeviceNameStorage = "" }
        guard isCurrent() else { return }
        if previous.state != value.state { withMutation(keyPath: \.sessionRecovery) {} }
        guard isCurrent() else { return }
        if previous.holdsPicture != value.holdsPicture { withMutation(keyPath: \.holdsMonitor) {} }
        guard isCurrent() else { return }
        if previous.cardGraceElapsed != value.cardGraceElapsed { withMutation(keyPath: \.sessionRecoveryCardGraceElapsed) {} }
        guard isCurrent() else { return }
        if previous.reconnecting != value.reconnecting { withMutation(keyPath: \.isReconnecting) {} }
        guard isCurrent() else { return }
        if previousName != recoveryDeviceNameStorage { withMutation(keyPath: \.recoveryDeviceName) {} }
        guard isCurrent() else { return }
        if previous.state != value.state {
            switch value.state {
            case .idle:
                if case .retrying(let count, _) = previous.state, !value.holdsPicture {
                    ControlLiveLog.line("session: recovered after \(count - 1) failed attempt(s)")
                }
            case .waitingForOperator(let count):
                ControlLiveLog.line("session: recovery exhausted after \(count) attempts")
            case .pausedAfterRepeatedDrops(let drops):
                log.info("session: storm pause after \(drops) drops")
            case .retrying: break
            }
        }
        if previous.state != value.state,
            episodeID != nil || (!value.holdsPicture && value.targetID != nil) {
            applyLinkPresentation(ifCurrent: isCurrent)
        }
    }

    func beginSessionRecovery(reason: String, trigger: SessionRecoveryTrigger = .bleDropped) {
        let target = connectedCamera?.id.uuidString ?? recoverySnapshotStorage.targetID ?? reconnectTarget?.uuidString
        recoveryEpisode.begin(targetID: target, trigger: trigger, reason: reason)
    }

    func retrySessionRecovery() { recoveryEpisode.retry() }

    func cancelSessionRecovery(clearHoldsMonitor: Bool = true) {
        recoveryEpisode.cancel(clearHold: clearHoldsMonitor)
    }

    static func recoveryDeadline(for phase: ConnectionPhase) -> Duration {
        DjiAppleRecoveryEpisode.deadline(for: recoveryStage(phase))
    }

    func hasFreshRecoveryPicture(since started: Date, now: Date = Date()) -> Bool {
        SessionRecoveryPolicy.hasFreshPicture(
            attemptStartedAt: started.timeIntervalSinceReferenceDate,
            now: now.timeIntervalSinceReferenceDate,
            lastSourceFrameAt: decoder.lastSourceFrameAt?.timeIntervalSinceReferenceDate,
            lastPresentedAt: decoder.monitorPresentedAt?.timeIntervalSinceReferenceDate)
    }

    private func waitForRecoveryPicture(
        since started: Date, timeout: Duration, pictureOwner: Int
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !Task.isCancelled, clock.now < deadline, isLivePictureRepairCurrent(pictureOwner) {
            if hasFreshRecoveryPicture(since: started) { return true }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
        }
        return false
    }
    /// Stage 4: new UDP handshake + register + subscribe on SoftAP. BLE and
    /// `phase == .live` stay so the operator is not dumped to a black home screen.
    private func rejoinDatalinkKeepingLive(attempt: DjiApplePictureRecovery.Attempt) async {
        guard attempt.isCurrent, let camera = connectedCamera else { return }
        let pictureOwner = cameraMedia.resumeID
        log.info("feed: full datalink rejoin (SoftAP bind kept)")
        disposeDatalink(ifCurrent: { attempt.isCurrent })
        guard attempt.isCurrent,
            let started = attempt.prepareReplacementEndpoint() else { return }
        var attemptedDatalink: DjiAppleDatalink?
        do {
            try Task.checkCancellation()
            guard attempt.isCurrent else { return }
            // Station drivers check the hotspot path themselves in open().
            if connectionSetup == .cameraWiFi {
                try await DjiAppleWiFiJoiner.waitUntilCameraPathReady(timeout: 8, host: .pocket)
            }
            try Task.checkCancellation()
            guard attempt.isCurrent else { return }
            let dl = makeDatalink(camera)
            guard attempt.isCurrent else { dl.close(); return }
            wireDatalink(dl)
            guard attempt.isCurrent else { dl.close(); return }
            datalink = dl
            attemptedDatalink = dl
            guard attempt.bindReplacementLiveView(dl, recovery: .init(datalink: dl)) else { return }
            decoder.beginIDRHold()
            try await dl.open { [self] in
                guard attempt.isCurrent, shouldCommitLiveHandshake(dl) else { return }
                guard isLivePictureRepairCurrent(pictureOwner) else { return }
                sendInitialLiveViewEnable(
                    displayAttached: decoder.isDisplayReady, pathProven: true)
            }
            guard attempt.isCurrent, shouldCommitLiveHandshake(dl) else { return }
            // New session: the old stall ladder is over. First picture owns
            // the new driver until a rolling picture; then a fresh watchdog.
            feedWatchdog = FeedWatchdog()
            startKeepalive(ssid: joinedSSID)
            _ = await attempt.waitForPicture(.init(datalink: dl),
                since: started, pictureIntent: pictureOwner,
                timeout: .seconds(2 * CameraSoftAP.foregroundPictureGrace))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, attemptedDatalink == nil || datalink === attemptedDatalink
            else { return }
            log.info("feed: full rejoin failed (\(error.localizedDescription, privacy: .public))")
            ControlLiveLog.line("feed: full rejoin failed (\(error.localizedDescription))")
            disposeDatalink()
            // A nil datalink under a live phase has no repair owner: the
            // watchdog cannot enable or rebind, so Reconnecting stayed up
            // until force-quit. Bounded session recovery (warm rehandshake,
            // then BLE reconnect) owns it from here, last frame held.
            beginSessionRecovery(reason: "datalink rejoin failed", trigger: .datalinkLost)
        }
    }

    /// Drop the live UDP session so the next connect cannot inherit a half-closed driver.
    private func disposeDatalink(ifCurrent: () -> Bool = { true }) {
        status.meteredEv = nil
        guard ifCurrent() else { return }
        let link = datalink
        defer {
            if let link {
                link.onAccessUnit = nil
                link.onVideoDiscontinuity = nil
                link.onStatusFrame = nil
                link.close()
            }
        }
        datalink = nil
        guard ifCurrent() else { return }
        #if DEBUG
            sessionRecoveryNativePeers?.disposeEndpoint()
            guard ifCurrent() else { return }
        #endif
    }

    private func shouldCommitLiveHandshake(_ dl: DjiAppleDatalink) -> Bool {
        let ok = CameraSoftAP.shouldCommitLiveHandshake(
            driverOwned: datalink === dl,
            isClosed: dl.isClosed,
            isCancelled: Task.isCancelled)
        if !ok {
            log.info("live: ignore stale datalink open")
        }
        return ok
    }

    private func wireDatalink(_ dl: DjiAppleDatalink) {
        incidentSocketGeneration += 1
        AppDiagnostics.incidents.noteSocketGeneration(incidentSocketGeneration)
        dl.onVideoDiscontinuity = { [weak self, weak dl] in
            guard let self, let dl, self.datalink === dl else { return }
            self.decoder.noteCompressedDiscontinuity()
        }
        // Admission was captured by the raw UDP callback before this actor queue.
        dl.onMediaFrame = { [weak self, weak dl] frame, admission in
            guard let self, let dl, self.datalink === dl, let admission else { return }
            _ = self.cameraMedia.mediaService?.ingest(frame, admission: admission)
        }
        cameraMedia.mediaService?.attachIngress(dl.mediaIngress)
        dl.onStatusFrame = { [weak self, weak dl] frame in
            guard let self, let dl, self.datalink === dl else { return }
            self.applyIncomingStatus(frame)
        }
        dl.onAccessUnit = { [weak self, weak dl] accessUnit in
            guard let self, let dl, self.datalink === dl else { return }
            self.ingestAccessUnit(accessUnit)
        }
    }

    /// Android parity: offer every datalink frame to the opcode waiter.
    /// Restricting to flags == 0xC0 dropped 0x80 / same-opcode ACKs.
    func applyIncomingStatus(_ frame: Duml.Frame) {
        route(frame)
        if frame.cmdSet == 0x00, frame.cmdId == 0x27 {
            return
        }
        if !isMultiviewControlsOnly, frame.cmdSet == 0x02, frame.cmdId == 0x89 {
            subjectTracking.receiveLivePush(frame.payload)
        }
        _ = CameraStatusDecoder.apply(
            frame, to: &cameraReportedCapture, model: connectedCamera?.model)
        controlSeam?.sessionDidChange()
        var s = status
        let applied = CameraStatusDecoder.apply(frame, to: &s, model: connectedCamera?.model)
        // Decode only reported fields while a control is settling. The merged
        // snapshot already contains optimistic values and cannot confirm a SET.
        var reported = CameraStatus()
        if editorReconciliation.needsSparseReport
        {
            _ = CameraStatusDecoder.apply(frame, to: &reported, model: connectedCamera?.model)
        }
        let flipReply = CameraParam.isSelfieFlipGetReply(
            set: frame.cmdSet, cmd: frame.cmdId, payload: frame.payload)
        if flipReply, let parsed = CameraParam.parseGetReply(frame.payload) {
            lastSelfieFlipReplyAt = Date()
            s.selfieFlip = SelfieFlip(rawValue: parsed.value)
        }
        guard applied || flipReply else { return }
        let editor = editorReconciliation.project(incoming: s, reported: reported,
            committed: status, origin: .subscription)
        guard editorReconciliation.admits(editor.authority) else { return }
        if editor.formatExpired { controlNote = "Frame rate unconfirmed; choose the shutter angle again" }
        guard editorReconciliation.admits(editor.authority) else { return }
        s = editor.status
        let angle = editor.rematchAngle
        if isMultiviewControlsOnly {
            if status != s { status = s }
            guard editorReconciliation.admits(editor.authority) else { return }
            rematchShutterAngle(angle)
            settleLateFromSubscribe()
            return
        }
        gimbal.ingest(frame, status: s)
        absorbCameraFocus(s)
        noteExpoIfChanged(s)
        noteZoomIfChanged(s)
        // Scope clip ceiling follows the camera's EI; feeding it here keeps the
        // scope view bodies free of session-status reads (5 Hz re-render trap).
        // The actual live lease stays separate from a covered clip's display projection.
        // Presentation pins cannot calibrate the source.
        decoder.refreshSourceCalibration()
        let flipChanged = s.selfieFlip != status.selfieFlip
        gimbal.settle(frame, status: s)
        guard editorReconciliation.admits(editor.authority) else { return }
        status = s
        guard editorReconciliation.admits(editor.authority) else { return }
        rematchShutterAngle(angle)
        zoomGesture.confirmIfReady()
        if flipReply || flipChanged {
            if flipChanged {
                ControlLiveLog.line(
                    "control: Selfie Flip \(s.selfieFlip?.label ?? "nil") extra-mirror=\(gimbal.stickMapping.commanded180 && !(s.selfieFlip?.isOn ?? false) ? 1 : 0)"
                )
                decoder.invalidatePictureFlipPresentation()
            }
            gimbal.syncPose()
        }
        settleLateFromSubscribe()
    }

    private func resetGimbalPoseForNewStream() {
        gimbal.resetPose()
        lastSelfieFlipReplyAt = nil
        decoder.invalidatePictureFlipPresentation()
        decoder.poseViewFlip = false
        gimbal.syncPose()
    }

    var hasMediaDatalink: Bool { datalink != nil }

    func sendMediaFrame(_ frame: Duml.Frame) {
        _ = datalink?.send(frame)
    }

    func rejoinSoftAPAfterInternetHop() async {
        guard connectionSetup == .cameraWiFi, let ssid = cachedSSID ?? joinedSSID,
            let pass = cachedPassword
        else { return }
        let wpa3 = connectedCamera?.model.wpa3 ?? true
        try? await DjiAppleWiFiJoiner.join(ssid: ssid, passphrase: pass, wpa3: wpa3, host: .pocket)
        try? await DjiAppleWiFiJoiner.waitUntilCameraPathReady(timeout: 20, host: .pocket)
    }

    func sendEnterPlayback() { datalink?.enterPlayback() }
    func sendExitPlayback() { datalink?.exitPlayback() }

    func awaitMediaOpcode(
        _ set: UInt8, _ cmd: UInt8, timeout: Duration, send: (() -> Void)?
    ) async throws -> Duml.Frame {
        try await waitFrame(set, cmd, timeout: timeout, consumeHold: false, send: send)
    }

    @discardableResult
    func restartLiveViewAfterMedia() -> Bool {
        locallyAccepted(pictureRecovery.requestLiveView(.mediaReturn, reason: "media browse ended"))
    }

    func resetMediaSession() { resetMediaSession(ifCurrent: { true }) }

    private func resetMediaSession(ifCurrent: () -> Bool) {
        guard ifCurrent() else { return }
        cameraMedia.resetSession()
        guard ifCurrent() else { return }
        mediaLibraryOwner?.bind(nil)
        guard ifCurrent() else { return }
        mediaLibraryOwner?.close()
        guard ifCurrent() else { return }
        mediaOperationNote = nil
        guard ifCurrent() else { return }
        mediaLibraryOwner?.visibility = .cachedOnly
    }

    func clearMediaCache() async throws {
        let library = mediaLibrary
        cameraMedia.resetSession()
        library.bind(nil)
        let token = library.actionToken
        try await cameraMedia.clearCache(cameraID: mediaCameraID, preservingCatalog: true)
        guard library.isCurrent(token), !Task.isCancelled else { return }
        mediaIOCacheRevision &+= 1
        library.refreshLocalCache()
    }

    private func settleLateFromSubscribe() {
        controlExchange.settleFromReport()
    }

    private func ingestAccessUnit(_ accessUnit: [UInt8]) {
        guard
            CameraSoftAP.shouldIngestLiveVideo(
                ingestArmed: true,
                browsingMedia: isBrowsingMedia,
                operatorOverlayHeld: false)
        else { return }
        rawAccessUnits += 1
        if decoder.decode(accessUnit: accessUnit) { rawFramesEnqueued += 1 }
    }

    private func publishStatusNow() {
        lastStatusMutation = CFAbsoluteTimeGetCurrent()
        statusFlushTask?.cancel()
        statusFlushTask = nil
        withMutation(keyPath: \.status) {}
        onChromePublished?()
    }

    private func scheduleStatusFlush() {
        guard statusFlushTask == nil else { return }
        statusFlushTask = Task { @MainActor in
            let remaining =
                LiveChromeThrottle.statusInterval
                - (CFAbsoluteTimeGetCurrent() - lastStatusMutation)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            statusFlushTask = nil
            withMutation(keyPath: \.status) {}
            lastStatusMutation = CFAbsoluteTimeGetCurrent()
            onChromePublished?()
        }
    }

    // ---- helpers ---------------------------------------------------------------------------------

    private struct KnownWifi {
        var ssid: String?
        var password: String?
        var source: String
        var skipBle: Bool
    }

    /// Memory (this launch) or Keychain (camera id / advertised name / last SSID).
    /// A live BLE name that differs from the cached SSID is a renamed SoftAP —
    /// join that name with the cached password (GetSSID after Mimo is often 0xE4).
    private func resolvedWifiCreds(for camera: DjiAppleSighting) -> KnownWifi {
        #if DEBUG
            if let trace = connectionNativePeers {
                return KnownWifi(ssid: trace.ssid, password: trace.password,
                    source: trace.password == nil ? "none" : "SIMULATED", skipBle: trace.password != nil)
            }
        #endif
        let saved = saved(camera.id)
        let advertised =
            CameraWifiResolution.liveAdvertisedSSID(camera.name)
            ?? CameraWifiResolution.liveAdvertisedSSID(saved?.advertisedName)
            ?? (camera.name.isEmpty ? saved?.advertisedName : camera.name)
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
            keychainPassword: keychain?.password,
            advertisedName: advertised
        )
        if let used = resolved.ssid,
            let live = CameraWifiResolution.liveAdvertisedSSID(advertised),
            used == live
        {
            let cached = [memory?.ssid, keychain?.ssid, saved?.lastSSID]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let cached, cached != used {
                ControlLiveLog.line("creds: live BLE name \(used) replaces cached SSID \(cached)")
            }
        }
        if let ssid = resolved.ssid, ssidBelongsToAnotherBody(ssid, camera: camera) {
            log.info(
                "creds: dropping \(resolved.source, privacy: .public) SSID \(ssid, privacy: .public) — other body"
            )
            return KnownWifi(ssid: nil, password: nil, source: "none", skipBle: false)
        }
        return KnownWifi(
            ssid: resolved.ssid,
            password: resolved.password,
            source: resolved.source,
            skipBle: resolved.skipBle
        )
    }

    private func ssidBelongsToAnotherBody(_ ssid: String, camera: DjiAppleSighting) -> Bool {
        if CameraWifiResolution.isSSIDOwnedByAnotherCamera(
            ssid, cameraId: camera.id.uuidString, saved: savedCameras())
        {
            return true
        }
        return CameraBodyFamily.ssidConflictsWithBody(
            ssid: ssid, modelId: camera.modelId, advertisedName: camera.name)
    }

    private func assertSSIDBelongs(to camera: DjiAppleSighting, ssid: String) throws {
        if ssidBelongsToAnotherBody(ssid, camera: camera) {
            log.info(
                "creds: SSID \(ssid, privacy: .public) does not belong to \(camera.model.name, privacy: .public)"
            )
            throw Fail.wrongCamera
        }
    }

    private func persistWifiCreds(camera: DjiAppleSighting, ssid: String, password: String) {
        #if DEBUG
            if let trace = connectionNativePeers { trace.persist(ssid, password); return }
        #endif
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
        if let cached = cachedSSID { names.insert(cached) }
        for camera in savedCameras() {
            if let other = camera.lastSSID { names.insert(other) }
        }
        names.remove(ssid)
        return names.filter { !$0.isEmpty }
    }

    enum Fail: LocalizedError {
        case creds, timeout, pairingTimeout, pairingDeferred, disconnected
        case commandTimeout(String)
        case credsEmpty(String)
        case disconnectedDuring(String)
        case credsRefused(String, UInt8)
        case mimoSession
        case staleSoftAP
        case wrongCamera
        case setupNotSaved
        case hostWiFi(String)
        case stationCameraMissing(String)
        case nanoWake
        var errorDescription: String? {
            switch self {
            case .creds: "couldn't read the camera's Wi-Fi credentials"
            case .timeout: "the camera stopped responding"
            case .pairingTimeout: "pairing timed out — tap Approve on the camera if it asked"
            case .pairingDeferred: StartupConnectionCopy.pairingDeferred
            case .disconnected: "the camera disconnected"
            case .commandTimeout(let name):
                "\(name) timed out — camera didn't reply (AP still coming up?)"
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
            case .setupNotSaved:
                "this setup's password is missing on this device. Edit the setup and enter it again"
            case .hostWiFi:
                "this iPhone could not join the Wi-Fi. Check the password and that the network is in range"
            case .stationCameraMissing:
                "the camera joined the Wi-Fi, but this iPhone cannot reach it there. The router is keeping the two apart: on a Wi-Fi 7 router turn off MLO for this network (or add a camera network without it), and turn off client isolation. The Hotspot setup avoids the router"
            case .nanoWake:
                "the Nano did not confirm its Wi-Fi wake. Keep it powered on and try again"
            }
        }
    }
}

extension CameraSession: DjiAppleGimbalHost {
    var gimbalLink: (any DjiAppleGimbalLink)? { datalink }
    var isLivePhase: Bool { phase == .live }
    var cameraModel: CameraModel? { connectedCamera?.model }
    func gimbalLog(_ line: String) { ControlLiveLog.line(line) }

    func gimbalPoseDidSync(viewFlip: Bool) {
        decoder.poseViewFlip = viewFlip
        decoder.syncPictureFlip()
    }

    /// Retire manual requests and any delayed wide-angle color restoration.
    func retireZoomForProgrammedMove() -> Bool {
        controlExchange.cancelSet(CameraSetMailbox.zoomOpcodeKey)
        return zoomGesture.retireForProgrammedZoom()
    }
}
