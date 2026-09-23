package com.opencapture.openpocketcine.multiview

import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.opencapture.monitorui.MultiviewArrangement
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan
import com.opencapture.openpocketcine.feed.FeedEffectsRenderPlanFactory
import com.opencapture.openpocketcine.session.BleLink
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.DatalinkDriver
import com.opencapture.openpocketcine.session.DumlFrame
import com.opencapture.openpocketcine.session.FoundCamera
import com.opencapture.openpocketcine.session.GimbalStickMapping
import com.opencapture.openpocketcine.session.HevcDecoder
import com.opencapture.openpocketcine.session.LiveViewEnablePolicy
import com.opencapture.openpocketcine.session.StatusExtras
import com.opencapture.openpocketcine.session.interruptibleDatalinkOpen
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

private const val TAG = "Multiview"

/** Model support from the shared core (`MulticamSupport`). Cached per model identity. */
data class MulticamSupportInfo(val appears: Boolean, val preview: Boolean, val missingRoleQueryE0: Boolean)

private val supportCache = HashMap<String, MulticamSupportInfo>()

fun FoundCamera.multicamSupport(): MulticamSupportInfo {
    val key = "${modelId ?: -1}|$name|${model.name}"
    synchronized(supportCache) { supportCache[key]?.let { return it } }
    val request = JSONObject().put("name", model.name.ifEmpty { name })
    modelId?.let { request.put("modelId", it) }
    val raw = if (SwiftCore.isAvailable) SwiftCore.multicamDecision("support", request.toString()) else null
    val json = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
    val info = MulticamSupportInfo(
        appears = json?.optBoolean("appears") ?: false,
        preview = json?.optBoolean("preview") ?: false,
        missingRoleQueryE0 = json?.optBoolean("missingRoleQueryE0") ?: false,
    )
    synchronized(supportCache) { supportCache[key] = info }
    return info
}

val FoundCamera.appearsInMultiview: Boolean get() = multicamSupport().appears
val FoundCamera.hasMultiviewPreview: Boolean get() = multicamSupport().preview

/** iOS `MultiviewLayout` raw values; persisted in the stage. */
enum class MultiviewLayout(val raw: String) {
    GRID("2 × 2 grid"),
    CENTER_STAGE("Center stage");

    val arrangement: MultiviewArrangement
        get() = if (this == GRID) MultiviewArrangement.GRID else MultiviewArrangement.CENTER_STAGE

    companion object {
        fun from(raw: String): MultiviewLayout = entries.firstOrNull { it.raw == raw } ?: CENTER_STAGE
    }
}

/** Each tile owns one bounded repair ladder (core `MultiviewRecovery`). A healthy take resets its budget. */
class MultiviewRecoveryLadder {
    private var handle = if (SwiftCore.isAvailable) SwiftCore.multiviewRecoveryCreate() else 0L
    fun action(snapshotJSON: String): String =
        if (handle == 0L) "none" else SwiftCore.multiviewRecoveryCall(handle, "action", snapshotJSON) ?: "none"
    fun beginRejoin(): Boolean = handle != 0L && SwiftCore.multiviewRecoveryCall(handle, "beginRejoin", "{}") == "true"
    fun fail() { if (handle != 0L) SwiftCore.multiviewRecoveryCall(handle, "fail", "{}") }
    val failed: Boolean get() = handle != 0L && SwiftCore.multiviewRecoveryCall(handle, "failed", "{}") == "true"
    fun reset() { if (handle != 0L) SwiftCore.multiviewRecoveryCall(handle, "reset", "{}") }
    fun close() {
        if (handle != 0L) SwiftCore.multiviewRecoveryDestroy(handle)
        handle = 0L
    }
}

/**
 * Android Multiview. iOS `MultiviewSession`: one shared network, up to four
 * cameras, each with its own BLE provisioning, verified LAN datalink, decoder
 * and repair ladder. State is Compose snapshot state, mutated on Main only.
 */
