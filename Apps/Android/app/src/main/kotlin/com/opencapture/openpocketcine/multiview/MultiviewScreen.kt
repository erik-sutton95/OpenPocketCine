package com.opencapture.openpocketcine.multiview

import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.opencapture.monitorui.MonitorPalette
import com.opencapture.monitorui.MonitorRecordLamp
import com.opencapture.monitorui.MonitorRect
import com.opencapture.monitorui.MultiviewPresentationLayout
import com.opencapture.monitorui.MultiviewSafeArea
import com.opencapture.monitorui.monitorScrollFade
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LiveViewScreen
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.feed.LiveFeedEffectsSession
import com.opencapture.openpocketcine.liveChromeGlass
import com.opencapture.openpocketcine.monitorGlass
import com.opencapture.openpocketcine.pickerPanelGlass
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.FoundCamera
import kotlinx.coroutines.launch

private val StageCanvas = MonitorPalette.backgroundDeep
private val TileShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
private val ControlShape = RoundedCornerShape(14.dp)

/**
 * Android Multiview stage. iOS `MultiviewView`: shared layout geometry, one
 * persistent tile per camera, floating session/assist/network/DISP/record
 * controls, the network popup, the camera picker and borrowed Live View.
 */
@Composable
fun MultiviewScreen(model: AppModel, onClose: () -> Unit) {
    val context = LocalContext.current
    val session = remember { MultiviewSession(context) }
    val scope = rememberCoroutineScope()
    var adding by remember { mutableStateOf<MultiviewSession.Tile?>(null) }
    var showNetwork by remember { mutableStateOf(false) }
    var showLeave by remember { mutableStateOf(false) }
    var liveTile by remember { mutableStateOf<MultiviewSession.Tile?>(null) }
    var clean by remember { mutableStateOf(false) }
    var cameraSettings by remember { mutableStateOf(false) }
    val close = rememberUpdatedState(onClose)

    fun closeStage() {
        scope.launch { if (session.closeStage()) close.value() }
    }

    val activity = LocalActivity.current
    DisposableEffect(session) {
        session.start()
        showNetwork = !session.networkConfigured
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            if (!model.keepScreenAwake) activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            session.dispose()
        }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, session) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> session.setApplicationActive(true)
                Lifecycle.Event.ON_PAUSE -> {
                    session.setApplicationActive(false)
                    cameraSettings = false
                }
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(session.layout, session.focusedIndex) { session.persistStage() }

    val borrowed = liveTile?.liveModel
    if (liveTile != null && borrowed != null) {
        DisposableEffect(borrowed) {
            borrowed.multiviewExit = { liveTile = null }
            onDispose { session.closeLiveView() }
        }
        BackHandler { liveTile = null }
        LiveViewScreen(borrowed)
        return
    }

    BackHandler {
        when {
            session.closing -> Unit
            cameraSettings -> cameraSettings = false
            showNetwork -> {
                showNetwork = false
                if (!session.networkConfigured) closeStage()
            }
            adding != null -> {
                adding = null
            }
            session.tiles.any { it.camera != null } -> showLeave = true
            else -> closeStage()
        }
    }

    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val insets = WindowInsets.safeDrawing
    val safe = with(density) {
        MultiviewSafeArea(
            top = insets.getTop(this).toDp().value,
            leading = insets.getLeft(this, direction).toDp().value,
            bottom = insets.getBottom(this).toDp().value,
            trailing = insets.getRight(this, direction).toDp().value,
        )
    }
    val overlayOpen = showNetwork || adding != null || session.closing || cameraSettings

    BoxWithConstraints(Modifier.fillMaxSize().background(StageCanvas)) {
        val layout = MultiviewPresentationLayout.compute(
            width = maxWidth.value, height = maxHeight.value, safeArea = safe,
            arrangement = session.layout.arrangement, selected = session.focusedIndex,
        )
        Box(
            // iOS hides the stage from VoiceOver while a popup covers it.
            Modifier.fillMaxSize().then(if (overlayOpen) Modifier.clearAndSetSemantics { } else Modifier),
        ) {
            MultiviewTileCanvas(session.tiles.map { it.id }, layout) { index, compact ->
                val tile = session.tiles[index]
                TileView(
                    session = session, tile = tile, index = index, compact = compact,
                    clean = clean, enabled = !overlayOpen,
                    readoutsOverlay = layout.readoutsOverlay && index == session.focusedIndex,
                    // The View Assist palette floats over the main tile's lower left;
                    // its footer starts where the stage value row does.
                    footerStart = if (layout.readoutsOverlay && index == session.focusedIndex)
                        layout.readouts.x - layout.tiles[index].x else 0f,
                    // Grid's selected tile carries its values between the footer columns.
                    inlineValues = layout.readoutsOverlay && index == session.focusedIndex &&
                        session.layout == MultiviewLayout.GRID,
                    confirmRecording = model.recordConfirmationEnabled,
                    onAdd = { empty ->
                        if (session.networkConfigured) adding = empty else showNetwork = true
                    },
                    onOpenLive = {
                        session.openLiveView(tile)
                        if (tile.liveModel != null) liveTile = tile
                    },
                )
            }
            if (!clean) {
                SessionControls(
                    session, Modifier.rect(layout.sessionControls),
                    onExit = {
                        if (session.tiles.any { it.camera != null }) showLeave = true else closeStage()
                    },
                )
                if (session.layout == MultiviewLayout.CENTER_STAGE) {
                    StageReadouts(session.tiles.getOrNull(session.focusedIndex)?.settings, Modifier.rect(layout.readouts))
                }
                MultiviewAssistPalette(
                    session, layout.controlCellSize, Modifier.rect(layout.assists),
                    horizontal = layout.assistsHorizontal,
                    fixed = layout.portrait && session.layout == MultiviewLayout.CENTER_STAGE,
                    maxExpandedHeight = if (layout.assistsHorizontal) null else layout.assists.height,
                    onSettings = { cameraSettings = true },
                )
                NetworkButton(
                    enabled = !session.busy && !session.connectingCameras,
                    modifier = Modifier.rect(layout.network),
                    onClick = { showNetwork = true },
                )
            }
            DisplayButton(clean, Modifier.rect(layout.display)) { clean = !clean }
            RecordAllButton(session, model.recordConfirmationEnabled, layout.record.width, Modifier.rect(layout.record)) {
                scope.launch { session.toggleAllRecording() }
            }
        }
        if (cameraSettings) {
            MultiviewCameraSettings(session, session.focusedIndex, maxWidth.value, maxHeight.value, safe) {
                cameraSettings = false
            }
        }
        if (session.closing) {
            Row(
                Modifier.align(Alignment.Center).liveChromeGlass(RoundedCornerShape(16.dp)).padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                CircularProgressIndicator(Modifier.size(20.dp), color = LiveDesign.text, strokeWidth = 2.dp)
                Text("Returning cameras to their Wi-Fi…", color = LiveDesign.text, style = LiveType.text(15f))
            }
        }
        if (showNetwork) {
            MultiviewNetworkSetup(
                session = session,
                cancel = {
                    showNetwork = false
                    if (!session.networkConfigured) closeStage()
                },
                complete = { showNetwork = false },
            )
        } else {
            adding?.let { tile ->
                CameraPicker(
                    session = session,
                    onCancel = {
                        adding = null
                            },
                    onPick = { camera ->
                        adding = null
                        session.enqueueAdd(camera, tile, experimental = !camera.hasMultiviewPreview)
                    },
                )
            }
        }
    }

    session.error?.let { message ->
        AlertDialog(
            onDismissRequest = { session.error = null },
            title = { Text("Multiview") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { session.error = null }) { Text("OK") } },
            dismissButton = if (session.hasPendingCleanup) {
                { TextButton(onClick = { session.error = null; close.value() }) { Text("Close anyway") } }
            } else null,
        )
    }
    if (showLeave) {
        AlertDialog(
            onDismissRequest = { showLeave = false },
            text = { Text("Close Multiview and return cameras to their own Wi-Fi? Recording continues.") },
            confirmButton = {
                TextButton(onClick = {
                    showLeave = false
                    closeStage()
                }) { Text("Close monitoring") }
            },
            dismissButton = { TextButton(onClick = { showLeave = false }) { Text("Cancel") } },
        )
    }
}

