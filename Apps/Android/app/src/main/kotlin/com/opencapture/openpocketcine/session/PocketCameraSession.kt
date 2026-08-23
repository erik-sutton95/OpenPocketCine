package com.opencapture.openpocketcine.session

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.opencapture.openpocketcine.CaptureLists
import com.opencapture.openpocketcine.EvComp
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.core.CameraSession as CameraSessionSeam
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.feed.FacePriorityExposure
import com.opencapture.openpocketcine.pairing.CameraApJoiner
import com.opencapture.openpocketcine.pairing.CameraWifiCredentialStore
import com.opencapture.openpocketcine.pairing.WifiLowLatencyLock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.math.abs

/**
 * BLE → pair → Wi-Fi creds → camera AP → datalink → live HEVC/AVC.
 * Mirrors iOS `CameraSession` recovery, feed watchdog, and operator commands.
 */
class PocketCameraSession(context: Context) : CameraSessionSeam {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val ble = BleLink(context)
    private val joiner = CameraApJoiner(context)
    val decoder = HevcDecoder().also { dec ->
        dec.onParameterSetsChanged = {
            scope.launch { sendRecoverEnable(force = true, reason = "encoder format change") }
        }
    }
    private val wifiCache = CameraWifiCredentialStore(appContext)
    private val wifiLock = WifiLowLatencyLock(appContext)

    private val _phase = MutableStateFlow(ConnectionPhase.IDLE)
    override val phase: ConnectionPhase get() = _phase.value
    val phaseFlow: StateFlow<ConnectionPhase> = _phase.asStateFlow()

    private val _failure = MutableStateFlow<String?>(null)
    val failure: StateFlow<String?> = _failure.asStateFlow()

    val found: StateFlow<List<FoundCamera>> = ble.found
    val radioOn: StateFlow<Boolean> get() = ble.radioOn
    private val _status = MutableStateFlow(CameraStatus())
    val status: StateFlow<CameraStatus> = _status.asStateFlow()

    private val _controlNote = MutableStateFlow<String?>(null)
    val controlNote: StateFlow<String?> = _controlNote.asStateFlow()
    private val _controlBusy = MutableStateFlow(false)
    val controlBusy: StateFlow<Boolean> = _controlBusy.asStateFlow()
    private val _focusPoint = MutableStateFlow(0.5f to 0.5f)
    val focusPoint: StateFlow<Pair<Float, Float>> = _focusPoint.asStateFlow()
    private var audioDspBlob: ByteArray? = null
    private var audioTail: Job? = null
    private var audioPin: AudioPin? = null
    private var gimbalStickJob: Job? = null
    @Volatile private var pendingGimbalAxes: Pair<Int, Int> =
        CameraCommands.GIMBAL_STICK_CENTER to CameraCommands.GIMBAL_STICK_CENTER

    var connectedCamera: FoundCamera? = null
        private set
    var joinedSSID: String? = null
        private set

    /** iOS `CameraSession.supportsFocusMode`. Unknown camera defaults on. */
    val supportsFocusMode: Boolean
        get() {
            val model = connectedCamera?.model ?: return true
            if (!model.supportsFocusMode) return false
            if (model.family.equals("nano", ignoreCase = true)) return false
            val n = model.name.lowercase().replace(" ", "")
            return n.isEmpty() || (!n.contains("nano") && !n.contains("atto"))
        }

    var videoPackets = 0
    var accessUnits = 0
    var framesEnqueued = 0
    var droppedIncomplete = 0
    var decoderErrors = 0
    var hasVideoFormat = false
    var nalTypes = ""
    var lastKeyframeAge = "—"

    var holdsMonitor = false
        private set
    private val _recoveryState = MutableStateFlow<SessionRecoveryUi>(SessionRecoveryUi.Idle)
    val recoveryState: StateFlow<SessionRecoveryUi> = _recoveryState.asStateFlow()

    private var rawAccessUnits = 0
    private var lastIdrRequest = 0L
    private var liveViewEnableSends = 0
    private var idrHoldEnableCount = 0
    private var firstPictureSettled = false
    private var focusTrackPending = false
    private var lastFocusTrackAt: Long? = null
    private var streamStartedAt: Long? = null
    private var lastBleNotifyAt: Long? = null
    @Volatile private var isBrowsingMedia = false
    @Volatile private var operatorOverlayHeld = false
    private var evBeforeFacePriority: EvComp? = null
    private var lastFacePriorityEVAt = 0L
    private var facePriorityAcquireAt: Long? = null
    private var needsForegroundRecover = false
    private var nextTrackingId = 1
    private var mediaListCounter = 1
    private val feedWatchdog = LiveViewEnablePolicy.State()
    private var coreWatchdog = 0L
    private val dropStorm = SessionDropStormGuard()
    private var recoveryJob: Job? = null
    private var recoveryCameraId: String? = null
    private var recoveryDeviceName = ""
    private var datalink: DatalinkDriver? = null
    private var connectJob: Job? = null
    private var keepaliveJob: Job? = null
    private var frameJob: Job? = null
    private val waiters = ConcurrentHashMap<Int, FrameWaiter>()
    private val pairingHold = ConcurrentHashMap<Int, DumlFrame>()
    private val inflight = ConcurrentHashMap<Int, InflightSend>()
    private val inflightPending = ConcurrentHashMap<Int, InflightSend>()
    private var reconnectJob: Job? = null
    private var reconnectTarget: String? = null
    private var feedRecoveryJob: Job? = null
    private var lastFirstPictureLogAt = 0L
    private var lastFirstPictureSignature = ""
    private var lastRecoverSkipAt = 0L
    private var lastRecoverSkipReason = ""
    private var formatPin: FormatPin? = null
    private var colorPin: ColorPin? = null
    private var teleColorSent = false
    private var restoreDLog2OnWide = false
    private var zoomStop = 1.0
    private var zoomStopTouched = false
    var zoomPinchPreview: Double? = null
        private set
    var zoomOptimistic: Double? = null
        private set
    private var zoomPinchAnchor = 1.0
    private var lastPinchLens: Int? = null
    private var lastPinchLogTenths: Double? = null
    private var lastZoomWireAt = 0L
    private var pendingZoomPayload: ByteArray? = null
    private var zoomFlushJob: Job? = null
    private val faceDetector = LiveFaceDetector()
    private val _faceAFArmed = MutableStateFlow(false)
    val faceAFArmed: StateFlow<Boolean> = _faceAFArmed.asStateFlow()
    private val _wantsFaceDetect = MutableStateFlow(false)
    val wantsFaceDetect: StateFlow<Boolean> = _wantsFaceDetect.asStateFlow()
    private var faceAFArmJob: Job? = null
    private var faceTickJob: Job? = null
    private var lastFaceHitAt: Long? = null
    private var lastFaceAt: Long? = null
    private val _zoomReadout = MutableStateFlow(1.0)
    val zoomReadout: StateFlow<Double> = _zoomReadout.asStateFlow()
    private val _zoomPinching = MutableStateFlow(false)
    val zoomPinching: StateFlow<Boolean> = _zoomPinching.asStateFlow()
    private var searchBox: TrackingBox? = null
    private var subjectBox: TrackingBox? = null
    private var isTracking = false
    private var trackingSawLock = false
    private var faceBox: TrackingBox? = null
    private var sceneFaces: List<TrackingBox> = emptyList()
    private var lastTapFocusAt: Long? = null
    private var lastOperatorClearAt: Long? = null
    private var lastSubjectPushAt: Long? = null
    private var lastLiveTrackingAt: Long? = null
    private var lastGimbalStickAt: Long? = null
    private var trackingPollJob: Job? = null
    private val _trackingHud = MutableStateFlow(TrackingHud())
    val trackingHud: StateFlow<TrackingHud> = _trackingHud.asStateFlow()
    private val _isReconnecting = MutableStateFlow(false)
    val isReconnecting: StateFlow<Boolean> = _isReconnecting.asStateFlow()

    init {
        ble.onLinkLost = {
            if (_phase.value == ConnectionPhase.LIVE || holdsMonitor) {
                beginSessionRecovery("BLE dropped")
            } else {
                failLink("the camera disconnected")
            }
        }
        joiner.onPathLost = {
            if (_phase.value == ConnectionPhase.LIVE || holdsMonitor) {
                beginSessionRecovery("the camera Wi-Fi disconnected")
            } else {
                failLink("the camera Wi-Fi disconnected")
            }
        }
        joiner.onReassociated = {
            Log.i(TAG, "wifi: SoftAP reassociated — rebuild UDP, keep LIVE")
            startFeedRecovery {
                withContext(Dispatchers.IO) { datalink?.rebuildUdpKeepingSession() }
                sendRecoverEnable(force = true, reason = "wifi reassociated")
            }
        }
    }

    override fun startScan() {
        startScan(reconnect = null)
    }

    fun startScan(reconnect: String?) {
        reconnectTarget = reconnect
        _isReconnecting.value = reconnect != null
        _phase.value = ConnectionPhase.SCANNING
        _failure.value = null
        ble.startScan()
        if (reconnectJob == null) {
            reconnectJob =
                scope.launch {
                    ble.found.collect { cameras ->
                        val target = reconnectTarget ?: return@collect
                        val match = cameras.firstOrNull { it.id == target } ?: return@collect
                        reconnectTarget = null
                        connect(match)
                    }
                }
        }
    }

    fun reconnect(id: String) {
        if (_phase.value == ConnectionPhase.LIVE && connectedCamera?.id == id &&
            !_recoveryState.value.isRecovering && !holdsMonitor
        ) {
            return
        }
        if (!holdsMonitor && !phaseAllowsReconnect(_phase.value)) return
        if (_phase.value == ConnectionPhase.LIVE && !holdsMonitor) leaveLiveForReconnect()
        found.value.firstOrNull { it.id == id }?.let {
            connect(it)
            return
        }
        startScan(reconnect = id)
    }

    fun connect(camera: FoundCamera) {
        if (_phase.value == ConnectionPhase.LIVE && connectedCamera?.id == camera.id &&
            !_recoveryState.value.isRecovering && !holdsMonitor
        ) {
            return
        }
        if (!holdsMonitor) {
            when (_phase.value) {
                ConnectionPhase.IDLE, ConnectionPhase.SCANNING, ConnectionPhase.FAILED -> Unit
                ConnectionPhase.LIVE -> leaveLiveForReconnect()
                else -> return
            }
        }
        reconnectTarget = null
        _isReconnecting.value = false
        connectJob?.cancel()
        if (!holdsMonitor) publishPhase(ConnectionPhase.CONNECTING_GATT)
        connectJob =
            scope.launch {
                try {
                    run(camera)
                } catch (e: Exception) {
                    if (_phase.value == ConnectionPhase.IDLE) return@launch
                    if (holdsMonitor) {
                        Log.i(TAG, "session: recovery attempt failed ${e.message}")
                        return@launch
                    }
                    if (_phase.value == ConnectionPhase.FAILED) return@launch
                    _failure.value = e.message ?: e.toString()
                    _phase.value = ConnectionPhase.FAILED
                }
            }
    }

    fun attachSurface(surface: Surface?) {
        decoder.attachSurface(surface)
    }

    override fun disconnect() {
        cancelSessionRecovery(clearHoldsMonitor = true)
        reconnectTarget = null
        _isReconnecting.value = false
        feedRecoveryJob?.cancel()
        feedRecoveryJob = null
        connectJob?.cancel()
        keepaliveJob?.cancel()
        frameJob?.cancel()
        endGimbalStick()
        failAllWaiters(IllegalStateException("the camera disconnected"))
        pairingHold.clear()
        inflight.clear()
        inflightPending.clear()
        disposeDatalink()
        ble.disconnect()
        decoder.reset()
        joiner.release()
        wifiLock.release()
        connectedCamera = null
        joinedSSID = null
        holdsMonitor = false
        isBrowsingMedia = false
        _phase.value = ConnectionPhase.IDLE
        _status.value = CameraStatus()
        _failure.value = null
        _controlNote.value = null
        _controlBusy.value = false
        formatPin = null
        colorPin = null
        teleColorSent = false
        restoreDLog2OnWide = false
        resetZoomHud()
        clearLocalTracking()
        clearFaceAF()
        _faceAFArmed.value = false
        faceAFArmJob?.cancel()
        faceAFArmJob = null
        faceTickJob?.cancel()
        faceTickJob = null
        pendingZoomPayload = null
        zoomFlushJob?.cancel()
        zoomFlushJob = null
        lastTapFocusAt = null
        _focusPoint.value = 0.5f to 0.5f
        refreshTrackingHud()
        audioTail?.cancel()
        audioTail = null
        audioPin = null
        audioDspBlob = null
        videoPackets = 0
        accessUnits = 0
        framesEnqueued = 0
        droppedIncomplete = 0
        decoderErrors = 0
        hasVideoFormat = false
        nalTypes = ""
        lastKeyframeAge = "—"
        streamStartedAt = null
        liveViewEnableSends = 0
        idrHoldEnableCount = 0
        firstPictureSettled = false
        focusTrackPending = false
        lastFocusTrackAt = null
        lastBleNotifyAt = null
        needsForegroundRecover = false
        feedWatchdog.reset()
        if (coreWatchdog != 0L && SwiftCore.isAvailable) SwiftCore.feedWatchdogReset(coreWatchdog)
        ble.startScan()
    }

    fun close() {
        disconnect()
        ble.stopScan()
        ble.close()
    }

    private suspend fun run(camera: FoundCamera) {
        if (!SwiftCore.isAvailable) error("Swift core is not loaded — run just android-core")
        connectedCamera = camera
        rawAccessUnits = 0
        lastIdrRequest = 0L
        liveViewEnableSends = 0
        idrHoldEnableCount = 0
        firstPictureSettled = false
        focusTrackPending = true
        lastFocusTrackAt = null
        streamStartedAt = null
        feedWatchdog.reset()
        if (coreWatchdog != 0L && SwiftCore.isAvailable) SwiftCore.feedWatchdogReset(coreWatchdog)
        if (!holdsMonitor) decoder.reset()
        else decoder.beginIDRHold()
        publishPhase(ConnectionPhase.CONNECTING_GATT)
        startFrameRouter()
        ble.connect(camera)

        pairingHold.clear()
        inflight.clear()
        inflightPending.clear()
        publishPhase(ConnectionPhase.PAIRING)
        ble.send(SwiftCore.command(SwiftCore.CMD_SESSION_WAKE, 0x802B))
        ble.send(SwiftCore.command(SwiftCore.CMD_SET_PAIRING_PIN, 0x8092, camera.model.pairingToken))
        publishPhase(ConnectionPhase.AWAITING_APPROVAL)
        try {
            completePairing()
        } catch (_: TimeoutCancellationException) {
            error("pairing timed out — tap Approve on the camera if it asked")
        }

        startKeepalive(joinedSSID)
        publishPhase(ConnectionPhase.READING_WIFI_CREDS)
        val skipApSettle = joiner.isProcessBound() && wifiCache.load(camera.id) != null
        if (!skipApSettle) delay(200)
        ble.send(SwiftCore.command(SwiftCore.CMD_SESSION_5310, 0x8053))
        runCatching { waitFrame(0x53, 0x10, 2_000) }
        if (!skipApSettle) delay(600)
        val (ssid, pass) = wifiCredsAfterPairing(camera)

        publishPhase(ConnectionPhase.JOINING_WIFI)
        if (!joiner.isProcessBound()) {
            val joined = joiner.join(ssid, pass, camera.model.wpa3)
            if (!joined) error("couldn't join camera Wi-Fi — tap the system Join prompt if Android asked")
        }
        joinedSSID = ssid
        wifiLock.acquire()

        publishPhase(ConnectionPhase.OPENING_DATALINK)
        openDatalinkKeepingLive(camera)
        startKeepalive(ssid)
    }

