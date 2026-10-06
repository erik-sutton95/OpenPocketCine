package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.core.CameraSession
import com.opencapture.opencine.core.CameraSessionID
import com.opencapture.opencine.core.CommandRejection
import com.opencapture.opencine.core.ControlAuthority
import com.opencapture.opencine.core.MonitorEntryDescriptor
import com.opencapture.opencine.core.MonitorEntryID
import com.opencapture.opencine.core.PictureHealth
import com.opencapture.opencine.core.PictureSourceDescriptor
import com.opencapture.opencine.core.StreamID
import com.opencapture.opencine.core.TelemetrySource
import com.opencapture.opencine.multicam.MulticamGroup
import com.opencapture.opencine.multicam.MulticamSnapshot
import com.opencapture.opencine.multicam.RecordDirection
import com.opencapture.opencine.multicam.RecordPlan
import com.opencapture.opencine.multicam.RecordResult
import com.opencapture.opencine.multicam.RecordSubmissionException
import com.opencapture.opencine.multicam.TargetOutcome
import com.opencapture.opencine.multicam.TargetPolicy
import com.opencapture.opencine.dji.ControlWireEvent
import com.opencapture.opencine.dji.DjiCameraSessionAdapter
import com.opencapture.opencine.dji.PocketControlPort
import com.opencapture.opencine.dji.PocketControlState
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.ConnectionPhase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What a tile's record seam reads from it (iOS `MultiviewTileControl.status` and `link`). */
internal data class TileRecordState(
    /** The tile's datalink object; a different one is a replaced link. `null`: no link. */
    val link: Any? = null,
    /** A control host is verified for [link]. */
    val controlHost: Boolean = false,
    val connecting: Boolean = false,
    val recovering: Boolean = false,
    val cameraId: String? = null,
    val shootingMode: Int = -1,
    val recordingBusy: Boolean = false,
    /** Latest `02/80` recording flag and its elapsed-realtime receive time. */
    val observation: Pair<Boolean, Long>? = null,
    /** Pocket's qualification: the observation is fresh (under 3 s, sampled each second). */
    val recordingAvailable: Boolean = false,
    val batteryPercent: Int = -1,
    val storageFreeMb: Int = 0,
    val storageTotalMb: Int = 0,
    /** The tile's body, so the adapter declares what it reports (timecode). */
    val model: CameraModel? = null,
)

/**
 * A Multiview tile's record path as [DjiCameraSessionAdapter] drives it, so the multicam engine
 * sees each tile as a common camera session (MULTI-02, iOS `MultiviewTileControl`). The tile
 * keeps its datalink, decoder and repair ownership; this reads its state and sends the explicit
 * record command on the tile's own link. It never opens a link and is not a second command pump:
 * settings stay on the editor's borrowed session.
 */
internal class MultiviewTileControl(
    private val state: () -> TileRecordState,
    /** Sends start or stop on the tile's link; `false` when it never left the phone. */
    private val send: suspend (start: Boolean) -> Boolean,
    /** Reply to the record command received at or after `since`: `true` ACK, `false` NACK. */
    private val reply: (since: Long) -> Boolean?,
    private val setBusy: (Boolean) -> Unit,
    private val scope: CoroutineScope,
    private val clock: () -> Long,
) : PocketControlPort {
    /** Pocket's record confirmation window: a reply or a matching report within 8 s. */
    var confirmationWindowMs = 8_000L

    override fun controlState(): PocketControlState {
        val tile = state()
        return PocketControlState(
            linkReady = tile.link != null && tile.controlHost && !tile.connecting && !tile.recovering,
            recovering = tile.recovering,
            phase = if (tile.connecting) ConnectionPhase.OPENING_DATALINK else ConnectionPhase.IDLE,
            cameraId = tile.cameraId,
            shootingMode = tile.shootingMode,
            busy = tile.recordingBusy,
            // ponytail: tiles route only record; ISO and white balance stay on the editor's
            // mailbox, so they are declared with no choices and never reach this port.
            recording = tile.observation?.first?.takeIf { tile.recordingAvailable },
            batteryPercent = tile.batteryPercent.takeIf { it in 0..100 },
            storageFreeMb = tile.storageFreeMb.takeIf { tile.storageTotalMb > 0 },
            model = tile.model,
        )
    }

    override fun setIsoIndex(index: Int, onStage: ((ControlWireEvent) -> Unit)?) {
        onStage?.invoke(ControlWireEvent.NOT_SENT)
    }

    override fun setWhiteBalanceAuto(tint: Int?, onStage: ((ControlWireEvent) -> Unit)?) {
        onStage?.invoke(ControlWireEvent.NOT_SENT)
    }

    override fun setWhiteBalance(kelvin: Int, tint: Int, onStage: ((ControlWireEvent) -> Unit)?) {
        onStage?.invoke(ControlWireEvent.NOT_SENT)
    }

    override fun takePhoto() = Unit

    /** The session writes one note per tile from the record outcome. */
    override fun noteControlRejection(note: String) = Unit

    /**
     * One explicit start or stop on the tile's link: NACK refuses, the camera's own newer report
     * confirms, the window closing leaves it unconfirmed. A replaced link ends the wait; the
     * adapter has already abandoned the request as outcome unknown.
     */
    override fun setRecording(start: Boolean, onStage: ((ControlWireEvent) -> Unit)?) {
        val link = state().link
        if (link == null || !state().controlHost || state().recordingBusy) {
            onStage?.invoke(ControlWireEvent.NOT_SENT)
            return
        }
        setBusy(true)
        scope.launch {
            var event = ControlWireEvent.UNCONFIRMED
            try {
                val sent = clock()
                if (!send(start)) {
                    event = ControlWireEvent.NOT_SENT
                    return@launch
                }
                onStage?.invoke(ControlWireEvent.SENT)
                var acknowledged = false
                while (clock() < sent + confirmationWindowMs) {
                    delay(100)
                    val tile = state()
                    if (tile.link !== link) return@launch
                    when (reply(sent)) {
                        false -> {
                            event = ControlWireEvent.REFUSED
                            return@launch
                        }
                        true -> if (!acknowledged) {
                            acknowledged = true
                            onStage?.invoke(ControlWireEvent.ACKNOWLEDGED)
                        }
                        null -> Unit
                    }
                    val observation = tile.observation
                    if (observation != null && observation.second > sent && observation.first == start) {
                        event = ControlWireEvent.CONFIRMED
                        return@launch
                    }
                }
            } finally {
                setBusy(false)
                onStage?.invoke(event)
            }
        }
    }
}

