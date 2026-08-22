package com.opencapture.openpocketcine.session

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.core.CameraSession as CameraSessionSeam
import com.opencapture.openpocketcine.core.ConnectionPhase
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * BLE → pair → Wi-Fi creds → camera AP → datalink → live HEVC/AVC.
 * Mirrors iOS `CameraSession` recovery, feed watchdog, and operator commands.
 */
class PocketCameraSession(context: Context) : CameraSessionSeam {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val ble = BleLink(context)
    private val joiner = CameraApJoiner(context)
    val decoder = HevcDecoder()
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
    private val _focusPoint = MutableStateFlow<Pair<Float, Float>?>(null)
    val focusPoint: StateFlow<Pair<Float, Float>?> = _focusPoint.asStateFlow()
    private var audioDspBlob: ByteArray? = null
    private var gimbalStickJob: Job? = null
    @Volatile private var pendingGimbalAxes: Pair<Int, Int> =
        CameraCommands.GIMBAL_STICK_CENTER to CameraCommands.GIMBAL_STICK_CENTER

    var connectedCamera: FoundCamera? = null
        private set
    var joinedSSID: String? = null
        private set

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
    private var isBrowsingMedia = false
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
    private var reconnectJob: Job? = null
    private var reconnectTarget: String? = null
    private var feedRecoveryJob: Job? = null
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
                datalink?.rebuildUdpKeepingSession()
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
        datalink?.close()
        datalink = null
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
        _focusPoint.value = null
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
        publishPhase(ConnectionPhase.PAIRING)
        ble.send(SwiftCore.command(SwiftCore.CMD_SESSION_WAKE, 0x802B))
        ble.send(SwiftCore.command(SwiftCore.CMD_SET_PAIRING_PIN, 0x8092, camera.model.pairingToken))
        publishPhase(ConnectionPhase.AWAITING_APPROVAL)
        try {
            completePairing()
        } catch (_: TimeoutCancellationException) {
            error("pairing timed out — tap Approve on the camera if it asked")
        }