    private suspend fun wifiCredsAfterPairing(camera: FoundCamera): Pair<String, String> {
        val cached = wifiCache.load(camera.id)
        if (cached != null) {
            Log.i(TAG, "creds: skipping BLE GetSSID/GetPassword — cached SSID ${cached.first}")
            return cached
        }
        val ssid =
            readWifiString("GetSSID", 0x07, 0x07) {
                ble.send(SwiftCore.command(SwiftCore.CMD_GET_WIFI_SSID, 0x8007))
            }
        val pass =
            readWifiString("GetPassword", 0x07, 0x0E) {
                ble.send(SwiftCore.command(SwiftCore.CMD_GET_WIFI_PASSWORD, 0x800E))
            }
        wifiCache.save(camera.id, ssid, pass)
        return ssid to pass
    }

    /**
     * iOS `openDatalinkKeepingLive`: handshake then `0x09/0xa8` in the same
     * turn. SoftAP still up after a miss → retry, do not pop pairing.
     */
    private suspend fun openDatalinkKeepingLive(camera: FoundCamera) {
        val existing = datalink
        val dl =
            existing?.takeUnless { it.isClosed }
                ?: DatalinkDriver(
                    joiner,
                    camera.model.datalinkPort,
                    camera.model.tcpPoke,
                    camera.model.pairingToken,
                ).also { created ->
                    created.onStatusFrame = { frame -> ingestDatalinkFrame(frame) }
                    created.onAccessUnit = { au ->
                        if (!isBrowsingMedia && !operatorOverlayHeld) {
                            rawAccessUnits += 1
                            decoder.decode(au)
                        }
                    }
                    datalink = created
                }
        var attempt = 0
        while (true) {
            try {
                withTimeout(30_000) {
                    kotlinx.coroutines.withContext(Dispatchers.IO) {
                        dl.open(
                            afterHandshake = {
                                if (datalink !== dl || dl.isClosed) {
                                    Log.i(TAG, "live: ignore stale datalink open")
                                    return@open
                                }
                                publishPhase(ConnectionPhase.LIVE)
                                decoder.beginIDRHold()
                                sendCapturedLiveView("first picture")
                                if (holdsMonitor) {
                                    _recoveryState.value = SessionRecoveryUi.Idle
                                    holdsMonitor = false
                                }
                            },
                        )
                    }
                }
                return
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                if (LiveViewEnablePolicy.shouldKickAfterHandshakeTimeout(joiner.isProcessBound())) {
                    throw e
                }
                attempt += 1
                if (LiveViewEnablePolicy.shouldGiveUpOpenRetry(attempt)) {
                    Log.i(TAG, "session: handshake give-up after $attempt opens")
                    throw e
                }
                Log.i(TAG, "session: handshake miss #$attempt — SoftAP up, retry (no kick)")
                delay(LiveViewEnablePolicy.HANDSHAKE_RETRY_PAUSE_MS)
            }
        }
    }

    /** Stay on LIVE while recovering so the monitor (last frame) is not unmounted. */
    private fun publishPhase(next: ConnectionPhase) {
        if (holdsMonitor && _phase.value == ConnectionPhase.LIVE && next != ConnectionPhase.IDLE) return
        _phase.value = next
    }

    private fun startFrameRouter() {
        frameJob?.cancel()
        frameJob =
            scope.launch {
                ble.frames.collect { frame ->
                    lastBleNotifyAt = SystemClock.elapsedRealtime()
                    if (frame.cmdSet == 0x07 && frame.cmdId == 0x46 && frame.flags == SwiftCore.FLAG_REQUEST) {
                        ble.send(SwiftCore.command(SwiftCore.CMD_PAIR_APPROVAL_ACK, frame.seq))
                    }
                    val waiter = waiters[frame.key]
                    if (waiter != null) {
                        waiter.keys.forEach { waiters.remove(it) }
                        waiter.resume(frame)
                    } else if (shouldHold(frame)) {
                        pairingHold[frame.key] = frame
                    }
                }
            }
    }

    private suspend fun completePairing() {
        val frame = waitFrame(matching = listOf(0x0745, 0x0746), timeoutMs = 90_000)
        if (frame.cmdSet == 0x07 && frame.cmdId == 0x45 && frame.payload.size >= 2 && frame.payload[1] == 0x02.toByte()) {
            waitFrame(0x07, 0x46, 90_000)
        }
    }

    private suspend fun waitFrame(set: Int, cmd: Int, timeoutMs: Long): DumlFrame =
        waitFrame(matching = listOf(((set and 0xFF) shl 8) or (cmd and 0xFF)), timeoutMs = timeoutMs)

    private suspend fun waitFrame(matching: List<Int>, timeoutMs: Long): DumlFrame {
        for (key in matching) {
            pairingHold.remove(key)?.let { return it }
        }
        return withTimeout(timeoutMs) {
            suspendCancellableCoroutine { cont ->
                val waiter = FrameWaiter(matching.toSet(), cont)
                matching.forEach { waiters[it] = waiter }
                cont.invokeOnCancellation { matching.forEach { waiters.remove(it) } }
            }
        }
    }

    private fun failAllWaiters(error: Throwable) {
        val pending = waiters.values.distinct()
        waiters.clear()
        pending.forEach { it.resumeWithException(error) }
    }

    private fun startKeepalive(ssid: String?) {
        keepaliveJob?.cancel()
        keepaliveJob =
            scope.launch {
                while (true) {
                    ble.send(SwiftCore.command(SwiftCore.CMD_SESSION_KEEPALIVE, 0x802B))
                    val live = _phase.value == ConnectionPhase.LIVE && datalink != null
                    if (ssid != null && !holdsMonitor) {
                        withContext(Dispatchers.IO) {
                            if (!isBrowsingMedia && shouldStartUDPRebuild) {
                                datalink?.rebuildUdpKeepingSession()
                                val videoAge = datalink?.lastVideoPacketAt?.let { SystemClock.elapsedRealtime() - it }
                                val hadVideo =
                                    LiveViewEnablePolicy.hadVideo(datalink?.videoPackets ?: 0, videoAge)
                                val force = LiveViewEnablePolicy.shouldForceEnableAfterUDPRebuild(hadVideo)
                                if (liveViewEnableSends > 0) {
                                    if (force) {
                                        Log.i(TAG, "live: first-picture enable after UDP rebuild (neverGotVideo)")
                                    }
                                    sendRecoverEnable(
                                        force = force,
                                        reason =
                                            if (force) "first-picture after UDP rebuild"
                                            else "keepalive after UDP rebuild",
                                    )
                                }
                            }
                            datalink?.keepalive()
                        }
                    } else if (live && !isBrowsingMedia) {
                        withContext(Dispatchers.IO) { datalink?.keepalive() }
                    }
                    if (live && !isBrowsingMedia) {
                        publishPipelineStats()
                        recoverLiveViewIfNeeded()
                    }
                    delay(1_000)
                }
            }
    }

    /** One UDP rebuild at a time. Keepalive must not collide with first-picture. */
    private val shouldStartUDPRebuild: Boolean
        get() {
            val now = SystemClock.elapsedRealtime()
            val videoAge = datalink?.lastVideoPacketAt?.let { now - it }
            val sinceEnable = if (lastIdrRequest == 0L) null else now - lastIdrRequest
            if (LiveViewEnablePolicy.shouldHoldForGopReset(sinceEnable, videoAge)) return false
            if (FocusTrackMode.shouldHoldWatchdog(lastFocusTrackAt?.let { (now - it) / 1000.0 })) {
                return false
            }
            val videoFresh = videoAge != null && videoAge < LiveViewEnablePolicy.STALL_MS
            return LiveViewEnablePolicy.shouldKeepaliveRebuildUDP(
                flowNeedsRebuild = datalink?.needsRebuild == true,
                rebuildInFlight = datalink?.isRebuilding == true || feedRecoveryJob != null,
                sinceRebuildMs = datalink?.lastRebuildAt?.let { now - it },
                videoFresh = videoFresh,
                sawPicture = hasStableLivePicture,
            )
        }

    private val hasStableLivePicture: Boolean
        get() {
            val at = decoder.lastPresentedAt ?: return false
            return SystemClock.elapsedRealtime() - at >= LiveViewEnablePolicy.REBUILD_COOLDOWN_MS
        }

    private fun publishPipelineStats() {
        videoPackets = datalink?.videoPackets ?: 0
        accessUnits = rawAccessUnits
        framesEnqueued = decoder.framesEnqueued.get()
        droppedIncomplete = datalink?.droppedIncomplete ?: 0
        decoderErrors = decoder.decoderErrors.get()
        hasVideoFormat = decoder.hasFormat
        nalTypes = decoder.nalTypesSeen.ifEmpty { "—" }
        val keyframe = decoder.lastKeyframeAt
        lastKeyframeAge =
            if (keyframe == null) "none yet"
            else String.format("%.1fs", (System.currentTimeMillis() - keyframe) / 1000.0)
    }

    /** 0x09/0xa8 is live-start and the only PLI — 1 Hz spam resets the GOP and blacks the feed. */
    private fun recoverLiveViewIfNeeded() {
        if (isBrowsingMedia || holdsMonitor) {
            logRecoverSkip(if (isBrowsingMedia) "browsing" else "holdsMonitor")
            return
        }
        if (needsForegroundRecover) {
            logRecoverSkip("foreground")
            return
        }
        if (!joiner.isProcessBound()) {
            logRecoverSkip("unbound")
            return
        }
        if (feedRecoveryJob != null) {
            logRecoverSkip("recoveryJob")
            return
        }
        if (com.opencapture.openpocketcine.media.MediaLiveResume.strayPlaybackAction(
                browsing = isBrowsingMedia,
                inPlayback = _status.value.inPlayback,
            ) != null
        ) {
            datalink?.exitPlayback()
            Log.i(TAG, "media: stray playback — sent exit")
            val hasPicture = decoder.lastPresentedAt != null
            if (!LiveViewEnablePolicy.shouldContinueFirstPictureAfterStrayPlayback(hasPicture)) {
                return
            }
        }
        val packets = datalink?.videoPackets ?: 0
        val now = SystemClock.elapsedRealtime()
        if (packets > 0 && streamStartedAt == null) streamStartedAt = now
        val presentedAge = decoder.lastPresentedAt?.let { now - it }
        if (!firstPictureSettled &&
            LiveViewEnablePolicy.shouldMarkFirstPictureSettled(
                presentedAgeMs = presentedAge,
                sinceEnableMs = if (lastIdrRequest == 0L) Long.MAX_VALUE else now - lastIdrRequest,
            )
        ) {
            firstPictureSettled = true
            if (focusTrackPending) {
                focusTrackPending = false
                refreshFocusTrack()
            }
        }
        if (LiveViewEnablePolicy.shouldRunFirstPictureRecover(
                presentedAgeMs = presentedAge,
                alreadySettled = firstPictureSettled,
            )
        ) {
            recoverFirstPictureIfNeeded(now, packets)
            return
        }
        if (decoder.awaitingIdr) {
            val videoAge = datalink?.lastVideoPacketAt?.let { now - it }
            if (LiveViewEnablePolicy.shouldRepeatRecoverEnable(
                    sinceEnableMs = if (lastIdrRequest == 0L) 0L else now - lastIdrRequest,
                    sinceRebuildMs = datalink?.lastRebuildAt?.let { now - it },
                    pathReady = true,
                    bleAgeMs = lastBleNotifyAt?.let { now - it },
                    hadVideo = LiveViewEnablePolicy.hadVideo(packets, videoAge),
                    holdEnableCount = idrHoldEnableCount,
                    videoAgeMs = videoAge,
                )
            ) {
                Log.i(TAG, "live: still holding for IDR — re-request enable")
                sendRecoverEnable(force = true, reason = "still holding for IDR")
                return
            }
        }
        applyFeedWatchdog(now, packets)
    }