private fun Modifier.rect(rect: MonitorRect): Modifier =
    offset(rect.x.dp, rect.y.dp).requiredSize(rect.width.dp, rect.height.dp)

@Composable
private fun SessionControls(session: MultiviewSession, modifier: Modifier, onExit: () -> Unit) {
    com.opencapture.openpocketcine.MonitorChromeButton(
        OpcIcon.CHEVRON_LEFT, "Exit Multiview", modifier,
        enabled = !session.busy && !session.groupRecordingBusy, onClick = onExit,
    )
}

@Composable
private fun StageReadouts(settings: CameraStatus?, modifier: Modifier) {
    val values = multiviewExposureReadouts(settings ?: CameraStatus())
    Box(modifier, contentAlignment = Alignment.Center) {
        Row(Modifier.widthIn(max = 300.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            values.forEach { (label, value) ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(value, color = LiveDesign.text, style = LiveType.mono(12f, FontWeight.SemiBold), maxLines = 1)
                    Text(label, color = LiveDesign.muted, style = LiveType.text(7f, FontWeight.SemiBold), maxLines = 1)
                }
            }
        }
    }
}

private enum class MultiviewTool { LAYOUT, LUT, FIT, SETTINGS }

@Composable
internal fun MultiviewAssistPalette(
    session: MultiviewSession, cell: Float, modifier: Modifier,
    horizontal: Boolean = false, fixed: Boolean = false, maxExpandedHeight: Float? = null,
    onSettings: () -> Unit,
) {
    val assigned = session.tiles.filter { it.camera != null }
    var usage by remember { mutableStateOf(com.opencapture.monitorui.MonitorToolUsageState()) }
    val haptics = com.opencapture.openpocketcine.LocalOperatorHaptics.current
    fun title(tool: MultiviewTool) = when (tool) {
        MultiviewTool.LUT -> "Toggle Auto LUT for all cameras"
        MultiviewTool.FIT -> if (session.fill) "Fit feed in frame" else "Fill frame with feed"
        MultiviewTool.LAYOUT -> if (session.layout == MultiviewLayout.GRID) "Show Focused stage" else "Show Grid"
        MultiviewTool.SETTINGS -> "Camera settings"
    }
    fun isOn(tool: MultiviewTool) = tool == MultiviewTool.LUT && assigned.any { tile -> tile.lutEnabled }
    fun isAvailable(tool: MultiviewTool) =
        tool !in listOf(MultiviewTool.LUT, MultiviewTool.SETTINGS) || assigned.isNotEmpty()
    fun identifier(tool: MultiviewTool) = when (tool) {
        MultiviewTool.LUT -> "multiview.lut"
        MultiviewTool.FIT -> "multiview.fitFill"
        MultiviewTool.LAYOUT -> "multiview.layout"
        MultiviewTool.SETTINGS -> "multiview.settings"
    }
    fun toggle(tool: MultiviewTool) {
        haptics.selection()
        when (tool) {
            MultiviewTool.LUT -> {
                val enabled = !assigned.all { it.lutEnabled }
                assigned.forEach { if (it.lutEnabled != enabled) it.toggleLUT() }
                session.persistStage()
            }
            MultiviewTool.FIT -> { session.fill = !session.fill; session.persistStage() }
            MultiviewTool.LAYOUT -> session.layout = if (session.layout == MultiviewLayout.GRID)
                MultiviewLayout.CENTER_STAGE else MultiviewLayout.GRID
            MultiviewTool.SETTINGS -> onSettings()
        }
    }
    val glyph: @Composable (MultiviewTool, Color, Modifier) -> Unit = { tool, tint, iconModifier ->
        val icon = when (tool) {
            MultiviewTool.LUT -> OpcIcon.PALETTE
            MultiviewTool.FIT -> if (session.fill) OpcIcon.MINIMIZE else OpcIcon.MAXIMIZE
            MultiviewTool.LAYOUT -> if (session.layout == MultiviewLayout.GRID) OpcIcon.LAYOUT_LIST else OpcIcon.LAYOUT_GRID
            MultiviewTool.SETTINGS -> OpcIcon.SLIDERS_HORIZONTAL
        }
        OpcIcon(icon, null, iconModifier, tint)
    }
    if (fixed) {
        // Portrait Center stage: the same tools as a plain, always-visible column spanning
        // the secondary feeds. No chevron, drag or collapse.
        Column(modifier.monitorGlass(RoundedCornerShape(14.dp)).padding(4.dp)) {
            MultiviewTool.entries.forEach { tool ->
                val available = isAvailable(tool) && !session.closing
                Box(
                    Modifier.weight(1f).fillMaxWidth().heightIn(min = 44.dp)
                        .alpha(if (isAvailable(tool)) 1f else .4f)
                        .testTag(identifier(tool))
                        .semantics {
                            contentDescription = title(tool)
                            if (tool == MultiviewTool.LUT) stateDescription = if (isOn(tool)) "On" else "Off"
                            role = Role.Button
                        }
                        .chromeClickable(enabled = available) { toggle(tool) },
                    contentAlignment = Alignment.Center,
                ) {
                    glyph(tool, if (isOn(tool)) MonitorPalette.accent else MonitorPalette.text,
                        Modifier.size((cell * 29f / 54f).dp))
                }
            }
        }
        return
    }
    // Landscape stages mount the palette as Live View does: horizontal, bottom-leading.
    Box(modifier, contentAlignment = if (horizontal) Alignment.BottomStart else Alignment.BottomCenter) {
        com.opencapture.monitorui.MonitorAssistPalette(
            tools = MultiviewTool.entries, portrait = !horizontal, locked = session.closing,
            isOn = ::isOn,
            title = ::title, label = { tool -> when (tool) {
                MultiviewTool.LUT -> "LUT"
                MultiviewTool.FIT -> if (session.fill) "FILL" else "FIT"
                MultiviewTool.LAYOUT -> if (session.layout == MultiviewLayout.GRID) "FOCUS" else "GRID"
                MultiviewTool.SETTINGS -> "CAM"
            } },
            hasOptions = { false }, onOptions = {},
            isAvailable = ::isAvailable,
            accessibilityLabel = ::title,
            accessibilityIdentifier = ::identifier,
            accessibilityValue = { if (it == MultiviewTool.LUT) {
                if (assigned.any { tile -> tile.lutEnabled }) "On" else "Off"
            } else null },
            expansionAccessibilityName = "Multiview tools", expansionAccessibilityIdentifier = "multiview.tools.expand",
            cellSize = cell, maxExpandedHeight = maxExpandedHeight,
            idOf = { it.name }, usage = usage, onUsageChange = { usage = it },
            onToggle = ::toggle,
            glyph = glyph,
            chevron = { expanded, vertical ->
                val icon = if (vertical) { if (expanded) OpcIcon.CHEVRON_DOWN else OpcIcon.CHEVRON_UP }
                    else { if (expanded) OpcIcon.CHEVRON_LEFT else OpcIcon.CHEVRON_RIGHT }
                OpcIcon(icon, null, Modifier.size(14.dp), LiveDesign.muted)
            },
        )
    }
}

