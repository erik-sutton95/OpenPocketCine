package com.opencapture.openpocketcine.multiview

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LivePopupAction
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.VideoResolution
import com.opencapture.openpocketcine.session.timecodeClock
import com.opencapture.openpocketcine.monitor.MonitorCameraBatteryGauge

/** Display values come from the existing throttled tile status; no telemetry polling. */
internal data class MultiviewTileReadouts(
    val letter: String,
    val name: String,
    val model: String,
    val timecode: String,
    val battery: String,
    val batteryPercent: Int,
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

/** Metadata stays inside every feed, including narrow thumbnails and portrait rows. */
@Composable
internal fun MultiviewTileChrome(
    readouts: MultiviewTileReadouts,
    focused: Boolean,
    compact: Boolean,
    enabled: Boolean,
    onOptions: () -> Unit,
    footerInset: Float = 0f,
    footerStart: Float = 0f,
    /** Grid's selected tile shows its camera values between the footer's left and right. */
    values: List<Pair<String, String>>? = null,
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val narrow = maxWidth < 200.dp
        val short = maxHeight < 80.dp
        val small = if (narrow) 7f else if (compact) 8f else 10f
        val edge = if (narrow) 4.dp else 6.dp
        Row(
            Modifier.fillMaxWidth().align(Alignment.TopCenter)
                .padding(start = edge, top = edge, end = if (narrow) 28.dp else 50.dp, bottom = edge),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(if (narrow) 3.dp else 5.dp),
        ) {
            Box(
                Modifier.size(if (narrow) 14.dp else if (compact) 18.dp else 24.dp)
                    .background(if (focused) LiveDesign.accent else Color.Black.copy(alpha = 0.45f), RoundedCornerShape(4.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text(readouts.letter, color = if (focused) Color.Black else Color.White,
                    style = LiveType.text(if (compact) 9f else 13f, FontWeight.Bold))
            }
            Column(Modifier.weight(1f)) {
                Text(readouts.name, color = Color.White, style = LiveType.text(if (narrow) 9f else if (compact) 10f else 13f, FontWeight.SemiBold),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (!short) {
                    Text(readouts.model, color = Color.White.copy(alpha = 0.7f), style = LiveType.text(small),
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("TC ${readouts.timecode}", color = Color.White, style = LiveType.mono(small),
                        maxLines = 1, modifier = Modifier.semantics { contentDescription = "Timecode ${readouts.timecode}" })
                }
            }
        }
        // Its full 44dp hit target does not force a tall header on landscape thumbnails.
        Box(
            Modifier.align(Alignment.TopEnd).size(44.dp).chromeClickable(enabled = enabled, onClick = onOptions)
                .semantics { contentDescription = "Camera ${readouts.letter} options"; role = Role.Button },
            contentAlignment = Alignment.TopEnd,
        ) {
            OpcIcon(OpcIcon.ELLIPSIS, null, Modifier.padding(top = edge, end = edge).size(20.dp), Color.White)
        }
        Column(
            Modifier.fillMaxWidth().align(Alignment.BottomCenter).padding(start = footerStart.dp, bottom = footerInset.dp)
                .padding(edge),
        ) {
            if (!compact) {
                Text(readouts.format, color = Color.White.copy(alpha = 0.75f), style = LiveType.text(small), maxLines = 1)
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                MonitorCameraBatteryGauge(readouts.batteryPercent, showsIcon = false)
                Text(readouts.storage, color = Color.White, style = LiveType.mono(small), maxLines = 1,
                    modifier = (if (values == null) Modifier.weight(1f) else Modifier)
                        .semantics { contentDescription = "Storage ${readouts.storage}" })
                if (values != null) {
                    // Inline with both sides; the values take what is left over.
                    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.Bottom) {
                        values.forEach { (label, value) ->
                            Column(Modifier.weight(1f, fill = false).widthIn(max = 55.dp),
                                horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(value, color = LiveDesign.text, style = LiveType.mono(10f, FontWeight.SemiBold), maxLines = 1)
                                Text(label, color = LiveDesign.muted, style = LiveType.text(6f, FontWeight.SemiBold), maxLines = 1)
                            }
                        }
                    }
                }
                Text(readouts.recording, color = if (readouts.isRecording) LiveDesign.rec else Color.White,
                    style = LiveType.mono(small, FontWeight.SemiBold), maxLines = 1)
            }
        }
    }
}

/** Recovery is safety status, so Clean display keeps it and its camera actions available. */
@Composable
internal fun MultiviewTileOverlay(
    readouts: MultiviewTileReadouts, focused: Boolean, compact: Boolean, clean: Boolean,
    enabled: Boolean, onOptions: () -> Unit, readoutsOverlay: Boolean = false, footerStart: Float = 0f,
    inlineValues: Boolean = false, settings: CameraStatus? = null,
) {
    Box(Modifier.fillMaxSize()) {
        if (!clean && readoutsOverlay) {
        }
        if (!clean) MultiviewTileChrome(readouts, focused, compact, enabled, onOptions,
            footerInset = 0f, footerStart = footerStart,  // inline with the camera values row
            values = if (inlineValues && settings != null) multiviewExposureReadouts(settings) else null)
        if (readouts.recovery != null && (compact || clean)) {
            Box(
                Modifier.align(Alignment.Center).heightIn(min = 44.dp)
                    .background(Color.Black.copy(alpha = 0.8f), RoundedCornerShape(8.dp))
                    .chromeClickable(enabled = enabled, onClick = onOptions)
                    .semantics { contentDescription = "${readouts.recovery} Camera ${readouts.letter} options"; role = Role.Button }
                    .padding(horizontal = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(readouts.recovery, color = Color.White, style = LiveType.text(if (compact) 8f else 12f, FontWeight.SemiBold),
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

internal enum class MultiviewCameraAction { LIVE_VIEW, RECORD, LUT, RECONNECT, EXPERIMENTAL, REMOVE }

/** The same actions are reachable on full-size feeds and compact secondary feeds. */
@Composable
internal fun MultiviewCameraMenu(
    cameraName: String, recording: Boolean, lutEnabled: Boolean,
    canOpen: Boolean, canRecord: Boolean, canReconnect: Boolean, canRemove: Boolean,
    readouts: MultiviewTileReadouts? = null,
    experimentalRetryEnabled: Boolean? = null,
    onAction: (MultiviewCameraAction) -> Unit,
) {
    readouts?.let { values ->
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            Text(values.name, style = LiveType.text(14f, FontWeight.SemiBold))
            Text(values.model, style = LiveType.text(12f))
            Text("TC ${values.timecode}", style = LiveType.mono(12f))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                MonitorCameraBatteryGauge(values.batteryPercent)
                Text(values.storage, style = LiveType.text(12f))
            }
            Text("${values.format} · ${values.recording}", style = LiveType.text(12f))
        }
    }
    LivePopupAction("Open Live View", enabled = canOpen) { onAction(MultiviewCameraAction.LIVE_VIEW) }
    LivePopupAction(if (recording) "Stop recording" else "Start recording", enabled = canRecord) {
        onAction(MultiviewCameraAction.RECORD)
    }
    LivePopupAction(if (lutEnabled) "Disable Auto LUT" else "Enable Auto LUT") { onAction(MultiviewCameraAction.LUT) }
    LivePopupAction("Reconnect", enabled = canReconnect) { onAction(MultiviewCameraAction.RECONNECT) }
    experimentalRetryEnabled?.let { enabled ->
        LivePopupAction("Try experimental shared Wi-Fi", enabled = enabled) { onAction(MultiviewCameraAction.EXPERIMENTAL) }
    }
    LivePopupAction("Remove camera", enabled = canRemove, destructive = true) { onAction(MultiviewCameraAction.REMOVE) }
}
