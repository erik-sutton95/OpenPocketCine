package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.appkit.MultiviewCameraAction
import com.opencapture.opencine.appkit.MultiviewReadout
import com.opencapture.opencine.appkit.MultiviewRecordContext
import com.opencapture.opencine.appkit.MultiviewTally
import com.opencapture.opencine.appkit.MultiviewTile
import com.opencapture.opencine.appkit.MultiviewTileReadings
import com.opencapture.opencine.appkit.recordContext
import com.opencapture.opencine.appkit.tile
import com.opencapture.opencine.appkit.MultiviewTool
import com.opencapture.opencine.core.PowerStatus
import com.opencapture.opencine.cameracontrols.cameraBatteryReadoutLabel
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.StorageReadout
import com.opencapture.opencine.vocabulary.storageReadout
import com.opencapture.opencine.media.storageReadout
import com.opencapture.opencine.core.StorageStatus
import com.opencapture.opencine.vocabulary.VideoResolution

/** The toolbar in iOS order (Pocket iOS `MultiviewStage` tools). */
internal val multiviewTools = listOf(MultiviewTool.LAYOUT, MultiviewTool.CAMERA, MultiviewTool.FIT, MultiviewTool.LUT)

/** Display values come from the existing throttled tile status; no telemetry polling. */
internal data class MultiviewTileReadouts(
    val letter: String,
    val name: String,
    val model: String,
    val timecode: String,
    val battery: String,
    val storage: String,
    val recording: String,
    val isRecording: Boolean,
    val format: String,
    val recovery: String?,
)

internal fun multiviewTileReadouts(
    index: Int, name: String, model: String, settings: CameraStatus, timecode: String?,
    recordingObservation: Boolean?, recordingBusy: Boolean,
    recovering: Boolean, hasPicture: Boolean, failure: String?,
    power: PowerStatus,
    colorFamily: String = "pocket",
    storage: StorageStatus? = null,
): MultiviewTileReadouts {
    val elapsed = settings.recordElapsedSec.coerceAtLeast(0)
    // As iOS: the last reported observation is shown even when status is stale.
    val recording = MultiviewTally.text(
        recording = recordingObservation,
        seconds = elapsed, waiting = recordingBusy, holding = recovering, failed = failure != null,
    )
    val resolution = VideoResolution.fromRaw(settings.resolutionCode)?.label ?: "—"
    val fps = if (settings.fps > 0) "${settings.fps}p" else "—"
    val color = if (settings.colorMode < 0) "—" else CameraCommands.colorLabel(settings.colorMode, colorFamily)
    return MultiviewTileReadouts(
        letter = ('A' + index.coerceIn(0, 3)).toString(), name = name, model = model,
        timecode = timecode ?: "\u2014",
        battery = cameraBatteryReadoutLabel(power.batteryReading) ?: "\u2014",
        storage = (if (storage != null) storage.storageReadout else settings.storageReadout)?.free ?: StorageReadout.UNAVAILABLE,
        recording = recording, isRecording = recordingObservation == true,
        format = "$resolution $fps · $color",
        recovery = when {
            failure != null -> "Connection needs attention"
            recovering -> "Restoring picture…"
            !hasPicture -> "Waiting for picture…"
            else -> null
        },
    )
}

internal fun multiviewExposureReadouts(settings: CameraStatus): List<Pair<String, String>> = listOf(
    "ISO" to if (settings.iso > 0) settings.iso.toString() else "—",
    "SHUTTER" to if (settings.shutterDenom > 0) "1/${settings.shutterDenom}" else "—",
    "WB" to when {
        settings.wbMode == CameraCommands.WB_AUTO -> "Auto"
        settings.wbMode < 0 -> "—"
        settings.wbKelvin > 0 -> "${settings.wbKelvin}K"
        else -> "—"
    },
    "FOCUS" to settings.focusLabel,
)

/** The program readouts and Grid's in-tile row. */
internal fun multiviewStageReadouts(settings: CameraStatus): List<MultiviewReadout> =
    multiviewExposureReadouts(settings).map { (title, value) -> MultiviewReadout(title, value) }

/** The shared stage's values for one slot, null while it is empty: Pocket's camera readings with the stage's own. */
internal fun MultiviewSession.stageTile(index: Int): MultiviewTile? {
    val tile = tiles[index]
    val camera = tile.camera ?: return null
    val power = tile.control.current.power
    val readouts = multiviewTileReadouts(
        index, camera.name, camera.model.name, tile.settings, tile.timecodeReadout,
        tile.recordingObservation?.first, tile.recordingBusy, tile.recovering, tile.hasPicture, tile.failureMessage,
        power = power, colorFamily = camera.model.family, storage = tile.control.snapshots.value.storage,
    )
    val shared = coordinator.tile(
        index,
        MultiviewTileReadings(
            name = camera.name, model = camera.model.name, format = readouts.format, storage = readouts.storage,
            timecode = tile.timecodeReadout, readouts = multiviewStageReadouts(tile.settings),
            recordingSeconds = tile.settings.recordElapsedSec.coerceAtLeast(0), power = power,
            hasPicture = tile.hasPicture,
        ),
    ) ?: return null
    // Compose's status card offers a failure's own buttons (a per-platform look, docs/appkit).
    val failureActions = setOf(
        MultiviewCameraAction.EXPERIMENTAL, MultiviewCameraAction.RECONNECT, MultiviewCameraAction.REMOVE,
    )
    val status = shared.status?.let { status ->
        if (tile.failureMessage == null) status else status.copy(actions = shared.actions.filter { it.id in failureActions })
    }
    return shared.copy(status = status)
}

/** The record plan for every camera (null) or one slot, with what blocks it now. */
internal fun MultiviewSession.recordContext(slot: Int?): MultiviewRecordContext = coordinator.recordContext(slot)
