package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.appkit.MultiviewCameraAction
import com.opencapture.opencine.appkit.MultiviewReadout
import com.opencapture.opencine.appkit.MultiviewRecordContext
import com.opencapture.opencine.appkit.MultiviewTile
import com.opencapture.opencine.appkit.MultiviewTileStatus
import com.opencapture.opencine.dji.hasMultiviewPreview
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.VideoResolution
import com.opencapture.opencine.vocabulary.timecodeClock

/** Display values come from the existing throttled tile status; no telemetry polling. */
internal data class MultiviewTileReadouts(
    val letter: String,
    val name: String,
    val model: String,
    val timecode: String,
    val battery: String,
    val batteryPercent: Int,
    val charging: Boolean,
    val storage: String,
    val recording: String,
    val isRecording: Boolean,
    val format: String,
    val recovery: String?,
)

internal fun multiviewTileReadouts(
    index: Int, name: String, model: String, settings: CameraStatus, timecode: String?,
    recordingObservation: Boolean?, recordingAvailable: Boolean, recordingBusy: Boolean,
    recovering: Boolean, hasPicture: Boolean, failure: String?, recordingNote: String? = null,
    colorFamily: String = "pocket",
): MultiviewTileReadouts {
    val total = if (settings.sdTotalMb > 0) settings.sdTotalMb else settings.storageTotalMb
    val free = if (settings.sdTotalMb > 0) settings.sdFreeMb else settings.storageFreeMb
    val elapsed = settings.recordElapsedSec.coerceAtLeast(0)
    val recording = when {
        recordingBusy -> "WAIT"
        recordingNote?.contains("rejected") == true || recordingNote?.contains("No confirmation") == true -> "REC ?"
        recovering -> "HOLD"
        !recordingAvailable || recordingObservation == null -> "REC —"
        recordingObservation -> "REC ${elapsed / 60}:${(elapsed % 60).toString().padStart(2, '0')}"
        else -> "STBY"
    }
    val resolution = VideoResolution.fromRaw(settings.resolutionCode)?.label ?: "—"
    val fps = if (settings.fps > 0) "${settings.fps}p" else "—"
    val color = if (settings.colorMode < 0) "—" else CameraCommands.colorLabel(settings.colorMode, colorFamily)
    return MultiviewTileReadouts(
        letter = ('A' + index.coerceIn(0, 3)).toString(), name = name, model = model,
        timecode = timecodeClock(timecode) ?: "—",
        battery = if (settings.batteryPercent in 0..100) "${settings.batteryPercent}%" else "—",
        batteryPercent = settings.batteryPercent,
        charging = settings.charging,
        storage = if (total > 0 && free >= 0) "${free / 1024} GB" else "—",
        recording = recording, isRecording = recordingObservation == true,
        format = "$resolution · $fps · $color",
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

/** Pocket's camera option ids beside the shared Live View id. */
internal object MultiviewTileAction {
    const val RECORD = "record"
    const val LUT = "lut"
    const val RECONNECT = "reconnect"
    const val EXPERIMENTAL = "experimental"
    const val REMOVE = "remove"
}

/** The shared stage's values for one slot, null while it is empty. */
internal fun MultiviewSession.stageTile(index: Int): MultiviewTile? {
    val tile = tiles[index]
    val camera = tile.camera ?: return null
    val readouts = multiviewTileReadouts(
        index, camera.name, camera.model.name, tile.settings, tile.timecodeReadout,
        tile.recordingObservation?.first, tile.recordingAvailable,
        tile.recordingBusy, tile.recovering, tile.hasPicture, tile.failureMessage, tile.recordingNote,
        colorFamily = camera.model.family,
    )
    val settled = !busy && !tile.connecting && !tile.recovering
    val experimental = tile.failureMessage != null && !tile.experimentalNetwork && tile.identity == null
    val record = recordPlan(tile)
    return MultiviewTile(
        name = camera.name, model = camera.model.name, format = readouts.format,
        battery = tile.settings.batteryPercent.takeIf { it in 0..100 }, charging = readouts.charging,
        storage = readouts.storage, timecode = timecodeClock(tile.timecodeReadout),
        tally = readouts.recording, recording = readouts.isRecording, lut = tile.lutEnabled,
        readouts = multiviewStageReadouts(tile.settings),
        status = readouts.recovery?.let { text ->
            MultiviewTileStatus(
                text, detail = tile.failureMessage ?: tile.status,
                inProgress = tile.failureMessage == null && !tile.networkVerified,
                actions = if (tile.failureMessage == null) emptyList() else listOfNotNull(
                    MultiviewCameraAction(MultiviewTileAction.EXPERIMENTAL, "Try experimental shared Wi-Fi", enabled = settled)
                        .takeIf { experimental },
                    MultiviewCameraAction(MultiviewTileAction.RECONNECT, "Reconnect", enabled = settled),
                    MultiviewCameraAction(
                        MultiviewTileAction.REMOVE, "Remove", MultiviewCameraAction.Kind.DESTRUCTIVE, enabled = settled,
                    ),
                ),
            )
        },
        failure = tile.failureMessage,
        footnote = "Remove this tile to enable Record all for your other cameras."
            .takeIf { tile.networkVerified && !camera.hasMultiviewPreview },
        actions = listOfNotNull(
            MultiviewCameraAction(
                MultiviewCameraAction.LIVE_VIEW, "Open Live View", enabled = tile.controlHost != null && !tile.connecting,
            ),
            MultiviewCameraAction(
                MultiviewTileAction.RECORD,
                if (tile.recordingObservation?.first == true) "Stop recording" else "Start recording",
                MultiviewCameraAction.Kind.RECORD,
                enabled = record.isExecutable && !groupRecordingBusy && !closing,
            ),
            MultiviewCameraAction(MultiviewTileAction.LUT, if (tile.lutEnabled) "Disable Auto LUT" else "Enable Auto LUT"),
            MultiviewCameraAction(MultiviewTileAction.RECONNECT, "Reconnect", enabled = settled),
            MultiviewCameraAction(MultiviewTileAction.EXPERIMENTAL, "Try experimental shared Wi-Fi", enabled = settled)
                .takeIf { experimental },
            MultiviewCameraAction(
                MultiviewTileAction.REMOVE, "Remove camera", MultiviewCameraAction.Kind.DESTRUCTIVE,
                enabled = !busy && !tile.connecting && !groupRecordingBusy && !tile.recordingBusy && !closing,
            ),
        ),
    )
}

/** The record plan for every camera (null) or one slot, with what blocks it now. */
internal fun MultiviewSession.recordContext(slot: Int?): MultiviewRecordContext = MultiviewRecordContext(
    recordPlan(slot?.let { tiles[it] }), busy = busy || groupRecordingBusy, closing = closing,
)
