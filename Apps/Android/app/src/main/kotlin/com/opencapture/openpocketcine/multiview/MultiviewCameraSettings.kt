package com.opencapture.openpocketcine.multiview

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorCaptureReveal
import com.opencapture.monitorui.MonitorDrawerTabs
import com.opencapture.monitorui.MonitorReadoutDismissBackdrop
import com.opencapture.monitorui.MonitorRect
import com.opencapture.monitorui.MultiviewSafeArea
import com.opencapture.monitorui.monitorScrollFade
import com.opencapture.openpocketcine.CaptureLists
import com.opencapture.openpocketcine.CaptureShutterPolicy
import com.opencapture.openpocketcine.LiveControlSheet
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveSheet
import com.opencapture.openpocketcine.LivePopupAction
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.pickerPanelGlass
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraStatus
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min

/** Bounded in the current viewport, including its physical cutout and navigation insets. */
internal fun multiviewSettingsBounds(width: Float, height: Float, safe: MultiviewSafeArea): MonitorRect {
    val left = max(0f, safe.leading) + 16f
    val right = max(left + 1, width - max(0f, safe.trailing) - 16f)
    val top = max(0f, safe.top) + 16f
    val bottom = max(top + 1, height - max(0f, safe.bottom) - 16f)
    val panelWidth = min(560f, right - left)
    val panelHeight = min(520f, bottom - top)
    return MonitorRect(left + (right - left - panelWidth) / 2, top + (bottom - top - panelHeight) / 2,
        panelWidth, panelHeight)
}

internal fun multiviewSettingsCategories(camera: CameraModel, status: CameraStatus): List<LiveSheet> = buildList {
    addAll(listOf(LiveSheet.ISO, LiveSheet.SHUTTER, LiveSheet.EXPO, LiveSheet.WB))
    if (CaptureLists.supportsFocusMode(camera)) add(LiveSheet.FOCUS)
    if (camera.supportsAperture) add(LiveSheet.APERTURE)
    if (!CameraCommands.isPhotoMode(status.shootingMode)) addAll(listOf(LiveSheet.FORMAT, LiveSheet.COLOR))
    add(LiveSheet.MODE)
    if (CaptureShutterPolicy.showsAudioControls(status.shootingMode)) add(LiveSheet.AUDIO)
}

internal fun multiviewSettingsLocked(sheet: LiveSheet, recording: Boolean): Boolean =
    recording && sheet in listOf(LiveSheet.FORMAT, LiveSheet.COLOR, LiveSheet.MODE)

private fun LiveSheet.settingsLabel(): String = when (this) {
    LiveSheet.EXPO -> "Exposure"
    LiveSheet.WB -> "WB"
    LiveSheet.ISO -> "ISO"
    else -> name.lowercase().replaceFirstChar { it.uppercase() }
}