    private fun recoverFirstPictureIfNeeded(now: Long, packets: Int) {
        if (datalink?.isRebuilding == true || feedRecoveryJob != null) return
        when (
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = packets,
                enableSends = liveViewEnableSends,
                sinceEnableMs = if (lastIdrRequest == 0L) 0L else now - lastIdrRequest,
                videoAgeMs = datalink?.lastVideoPacketAt?.let { now - it },
                sinceRebuildMs = datalink?.lastRebuildAt?.let { now - it },
            )
        ) {
            LiveViewEnablePolicy.FirstPictureStep.WAIT ->
                logFirstPicture(now, packets)
            LiveViewEnablePolicy.FirstPictureStep.RESEND_ENABLE -> {
                // Do not route through sendRecoverEnable — inPlayback / decoder-ready
                // holds skipped the only PLI and sat on WAITING FOR LIVE VIEW.
                sendCapturedLiveView(
                    if (liveViewEnableSends == 0) "first picture" else "first-picture resend",
                )
            }
            LiveViewEnablePolicy.FirstPictureStep.REBUILD_UDP -> {
                val videoAge = datalink?.lastVideoPacketAt?.let { now - it }
                val noPicture = decoder.lastPresentedAt == null && !decoder.hasFormat
                if (LiveViewEnablePolicy.shouldKeepUdpForLeftoverGop(
                        noPicture = noPicture,
                        videoPackets = packets,
                        videoAgeMs = videoAge,
                    )
                ) {
                    Log.i(
                        TAG,
                        "live: leftover GOP without picture pkts=$packets " +
                            "lastVideo=${videoAge}ms — resend enable, keep UDP",
                    )
                    sendCapturedLiveView("first-picture leftover GOP")
                    return
                }
                Log.i(TAG, "live: first-picture rebuild UDP (receive died pkts=$packets)")
                startFeedRecovery {
                    withContext(Dispatchers.IO) { datalink?.rebuildUdpKeepingSession() }
                    sendCapturedLiveView("first-picture after UDP rebuild")
                }
            }
            LiveViewEnablePolicy.FirstPictureStep.REJOIN -> {
                Log.i(TAG, "live: first-picture full rejoin (SoftAP bind kept)")
                startFeedRecovery { rejoinDatalinkKeepingLive() }
            }
        }
    }

    private fun applyFeedWatchdog(now: Long, packets: Int) {
        if (needsForegroundRecover) return
        val videoAgeMs = datalink?.lastVideoPacketAt?.let { now - it }
        val snap =
            LiveViewEnablePolicy.Snapshot(
                now = now,
                videoPackets = packets,
                lastVideoPacketAt = datalink?.lastVideoPacketAt,
                lastAccessUnitAt = datalink?.lastAccessUnitAt,
                lastStatusAt = datalink?.lastStatusAt,
                lastBleNotifyAt = lastBleNotifyAt,
                lastRebuildAt = datalink?.lastRebuildAt,
                lastEnableAt = lastIdrRequest,
                pathReady = joiner.isProcessBound(),
                hasFormat = decoder.hasFormat,
                decoderErrors = decoderErrors,
                live = _phase.value == ConnectionPhase.LIVE,
                sawPicture = decoder.lastPresentedAt != null,
                lastFocusTrackAt = lastFocusTrackAt,
            )
        if (coreWatchdog == 0L && SwiftCore.isAvailable) {
            coreWatchdog = SwiftCore.feedWatchdogCreate()
        }
        if (coreWatchdog != 0L) {
            val nowSec = now / 1000.0
            fun age(at: Long?): Double? {
                if (at == null || at <= 0L) return null
                return (now - at) / 1000.0
            }
            val json =
                buildString {
                    append("{")
                    append("\"now\":$nowSec")
                    append(",\"flowHealthy\":${snap.pathReady && datalink?.needsRebuild != true}")
                    append(",\"pathReady\":${snap.pathReady}")
                    append(",\"hasFormat\":${decoder.hasFormat}")
                    append(",\"decoderFailed\":${decoderErrors > 0}")
                    append(",\"live\":${_phase.value == ConnectionPhase.LIVE}")
                    append(",\"sawPicture\":${decoder.lastPresentedAt != null}")
                    append(",\"tcpPokeReady\":${datalink?.isTcpPokeReady == true}")
                    append(",\"hadVideo\":${LiveViewEnablePolicy.hadVideo(packets, videoAgeMs)}")
                    age(decoder.lastPresentedAt)?.let { append(",\"lastDecodedFrameAge\":$it") }
                    age(datalink?.lastVideoPacketAt)?.let { append(",\"lastVideoPacketAge\":$it") }
                    age(datalink?.lastAccessUnitAt)?.let { append(",\"lastAccessUnitAge\":$it") }
                    age(datalink?.lastStatusAt)?.let { append(",\"lastStatusAge\":$it") }
                    age(lastBleNotifyAt)?.let { append(",\"lastBleNotifyAge\":$it") }
                    age(datalink?.lastRebuildAt)?.let { append(",\"secondsSinceLastRebuild\":$it") }
                    age(lastIdrRequest.takeIf { it > 0L })?.let { append(",\"secondsSinceLastEnable\":$it") }
                    age(lastFocusTrackAt)?.let { append(",\"secondsSinceFocusTrackSet\":$it") }
                    append("}")
                }
            when (SwiftCore.feedWatchdogTick(coreWatchdog, json)) {
                "resendLiveViewEnable" ->
                    sendRecoverEnable(force = true, reason = "watchdog")
                "rebuildVTSession",
                "reopenDatalink",
                "fullSessionRejoin",
                ->
                    startFeedRecovery {
                        withContext(Dispatchers.IO) { datalink?.rebuildUdpKeepingSession() }
                        sendRecoverEnable(force = true, reason = "feed watchdog UDP rebuild")
                    }
                else -> logWatchdogHold(snap)
            }
            return
        }
        when (LiveViewEnablePolicy.tick(feedWatchdog, snap)) {
            LiveViewEnablePolicy.Action.NONE -> logWatchdogHold(snap)
            LiveViewEnablePolicy.Action.RESEND_ENABLE ->
                sendRecoverEnable(force = true, reason = "watchdog")
            LiveViewEnablePolicy.Action.REBUILD_UDP ->
                startFeedRecovery {
                    withContext(Dispatchers.IO) { datalink?.rebuildUdpKeepingSession() }
                    sendRecoverEnable(force = true, reason = "feed watchdog UDP rebuild")
                }
        }
    }

    private fun logRecoverSkip(reason: String) {
        val now = SystemClock.elapsedRealtime()
        if (reason == lastRecoverSkipReason && now - lastRecoverSkipAt < 3_000L) return
        lastRecoverSkipReason = reason
        lastRecoverSkipAt = now
        Log.i(
            TAG,
            "live: skip recover ($reason) pkts=${datalink?.videoPackets ?: 0} " +
                "enables=$liveViewEnableSends",
        )
    }

    private fun logFirstPicture(now: Long, packets: Int) {
        val signature = "$packets.$rawAccessUnits.${decoder.hasFormat}.$liveViewEnableSends"
        if (signature == lastFirstPictureSignature && now - lastFirstPictureLogAt < 3_000L) return
        lastFirstPictureSignature = signature
        lastFirstPictureLogAt = now
        val videoAge = datalink?.lastVideoPacketAt?.let { now - it }
        val statusAge = datalink?.lastStatusAt?.let { now - it }
        Log.i(
            TAG,
            "live: first-picture videoPkts=$packets aus=$rawAccessUnits " +
                "lastVideo=${videoAge ?: -1}ms lastStatus=${statusAge ?: -1}ms " +
                "enables=$liveViewEnableSends format=${if (decoder.hasFormat) 1 else 0} " +
                "idrHold=${if (decoder.awaitingIdr) 1 else 0} " +
                "bound=${if (joiner.isProcessBound()) 1 else 0} " +
                "fg=${if (needsForegroundRecover) 1 else 0} " +
                "hold=${if (holdsMonitor) 1 else 0}",
        )
    }

    private fun logWatchdogHold(snap: LiveViewEnablePolicy.Snapshot) {
        if (LiveViewEnablePolicy.udpReceiveAlive(snap)) return
        val sinceEnable = if (snap.lastEnableAt == 0L) null else snap.now - snap.lastEnableAt
        val videoAge = LiveViewEnablePolicy.age(snap.now, snap.lastVideoPacketAt)
        if (LiveViewEnablePolicy.shouldHoldForGopReset(sinceEnable, videoAge)) {
            Log.i(TAG, LiveViewEnablePolicy.holdUdpRebuildGopLog(sinceEnable, videoAge))
        } else if (
            FocusTrackMode.shouldHoldWatchdog(
                LiveViewEnablePolicy.age(snap.now, snap.lastFocusTrackAt)?.div(1000.0),
            )
        ) {
            Log.i(
                TAG,
                LiveViewEnablePolicy.holdUdpRebuildAfcLog(
                    LiveViewEnablePolicy.age(snap.now, snap.lastFocusTrackAt),
                    videoAge,
                ),
            )
        }
    }

    private fun sendRecoverEnable(force: Boolean, reason: String) {
        if (isBrowsingMedia) return
        if (_status.value.inPlayback) {
            datalink?.exitPlayback()
            Log.i(TAG, "feed: hold enable — camera still in playback ($reason)")
            return
        }
        val pathReady = joiner.isProcessBound()
        val decoderReady = decoder.isPresentationReady
        if (!LiveViewEnablePolicy.shouldSendRecoverEnable(pathReady, decoderReady)) {
            Log.i(TAG, "feed: hold enable path=${if (pathReady) 1 else 0} decoder=${if (decoderReady) 1 else 0} reason=$reason")
            return
        }
        if (!force && lastIdrRequest != 0L &&
            SystemClock.elapsedRealtime() - lastIdrRequest < LiveViewEnablePolicy.ESCALATE_MS
        ) {
            return
        }
        sendCapturedLiveView(reason)
    }

    private fun startFeedRecovery(work: suspend () -> Unit) {
        feedRecoveryJob?.cancel()
        feedRecoveryJob =
            scope.launch {
                try {
                    work()
                } finally {
                    feedRecoveryJob = null
                }
            }
    }

    /** iOS `CameraSession.noteSceneBecameInactive`. */
    fun noteSceneBecameInactive() {
        if (_phase.value == ConnectionPhase.LIVE) needsForegroundRecover = true
        Log.i(TAG, "live: scene inactive — will recover feed on active")
    }

    /** iOS `CameraSession.noteSceneBecameActive`. Skip while browsing media. */
    fun noteSceneBecameActive() {
        if (isBrowsingMedia) {
            needsForegroundRecover = false
            return
        }
        if (!needsForegroundRecover) return
        if (LiveViewEnablePolicy.shouldClearForegroundRecoverWithoutRebuild(holdsMonitor)) {
            needsForegroundRecover = false
            return
        }
        needsForegroundRecover = false
        if (_phase.value == ConnectionPhase.LIVE) {
            recoverAfterForeground()
            return
        }
        val id = connectedCamera?.id ?: reconnectTarget
        if (id != null) {
            Log.i(TAG, "live: scene active — session not live, reconnect")
            reconnect(id)
        }
    }

    /**
     * UDP and the present path die while suspended. Watchdog will not fire if
     * packets still arrive but the picture is frozen — that is the resume canvas.
     */
    private fun recoverAfterForeground() {
        val now = SystemClock.elapsedRealtime()
        val presentedAgeSec = decoder.lastPresentedAt?.let { (now - it) / 1000.0 }
        if (!LiveViewEnablePolicy.shouldRecoverAfterForeground(presentedAgeSec)) {
            Log.i(TAG, "live: foreground — picture still fresh, skip rebuild")
            return
        }
        Log.i(TAG, "live: recover after foreground")
        firstPictureSettled = false
        decoder.prepareAfterForeground()
        startFeedRecovery {
            withContext(Dispatchers.IO) {
                datalink?.rebuildUdpKeepingSession()
            }
            if (liveViewEnableSends > 0) {
                sendRecoverEnable(force = true, reason = "foreground")
            } else {
                sendCapturedLiveView("first picture")
            }
            delay(LiveViewEnablePolicy.FOREGROUND_PICTURE_GRACE_MS)
            val stillFrozen =
                LiveViewEnablePolicy.shouldEscalateForegroundRecover(
                    decoder.lastPresentedAt?.let { (SystemClock.elapsedRealtime() - it) / 1000.0 },
                )
            if (stillFrozen) {
                Log.i(TAG, "live: foreground still frozen — full datalink rejoin")
                rejoinDatalinkKeepingLive()
            }
        }
    }

    /** New UDP handshake on SoftAP. BLE and LIVE stay so the last frame is not dumped. */
    private suspend fun rejoinDatalinkKeepingLive() {
        val camera = connectedCamera ?: return
        Log.i(TAG, "feed: full datalink rejoin (SoftAP bind kept)")
        disposeDatalink()
        decoder.flushForRecovery()
        liveViewEnableSends = 0
        idrHoldEnableCount = 0
        firstPictureSettled = false
        focusTrackPending = true
        if (!joiner.isProcessBound()) return
        openDatalinkKeepingLive(camera)
    }

    private fun sendCapturedLiveView(reason: String): Boolean {
        if (isBrowsingMedia && reason != "media browse ended") return false
        val camera = connectedCamera
        val receiver = liveViewEnableReceiver(camera)
        // Handbook: do not send `0x02/0x0c` to start live view. Gallery leftover
        // is stray-playback's job. Unconditional exit sat on videoPkts=0.
        if (LiveViewEnablePolicy.shouldExitPlaybackBeforeLiveEnable(_status.value.inPlayback)) {
            datalink?.exitPlayback()
        }
        val nanoGate = usesNanoLiveViewGate(camera)
        if (nanoGate) datalink?.sendNanoGate(start = true)
        val prepare = LiveViewEnablePolicy.shouldSendLiveViewPrepare(nanoGate)
        if (prepare) datalink?.sendCommand(SwiftCore.CMD_TAP_FOCUS_HINT)
        datalink?.startLiveView(receiver)
        val now = SystemClock.elapsedRealtime()
        lastIdrRequest = now
        liveViewEnableSends += 1
        if (!decoder.awaitingIdr) idrHoldEnableCount = 0
        decoder.beginIDRHold()
        idrHoldEnableCount += 1
        Log.i(
            TAG,
            "live: ${if (prepare) "0x02/0x68 08 then " else ""}" +
                "0x09/0xa8 rcv=0x${receiver.toString(16)} ($reason) #$liveViewEnableSends",
        )
        return true
    }

    private fun liveViewEnableReceiver(camera: FoundCamera?): Int {
        val model = camera?.model
        if (model != null && model.liveViewEnableReceiver != 0x08) return model.liveViewEnableReceiver
        if (model?.usesNanoLiveViewGate == true || model?.family == "nano") {
            return CameraCommands.LIVE_VIEW_ENABLE_RECEIVER_NANO
        }
        if (isNanoBody(camera)) return CameraCommands.LIVE_VIEW_ENABLE_RECEIVER_NANO
        return CameraCommands.LIVE_VIEW_ENABLE_RECEIVER_POCKET
    }

    private fun usesNanoLiveViewGate(camera: FoundCamera?): Boolean =
        camera?.model?.usesNanoLiveViewGate == true || isNanoBody(camera)

    private fun isNanoBody(camera: FoundCamera?): Boolean {
        if (camera == null) return false
        if (camera.modelId == 0x19) return true
        val n = camera.model.name.lowercase().replace(" ", "")
        return n.contains("nano") || n.contains("atto")
    }

    private fun failLink(reason: String) {
        when (_phase.value) {
            ConnectionPhase.IDLE, ConnectionPhase.SCANNING -> return
            ConnectionPhase.LIVE -> {
                beginSessionRecovery(reason)
                return
            }
            else -> Unit
        }
        if (holdsMonitor) {
            beginSessionRecovery(reason)
            return
        }
        Log.i(TAG, "link lost: $reason")
        _failure.value = reason
        _phase.value = ConnectionPhase.FAILED
        connectJob?.cancel()
        stopLivePipeline(preserveDecoder = false)
        ble.disconnect()
    }

    private fun leaveLiveForReconnect() {
        stopLivePipeline(preserveDecoder = false)
        ble.disconnect()
        _failure.value = null
        _phase.value = ConnectionPhase.FAILED
    }

    /** Drop the live UDP session so the next connect cannot inherit a half-closed driver. */
    private fun disposeDatalink() {
        val link = datalink
        datalink = null
        if (link == null) return
        link.onAccessUnit = null
        link.onStatusFrame = null
        link.close()
    }

    private fun stopLivePipeline(preserveDecoder: Boolean, preserveSoftAP: Boolean = false) {
        keepaliveJob?.cancel()
        keepaliveJob = null
        endGimbalStick()
        failAllWaiters(IllegalStateException("the camera disconnected"))
        disposeDatalink()
        if (preserveDecoder) decoder.flushForRecovery() else decoder.reset()
        if (!preserveSoftAP) {
            joiner.release()
        }
        videoPackets = 0
        accessUnits = 0
        framesEnqueued = 0
        droppedIncomplete = 0
        decoderErrors = 0
        hasVideoFormat = false
        streamStartedAt = null
        liveViewEnableSends = 0
        idrHoldEnableCount = 0
        firstPictureSettled = false
        focusTrackPending = false
        lastFocusTrackAt = null
        needsForegroundRecover = false
        feedWatchdog.reset()
        if (coreWatchdog != 0L && SwiftCore.isAvailable) SwiftCore.feedWatchdogReset(coreWatchdog)
    }

    fun retrySessionRecovery() {
        dropStorm.reset()
        cancelSessionRecovery(clearHoldsMonitor = false)
        beginSessionRecovery("operator retry")
    }

    fun abandonRecoveryToMenu() {
        holdsMonitor = false
        disconnect()
    }

    private fun beginSessionRecovery(reason: String) {
        if (_recoveryState.value is SessionRecoveryUi.PausedAfterDrops) return
        if (_recoveryState.value is SessionRecoveryUi.WaitingForOperator) return
        if (recoveryJob != null) return
        val camera = connectedCamera
        val cameraId = camera?.id ?: recoveryCameraId
        if (cameraId == null) {
            Log.i(TAG, "session: drop ($reason) — no camera to recover")
            return
        }
        recoveryCameraId = cameraId
        if (recoveryDeviceName.isEmpty()) recoveryDeviceName = camera?.name.orEmpty()
        holdsMonitor = true
        connectJob?.cancel()
        stopLivePipeline(preserveDecoder = true, preserveSoftAP = joiner.isProcessBound())
        ble.disconnect()
        val now = SystemClock.elapsedRealtime()
        if (dropStorm.noteDrop(now)) {
            Log.i(TAG, "session: drop ($reason) → storm pause after ${dropStorm.dropsInWindow} drops")
            _recoveryState.value = SessionRecoveryUi.PausedAfterDrops(dropStorm.dropsInWindow)
            return
        }
        Log.i(TAG, "session: drop ($reason) → bounded recovery")
        _recoveryState.value = SessionRecoveryPolicy.monitor.state(afterFailedAttempts = 0)
        val target = camera ?: FoundCamera(cameraId, "", recoveryDeviceName, CameraModel.default, null)
        recoveryJob =
            scope.launch {
                runSessionRecovery(target)
                recoveryJob = null
            }
    }

    private fun cancelSessionRecovery(clearHoldsMonitor: Boolean) {
        recoveryJob?.cancel()
        recoveryJob = null
        _recoveryState.value = SessionRecoveryUi.Idle
        if (clearHoldsMonitor) {
            holdsMonitor = false
            recoveryCameraId = null
            recoveryDeviceName = ""
        }
    }

    private suspend fun runSessionRecovery(camera: FoundCamera) {
        val policy = SessionRecoveryPolicy.monitor
        var failures = 0
        while (true) {
            val state = policy.state(afterFailedAttempts = failures)
            _recoveryState.value = state
            if (state !is SessionRecoveryUi.Retrying) return
            val recovered = attemptRecoveryConnect(camera)
            if (recovered) {
                _recoveryState.value = SessionRecoveryUi.Idle
                holdsMonitor = false
                recoveryJob = null
                Log.i(TAG, "session: recovered after $failures failed attempt(s)")
                return
            }
            failures += 1
            when (val decision = policy.decision(afterFailedAttempts = failures, jitter = kotlin.random.Random.nextDouble())) {
                SessionRecoveryDecision.Stop -> {
                    _recoveryState.value = policy.state(afterFailedAttempts = failures)
                    Log.i(TAG, "session: recovery exhausted after $failures attempts")
                    return
                }
                is SessionRecoveryDecision.Retry -> delay(decision.afterMs)
            }
        }
    }

    private suspend fun attemptRecoveryConnect(camera: FoundCamera): Boolean {
        val id = recoveryCameraId ?: camera.id
        ble.startScan()
        val foundCamera = waitForRecoveryAdvertisement(id, RECOVERY_ATTEMPT_MS) ?: return false
        return try {
            withTimeout(RECOVERY_ATTEMPT_MS) { run(foundCamera) }
            datalink != null
        } catch (_: Exception) {
            false
        }
    }

    private suspend fun waitForRecoveryAdvertisement(id: String, timeoutMs: Long): FoundCamera? {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            found.value.firstOrNull { it.id == id }?.let { return it }
            delay(250)
        }
        return null
    }

    private fun ingestDatalinkFrame(frame: DumlFrame) {
        val waiter = waiters[frame.key]
        if (waiter != null) {
            waiter.keys.forEach { waiters.remove(it) }
            waiter.resume(frame)
        } else {
            val send = inflight[frame.key]
            if (send != null) {
                finishInflight(send, frame)
            } else if (shouldHold(frame)) {
                pairingHold[frame.key] = frame
            }
        }
        val prev = _status.value
        val json = SwiftCore.applyStatus(frame.cmdSet, frame.cmdId, frame.payload, prev.toJson())
        var next = if (json != null) CameraStatus.fromJson(json) else prev
        if (json == null || !next.hasHudFields) next = next.preservingExtras(prev)
        if (next.availableShutterDenoms.isEmpty()) {
            next = next.copy(availableShutterDenoms = prev.availableShutterDenoms)
        }
        if (next.availableIsoIndices.isEmpty()) {
            next = next.copy(availableIsoIndices = prev.availableIsoIndices)
        }
        if (next.availableColorModes.isEmpty()) {
            next = next.copy(availableColorModes = prev.availableColorModes)
        }
        next = StatusExtras.apply(frame, next)
        next = CamFov.absorb(next)
        next = absorbStaleFormat(next)
        next = absorbStaleColor(next)
        noteZoomIfChanged(prev, next)
        if (frame.cmdSet == 0x02 && frame.cmdId == 0x89) {
            applyLiveTrackingPush(frame.payload)
        }
        if (frame.cmdSet == 0x02 && frame.cmdId == 0xA5) {
            applyTrackingPoll(frame.payload)
        }
        if (lastTapFocusAt != null) refreshTrackingHud()
        if (frame.cmdSet == 0x02 && frame.cmdId == 0xA0) {
            val (updated, blob) = StatusExtras.applyAudioDsp(frame.payload, next)
            next = updated
            if (blob != null) {
                audioDspBlob = blob
                next = next.applyingAudioBlob(blob)
            }
        }
        audioPin?.let { pin ->
            val (held, nextPin) = pin.absorb(next, _status.value, SystemClock.elapsedRealtime())
            next = held
            audioPin = nextPin
        }
        if (next != prev) {
            if (next.inPlayback != prev.inPlayback) {
                Log.i(TAG, "live: inPlayback=${if (next.inPlayback) 1 else 0}")
            }
            _status.value = next
            publishFaceDetectWanted()
        }
    }

    fun pressRecord() {
        val starting = !_status.value.isRecording
        _controlBusy.value = true
        fireKind(
            if (starting) SwiftCore.CMD_RECORD_START else SwiftCore.CMD_RECORD_STOP,
            null,
            if (starting) "Record" else "Stop",
            onSettle = { _controlBusy.value = false },
        )
    }

    /** Rec lamp: still in Photo / SuperNight, else start/stop video. */
    fun pressShutter() {
        if (CameraCommands.isPhotoMode(_status.value.shootingMode)) {
            _controlBusy.value = true
            fireKind(
                SwiftCore.CMD_SHOOT_PHOTO,
                null,
                "Photo",
                retransmits = false,
                onSettle = { _controlBusy.value = false },
            )
            return
        }
        pressRecord()
    }

    fun setEv(thirds: Int) {
        val ev = EvComp.fromThirds(thirds)
        val previous = _status.value.evComp
        _status.value = _status.value.copy(evComp = ev.rawValue)
        fireKind(
            SwiftCore.CMD_SET_EV,
            "${ev.rawValue}",
            "EV",
            coalesce = true,
            onFail = {
                if (_status.value.evComp == ev.rawValue) {
                    _status.value = _status.value.copy(evComp = previous)
                }
            },
        )
    }

    /** Snapshot EV on enable; restore it (or 0.0) on disable. Matches iOS. */
    fun setFacePriorityEnabled(on: Boolean) {
        if (on) {
            evBeforeFacePriority = EvComp.fromRaw(_status.value.evComp) ?: EvComp.ZERO
            publishFaceDetectWanted()
            return
        }
        val restore =
            FacePriorityExposure.restoreWrite(
                evBeforeFacePriority,
                expoIsAuto = _status.value.expoMode == CameraCommands.EXPO_AUTO,
                current = EvComp.fromRaw(_status.value.evComp),
            )
        evBeforeFacePriority = null
        lastFacePriorityEVAt = 0L
        facePriorityAcquireAt = null
        publishFaceDetectWanted()
        if (restore != null) setEv(restore.thirds)
    }

    fun setIsoLimit(raw: Int) {
        val previous = _status.value.isoLimit
        _status.value = _status.value.copy(isoLimit = raw)
        fireKind(
            SwiftCore.CMD_SET_ISO_LIMIT,
            "$raw",
            "ISO limit",
            coalesce = true,
            onFail = {
                if (_status.value.isoLimit == raw) {
                    _status.value = _status.value.copy(isoLimit = previous)
                }
            },
        )
    }

    /** GET `0x8E` pid `0x000F`. Swift core already packs the bytes. */
    fun getIsoLimit() {
        if (_controlBusy.value) return
        scope.launch { refreshIsoLimit() }
    }

    /** GET only when Auto ISO exists. D-Log2 has no ceiling. */
    suspend fun refreshIsoLimit(): Boolean {
        if (!CameraCommands.shouldGetIsoLimit(_status.value.colorMode)) return false
        return sendKind(SwiftCore.CMD_GET_ISO_LIMIT, null, "ISO limit GET")
    }

    /** True while a feed recover rebuild is in flight — FPS chip `RECOV`, not session recovery. */
    val isFeedRecovering: Boolean
        get() = feedRecoveryJob != null

    fun setShootingMode(raw: Int) {
        val previous = _status.value.shootingMode
        _status.value = _status.value.copy(shootingMode = raw)
        fireKind(
            SwiftCore.CMD_SET_SHOOTING_MODE,
            "$raw",
            "Mode",
            onFail = {
                if (_status.value.shootingMode == raw) {
                    _status.value = _status.value.copy(shootingMode = previous)
                }
            },
        )
    }

    /** Unsnapped live / preview so 2.89× (shown 2.9×) still cycles to 3×. */
    fun zoomCycleFrom(): Double =
        zoomPinchPreview ?: zoomOptimistic ?: _status.value.zoomFactor ?: zoomStop

    fun setZoomLens(position: Int) {
        fireZoom(CameraCommands.zoomLens(position), announce = false, name = "Zoom slider")
    }

    fun setZoom(factor: Double) {
        val from = CamFov.displayLabel(_zoomReadout.value)
        val to = CamFov.displayLabel(factor)
        Log.i(TAG, "zoom: setZoom $from → $to live=${datalink != null}")
        val write = CamFov.chipWrite(factor)
        if (write == null) {
            _controlNote.value = "Zoom $to — no command"
            Log.i(TAG, "zoom: tap ignored — no write for $to")
            return
        }
        zoomPinchPreview = null
        dropDLog2ForZoom(factor)
        zoomOptimistic = factor
        markZoomStop(factor)
        val name = "Zoom $to"
        _controlNote.value = name
        when (write) {
            is CamFov.ChipWrite.Lens ->
                fireZoom(CameraCommands.zoomLens(write.position), announce = true, name = name)
            is CamFov.ChipWrite.Slew ->
                fireZoom(CameraCommands.zoomSlew(write.value), announce = true, name = name)
        }
        refreshZoomHud()
    }

    fun setZoomSlider(factor: Double) {
        val position = CamFov.pinchLens(factor)
        val tenths = CamFov.displayTenths(factor)
        if (lastPinchLogTenths != tenths) {
            lastPinchLogTenths = tenths
            Log.i(TAG, "zoom: setZoomSlider ${CamFov.displayLabel(factor)} lens=$position")
        }
        fireZoom(CameraCommands.zoomLens(position), announce = false, name = "Zoom slider")
    }

    fun setZoomSlew(value: Int) {
        fireZoom(CameraCommands.zoomSlew(value), announce = false, name = "Zoom slew")
    }

    fun setZoomStop() {
        fireZoom(CameraCommands.zoomStop(), announce = false, name = "Zoom stop")
    }

    fun updateZoomPinch(magnification: Double) {
        if (zoomPinchPreview == null) {
            zoomPinchAnchor = _status.value.zoomFactor ?: zoomOptimistic ?: zoomStop
            zoomOptimistic = null
            lastPinchLens = null
            lastPinchLogTenths = null
        }
        val factor = CamFov.pinchFactor(zoomPinchAnchor, magnification)
        val first = zoomPinchPreview == null
        // iOS `dropDLog2ForZoom` before every 0xB8. D-Log2 rejects zoom; any
        // step off 1× hops to D-Log first. Do not gate on `first` — the pinch
        // begin event is magnification 1.0, so the hop must run on later ticks.
        dropDLog2ForZoom(factor)
        zoomPinchPreview = factor
        val lens = CamFov.pinchLens(factor)
        refreshZoomHud()
        if (lastPinchLens == lens) return
        lastPinchLens = lens
        if (first && abs(factor - zoomPinchAnchor) < 0.01) return
        setZoomSlider(factor)
    }

    fun endZoomPinch() {
        flushPendingZoom()
        val preview = zoomPinchPreview
        if (preview != null) {
            markZoomStop(preview)
            restoreDLog2IfNeeded(preview)
        }
        zoomPinchPreview = null
        lastPinchLens = null
        refreshZoomHud()
    }

    fun recenterGimbal() {
        endGimbalStick()
        datalink?.sendDuml(
            cmdSet = 0x04,
            cmdId = CameraCommands.CMD_GIMBAL_MODE,
            payload = CameraCommands.gimbalRecenter(),
            receiver = CameraCommands.RX_GIMBAL,
        )
        _controlNote.value = "Gimbal re-centered"
    }

    fun flipGimbal() {
        endGimbalStick()
        datalink?.sendDuml(
            cmdSet = 0x04,
            cmdId = CameraCommands.CMD_GIMBAL_MODE,
            payload = CameraCommands.gimbalFlip(),
            receiver = CameraCommands.RX_GIMBAL,
        )
        _controlNote.value = "Gimbal flipped"
    }

    val supportsTapFocus: Boolean
        get() = connectedCamera?.model?.supportsTapFocus ?: true

    val isTrackingActive: Boolean
        get() = isTracking || searchBox != null || subjectBox != null

    val isFocusResetAvailable: Boolean
        get() {
            val point = _focusPoint.value
            return FocusResetPolicy.isAvailable(
                point.first.toDouble(),
                point.second.toDouble(),
                isTrackingActive,
            )
        }

    fun handleFeedTap(x: Float, y: Float) {
        val nx = x.coerceIn(0f, 1f).toDouble()
        val ny = y.coerceIn(0f, 1f).toDouble()
        val hud = _trackingHud.value
        val box = FaceTrackTap.boxIfTapped(hud.overlay, nx, ny, hud.dimmedFaces)
        if (box != null) {
            startTracking(box)
            return
        }
        when (LiveFeedTapPolicy.action(supportsTapFocus, tappedFace = false)) {
            LiveFeedTapPolicy.Action.TAP_FOCUS -> markFocus(x, y)
            LiveFeedTapPolicy.Action.TRACK_FACE, LiveFeedTapPolicy.Action.IGNORE -> Unit
        }
    }

    fun startTracking(x: Float, y: Float, width: Float = 0.2f, height: Float = 0.2f) {
        startTracking(TrackingBox.fromCenter(x.toDouble(), y.toDouble(), width.toDouble(), height.toDouble()))
    }

    fun startTracking(box: TrackingBox) {
        if (box.isTooSmall) {
            noteFrameTooSmall()
            return
        }
        stopTrackingPoll()
        lastOperatorClearAt = null
        lastLiveTrackingAt = null
        lastSubjectPushAt = null
        searchBox = box
        subjectBox = null
        isTracking = false
        trackingSawLock = false
        faceBox = null
        refreshTrackingHud()
        val id = nextTrackingId
        nextTrackingId = if (nextTrackingId == 0xFFFF) 1 else nextTrackingId + 1
        val extra =
            "$id\u001f${box.centerX}\u001f${box.centerY}\u001f${box.width}\u001f${box.height}"
        fireKind(
            SwiftCore.CMD_SET_TRACKING_BOX,
            extra,
            "Track",
            onSettle = { ok -> if (ok) beginTrackingPoll() },
        )
    }

    fun cancelSubjectTracking() {
        cancelTracking(sendClear = true)
    }

    fun cancelTracking() {
        cancelTracking(sendClear = true)
    }

    fun resetFocusPoint() {
        markFocus(0.5f, 0.5f)
    }

    fun applyDetectedFaces(faces: List<TrackingBox>) {
        if (!_wantsFaceDetect.value) {
            clearFaceAF()
            return
        }
        val now = SystemClock.elapsedRealtime()
        val dt = lastFaceAt?.let { (now - it) / 1000.0 } ?: 0.04
        lastFaceAt = now
        val moving = isFaceSceneMoving(now)
        sceneFaces = faces.take(SceneFacePolicy.MAX_FACES)
        if (isTrackingActive) {
            faceBox = null
            lastFaceHitAt = null
            refreshTrackingHud()
            return
        }
        if (!FaceAFPolicy.wantsFaceAF(_status.value.focusMode, _faceAFArmed.value)) {
            faceBox = null
            lastFaceHitAt = null
            refreshTrackingHud()
            return
        }
        val sinceHit = FaceTrackHold.secondsSinceHit(lastFaceHitAt, now)
        val hit =
            sceneFaces
                .filter {
                    FaceTrackHold.shouldAccept(
                        detected = it,
                        last = faceBox,
                        secondsSinceHit = sinceHit,
                        sceneMoving = moving,
                    )
                }
                .maxByOrNull { it.area }
        if (hit != null) {
            lastFaceHitAt = now
            faceBox =
                FaceTrackHold.follow(
                    faceBox,
                    hit,
                    dt.coerceIn(1.0 / 120.0, 0.08),
                    moving,
                )
        } else {
            tickFaceHold(now, moving)
        }
        refreshTrackingHud()
    }

    private fun isFaceSceneMoving(now: Long = SystemClock.elapsedRealtime()): Boolean =
        FaceTrackHold.isSceneMoving(lastGimbalStickAt?.let { (now - it) / 1000.0 })

    /** iOS `tickFaceBoxes` — drop the painted face after miss timeout. */
    private fun tickFaceHold(now: Long = SystemClock.elapsedRealtime(), moving: Boolean = isFaceSceneMoving(now)) {
        val sinceHit = FaceTrackHold.secondsSinceHit(lastFaceHitAt, now)
        if (!FaceTrackHold.shouldDrop(sinceHit, moving)) return
        if (faceBox == null && sceneFaces.isEmpty()) return
        faceBox = null
        sceneFaces = emptyList()
        lastFaceHitAt = null
        refreshTrackingHud()
    }

    /** iOS `decoder.onSourceFrame` → `considerFaceAF`. */
    fun considerFaceFrame(bitmap: android.graphics.Bitmap) {
        if (!_wantsFaceDetect.value) {
            bitmap.recycle()
            clearFaceAF()
            return
        }
        faceDetector.consider(bitmap) { hits -> applyDetectedFaces(hits) }
    }

    fun noteLiveFrame() {
        decoder.notePresented()
        armFaceAFAfterFirstPicture()
    }

    private fun armFaceAFAfterFirstPicture() {
        if (_faceAFArmed.value || faceAFArmJob != null) return
        faceAFArmJob =
            scope.launch {
                while (isActive && !_faceAFArmed.value) {
                    delay(100)
                    if (decoder.lastPresentedAt != null) {
                        _faceAFArmed.value = true
                        publishFaceDetectWanted()
                    }
                }
                faceAFArmJob = null
            }
    }

    private fun publishFaceDetectWanted() {
        val live = _status.value
        val next =
            FaceAFPolicy.wantsFaceDetect(
                focusMode = live.focusMode,
                armed = _faceAFArmed.value,
                facePriority = evBeforeFacePriority != null,
                expoAuto = live.expoMode == CameraCommands.EXPO_AUTO,
            )
        if (_wantsFaceDetect.value == next) {
            if (next) ensureFaceTick()
            return
        }
        _wantsFaceDetect.value = next
        if (!next) {
            faceTickJob?.cancel()
            faceTickJob = null
            clearFaceAF()
        } else {
            ensureFaceTick()
        }
    }

    private fun ensureFaceTick() {
        if (faceTickJob != null) return
        faceTickJob =
            scope.launch {
                while (isActive && _wantsFaceDetect.value) {
                    delay(50)
                    tickFaceHold()
                }
                faceTickJob = null
            }
    }

    private fun clearFaceAF() {
        faceBox = null
        sceneFaces = emptyList()
        lastFaceAt = null
        lastFaceHitAt = null
        refreshTrackingHud()
    }

    fun markBrowsingMedia(browsing: Boolean) {
        isBrowsingMedia = browsing
    }

    /** Drop live HEVC while Settings / Media cover the monitor so 4K playback is not fighting the decoder. */
    fun setOperatorOverlayHeld(held: Boolean) {
        operatorOverlayHeld = held
    }

    fun beginMediaBrowse() {
        isBrowsingMedia = true
        scope.launch {
            sendDumlWait(0x02, CameraCommands.CMD_PLAYBACK, CameraCommands.enterPlayback(), "Playback")
            listMedia()
        }
    }

    fun endMediaBrowse() {
        isBrowsingMedia = false
        scope.launch {
            sendDumlWait(0x02, CameraCommands.CMD_PLAYBACK, CameraCommands.exitPlayback(), "Live")
            sendCapturedLiveView("media browse ended")
        }
    }

    fun listMedia() {
        datalink?.sendDuml(0x00, CameraCommands.CMD_MEDIA_LIST, CameraCommands.mediaListTrigger())
        datalink?.sendDuml(
            0x00,
            CameraCommands.CMD_MEDIA_LIST,
            CameraCommands.mediaList(counter = mediaListCounter, cursor = 1),
        )
        mediaListCounter = (mediaListCounter + 1) and 0xFF
        if (mediaListCounter == 0) mediaListCounter = 1
    }

    fun deleteMedia(handle: Int) {
        if (_controlBusy.value) return
        scope.launch {
            sendDumlWait(
                0x00,
                CameraCommands.CMD_MEDIA_DELETE,
                CameraCommands.deleteMedia(handle, mediaListCounter),
                "Delete",
            )
        }
    }

    fun setMediaFavorite(handle: Int, favorite: Boolean) {
        if (_controlBusy.value) return
        scope.launch {
            sendDumlWait(
                0x02,
                CameraCommands.CMD_MEDIA_FAVORITE,
                CameraCommands.setMediaFavorite(handle, favorite, mediaListCounter),
                "Favorite",
            )
        }
    }

    fun setIsoIndex(index: Int) {
        val previous = _status.value.isoIndex
        _status.value = _status.value.copy(isoIndex = index)
        fireKind(
            SwiftCore.CMD_SET_ISO_INDEX,
            "$index",
            "ISO",
            coalesce = true,
            onFail = {
                if (_status.value.isoIndex == index) {
                    _status.value = _status.value.copy(isoIndex = previous)
                }
            },
        )
    }

    fun setShutterDenom(denom: Int) {
        if (_status.value.expoMode != CameraCommands.EXPO_MANUAL) {
            val previousExpo = _status.value.expoMode
            _status.value = _status.value.copy(expoMode = CameraCommands.EXPO_MANUAL)
            fireKind(
                SwiftCore.CMD_SET_EXPO_MODE,
                "manual",
                "Manual expo",
                onFail = {
                    if (_status.value.expoMode == CameraCommands.EXPO_MANUAL) {
                        _status.value = _status.value.copy(expoMode = previousExpo)
                    }
                },
            )
        }
        val previous = _status.value.shutterDenom
        _status.value = _status.value.copy(shutterDenom = denom, expoMode = CameraCommands.EXPO_MANUAL)
        fireKind(
            SwiftCore.CMD_SET_SHUTTER,
            "$denom",
            "1/$denom",
            coalesce = true,
            onFail = {
                if (_status.value.shutterDenom == denom) {
                    _status.value = _status.value.copy(shutterDenom = previous)
                }
            },
        )
    }

    fun setExpoMode(mode: Int) {
        val extra = CameraCommands.expoWireExtra(mode) ?: return
        val previous = _status.value.expoMode
        _status.value = _status.value.copy(expoMode = mode)
        fireKind(
            SwiftCore.CMD_SET_EXPO_MODE,
            extra,
            "ExpoMode",
            onFail = {
                if (_status.value.expoMode == mode) {
                    _status.value = _status.value.copy(expoMode = previous)
                }
            },
        )
    }

    fun setWhiteBalanceAuto() {
        val previous = _status.value
        _status.value = previous.copy(wbMode = CameraCommands.WB_AUTO, wbKelvin = -1, wbTint = 0)
        fireKind(
            SwiftCore.CMD_SET_WB_AUTO,
            null,
            "WB Auto",
            onFail = {
                val cur = _status.value
                if (cur.wbMode == CameraCommands.WB_AUTO && cur.wbKelvin == -1) {
                    _status.value = previous
                }
            },
        )
    }

    fun setWhiteBalance(kelvin: Int, tint: Int) {
        val (k, t) = CameraCommands.clampWhiteBalanceCustom(kelvin, tint)
        val previous = _status.value
        _status.value = previous.copy(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = k, wbTint = t)
        fireKind(
            SwiftCore.CMD_SET_WB_CUSTOM,
            "$k\u001f$t",
            "WB ${k}K tint $t",
            onFail = {
                val cur = _status.value
                if (cur.wbMode == CameraCommands.WB_CUSTOM && cur.wbKelvin == k && cur.wbTint == t) {
                    _status.value = previous
                }
            },
        )
    }

    fun setFocusMode(continuous: Boolean) {
        if (!supportsFocusMode) return
        val next =
            if (continuous) CameraCommands.FOCUS_CONTINUOUS else CameraCommands.FOCUS_SINGLE
        val previous = _status.value.focusMode
        _status.value = _status.value.copy(focusMode = next)
        fireKind(
            SwiftCore.CMD_SET_FOCUS_MODE,
            if (continuous) "2" else "1",
            "Focus",
            onFail = {
                if (_status.value.focusMode == next) {
                    _status.value = _status.value.copy(focusMode = previous)
                }
            },
        )
    }

    fun setFocusTrack(mode: Int) {
        if (!supportsFocusMode) return
        val track = FocusTrackMode.fromRaw(mode) ?: return
        val previous = _status.value.focusTrack
        lastFocusTrackAt = SystemClock.elapsedRealtime()
        _status.value = _status.value.copy(focusTrack = mode)
        fireKind(
            SwiftCore.CMD_SET_FOCUS_TRACK,
            "$mode",
            "AF-C ${track.label}",
            onFail = {
                if (_status.value.focusTrack == mode) {
                    _status.value = _status.value.copy(focusTrack = previous)
                }
            },
        )
    }

    fun refreshFocusTrack() {
        if (!supportsFocusMode) return
        if (_controlBusy.value) return
        scope.launch {
            sendKind(SwiftCore.CMD_GET_FOCUS_TRACK, null, "Focus track GET")
        }
    }

    /**
     * `0x02/0x42` then optional native ISO hop — iOS `CameraSession.setColorMode`.
     * Optimistic HUD + pin until subscribe matches. Hop only when still on native
     * and [hopEnabled].
     */
    fun setColorMode(
        mode: Int,
        hopEnabled: Boolean = OperatorPrefs.nativeISOHopEnabled(appContext),
    ) {
        val live = _status.value
        val family = connectedCamera?.model?.family ?: "pocket"
        val allowed = CaptureLists.colorWheel(family, live.availableColorModes).map { it.first }
        if (mode !in allowed) return
        val from = live.colorMode
        pinColor(mode)
        fireKind(
            SwiftCore.CMD_SET_COLOR_MODE,
            "$mode",
            CameraCommands.colorLabel(mode, family),
            onFail = { colorPin = null },
        )
        hopNativeISO(from, mode, hopEnabled)
    }

    /**
     * `0x02/0x18` via Swift `Commands.setVideoFormat`. Optimistic HUD, pin until
     * `cam_video_param_v2` matches, revert on ACK fail. Unlabeled res/fps do not SET.
     */
    fun setVideoFormat(format: VideoFormat): Boolean {
        val previous = _status.value
        _status.value =
            previous.copy(
                resolutionCode = format.resolution.rawValue,
                fpsIndex = format.frameRate.rawValue,
                fps = format.frameRate.fps,
            )
        formatPin =
            FormatPin(
                expected = format,
                deadlineElapsedRealtime = SystemClock.elapsedRealtime() + 2_000L,
            )
        val rematch =
            CaptureLists.rematchShutterDenomAfterFps(
                usesAngle = OperatorPrefs.shutterUsesAngle(appContext),
                degrees = OperatorPrefs.shutterAngleDegrees(appContext),
                previousFps = previous.fps,
                nextFps = format.frameRate.fps,
                expoMode = previous.expoMode,
                currentDenom = previous.shutterDenom,
                available = previous.availableShutterDenoms,
            )
        fireKind(
            SwiftCore.CMD_SET_VIDEO_FORMAT,
            "${format.resolution.rawValue}\u001f${format.frameRate.rawValue}",
            format.chipLabel,
            onFail = {
                val live = _status.value
                if (live.resolutionCode == format.resolution.rawValue &&
                    live.fpsIndex == format.frameRate.rawValue
                ) {
                    _status.value =
                        live.copy(
                            resolutionCode = previous.resolutionCode,
                            fpsIndex = previous.fpsIndex,
                            fps = previous.fps,
                        )
                }
                formatPin = null
            },
        )
        if (rematch != null) setShutterDenom(rematch)
        return true
    }

    fun setResolutionFps(res: Int, fpsIndex: Int): Boolean {
        val format = VideoFormat.parse(res, fpsIndex) ?: return false
        return setVideoFormat(format)
    }

    private fun absorbStaleFormat(incoming: CameraStatus): CameraStatus {
        val (next, remaining) =
            VideoFormat.absorbStale(incoming, formatPin, SystemClock.elapsedRealtime())
        formatPin = remaining
        return next
    }

    private fun absorbStaleColor(incoming: CameraStatus): CameraStatus {
        val (next, remaining) =
            ColorPin.absorbStale(incoming, colorPin, SystemClock.elapsedRealtime())
        colorPin = remaining
        return next
    }

    private fun pinColor(mode: Int) {
        _status.value = _status.value.copy(colorMode = mode)
        colorPin =
            ColorPin(
                expected = mode,
                deadlineElapsedRealtime = SystemClock.elapsedRealtime() + 2_000L,
            )
    }

    /** iOS `hopNativeISO` — fires immediately, does not wait for the color ACK. */
    private fun hopNativeISO(from: Int, to: Int, hopEnabled: Boolean) {
        val hop =
            CameraCommands.nativeIsoHop(from, to, _status.value.isoIndex, hopEnabled) ?: return
        Log.i(
            TAG,
            "iso: native hop $from → $to ${_status.value.isoIndex} → $hop",
        )
        setIsoIndex(hop)
    }

    private fun dropDLog2ForZoom(factor: Double) {
        val next = CamFov.colorModeForZoom(factor, _status.value.colorMode)
        if (next == null) {
            restoreDLog2IfNeeded(factor)
            return
        }
        sendZoomColorOnce(next)
    }

    private fun sendZoomColorOnce(next: Int) {
        if (teleColorSent) return
        teleColorSent = true
        restoreDLog2OnWide = true
        val from = _status.value.colorMode
        pinColor(next)
        _controlNote.value = "D-Log — D-Log2 cannot zoom"
        fireKind(
            SwiftCore.CMD_SET_COLOR_MODE,
            "$next",
            "D-Log (zoom)",
            onFail = {
                colorPin = null
                restoreDLog2OnWide = false
                teleColorSent = false
            },
        )
        hopNativeISO(from, next, OperatorPrefs.nativeISOHopEnabled(appContext))
        Log.i(TAG, "zoom: D-Log2 → D-Log (from $from)")
    }

    private fun restoreDLog2IfNeeded(factor: Double) {
        if (!restoreDLog2OnWide || !CamFov.shouldRestoreDLog2(factor)) return
        restoreDLog2OnWide = false
        teleColorSent = false
        val from = _status.value.colorMode
        pinColor(CameraCommands.COLOR_DLOG2)
        fireKind(
            SwiftCore.CMD_SET_COLOR_MODE,
            "${CameraCommands.COLOR_DLOG2}",
            "D-Log2",
            onFail = { colorPin = null },
            onSettle = { ok -> if (ok) _controlNote.value = "Zoom 1× · D-Log2" },
        )
        hopNativeISO(from, CameraCommands.COLOR_DLOG2, OperatorPrefs.nativeISOHopEnabled(appContext))
        Log.i(TAG, "zoom: restore D-Log2 on 1× (from $from)")
    }

    /** iOS `CameraSetMailbox.zoomCoalesceHold` — 20 Hz latest-wins slider. */
    private fun fireZoom(payload: ByteArray, announce: Boolean, name: String) {
        val dl = datalink
        if (dl == null) {
            _controlNote.value = "Zoom not available"
            return
        }
        if (announce) {
            pendingZoomPayload = null
            zoomFlushJob?.cancel()
            zoomFlushJob = null
            dl.sendDuml(0x02, CameraCommands.CMD_ZOOM, payload)
            _controlNote.value = name
            lastZoomWireAt = SystemClock.elapsedRealtime()
            return
        }
        val now = SystemClock.elapsedRealtime()
        val wait = CamFov.SLIDER_COALESCE_MS - (now - lastZoomWireAt)
        if (wait <= 0L) {
            pendingZoomPayload = null
            zoomFlushJob?.cancel()
            zoomFlushJob = null
            lastZoomWireAt = now
            dl.sendDuml(0x02, CameraCommands.CMD_ZOOM, payload)
            return
        }
        pendingZoomPayload = payload
        if (zoomFlushJob != null) return
        zoomFlushJob =
            scope.launch {
                delay(wait.coerceAtLeast(1L))
                val bytes = pendingZoomPayload
                pendingZoomPayload = null
                zoomFlushJob = null
                if (bytes != null) {
                    datalink?.sendDuml(0x02, CameraCommands.CMD_ZOOM, bytes)
                    lastZoomWireAt = SystemClock.elapsedRealtime()
                }
            }
    }

    private fun flushPendingZoom() {
        zoomFlushJob?.cancel()
        zoomFlushJob = null
        val bytes = pendingZoomPayload ?: return
        pendingZoomPayload = null
        datalink?.sendDuml(0x02, CameraCommands.CMD_ZOOM, bytes)
        lastZoomWireAt = SystemClock.elapsedRealtime()
    }

    private fun markZoomStop(factor: Double) {
        zoomStop = factor
        zoomStopTouched = true
    }

    private fun refreshZoomHud() {
        _zoomReadout.value =
            CamFov.readout(
                live = _status.value.zoomFactor,
                preview = zoomPinchPreview,
                fallback = zoomStop,
                optimistic = zoomOptimistic,
            )
        _zoomPinching.value = zoomPinchPreview != null
    }

    private fun resetZoomHud() {
        zoomStop = 1.0
        zoomStopTouched = false
        zoomPinchPreview = null
        zoomOptimistic = null
        zoomPinchAnchor = 1.0
        lastPinchLens = null
        lastPinchLogTenths = null
        refreshZoomHud()
    }

    private fun noteZoomIfChanged(prev: CameraStatus, incoming: CameraStatus) {
        if (incoming.zoomFactorRaw == prev.zoomFactorRaw && incoming.zoomLens == prev.zoomLens) {
            return
        }
        val factor = incoming.zoomFactor
        val optimistic = zoomOptimistic
        if (factor != null && optimistic != null && CamFov.matches(factor, optimistic)) {
            zoomOptimistic = null
        }
        if (!zoomStopTouched && factor != null) {
            zoomStop =
                when {
                    abs(factor - CamFov.MAX_FACTOR) < 0.15 -> 12.0
                    abs(factor - 6) < 0.2 -> 6.0
                    abs(factor - 3) < 0.2 -> 3.0
                    factor < 2.5 -> 1.0
                    else -> zoomStop
                }
        }
        refreshZoomHud()
    }

    fun setAudioChannel(value: Int) {
        pinAudio(channel = value)
        val previous = _status.value.audioChannel
        _status.value = _status.value.copy(audioChannel = value)
        val label = CameraCommands.audioChannelLabel(value) ?: value.toString()
        enqueueAudio {
            val ok = sendKind(SwiftCore.CMD_SET_AUDIO_CHANNEL, "$value", "Audio $label")
            if (!ok) {
                if (_status.value.audioChannel == value) {
                    _status.value = _status.value.copy(audioChannel = previous)
                }
                clearAudioPin(channel = true)
            }
        }
    }

    fun setVocalBoost(on: Boolean) {
        val boost = if (on) 1 else 0
        pinAudio(vocal = boost)
        val previous = _status.value.vocalBoost
        _status.value = _status.value.copy(vocalBoost = boost)
        val label = if (on) "On" else "Off"
        enqueueAudio {
            val ok = sendKind(SwiftCore.CMD_SET_VOCAL_BOOST, if (on) "1" else "0", "Vocal $label")
            if (!ok) {
                if (_status.value.vocalBoost == boost) {
                    _status.value = _status.value.copy(vocalBoost = previous)
                }
                clearAudioPin(vocal = true)
            }
        }
    }

    fun setWindNr(on: Boolean) {
        val value = if (on) 1 else 0
        pinAudio(wind = value)
        _status.value = _status.value.copy(windNr = value)
        enqueueAudio {
            patchAudioDsp("Wind ${if (on) "On" else "Off"}") { CameraCommands.patchWind(it, on) }
        }
    }

    fun setDirectionalAudio(mode: Int) {
        pinAudio(directional = mode)
        _status.value = _status.value.copy(directionalAudio = mode, windNr = 1)
        val label = CameraCommands.audioDirLabel(mode) ?: mode.toString()
        enqueueAudio {
            patchAudioDsp("Dir $label") { CameraCommands.patchDirectional(it, mode) }
        }
    }

    fun refreshAudio() {
        enqueueAudio {
            sendKind(SwiftCore.CMD_GET_AUDIO_CHANNEL, null, "Audio ch GET")
            sendKind(SwiftCore.CMD_GET_VOCAL_BOOST, null, "Vocal GET")
            sendKind(SwiftCore.CMD_AUDIO_DSP_GET, null, "AudioDSP GET")
        }
    }

    fun updateGimbalStick(
        x: Float,
        y: Float,
        sensitivity: Int = CameraCommands.GIMBAL_STICK_DEFAULT_SENSITIVITY,
    ) {
        lastGimbalStickAt = SystemClock.elapsedRealtime()
        pendingGimbalAxes = encodedGimbalAxes(x, y, sensitivity)
        if (gimbalStickJob != null) return
        datalink?.sendGimbalStick(pendingGimbalAxes.first, pendingGimbalAxes.second)
        gimbalStickJob =
            scope.launch {
                while (true) {
                    delay(40)
                    val axes = pendingGimbalAxes
                    datalink?.sendGimbalStick(axes.first, axes.second)
                }
            }
    }

    fun endGimbalStick() {
        val wasHeld = gimbalStickJob != null
        gimbalStickJob?.cancel()
        gimbalStickJob = null
        pendingGimbalAxes =
            CameraCommands.GIMBAL_STICK_CENTER to CameraCommands.GIMBAL_STICK_CENTER
        if (wasHeld) {
            datalink?.sendGimbalStick(
                CameraCommands.GIMBAL_STICK_CENTER,
                CameraCommands.GIMBAL_STICK_CENTER,
            )
        }
    }

    /** Prefer the Swift `GimbalStick.encode` wire; Kotlin copies the same gain/deadzone. */
    private fun encodedGimbalAxes(x: Float, y: Float, sensitivity: Int): Pair<Int, Int> {
        if (SwiftCore.isAvailable) {
            val packed = SwiftCore.gimbalStickEncode(x.toDouble(), y.toDouble(), sensitivity)
            if (packed != null) {
                val parts = packed.split(',')
                if (parts.size == 2) {
                    val axis0 = parts[0].toIntOrNull()
                    val axis1 = parts[1].toIntOrNull()
                    if (axis0 != null && axis1 != null) return axis0 to axis1
                }
            }
        }
        return CameraCommands.gimbalAxes(x, y, sensitivity = sensitivity)
    }

    fun tapFocus(x: Float, y: Float) {
        markFocus(x, y)
    }

    private fun markFocus(x: Float, y: Float) {
        if (!supportsTapFocus) return
        cancelTracking(sendClear = isTrackingActive)
        lastTapFocusAt = SystemClock.elapsedRealtime()
        faceBox = null
        val nx = x.coerceIn(0f, 1f)
        val ny = y.coerceIn(0f, 1f)
        _focusPoint.value = nx to ny
        refreshTrackingHud()
        val dl = datalink ?: return
        dl.sendDuml(0x02, 0x22, byteArrayOf(0x02))
        val xy = "$nx\u001f$ny"
        scope.launch {
            val focused =
                sendKind(SwiftCore.CMD_TAP_FOCUS_POINT, xy, "Focus region", timeoutMs = 800)
            if (!focused) return@launch
            sendKind(SwiftCore.CMD_TAP_FOCUS_HINT, null, "AE hint", timeoutMs = 800)
            sendKind(SwiftCore.CMD_TAP_FOCUS_COMMIT, xy, "Focus", timeoutMs = 800)
        }
    }

    private fun noteFrameTooSmall() {
        searchBox = null
        subjectBox = null
        isTracking = false
        refreshTrackingHud()
        _controlNote.value = "Frame Too Small"
        scope.launch {
            delay(2_000)
            if (_controlNote.value == "Frame Too Small") _controlNote.value = null
        }
    }

    private fun cancelTracking(sendClear: Boolean) {
        val had = isTrackingActive
        stopTrackingPoll()
        searchBox = null
        subjectBox = null
        isTracking = false
        trackingSawLock = false
        if (sendClear) lastOperatorClearAt = SystemClock.elapsedRealtime()
        lastLiveTrackingAt = null
        lastSubjectPushAt = null
        refreshTrackingHud()
        if (!sendClear || !had || datalink == null) return
        fireKind(SwiftCore.CMD_CLEAR_TRACKING_BOX, null, "Track clear")
    }

    private fun beginTrackingPoll() {
        stopTrackingPoll()
        trackingPollJob =
            scope.launch {
                var idleTicks = 0
                while (isActive && isTrackingActive) {
                    datalink?.sendDuml(0x02, CameraCommands.CMD_TRACK_POLL, CameraCommands.pollTracking())
                    delay(500)
                    val now = SystemClock.elapsedRealtime()
                    if (trackingSawLock &&
                        TrackingClearPolicy.shouldDropForSilence(lastSubjectPushAt, now)
                    ) {
                        clearLocalTracking()
                        return@launch
                    }
                    if (isTracking) {
                        idleTicks = 0
                    } else if (trackingSawLock) {
                        clearLocalTracking()
                        return@launch
                    } else {
                        idleTicks += 1
                        if (idleTicks >= 6) {
                            clearLocalTracking()
                            return@launch
                        }
                    }
                }
            }
    }

    private fun stopTrackingPoll() {
        trackingPollJob?.cancel()
        trackingPollJob = null
    }

    private fun clearLocalTracking() {
        searchBox = null
        subjectBox = null
        isTracking = false
        lastLiveTrackingAt = null
        lastSubjectPushAt = null
        stopTrackingPoll()
        refreshTrackingHud()
    }

    private fun applyLiveTrackingPush(payload: ByteArray) {
        val now = SystemClock.elapsedRealtime()
        if (!TrackingClearPolicy.shouldApplyLivePush(lastOperatorClearAt, now)) return
        val box = TrackingBox.parseLivePush(payload) ?: return
        lastSubjectPushAt = now
        subjectBox = smoothedSubject(box)
        isTracking = true
        trackingSawLock = true
        searchBox = null
        adoptCameraFocus(box.centerX, box.centerY, fromTrackingBox = true)
        refreshTrackingHud()
        if (trackingPollJob == null) beginTrackingPoll()
    }

    private fun applyTrackingPoll(payload: ByteArray) {
        val now = SystemClock.elapsedRealtime()
        if (!TrackingClearPolicy.shouldApplyLivePush(lastOperatorClearAt, now)) return
        when (val poll = TrackingPoll.parse(payload)) {
            is TrackingPoll.Locked -> {
                isTracking = true
                trackingSawLock = true
                val cameraBox = poll.box
                if (cameraBox != null) {
                    subjectBox = smoothedSubject(cameraBox)
                } else if (subjectBox == null) {
                    searchBox?.let { subjectBox = TrackingBox.subject(it) }
                }
                searchBox = null
                refreshTrackingHud()
            }
            TrackingPoll.Idle -> {
                isTracking = false
                if (trackingSawLock) clearLocalTracking()
                else refreshTrackingHud()
            }
            null -> Unit
        }
    }

    private fun smoothedSubject(toward: TrackingBox): TrackingBox {
        val now = SystemClock.elapsedRealtime()
        val dt = lastLiveTrackingAt?.let { (now - it) / 1000.0 } ?: Double.POSITIVE_INFINITY
        lastLiveTrackingAt = now
        return TrackingBoxSmoothing.blend(subjectBox, toward, dt)
    }

    private fun adoptCameraFocus(x: Double, y: Double, fromTrackingBox: Boolean) {
        val cur = _focusPoint.value
        if (!CameraFocusPolicy.shouldAdopt(cur.first.toDouble(), cur.second.toDouble(), x, y)) return
        _focusPoint.value = x.toFloat() to y.toFloat()
        if (fromTrackingBox) return
        lastTapFocusAt = SystemClock.elapsedRealtime()
        faceBox = null
    }

    private fun refreshTrackingHud() {
        val now = SystemClock.elapsedRealtime()
        val sinceTap = lastTapFocusAt?.let { (now - it) / 1000.0 }
        val overlay =
            if (FaceAFPolicy.shouldHoldTapBox(sinceTap)) {
                val base = FocusOverlayPolicy.resolve(isTracking, searchBox, subjectBox)
                when (base) {
                    is FocusOverlay.Search, is FocusOverlay.Subject -> base
                    is FocusOverlay.Focus, is FocusOverlay.Face -> FocusOverlay.Focus
                }
            } else {
                FaceAFPolicy.resolve(
                    _status.value.focusMode,
                    isTracking,
                    searchBox,
                    subjectBox,
                    faceBox,
                )
            }
        val hiding = (overlay as? FocusOverlay.Face)?.box
        val occluder =
            when (overlay) {
                is FocusOverlay.Subject -> overlay.box
                is FocusOverlay.Search -> overlay.box
                else -> subjectBox
            }
        _trackingHud.value =
            TrackingHud(
                overlay = overlay,
                sceneFaces = sceneFaces,
                dimmedFaces = SceneFacePolicy.dimmed(sceneFaces, hiding, occluder),
                isTracking = isTrackingActive,
            )
    }

    /** GET `0xA0` blob, patch `@2`, SET `0x9F`. Never invent the blob. */
    private suspend fun patchAudioDsp(name: String, patch: (ByteArray) -> ByteArray) {
        val got = sendKind(SwiftCore.CMD_AUDIO_DSP_GET, null, "AudioDSP GET")
        val blob = CameraCommands.audioDspBytes(_status.value.audioDspBlob) ?: audioDspBlob
        if (!got || blob == null || blob.size <= 2) {
            _controlNote.value = "$name: no DSP blob"
            return
        }
        val next = patch(blob)
        val previousBlob = _status.value.audioDspBlob
        val previousAt2 = _status.value.audioDspAt2
        val previousWind = _status.value.windNr
        val previousDir = _status.value.directionalAudio
        _status.value = _status.value.applyingAudioBlob(next)
        val ok = sendKind(SwiftCore.CMD_AUDIO_DSP_SET, CameraCommands.audioDspHex(next), name)
        if (!ok) {
            _status.value =
                _status.value.copy(
                    audioDspBlob = previousBlob,
                    audioDspAt2 = previousAt2,
                    windNr = previousWind,
                    directionalAudio = previousDir,
                )
            clearAudioPin(wind = true, directional = true)
        }
    }

    private fun pinAudio(
        channel: Int? = null,
        vocal: Int? = null,
        wind: Int? = null,
        directional: Int? = null,
    ) {
        val previous = audioPin
        audioPin =
            AudioPin(
                channel = channel ?: previous?.channel,
                vocal = vocal ?: previous?.vocal,
                wind = wind ?: previous?.wind,
                directional = directional ?: previous?.directional,
                deadlineElapsedMs = SystemClock.elapsedRealtime() + AudioPin.TTL_MS,
            )
    }

    private fun clearAudioPin(
        channel: Boolean = false,
        vocal: Boolean = false,
        wind: Boolean = false,
        directional: Boolean = false,
    ) {
        val pin = audioPin ?: return
        val next =
            pin.copy(
                channel = if (channel) null else pin.channel,
                vocal = if (vocal) null else pin.vocal,
                wind = if (wind) null else pin.wind,
                directional = if (directional) null else pin.directional,
            )
        audioPin = next.takeUnless { it.isEmpty() }
    }

    private fun enqueueAudio(work: suspend () -> Unit) {
        val previous = audioTail
        audioTail =
            scope.launch {
                previous?.join()
                work()
            }
    }

    private suspend fun sendDumlWait(
        set: Int,
        cmd: Int,
        payload: ByteArray,
        name: String,
        receiver: Int = CameraCommands.RX_CAMERA,
        flags: Int = CameraCommands.FLAG_REQUEST,
    ): Boolean {
        val dl = datalink
        if (dl == null) {
            _controlNote.value = "not live"
            return false
        }
        _controlNote.value = null
        val key = opcodeKey(set, cmd)
        pairingHold.remove(key)
        try {
            val reply =
                try {
                    withTimeout(3_000) {
                        suspendCancellableCoroutine<DumlFrame> { cont ->
                            val waiter = FrameWaiter(setOf(key), cont)
                            waiters[key] = waiter
                            cont.invokeOnCancellation { waiters.remove(key) }
                            dl.sendDuml(set, cmd, payload, flags, receiver)
                            pairingHold.remove(key)?.let { held -> waiter.resume(held) }
                        }
                    }
                } catch (_: TimeoutCancellationException) {
                    ControlHud.timeoutNote(name, announce = false)?.let { _controlNote.value = it }
                    Log.i(TAG, "control: timeout $name — waiter saw no ACK")
                    return false
                }
            val parsed = CameraReply.parse(reply.payload)
            if (!parsed.isSuccess) {
                _controlNote.value = "$name: ${parsed.message}"
            }
            return parsed.isSuccess
        } finally {
            waiters.remove(key)
        }
    }

    private fun opcodeKey(set: Int, cmd: Int): Int = ((set and 0xFF) shl 8) or (cmd and 0xFF)

    /**
     * iOS `fireCamera`: latest-wins SET mailbox. Do not block [controlBusy], do
     * not toast a timeout — subscribe/pin is the HUD, a missed ACK is not a
     * revert. Retransmit at 300 ms, settle at 2 s.
     */
    private fun fireKind(
        kind: Int,
        extra: String?,
        name: String,
        coalesce: Boolean = false,
        retransmits: Boolean = true,
        onFail: (() -> Unit)? = null,
        onSettle: ((Boolean) -> Unit)? = null,
    ) {
        val dl = datalink
        if (dl == null) {
            _controlNote.value = "not live"
            onFail?.invoke()
            onSettle?.invoke(false)
            return
        }
        _controlNote.value = null
        val key = SwiftCore.waitKey(kind)
        pairingHold.remove(key)
        val send =
            InflightSend(
                kind = kind,
                extra = extra,
                name = name,
                onFail = onFail,
                onSettle = onSettle,
                retransmits = retransmits,
            )
        if (coalesce && inflight.containsKey(key)) {
            inflightPending[key] = send
            return
        }
        launchInflight(key, send)
    }

    private fun launchInflight(key: Int, send: InflightSend) {
        inflight[key] = send
        inflightPending.remove(key)
        transmit(send)
        if (send.retransmits) {
            scope.launch {
                delay(300)
                if (inflight[key] === send && !send.retransmitted) {
                    send.retransmitted = true
                    transmit(send)
                }
            }
        }
        scope.launch {
            delay(2_000)
            if (inflight[key] === send) settleInflightTimeout(key, send)
        }
    }

    private fun transmit(send: InflightSend) {
        val dl = datalink ?: return
        pairingHold.remove(SwiftCore.waitKey(send.kind))
        try {
            dl.sendCommand(send.kind, send.extra)
            Log.i(TAG, "control: send ${send.name}")
        } catch (e: Exception) {
            Log.w(TAG, "control: send ${send.name} failed", e)
        }
    }

    private fun finishInflight(send: InflightSend, reply: DumlFrame) {
        val key = reply.key
        if (inflight[key] !== send) return
        inflight.remove(key)
        val parsed = CameraReply.parse(reply.payload)
        val ok = parsed.isSuccess
        if (!ok) {
            send.onFail?.invoke()
            _controlNote.value = "${send.name}: ${parsed.message}"
        }
        send.onSettle?.invoke(ok)
        Log.i(TAG, "control: ${send.name} ack=${if (ok) "ok" else parsed.message}")
        inflightPending.remove(key)?.let { launchInflight(key, it) }
    }

    private fun settleInflightTimeout(key: Int, send: InflightSend) {
        if (inflight[key] !== send) return
        inflight.remove(key)
        // iOS `ControlHud.timeoutNote(announce: false)` — never toast a SET timeout.
        Log.i(TAG, "control: ${send.name} — SET timeout, leave HUD")
        send.onSettle?.invoke(true)
        inflightPending.remove(key)?.let { launchInflight(key, it) }
    }

    /**
     * iOS `requestCamera`: true GET/SET round-trip (audio blobs, tap-focus burst).
     * Never [controlBusy], never toast a timeout.
     */
    private suspend fun sendKind(
        kind: Int,
        extra: String?,
        name: String,
        timeoutMs: Long = 3_000,
    ): Boolean {
        val dl = datalink
        if (dl == null) {
            _controlNote.value = "not live"
            return false
        }
        _controlNote.value = null
        val key = SwiftCore.waitKey(kind)
        pairingHold.remove(key)
        try {
            val reply =
                try {
                    withTimeout(timeoutMs) {
                        suspendCancellableCoroutine<DumlFrame> { cont ->
                            val waiter = FrameWaiter(setOf(key), cont)
                            waiters[key] = waiter
                            cont.invokeOnCancellation { waiters.remove(key) }
                            dl.sendCommand(kind, extra)
                            pairingHold.remove(key)?.let { held -> waiter.resume(held) }
                        }
                    }
                } catch (_: TimeoutCancellationException) {
                    ControlHud.timeoutNote(name, announce = false)?.let { _controlNote.value = it }
                    Log.i(TAG, "control: timeout $name — waiter saw no ACK")
                    return false
                }
            val parsed = CameraReply.parse(reply.payload)
            if (!parsed.isSuccess) {
                _controlNote.value = "$name: ${parsed.message}"
            }
            return parsed.isSuccess
        } finally {
            waiters.remove(key)
        }
    }

    private fun shouldHold(frame: DumlFrame): Boolean =
        DumlHold.shouldHoldReply(frame.cmdSet, frame.cmdId)

    private suspend fun readWifiString(name: String, set: Int, cmd: Int, send: () -> Unit): String {
        val deadline = SystemClock.elapsedRealtime() + 30_000
        var last = "couldn't read the camera's Wi-Fi credentials"
        var attempt = 0
        while (SystemClock.elapsedRealtime() < deadline) {
            attempt += 1
            Log.i(TAG, "creds: $name attempt $attempt")
            send()
            try {
                val frame = waitFrame(set, cmd, 6_000)
                val value = SwiftCore.unpackStatusString(frame.payload).orEmpty()
                if (value.isNotEmpty()) return value
                last = "$name came back empty — camera AP not up yet"
            } catch (_: Exception) {
                last = "$name timed out — camera didn't reply (AP still coming up?)"
            }
            delay(400)
        }
        error(last)
    }

    private class InflightSend(
        val kind: Int,
        val extra: String?,
        val name: String,
        val onFail: (() -> Unit)?,
        val onSettle: ((Boolean) -> Unit)?,
        val retransmits: Boolean,
        var retransmitted: Boolean = false,
    )

    private class FrameWaiter(
        val keys: Set<Int>,
        private var continuation: Continuation<DumlFrame>?,
    ) {
        fun resume(frame: DumlFrame) {
            continuation?.resume(frame)
            continuation = null
        }

        fun resumeWithException(error: Throwable) {
            continuation?.resumeWithException(error)
            continuation = null
        }
    }

    companion object {
        private const val TAG = "PocketCameraSession"
        private const val RECOVERY_ATTEMPT_MS = 30_000L
    }
}