        startKeepalive(ssid = null)
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
            existing
                ?: DatalinkDriver(
                    joiner,
                    camera.model.datalinkPort,
                    camera.model.tcpPoke,
                    camera.model.pairingToken,
                ).also { created ->
                    created.onStatusFrame = { frame -> ingestDatalinkFrame(frame) }
                    created.onAccessUnit = { au ->
                        rawAccessUnits += 1
                        decoder.decode(au)
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
                        publishPipelineStats()
                        if (!isBrowsingMedia) recoverLiveViewIfNeeded()
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
        if (isBrowsingMedia || holdsMonitor) return
        if (needsForegroundRecover) return
        if (!joiner.isProcessBound()) return
        if (feedRecoveryJob != null) return
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
            LiveViewEnablePolicy.FirstPictureStep.WAIT -> Unit
            LiveViewEnablePolicy.FirstPictureStep.RESEND_ENABLE -> {
                if (liveViewEnableSends == 0) {
                    sendCapturedLiveView("first picture")
                } else {
                    sendRecoverEnable(force = true, reason = "first-picture resend")
                }
            }
            LiveViewEnablePolicy.FirstPictureStep.REBUILD_UDP -> {
                Log.i(TAG, "live: first-picture rebuild UDP (receive died pkts=$packets)")
                startFeedRecovery {
                    datalink?.rebuildUdpKeepingSession()
                    sendRecoverEnable(force = true, reason = "first-picture after UDP rebuild")
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
                        datalink?.rebuildUdpKeepingSession()
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
                    datalink?.rebuildUdpKeepingSession()
                    sendRecoverEnable(force = true, reason = "feed watchdog UDP rebuild")
                }
        }
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
        if (holdsMonitor) return
        if (!needsForegroundRecover) return
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
        datalink?.close()
        datalink = null
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
        if (usesNanoLiveViewGate(camera)) datalink?.sendNanoGate(start = true)
        datalink?.startLiveView(receiver)
        val now = SystemClock.elapsedRealtime()
        lastIdrRequest = now
        liveViewEnableSends += 1
        if (!decoder.awaitingIdr) idrHoldEnableCount = 0
        decoder.beginIDRHold()
        idrHoldEnableCount += 1
        Log.i(TAG, "live: 0x09/0xa8 rcv=0x${receiver.toString(16)} ($reason) #$liveViewEnableSends")
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

    private fun stopLivePipeline(preserveDecoder: Boolean, preserveSoftAP: Boolean = false) {
        keepaliveJob?.cancel()
        keepaliveJob = null
        endGimbalStick()
        failAllWaiters(IllegalStateException("the camera disconnected"))
        datalink?.close()
        datalink = null
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
        } else if (shouldHold(frame)) {
            pairingHold[frame.key] = frame
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
        next = StatusExtras.apply(frame, next)
        if (frame.cmdSet == 0x02 && frame.cmdId == 0xA0) {
            val (updated, blob) = StatusExtras.applyAudioDsp(frame.payload, next)
            next = updated
            if (blob != null) {
                audioDspBlob = blob
                next =
                    next.copy(audioDspBlob = blob.joinToString("") { "%02x".format(it.toInt() and 0xFF) })
                        .withAudioDspAt2()
            }
        }
        if (next != prev) _status.value = next
    }

    fun pressRecord() {
        if (_controlBusy.value) return
        scope.launch {
            if (_status.value.isRecording) {
                sendKind(SwiftCore.CMD_RECORD_STOP, null, "Stop")
            } else {
                sendKind(SwiftCore.CMD_RECORD_START, null, "Record")
            }
        }
    }

    /** Rec lamp: still in Photo / SuperNight, else start/stop video. */
    fun pressShutter() {
        if (_controlBusy.value) return
        if (CameraCommands.isPhotoMode(_status.value.shootingMode)) {
            scope.launch {
                sendDumlWait(0x02, CameraCommands.CMD_PHOTO, CameraCommands.shootPhoto(), "Photo")
            }
            return
        }
        pressRecord()
    }

    fun setEv(thirds: Int) {
        if (_controlBusy.value) return
        scope.launch {
            sendDumlWait(0x02, CameraCommands.CMD_EV, CameraCommands.ev(thirds), "EV")
        }
    }

    fun setIsoLimit(raw: Int) {
        if (_controlBusy.value) return
        scope.launch {
            sendDumlWait(0x02, CameraCommands.CMD_PARAM, CameraCommands.isoLimit(raw), "ISO limit")
        }
    }

    fun setShootingMode(raw: Int) {
        if (_controlBusy.value) return
        scope.launch {
            sendKind(SwiftCore.CMD_SET_SHOOTING_MODE, "$raw", "Mode")
        }
    }

    fun setZoomLens(position: Int) {
        if (_controlBusy.value) return
        scope.launch {
            sendDumlWait(0x02, CameraCommands.CMD_ZOOM, CameraCommands.zoomLens(position), "Zoom")
        }
    }

    fun setZoom(factor: Double) {
        setZoomLens(CameraCommands.lensForZoomFactor(factor))
    }

    fun setZoomSlew(value: Int) {
        if (_controlBusy.value) return
        scope.launch {
            sendDumlWait(0x02, CameraCommands.CMD_ZOOM, CameraCommands.zoomSlew(value), "Zoom slew")
        }
    }

    fun setZoomStop() {
        if (_controlBusy.value) return
        scope.launch {
            sendDumlWait(0x02, CameraCommands.CMD_ZOOM, CameraCommands.zoomStop(), "Zoom stop")
        }
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

    fun startTracking(x: Float, y: Float, width: Float = 0.2f, height: Float = 0.2f) {
        if (_controlBusy.value) return
        val id = nextTrackingId
        nextTrackingId = if (nextTrackingId == 0xFFFF) 1 else nextTrackingId + 1
        scope.launch {
            sendDumlWait(
                0x02,
                CameraCommands.CMD_TRACK_SET,
                CameraCommands.trackingBox(id, x, y, width, height),
                "Track",
            )
        }
    }

    fun cancelTracking() {
        if (_controlBusy.value) return
        scope.launch {
            sendDumlWait(0x02, CameraCommands.CMD_TRACK_SET, CameraCommands.clearTracking(), "Track clear")
        }
    }

    fun resetFocusPoint() {
        tapFocus(0.5f, 0.5f)
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
        if (_controlBusy.value) return
        scope.launch {
            if (sendKind(SwiftCore.CMD_SET_ISO_INDEX, "$index", "ISO")) {
                _status.value = _status.value.copy(isoIndex = index)
            }
        }
    }

    fun setShutterDenom(denom: Int) {
        if (_controlBusy.value) return
        scope.launch {
            sendKind(SwiftCore.CMD_SET_EXPO_MODE, "manual", "Manual expo")
            if (sendKind(SwiftCore.CMD_SET_SHUTTER, "$denom", "1/$denom")) {
                _status.value = _status.value.copy(shutterDenom = denom, expoMode = CameraCommands.EXPO_MANUAL)
            }
        }
    }

    fun setExpoMode(manual: Boolean) {
        if (_controlBusy.value) return
        scope.launch {
            val extra = if (manual) "manual" else "auto"
            if (sendKind(SwiftCore.CMD_SET_EXPO_MODE, extra, "Expo")) {
                _status.value =
                    _status.value.copy(
                        expoMode = if (manual) CameraCommands.EXPO_MANUAL else CameraCommands.EXPO_AUTO,
                    )
            }
        }
    }

    fun setWhiteBalanceAuto() {
        if (_controlBusy.value) return
        scope.launch {
            if (sendKind(SwiftCore.CMD_SET_WB_AUTO, null, "WB Auto")) {
                _status.value = _status.value.copy(wbMode = CameraCommands.WB_AUTO)
            }
        }
    }

    fun setWhiteBalance(kelvin: Int, tint: Int) {
        if (_controlBusy.value) return
        scope.launch {
            if (sendKind(SwiftCore.CMD_SET_WB_CUSTOM, "$kelvin\u001f$tint", "WB")) {
                _status.value =
                    _status.value.copy(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = kelvin, wbTint = tint)
            }
        }
    }

    fun setFocusMode(continuous: Boolean) {
        if (connectedCamera?.model?.supportsFocusMode == false) return
        if (_controlBusy.value) return
        scope.launch {
            val extra = if (continuous) "2" else "1"
            if (sendKind(SwiftCore.CMD_SET_FOCUS_MODE, extra, "Focus")) {
                _status.value =
                    _status.value.copy(
                        focusMode =
                            if (continuous) CameraCommands.FOCUS_CONTINUOUS else CameraCommands.FOCUS_SINGLE,
                    )
            }
        }
    }

    fun setFocusTrack(mode: Int) {
        if (connectedCamera?.model?.supportsFocusMode == false) return
        val track = FocusTrackMode.fromRaw(mode) ?: return
        if (_controlBusy.value) return
        scope.launch {
            val previous = _status.value.focusTrack
            lastFocusTrackAt = SystemClock.elapsedRealtime()
            _status.value = _status.value.copy(focusTrack = mode)
            val ok = sendKind(SwiftCore.CMD_SET_FOCUS_TRACK, "$mode", "AF-C ${track.label}")
            if (!ok && _status.value.focusTrack == mode) {
                _status.value = _status.value.copy(focusTrack = previous)
            }
        }
    }

    fun refreshFocusTrack() {
        if (connectedCamera?.model?.supportsFocusMode == false) return
        if (_controlBusy.value) return
        scope.launch {
            sendKind(SwiftCore.CMD_GET_FOCUS_TRACK, null, "Focus track GET")
        }
    }

    fun setColorMode(mode: Int) {
        if (_controlBusy.value) return
        scope.launch {
            if (sendKind(SwiftCore.CMD_SET_COLOR_MODE, "$mode", "Color")) {
                _status.value = _status.value.copy(colorMode = mode)
            }
        }
    }

    fun setResolutionFps(res: Int, fpsIndex: Int) {
        if (_controlBusy.value) return
        scope.launch {
            if (sendKind(SwiftCore.CMD_SET_VIDEO_FORMAT, "$res\u001f$fpsIndex", "Format")) {
                _status.value =
                    _status.value.copy(
                        resolutionCode = res,
                        fpsIndex = fpsIndex,
                        fps = CameraCommands.fpsFromIndex(fpsIndex) ?: _status.value.fps,
                    )
            }
        }
    }

    fun setAudioChannel(value: Int) {
        if (_controlBusy.value) return
        scope.launch {
            if (sendKind(SwiftCore.CMD_SET_AUDIO_CHANNEL, "$value", "Audio")) {
                _status.value = _status.value.copy(audioChannel = value)
            }
        }
    }

    fun setVocalBoost(on: Boolean) {
        if (_controlBusy.value) return
        scope.launch {
            if (sendKind(SwiftCore.CMD_SET_VOCAL_BOOST, if (on) "1" else "0", "Vocal Boost")) {
                _status.value = _status.value.copy(vocalBoost = if (on) 1 else 0)
            }
        }
    }

    fun setWindNr(on: Boolean) {
        if (_controlBusy.value) return
        scope.launch { patchAudioDsp(SwiftCore.CMD_AUDIO_DSP_PATCH_WIND, if (on) "1" else "0", "Wind NR") }
    }

    fun setDirectionalAudio(mode: Int) {
        if (_controlBusy.value) return
        val extra =
            when (mode) {
                1 -> "1"
                2 -> "2"
                else -> "0"
            }
        scope.launch { patchAudioDsp(SwiftCore.CMD_AUDIO_DSP_PATCH_DIRECTIONAL, extra, "Directional") }
    }

    fun refreshAudio() {
        if (_controlBusy.value) return
        scope.launch {
            sendKind(SwiftCore.CMD_GET_AUDIO_CHANNEL, null, "Audio GET")
            sendKind(SwiftCore.CMD_GET_VOCAL_BOOST, null, "Vocal GET")
            sendKind(SwiftCore.CMD_AUDIO_DSP_GET, null, "DSP GET")
        }
    }

    fun updateGimbalStick(x: Float, y: Float) {
        pendingGimbalAxes = CameraCommands.gimbalAxes(x, y)
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

    fun tapFocus(x: Float, y: Float) {
        val nx = x.coerceIn(0f, 1f)
        val ny = y.coerceIn(0f, 1f)
        _focusPoint.value = nx to ny
        if (_controlBusy.value) return
        val xy = "$nx\u001f$ny"
        scope.launch {
            // mimo-tap-focus-20260818: 0x22 02, 0x30 xy, 0x68 08, 0x32 region.
            // Glamour is 0x8E pid 0x0039, not 0x68.
            sendKind(SwiftCore.CMD_TAP_FOCUS_PREPARE, null, "AE spot")
            sendKind(SwiftCore.CMD_TAP_FOCUS_POINT, xy, "Focus region")
            sendKind(SwiftCore.CMD_TAP_FOCUS_HINT, null, "AE hint")
            sendKind(SwiftCore.CMD_TAP_FOCUS_COMMIT, xy, "Focus")
        }
    }

    private suspend fun patchAudioDsp(kind: Int, extra: String, name: String) {
        var blob = _status.value.audioDspBlob.ifEmpty { null }
        if (blob == null) {
            sendKind(SwiftCore.CMD_AUDIO_DSP_GET, null, "DSP GET")
            blob = _status.value.audioDspBlob.ifEmpty { audioDspBlob?.joinToString("") { "%02x".format(it.toInt() and 0xFF) } }
        }
        if (blob.isNullOrEmpty()) {
            _controlNote.value = "$name: no audio DSP blob yet"
            return
        }
        sendKind(kind, "$blob\u001f$extra", name)
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
        _controlBusy.value = true
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
                        }
                    }
                } catch (_: Exception) {
                    _controlNote.value = "$name timed out"
                    return false
                }
            val ok = reply.payload.isEmpty() || reply.payload[0] == 0.toByte()
            if (!ok) {
                _controlNote.value = "$name: camera reply 0x%02X".format(reply.payload[0].toInt() and 0xFF)
            }
            return ok
        } finally {
            waiters.remove(key)
            _controlBusy.value = false
        }
    }