/** One tile with a camera as the multicam engine sees it (iOS `MultiviewSession.Tile.entry`). */
internal class MulticamTile(
    /** The tile's own identity: kept through layout, selection and rotation. */
    val id: MonitorEntryID,
    val name: String,
    val stream: StreamID,
    val control: DjiCameraSessionAdapter,
    /** A connection step, a repair or a record command is running. */
    val busy: Boolean,
    val picture: PictureHealth,
)

/**
 * The engine's view of the tiles with a camera, in slot order, at one instant (iOS
 * `multicamGroup` / `multicamSnapshot`). Pocket qualifies strict group record.
 */
internal class MultiviewMulticam(tiles: List<MulticamTile>) {
    val group = MulticamGroup().apply {
        for (tile in tiles) {
            add(
                MonitorEntryDescriptor(
                    id = tile.id,
                    name = tile.name,
                    picture = PictureSourceDescriptor(tile.stream, label = tile.name),
                    cameraSession = tile.control.id,
                    telemetry = TelemetrySource.CAMERA_SESSION,
                    controlAuthority = ControlAuthority.Owner,
                ),
            )
        }
    }
    val state = MulticamSnapshot(
        tiles.map { it.control.current },
        tiles.associate { it.stream to it.picture },
        tiles.filter { it.busy }.map { it.id }.toSet(),
    ) // now: the shared host clock (MonotonicInstant.now(), MULTI-03 F1)
    val sessions: Map<CameraSessionID, CameraSession> = tiles.associate { it.control.id to it.control }

    fun plan(requested: List<MonitorEntryID>, stop: Boolean, policy: TargetPolicy = RECORD_POLICY): RecordPlan =
        RecordPlan.make(if (stop) RecordDirection.STOP else RecordDirection.START, policy, requested, group, state)

    /**
     * Revalidates and sends an approved plan, then waits for every camera's outcome. `null`: the
     * plan is stale and nothing was sent. A partial result is never compensated.
     */
    suspend fun submit(plan: RecordPlan): RecordResult? =
        try {
            plan.submit(group, state, sessions).finished(sessions)
        } catch (_: RecordSubmissionException) {
            null
        }

    companion object {
        val RECORD_POLICY = TargetPolicy.STRICT
    }
}

/** The tile note for one camera's record outcome. */
internal fun recordingNote(outcome: TargetOutcome, start: Boolean): String? =
    when (outcome) {
        TargetOutcome.Confirmed -> if (start) "Recording" else "Recording stopped"
        is TargetOutcome.Rejected ->
            if (outcome.rejection == CommandRejection.CameraRefused) {
                "Recording command rejected · check camera"
            } else {
                "Not sent · check camera"
            }
        is TargetOutcome.Failed -> "Not sent · check camera"
        TargetOutcome.Superseded -> null
        else -> "No confirmation · check camera"
    }

/** Record all's summary: every target confirmed and every camera in the requested state. */
internal fun groupRecordingNote(result: RecordResult, allMatch: Boolean): String {
    val start = result.plan.direction == RecordDirection.START
    val targets = result.plan.targets.size
    return if (result.confirmed == targets && allMatch) {
        if (start) "Recording on ${result.confirmed} cameras" else "Recording stopped"
    } else {
        "${result.confirmed} of $targets confirmed · check camera tiles"
    }
}