internal fun phaseAllowsReconnect(phase: ConnectionPhase): Boolean =
    when (phase) {
        ConnectionPhase.IDLE,
        ConnectionPhase.SCANNING,
        ConnectionPhase.FAILED,
        ConnectionPhase.LIVE,
        -> true
        else -> false
    }

/**
 * Live-feed stall detector. UDP receive age is the stall signal — never 1 Hz `0x09/0xa8`.
 * Mirrors iOS `FeedWatchdog` + `CameraSoftAP` first-picture gates.
 */
internal object LiveViewEnablePolicy {
    const val STALL_MS = 2_000L
    const val ESCALATE_MS = 5_000L
    const val GOP_GRACE_MS = 8_000L
    const val REBUILD_BACKOFF_MS = 60_000L
    const val COOLDOWN_MS = 15_000L
    const val REBUILD_COOLDOWN_MS = 5_000L
    const val FIRST_PICTURE_RESEND_MS = 2_000L
    const val STALLED_FORMAT_RESEND_MS = 5_000L
    const val FORMAT_STALL_MS = 2_000L
    const val HANDSHAKE_RETRY_PAUSE_MS = 500L
    const val HANDSHAKE_OPEN_RETRY_LIMIT = 6
    /** After a foreground rebuild, wait this long for an IDR before a full rejoin. */
    const val FOREGROUND_PICTURE_GRACE_MS = 2_000L