@Composable
private fun NetworkButton(enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    com.opencapture.openpocketcine.AuxCircleButton(
        modifier.semantics { contentDescription = "Shared Wi-Fi" }, enabled = enabled, onClick = onClick,
    ) { tint -> OpcIcon(OpcIcon.WIFI, null, Modifier.fillMaxSize(), tint) }
}

@Composable
private fun DisplayButton(clean: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier.monitorGlass(ControlShape).chromeClickable(onClick = onClick)
            .semantics {
                contentDescription = "Change display mode"
                stateDescription = if (clean) "Clean" else "Live"
                role = Role.Button
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
    ) {
        Text(
            "DISP", color = if (clean) Color.White else LiveDesign.muted,
            style = LiveType.text(12f, FontWeight.Bold).copy(letterSpacing = 0.4.sp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Box(
                Modifier.size(14.dp, 3.dp).clip(CircleShape)
                    .background(if (clean) Color.White.copy(alpha = 0.28f) else LiveDesign.accent),
            )
            Box(
                Modifier.size(14.dp, 3.dp).clip(CircleShape)
                    .background(if (clean) LiveDesign.accent else Color.White.copy(alpha = 0.28f)),
            )
        }
    }
}

@Composable
private fun RecordAllButton(
    session: MultiviewSession, confirm: Boolean, diameter: Float, modifier: Modifier, onClick: () -> Unit,
) {
    var pending by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(session.anyRecording, session.canRecordTogether) { pending = null }
    pending?.let { stopping ->
        MultiviewRecordConfirmation(stopping, "All connected cameras", onDismiss = { pending = null }) {
            pending = null
            if (session.canRecordTogether && session.anyRecording == stopping) onClick()
        }
    }
    Box(
        modifier.alpha(if (session.canRecordTogether || session.groupRecordingBusy) 1f else 0.4f)
            .chromeClickable(enabled = session.canRecordTogether) {
                if (confirm) pending = session.anyRecording else onClick()
            }
            .semantics {
                contentDescription = if (session.anyRecording) "Stop all recording" else "Record all"
                role = Role.Button
            }, contentAlignment = Alignment.Center,
    ) {
        MonitorRecordLamp(recording = session.anyRecording, modifier = Modifier.size(diameter.dp))
        if (session.groupRecordingBusy) {
            CircularProgressIndicator(Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
        }
    }
}

@Composable
internal fun MultiviewRecordConfirmation(
    stopping: Boolean, target: String, onDismiss: () -> Unit, onConfirm: () -> Unit,
) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().chromeClickable(onClick = onDismiss), contentAlignment = Alignment.BottomCenter) {
            Column(
                Modifier.fillMaxWidth().padding(16.dp).pickerPanelGlass(ControlShape).padding(18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(if (stopping) "Stop recording?" else "Start recording?", color = LiveDesign.text,
                    style = LiveType.text(16f, FontWeight.SemiBold))
                Text(target, color = LiveDesign.muted, style = LiveType.text(13f))
                TextButton(onClick = onConfirm, modifier = Modifier.fillMaxWidth()) {
                    Text(if (stopping) "Stop" else "Start", color = if (stopping) LiveDesign.rec else LiveDesign.accent)
                }
                TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Cancel", color = LiveDesign.muted) }
            }
        }
    }
}