/** Uses Live View's native picker, tabs, reveal and dismiss layer over the four retained feeds. */
@Composable
internal fun MultiviewCameraSettings(
    session: MultiviewSession,
    initialIndex: Int,
    width: Float,
    height: Float,
    safe: MultiviewSafeArea,
    confirmRecording: Boolean,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var confirmRecord by remember { mutableStateOf<Boolean?>(null) }
    val cameras = session.tiles.filter { it.camera != null }
    var selectedIndex by remember { mutableIntStateOf(initialIndex) }
    var selectedSheet by remember { mutableStateOf(LiveSheet.ISO) }
    val tile = cameras.firstOrNull { it.index == selectedIndex } ?: cameras.firstOrNull()
    LaunchedEffect(tile?.id) { if (tile == null) onDismiss() else selectedIndex = tile.index }
    val bounds = multiviewSettingsBounds(width, height, safe)
    val available = tile?.let(session::controlsAvailable) == true
    val cameraIdentity = tile?.camera?.id
    val endpoint = tile?.driver
    val recording = tile?.settings?.isRecording
    LaunchedEffect(tile, cameraIdentity, tile?.recordingObservation?.first, tile?.recordingAvailable, session.closing) {
        confirmRecord = null
    }
    DisposableEffect(tile, cameraIdentity, endpoint, available, recording) {
        val controls = if (tile != null && available) tile.openControls { session.controlsAvailable(tile) } else null
        onDispose {
            if (tile?.controlsModel === controls) tile?.closeControls() else controls?.close()
        }
    }
    Box(Modifier.fillMaxSize()) {
        MonitorReadoutDismissBackdrop(onDismiss = onDismiss)
        MonitorCaptureReveal(Modifier.offset(bounds.x.dp, bounds.y.dp).width(bounds.width.dp).heightIn(max = bounds.height.dp)) {
            Column(
                Modifier.fillMaxWidth().height(bounds.height.dp).pickerPanelGlass(RoundedCornerShape(16.dp)).padding(12.dp)
                    .testTag("multiview.cameraSettings"),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Camera settings", color = LiveDesign.text, style = LiveType.text(16f, FontWeight.SemiBold),
                        modifier = Modifier.weight(1f))
                    Box(Modifier.size(44.dp).chromeClickable(onClick = onDismiss)
                        .semantics { contentDescription = "Close camera settings"; role = Role.Button },
                        contentAlignment = Alignment.Center) {
                        OpcIcon(OpcIcon.X, null, Modifier.size(20.dp), LiveDesign.text)
                    }
                }
                val cameraTabScroll = rememberScrollState()
                Row(Modifier.fillMaxWidth().monitorScrollFade(cameraTabScroll, vertical = false).horizontalScroll(cameraTabScroll)) {
                    MonitorDrawerTabs(
                        tabs = cameras.map { "${'A' + it.index} · ${it.camera?.name.orEmpty()}" },
                        selected = cameras.indexOf(tile).coerceAtLeast(0),
                        onSelect = { index ->
                            if (selectedIndex != cameras[index].index) {
                                tile?.closeControls()
                                selectedIndex = cameras[index].index
                                selectedSheet = LiveSheet.ISO
                            }
                        },
                    )
                }
                val camera = tile?.camera
                val controls = tile?.controlsModel
                if (camera != null && controls != null && available) {
                    val status by controls.session.chromeStatus.collectAsState()
                    val note by controls.session.controlNote.collectAsState()
                    val categories = multiviewSettingsCategories(camera.model, status)
                    val sheet = selectedSheet.takeIf { it in categories } ?: LiveSheet.ISO
                    val categoryScroll = rememberScrollState()
                    Row(Modifier.fillMaxWidth().monitorScrollFade(categoryScroll, vertical = false).horizontalScroll(categoryScroll)) {
                        MonitorDrawerTabs(categories.map { it.settingsLabel() }, categories.indexOf(sheet),
                            onSelect = { selectedSheet = categories[it] })
                    }
                    LivePopupAction(
                        if (tile.recordingObservation?.first == true) "Stop recording" else "Start recording",
                        enabled = tile.recordingAvailable && !tile.recordingBusy && !session.groupRecordingBusy && !session.closing,
                    ) {
                        if (confirmRecording) confirmRecord = tile.recordingObservation?.first == true
                        else scope.launch { session.toggleRecording(tile) }
                    }
                    note?.let { Text(it, color = LiveDesign.amber, style = LiveType.text(11f), maxLines = 2) }
                    // Changing camera, category, recording or mode retires any in-progress native drum gesture.
                    key(controls, sheet, status.isRecording, status.shootingMode) {
                        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                            LiveControlSheet(
                                sheet, controls, status, locked = multiviewSettingsLocked(sheet, status.isRecording),
                                onDismiss = onDismiss, maxHeightDp = maxHeight.value, portrait = false, showsHeader = false,
                            )
                        }
                    }
                } else {
                    Text(if (tile?.recovering == true) "Reconnect this camera before changing settings."
                        else "Camera settings are available when its connection is ready.",
                        color = LiveDesign.muted, style = LiveType.text(13f), modifier = Modifier.padding(vertical = 16.dp))
                }
            }
        }
    }
    confirmRecord?.let { stopping ->
        val target = tile ?: return@let
        MultiviewRecordConfirmation(stopping, target.camera?.name.orEmpty(), onDismiss = { confirmRecord = null }) {
            confirmRecord = null
            if (target.recordingAvailable && target.recordingObservation?.first == stopping && !session.closing) {
                scope.launch { session.toggleRecording(target) }
            }
        }
    }

}
