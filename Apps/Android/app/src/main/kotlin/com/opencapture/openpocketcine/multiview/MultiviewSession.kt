package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.multicam.RecordAll
import com.opencapture.opencine.dji.applyAttitude
import com.opencapture.opencine.dji.fromJson
import com.opencapture.opencine.dji.toJson
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.FoundCamera
import com.opencapture.opencine.vocabulary.GimbalStickMapping

import com.opencapture.opencine.dji.MultiviewDiscovery
import com.opencapture.opencine.dji.MultiviewFailure
import com.opencapture.opencine.dji.MultiviewNetworkStore
import com.opencapture.opencine.dji.DjiStationCommissioner
import com.opencapture.opencine.dji.dji
import com.opencapture.opencine.dji.SharedWiFi
import com.opencapture.opencine.dji.restoreCameraWiFiWithRetry
import com.opencapture.opencine.dji.DjiNative
import com.opencapture.opencine.dji.StationJoin
import android.content.Context
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.opencapture.opencine.appkit.MultiviewStageJournal
import com.opencapture.opencine.appkit.race
import com.opencapture.opencine.appkit.MultiviewStageState
import com.opencapture.opencine.appkit.MultiviewStageLayout
import com.opencapture.opencine.appkit.MultiviewStagePreferences
import com.opencapture.monitorui.MultiviewArrangement
import com.opencapture.opencine.core.MonitorEntryID
import com.opencapture.opencine.core.PictureHealth
import com.opencapture.opencine.core.StreamID
import com.opencapture.opencine.core.CameraSession
import com.opencapture.opencine.core.MultiviewAutoLUT
import com.opencapture.opencine.core.MultiviewCameraPolicy
import com.opencapture.opencine.core.MultiviewLinkStatus
import com.opencapture.opencine.core.MultiviewMemberLink
import com.opencapture.opencine.core.MultiviewRepairContext
import com.opencapture.opencine.core.MultiviewRepairResult
import com.opencapture.opencine.core.MultiviewRepairStep
import com.opencapture.opencine.core.StationCommission
import com.opencapture.opencine.core.StationCommissionOutcome
import com.opencapture.opencine.core.StationCameraRecord
import com.opencapture.opencine.core.StationCommissioner
import com.opencapture.opencine.core.StationHostPath
import com.opencapture.opencine.core.StationNetwork
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.opencine.vocabulary.LutLookResolver
import com.opencapture.opencine.vocabulary.LutLookSource
import com.opencapture.opencine.multicam.EditorLeaseException
import com.opencapture.opencine.multicam.EditorLeases
import com.opencapture.opencine.multicam.RecordDirection
import com.opencapture.opencine.multicam.RecordPlan
import com.opencapture.opencine.multicam.ResourceAdmission
import com.opencapture.opencine.multicam.ResourceRequest
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.cameracontrols.MonitorFeedEffectsPlans
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.opencine.dji.DjiCameraLUTProfile
import com.opencapture.opencine.dji.BleLink
import com.opencapture.opencine.dji.DatalinkDriver
import com.opencapture.opencine.dji.DjiCameraSessionAdapter
import com.opencapture.opencine.dji.DumlFrame
import com.opencapture.opencine.decoder.HevcDecoder
import com.opencapture.opencine.dji.LiveViewEnablePolicy
import com.opencapture.opencine.dji.MultiviewControlLease
import com.opencapture.opencine.dji.StatusExtras
import com.opencapture.opencine.dji.interruptibleDatalinkOpen
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.cancelAndJoin
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
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import com.opencapture.opencine.runtime.InspectorPreviewPipeline
import com.opencapture.opencine.runtime.ScopeSampleBus

private const val TAG = "Multiview"

