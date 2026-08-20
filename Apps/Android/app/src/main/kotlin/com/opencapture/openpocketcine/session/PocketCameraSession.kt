package com.opencapture.openpocketcine.session

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.core.CameraSession as CameraSessionSeam
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.pairing.CameraApJoiner
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
import kotlinx.coroutines.withTimeout
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * BLE → pair → Wi-Fi creds → camera AP → datalink → live HEVC.
 * Mirrors iOS `CameraSession` without inventing extra camera-control commands.
 */
class PocketCameraSession(context: Context) : CameraSessionSeam {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val ble = BleLink(context)
    private val joiner = CameraApJoiner(context)
    val decoder = HevcDecoder()

    private val _phase = MutableStateFlow(ConnectionPhase.IDLE)
    override val phase: ConnectionPhase get() = _phase.value
    val phaseFlow: StateFlow<ConnectionPhase> = _phase.asStateFlow()

    private val _failure = MutableStateFlow<String?>(null)
    val failure: StateFlow<String?> = _failure.asStateFlow()

    val found: StateFlow<List<FoundCamera>> = ble.found
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

    private var rawAccessUnits = 0
    private var lastIdrRequest = 0L
    private var streamStartedAt: Long? = null
    private var datalink: DatalinkDriver? = null
    private var connectJob: Job? = null
    private var keepaliveJob: Job? = null
    private var frameJob: Job? = null
    private val waiters = ConcurrentHashMap<Int, FrameWaiter>()
    private val pairingHold = ConcurrentHashMap<Int, DumlFrame>()
    private var reconnectJob: Job? = null
    private var reconnectTarget: String? = null

    init {
        ble.onLinkLost = { failLink("the camera disconnected") }
        joiner.onPathLost = { failLink("the camera Wi-Fi disconnected") }
    }

    override fun startScan() {
        startScan(reconnect = null)
    }

    fun startScan(reconnect: String?) {
        reconnectTarget = reconnect
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
        if (!phaseAllowsReconnect(_phase.value)) return
        if (_phase.value == ConnectionPhase.LIVE) leaveLiveForReconnect()
        found.value.firstOrNull { it.id == id }?.let {
            connect(it)
            return
        }
        startScan(reconnect = id)
    }