    fun shouldGiveUpOpenRetry(attempts: Int): Boolean = attempts >= HANDSHAKE_OPEN_RETRY_LIMIT

    fun shouldKickAfterHandshakeTimeout(pathReady: Boolean): Boolean = !pathReady

    enum class Action { NONE, RESEND_ENABLE, REBUILD_UDP }

    enum class Stage { IDLE, RESEND_ENABLE, REBUILD_UDP, COOLDOWN }

    enum class FirstPictureStep { WAIT, RESEND_ENABLE, REBUILD_UDP, REJOIN }

    class State {
        var stage: Stage = Stage.IDLE
        var lastActionAt: Long = 0

        fun reset() {
            stage = Stage.IDLE
            lastActionAt = 0
        }
    }

    data class Snapshot(
        val now: Long,
        val videoPackets: Int,
        val lastVideoPacketAt: Long?,
        val lastAccessUnitAt: Long?,
        val lastStatusAt: Long?,
        val lastBleNotifyAt: Long?,
        val lastRebuildAt: Long?,
        val lastEnableAt: Long,
        val pathReady: Boolean,
        val hasFormat: Boolean,
        val decoderErrors: Int,
        val live: Boolean,
        val sawPicture: Boolean,
        val lastFocusTrackAt: Long? = null,
    )