private fun multiviewLog(line: String) {
    Log.i(TAG, line)
    DiagnosticCenter.log("info", "multiview", "session", line)
}

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
    private var handle = if (DjiNative.isAvailable) DjiNative.multiviewRecoveryCreate() else 0L
    fun action(snapshotJSON: String): String =
        if (handle == 0L) "none" else DjiNative.multiviewRecoveryCall(handle, "action", snapshotJSON) ?: "none"
    fun beginRejoin(): Boolean = handle != 0L && DjiNative.multiviewRecoveryCall(handle, "beginRejoin", "{}") == "true"
    fun fail() { if (handle != 0L) DjiNative.multiviewRecoveryCall(handle, "fail", "{}") }
    val failed: Boolean get() = handle != 0L && DjiNative.multiviewRecoveryCall(handle, "failed", "{}") == "true"
    fun reset() { if (handle != 0L) DjiNative.multiviewRecoveryCall(handle, "reset", "{}") }
    fun close() {
        if (handle != 0L) DjiNative.multiviewRecoveryDestroy(handle)
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
    private val saveStage: (MultiviewStageJournal.Stage?) -> Boolean = { MultiviewStageStore.save(context, it) },
    private val networkStore: MultiviewNetworkStore = MultiviewNetworkStore(context),
    private val resetCamera: (suspend (MultiviewStageJournal.Camera) -> Boolean)? = null,
) {
    private val app = context.applicationContext

    /** Nested, not inner: Compose needs stability metadata on this type (an inner class has none). */
    class Tile(
        val index: Int,
        private val app: Context,
        private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        /** The session's shared path; this tile's datalink binds to it. */
        private val path: SharedWiFi = SharedWiFi(app),
    ) : MultiviewMemberLink<FoundCamera> {
        val id: String = UUID.randomUUID().toString()
        /** Stable multicam slot: this tile's identity through layout, selection and rotation. */
        val entryId = MonitorEntryID(UUID.fromString(id))
        /** The tile's picture stream, named for the multicam engine. */
        val stream = StreamID()
        val decoder = HevcDecoder(errorJournal = DiagnosticCenter::logDecoderError)
        val scopeBus = com.opencapture.opencine.runtime.ScopeSampleBus()
        val inspectorPreview = com.opencapture.opencine.runtime.InspectorPreviewPipeline(
            scopeBus, { com.opencapture.opencine.runtime.NativeGlBackend.create(it) }, "OpcTileInspector")
        /** Record-only control port on this tile's own link (MULTI-02); see [MultiviewTileControl]. */
        internal val controlPort = MultiviewTileControl(
            state = ::recordState,
            send = { start ->
                val endpoint = driver
                if (endpoint == null || endpoint.isClosed) {
                    false
                } else {
                    lastCommandAt = SystemClock.elapsedRealtime()
                    withContext(Dispatchers.IO) {
                        endpoint.sendCommand(if (start) DjiNative.CMD_RECORD_START else DjiNative.CMD_RECORD_STOP)
                    }
                    true
                }
            },
            reply = { since ->
                responses[RECORD_KEY]?.takeIf { it.second >= since }?.first?.let {
                    it.payload.size == 1 && it.payload[0].toInt() == 0
                }
            },
            setBusy = { recordingBusy = it },
            scope = scope,
            clock = SystemClock::elapsedRealtime,
        )
        /**
         * This tile's camera as a common session: one per tile for its lifetime, so selection,
         * layout and rotation never change it. Its control epoch advances when the tile's link or
         * camera is replaced.
         */
        val control = DjiCameraSessionAdapter(controlPort, scope).apply {
            // Backstops only: the tile's own 8 s confirmation window decides first.
            wireTimeout = 9.seconds
            readbackTimeout = 9.seconds
        }
        var liveModel by mutableStateOf<AppModel?>(null)
        /** Settings use their own command model, never the tile's presentation owner. */
        var controlsModel by mutableStateOf<AppModel?>(null)
            private set
        fun closeControls() {
            controlsModel?.close()
            controlsModel = null
        }
        /** [admits]: the session's engine lease and availability (`MultiviewSession.openControls`). */
        fun openControls(admits: () -> Boolean): AppModel? {
            closeControls()
            val camera = camera ?: return null
            val endpoint = driver ?: return null
            val recording = latestSettings.isRecording
            val lease = MultiviewControlLease(
                isCurrent = {
                    this.camera?.id == camera.id && driver === endpoint &&
                        latestSettings.isRecording == recording && admits()
                },
                onSet = { lastCommandAt = it },
            )
            if (!lease.allows()) return null
            return AppModel(app, borrowing = decoder, controlLease = lease).also {
                it.session.updateMultiview(camera, endpoint, latestSettings)
                // The capture drums edit through the shared control model; close() unbinds it.
                it.control.bind(it.session.control)
                controlsModel = it
            }
        }
        var driver: DatalinkDriver? = null
            set(value) {
                val replaced = field !== value
                if (replaced) closeControls()
                field = value
                if (replaced) control.linkDidChange()
                liveModel?.session?.updateMultiview(camera, value, latestSettings)
            }
        var connecting by mutableStateOf(false)
        var experimentalNetwork by mutableStateOf(false)
        var networkVerified by mutableStateOf(false)
        var cameraAddress = ""
        var identity: ByteArray? = null
        /** Latest reply per DUML key with its receive time. */
        val responses = HashMap<Int, Pair<DumlFrame, Long>>()
        private var cameraState by mutableStateOf<FoundCamera?>(null)
        var camera: FoundCamera?
            get() = cameraState
            set(value) {
                val replaced = value?.id != cameraState?.id
                cameraState = value
                if (replaced) control.linkDidChange()
            }
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
        internal val feedEffectsPlans = MonitorFeedEffectsPlans(SwiftCore)
        var lutEnabled by mutableStateOf(true)
        internal var plan by mutableStateOf(FeedEffectsRenderPlan.IDENTITY)
        /** Camera settings' preview owner; the tile's existing present tap feeds it while set. */
        internal var previewOwner by mutableStateOf<Any?>(null)
        var lutCaption by mutableStateOf("Auto LUT")
        var hasPicture by mutableStateOf(false)
        var publishing by mutableStateOf(false)
        /** The member link's own record that its control link is up (it reported `CONTROLLING`). */
        private var controlLinkUp = false
        /** The status this link last reported; read on the decoder thread. */
        @Volatile private var reported: MultiviewLinkStatus? = null
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

        /** The body's clock at its declared precision, only where it declares one (Nano has none). */
        val timecodeReadout: String? get() = if (camera == null) null else control.tileTimecodeReadout()

        fun updateSettings(frame: DumlFrame) {
            val cam = camera ?: return
            val prev = latestSettings
            val json = DjiNative.applyStatus(frame.cmdSet, frame.cmdId, frame.payload, prev.toJson())
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
            val result = feedEffectsPlans.multiviewAutoLut(
                app, lutEnabled, settings.colorMode, DjiCameraLUTProfile.make(cam?.model?.family ?: "pocket", cam?.model?.name),
            )
            plan = result.first
            lutCaption = autoLUT.caption(lutEnabled, conversionLoaded = result.first.lutCube != null)
        }

        /** Claims decoder input for a new transport; the previous one can no longer feed it. */
        fun wire(next: DatalinkDriver) {
            inputOwner = decoder.claimInputOwner()
            val owner = inputOwner
            next.onVideoEpochChanged = { epoch -> decoder.advanceInputEpoch(owner, epoch) }
            next.onReferenceDiscontinuity = { epoch -> decoder.noteReferenceDiscontinuity(owner, epoch) }
        }

        fun claimedInput(): Long = inputOwner

        internal fun recordState() = TileRecordState(
            link = driver,
            controlHost = controlHost != null,
            connecting = connecting,
            recovering = recovering,
            cameraId = camera?.id,
            shootingMode = settings.shootingMode,
            recordingBusy = recordingBusy,
            observation = recordingObservation,
            recordingAvailable = recordingAvailable,
            batteryPercent = settings.batteryPercent,
            storageFreeMb = settings.storageFreeMb,
            storageTotalMb = settings.storageTotalMb,
            model = camera?.model,
            charging = settings.chargingReading,
            timecode = settings.timecodeValue,
        )

        internal fun multicam() = MulticamTile(
            entryId, camera?.name.orEmpty(), stream, control,
            busy = recordingBusy || connecting || recovering,
            picture = pictureHealth,
        )

        // --- Member link (OpenCine MultiviewMemberLink; Pocket supplies DJI's) -----------------

        override val session: CameraSession get() = control

        override var onStatus: ((MultiviewLinkStatus) -> Unit)? = null

        override val isPublishing: Boolean get() = publishing

        /**
         * Longer than any DJI repair's own bound (the UDP rebuild's handshake and station open), so
         * the race never cuts a DJI repair short.
         */
        override val repairDeadline: Duration get() = 60.seconds

        /** Reports [status] to the coordinator, on the main thread. */
        private fun report(status: MultiviewLinkStatus) {
            reported = status
            onStatus?.invoke(status)
        }

        override val pictureHealth: PictureHealth
            get() = when {
                failureMessage != null -> PictureHealth.FAILED
                recovering -> PictureHealth.STALLED
                hasPicture -> PictureHealth.LIVE
                else -> PictureHealth.STARTING
            }

        override val autoLUT: MultiviewAutoLUT
            get() {
                val cam = camera
                val family = cam?.model?.family ?: "pocket"
                val source = LutLookResolver.resolve(
                    LutCatalog.AUTO, true, settings.colorMode, profile = DjiCameraLUTProfile.make(family, cam?.model?.name),
                )
                return MultiviewAutoLUT(
                    colorMode = settings.colorMode.takeIf { it >= 0 }?.let { CameraCommands.colorLabel(it, family) },
                    conversion = if (source == LutLookSource.Off) null else LutLookResolver.sourceTitle(source),
                )
            }

        override suspend fun probe(address: String, network: StationNetwork): Boolean {
            val local = path.address(network.hotspot) ?: return false
            return MultiviewDiscovery(path).probe(address, local)
        }

        override suspend fun open(
            camera: FoundCamera,
            address: String,
            expecting: ByteArray?,
            network: StationNetwork,
        ): ByteArray {
            driver?.close()
            driver = null
            controlLinkUp = false
            responses.clear()
            recordingObservation = null
            publishing = false
            previewStarted = null
            enableSends = 0
            lastEnable = 0L
            if (hasPicture) decoder.beginIDRHold() else decoder.reset()
            report(MultiviewLinkStatus.OPENING)
            val driver = DatalinkDriver(
                path, camera.model.datalinkPort, camera.model.tcpPoke, camera.model.pairingToken,
                cameraModel = camera.model, host = address,
            )
            wire(driver)
            this.driver = driver
            driver.onStatusFrame = { frame ->
                if (this.driver === driver) {
                    if ((frame.flags and 0x80) != 0) {
                        if (responses.size > 128) responses.clear()
                        responses[frame.key] = frame to SystemClock.elapsedRealtime()
                    }
                    if (controlLinkUp) {
                        updateSettings(frame)
                        liveModel?.session?.receiveMultiview(frame)
                        controlsModel?.session?.receiveMultiview(frame)
                        if (frame.cmdSet == 0x02 && frame.cmdId == 0x80 && frame.payload.size >= 13) {
                            val json = DjiNative.applyStatus(frame.cmdSet, frame.cmdId, frame.payload, CameraStatus().toJson())
                            val recording = json?.let { CameraStatus.fromJson(it).isRecording } ?: false
                            recordingObservation = recording to SystemClock.elapsedRealtime()
                        }
                    }
                }
            }
            withTimeout(STATION_OPEN_MS) { interruptibleDatalinkOpen { driver.open(identityOnly = true) } }
            val sent = SystemClock.elapsedRealtime()
            driver.sendCommand(DjiNative.CMD_GET_WIFI_SSID)
            val deadline = sent + 8_000
            var reply: DumlFrame? = null
            while (SystemClock.elapsedRealtime() < deadline) {
                responses[IDENTITY_KEY]?.takeIf { it.second >= sent }?.let { reply = it.first }
                if (reply != null) break
                delay(50)
            }
            val proven = reply?.payload
            if (proven == null || (expecting != null && !proven.contentEquals(expecting))) {
                throw MultiviewFailure.Message("This network connection did not identify the selected camera.")
            }
            return proven
        }

        override suspend fun startPreview(camera: FoundCamera) {
            val driver = driver ?: throw CancellationException("multiview link closed")
            withContext(Dispatchers.IO) { driver.completeRegistration() }
            controlLinkUp = true
            report(MultiviewLinkStatus.CONTROLLING)
            liveModel?.session?.updateMultiview(camera, driver, latestSettings)
            multiviewLog("multiview: station camera identity verified")
            val input = claimedInput()
            driver.onAccessUnit = { au, epoch ->
                if (decoder.decode(au, input, epoch)) {
                    if (!hasPicture || reported != MultiviewLinkStatus.LIVE) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            if (this.driver === driver) {
                                if (!hasPicture) multiviewLog("multiview: station preview enqueued")
                                hasPicture = true
                                report(MultiviewLinkStatus.LIVE)
                            }
                        }
                    }
                }
            }
            decoder.onParameterSetsChanged = {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    if (this.driver === driver && controlLinkUp) sendEnable(driver, camera)
                }
            }
            // Subscribe is fire-and-forget; an enable in the same burst is ignored.
            delay(SUBSCRIBE_SETTLE_MS)
            withContext(Dispatchers.IO) {
                val nanoGate = camera.model.usesNanoLiveViewGate
                if (nanoGate) driver.sendNanoGate(start = true)
                if (camera.model.sendsLiveViewPrepare) {
                    driver.sendCommand(DjiNative.CMD_TAP_FOCUS_HINT)
                }
                driver.startLiveView(camera.model.liveViewEnableReceiver)
            }
            lastEnable = SystemClock.elapsedRealtime()
            enableSends = 1
            publishing = true
            previewStarted = SystemClock.elapsedRealtime()
            if (!hasPicture) report(MultiviewLinkStatus.AWAITING_PICTURE)
        }

        // The camera stops video ~10 s after the last registration; this heartbeat is never
        // gated by UI or repair state.
        override suspend fun keepalive() {
            driver?.let { driver -> withContext(Dispatchers.IO) { driver.keepalive() } }
        }

        override fun close() {
            driver?.close()
            driver = null
            controlLinkUp = false
        }

        internal fun sendEnable(driver: DatalinkDriver, camera: FoundCamera) {
            scope.launch(Dispatchers.IO) { driver.startLiveView(camera.model.liveViewEnableReceiver) }
            lastEnable = SystemClock.elapsedRealtime()
            enableSends += 1
        }

        /** DJI's feed watchdog ladder on this tile's own link, once a second while it publishes. */
        override fun repair(context: MultiviewRepairContext): MultiviewRepairStep {
            val driver = driver ?: return MultiviewRepairStep.Handled
            val now = SystemClock.elapsedRealtime()
            fun age(at: Long?): Double? = at?.takeIf { it > 0L }?.let { (now - it) / 1000.0 }
            val pathReady = context.pathReady
            val videoAge = driver.lastVideoPacketAt?.let { now - it }
            val auAge = driver.lastAccessUnitAt?.let { now - it }
            val udpAlive = (videoAge != null && videoAge < LiveViewEnablePolicy.STALL_MS) ||
                (auAge != null && auAge < LiveViewEnablePolicy.STALL_MS)
            val presentedAge = decoder.lastPresentedAt?.let { now - it }
            val presentFrozen = udpAlive && presentedAge != null && presentedAge > LiveViewEnablePolicy.STALL_MS
            val json = buildString {
                append("{")
                append("\"now\":${now / 1000.0}")
                append(",\"flowHealthy\":${pathReady && !driver.needsRebuild}")
                append(",\"pathReady\":$pathReady")
                append(",\"hasFormat\":${decoder.hasFormat}")
                append(",\"decoderFailed\":${decoder.failedThisGeneration}")
                append(",\"live\":true")
                append(",\"sawPicture\":$hasPicture")
                append(",\"tcpPokeReady\":${driver.isTcpPokeReady}")
                append(",\"hadVideo\":${driver.videoPackets > 0}")
                age(decoder.lastPresentedAt)?.let { append(",\"lastDecodedFrameAge\":$it") }
                age(driver.lastVideoPacketAt)?.let { append(",\"lastVideoPacketAge\":$it") }
                age(driver.lastAccessUnitAt)?.let { append(",\"lastAccessUnitAge\":$it") }
                age(driver.lastStatusAt)?.let { append(",\"lastStatusAge\":$it") }
                age(driver.lastRebuildAt)?.let { append(",\"secondsSinceLastRebuild\":$it") }
                age(lastEnable)?.let { append(",\"secondsSinceLastEnable\":$it") }
                age(lastCommandAt)?.let { append(",\"secondsSinceCameraSet\":$it") }
                // A lost packet leaves the decoder waiting for an IRAP the Pocket only sends
                // when asked; these let the core watchdog see that (DjiCameraSession parity).
                age(decoder.lastDecoderOutputAt)?.let { append(",\"lastDecoderOutputAge\":$it") }
                append(",\"decoderOutputExpected\":${decoder.decoderOutputExpected}")
                append(",\"referenceRecoveryNeeded\":${decoder.referenceRecoveryNeeded}")
                append(",\"repairReady\":${decoder.isPresentationReady}")
                append("}")
            }
            if (checkForegroundDecoder && udpAlive) {
                checkForegroundDecoder = false
                if (decoder.failedThisGeneration || presentFrozen || decoder.lastPresentedAt == null) {
                    decoder.prepareAfterForeground()
                    sendEnable(driver, camera ?: return MultiviewRepairStep.Handled)
                    foregroundRepairAt = now
                    multiviewLog("multiview: foreground decoder repair, socket retained")
                    return MultiviewRepairStep.Handled
                }
            }
            var foregroundRejoin = false
            foregroundRepairAt?.let { repaired ->
                if (now - repaired > 12_000) {
                    foregroundRepairAt = null
                    if (presentFrozen) foregroundRejoin = true
                }
            }
            val action = if (foregroundRejoin) "fullSessionRejoin" else recovery.action(json)
            if (decoder.awaitingIdr &&
                LiveViewEnablePolicy.shouldReleaseIDRHold(
                    awaitingIDR = true, udpReceiveAlive = udpAlive,
                    sinceEnableMs = lastEnable.takeIf { it > 0L }?.let { now - it },
                    hasPresentedPicture = decoder.lastPresentedAt != null,
                )
            ) {
                decoder.endIDRHold()
            }
            if (action == "none") return MultiviewRepairStep.Healthy
            multiviewLog("multiview: repair action=$action snapshot=$json")
            report(MultiviewLinkStatus.RECONNECTING)
            val camera = camera ?: return MultiviewRepairStep.Handled
            if (action == "resendLiveViewEnable") {
                if (!decoder.isPresentationReady) return MultiviewRepairStep.Handled
                sendEnable(driver, camera)
                decoder.beginIDRHold()
                return MultiviewRepairStep.Handled
            }
            if (action == "rebuildVTSession") {
                // Keep the socket and last picture; a fresh codec takes the IRAP this enable requests.
                decoder.rebuildPresentation()
                sendEnable(driver, camera)
                return MultiviewRepairStep.Handled
            }
            if (action == "fullSessionRejoin") return MultiviewRepairStep.Repair { MultiviewRepairResult.Rejoin }
            return MultiviewRepairStep.Repair {
                try {
                    withContext(Dispatchers.IO) { driver.rebuildUdp() }
                    if (context.running() && this.driver === driver) {
                        sendEnable(driver, camera)
                        decoder.beginIDRHold()
                    }
                    MultiviewRepairResult.Done
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    if (context.running()) MultiviewRepairResult.Rejoin else MultiviewRepairResult.Done
                }
            }
        }

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
            lutEnabled = true
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

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val path = SharedWiFi(app)
    /** DJI's camera setup through OpenCine's station seams. */
    private val commissioner: StationCommissioner<FoundCamera> = DjiStationCommissioner(app, path, ::log)
    private val cameraPolicy: MultiviewCameraPolicy<FoundCamera> = MultiviewCameraPolicy.dji
    private val hostPath: StationHostPath get() = path
    val tiles: List<Tile> = List(MultiviewQualificationPolicy.tileCount) { Tile(it, app, scope, path) }

    init {
        for (tile in tiles) tile.onStatus = { show(it, tile) }
    }

    /**
     * The coordinator's half of a member link's status: the tile's copy, and the control host it
     * records once the link's control path is up at the address it was opened at.
     */
    private fun show(status: MultiviewLinkStatus, tile: Tile) {
        when (status) {
            MultiviewLinkStatus.OPENING -> tile.status = "Connecting normal preview"
            MultiviewLinkStatus.CONTROLLING -> {
                tile.controlHost = tile.cameraAddress
                tile.failureMessage = null
            }
            MultiviewLinkStatus.AWAITING_PICTURE -> tile.status = "Waiting for video"
            MultiviewLinkStatus.LIVE -> tile.status = LIVE_STATUS
            MultiviewLinkStatus.RECONNECTING -> tile.status = "Reconnecting…"
        }
    }

    /** The shared network as the member links open on it. */
    private val stationNetwork: StationNetwork get() = StationNetwork(ssid, password, usePhoneHotspot)
    private val scanner = BleLink(app)
    val found = mutableStateListOf<FoundCamera>()
    var busy by mutableStateOf(false)
    var ready by mutableStateOf(false)
    var ssid by mutableStateOf("")
    var usePhoneHotspot by mutableStateOf(false)
    var password by mutableStateOf("")
    var groupRecordingBusy by mutableStateOf(false)
    var groupRecordingNote by mutableStateOf<String?>(null)
    val recordingTiles: List<Tile> get() = tiles.filter { it.camera != null }
    val anyRecording: Boolean get() = recordingTiles.any { it.recordingObservation?.first == true }
    val canRecordTogether: Boolean get() = !busy && !groupRecordingBusy && recordPlan().isExecutable

    /** Settings-editor leases (OpenCineMulticam): one open editor, asked before every SET. */
    private val editorLeases = EditorLeases()

    /**
     * The engine's view of [of] (those with a camera), now. A one-tile plan or lease check reads
     * only that tile, so its composable recomposes only for that camera; such plans equal plans
     * built over every tile (non-requested entries never matter).
     */
    internal fun multicam(of: List<Tile> = recordingTiles) =
        MultiviewMulticam(of.filter { it.camera != null }.map { it.multicam() })

    /**
     * The operator's record button as an explicit strict plan: stop when any requested camera
     * reports recording, else start. `tile == null` is Record all. The confirmation dialog holds
     * this value; any change to it (camera, link epoch, mode, availability, reported recording)
     * dismisses the dialog, routine telemetry does not.
     */
    fun recordPlan(tile: Tile? = null): RecordPlan {
        val requested = tile?.let { listOf(it) } ?: recordingTiles
        return multicam(requested).plan(requested.map { it.entryId }, stop = requested.any { it.recordingObservation?.first == true })
    }

    var networkConfigured by mutableStateOf(false)
    var configuringNetwork by mutableStateOf(false)
    var networkSetupError by mutableStateOf<String?>(null)
    var applicationActive = true
        private set
    private var foregroundAt = 0L
    var host by mutableStateOf("")
    var error by mutableStateOf<String?>(null)
    val presentation = MultiviewStageState(MultiviewQualificationPolicy.tileCount)
    var layout: MultiviewLayout
        get() = MultiviewLayout.from(presentation.layout.rawValue)
        set(value) { presentation.layout = if (value == MultiviewLayout.GRID) MultiviewStageLayout.GRID else MultiviewStageLayout.CENTER_STAGE }
    var fill: Boolean
        get() = presentation.fill
        set(value) { presentation.fill = value }
    var focusedIndex: Int
        get() = presentation.selected
        set(value) { presentation.selected = value }
    var closing by mutableStateOf(false)
    val connectingCameras: Boolean get() = tiles.any { it.connecting }
    private val searches = HashMap<String, MultiviewDiscovery>()
    private val connectionJobs = HashMap<String, Job>()
    private var hostJoin: kotlinx.coroutines.Deferred<Unit>? = null
    private val addressReservations = HashMap<String, String>()
    private var pendingReset: List<MultiviewStageJournal.Camera> = emptyList()
    private val stationResets = HashMap<String, kotlinx.coroutines.Deferred<Boolean>>()
    private var cleanupJournalWritten = false
    private var scanJob: Job? = null
    private var networkScanJob: Job? = null
    private var monitor: Job? = null
    private var running = false

    internal fun controlsAvailable(tile: Tile): Boolean =
        running && applicationActive && !closing && !busy && tile.camera != null && tile.controlHost != null &&
            tile.driver?.let { !it.isClosed && !it.isRebuilding } == true &&
            !tile.connecting && !tile.recovering && tile.failureMessage == null && tile.liveModel == null

    /**
     * One settings editor at a time. The engine's editor lease names the tile's session and control
     * epoch: switching tiles, a replaced link or camera, or lost authority retires it, so a queued
     * SET can never reach another camera (plan 7.5).
     */
    fun openControls(tile: Tile): AppModel? {
        editorLeases.closeAll()
        val view = multicam(listOf(tile))
        val lease = try {
            editorLeases.open(tile.entryId, view.group, view.state)
        } catch (_: EditorLeaseException) {
            return null
        }
        return tile.openControls {
            val now = multicam(listOf(tile))
            editorLeases.refusal(lease, now.group, now.state) == null && controlsAvailable(tile)
        }
    }

    // --- Borrowed Live View -------------------------------------------------------------------

    fun openLiveView(tile: Tile) {
        tile.closeControls()
        val camera = tile.camera ?: return
        if (tile.controlHost == null || tile.recovering) return
        val model = AppModel(app, borrowing = tile.decoder)
        model.session.updateMultiview(camera, tile.driver, tile.latestSettings)
        model.session.adoptMultiviewPose(tile.pose)
        model.setBorrowedLut(tile.lutEnabled)
        model.borrowMonitor(camera) { releaseLiveView(tile) }
        tile.liveModel = model
    }

    private fun releaseLiveView(tile: Tile) {
        val model = tile.liveModel ?: return
        tile.liveModel = null
        tile.lutEnabled = model.borrowedLutEnabled()
        tile.pose = model.session.multiviewPose
        model.session.releaseMultiview()
        model.multiviewExit = null
        model.close()
        tile.poseViewFlip = tile.pose.poseViewFlip
        tile.updateLUT()
    }

    fun closeLiveView() {
        for (tile in tiles) releaseLiveView(tile)
        // Every tile feed remounts with a fresh surface. A fresh codec takes the IRAP this
        // enable requests, rather than waiting for the watchdog to find a frozen picture.
        for (tile in tiles) {
            val driver = tile.driver ?: continue
            val camera = tile.camera ?: continue
            if (!tile.publishing) continue
            tile.decoder.rebuildPresentation()
            tile.sendEnable(driver, camera)
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
        scan()
        monitor = scope.launch {
            while (isActive) {
                delay(1_000)
                ready = hostPath.address(usePhoneHotspot) != null
                for (tile in tiles) {
                    tile.keepalive()
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
        if (!active) tiles.forEach { it.closeControls() }
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
        commissioner.closeCommissions()
        closeLiveView()
        running = false
        setApplicationActive(true)
        searches.values.forEach { it.cancel() }
        searches.clear()
        monitor?.cancel()
        scanJob?.cancel()
        scanner.stopScan()
        networkScanJob?.cancel()
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
        tiles.forEach { it.feedEffectsPlans.close(); it.inspectorPreview.close(); it.recovery.close() }
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
        val address = hostPath.join(StationNetwork(ssid, password, hotspot = false)) ?: throw MultiviewFailure.Network()
        host = address
        ready = true
    }

    suspend fun configureNetwork(): Boolean {
        if (busy || configuringNetwork || tiles.any { it.camera != null }) return false
        configuringNetwork = true
        networkSetupError = null
        try {
            if (!com.opencapture.opencine.appkit.validStationCredentials(ssid, password, usePhoneHotspot)) {
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

    /** Shared wizard scan: hold ownership through cancellation and same-link AP cleanup. */
    suspend fun scanNetworks(onFound: (String) -> Unit) = coroutineScope {
        if (busy || !running || closing || tiles.any { it.camera != null }) {
            throw CancellationException("network setup unavailable")
        }
        busy = true
        networkScanJob = currentCoroutineContext()[Job]
        try {
            var camera: FoundCamera? = null
            for (attempt in 0 until 10) {
                currentCoroutineContext().ensureActive()
                camera = found.firstOrNull { cameraPolicy.hasPreview(it) }
                if (camera != null) break
                delay(300)
            }
            val selected = camera ?: throw MultiviewFailure.Unavailable()
            scanJob?.cancel()
            scanner.stopScan()
            commissioner.scanNetworks(
                selected,
                beforeStationChange = {
                    if (!recordStationChange(selected)) {
                        throw MultiviewFailure.Message("Could not save camera Wi-Fi cleanup. Try again.")
                    }
                },
                onRestored = { restored ->
                    if (restored) {
                        pendingReset = pendingReset.filterNot { it.id == selected.id }
                        if (pendingReset.isEmpty()) networkSetupError = null
                        persistStage()
                    } else {
                        networkSetupError =
                            "Camera Wi-Fi could not be restored. Keep it powered on and close Multiview to retry."
                    }
                }, onFound = onFound,
            )
        } finally {
            busy = false
            networkScanJob = null
            if (running && !closing) scan()
        }
    }

    fun savedNetworks(): List<MultiviewNetworkStore.Network> = networkStore.savedNetworks()

    private fun recordStationChange(camera: FoundCamera): Boolean {
        val record = commissioner.record(camera)
        val saved = MultiviewStageJournal.Camera(
            slot = 0, id = record.id, name = record.name, modelId = record.modelId,
            deviceAddress = record.deviceAddress, identity = null, address = "", experimental = false, lutEnabled = true,
        )
        pendingReset = MultiviewStageJournal.cleanupTargets(pendingReset, listOf(saved))
        return persistStage()
    }

    // --- Cameras ---------------------------------------------------------------------------------

    fun enqueueAdd(camera: FoundCamera, tile: Tile, experimental: Boolean = false) {
        if (!running || !networkConfigured || closing || tile.camera != null || tile.connecting) return
        connectionJobs[tile.id]?.cancel()
        connectionJobs[tile.id] = scope.launch { add(camera, tile, experimental) }
    }

    suspend fun add(camera: FoundCamera, tile: Tile, experimental: Boolean = false) {
        val reasons = ResourceAdmission.reasons(
            ResourceRequest(tile.entryId, device = null, claims = emptyList()),
            cameraPolicy.qualification(camera, experimental),
            recordingTiles.map { ResourceRequest(it.entryId, device = null, claims = emptyList()) },
            MultiviewQualificationPolicy.budget,
        )
        if (reasons.isNotEmpty()) {
            error = "Multiview preview is not available for this camera model yet."
            return
        }
        if (!running || !networkConfigured || closing || busy || tile.connecting || tile.camera != null ||
            tiles.any { it.camera?.id == camera.id }
        ) return
        tile.connecting = true
        var client: StationCommission? = null
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
            val link = commissioner.connect(camera) { tile.status = it }
            client = link
            stage = "camera Wi-Fi identity"
            val identity = link.identity()
            stage = "station role"
            // Kept through a lost join reply so reconnect can re-run discovery only.
            tile.identity = identity
            val outcome = try {
                link.join(
                    stationNetwork, identity, experimental,
                    progress = { text ->
                        tile.status = text
                        if (text.startsWith("Waiting for camera")) stage = "camera Wi-Fi join"
                    },
                    verifyOnNetwork = {
                        try {
                            discoverPreview(tile, camera, identity)
                            true
                        } catch (error: CancellationException) {
                            throw error
                        } catch (_: Exception) {
                            false
                        }
                    },
                )
            } catch (error: StationJoin.Failure) {
                tile.identity = null
                throw error
            }
            if (outcome == StationCommissionOutcome.VERIFIED) {
                networkStore.save(ssid, password, usePhoneHotspot)
                return
            }
            networkStore.save(ssid, password, usePhoneHotspot)
            link.close()
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
            client?.close()
            if (running) persistStage()
        }
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
            val proven = tile.open(camera, address, identity, stationNetwork)
            if (tiles.any { it.id != tile.id && it.identity?.contentEquals(proven) == true }) {
                tile.close()
                throw MultiviewFailure.Message("This camera is already in Multiview.")
            }
            if (!running) throw CancellationException("multiview closed")
            tile.networkVerified = true
            if (!cameraPolicy.hasPreview(camera)) {
                tile.close()
                tile.failureMessage = null
                tile.status = "Wi-Fi join verified · Preview not supported yet"
                log("multiview: experimental LAN identity verified; preview unavailable")
                return
            }
            tile.startPreview(camera)
        } finally {
            if (addressReservations[address] == tile.id) addressReservations.remove(address)
        }
    }

    // --- Watchdog ----------------------------------------------------------------------------------

    /**
     * The coordinator's half of repair: when a tile may repair, the 45 s path-loss rule, and the
     * rejoin within the tile's budget. The tile's own link decides and runs the repair.
     */
    private fun monitorPreview(tile: Tile) {
        if (tile.driver == null) return
        val now = SystemClock.elapsedRealtime()
        if (!applicationActive || now - foregroundAt <= 3_000 || busy || tile.recovering ||
            tile.recovery.failed || !tile.publishing || !tile.surfaceMounted
        ) return
        val pathReady = hostPath.address(usePhoneHotspot) != null
        if (pathReady) tile.pathLostAt = null else if (tile.pathLostAt == null) tile.pathLostAt = now
        val context = MultiviewRepairContext(
            pathReady = pathReady,
            running = { running },
            applicationActive = { applicationActive },
            foregroundUnchanged = { true },
            pathAvailable = { hostPath.address(usePhoneHotspot) != null },
            beginAttempt = { tile.recovery.beginRejoin() },
            bluetoothTurn = { bluetoothTurn() },
        )
        when (val step = tile.repair(context)) {
            MultiviewRepairStep.Healthy -> if (!pathReady && now - (tile.pathLostAt ?: now) > 45_000) {
                tile.recovery.fail()
                tile.failureMessage = "Shared network unavailable. Rejoin it, then reconnect this camera."
            }
            MultiviewRepairStep.Handled -> Unit
            is MultiviewRepairStep.WaitForOperator -> waitForOperator(tile, step.message)
            is MultiviewRepairStep.Repair -> {
                tile.recovering = true
                tile.repairJob = scope.launch {
                    try {
                        when (val result = MultiviewRepairResult.race(tile.repairDeadline, scope) { step.run() }) {
                            MultiviewRepairResult.Done -> Unit
                            MultiviewRepairResult.Rejoin -> rejoinWhenAvailable(tile)
                            is MultiviewRepairResult.WaitForOperator -> waitForOperator(tile, result.message)
                        }
                    } finally {
                        tile.recovering = false
                        tile.repairJob = null
                    }
                }
            }
        }
    }

    /** No automatic repair remains for this tile: it shows why and offers Reconnect. */
    private fun waitForOperator(tile: Tile, message: String) {
        tile.recovery.fail()
        tile.failureMessage = message
    }

    /**
     * A member link's turn on Bluetooth for its repair: after any add or network scan (the
     * session's Bluetooth users) has finished. DJI's link never asks; the shared coordinator owns
     * the real queue (Plan 3).
     */
    private suspend fun bluetoothTurn(): (() -> Unit)? {
        while (running && (busy || tiles.any { it.connecting })) delay(200)
        return if (running) ({}) else null
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

    /**
     * Sends an approved plan: one explicit start or stop per camera, revalidated first, each
     * outcome on its own tile. A partial result is never compensated; stopping a camera that
     * started is a separate operator action.
     */
    suspend fun record(plan: RecordPlan, together: Boolean) {
        if (busy || closing || groupRecordingBusy) return
        val start = plan.direction == RecordDirection.START
        if (together) {
            groupRecordingBusy = true
            groupRecordingNote = RecordAll.progress(plan.direction)
        }
        try {
            for (tile in recordingTiles) {
                if (plan.targets.any { tile.entryId in it.entries }) tile.recordingNote = RecordAll.WAITING
            }
            val result = multicam().submit(plan)
            if (result == null) {
                // Stale: a camera, link or mode changed after the operator approved.
                if (together) groupRecordingNote = RecordAll.CHANGED
                return
            }
            val group = multicam().group
            for (tile in tiles) {
                val outcome = result.outcome(tile.entryId, group) ?: continue
                RecordAll.note(outcome, plan.direction)?.let { tile.recordingNote = it }
            }
            if (together) {
                val allMatch = recordingTiles.all { it.recordingAvailable && it.recordingObservation?.first == start }
                groupRecordingNote = RecordAll.summary(result, allMatch)
            }
        } finally {
            if (together) groupRecordingBusy = false
        }
    }

    fun remove(tile: Tile): Boolean {
        if (busy || tile.connecting || groupRecordingBusy || tile.recordingBusy) return false
        tile.reset()
        persistStage()
        return true
    }

    // --- Stage persistence and cleanup ---------------------------------------------------------------

    private fun savedCameras(): List<MultiviewStageJournal.Camera> =
        tiles.mapNotNull { tile ->
            val camera = tile.camera ?: return@mapNotNull null
            MultiviewStageJournal.Camera(
                slot = tile.index, id = camera.id, name = camera.name, modelId = camera.modelId,
                deviceAddress = camera.address, identity = tile.identity, address = tile.cameraAddress,
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
            MultiviewStageJournal.Stage(
                ssid = if (networkConfigured) ssid else "",
                hotspot = usePhoneHotspot,
                layout = layout.raw,
                focusedIndex = focusedIndex,
                cameras = saved,
                pendingReset = if (running && !closing) {
                    MultiviewStageJournal.cleanupTargets(pendingReset, saved)
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
    fun restoreStage(stage: MultiviewStageJournal.Stage? = MultiviewStageStore.load(app)) {
        stage ?: return
        pendingReset = stage.pendingReset.orEmpty()
        if (stage.returnedToCameraWiFi != true) {
            pendingReset = MultiviewStageJournal.cleanupTargets(pendingReset, stage.cameras)
        }
        cleanupJournalWritten = pendingReset.isNotEmpty()
        presentation.importLegacy(MultiviewStagePreferences(
            layout = if (MultiviewLayout.from(stage.layout) == MultiviewLayout.GRID) MultiviewStageLayout.GRID else MultiviewStageLayout.CENTER_STAGE,
            selected = stage.focusedIndex, fill = stage.fill == true,
        ))
        // Migrate unfinished camera cleanup before a new camera is added.
        if (cleanupJournalWritten) persistStage()
    }

    val hasPendingCleanup: Boolean get() = !running && pendingReset.isNotEmpty() && !closing

    /** Close every camera's monitor first, then restore its own access point in parallel. */
    suspend fun closeStage(): Boolean {
        if (closing) return false
        closing = true
        networkScanJob?.cancelAndJoin()
        if (running) pendingReset = MultiviewStageJournal.cleanupTargets(pendingReset, savedCameras())
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
    suspend fun resetStationOnce(saved: MultiviewStageJournal.Camera): Boolean {
        stationResets[saved.id]?.let { return it.await() }
        if (pendingReset.none { it.id == saved.id }) return true
        val task = scope.async {
            val success = resetCamera?.let { hook -> restoreCameraWiFiWithRetry { hook(saved) } }
                ?: commissioner.restoreAccessPoint(
                    StationCameraRecord(saved.id, saved.name, saved.modelId, saved.deviceAddress),
                )
            if (success) pendingReset = pendingReset.filterNot { it.id == saved.id }
            persistStage()
            stationResets.remove(saved.id)
            success
        }
        stationResets[saved.id] = task
        return task.await()
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

    private fun log(line: String) = multiviewLog(line)

    companion object {
        const val LIVE_STATUS = "Live · Video mode"
        private const val IDENTITY_KEY = (0x07 shl 8) or 0x07
        private const val RECORD_KEY = (0x02 shl 8) or 0x02
        private const val STATION_OPEN_MS = 15_000L
        private const val SUBSCRIBE_SETTLE_MS = 150L
    }
}

private fun List<Byte>.toByteArray(): ByteArray = ByteArray(size) { this[it] }