@Composable
private fun TileView(
    session: MultiviewSession,
    tile: MultiviewSession.Tile,
    index: Int,
    compact: Boolean,
    clean: Boolean,
    enabled: Boolean,
    readoutsOverlay: Boolean,
    footerStart: Float,
    inlineValues: Boolean = false,
    confirmRecording: Boolean,
    onAdd: (MultiviewSession.Tile) -> Unit,
    onOpenLive: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val camera = tile.camera
    val focused = index == session.focusedIndex && camera != null
    var optionsOpen by remember { mutableStateOf(false) }
    var confirmRecord by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(clean, enabled, camera) { if (clean || !enabled || camera == null) optionsOpen = false }
    LaunchedEffect(camera, tile.recordingObservation?.first, tile.recordingAvailable, session.closing) { confirmRecord = null }
    Box(Modifier.fillMaxSize().background(LiveDesign.surface, TileShape)) {
        if (camera != null) {
            val readouts = multiviewTileReadouts(
                index, camera.name, camera.model.name, tile.settings, tile.timecodeReadout,
                tile.recordingObservation?.first, tile.recordingAvailable,
                tile.recordingBusy, tile.recovering, tile.hasPicture, tile.failureMessage, tile.recordingNote,
                colorFamily = camera.model.family,
            )
            if (tile.liveModel == null) TileFeed(session, tile, session.fill)
            // A tile retains the same feed owner through layout, selection and rotation.
            Box(
                Modifier.fillMaxSize().pointerInput(tile, enabled) {
                    if (!enabled) return@pointerInput
                    detectTapGestures(
                        onDoubleTap = { if (tile.controlHost != null) onOpenLive() },
                        onTap = { session.focusedIndex = index },
                    )
                }.semantics {
                    contentDescription = "Select camera ${'A' + index}, ${camera.name}"
                    stateDescription = if (focused) "Selected" else "Not selected"
                    role = Role.Button
                    if (enabled) onClick { session.focusedIndex = index; true }
                },
            )
            MultiviewTileOverlay(
                readouts = readouts,
                focused = focused, compact = compact, clean = clean, enabled = enabled,
                readoutsOverlay = readoutsOverlay, footerStart = footerStart, inlineValues = inlineValues, settings = tile.settings, onOptions = { session.focusedIndex = index; optionsOpen = true },
            )
            Box(Modifier.align(Alignment.TopEnd).padding(6.dp)) {
                DropdownMenu(expanded = optionsOpen, onDismissRequest = { optionsOpen = false },
                    modifier = Modifier.widthIn(min = 220.dp, max = 320.dp).heightIn(max = 520.dp).pickerPanelGlass(ControlShape),
                    containerColor = Color.Transparent, shadowElevation = 0.dp) {
                    tile.failureMessage?.let { message ->
                        Text(message, modifier = Modifier.widthIn(max = 280.dp).padding(12.dp), style = LiveType.text(12f))
                    }
                    MultiviewCameraMenu(
                        cameraName = camera.name, readouts = readouts,
                        experimentalRetryEnabled = if (tile.failureMessage != null && !tile.experimentalNetwork && tile.identity == null) {
                            !session.busy && !tile.connecting && !tile.recovering
                        } else null,
                        recording = tile.recordingObservation?.first == true,
                        lutEnabled = tile.lutEnabled,
                        canOpen = tile.controlHost != null && !tile.connecting,
                        canRecord = tile.recordingAvailable && !tile.recordingBusy && !session.groupRecordingBusy && !session.closing,
                        canReconnect = !session.busy && !tile.connecting && !tile.recovering,
                        canRemove = !session.busy && !tile.connecting && !session.groupRecordingBusy && !tile.recordingBusy && !session.closing,
                        onAction = { action ->
                            optionsOpen = false
                            when (action) {
                                MultiviewCameraAction.LIVE_VIEW -> onOpenLive()
                                MultiviewCameraAction.RECORD -> {
                                    if (confirmRecording) confirmRecord = tile.recordingObservation?.first == true
                                    else scope.launch { session.toggleRecording(tile) }
                                }
                                MultiviewCameraAction.LUT -> { tile.toggleLUT(); session.persistStage() }
                                MultiviewCameraAction.RECONNECT -> scope.launch { session.reconnect(tile) }
                                MultiviewCameraAction.EXPERIMENTAL -> scope.launch { session.tryExperimentalNetwork(tile) }
                                MultiviewCameraAction.REMOVE -> session.remove(tile)
                            }
                        },
                    )
                }
            }
            if ((!tile.hasPicture || tile.failureMessage != null || tile.recovering) && !compact && !clean) {
                TileStatusCard(session, tile, Modifier.align(Alignment.Center))
            }
        } else {
            // Center stage offers "Add camera" on the big tile while it is empty.
            val focused = session.tiles.getOrNull(session.focusedIndex)
            val addTarget = focused?.takeIf { session.layout == MultiviewLayout.CENTER_STAGE && it.camera == null }
                ?: session.tiles.firstOrNull { it.camera == null }
            if (addTarget === tile && !clean) {
                Column(
                    Modifier.fillMaxSize()
                        .chromeClickable(enabled = enabled && !session.busy && !session.groupRecordingBusy) { onAdd(tile) }
                        .semantics { contentDescription = "Add camera"; role = Role.Button },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterVertically),
                ) {
                    OpcIcon(OpcIcon.CIRCLE_PLUS, null, Modifier.size(if (compact) 24.dp else 34.dp), LiveDesign.muted)
                    Text("Add camera", color = LiveDesign.muted, style = LiveType.text(if (compact) 10f else 14f, FontWeight.SemiBold))
                }
            } else if (!clean) {
                Text("${'A' + index}", color = LiveDesign.muted.copy(alpha = 0.35f),
                    style = LiveType.text(16f), modifier = Modifier.align(Alignment.Center))
            }
        }
        Box(Modifier.fillMaxSize().border(
            if (tile.recordingObservation?.first == true) 3.dp else if (focused && !clean) 2.dp else 1.dp,
            when {
                tile.recordingObservation?.first == true -> LiveDesign.rec
                focused && !clean -> LiveDesign.accent
                else -> Color.White.copy(alpha = 0.1f)
            }, TileShape,
        ))
    }
    confirmRecord?.let { stopping ->
        MultiviewRecordConfirmation(stopping, camera?.name.orEmpty(), onDismiss = { confirmRecord = null }) {
            confirmRecord = null
            if (tile.recordingAvailable && tile.recordingObservation?.first == stopping && !session.closing) {
                scope.launch { session.toggleRecording(tile) }
            }
        }
    }
}