    fun age(now: Long, at: Long?): Long? = at?.let { now - it }

    fun udpReceiveAlive(snap: Snapshot): Boolean {
        val video = age(snap.now, snap.lastVideoPacketAt)
        if (video != null && video < STALL_MS) return true
        val au = age(snap.now, snap.lastAccessUnitAt)
        return au != null && au < STALL_MS
    }

    fun controlReceiveAlive(snap: Snapshot): Boolean {
        val status = age(snap.now, snap.lastStatusAt) ?: return false
        return status < STALL_MS
    }

    fun hadVideo(videoPackets: Int, videoAgeMs: Long?): Boolean =
        videoPackets > 0 || videoAgeMs != null

    fun shouldHoldForGopReset(sinceEnableMs: Long?, videoAgeMs: Long?): Boolean {
        if (sinceEnableMs == null || sinceEnableMs >= GOP_GRACE_MS) return false
        if (videoAgeMs != null && videoAgeMs > sinceEnableMs + STALL_MS) return false
        return true
    }

    /** Control Center / a short app-switcher peek still has a live GOP — do not tear UDP. */
    fun shouldRecoverAfterForeground(
        secondsSinceLastPresented: Double?,
        stallSec: Double = STALL_MS / 1000.0,
    ): Boolean {
        val age = secondsSinceLastPresented ?: return true
        return age >= stallSec
    }

