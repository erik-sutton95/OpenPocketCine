package com.opencapture.openpocketcine.session

import com.opencapture.opencine.core.Availability
import com.opencapture.opencine.core.CameraCommand
import com.opencapture.opencine.core.CameraCommandIntent
import com.opencapture.opencine.core.CameraDeviceID
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.CameraSnapshot
import com.opencapture.opencine.core.CapabilitySnapshot
import com.opencapture.opencine.core.CaptureMode
import com.opencapture.opencine.core.CommandFailure
import com.opencapture.opencine.core.CommandPreconditions
import com.opencapture.opencine.core.CommandReceipt
import com.opencapture.opencine.core.CommandRejection
import com.opencapture.opencine.core.CommandStage
import com.opencapture.opencine.core.ConnectionAttemptID
import com.opencapture.opencine.core.ConnectionState
import com.opencapture.opencine.core.ControlAuthority
import com.opencapture.opencine.core.ControlEpoch
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.IntegrationID
import com.opencapture.opencine.core.MonotonicInstant
import com.opencapture.opencine.core.Observation
import com.opencapture.opencine.core.ObservationOrigin
import com.opencapture.opencine.core.ObservationPrecision
import com.opencapture.opencine.core.OperationID
import com.opencapture.opencine.core.PowerStatus
import com.opencapture.opencine.core.RecordingState
import com.opencapture.opencine.core.SessionCloseReason
import com.opencapture.opencine.core.SettingDescriptor
import com.opencapture.opencine.core.SettingDomain
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.StorageVolume
import com.opencapture.opencine.core.UnavailableReason
import com.opencapture.opencine.core.WhiteBalanceValue
import com.opencapture.opencine.core.rejection
import com.opencapture.openpocketcine.core.ConnectionPhase as PocketPhase
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Duration.Companion.seconds
import com.opencapture.opencine.core.CameraSession as OpenCineCameraSession
import com.opencapture.opencine.core.ConnectionPhase as CorePhase

/** Wire progress of one camera SET, reported by `PocketCameraSession.fireKind` (iOS `ControlWireEvent`). */
enum class ControlWireEvent {
    /** Refused locally, or replaced by a newer request before it reached the wire. */
    NOT_SENT,
    SENT,

    /** The camera ACKed. Its status may not show the value yet. */
    ACKNOWLEDGED,

    /** The camera's own status shows the requested value. */
    CONFIRMED,

    /** NACK. */
    REFUSED,

    /** The settle window closed with no ACK and no matching status. */
    UNCONFIRMED,
}

/** Camera-reported white balance: Kelvin is 0 in Auto. */
data class ReportedWhiteBalance(val mode: Int, val kelvin: Int, val tint: Int)

/**
 * What the seam reads from the Pocket session. `isoIndex`, `whiteBalance` and `recording` are
 * camera reports only, never the optimistic HUD values in `PocketCameraSession.status`.
 */
data class PocketControlState(
    /** A SET can go on the wire now (the `fireKind` admission rule, lease included). */
    val linkReady: Boolean = false,
    val authorized: Boolean = true,
    val recovering: Boolean = false,
    val phase: PocketPhase = PocketPhase.IDLE,
    val cameraId: String? = null,
    val shootingMode: Int = -1,
    val busy: Boolean = false,
    /** Legal `0x02/0x2A` index bytes; `0` (Auto) only where the color mode offers it. */
    val isoChoices: List<Int> = emptyList(),
    val isoIndex: Int? = null,
    val whiteBalance: ReportedWhiteBalance? = null,
    val recording: Boolean? = null,
    val batteryPercent: Int? = null,
    val storageFreeMb: Int? = null,
)

/** The Pocket session as the seam drives it. `PocketCameraSession` and the JVM tests implement it. */
interface PocketControlPort {
    fun controlState(): PocketControlState

    fun setIsoIndex(index: Int, onStage: ((ControlWireEvent) -> Unit)? = null)

    fun setWhiteBalanceAuto(tint: Int? = null, onStage: ((ControlWireEvent) -> Unit)? = null)

    fun setWhiteBalance(kelvin: Int, tint: Int, onStage: ((ControlWireEvent) -> Unit)? = null)

    fun setRecording(start: Boolean, onStage: ((ControlWireEvent) -> Unit)? = null)

    fun takePhoto()

    fun noteControlRejection(note: String)
}

/**
 * OpenCineCore `CameraSession` over the Pocket session for the CORE-02 slice: ISO, white balance
 * and record start/stop (iOS `DJICameraSessionAdapter`). One per `PocketCameraSession`; the
 * control epoch advances whenever the datalink is replaced. Confined to the main thread like
 * the session; [scope] runs only the timeouts.
 */