    private fun opcodeKey(set: Int, cmd: Int): Int = ((set and 0xFF) shl 8) or (cmd and 0xFF)

    private suspend fun sendKind(kind: Int, extra: String?, name: String): Boolean {
        val dl = datalink
        if (dl == null) {
            _controlNote.value = "not live"
            return false
        }
        _controlBusy.value = true
        _controlNote.value = null
        val key = SwiftCore.waitKey(kind)
        pairingHold.remove(key)
        try {
            val reply =
                try {
                    withTimeout(3_000) {
                        suspendCancellableCoroutine<DumlFrame> { cont ->
                            val waiter = FrameWaiter(setOf(key), cont)
                            waiters[key] = waiter
                            cont.invokeOnCancellation { waiters.remove(key) }
                            dl.sendCommand(kind, extra)
                        }
                    }
                } catch (_: Exception) {
                    if (name == "Record" || name == "Stop") {
                        delay(900)
                        val rec = _status.value.isRecording
                        if (name == "Record" && rec) return true
                        if (name == "Stop" && !rec) return true
                    }
                    _controlNote.value = "$name timed out"
                    return false
                }
            val ok = reply.payload.isEmpty() || reply.payload[0] == 0.toByte()
            if (!ok) {
                _controlNote.value = "$name: camera reply 0x%02X".format(reply.payload[0].toInt() and 0xFF)
            }
            return ok
        } finally {
            waiters.remove(key)
            _controlBusy.value = false
        }
    }

    private fun shouldHold(frame: DumlFrame): Boolean =
        when (frame.key) {
            0x0745, 0x0746, 0x0707, 0x070E, 0x5310 -> true
            0x0201, 0x0202, 0x0209, 0x020C, 0x021E, 0x0222, 0x0224, 0x0228, 0x022A, 0x022C,
            0x0218, 0x022E, 0x0230, 0x0232, 0x0242, 0x028E, 0x029F, 0x02A0,
            0x02A5, 0x02A6, 0x02B8, 0x02BF, 0x044C, 0x0026, 0x0028, 0x09A8,
            -> true
            else -> false
        }

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