    fun shouldEscalateForegroundRecover(
        secondsSinceLastPresented: Double?,
        graceSec: Double = FOREGROUND_PICTURE_GRACE_MS / 1000.0,
    ): Boolean {
        val age = secondsSinceLastPresented ?: return true
        return age >= graceSec
    }

    fun holdUdpRebuildGopLog(sinceEnableMs: Long?, videoAgeMs: Long?): String =
        "feed: hold UDP rebuild — GOP-reset grace lastEnable=${ageSec(sinceEnableMs)}s lastVideo=${ageSec(videoAgeMs)}s"

    fun holdUdpRebuildAfcLog(sinceSetMs: Long?, videoAgeMs: Long?): String =
        "feed: hold UDP rebuild — AF-C grace lastSet=${ageSec(sinceSetMs)}s lastVideo=${ageSec(videoAgeMs)}s"

    private fun ageSec(ageMs: Long?): String {
        val value = if (ageMs == null) -1.0 else ageMs / 1000.0
        return String.format(java.util.Locale.US, "%.1f", value)
    }

    fun shouldHoldBind(pathReady: Boolean, bleAgeMs: Long?): Boolean =
        pathReady && (bleAgeMs ?: Long.MAX_VALUE) < STALL_MS

    fun shouldHoldRebuildAfterRecentUdp(
        sinceRebuildMs: Long?,
        pathReady: Boolean,
        bleAgeMs: Long?,
        hadVideo: Boolean,
    ): Boolean {
        if (!hadVideo) return false
        if (!shouldHoldBind(pathReady, bleAgeMs)) return false
        val since = sinceRebuildMs ?: return false
        return since < REBUILD_BACKOFF_MS
    }