    fun connect(camera: FoundCamera) {
        when (_phase.value) {
            ConnectionPhase.IDLE, ConnectionPhase.SCANNING, ConnectionPhase.FAILED -> Unit
            ConnectionPhase.LIVE -> leaveLiveForReconnect()
            else -> return
        }
        reconnectTarget = null
        connectJob?.cancel()
        connectJob =
            scope.launch {
                try {
                    run(camera)
                } catch (e: Exception) {
                    if (_phase.value == ConnectionPhase.IDLE) return@launch
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
        reconnectTarget = null
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
        connectedCamera = null
        joinedSSID = null
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
        streamStartedAt = null
        decoder.reset()
        _phase.value = ConnectionPhase.CONNECTING_GATT
        startFrameRouter()
        ble.connect(camera)

        pairingHold.clear()
        _phase.value = ConnectionPhase.PAIRING
        ble.send(SwiftCore.command(SwiftCore.CMD_SESSION_WAKE, 0x802B))
        ble.send(SwiftCore.command(SwiftCore.CMD_SET_PAIRING_PIN, 0x8092, camera.model.pairingToken))
        _phase.value = ConnectionPhase.AWAITING_APPROVAL
        try {
            completePairing()
        } catch (_: TimeoutCancellationException) {
            error("pairing timed out — tap Approve on the camera if it asked")
        }

        startKeepalive(ssid = null)
        _phase.value = ConnectionPhase.READING_WIFI_CREDS
        delay(200)
        ble.send(SwiftCore.command(SwiftCore.CMD_SESSION_5310, 0x8053))
        runCatching { waitFrame(0x53, 0x10, 2_000) }
        delay(600)
        val ssid =
            readWifiString("GetSSID", 0x07, 0x07) {
                ble.send(SwiftCore.command(SwiftCore.CMD_GET_WIFI_SSID, 0x8007))
            }
        val pass =
            readWifiString("GetPassword", 0x07, 0x0E) {
                ble.send(SwiftCore.command(SwiftCore.CMD_GET_WIFI_PASSWORD, 0x800E))
            }

        _phase.value = ConnectionPhase.JOINING_WIFI
        val joined = joiner.join(ssid, pass, camera.model.wpa3)
        if (!joined) error("couldn't join camera Wi-Fi — tap the system Join prompt if Android asked")
        joinedSSID = ssid

        _phase.value = ConnectionPhase.OPENING_DATALINK
        val dl = DatalinkDriver(joiner, camera.model.datalinkPort, camera.model.tcpPoke, camera.model.pairingToken)
        dl.onStatusFrame = { frame ->
            ingestDatalinkFrame(frame)
        }
        dl.onAccessUnit = { au ->
            rawAccessUnits += 1
            decoder.decode(au)
        }
        datalink = dl
        withTimeout(20_000) { kotlinx.coroutines.withContext(Dispatchers.IO) { dl.open() } }
        dl.startLiveView()
        lastIdrRequest = SystemClock.elapsedRealtime()
        _phase.value = ConnectionPhase.LIVE
        startKeepalive(ssid)
    }

    private fun startFrameRouter() {
        frameJob?.cancel()
        frameJob =
            scope.launch {
                ble.frames.collect { frame ->
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
                    if (ssid != null) {
                        datalink?.keepalive()
                        publishPipelineStats()
                        recoverLiveViewIfNeeded()
                    }
                    delay(1_000)
                }
            }
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
        val packets = datalink?.videoPackets ?: 0
        val now = SystemClock.elapsedRealtime()
        if (packets > 0 && streamStartedAt == null) streamStartedAt = now
        if (!LiveViewEnablePolicy.shouldResendEnable(
                videoPackets = packets,
                nowElapsedRealtime = now,
                lastIdrRequest = lastIdrRequest,
                hasFormat = decoder.hasFormat,
                decoderErrors = decoderErrors,
                streamStartedAt = streamStartedAt,
            )
        ) {
            return
        }
        lastIdrRequest = now
        datalink?.startLiveView()
    }

    private fun failLink(reason: String) {
        when (_phase.value) {
            ConnectionPhase.IDLE, ConnectionPhase.SCANNING -> return
            else -> Unit
        }
        Log.i(TAG, "link lost: $reason")
        _failure.value = reason
        _phase.value = ConnectionPhase.FAILED
        connectJob?.cancel()
        stopLivePipeline()
        ble.disconnect()
    }

    private fun leaveLiveForReconnect() {
        stopLivePipeline()
        ble.disconnect()
        _failure.value = null
        _phase.value = ConnectionPhase.FAILED
    }

    private fun stopLivePipeline() {
        keepaliveJob?.cancel()
        keepaliveJob = null
        endGimbalStick()
        failAllWaiters(IllegalStateException("the camera disconnected"))
        datalink?.close()
        datalink = null
        decoder.reset()
        videoPackets = 0
        accessUnits = 0
        framesEnqueued = 0
        droppedIncomplete = 0
        decoderErrors = 0
        hasVideoFormat = false
        streamStartedAt = null
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
            0x0201, 0x0202, 0x021E, 0x0222, 0x0224, 0x0228, 0x022A, 0x022C,
            0x0218, 0x0230, 0x0232, 0x0242, 0x028E, 0x029F, 0x02A0,
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

/** First-picture resend is 2 s; after packets, only a missing format at 5 s — never 1 Hz. */
internal object LiveViewEnablePolicy {
    const val FIRST_PICTURE_RESEND_MS = 2_000L
    const val STALLED_FORMAT_RESEND_MS = 5_000L
    const val FORMAT_STALL_MS = 2_000L

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