@Composable
private fun TileStatusCard(session: MultiviewSession, tile: MultiviewSession.Tile, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    val disabled = session.busy || tile.connecting || tile.recovering
    Column(
        modifier.padding(16.dp).liveChromeGlass(RoundedCornerShape(16.dp)).padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (tile.failureMessage == null && !tile.networkVerified) {
            CircularProgressIndicator(Modifier.size(22.dp), color = LiveDesign.text, strokeWidth = 2.dp)
        }
        Text(
            tile.failureMessage ?: tile.status, color = LiveDesign.text, textAlign = TextAlign.Center,
            style = LiveType.text(13f),
        )
        if (tile.networkVerified && tile.camera?.hasMultiviewPreview == false) {
            Text(
                "Remove this tile to enable Record all for your other cameras.",
                color = LiveDesign.text, textAlign = TextAlign.Center, style = LiveType.text(12f),
            )
        }
        if (tile.failureMessage != null) {
            if (!tile.experimentalNetwork && tile.identity == null) {
                PillButton("Try experimental shared Wi-Fi", enabled = !disabled) {
                    scope.launch { session.tryExperimentalNetwork(tile) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PillButton("Reconnect", enabled = !disabled) { scope.launch { session.reconnect(tile) } }
                PillButton("Remove", enabled = !disabled, destructive = true) { session.remove(tile) }
            }
        }
    }
}

@Composable
private fun PillButton(
    title: String,
    enabled: Boolean = true,
    destructive: Boolean = false,
    prominent: Boolean = false,
    onClick: () -> Unit,
) {
    Box(
        Modifier.heightIn(min = 44.dp).alpha(if (enabled) 1f else 0.4f)
            .clip(RoundedCornerShape(10.dp))
            .background(if (prominent) LiveDesign.accent else LiveDesign.glassBright)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { role = Role.Button }
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            color = when {
                prominent -> Color.Black
                destructive -> LiveDesign.rec
                else -> LiveDesign.accent
            },
            style = LiveType.text(15f, FontWeight.SemiBold),
        )
    }
}

/** HEVC/AVC → OES → optional Auto LUT → TextureView. Fit/Fill sizes the view, never the decoder. */
@Composable
private fun TileFeed(session: MultiviewSession, tile: MultiviewSession.Tile, fill: Boolean) {
    val context = LocalContext.current
    var gpuFailed by remember { mutableStateOf(false) }
    val handed = remember { arrayOfNulls<Surface>(1) }
    val feed = remember(tile) {
        LiveFeedEffectsSession(
            context = context,
            onDecoderSurface = { surface ->
                handed[0] = surface
                session.attachTileSurface(tile, surface)
            },
            onGpuFailed = { gpuFailed = true },
            onFramePresented = { tile.decoder.notePresented(it) },
        )
    }
    val previewOwner = tile.previewOwner
    LaunchedEffect(feed, tile.plan, previewOwner) {
        feed.updatePlan(if (previewOwner == null) tile.plan else tile.plan.withPreviewOwner(previewOwner))
    }
    // Camera settings' preview borrows this feed's GL present tap, like Live View's inspector.
    LaunchedEffect(feed, previewOwner != null) {
        feed.configurePreviewSource(tile, ready = true, active = previewOwner != null)
    }
    DisposableEffect(feed) {
        feed.setSourceSize(tile.decoder.pictureWidth, tile.decoder.pictureHeight)
        // The decoder drops its output when the coded raster changes; the GL window keeps
        // its OES surface, so hand the same one back after resizing the grade targets.
        tile.decoder.onOutputSizeChanged = { w, h ->
            feed.setSourceSize(w, h)
            handed[0]?.let { session.attachTileSurface(tile, it) }
        }
        onDispose {
            tile.decoder.onOutputSizeChanged = null
            handed[0]?.let { session.detachTileSurface(tile, it) }
            handed[0] = null
            feed.detachDisplay()
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().clipToBounds(), contentAlignment = Alignment.Center) {
        // Reading `hasPicture` recomposes once the coded raster is known.
        val ratio = tile.hasPicture.let { tile.decoder.pictureAspect.toFloat() }
        val width: Dp = if (fill) maxOf(maxWidth, maxHeight * ratio) else maxWidth
        val height: Dp = if (fill) maxOf(maxHeight, maxWidth / ratio) else maxHeight
        key(gpuFailed) {
            AndroidView(
                factory = { viewContext ->
                    TextureView(viewContext).apply {
                        isOpaque = true
                        surfaceTextureListener = TileTextureListener(
                            gles = !gpuFailed, feed = feed,
                            onPlainSurface = { surface ->
                                handed[0] = surface
                                session.attachTileSurface(tile, surface)
                            },
                            onDestroyed = {
                                handed[0]?.let { session.detachTileSurface(tile, it) }
                                handed[0] = null
                            },
                            onUpdated = { texture -> if (gpuFailed) tile.decoder.notePresented(texture.timestamp) },
                        )
                    }
                },
                modifier = Modifier.requiredSize(width, height)
                    .graphicsLayer { scaleX = if (tile.poseViewFlip) -1f else 1f },
            )
        }
    }
}

/** The decoder output is dropped before the GL window, so MediaCodec never writes a dead Surface. */
private class TileTextureListener(
    private val gles: Boolean,
    private val feed: LiveFeedEffectsSession,
    private val onPlainSurface: (Surface) -> Unit,
    private val onDestroyed: () -> Unit,
    private val onUpdated: (SurfaceTexture) -> Unit,
) : TextureView.SurfaceTextureListener {
    private var plain: Surface? = null

    override fun onSurfaceTextureAvailable(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        if (gles) {
            feed.attachDisplay(surfaceTexture, width, height)
        } else {
            val next = Surface(surfaceTexture)
            plain?.release()
            plain = next
            onPlainSurface(next)
        }
    }

    override fun onSurfaceTextureSizeChanged(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        if (gles) feed.resize(width, height)
    }

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        onDestroyed()
        if (gles) feed.detachDisplay()
        plain?.release()
        plain = null
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) = onUpdated(surfaceTexture)
}

// --- Network setup ---------------------------------------------------------------------------------

@Composable
private fun MultiviewNetworkSetup(session: MultiviewSession, cancel: () -> Unit, complete: () -> Unit) {
    val saved = remember { session.savedNetworks() }
    com.opencapture.openpocketcine.pairing.StationNetworkSetup(
        savedNetworks = saved,
        currentSsid = session.path::currentSsid,
        hotspotActive = { session.path.address(true) != null },
        scan = session::scanNetworks,
        connect = { network ->
            session.selectNetworkSource(network.hotspot)
            session.selectNetwork(network.ssid)
            session.password = network.password
            if (session.configureNetwork()) null else session.networkSetupError ?: "Could not connect. Try again."
        }, cancel = cancel, complete = complete,
        lockedNetwork = if (session.tiles.any { it.camera != null }) {
            MultiviewNetworkStore.Network(session.ssid, "", session.usePhoneHotspot)
        } else null,
        warning = session.networkSetupError,
    )
}

@Composable
private fun TextAction(title: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier.heightIn(min = 44.dp).widthIn(min = 64.dp).alpha(if (enabled) 1f else 0.4f)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { role = Role.Button },
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(title, color = LiveDesign.accent, style = LiveType.text(16f))
    }
}