class MultiviewSession(
    context: Context,
    private val saveStage: (MultiviewStageStore.Stage?) -> Boolean = { MultiviewStageStore.save(context, it) },
    private val networkStore: MultiviewNetworkStore = MultiviewNetworkStore(context),
    private val resetCamera: (suspend (MultiviewStageStore.Camera) -> Boolean)? = null,
) {
    private val app = context.applicationContext

    /** Nested, not inner: Compose needs stability metadata on this type (an inner class has none). */
    class Tile(val index: Int, private val app: Context) {
        val id: String = UUID.randomUUID().toString()
        val decoder = HevcDecoder()
        var liveModel by mutableStateOf<AppModel?>(null)
        var driver: DatalinkDriver? = null
            set(value) {
                field = value
                liveModel?.session?.updateMultiview(camera, value, latestSettings)
            }
        var connecting by mutableStateOf(false)
        var experimentalNetwork by mutableStateOf(false)
        var networkVerified by mutableStateOf(false)
        var cameraAddress = ""
        var identity: ByteArray? = null
        /** Latest reply per DUML key with its receive time. */
        val responses = HashMap<Int, Pair<DumlFrame, Long>>()
        var camera by mutableStateOf<FoundCamera?>(null)
        var status by mutableStateOf("Add camera")
        var failureMessage by mutableStateOf<String?>(null)
        val recovery = MultiviewRecoveryLadder()
        var repairJob: Job? = null
        var recovering by mutableStateOf(false)
        var pathLostAt: Long? = null
        var checkForegroundDecoder = false
        var foregroundRepairAt: Long? = null
        var settings by mutableStateOf(CameraStatus())
        var pose = GimbalStickMapping()
        var poseViewFlip by mutableStateOf(false)
        var latestSettings = CameraStatus()
        private var settingsPublishedAt = 0L
        var lutEnabled by mutableStateOf(false)
        internal var plan by mutableStateOf(FeedEffectsRenderPlan.IDENTITY)
        var lutCaption by mutableStateOf("Auto LUT")
        var hasPicture by mutableStateOf(false)
        var publishing by mutableStateOf(false)
        var recordingBusy by mutableStateOf(false)
        var recordingAvailable by mutableStateOf(false)
        var recordingNote by mutableStateOf<String?>(null)
        var controlHost by mutableStateOf<String?>(null)
        /** Active flag and elapsed-realtime receive time of the latest `02/80` report. */
        var recordingObservation by mutableStateOf<Pair<Boolean, Long>?>(null)
        var lastEnable = 0L
        /** Last camera SET on this transport (recording). The watchdog holds for its GOP reset. */
        var lastCommandAt = 0L
        var enableSends = 0
        var previewStarted: Long? = null
        /** The tile's feed (or the borrowed Live View) currently owns a decoder surface. */
        var surfaceMounted = false
        private var inputOwner = 0L

        val timecodeReadout: String?
            get() {
                val cam = camera ?: return null
                if (cam.model.family == "nano") return null
                return settings.timecode?.takeIf { it.isNotEmpty() }
            }

        fun updateSettings(frame: DumlFrame) {
            val cam = camera ?: return
            val prev = latestSettings
            val json = SwiftCore.applyStatus(frame.cmdSet, frame.cmdId, frame.payload, prev.toJson())
            var next = if (json != null) CameraStatus.fromJson(json) else prev
            if (json == null || !next.hasHudFields) next = next.preservingExtras(prev)
            next = StatusExtras.apply(frame, next, cam.model.name, cam.model.family)
            latestSettings = next
            if (frame.cmdSet == 0x04 && frame.cmdId == 0x05) pose = pose.applyAttitude(frame.payload)
            if (frame.cmdSet == 0x04 && frame.cmdId == 0x27) pose = pose.noteBodyFace(next.gimbalFace)
            pose = pose.copy(selfieFlip = next.selfieFlip == true)
            if (liveModel == null) poseViewFlip = pose.poseViewFlip
            val colorChanged = next.colorMode != settings.colorMode
            val now = SystemClock.elapsedRealtime()
            if (colorChanged || now - settingsPublishedAt >= 200) {
                if (settings != next) settings = next
                settingsPublishedAt = now
            }
            if (colorChanged && liveModel == null) updateLUT()
        }

        fun toggleLUT() {
            lutEnabled = !lutEnabled
            updateLUT()
        }

        fun updateLUT() {
            val cam = camera
            val result = FeedEffectsRenderPlanFactory.multiviewAutoLut(
                app, lutEnabled, settings.colorMode, cam?.model?.family ?: "pocket", cam?.model?.name,
            )
            plan = result.first
            lutCaption = result.second
        }

        /** Claims decoder input for a new transport; the previous one can no longer feed it. */
        fun wire(next: DatalinkDriver) {
            inputOwner = decoder.claimInputOwner()
            val owner = inputOwner
            next.onVideoEpochChanged = { epoch -> decoder.advanceInputEpoch(owner, epoch) }
            next.onReferenceDiscontinuity = { epoch -> decoder.noteReferenceDiscontinuity(owner, epoch) }
        }

        fun claimedInput(): Long = inputOwner

        fun reset() {
            repairJob?.cancel()
            repairJob = null
            recovering = false
            recovery.reset()
            pathLostAt = null
            foregroundRepairAt = null
            failureMessage = null
            driver?.close()
            driver = null
            camera = null
            networkVerified = false
            experimentalNetwork = false
            settings = CameraStatus()
            latestSettings = CameraStatus()
            pose = GimbalStickMapping()
            poseViewFlip = false
            lutEnabled = false
            updateLUT()
            previewStarted = null
            identity = null
            controlHost = null
            recordingObservation = null
            recordingAvailable = false
            responses.clear()
            recordingNote = null
            hasPicture = false
            publishing = false
            enableSends = 0
            lastEnable = 0L
            decoder.reset()
            status = "Add camera"
        }
    }

    val tiles: List<Tile> = List(4) { Tile(it, app) }
    private val scanner = BleLink(app)
    val found = mutableStateListOf<FoundCamera>()
    var busy by mutableStateOf(false)
    var ready by mutableStateOf(false)
    var ssid by mutableStateOf("")
    var usePhoneHotspot by mutableStateOf(false)
    var password by mutableStateOf("")
    val networks = mutableStateListOf<String>()
    var networkMessage by mutableStateOf("Choose a camera to scan for Wi-Fi.")
    var networkScanning by mutableStateOf(false)
    private var preparedCamera: String? = null
    var groupRecordingBusy by mutableStateOf(false)
    var groupRecordingNote by mutableStateOf<String?>(null)
    val recordingTiles: List<Tile> get() = tiles.filter { it.camera != null }
    val anyRecording: Boolean get() = recordingTiles.any { it.recordingObservation?.first == true }
    val canRecordTogether: Boolean
        get() = !busy && !groupRecordingBusy && recordingTiles.isNotEmpty() &&
            recordingTiles.all { it.recordingAvailable && !it.recordingBusy }

    var networkConfigured by mutableStateOf(false)
    var configuringNetwork by mutableStateOf(false)
    var networkSetupError by mutableStateOf<String?>(null)
    var applicationActive = true
        private set
    private var foregroundAt = 0L
    var host by mutableStateOf("")
    var error by mutableStateOf<String?>(null)
    var layout by mutableStateOf(MultiviewLayout.CENTER_STAGE)
    var fill by mutableStateOf(false)
    var focusedIndex by mutableStateOf(0)
    var closing by mutableStateOf(false)
    val connectingCameras: Boolean get() = tiles.any { it.connecting }
    val path = SharedWiFi(app)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val provisioners = HashMap<String, MultiviewProvisioner>()
    private val searches = HashMap<String, MultiviewDiscovery>()
    private val connectionJobs = HashMap<String, Job>()
    private var hostJoin: kotlinx.coroutines.Deferred<Unit>? = null
    private val addressReservations = HashMap<String, String>()
    private var pendingReset: List<MultiviewStageStore.Camera> = emptyList()
    private val stationResets = HashMap<String, kotlinx.coroutines.Deferred<Boolean>>()
    private var cleanupJournalWritten = false
    private var networkCamera: MultiviewProvisioner? = null
    private var scanJob: Job? = null
    private var monitor: Job? = null
    private var running = false
    private val joinPolicy: JSONObject by lazy {
        SwiftCore.multicamDecision("joinPolicy", "{}")?.let { runCatching { JSONObject(it) }.getOrNull() }
            ?: JSONObject()
    }
    private val maximumJoinAttempts get() = joinPolicy.optInt("maximumAttempts", 3)
    private val prepareSettleMs get() = joinPolicy.optLong("prepareSettleSeconds", 10) * 1_000
    private val joinReplyTimeoutMs get() = (joinPolicy.optDouble("replyTimeoutSeconds", 45.0) * 1_000).toLong()
    private val retryDelayMs get() = joinPolicy.optLong("retryDelaySeconds", 5) * 1_000

    // --- Borrowed Live View -------------------------------------------------------------------

    fun openLiveView(tile: Tile) {
        val camera = tile.camera ?: return
        if (tile.controlHost == null || tile.recovering) return
        val model = AppModel(app, borrowing = tile.decoder)
        model.session.updateMultiview(camera, tile.driver, tile.latestSettings)
        model.session.adoptMultiviewPose(tile.pose)
        model.setBorrowedLut(tile.lutEnabled)
        tile.liveModel = model
    }

    fun closeLiveView() {
        for (tile in tiles) {
            val model = tile.liveModel ?: continue
            tile.lutEnabled = model.borrowedLutEnabled()
            model.session.releaseMultiview()
            model.multiviewExit = null
            model.close()
            tile.liveModel = null
            tile.poseViewFlip = tile.pose.poseViewFlip
            tile.updateLUT()
        }
        // Every tile feed remounts with a fresh surface. A fresh codec takes the IRAP this
        // enable requests, rather than waiting for the watchdog to find a frozen picture.
        for (tile in tiles) {
            val driver = tile.driver ?: continue
            val camera = tile.camera ?: continue
            if (!tile.publishing) continue
            tile.decoder.rebuildPresentation()
            sendEnable(tile, driver, camera)
            tile.checkForegroundDecoder = true
        }
        foregroundAt = SystemClock.elapsedRealtime()
    }

    // --- Lifecycle -------------------------------------------------------------------------------

    fun start() {
        if (running) return
        running = true
        host = ""
        ready = false
        networkConfigured = false
        ssid = ""
        password = ""
        usePhoneHotspot = false
        path.hotspot = false
        restoreStage()
        networks.clear()
        networkStore.savedNetworks().filter { !it.hotspot }.forEach { if (it.ssid !in networks) networks += it.ssid }
        path.currentSsid()?.takeIf { !it.lowercase().startsWith("osmo") && it !in networks }?.let { networks += it }
        scan()
        monitor = scope.launch {
            while (isActive) {
                delay(1_000)
                ready = path.address(usePhoneHotspot) != null
                for (tile in tiles) {
                    // The camera stops video ~10 s after the last registration; this
                    // heartbeat is never gated by UI or repair state.
                    tile.driver?.let { driver -> withContext(Dispatchers.IO) { driver.keepalive() } }
                    tile.recordingAvailable = tile.controlHost != null &&
                        tile.recordingObservation?.let { SystemClock.elapsedRealtime() - it.second < 3_000 } == true
                    monitorPreview(tile)
                }
            }
        }
    }

    fun scan() {
        scanJob?.cancel()
        scanJob = scope.launch {
            scanner.startScan()
            scanner.found.collectLatest { list ->
                for (camera in list) if (found.none { it.id == camera.id }) found += camera
            }
        }
    }

    fun setApplicationActive(active: Boolean) {
        applicationActive = active
        if (active) {
            foregroundAt = SystemClock.elapsedRealtime()
            for (tile in tiles) if (tile.publishing) tile.checkForegroundDecoder = true
        }
        // Keep camera assignments and sockets. Foreground watchdog owns repair.
    }

    fun stop() {
        persistStage()
        hostJoin?.cancel()
        hostJoin = null
        connectionJobs.values.forEach { it.cancel() }
        connectionJobs.clear()
        provisioners.values.forEach { it.close() }
        provisioners.clear()
        closeLiveView()
        running = false
        setApplicationActive(true)
        searches.values.forEach { it.cancel() }
        searches.clear()
        monitor?.cancel()
        scanJob?.cancel()
        scanner.stopScan()
        releaseNetworkCameraLink()
        ready = false
        password = ""
        for (tile in tiles) {
            tile.repairJob?.cancel()
            tile.driver?.close()
            tile.driver = null
            tile.decoder.reset()
        }
    }

    /** Final teardown after [closeStage]; the session is not reused. */
    fun dispose() {
        stop()
        path.release()
        scanner.close()
        tiles.forEach { it.recovery.close() }
        scope.cancel()
    }

    // --- Network setup ---------------------------------------------------------------------------

    fun selectNetworkSource(hotspot: Boolean) {
        if (configuringNetwork || tiles.any { it.camera != null }) return
        usePhoneHotspot = hotspot
        path.hotspot = hotspot
        ssid = ""
        password = ""
        invalidateNetworkConfirmation()
    }

    fun selectNetwork(name: String) {
        if (configuringNetwork || tiles.any { it.camera != null }) return
        if (ssid != name) {
            ssid = name
            password = networkStore.load(name, usePhoneHotspot)?.password ?: ""
        }
        invalidateNetworkConfirmation()
    }

    private fun invalidateNetworkConfirmation() {
        networkConfigured = false
        networkSetupError = null
        host = ""
        ready = false
    }

    private suspend fun joinSharedNetwork() {
        hostJoin?.let { return it.await() }
        val task = scope.async { performHostJoin() }
        hostJoin = task
        try {
            task.await()
        } finally {
            if (hostJoin === task) hostJoin = null
        }
        if (!running) throw CancellationException("multiview closed")
    }

    private suspend fun performHostJoin() {
        if (ssid.isEmpty()) throw MultiviewFailure.Network()
        // The host phone must not try joining its own hotspot. Its local bridge
        // may appear only after the first camera associates.
        if (usePhoneHotspot) return
        if (!path.join(ssid, password)) throw MultiviewFailure.Network()
        val address = path.address(false) ?: throw MultiviewFailure.Network()
        host = address
        ready = true
    }

    suspend fun configureNetwork(): Boolean {
        if (busy || configuringNetwork || tiles.any { it.camera != null }) return false
        configuringNetwork = true
        networkSetupError = null
        try {
            if (ssid.isEmpty() || ssid.toByteArray().size > 32 || password.toByteArray().size > 63) {
                throw MultiviewFailure.Message("Check the network name and password.")
            }
            joinSharedNetwork()
            networkStore.save(ssid, password, usePhoneHotspot)
            networkConfigured = true
            persistStage()
            return true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            networkSetupError = error.message
            return false
        } finally {
            configuringNetwork = false
        }
    }

    /** Optional: read nearby Wi-Fi names through one camera. Its role change is journaled first. */
    suspend fun prepareNetworks(camera: FoundCamera) {
        if (!camera.hasMultiviewPreview || busy || !running || closing) return
        busy = true
        networkScanning = true
        networkMessage = "Connecting · approve on camera if asked"
        try {
            if (preparedCamera != camera.id) {
                releaseNetworkCameraLink()
                val client = MultiviewProvisioner(app)
                networkCamera = client
                client.onWiFiScan = { names ->
                    for (name in names) if (name !in networks) networks += name
                    val sorted = networks.sortedWith(String.CASE_INSENSITIVE_ORDER)
                    networks.clear()
                    networks.addAll(sorted)
                }
                client.connect(camera)
                preparedCamera = camera.id
                if (camera.model.family == "nano") client.exchange(SwiftCore.CMD_SESSION_5310)
            }
            val client = networkCamera ?: throw MultiviewFailure.Unavailable()
            networkMessage = "Preparing camera Wi-Fi"
            // A lost setter reply can still mean the camera changed roles.
            if (!recordStationChange(camera)) {
                throw MultiviewFailure.Message("Could not save camera Wi-Fi cleanup. Try again.")
            }
            val role = client.exchange(SwiftCore.CMD_MULTICAM_STATION_MODE, "1")
            if (role.payload.firstOrNull()?.toInt() != 0) throw MultiviewFailure.Rejected()
            delay(10_000)
            networkMessage = "Looking for Wi-Fi networks"
            client.exchange(SwiftCore.CMD_MULTICAM_WIFI_SCAN, timeoutMs = 8_000)
            delay(6_000)
            networkMessage = if (networks.isEmpty()) {
                "No networks found. Retry the scan or enter a hidden network."
            } else {
                "Choose the same Wi-Fi for this device and your cameras."
            }
        } catch (error: CancellationException) {
            networkMessage = "Could not scan. Retry or enter your network name."
            finishNetworkScan(camera)
            throw error
        } catch (_: Exception) {
            networkMessage = "Could not scan. Retry or enter your network name."
        }
        finishNetworkScan(camera)
    }

    private suspend fun finishNetworkScan(camera: FoundCamera) {
        releaseNetworkCameraLink()
        busy = false
        networkScanning = false
        pendingReset.firstOrNull { it.id == camera.id }?.let { saved ->
            val scanMessage = networkMessage
            networkMessage = "Returning camera to its Wi-Fi"
            if (!resetStationOnce(saved)) {
                networkSetupError =
                    "Camera Wi-Fi could not be restored. Keep it powered on and close Multiview to retry."
            }
            networkMessage = scanMessage
        }
        if (running && !closing) scan()
    }

    private fun recordStationChange(camera: FoundCamera): Boolean {
        val saved = MultiviewStageStore.Camera(
            slot = 0, id = camera.id, name = camera.name, modelId = camera.modelId,
            bleAddress = camera.address, identity = null, address = "", experimental = false, lutEnabled = false,
        )
        pendingReset = MultiviewStageStore.cleanupTargets(pendingReset, listOf(saved))
        return persistStage()
    }

    /** The setup popup cancels its job first; closing the BLE link unblocks a pending connect. */
    fun cancelNetworkScan() {
        if (!networkScanning) return
        releaseNetworkCameraLink()
    }

    fun releaseNetworkCamera() {
        if (busy) return
        releaseNetworkCameraLink()
        if (running) scan()
    }

    private fun releaseNetworkCameraLink() {
        networkCamera?.close()
        networkCamera = null
        preparedCamera = null
    }

    // --- Cameras ---------------------------------------------------------------------------------

    fun enqueueAdd(camera: FoundCamera, tile: Tile, experimental: Boolean = false) {
        if (!running || !networkConfigured || closing || tile.camera != null || tile.connecting) return
        connectionJobs[tile.id]?.cancel()
        connectionJobs[tile.id] = scope.launch { add(camera, tile, experimental) }
    }

    suspend fun add(camera: FoundCamera, tile: Tile, experimental: Boolean = false) {
        if (!camera.appearsInMultiview || !(camera.hasMultiviewPreview || experimental)) {
            error = "Multiview preview is not available for this camera model yet."
            return
        }
        if (!running || !networkConfigured || closing || busy || tile.connecting || tile.camera != null ||
            tiles.any { it.camera?.id == camera.id }
        ) return
        tile.connecting = true
        val client = MultiviewProvisioner(app)
        provisioners[tile.id] = client
        tile.camera = camera
        tile.experimentalNetwork = experimental
        tile.networkVerified = false
        tile.failureMessage = null
        tile.status = "Connecting · approve on camera"
        persistStage()
        var stage = "host Wi-Fi"
        try {
            joinSharedNetwork()
            stage = "Bluetooth pairing"
            client.connect(camera)
            if (camera.model.family == "nano") {
                tile.status = "Waking camera Wi-Fi"
                val wake = client.exchange(SwiftCore.CMD_SESSION_5310).payload.map { it.toInt() and 0xFF }
                if (wake != listOf(1, 0, 0, 0)) {
                    throw MultiviewFailure.Message(
                        "The Nano did not confirm its Wi-Fi wake. Keep it powered on and try again.")
                }
                delay(1_000)
            }
            stage = "camera Wi-Fi identity"
            val identity = readIdentity(client)
            if (identity.size <= 2 || identity[0].toInt() != 0) throw MultiviewFailure.Rejected()
            if (camera.hasMultiviewPreview && !experimental) {
                tile.status = "Selecting Video mode"
                client.send(SwiftCore.CMD_MULTICAM_VIDEO_MODE)
                delay(2_000)
            }
            stage = "station role"
            val role = client.exchange(SwiftCore.CMD_MULTICAM_WIFI_WORK_MODE).payload
            val allowMissing = experimental || (camera.multicamSupport().missingRoleQueryE0 && role.hexString() == "e0")
            val decision = SwiftCore.multicamDecision(
                "stationDecision",
                JSONObject().put("reply", role.hexString()).put("allowMissingQuery", allowMissing).toString(),
            ) ?: "reject"
            val missingRoleQuery = decision == "setWithoutReadback"
            log("multiview: station experimental=$experimental decision=$decision")
            if (decision != "alreadyStation") {
                if (decision == "reject") {
                    throw MultiviewFailure.Message(
                        "This camera did not report a supported Wi-Fi mode. Shared Wi-Fi setup is experimental for this model.")
                }
                val switched = client.exchange(SwiftCore.CMD_MULTICAM_STATION_MODE, "1").payload
                val accepted = SwiftCore.multicamDecision(
                    "acceptsSetter",
                    JSONObject().put("reply", switched.hexString()).put("missingQuery", missingRoleQuery).toString(),
                ) == "true"
                if (!accepted) throw MultiviewFailure.Message("The camera did not accept shared Wi-Fi mode.")
                // The bounded experimental path also permits the captured missing-getter shape.
                // Its join result and subsequent LAN identity check remain required.
                if (!missingRoleQuery) {
                    var stationReady = false
                    for (poll in 0 until 6) {
                        val reported = client.exchange(SwiftCore.CMD_MULTICAM_WIFI_WORK_MODE).payload.hexString()
                        if (reported == "0001") {
                            stationReady = true
                            break
                        }
                        if (reported != "0000") throw MultiviewFailure.Rejected()
                        delay(2_000)
                    }
                    if (!stationReady) {
                        throw MultiviewFailure.Message("Camera Wi-Fi is still starting. Retry with the camera nearby.")
                    }
                }
            }
            tile.identity = identity
            stage = "camera Wi-Fi join"
            tile.status = "Waiting for camera Wi-Fi"
            delay(prepareSettleMs)
            var attempt = 1
            joinLoop@ while (attempt <= maximumJoinAttempts) {
                tile.status = "Joining Wi-Fi · attempt $attempt of $maximumJoinAttempts"
                val joined = try {
                    client.exchange(SwiftCore.CMD_MULTICAM_JOIN, "$ssid\u001f$password", joinReplyTimeoutMs)
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    log("multiview: join reply timeout; checking verified LAN identity")
                    // A lost BLE reply is not proof that association failed.
                    if (!usePhoneHotspot || path.address(true) != null) {
                        try {
                            discoverPreview(tile, camera, identity)
                            networkStore.save(ssid, password, usePhoneHotspot)
                            return
                        } catch (error: CancellationException) {
                            throw error
                        } catch (_: Exception) {
                            // Not found on the LAN: fall through to the bounded join retry.
                        }
                    }
                    if (attempt < maximumJoinAttempts) {
                        delay(retryDelayMs)
                        attempt += 1
                        continue@joinLoop
                    }
                    tile.identity = null
                    throw MultiviewFailure.Message("Camera Wi-Fi did not respond. Retry setup with the camera nearby.")
                }
                // Only the fixed-size result is logged, never the credential request.
                log("multiview: Wi-Fi join attempt=$attempt result=${joined.payload.take(4).toByteArray().hexString()}")
                when (
                    SwiftCore.multicamDecision(
                        "joinDecision",
                        JSONObject().put("reply", joined.payload.hexString()).put("attempt", attempt).toString(),
                    )
                ) {
                    "connected" -> break@joinLoop
                    "retry" -> {
                        tile.status = "Retrying Wi-Fi connection"
                        delay(retryDelayMs)
                        attempt += 1
                    }
                    else -> {
                        tile.identity = null
                        throw MultiviewFailure.Message(
                            "The camera could not join the shared Wi-Fi. Check its name and password, and make sure the network is in range.")
                    }
                }
            }
            tile.identity = identity
            if (usePhoneHotspot) {
                tile.status = "Waiting for Personal Hotspot"
                val deadline = SystemClock.elapsedRealtime() + 15_000
                while (path.address(true) == null && SystemClock.elapsedRealtime() < deadline) delay(250)
                if (path.address(true) == null) {
                    throw MultiviewFailure.Message(
                        "Turn on the hotspot and let other devices join, then retry. The hotspot network is not available yet.")
                }
            }
            networkStore.save(ssid, password, usePhoneHotspot)
            client.close()
            stage = "LAN discovery"
            discoverPreview(tile, camera, identity)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (!running) return
            tile.driver?.close()
            tile.driver = null
            tile.status = "Could not connect"
            tile.failureMessage = error.message ?: "Could not connect"
            log("multiview: add failed stage=$stage error=${error.javaClass.simpleName}")
            // Keep the tile available for discovery retry after a successful join.
        } finally {
            tile.connecting = false
            client.close()
            provisioners.remove(tile.id)
            if (running) persistStage()
        }
    }

    /**
     * A Pocket just returned to its own AP by [resetStation] ignored this query until the
     * `53/10` Wi-Fi wake that single-camera pairing always sends (Pocket 4 Pro, Android,
     * 2026-09-23). One wake and one retry; any other failure still stops setup.
     */
    private suspend fun readIdentity(client: MultiviewProvisioner): ByteArray =
        try {
            client.exchange(SwiftCore.CMD_GET_WIFI_SSID).payload
        } catch (_: MultiviewFailure.Timeout) {
            log("multiview: identity reply missing; sending Wi-Fi wake once")
            try {
                client.exchange(SwiftCore.CMD_SESSION_5310, timeoutMs = 2_000)
            } catch (_: MultiviewFailure) {
            }
            delay(600)
            client.exchange(SwiftCore.CMD_GET_WIFI_SSID).payload
        }

    suspend fun reconnect(tile: Tile) {
        val camera = tile.camera ?: return
        if (busy || tile.connecting || tile.recovering) return
        tile.failureMessage = null
        tile.recovery.reset()
        if (tile.identity != null) {
            connectPreview(tile)
            if (running && tile.failureMessage != null) readd(tile)
        } else {
            tile.camera = null
            add(camera, tile, tile.experimentalNetwork)
        }
    }

    private suspend fun readd(tile: Tile) {
        val camera = tile.camera ?: return
        val experimental = tile.experimentalNetwork
        val lut = tile.lutEnabled
        if (!remove(tile)) return
        tile.lutEnabled = lut
        add(camera, tile, experimental)
    }

    suspend fun tryExperimentalNetwork(tile: Tile) {
        val camera = tile.camera ?: return
        if (!remove(tile)) return
        add(camera, tile, experimental = true)
    }

    suspend fun connectPreview(tile: Tile) {
        val camera = tile.camera ?: return
        val identity = tile.identity ?: return
        if (!running || closing || busy || tile.connecting) return
        tile.connecting = true
        try {
            discoverPreview(tile, camera, identity)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            if (!running) return
            tile.driver?.close()
            tile.driver = null
            tile.publishing = false
            tile.controlHost = null
            tile.status = "Could not connect preview"
            tile.failureMessage = "Could not restore preview. Tap Reconnect to try again."
            tile.recovery.fail()
        } finally {
            tile.connecting = false
            if (running) persistStage()
        }
    }

    private suspend fun discoverPreview(tile: Tile, camera: FoundCamera, identity: ByteArray) {
        val search = MultiviewDiscovery(path)
        searches[tile.id] = search
        try {
            tile.driver?.close()
            tile.driver = null
            tile.controlHost = null
            tile.recordingAvailable = false
            val excluded = tiles.filter { it.id != tile.id }.mapNotNull { it.controlHost }.toSet()
            if (SharedWiFi.validAddress(tile.cameraAddress)) {
                try {
                    openPreview(tile, camera, identity)
                    return
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                }
            }
            for (attempt in 1..2) {
                if (!running) throw CancellationException("multiview closed")
                tile.status = "Finding camera on Wi-Fi · $attempt of 2"
                val candidates = search.candidates(excluded)
                for (address in candidates) {
                    if (!running) throw CancellationException("multiview closed")
                    tile.cameraAddress = address
                    try {
                        openPreview(tile, camera, identity)
                        return
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        tile.driver?.close()
                        tile.driver = null
                        tile.controlHost = null
                    }
                }
                if (attempt == 1) delay(3_000)
            }
            throw MultiviewFailure.Message(
                "Could not find this camera on the shared Wi-Fi. Check that both devices use the same network and that client isolation is off, then tap Reconnect.")
        } finally {
            search.cancel()
            searches.remove(tile.id)
        }
    }

    private suspend fun openPreview(tile: Tile, camera: FoundCamera, identity: ByteArray) {
        val address = tile.cameraAddress
        val owner = addressReservations[address]
        if (owner != null && owner != tile.id) throw MultiviewFailure.Unavailable()
        addressReservations[address] = tile.id
        try {
            if (!running || !SharedWiFi.validAddress(address) ||
                tiles.any { it.id != tile.id && it.controlHost == address }
            ) {
                throw MultiviewFailure.Message("Camera discovery returned an unavailable address. Tap Reconnect to search again.")
            }
            tile.driver?.close()
            tile.driver = null
            tile.controlHost = null
            tile.responses.clear()
            tile.recordingObservation = null
            tile.recordingAvailable = false
            tile.publishing = false
            tile.previewStarted = null
            tile.enableSends = 0
            tile.lastEnable = 0L
            if (tile.hasPicture) tile.decoder.beginIDRHold() else tile.decoder.reset()
            tile.status = "Connecting normal preview"
            val driver = DatalinkDriver(
                path, camera.model.datalinkPort, camera.model.tcpPoke, camera.model.pairingToken,
                cameraModel = camera.model, host = address,
            )
            tile.wire(driver)
            tile.driver = driver
            driver.onStatusFrame = { frame ->
                if (tile.driver === driver) {
                    if ((frame.flags and 0x80) != 0) {
                        if (tile.responses.size > 128) tile.responses.clear()
                        tile.responses[frame.key] = frame to SystemClock.elapsedRealtime()
                    }
                    if (tile.controlHost != null) {
                        tile.updateSettings(frame)
                        tile.liveModel?.session?.receiveMultiview(frame)
                        if (frame.cmdSet == 0x02 && frame.cmdId == 0x80 && frame.payload.size >= 13) {
                            val json = SwiftCore.applyStatus(frame.cmdSet, frame.cmdId, frame.payload, CameraStatus().toJson())
                            val recording = json?.let { CameraStatus.fromJson(it).isRecording } ?: false
                            tile.recordingObservation = recording to SystemClock.elapsedRealtime()
                        }
                    }
                }
            }
            withTimeout(STATION_OPEN_MS) { interruptibleDatalinkOpen { driver.open(identityOnly = true) } }
            val sent = SystemClock.elapsedRealtime()
            driver.sendCommand(SwiftCore.CMD_GET_WIFI_SSID)
            val deadline = sent + 8_000
            var reply: DumlFrame? = null
            while (SystemClock.elapsedRealtime() < deadline) {
                tile.responses[IDENTITY_KEY]?.takeIf { it.second >= sent }?.let { reply = it.first }
                if (reply != null) break
                delay(50)
            }
            if (reply?.payload?.contentEquals(identity) != true) {
                throw MultiviewFailure.Message("This network connection did not identify the selected camera.")
            }
            if (!running) throw CancellationException("multiview closed")
            tile.networkVerified = true
            if (!camera.hasMultiviewPreview) {
                driver.close()
                tile.driver = null
                tile.failureMessage = null
                tile.status = "Wi-Fi join verified · Preview not supported yet"
                log("multiview: experimental LAN identity verified; preview unavailable")
                return
            }
            withContext(Dispatchers.IO) { driver.completeRegistration() }
            tile.controlHost = address
            tile.liveModel?.session?.updateMultiview(camera, driver, tile.latestSettings)
            tile.failureMessage = null
            log("multiview: station camera identity verified")
            val input = tile.claimedInput()
            driver.onAccessUnit = { au, epoch ->
                if (tile.decoder.decode(au, input, epoch)) {
                    if (!tile.hasPicture || tile.status != LIVE_STATUS) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            if (tile.driver === driver) {
                                if (!tile.hasPicture) log("multiview: station preview enqueued")
                                tile.hasPicture = true
                                tile.status = LIVE_STATUS
                            }
                        }
                    }
                }
            }
            tile.decoder.onParameterSetsChanged = {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    if (tile.driver === driver && tile.controlHost != null) sendEnable(tile, driver, camera)
                }
            }
            // Subscribe is fire-and-forget; an enable in the same burst is ignored.
            delay(SUBSCRIBE_SETTLE_MS)
            withContext(Dispatchers.IO) {
                val nanoGate = camera.model.usesNanoLiveViewGate
                if (nanoGate) driver.sendNanoGate(start = true)
                if (camera.model.sendsLiveViewPrepare) {
                    driver.sendCommand(SwiftCore.CMD_TAP_FOCUS_HINT)
                }
                driver.startLiveView(camera.model.liveViewEnableReceiver)
            }
            tile.lastEnable = SystemClock.elapsedRealtime()
            tile.enableSends = 1
            tile.publishing = true
            tile.previewStarted = SystemClock.elapsedRealtime()
            if (!tile.hasPicture) tile.status = "Waiting for video"
        } finally {
            if (addressReservations[address] == tile.id) addressReservations.remove(address)
        }
    }

    private fun sendEnable(tile: Tile, driver: DatalinkDriver, camera: FoundCamera) {
        scope.launch(Dispatchers.IO) { driver.startLiveView(camera.model.liveViewEnableReceiver) }
        tile.lastEnable = SystemClock.elapsedRealtime()
        tile.enableSends += 1
    }

    // --- Watchdog ----------------------------------------------------------------------------------

    private fun monitorPreview(tile: Tile) {
        val driver = tile.driver ?: return
        val now = SystemClock.elapsedRealtime()
        if (!applicationActive || now - foregroundAt <= 3_000 || busy || tile.recovering ||
            tile.recovery.failed || !tile.publishing || !tile.surfaceMounted
        ) return
        fun age(at: Long?): Double? = at?.takeIf { it > 0L }?.let { (now - it) / 1000.0 }
        val pathReady = path.address(usePhoneHotspot) != null
        val videoAge = driver.lastVideoPacketAt?.let { now - it }
        val auAge = driver.lastAccessUnitAt?.let { now - it }
        val udpAlive = (videoAge != null && videoAge < LiveViewEnablePolicy.STALL_MS) ||
            (auAge != null && auAge < LiveViewEnablePolicy.STALL_MS)
        val presentedAge = tile.decoder.lastPresentedAt?.let { now - it }
        val presentFrozen = udpAlive && presentedAge != null && presentedAge > LiveViewEnablePolicy.STALL_MS
        val json = buildString {
            append("{")
            append("\"now\":${now / 1000.0}")
            append(",\"flowHealthy\":${pathReady && !driver.needsRebuild}")
            append(",\"pathReady\":$pathReady")
            append(",\"hasFormat\":${tile.decoder.hasFormat}")
            append(",\"decoderFailed\":${tile.decoder.failedThisGeneration}")
            append(",\"live\":true")
            append(",\"sawPicture\":${tile.hasPicture}")
            append(",\"tcpPokeReady\":${driver.isTcpPokeReady}")
            append(",\"hadVideo\":${driver.videoPackets > 0}")
            age(tile.decoder.lastPresentedAt)?.let { append(",\"lastDecodedFrameAge\":$it") }
            age(driver.lastVideoPacketAt)?.let { append(",\"lastVideoPacketAge\":$it") }
            age(driver.lastAccessUnitAt)?.let { append(",\"lastAccessUnitAge\":$it") }
            age(driver.lastStatusAt)?.let { append(",\"lastStatusAge\":$it") }
            age(driver.lastRebuildAt)?.let { append(",\"secondsSinceLastRebuild\":$it") }
            age(tile.lastEnable)?.let { append(",\"secondsSinceLastEnable\":$it") }
            age(tile.lastCommandAt)?.let { append(",\"secondsSinceCameraSet\":$it") }
            // A lost packet leaves the decoder waiting for an IRAP the Pocket only sends
            // when asked; these let the core watchdog see that (PocketCameraSession parity).
            age(tile.decoder.lastDecoderOutputAt)?.let { append(",\"lastDecoderOutputAge\":$it") }
            append(",\"decoderOutputExpected\":${tile.decoder.decoderOutputExpected}")
            append(",\"referenceRecoveryNeeded\":${tile.decoder.referenceRecoveryNeeded}")
            append(",\"repairReady\":${tile.decoder.isPresentationReady}")
            append("}")
        }
        if (pathReady) tile.pathLostAt = null else if (tile.pathLostAt == null) tile.pathLostAt = now
        if (tile.checkForegroundDecoder && udpAlive) {
            tile.checkForegroundDecoder = false
            if (tile.decoder.failedThisGeneration || presentFrozen || tile.decoder.lastPresentedAt == null) {
                tile.decoder.prepareAfterForeground()
                sendEnable(tile, driver, tile.camera ?: return)
                tile.foregroundRepairAt = now
                log("multiview: foreground decoder repair, socket retained")
                return
            }
        }
        var foregroundRejoin = false
        tile.foregroundRepairAt?.let { repaired ->
            if (now - repaired > 12_000) {
                tile.foregroundRepairAt = null
                if (presentFrozen) foregroundRejoin = true
            }
        }
        val action = if (foregroundRejoin) "fullSessionRejoin" else tile.recovery.action(json)
        if (tile.decoder.awaitingIdr &&
            LiveViewEnablePolicy.shouldReleaseIDRHold(
                awaitingIDR = true, udpReceiveAlive = udpAlive,
                sinceEnableMs = tile.lastEnable.takeIf { it > 0L }?.let { now - it },
                hasPresentedPicture = tile.decoder.lastPresentedAt != null,
            )
        ) {
            tile.decoder.endIDRHold()
        }
        if (action == "none") {
            if (!pathReady && now - (tile.pathLostAt ?: now) > 45_000) {
                tile.recovery.fail()
                tile.failureMessage = "Shared network unavailable. Rejoin it, then reconnect this camera."
            }
            return
        }
        log("multiview: repair action=$action snapshot=$json")
        tile.status = "Reconnecting…"
        val camera = tile.camera ?: return
        if (action == "resendLiveViewEnable") {
            if (!tile.decoder.isPresentationReady) return
            sendEnable(tile, driver, camera)
            tile.decoder.beginIDRHold()
            return
        }
        if (action == "rebuildVTSession") {
            // Keep the socket and last picture; a fresh codec takes the IRAP this enable requests.
            tile.decoder.rebuildPresentation()
            sendEnable(tile, driver, camera)
            return
        }
        tile.recovering = true
        tile.repairJob = scope.launch {
            try {
                if (action == "fullSessionRejoin") {
                    rejoinWhenAvailable(tile)
                } else {
                    try {
                        withContext(Dispatchers.IO) { driver.rebuildUdp() }
                        if (!running || tile.driver !== driver) return@launch
                        sendEnable(tile, driver, camera)
                        tile.decoder.beginIDRHold()
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        if (running) rejoinWhenAvailable(tile)
                    }
                }
            } finally {
                tile.recovering = false
                tile.repairJob = null
            }
        }
    }

    private suspend fun rejoinWhenAvailable(tile: Tile) {
        // One discovery owner; waiting tiles do not spend their retry budget.
        while (busy && running) delay(200)
        if (!running || tile.camera == null) return
        if (!tile.recovery.beginRejoin()) {
            tile.failureMessage = "Could not restore preview. Tap Reconnect to try again."
            return
        }
        connectPreview(tile)
    }

    // --- Recording -----------------------------------------------------------------------------

    suspend fun toggleAllRecording() {
        if (!canRecordTogether) return
        val stop = anyRecording
        val targets = recordingTiles.filter { it.recordingObservation?.first != !stop }
        groupRecordingBusy = true
        groupRecordingNote = if (stop) "Stopping cameras…" else "Starting cameras…"
        coroutineScope { targets.map { tile -> async { recording(!stop, tile) } }.awaitAll() }
        val expected = if (stop) "Recording stopped" else "Recording"
        val confirmed = targets.count { it.recordingNote == expected }
        val allMatch = recordingTiles.all { it.recordingAvailable && it.recordingObservation?.first == !stop }
        groupRecordingNote = if (confirmed == targets.size && allMatch) {
            if (stop) "Recording stopped" else "Recording on $confirmed cameras"
        } else {
            "$confirmed of ${targets.size} confirmed · check camera tiles"
        }
        groupRecordingBusy = false
    }

    suspend fun toggleRecording(tile: Tile) {
        if (groupRecordingBusy) return
        val observation = tile.recordingObservation ?: return
        if (SystemClock.elapsedRealtime() - observation.second >= 3_000) return
        recording(!observation.first, tile)
    }

    /** Commands share the tile's existing UDP session; opening another would replace preview. */
    suspend fun recording(enabled: Boolean, tile: Tile) {
        val driver = tile.driver ?: return
        if (!running || tile.recordingBusy || tile.controlHost == null) return
        tile.recordingBusy = true
        try {
            val sent = SystemClock.elapsedRealtime()
            tile.lastCommandAt = sent
            withContext(Dispatchers.IO) {
                driver.sendCommand(if (enabled) SwiftCore.CMD_RECORD_START else SwiftCore.CMD_RECORD_STOP)
            }
            tile.recordingNote = "Waiting for camera confirmation"
            val deadline = sent + 8_000
            while (running && tile.driver === driver && SystemClock.elapsedRealtime() < deadline) {
                delay(100)
                val reply = tile.responses[RECORD_KEY]?.takeIf { it.second >= sent }?.first
                if (reply != null && !(reply.payload.size == 1 && reply.payload[0].toInt() == 0)) {
                    tile.recordingNote = "Recording command rejected · check camera"
                    return
                }
                val observation = tile.recordingObservation
                if (observation != null && observation.second > sent && observation.first == enabled) {
                    log("multiview: station recording confirmed active=$enabled")
                    tile.recordingNote = if (enabled) "Recording" else "Recording stopped"
                    return
                }
            }
            tile.recordingNote = "No confirmation · check camera"
        } finally {
            tile.recordingBusy = false
        }
    }

    fun remove(tile: Tile): Boolean {
        if (busy || tile.connecting || groupRecordingBusy || tile.recordingBusy) return false
        tile.reset()
        persistStage()
        return true
    }

    // --- Stage persistence and cleanup ---------------------------------------------------------------

    private fun savedCameras(): List<MultiviewStageStore.Camera> =
        tiles.mapNotNull { tile ->
            val camera = tile.camera ?: return@mapNotNull null
            MultiviewStageStore.Camera(
                slot = tile.index, id = camera.id, name = camera.name, modelId = camera.modelId,
                bleAddress = camera.address, identity = tile.identity, address = tile.cameraAddress,
                experimental = tile.experimentalNetwork, lutEnabled = tile.lutEnabled,
            )
        }

    fun persistStage(): Boolean {
        if (!networkConfigured && pendingReset.isEmpty()) {
            if (!cleanupJournalWritten) return true
            val success = saveStage(null)
            if (success) cleanupJournalWritten = false
            return success
        }
        val saved = savedCameras()
        val success = saveStage(
            MultiviewStageStore.Stage(
                ssid = if (networkConfigured) ssid else "",
                hotspot = usePhoneHotspot,
                layout = layout.raw,
                focusedIndex = focusedIndex,
                cameras = saved,
                pendingReset = if (running && !closing) {
                    MultiviewStageStore.cleanupTargets(pendingReset, saved)
                } else {
                    pendingReset
                },
                returnedToCameraWiFi = !running && pendingReset.isEmpty(),
                fill = fill,
            ),
        )
        if (!success) log("multiview: could not save stage")
        if (success && !networkConfigured) cleanupJournalWritten = true
        return success
    }

    /**
     * A new session always asks for a network and starts with empty slots. Old
     * stages supply presentation preferences and cleanup obligations only.
     */
    fun restoreStage(stage: MultiviewStageStore.Stage? = MultiviewStageStore.load(app)) {
        stage ?: return
        pendingReset = stage.pendingReset.orEmpty()
        if (stage.returnedToCameraWiFi != true) {
            pendingReset = MultiviewStageStore.cleanupTargets(pendingReset, stage.cameras)
        }
        cleanupJournalWritten = pendingReset.isNotEmpty()
        layout = MultiviewLayout.from(stage.layout)
        fill = stage.fill == true
        focusedIndex = stage.focusedIndex
        // Migrate unfinished camera cleanup before a new camera is added.
        if (cleanupJournalWritten) persistStage()
    }

    val hasPendingCleanup: Boolean get() = !running && pendingReset.isNotEmpty() && !closing

    /** Close every camera's monitor first, then restore its own access point in parallel. */
    suspend fun closeStage(): Boolean {
        if (closing) return false
        closing = true
        if (running) pendingReset = MultiviewStageStore.cleanupTargets(pendingReset, savedCameras())
        persistStage()
        stop()
        coroutineScope { pendingReset.map { saved -> async { resetStationOnce(saved) } }.awaitAll() }
        persistStage()
        closing = false
        if (pendingReset.isNotEmpty()) {
            error = "Some cameras could not return to their own Wi-Fi. Keep them powered on and close Multiview again to retry."
            return false
        }
        return true
    }

    /** Shared by scan completion, close and restored cleanup; one reset per camera at a time. */
    suspend fun resetStationOnce(saved: MultiviewStageStore.Camera): Boolean {
        stationResets[saved.id]?.let { return it.await() }
        if (pendingReset.none { it.id == saved.id }) return true
        val task = scope.async {
            val success = resetCamera?.invoke(saved) ?: resetStation(saved)
            if (success) pendingReset = pendingReset.filterNot { it.id == saved.id }
            persistStage()
            stationResets.remove(saved.id)
            success
        }
        stationResets[saved.id] = task
        return task.await()
    }

    private suspend fun resetStation(saved: MultiviewStageStore.Camera): Boolean {
        if (saved.bleAddress.isEmpty()) return false
        val client = MultiviewProvisioner(app)
        return try {
            client.connect(restoredCamera(saved), pairingTimeoutMs = 12_000)
            val reply = client.exchange(SwiftCore.CMD_MULTICAM_STATION_MODE, "0").payload.hexString()
            val accepted = reply == "00" || reply == "0000"
            log("multiview: return camera Wi-Fi accepted=$accepted")
            accepted
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            log("multiview: return camera Wi-Fi failed ${error.javaClass.simpleName}: ${error.message}")
            false
        } finally {
            client.close()
        }
    }

    private fun restoredCamera(saved: MultiviewStageStore.Camera): FoundCamera {
        val model = com.opencapture.openpocketcine.session.CameraModel.fromJson(
            SwiftCore.resolveCameraModel(saved.modelId ?: -1, saved.name, saved.bleAddress, true))
        return FoundCamera(saved.id, saved.bleAddress, saved.name, model, saved.modelId)
    }

    // --- Tile surfaces --------------------------------------------------------------------------------

    fun attachTileSurface(tile: Tile, surface: Surface) {
        tile.decoder.attachSurface(surface)
        tile.surfaceMounted = true
    }

    fun detachTileSurface(tile: Tile, surface: Surface) {
        tile.decoder.detachSurface(surface)
        if (tile.liveModel == null) tile.surfaceMounted = false
    }

    private fun log(line: String) {
        Log.i(TAG, line)
        DiagnosticCenter.log("info", "multiview", "session", line)
    }

    companion object {
        const val LIVE_STATUS = "Live · Video mode"
        private const val IDENTITY_KEY = (0x07 shl 8) or 0x07
        private const val RECORD_KEY = (0x02 shl 8) or 0x02
        private const val STATION_OPEN_MS = 15_000L
        private const val SUBSCRIBE_SETTLE_MS = 150L
    }
}

private fun ByteArray.hexString(): String = hex(this)

private fun List<Byte>.toByteArray(): ByteArray = ByteArray(size) { this[it] }
