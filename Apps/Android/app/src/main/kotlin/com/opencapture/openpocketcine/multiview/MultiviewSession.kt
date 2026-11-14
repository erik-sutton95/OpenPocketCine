package com.opencapture.openpocketcine.multiview

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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.opencapture.opencine.appkit.MultiviewStageJournal
import com.opencapture.opencine.appkit.MultiviewCoordinator
import com.opencapture.opencine.appkit.MultiviewHost
import com.opencapture.opencine.appkit.MultiviewJournalStorage
import com.opencapture.opencine.appkit.MultiviewMember
import com.opencapture.opencine.appkit.MultiviewMemberChange
import com.opencapture.opencine.appkit.MultiviewNetworkStorage
import com.opencapture.opencine.appkit.anyRecording
import com.opencapture.opencine.appkit.canRecordTogether
import com.opencapture.opencine.appkit.record
import com.opencapture.opencine.appkit.recordPlan
import com.opencapture.opencine.core.MultiviewRecordReport
import com.opencapture.opencine.core.NearbyCameraScanner
import com.opencapture.opencine.core.StationRestoreResult
import com.opencapture.opencine.appkit.race
import com.opencapture.opencine.appkit.MultiviewStageState
import com.opencapture.opencine.appkit.MultiviewStageLayout
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
import com.opencapture.opencine.core.StationNetwork
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.opencine.vocabulary.LutLookResolver
import com.opencapture.opencine.vocabulary.LutLookSource
import com.opencapture.opencine.multicam.RecordPlan
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
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
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

        /**
         * The stage's half of this tile (camera, copy, control host, record state, recovery
         * budget), owned by OpenCine's `MultiviewCoordinator`; the properties below forward to it.
         */
        val member = MultiviewMember<FoundCamera>(UUID.fromString(id))
        /** Stable multicam slot: this tile's identity through layout, selection and rotation. */
        val entryId: MonitorEntryID get() = member.entryID
        /** The tile's picture stream, named for the multicam engine. */
        val stream: StreamID get() = member.stream
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
        var connecting: Boolean
            get() = member.connecting
            set(value) { member.connecting = value }
        var experimentalNetwork: Boolean
            get() = member.experimental
            set(value) { member.experimental = value }
        var networkVerified: Boolean
            get() = member.networkVerified
            set(value) { member.networkVerified = value }
        var cameraAddress: String
            get() = member.address
            set(value) { member.address = value }
        var identity: ByteArray?
            get() = member.identity
            set(value) { member.identity = value }
        /** Latest reply per DUML key with its receive time. */
        val responses = HashMap<Int, Pair<DumlFrame, Long>>()
        var camera: FoundCamera?
            get() = member.camera
            set(value) { member.camera = value }
        var status: String
            get() = member.status
            set(value) { member.status = value }
        var failureMessage: String?
            get() = member.failureMessage
            set(value) { member.failureMessage = value }
        /** DJI's own feed-watchdog ladder on this tile's link; the rejoin budget is the member's. */
        val recovery = MultiviewRecoveryLadder()
        var recovering: Boolean
            get() = member.recovering
            set(value) { member.recovering = value }
        var checkForegroundDecoder = false
        var foregroundRepairAt: Long? = null
        var settings by mutableStateOf(CameraStatus())
        var pose = GimbalStickMapping()
        var poseViewFlip by mutableStateOf(false)
        var latestSettings = CameraStatus()
        private var settingsPublishedAt = 0L
        internal val feedEffectsPlans = MonitorFeedEffectsPlans(SwiftCore)
        var lutEnabled: Boolean
            get() = member.lutEnabled
            set(value) { member.lutEnabled = value }
        internal var plan by mutableStateOf(FeedEffectsRenderPlan.IDENTITY)
        /** Camera settings' preview owner; the tile's existing present tap feeds it while set. */
        internal var previewOwner by mutableStateOf<Any?>(null)
        var lutCaption by mutableStateOf("Auto LUT")
        var hasPicture by mutableStateOf(false)
        var publishing: Boolean
            get() = member.publishing
            set(value) { member.publishing = value }
        /** The member link's own record that its control link is up (it reported `CONTROLLING`). */
        private var controlLinkUp = false
        /** The status this link last reported; read on the decoder thread. */
        @Volatile private var reported: MultiviewLinkStatus? = null
        var recordingBusy: Boolean
            get() = member.recordingBusy
            set(value) { member.recordingBusy = value }
        var recordingAvailable: Boolean
            get() = member.recordingAvailable
            set(value) { member.recordingAvailable = value }
        var recordingNote: String?
            get() = member.recordingNote
            set(value) { member.recordingNote = value }
        var controlHost: String?
            get() = member.controlHost
            set(value) { member.controlHost = value }
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

        /** The camera's own latest take report on this link (`02/80`), on the elapsed-realtime clock. */
        override val recordReport: MultiviewRecordReport?
            get() = recordingObservation?.let { MultiviewRecordReport(it.first, it.second) }

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
            // A new link starts DJI's watchdog ladder over; the member's budget stays the coordinator's.
            recovery.reset()
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
            // A sustained live transport restores the member's rejoin budget.
            context.observeHealth(udpAlive)
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

        /** What the tile itself drops when the stage removes its member (the stage clears the member). */
        internal fun clearLocal() {
            recovery.reset()
            foregroundRepairAt = null
            settings = CameraStatus()
            latestSettings = CameraStatus()
            pose = GimbalStickMapping()
            poseViewFlip = false
            updateLUT()
            previewStarted = null
            recordingObservation = null
            responses.clear()
            hasPicture = false
            enableSends = 0
            lastEnable = 0L
            decoder.reset()
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val path = SharedWiFi(app)
    val tiles: List<Tile> = List(MultiviewQualificationPolicy.tileCount) { Tile(it, app, scope, path) }
    private val scanner = BleLink(app)

    /**
     * The shared stage (OpenCine's `MultiviewCoordinator`): lifecycle, network, discovery, adds,
     * recovery budgets, record plans, editor leases, the journal and close. This session is its
     * host: the tiles' pictures and surfaces, Live View and the editors are Pocket's. Differences
     * kept on purpose: 24 probes a batch, the early identity read, the decoder rebuild after Live
     * View and repair only while a surface is mounted.
     */
    val coordinator: MultiviewCoordinator<FoundCamera, Tile>

    init {
        val commissioner = PocketStationCommissioner(
            DjiStationCommissioner(app, path, ::log), resetCamera,
            identityRead = { camera, identity -> tiles.firstOrNull { it.camera?.id == camera.id }?.identity = identity },
        )
        coordinator = MultiviewCoordinator(
            links = tiles,
            members = tiles.map { it.member },
            policy = MultiviewCameraPolicy.dji,
            commissioner = commissioner,
            scanner = BleScanner(scanner),
            hostPath = path,
            describe = commissioner::record,
            journal = MultiviewJournalStorage(load = { MultiviewStageStore.load(app) }, save = saveStage),
            networks = MultiviewNetworkStorage(
                password = { ssid, hotspot -> networkStore.load(ssid, hotspot)?.password },
                save = { networkStore.save(it.ssid, it.password, it.hotspot) },
            ),
            scope = scope,
            budget = MultiviewQualificationPolicy.budget,
            failureMessage = { it.message ?: "Could not connect" },
            // Android probes 24 hosts at a time (the handbook's number; iOS 64).
            probeWidth = 24,
            clock = SystemClock::elapsedRealtime,
        )
        coordinator.host = Host()
    }

    val found: List<FoundCamera> get() = coordinator.found
    var busy: Boolean
        get() = coordinator.busy
        set(value) { coordinator.busy = value }
    val ready: Boolean get() = coordinator.ready
    var ssid: String
        get() = coordinator.ssid
        set(value) { coordinator.ssid = value }
    var usePhoneHotspot: Boolean
        get() = coordinator.usePhoneHotspot
        set(value) { coordinator.usePhoneHotspot = value }
    var password: String
        get() = coordinator.password
        set(value) { coordinator.password = value }
    val groupRecordingBusy: Boolean get() = coordinator.groupRecordingBusy
    val groupRecordingNote: String? get() = coordinator.groupRecordingNote
    val recordingTiles: List<Tile> get() = tiles.filter { it.camera != null }
    val anyRecording: Boolean get() = coordinator.anyRecording
    val canRecordTogether: Boolean get() = coordinator.canRecordTogether

    /**
     * The operator's record button as an explicit strict plan: stop when any requested camera
     * reports recording, else start. `tile == null` is Record all. The confirmation dialog holds
     * this value; any change to it (camera, link epoch, mode, availability, reported recording)
     * dismisses the dialog, routine telemetry does not.
     */
    fun recordPlan(tile: Tile? = null): RecordPlan = coordinator.recordPlan(tile?.index)

    val networkConfigured: Boolean get() = coordinator.networkConfigured
    val configuringNetwork: Boolean get() = coordinator.configuringNetwork
    val networkSetupError: String? get() = coordinator.networkSetupError
    val applicationActive: Boolean get() = coordinator.applicationActive
    val host: String get() = coordinator.hostAddress
    var error: String?
        get() = coordinator.error
        set(value) { coordinator.error = value }
    val presentation: MultiviewStageState get() = coordinator.presentation
    var layout: MultiviewLayout
        get() = MultiviewLayout.from(presentation.layout.rawValue)
        set(value) { presentation.layout = if (value == MultiviewLayout.GRID) MultiviewStageLayout.GRID else MultiviewStageLayout.CENTER_STAGE }
    var fill: Boolean
        get() = presentation.fill
        set(value) { presentation.fill = value }
    var focusedIndex: Int
        get() = presentation.selected
        set(value) { presentation.selected = value }
    val closing: Boolean get() = coordinator.closing
    val connectingCameras: Boolean get() = coordinator.connectingCameras
    val hasPendingCleanup: Boolean get() = coordinator.hasPendingCleanup

    /** The stage's rule, plus what only Pocket knows: the tile's own open datalink and a borrowed Live View. */
    internal fun controlsAvailable(tile: Tile): Boolean =
        coordinator.controlsAvailable(tile.index) &&
            tile.driver?.let { !it.isClosed && !it.isRebuilding } == true && tile.liveModel == null

    /**
     * One settings editor at a time. The engine's editor lease names the tile's session and control
     * epoch: switching tiles, a replaced link or camera, or lost authority retires it, so a queued
     * SET can never reach another camera (plan 7.5).
     */
    fun openControls(tile: Tile): AppModel? {
        val lease = coordinator.openEditorLease(tile.index) ?: return null
        return tile.openControls { coordinator.editorAdmits(lease, tile.index) && controlsAvailable(tile) }
    }

    // --- Borrowed Live View -------------------------------------------------------------------

    fun openLiveView(tile: Tile) {
        coordinator.openLiveView(tile.index)
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
        coordinator.closeLiveView()
    }

    // --- Lifecycle -------------------------------------------------------------------------------

    fun start() {
        path.hotspot = false
        coordinator.start()
    }

    fun scan() = coordinator.scan()

    fun setApplicationActive(active: Boolean) = coordinator.setApplicationActive(active)

    fun stop() = coordinator.stop()

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
        coordinator.selectNetworkSource(hotspot)
        path.hotspot = coordinator.usePhoneHotspot
    }

    fun selectNetwork(name: String) = coordinator.selectNetwork(name)

    suspend fun configureNetwork(): Boolean = coordinator.configureNetwork()

    /** Shared wizard scan: hold ownership through cancellation and same-link AP cleanup. */
    suspend fun scanNetworks(onFound: (String) -> Unit) = coordinator.scanNetworks(onFound)

    fun savedNetworks(): List<MultiviewNetworkStore.Network> = networkStore.savedNetworks()

    // --- Cameras ---------------------------------------------------------------------------------

    fun enqueueAdd(camera: FoundCamera, tile: Tile, experimental: Boolean = false) =
        coordinator.enqueueAdd(camera, tile.index, experimental)

    suspend fun add(camera: FoundCamera, tile: Tile, experimental: Boolean = false) =
        coordinator.add(camera, tile.index, experimental)

    suspend fun reconnect(tile: Tile) = coordinator.reconnect(tile.index)

    suspend fun tryExperimentalNetwork(tile: Tile) = coordinator.tryExperimentalNetwork(tile.index)

    suspend fun connectPreview(tile: Tile) = coordinator.connectPreview(tile.index)

    /**
     * Sends an approved plan: one explicit start or stop per camera, revalidated first, each
     * outcome on its own tile. A partial result is never compensated; stopping a camera that
     * started is a separate operator action.
     */
    suspend fun record(plan: RecordPlan, together: Boolean) = coordinator.record(plan, together)

    fun remove(tile: Tile): Boolean = coordinator.remove(tile.index)

    // --- Stage persistence and cleanup ---------------------------------------------------------------

    fun persistStage(): Boolean = coordinator.persistStage()

    /**
     * A new session always asks for a network and starts with empty slots. Old
     * stages supply presentation preferences and cleanup obligations only.
     */
    fun restoreStage(stage: MultiviewStageJournal.Stage? = MultiviewStageStore.load(app)) =
        coordinator.restoreStage(stage)

    /** Close every camera's monitor first, then restore its own access point in parallel. */
    suspend fun closeStage(): Boolean = coordinator.closeStage()

    /** Shared by scan completion, close and restored cleanup; one reset per camera at a time. */
    suspend fun resetStationOnce(saved: MultiviewStageJournal.Camera): Boolean = coordinator.resetStationOnce(saved)

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

    /** The coordinator's host: what only Pocket has (pictures, surfaces, Live View, editors). */
    private inner class Host : MultiviewHost {
        override fun openLiveView(slot: Int): Boolean {
            val tile = tiles[slot]
            val camera = tile.camera ?: return false
            val model = AppModel(app, borrowing = tile.decoder)
            model.session.updateMultiview(camera, tile.driver, tile.latestSettings)
            model.session.adoptMultiviewPose(tile.pose)
            model.setBorrowedLut(tile.lutEnabled)
            model.borrowMonitor(camera) { releaseLiveView(tile) }
            tile.liveModel = model
            return true
        }

        override fun closeLiveView() {
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
            coordinator.restartRepairGrace()
        }

        override fun closeEditors() {
            for (tile in tiles) tile.closeControls()
        }

        override fun memberChanged(slot: Int, change: MultiviewMemberChange) {
            val tile = tiles[slot]
            when (change) {
                MultiviewMemberChange.CAMERA -> {
                    tile.closeControls()
                    tile.control.linkDidChange()
                }
                MultiviewMemberChange.CONTROL -> tile.closeControls()
                MultiviewMemberChange.REMOVED -> tile.clearLocal()
            }
        }

        override fun applicationActivityChanged(active: Boolean) {
            // Keep camera assignments and sockets. Foreground watchdog owns repair.
            if (active) for (tile in tiles) if (tile.publishing) tile.checkForegroundDecoder = true
        }

        override fun stageStopped() {
            for (tile in tiles) tile.decoder.reset()
        }

        /** A tile repairs only while its link is open and a surface shows its picture. */
        override fun showsPicture(slot: Int): Boolean = tiles[slot].let { it.driver != null && it.surfaceMounted }

        override fun log(line: String) = multiviewLog(line)
    }

    companion object {
        const val LIVE_STATUS = "Live · Video mode"
        private const val IDENTITY_KEY = (0x07 shl 8) or 0x07
        private const val RECORD_KEY = (0x02 shl 8) or 0x02
        private const val STATION_OPEN_MS = 15_000L
        private const val SUBSCRIBE_SETTLE_MS = 150L
    }
}