@Composable
private fun Footnote(text: String, color: Color = LiveDesign.muted) {
    Text(text, color = color, style = LiveType.text(13f))
}

/** A bounded centered card: at most 460 dp wide, including landscape. */
@Composable
private fun ModalCard(
    maxHeight: Float,
    tag: String,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    BoxWithConstraints(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))
            .pointerInput(Unit) { detectTapGestures { } },
        contentAlignment = Alignment.Center,
    ) {
        val width = minOf(460.dp, (maxWidth - 32.dp).coerceAtLeast(0.dp))
        val height = minOf(maxHeight.dp, (this.maxHeight - 24.dp).coerceAtLeast(0.dp))
        Column(
            Modifier.widthIn(max = width).fillMaxWidth().heightIn(max = height)
                .shadow(24.dp, TileShape)
                .liveChromeGlass(TileShape)
                .testTag(tag),
            content = content,
        )
    }
}

// --- Camera picker -------------------------------------------------------------------------------------

@Composable
private fun CameraPicker(session: MultiviewSession, onCancel: () -> Unit, onPick: (FoundCamera) -> Unit) {
    val available = session.found.filter { camera ->
        camera.appearsInMultiview && session.tiles.none { it.camera?.id == camera.id }
    }
    val cardHeight = (maxOf(1, minOf(4, available.size)) * 60 + 140).toFloat()
    ModalCard(maxHeight = cardHeight, tag = "multiview.cameraPicker") {
        Row(
            Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Add camera", color = LiveDesign.text, style = LiveType.display(20f), modifier = Modifier.weight(1f))
            TextAction("Cancel", onClick = onCancel)
        }
        val pickerScroll = rememberScrollState()
        Column(
            Modifier.weight(1f, fill = false).monitorScrollFade(pickerScroll).verticalScroll(pickerScroll)
                .padding(start = 20.dp, end = 20.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            for (camera in available) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(TileShape).background(LiveDesign.glassBright)
                        .chromeClickable { onPick(camera) }
                        .semantics { role = Role.Button }
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f).padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(camera.name, color = LiveDesign.text, maxLines = 2, style = LiveType.text(16f))
                        if (!camera.hasMultiviewPreview) {
                            Text(
                                "Try experimental shared Wi-Fi · Preview unavailable",
                                color = LiveDesign.muted, style = LiveType.text(12f),
                            )
                        }
                    }
                    OpcIcon(
                        if (camera.hasMultiviewPreview) OpcIcon.PLUS else OpcIcon.INFO, null,
                        Modifier.size(20.dp), LiveDesign.text,
                    )
                }
            }
            if (available.isEmpty()) {
                Row(
                    Modifier.heightIn(min = 52.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    CircularProgressIndicator(Modifier.size(20.dp), color = LiveDesign.text, strokeWidth = 2.dp)
                    Text("Looking for nearby cameras…", color = LiveDesign.text, style = LiveType.text(16f))
                }
            }
            Text(
                "Each camera will join ${session.ssid}. Approve on the camera if asked.",
                color = LiveDesign.muted, style = LiveType.text(13f), modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}
