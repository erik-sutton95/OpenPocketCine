package com.opencapture.openpocketcine.multiview

import android.graphics.Bitmap
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.min
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.opencapture.monitorui.MonitorDrawerTabs
import com.opencapture.monitorui.MonitorImagePreview
import com.opencapture.monitorui.MonitorInspector
import com.opencapture.monitorui.MultiviewSafeArea
import com.opencapture.monitorui.monitorScrollFade
import com.opencapture.openpocketcine.CaptureLists
import com.opencapture.openpocketcine.CaptureShutterPolicy
import com.opencapture.openpocketcine.LiveControlSheet
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveSheet
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.feed.InspectorPreviewPipeline
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraStatus

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

/** Live View's gimbal side panel with camera tabs on top, category rail on the right and native pickers. */
@Composable
internal fun MultiviewCameraSettings(
    session: MultiviewSession,
    initialIndex: Int,
    width: Float,
    height: Float,
    safe: MultiviewSafeArea,
    onDismiss: () -> Unit,
) {
    val cameras = session.tiles.filter { it.camera != null }
    var selectedIndex by remember { mutableIntStateOf(initialIndex) }
    var selectedSheet by remember { mutableStateOf(LiveSheet.ISO) }
    val tile = cameras.firstOrNull { it.index == selectedIndex } ?: cameras.firstOrNull()
    LaunchedEffect(tile?.id) { if (tile == null) onDismiss() else selectedIndex = tile.index }
    val available = tile?.let(session::controlsAvailable) == true
    val cameraIdentity = tile?.camera?.id
    val endpoint = tile?.driver
    val recording = tile?.settings?.isRecording
    DisposableEffect(tile, cameraIdentity, endpoint, available, recording) {
        val controls = if (tile != null && available) tile.openControls { session.controlsAvailable(tile) } else null
        onDispose {
            if (tile?.controlsModel === controls) tile?.closeControls() else controls?.close()
        }
    }
    val camera = tile?.camera
    val controls = tile?.controlsModel
    val ready = camera != null && controls != null && available
    // Live View's gimbal side panel container: trailing edge, width, glass, reveal and tap-outside dismissal.
    MonitorInspector(
        title = "Camera settings",
        viewportWidth = width,
        viewportHeight = height,
        onDismiss = onDismiss,
        modifier = Modifier.testTag("multiview.cameraSettings"),
        trailing = true,
        hasNavigation = false,
        safeLeading = safe.leading,
        safeTrailing = safe.trailing,
        safeTop = safe.top,
        safeBottom = safe.bottom,
        close = {
            // Inset from the panel corner; the 48dp target overflows the one-line header.
            Box(Modifier.padding(end = 8.dp).height(20.dp).wrapContentHeight(unbounded = true)) {
                Box(Modifier.size(48.dp).chromeClickable(onClick = onDismiss)
                    .semantics { contentDescription = "Close camera settings"; role = Role.Button },
                    contentAlignment = Alignment.Center) {
                    OpcIcon(OpcIcon.X, null, Modifier.size(13.dp), LiveDesign.muted)
                }
            }
        },
        // Recording stays on Record all and each tile's options; camera tabs sit under the header.
        compactHeader = true,
    ) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
            if (ready && camera != null && controls != null) {
                val status by controls.session.chromeStatus.collectAsState()
                val categories = multiviewSettingsCategories(camera.model, status)
                val sheet = selectedSheet.takeIf { it in categories } ?: LiveSheet.ISO
                Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    BoxWithConstraints(Modifier.weight(1f).fillMaxHeight()) {
                        val viewport = maxHeight
                        val density = LocalDensity.current
                        // Tallest controls seen this session, so the preview never makes a category scroll.
                        var controlsReserve by remember { mutableStateOf(200.dp) }
                        val previewHeight = max(72.dp, min(maxWidth * 9f / 16f, maxHeight - controlsReserve - 8.dp))
                        val controlsScroll = rememberScrollState()
                        // Like the assist inspector: the live preview leads the scrolled controls.
                        Column(Modifier.fillMaxSize().monitorScrollFade(controlsScroll).verticalScroll(controlsScroll),
                            verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            // 16:9 from the measured column: full width when the tallest controls still fit.
                            key(tile) {
                                MultiviewSettingsPreview(tile, Modifier.align(Alignment.CenterHorizontally)
                                    .width(previewHeight * 16f / 9f).height(previewHeight))
                            }
                            Column(Modifier.onSizeChanged {
                                controlsReserve = max(controlsReserve, with(density) { it.height.toDp() })
                            }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                // Changing camera, category, recording or mode retires any in-progress native drum gesture.
                                key(controls, sheet, status.isRecording, status.shootingMode) {
                                    LiveControlSheet(
                                        sheet, controls, status, locked = multiviewSettingsLocked(sheet, status.isRecording),
                                        onDismiss = onDismiss, maxHeightDp = viewport.value, portrait = false, showsHeader = false,
                                    )
                                }
                                // Compact error line; it takes space only while present.
                                val note by controls.session.controlNote.collectAsState()
                                note?.let { Text(it, color = LiveDesign.amber, style = LiveType.text(11f), maxLines = 2) }
                            }
                        }
                    }
                    BoxWithConstraints(Modifier.fillMaxHeight()) {
                        val railHeight = maxHeight
                        val categoryScroll = rememberScrollState()
                        Box(Modifier.monitorScrollFade(categoryScroll).verticalScroll(categoryScroll)) {
                            // The rail's single baseline spans the full content height; tabs stay top-aligned.
                            MonitorDrawerTabs(categories.map { it.settingsLabel() }, categories.indexOf(sheet),
                                onSelect = { selectedSheet = categories[it] }, vertical = true,
                                modifier = Modifier.heightIn(min = railHeight))
                        }
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

/** Live View's inspector image preview, fed by the selected tile's existing present tap. */
@Composable
private fun MultiviewSettingsPreview(tile: MultiviewSession.Tile, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val owner = remember(tile) { Any() }
    var image by remember(owner) { mutableStateOf<Bitmap?>(null) }
    val plan by rememberUpdatedState(tile.plan)
    DisposableEffect(owner, lifecycle) {
        var active = false
        fun update() {
            val resumed = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            if (resumed && !active) {
                InspectorPreviewPipeline.open(owner, false, context, plan) { image = it }
                tile.previewOwner = owner
                active = true
            } else if (!resumed && active) {
                if (tile.previewOwner === owner) tile.previewOwner = null
                InspectorPreviewPipeline.close(owner)
                image = null
                active = false
            }
        }
        val observer = LifecycleEventObserver { _, _ -> update() }
        lifecycle.addObserver(observer)
        update()
        onDispose {
            lifecycle.removeObserver(observer)
            if (tile.previewOwner === owner) tile.previewOwner = null
            InspectorPreviewPipeline.close(owner)
        }
    }
    SideEffect { InspectorPreviewPipeline.update(owner, tile.plan) }
    MonitorImagePreview(image?.asImageBitmap(), "${tile.camera?.name ?: "Camera"} preview", modifier)
}