/** Pocket's nearby DJI discovery as the stage's scanner. */
private class BleScanner(private val ble: BleLink) : NearbyCameraScanner<FoundCamera> {
    override suspend fun waitUntilReady(): Boolean = true

    override suspend fun scan(found: (FoundCamera) -> Unit) {
        ble.startScan()
        ble.found.collect { list -> for (camera in list) found(camera) }
    }

    override fun stop() = ble.stopScan()
}

/**
 * DJI's station commissioner with Pocket's two additions: the test hook that replaces only the
 * radio step of a camera's return (the bounded retry around it stays), and the early identity
 * read, kept through a lost join reply so Reconnect re-runs discovery only.
 */
private class PocketStationCommissioner(
    private val base: DjiStationCommissioner,
    private val resetCamera: (suspend (MultiviewStageJournal.Camera) -> Boolean)?,
    private val identityRead: (FoundCamera, ByteArray?) -> Unit,
) : StationCommissioner<FoundCamera> {
    override val scansNetworks: Boolean get() = base.scansNetworks

    override fun record(camera: FoundCamera): StationCameraRecord = base.record(camera)

    override suspend fun connect(camera: FoundCamera, progress: (String) -> Unit): StationCommission {
        val commission = base.connect(camera, progress)
        return object : StationCommission {
            override suspend fun identity(): ByteArray = commission.identity().also { identityRead(camera, it) }

            override suspend fun join(
                network: StationNetwork,
                identity: ByteArray,
                experimental: Boolean,
                progress: (String) -> Unit,
                verifyOnNetwork: suspend () -> Boolean,
            ): StationCommissionOutcome = try {
                commission.join(network, identity, experimental, progress, verifyOnNetwork)
            } catch (error: StationJoin.Failure) {
                identityRead(camera, null)
                throw error
            }

            override fun close() = commission.close()
        }
    }

    override fun closeCommissions() = base.closeCommissions()

    override suspend fun restoreAccessPoint(record: StationCameraRecord): StationRestoreResult {
        val hook = resetCamera ?: return base.restoreAccessPoint(record)
        val saved = MultiviewStageJournal.Camera(
            slot = 0, id = record.id, name = record.name, modelId = record.modelId, identity = null,
            deviceAddress = record.deviceAddress, address = "", experimental = false, lutEnabled = false,
        )
        return if (restoreCameraWiFiWithRetry { hook(saved) }) StationRestoreResult.Restored else StationRestoreResult.Failed
    }

    override suspend fun scanNetworks(
        camera: FoundCamera,
        beforeStationChange: () -> Unit,
        onRestored: (Boolean) -> Unit,
        onFound: (String) -> Unit,
    ) = base.scanNetworks(camera, beforeStationChange, onRestored, onFound)
}

private fun List<Byte>.toByteArray(): ByteArray = ByteArray(size) { this[it] }