    fun enableRestartedVideo(sinceEnableMs: Long?, videoAgeMs: Long?): Boolean {
        if (sinceEnableMs == null || videoAgeMs == null) return false
        return videoAgeMs + 50 < sinceEnableMs
    }

    fun shouldRepeatRecoverEnable(
        sinceEnableMs: Long,
        sinceRebuildMs: Long?,
        pathReady: Boolean,
        bleAgeMs: Long?,
        hadVideo: Boolean,
        holdEnableCount: Int,
        videoAgeMs: Long?,
    ): Boolean {
        if (hadVideo && videoAgeMs != null && videoAgeMs > sinceEnableMs + STALL_MS) return false
        if (!hadVideo) return sinceEnableMs >= STALL_MS
        if (shouldHoldRebuildAfterRecentUdp(sinceRebuildMs, pathReady, bleAgeMs, true)) return false
        if (holdEnableCount < 2) return sinceEnableMs >= ESCALATE_MS
        return sinceEnableMs >= REBUILD_BACKOFF_MS
    }

    fun shouldRunFirstPictureRecover(presentedAgeMs: Long?, alreadySettled: Boolean): Boolean {
        if (alreadySettled) return false
        return presentedAgeMs == null || presentedAgeMs >= STALL_MS
    }

    fun shouldMarkFirstPictureSettled(presentedAgeMs: Long?, sinceEnableMs: Long): Boolean {
        val presented = presentedAgeMs ?: return false
        return presented >= 0 && presented < STALL_MS && sinceEnableMs >= GOP_GRACE_MS
    }

    fun firstPictureStep(
        videoPackets: Int,
        enableSends: Int,
        sinceEnableMs: Long,
        videoAgeMs: Long?,
        sinceRebuildMs: Long?,
    ): FirstPictureStep {
        if (enableSends < 1) return FirstPictureStep.RESEND_ENABLE
        if (sinceEnableMs < FIRST_PICTURE_RESEND_MS) return FirstPictureStep.WAIT
        val had = hadVideo(videoPackets, videoAgeMs)
        val videoFresh = had && (videoAgeMs ?: Long.MAX_VALUE) < STALL_MS
        if (!had) {
            if (enableSends >= 4) return FirstPictureStep.REJOIN
            if (enableSends >= 2) {
                if (sinceRebuildMs != null && sinceRebuildMs < REBUILD_COOLDOWN_MS) {
                    return FirstPictureStep.WAIT
                }
                return FirstPictureStep.REBUILD_UDP
            }
            return FirstPictureStep.RESEND_ENABLE
        }
        if (sinceEnableMs < GOP_GRACE_MS) {
            if (videoFresh && enableSends == 1 && sinceEnableMs >= ESCALATE_MS) {
                return FirstPictureStep.RESEND_ENABLE
            }
            return FirstPictureStep.WAIT
        }
        if (videoFresh) {
            if (enableSends == 1) return FirstPictureStep.RESEND_ENABLE
            return FirstPictureStep.WAIT
        }
        if (sinceRebuildMs != null && sinceRebuildMs < REBUILD_COOLDOWN_MS) return FirstPictureStep.WAIT
        if (enableSends >= 4) return FirstPictureStep.REJOIN
        if (sinceRebuildMs != null) return FirstPictureStep.REJOIN
        return FirstPictureStep.REBUILD_UDP
    }

    /**
     * Leftover TRAIL P-frames still arriving: ask for IDR, keep the socket.
     * [videoPackets] > 0 with a stale [videoAgeMs] is a dead receive — rebuild UDP.
     * Frozen pkts=375 then three enable resends delayed first picture ~32 s.
     */
    fun shouldKeepUdpForLeftoverGop(
        noPicture: Boolean,
        videoPackets: Int,
        videoAgeMs: Long?,
    ): Boolean {
        if (!noPicture || videoPackets <= 0) return false
        val age = videoAgeMs ?: return false
        return age < STALL_MS
    }

    /** Pocket: `0x02/0x68` `08` immediately before `0x09/0xa8`. Not Nano. */
    fun shouldSendLiveViewPrepare(usesNanoLiveViewGate: Boolean): Boolean = !usesNanoLiveViewGate

    /** `0x02/0x0c` is gallery enter/exit — not live-start. Matches iOS / handbook. */
    fun shouldExitPlaybackBeforeLiveEnable(inPlayback: Boolean): Boolean = inPlayback

    fun shouldClearForegroundRecoverWithoutRebuild(holdsMonitor: Boolean): Boolean = holdsMonitor

    fun shouldContinueFirstPictureAfterStrayPlayback(hasPicture: Boolean): Boolean = !hasPicture

    /**
     * Mimo / iOS: arm pktType 0x02 ingest on the enable write. A DUML ACK wait
     * (Android used 200 ms) drops the 25–167 ms VPS and the HUD never leaves
     * WAITING FOR LIVE VIEW.
     */
    fun shouldWaitForLiveViewAckBeforeArm(): Boolean = false

    fun shouldKeepaliveRebuildUDP(
        flowNeedsRebuild: Boolean,
        rebuildInFlight: Boolean,
        sinceRebuildMs: Long?,
        videoFresh: Boolean = false,
        sawPicture: Boolean = true,
    ): Boolean {
        if (!sawPicture) return false
        if (!flowNeedsRebuild || rebuildInFlight || videoFresh) return false
        if (sinceRebuildMs != null && sinceRebuildMs < REBUILD_COOLDOWN_MS) return false
        return true
    }

    fun shouldForceEnableAfterUDPRebuild(hadVideo: Boolean): Boolean = !hadVideo

    fun shouldSendRecoverEnable(pathReady: Boolean, decoderReady: Boolean): Boolean =
        pathReady && decoderReady

    fun tick(state: State, snap: Snapshot): Action {
        if (!snap.live) {
            state.reset()
            return Action.NONE
        }
        if (!snap.pathReady) return Action.NONE
        if (udpReceiveAlive(snap)) {
            state.reset()
            return Action.NONE
        }
        val sinceEnable = if (snap.lastEnableAt == 0L) null else snap.now - snap.lastEnableAt
        val videoAge = age(snap.now, snap.lastVideoPacketAt)
        if (shouldHoldForGopReset(sinceEnable, videoAge)) return Action.NONE
        if (FocusTrackMode.shouldHoldWatchdog(age(snap.now, snap.lastFocusTrackAt)?.div(1000.0))) {
            return Action.NONE
        }

        val had = hadVideo(snap.videoPackets, videoAge)
        if (!had) {
            if (state.stage != Stage.IDLE && snap.now - state.lastActionAt < ESCALATE_MS) {
                return Action.NONE
            }
            return when (state.stage) {
                Stage.IDLE -> fire(state, Action.RESEND_ENABLE, snap.now)
                Stage.RESEND_ENABLE -> fire(state, Action.REBUILD_UDP, snap.now)
                Stage.REBUILD_UDP, Stage.COOLDOWN -> {
                    state.stage = Stage.COOLDOWN
                    state.lastActionAt = snap.now
                    Action.NONE
                }
            }
        }

        if (controlReceiveAlive(snap) && !udpReceiveAlive(snap)) {
            if (state.stage == Stage.RESEND_ENABLE &&
                !enableRestartedVideo(sinceEnable, videoAge) &&
                snap.now - state.lastActionAt >= STALL_MS
            ) {
                return fire(state, Action.REBUILD_UDP, snap.now)
            }
            if (state.stage == Stage.IDLE || snap.now - state.lastActionAt >= ESCALATE_MS) {
                return fire(state, Action.RESEND_ENABLE, snap.now)
            }
            return Action.NONE
        }

        val bleAge = age(snap.now, snap.lastBleNotifyAt)
        val sinceRebuild = age(snap.now, snap.lastRebuildAt)
        if (shouldHoldRebuildAfterRecentUdp(sinceRebuild, snap.pathReady, bleAge, had)) {
            if (state.stage == Stage.IDLE) {
                state.stage = Stage.COOLDOWN
                state.lastActionAt = snap.now
            }
            return Action.NONE
        }

        if (state.stage == Stage.COOLDOWN) {
            if (shouldHoldBind(snap.pathReady, bleAge)) return Action.NONE
            if (snap.now - state.lastActionAt >= COOLDOWN_MS) {
                return fire(state, Action.REBUILD_UDP, snap.now)
            }
            return Action.NONE
        }

        if (state.stage != Stage.IDLE && snap.now - state.lastActionAt < ESCALATE_MS) {
            return Action.NONE
        }
        return when (state.stage) {
            Stage.IDLE, Stage.RESEND_ENABLE -> fire(state, Action.REBUILD_UDP, snap.now)
            Stage.REBUILD_UDP, Stage.COOLDOWN -> {
                state.stage = Stage.COOLDOWN
                state.lastActionAt = snap.now
                Action.NONE
            }
        }
    }

    private fun fire(state: State, action: Action, now: Long): Action {
        state.stage =
            when (action) {
                Action.RESEND_ENABLE -> Stage.RESEND_ENABLE
                Action.REBUILD_UDP -> Stage.REBUILD_UDP
                Action.NONE -> state.stage
            }
        state.lastActionAt = now
        return action
    }

    /** Legacy gate used by tests: first-picture 2 s, stalled format 5 s — never 1 Hz. */
    fun shouldResendEnable(
        videoPackets: Int,
        nowElapsedRealtime: Long,
        lastIdrRequest: Long,
        hasFormat: Boolean,
        decoderErrors: Int,
        streamStartedAt: Long?,
    ): Boolean {
        if (videoPackets == 0) {
            return nowElapsedRealtime - lastIdrRequest >= FIRST_PICTURE_RESEND_MS
        }
        val started = streamStartedAt ?: nowElapsedRealtime
        val stalled =
            (decoderErrors > 0 && !hasFormat) ||
                (!hasFormat && nowElapsedRealtime - started > FORMAT_STALL_MS)
        if (!stalled) return false
        return nowElapsedRealtime - lastIdrRequest >= STALLED_FORMAT_RESEND_MS
    }
}