class DjiCameraSessionAdapter(
    private val port: PocketControlPort,
    private val scope: CoroutineScope,
    private val clock: () -> MonotonicInstant = ::systemNow,
) : OpenCineCameraSession {
    override val id: CameraSessionID = CameraSessionID()

    /** ACK to camera-reported value. Record telemetry trails its ACK by about 1 s. */
    // ponytail: hand-picked; tune against Pocket 3 / Pocket 4 record telemetry on hardware.
    var readbackTimeout: Duration = 3.seconds

    /** Admission to ACK or settle: coalesce hold plus the session's 2 s settle window. */
    var wireTimeout: Duration = 4.seconds

    private val _snapshots = MutableStateFlow(CameraSnapshot(session = id, epoch = ControlEpoch(1)))
    override val snapshots: StateFlow<CameraSnapshot> = _snapshots.asStateFlow()

    private var epoch = ControlEpoch(1)
    private var attempt = ConnectionAttemptID()
    private var closed = false

    // ponytail: receipts live as long as the session (Core contract); prune finished ones if a
    // long shoot ever makes this measurable.
    private val receipts = HashMap<OperationID, CommandReceipt>()
    private val open = HashMap<OperationID, Expectation>()
    private val waiters = HashMap<OperationID, CompletableDeferred<CommandReceipt>>()

    private class Expectation(var deadline: MonotonicInstant, val shows: (PocketControlState) -> Boolean)

    /** A snapshot rebuilt from the session right now. */
    val current: CameraSnapshot
        get() {
            rebuild()
            return _snapshots.value
        }

    // ---- UI entry points ----

    fun request(intent: CameraCommandIntent): CommandReceipt =
        send(CameraCommand(intent, CommandPreconditions(current)))

    /** White balance with the DJI tint; Core has no tint vocabulary yet. */
    fun setWhiteBalance(value: WhiteBalanceValue, tint: Int): CommandReceipt =
        send(CameraCommand(CameraCommandIntent.Set(SettingValue.WhiteBalance(value)), CommandPreconditions(current)), tint)

    fun setIsoIndex(index: Int): CommandReceipt =
        request(CameraCommandIntent.Set(SettingValue.Iso(iso(index))))

    fun setWhiteBalanceAuto(tint: Int? = null): CommandReceipt =
        if (tint == null) {
            request(CameraCommandIntent.Set(SettingValue.WhiteBalance(WhiteBalanceValue.Auto)))
        } else {
            setWhiteBalance(WhiteBalanceValue.Auto, tint)
        }

    /** Kelvin snaps to the 100 K steps the camera stores (`K/100` on the wire). */
    fun setWhiteBalanceCustom(kelvin: Int, tint: Int): CommandReceipt =
        setWhiteBalance(WhiteBalanceValue.Kelvin((kelvin.coerceIn(2_000, 10_000) + 50) / 100 * 100), tint)

    /**
     * Rec lamp: Photo fires a still; video resolves to an explicit start or stop from a fresh
     * snapshot, never a blind toggle (plan 5.4).
     */
    fun shutter(): CommandReceipt? {
        if (CameraCommands.isPhotoMode(port.controlState().shootingMode)) {
            port.takePhoto()
            return null
        }
        val recording = current.recording.value == RecordingState.RECORDING
        return request(if (recording) CameraCommandIntent.StopRecording else CameraCommandIntent.StartRecording)
    }

    fun receipt(operation: OperationID): CommandReceipt? = receipts[operation]

    // ---- session hooks ----

    /** Status, phase or busy changed. Cheap unless someone collects or a request awaits readback. */
    fun sessionDidChange() {
        if (closed) return
        if (_snapshots.subscriptionCount.value > 0) rebuild()
        if (open.isEmpty()) return
        val state = port.controlState()
        for ((operation, expectation) in open.toList()) {
            if (receipts[operation]?.stage == CommandStage.AwaitingObservation && expectation.shows(state)) {
                finish(operation, CommandStage.Confirmed)
            }
        }
    }

    /** The datalink was replaced or dropped. Requests on the old link cannot be followed. */
    fun linkDidChange() {
        if (closed) return
        epoch = epoch.next()
        for (operation in open.keys.toList()) abandon(operation)
        if (_snapshots.subscriptionCount.value > 0) rebuild()
    }

    // ---- OpenCineCore.CameraSession ----

    override suspend fun submit(command: CameraCommand): CommandReceipt = send(command)

    override suspend fun outcome(operation: OperationID): CommandReceipt? {
        val receipt = receipts[operation] ?: return null
        if (receipt.isFinished) return receipt
        return waiters.getOrPut(operation) { CompletableDeferred() }.await()
    }

    /** Ends this seam only. Never sends a camera command and never stops a recording. */
    override suspend fun close(reason: SessionCloseReason) {
        if (closed) return
        for (operation in open.keys.toList()) abandon(operation)
        closed = true
        val last = _snapshots.value
        _snapshots.value =
            last.copy(
                connection = ConnectionState.Disconnected(reason),
                authority = ControlAuthority.Unavailable(UnavailableReason.Link),
                revision = last.revision.next(),
            )
    }

    // ---- commands ----

    fun send(command: CameraCommand, tint: Int? = null): CommandReceipt {
        val operation = command.operation
        receipts[operation]?.let { return it }
        val snapshot = current
        receipts[operation] =
            CommandReceipt(
                operation, id, command.intent,
                confirmation = snapshot.capabilities[command.intent.key]?.semantics?.confirmation
                    ?: com.opencapture.opencine.core.SettingSemantics.Confirmation.READBACK,
            )
        val rejection = snapshot.rejection(command, clock()) ?: integrationRejection(command.intent, snapshot)
        if (rejection != null) {
            noteRejection(rejection)
            return advance(operation, CommandStage.Rejected(rejection))
        }
        advance(operation, CommandStage.Admitted)
        if (alreadyReported(command.intent, snapshot)) return advance(operation, CommandStage.Confirmed)
        val plan = wirePlan(command.intent, tint)
            ?: return advance(operation, CommandStage.Rejected(CommandRejection.Unsupported))
        open[operation] = Expectation(clock() + wireTimeout, plan.shows)
        expire(wireTimeout)
        plan.fire { event -> handle(event, operation) }
        return receipts.getValue(operation)
    }

    private class WirePlan(
        val shows: (PocketControlState) -> Boolean,
        val fire: ((ControlWireEvent) -> Unit) -> Unit,
    )

    /** Common intent to the DUML call that carries it, plus what the camera must report after. */
    private fun wirePlan(intent: CameraCommandIntent, tint: Int?): WirePlan? =
        when (intent) {
            is CameraCommandIntent.Set ->
                when (val value = intent.value) {
                    is SettingValue.Iso -> isoIndex(value.value)?.let { index ->
                        WirePlan({ it.isoIndex == index }) { onStage -> port.setIsoIndex(index, onStage) }
                    }
                    is SettingValue.WhiteBalance -> {
                        val t = (tint ?: port.controlState().whiteBalance?.tint ?: 0).coerceIn(-100, 100)
                        when (val wb = value.value) {
                            WhiteBalanceValue.Auto -> {
                                val target = ReportedWhiteBalance(CameraCommands.WB_AUTO, 0, t)
                                WirePlan({ it.whiteBalance == target }) { onStage ->
                                    port.setWhiteBalanceAuto(t, onStage)
                                }
                            }
                            is WhiteBalanceValue.Kelvin -> {
                                val k = wb.kelvin.coerceIn(2_000, 10_000)
                                val target = ReportedWhiteBalance(CameraCommands.WB_CUSTOM, k, t)
                                WirePlan({ it.whiteBalance == target }) { onStage ->
                                    port.setWhiteBalance(k, t, onStage)
                                }
                            }
                            is WhiteBalanceValue.Preset -> null
                        }
                    }
                    else -> null
                }
            CameraCommandIntent.StartRecording, CameraCommandIntent.StopRecording -> {
                val start = intent == CameraCommandIntent.StartRecording
                WirePlan({ it.recording == start }) { onStage -> port.setRecording(start, onStage) }
            }
            is CameraCommandIntent.FocusPoint -> null
        }

    private fun handle(event: ControlWireEvent, operation: OperationID) {
        // A finished receipt is final: a late ACK never rewrites an outcome.
        val expectation = open[operation] ?: return
        when (event) {
            ControlWireEvent.NOT_SENT -> finish(operation, CommandStage.Failed(CommandFailure.NOT_SENT))
            ControlWireEvent.SENT -> advance(operation, CommandStage.Sent)
            ControlWireEvent.ACKNOWLEDGED -> {
                advance(operation, CommandStage.Accepted)
                if (expectation.shows(port.controlState())) {
                    finish(operation, CommandStage.Confirmed)
                } else {
                    advance(operation, CommandStage.AwaitingObservation)
                    expectation.deadline = clock() + readbackTimeout
                    expire(readbackTimeout)
                }
            }
            // Only the camera-reported values decide, whoever claims the match.
            ControlWireEvent.CONFIRMED ->
                finish(
                    operation,
                    if (expectation.shows(port.controlState())) CommandStage.Confirmed else CommandStage.TimedOut,
                )
            ControlWireEvent.REFUSED -> finish(operation, CommandStage.Rejected(CommandRejection.CameraRefused))
            ControlWireEvent.UNCONFIRMED -> finish(operation, CommandStage.TimedOut)
        }
    }

    private fun noteRejection(rejection: CommandRejection) {
        when (rejection) {
            CommandRejection.SessionClosed, CommandRejection.WrongSession, CommandRejection.NotConnected,
            CommandRejection.StaleEpoch, CommandRejection.NoAuthority,
            -> port.noteControlRejection("not live")
            CommandRejection.RecordingStateUnknown -> port.noteControlRejection("Waiting for the camera's record state")
            else -> Unit
        }
    }

    private fun expire(after: Duration) {
        scope.launch {
            delay(after)
            expireOverdue()
        }
    }

    private fun expireOverdue() {
        val now = clock()
        for ((operation, expectation) in open.toList()) {
            if (expectation.deadline > now) continue
            if (receipts[operation]?.stage == CommandStage.AwaitingObservation) {
                finish(operation, CommandStage.TimedOut)
            } else {
                abandon(operation)
            }
        }
    }

    /** Unsent work fails; sent work may have reached the camera, so its outcome is unknown. */
    private fun abandon(operation: OperationID) {
        when (receipts[operation]?.stage) {
            CommandStage.Created, CommandStage.Admitted ->
                finish(operation, CommandStage.Failed(CommandFailure.NOT_SENT))
            else -> finish(operation, CommandStage.OutcomeUnknown)
        }
    }

    private fun finish(operation: OperationID, stage: CommandStage): CommandReceipt {
        open.remove(operation)
        return advance(operation, stage)
    }

    private fun advance(operation: OperationID, stage: CommandStage): CommandReceipt {
        val receipt = receipts.getValue(operation).copy(stage = stage)
        receipts[operation] = receipt
        if (receipt.isFinished) waiters.remove(operation)?.complete(receipt)
        return receipt
    }

    // ---- snapshot mapping (raw DJI state to common values) ----

    private fun rebuild() {
        if (closed) return
        val state = port.controlState()
        val last = _snapshots.value
        val connection = connection(state, last.connection)
        val descriptors = descriptors(state)
        val capabilities =
            if (CapabilitySnapshot(last.capabilities.revision, descriptors) == last.capabilities) {
                last.capabilities
            } else {
                CapabilitySnapshot(last.capabilities.revision.next(), descriptors)
            }
        val next =
            last.copy(
                epoch = epoch,
                device = state.cameraId?.let { CameraDeviceID.durable(it, INTEGRATION) },
                connection = connection,
                authority = when {
                    connection != ConnectionState.Ready -> ControlAuthority.Unavailable(UnavailableReason.Link)
                    state.authorized -> ControlAuthority.Owner
                    else -> ControlAuthority.Unavailable(UnavailableReason.Authority)
                },
                capabilities = capabilities,
                mode = mode(state.shootingMode),
                settings = settings(state),
                recording = state.recording?.let {
                    Observation(if (it) RecordingState.RECORDING else RecordingState.IDLE, ObservationOrigin.CAMERA_REPORTED, null)
                } ?: Observation.unknown,
                power = state.batteryPercent?.let {
                    PowerStatus(
                        battery = Observation(
                            it / 100.0, ObservationOrigin.CAMERA_REPORTED, null,
                            precision = ObservationPrecision.Quantized(0.01),
                        ),
                    )
                } ?: PowerStatus.unknown,
                storage = state.storageFreeMb?.let {
                    val free = Observation(it.toLong() * 1_048_576L, ObservationOrigin.CAMERA_REPORTED, null)
                    Observation(listOf(StorageVolume("active", freeBytes = free)), ObservationOrigin.CAMERA_REPORTED, null)
                } ?: Observation.unknown,
            )
        if (next == last) return
        _snapshots.value = next.copy(revision = last.revision.next())
    }

    private fun connection(state: PocketControlState, last: ConnectionState): ConnectionState {
        if (state.linkReady) return ConnectionState.Ready
        if (last !is ConnectionState.Connecting && last !is ConnectionState.Recovering) attempt = ConnectionAttemptID()
        if (state.recovering) return ConnectionState.Recovering(attempt)
        return when (state.phase) {
            PocketPhase.SCANNING, PocketPhase.CONNECTING_GATT, PocketPhase.PAIRING, PocketPhase.READING_WIFI_CREDS ->
                ConnectionState.Connecting(attempt, CorePhase.LINK)
            PocketPhase.AWAITING_APPROVAL -> ConnectionState.Connecting(attempt, CorePhase.AWAITING_APPROVAL)
            PocketPhase.JOINING_WIFI -> ConnectionState.Connecting(attempt, CorePhase.JOINING_NETWORK)
            PocketPhase.OPENING_DATALINK -> ConnectionState.Connecting(attempt, CorePhase.NEGOTIATING)
            // Core has no "open but not linked" state; this session object outlives links.
            PocketPhase.IDLE, PocketPhase.LIVE, PocketPhase.FAILED -> ConnectionState.Discovered
        }
    }

    /** Declared support is exactly what [wirePlan] routes. A JVM test holds the two together. */
    private fun descriptors(state: PocketControlState): List<SettingDescriptor> {
        val recording: Availability =
            when {
                CameraCommands.isPhotoMode(state.shootingMode) -> Availability.Unavailable(UnavailableReason.Mode)
                state.busy -> Availability.Unavailable(UnavailableReason.Busy)
                else -> Availability.Available
            }
        return listOf(
            SettingDescriptor(
                SettingKey.ISO,
                domain = SettingDomain(choices = state.isoChoices.map { SettingValue.Iso(iso(it)) }.distinct()),
            ),
            SettingDescriptor(
                SettingKey.WHITE_BALANCE,
                domain = SettingDomain(
                    choices = listOf(SettingValue.WhiteBalance(WhiteBalanceValue.Auto)),
                    range = 2_000.0..10_000.0,
                    step = 100.0,
                ),
            ),
            SettingDescriptor(SettingKey.RECORDING, availability = recording),
        )
    }

    private fun settings(state: PocketControlState): Map<SettingKey, Observation<SettingValue>> =
        buildMap {
            state.isoIndex?.let {
                put(SettingKey.ISO, Observation(SettingValue.Iso(iso(it)), ObservationOrigin.CAMERA_REPORTED, null))
            }
            state.whiteBalance?.let {
                val value =
                    if (it.mode == CameraCommands.WB_CUSTOM) WhiteBalanceValue.Kelvin(it.kelvin) else WhiteBalanceValue.Auto
                put(SettingKey.WHITE_BALANCE, Observation(SettingValue.WhiteBalance(value), ObservationOrigin.CAMERA_REPORTED, null))
            }
        }

    companion object {
        val INTEGRATION: IntegrationID = IntegrationID("org.opencapture.openpocketcine.dji")

        private val reference = System.nanoTime()

        fun systemNow(): MonotonicInstant = MonotonicInstant((System.nanoTime() - reference).nanoseconds)

        fun iso(index: Int): ISOValue = CameraCommands.isoValue(index)?.let { ISOValue.Manual(it) } ?: ISOValue.Auto

        fun isoIndex(value: ISOValue): Int? =
            when (value) {
                ISOValue.Auto -> 0
                is ISOValue.Manual -> CameraCommands.isoIndexFromValue(value.iso)
                is ISOValue.AutoLimited -> null
            }

        private fun mode(raw: Int): Observation<CaptureMode> {
            if (raw < 0) return Observation.unknown
            val role = if (CameraCommands.isPhotoMode(raw)) CaptureMode.Role.PHOTO else CaptureMode.Role.VIDEO
            return Observation(
                CaptureMode(role, "${INTEGRATION.rawValue}.mode.$raw", "Mode $raw"),
                ObservationOrigin.CAMERA_REPORTED, null,
            )
        }

        /**
         * The DJI record frames are value-shaped (`0x02/0x02` 01/00) but the app has only sent
         * them as a toggle of the reported state; a start while already recording is not
         * hardware-qualified. Unknown state is refused.
         */
        private fun integrationRejection(intent: CameraCommandIntent, snapshot: CameraSnapshot): CommandRejection? =
            when (intent) {
                CameraCommandIntent.StartRecording, CameraCommandIntent.StopRecording ->
                    if (snapshot.recording.isKnown) null else CommandRejection.RecordingStateUnknown
                else -> null
            }

        /** Idempotency: start while recording (or stop while idle) finishes without the wire. */
        private fun alreadyReported(intent: CameraCommandIntent, snapshot: CameraSnapshot): Boolean =
            when (intent) {
                CameraCommandIntent.StartRecording -> snapshot.recording.value == RecordingState.RECORDING
                CameraCommandIntent.StopRecording -> snapshot.recording.value == RecordingState.IDLE
                else -> false
            }
    }
}
