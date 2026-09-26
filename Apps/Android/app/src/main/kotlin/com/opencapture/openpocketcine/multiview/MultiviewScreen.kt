package com.opencapture.openpocketcine.multiview

import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.opencapture.monitorui.MonitorPalette
import com.opencapture.monitorui.MonitorRecordLamp
import com.opencapture.monitorui.MonitorRect
import com.opencapture.monitorui.MultiviewPresentationLayout
import com.opencapture.monitorui.MultiviewSafeArea
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LiveViewScreen
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan
import com.opencapture.openpocketcine.feed.LiveFeedEffectsSession
import com.opencapture.openpocketcine.glass
import com.opencapture.openpocketcine.liveChromeGlass
import com.opencapture.openpocketcine.monitorGlass
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.FoundCamera
import com.opencapture.openpocketcine.session.VideoResolution
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
                Lifecycle.Event.ON_PAUSE -> session.setApplicationActive(false)
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
    val overlayOpen = showNetwork || adding != null || session.closing

    BoxWithConstraints(Modifier.fillMaxSize().background(StageCanvas)) {
        val layout = MultiviewPresentationLayout.compute(
            width = maxWidth.value, height = maxHeight.value, safeArea = safe,
            arrangement = session.layout.arrangement, selected = session.focusedIndex,
        )
        Box(
            // iOS hides the stage from VoiceOver while a popup covers it.
            Modifier.fillMaxSize().then(if (overlayOpen) Modifier.clearAndSetSemantics { } else Modifier),
        ) {
            session.tiles.forEachIndexed { index, tile ->
                val frame = layout.tiles[index]
                key(tile.id) {
                    Box(Modifier.rect(frame).clip(TileShape)) {
                        TileView(
                            session = session, tile = tile, index = index,
                            compact = frame.width < 200f || frame.height < 136f,
                            clean = clean, enabled = !overlayOpen,
                            onAdd = { empty ->
                                if (session.networkConfigured) adding = empty else showNetwork = true
                            },
                            onOpenLive = {
                                session.openLiveView(tile)
                                if (tile.liveModel != null) liveTile = tile
                            },
                        )
                    }
                }
            }
            if (!clean) {
                SessionControls(
                    session, layout.sessionControlsHorizontal, layout.controlCellSize,
                    Modifier.rect(layout.sessionControls),
                    onExit = {
                        if (session.tiles.any { it.camera != null }) showLeave = true else closeStage()
                    },
                )
                StageAssistPalette(
                    session, layout.assistsHorizontal, layout.controlCellSize, Modifier.rect(layout.assists),
                )
                NetworkButton(
                    enabled = !session.busy && !session.connectingCameras,
                    modifier = Modifier.rect(layout.network),
                    onClick = { showNetwork = true },
                )
            }
            DisplayButton(clean, Modifier.rect(layout.display)) { clean = !clean }
            RecordAllButton(session, Modifier.rect(layout.record)) { scope.launch { session.toggleAllRecording() } }
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
private fun SessionControls(
    session: MultiviewSession,
    horizontal: Boolean,
    cell: Float,
    modifier: Modifier,
    onExit: () -> Unit,
) {
    ControlGroup(horizontal, modifier) {
        GlyphCell(
            OpcIcon.X, cell, "Close Multiview",
            enabled = !session.busy && !session.groupRecordingBusy, onClick = onExit,
        )
        GlyphCell(
            if (session.layout == MultiviewLayout.GRID) OpcIcon.LAYOUT_LIST else OpcIcon.LAYOUT_GRID,
            cell,
            if (session.layout == MultiviewLayout.GRID) "Show Center stage" else "Show 2 by 2 grid",
        ) {
            session.layout = if (session.layout == MultiviewLayout.GRID) {
                MultiviewLayout.CENTER_STAGE
            } else {
                MultiviewLayout.GRID
            }
        }
    }
}

@Composable
private fun StageAssistPalette(session: MultiviewSession, horizontal: Boolean, cell: Float, modifier: Modifier) {
    val assigned = session.tiles.filter { it.camera != null }
    ControlGroup(horizontal, modifier) {
        LabeledCell(
            icon = OpcIcon.PALETTE, label = "LUT", cell = cell,
            tint = if (assigned.any { it.lutEnabled }) LiveDesign.accent else MonitorPalette.secondary,
            description = "Toggle Auto LUT for all cameras",
            enabled = assigned.isNotEmpty(),
        ) {
            val enabled = !assigned.all { it.lutEnabled }
            for (tile in assigned) if (tile.lutEnabled != enabled) tile.toggleLUT()
            session.persistStage()
        }
        LabeledCell(
            icon = if (session.fill) OpcIcon.MINIMIZE else OpcIcon.MAXIMIZE,
            label = if (session.fill) "FILL" else "FIT", cell = cell, tint = MonitorPalette.secondary,
            description = if (session.fill) "Fit feed in frame" else "Fill frame with feed",
        ) {
            session.fill = !session.fill
            session.persistStage()
        }
    }
}

@Composable
private fun ControlGroup(horizontal: Boolean, modifier: Modifier, content: @Composable () -> Unit) {
    val inner = Modifier.padding(4.dp)
    Box(modifier.monitorGlass(ControlShape), contentAlignment = Alignment.Center) {
        if (horizontal) {
            Row(inner, horizontalArrangement = Arrangement.spacedBy(3.dp)) { content() }
        } else {
            Column(inner, verticalArrangement = Arrangement.spacedBy(3.dp)) { content() }
        }
    }
}

@Composable
private fun GlyphCell(
    icon: OpcIcon,
    cell: Float,
    description: String,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Box(
        Modifier.size(cell.dp).alpha(if (enabled) 1f else 0.4f)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics {
                contentDescription = description
                role = Role.Button
            },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(icon, null, Modifier.size((cell * 0.46f).dp), MonitorPalette.secondary)
    }
}

@Composable
private fun LabeledCell(
    icon: OpcIcon,
    label: String,
    cell: Float,
    tint: Color,
    description: String,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Column(
        Modifier.size(cell.dp).alpha(if (enabled) 1f else 0.4f)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics {
                contentDescription = description
                role = Role.Button
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
    ) {
        OpcIcon(icon, null, Modifier.size(20.dp), tint)
        Text(label, color = tint, style = LiveType.text(7.5f, FontWeight.SemiBold).copy(letterSpacing = 0.7.sp))
    }
}

@Composable
private fun NetworkButton(enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier.monitorGlass(ControlShape).alpha(if (enabled) 1f else 0.4f)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics {
                contentDescription = "Shared Wi-Fi"
                role = Role.Button
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
    ) {
        OpcIcon(OpcIcon.WIFI, null, Modifier.size(20.dp), MonitorPalette.secondary)
        Text(
            "WI-FI", color = MonitorPalette.secondary,
            style = LiveType.text(7.5f, FontWeight.SemiBold).copy(letterSpacing = 0.7.sp),
        )
    }
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
private fun RecordAllButton(session: MultiviewSession, modifier: Modifier, onClick: () -> Unit) {
    val enabled = session.canRecordTogether
    Box(
        modifier.alpha(if (enabled || session.groupRecordingBusy) 1f else 0.4f)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics {
                contentDescription = if (session.anyRecording) "Stop all recording" else "Record all"
                role = Role.Button
            },
        contentAlignment = Alignment.Center,
    ) {
        MonitorRecordLamp(recording = session.anyRecording)
        if (session.groupRecordingBusy) {
            CircularProgressIndicator(Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
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
    onAdd: (MultiviewSession.Tile) -> Unit,
    onOpenLive: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val camera = tile.camera
    val focused = index == session.focusedIndex && camera != null
    Box(
        Modifier.fillMaxSize()
            .background(LiveDesign.surface, TileShape)
            .border(
                if (focused) 2.dp else 1.dp,
                when {
                    camera == null -> Color.White.copy(alpha = 0.1f)
                    focused -> LiveDesign.accent
                    else -> Color.White.copy(alpha = 0.08f)
                },
                TileShape,
            ),
    ) {
        if (camera != null) {
            if (tile.liveModel == null) {
                TileFeed(session, tile, session.fill)
            }
            // Above the video (its TextureView would take the touches) and below the controls,
            // so Add, LUT, Record and Remove keep their button behavior.
            Box(
                Modifier.fillMaxSize().pointerInput(tile, compact, enabled) {
                    if (!enabled) return@pointerInput
                    detectTapGestures(
                        onDoubleTap = { if (tile.controlHost != null) onOpenLive() },
                        onTap = {
                            session.focusedIndex = index
                            if (compact) session.layout = MultiviewLayout.CENTER_STAGE
                        },
                    )
                },
            )
            if ((!tile.hasPicture || tile.failureMessage != null || tile.recovering) && !compact) {
                TileStatusCard(session, tile, Modifier.align(Alignment.Center))
            }
            Column(Modifier.fillMaxSize().alpha(if (clean) 0f else 1f)) {
                Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            camera.name, color = LiveDesign.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            style = LiveType.text(13f, FontWeight.SemiBold).shadowed(),
                        )
                        tile.timecodeReadout?.let { timecode ->
                            Text(
                                "TC $timecode", color = LiveDesign.text, maxLines = 1,
                                style = LiveType.mono(if (compact) 9f else 11f).shadowed(),
                                modifier = Modifier.semantics { contentDescription = "Timecode $timecode" },
                            )
                        }
                    }
                    val assigned = session.tiles.count { it.camera != null }
                    val empty = session.tiles.firstOrNull { it.camera == null }
                    if (session.layout == MultiviewLayout.GRID && assigned in 1..2 && empty != null &&
                        index == session.tiles.indexOfLast { it.camera != null }
                    ) {
                        TileIconButton(
                            OpcIcon.CIRCLE_PLUS, "Add camera", glass = false,
                            enabled = !clean && !session.busy && !session.groupRecordingBusy,
                        ) { onAdd(empty) }
                    }
                    if (!compact) {
                        TileIconButton(
                            OpcIcon.X, "Remove camera preview",
                            enabled = !clean && !session.busy && !tile.connecting &&
                                !session.groupRecordingBusy && !tile.recordingBusy && !session.closing,
                        ) { session.remove(tile) }
                    }
                }
                Spacer(Modifier.weight(1f))
                if (!compact && camera.hasMultiviewPreview) {
                    Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Bottom) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(
                                settingsSummary(tile.settings, camera), color = LiveDesign.text, maxLines = 2,
                                style = LiveType.text(10f, FontWeight.SemiBold).shadowed(),
                            )
                            Text(
                                exposureSummary(tile.settings), color = LiveDesign.text, maxLines = 2,
                                style = LiveType.text(9f).shadowed(),
                            )
                            tile.recordingNote?.takeIf {
                                it != "Recording" && it != "Recording stopped" && it != "Waiting for camera confirmation"
                            }?.let { Text(it, color = LiveDesign.text, style = LiveType.text(11f).shadowed()) }
                            if (tile.hasPicture && tile.status != MultiviewSession.LIVE_STATUS) {
                                Text(tile.status, color = LiveDesign.text, style = LiveType.text(11f).shadowed())
                            }
                        }
                        Spacer(Modifier.size(3.dp))
                        Box(
                            Modifier.size(48.dp, 44.dp).liveChromeGlass(TileShape)
                                .chromeClickable(enabled = !clean) {
                                    tile.toggleLUT()
                                    session.persistStage()
                                }
                                .semantics {
                                    contentDescription = if (tile.lutEnabled) "Disable Auto LUT" else "Enable Auto LUT"
                                    stateDescription = tile.lutCaption
                                    role = Role.Button
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "LUT", color = if (tile.lutEnabled) LiveDesign.accent else LiveDesign.text,
                                style = LiveType.text(13f, FontWeight.Bold),
                            )
                        }
                        Spacer(Modifier.size(8.dp))
                        val active = tile.recordingObservation?.first == true
                        val recordEnabled = !clean && !tile.recordingBusy && !session.groupRecordingBusy &&
                            !session.closing && tile.recordingAvailable
                        Box(
                            Modifier.size(44.dp).alpha(if (tile.recordingAvailable) 1f else 0.4f)
                                .glass(CircleShape)
                                .chromeClickable(enabled = recordEnabled) {
                                    scope.launch { session.toggleRecording(tile) }
                                }
                                .semantics {
                                    contentDescription = if (active) "Stop recording" else "Start recording"
                                    role = Role.Button
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (tile.recordingBusy) {
                                CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                            } else {
                                OpcIcon(
                                    if (active) OpcIcon.SQUARE else OpcIcon.PLAY, null, Modifier.size(20.dp),
                                    if (active) LiveDesign.rec else Color.White,
                                )
                            }
                        }
                    }
                }
            }
        } else {
            Column(
                Modifier.fillMaxSize()
                    .chromeClickable(enabled = enabled && !session.busy && !session.groupRecordingBusy) { onAdd(tile) }
                    .semantics {
                        contentDescription = "Add camera"
                        role = Role.Button
                    },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
            ) {
                OpcIcon(OpcIcon.CIRCLE_PLUS, null, Modifier.size(if (compact) 24.dp else 34.dp), Color.White)
                if (!compact) {
                    Text("Add camera", color = Color.White, style = LiveType.text(16f, FontWeight.SemiBold))
                }
            }
        }
        if (camera != null && tile.recordingObservation?.first == true) {
            Box(Modifier.fillMaxSize().border(4.dp, LiveDesign.rec, TileShape))
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

@Composable
private fun TileIconButton(
    icon: OpcIcon,
    description: String,
    glass: Boolean = true,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        Modifier.size(44.dp).alpha(if (enabled) 1f else 0.4f)
            .then(if (glass) Modifier.glass(CircleShape) else Modifier)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics {
                contentDescription = description
                role = Role.Button
            },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(icon, null, Modifier.size(if (glass) 20.dp else 22.dp), Color.White)
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
    LaunchedEffect(feed, tile.plan) { feed.updatePlan(tile.plan) }
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

private fun androidx.compose.ui.text.TextStyle.shadowed() =
    copy(shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(alpha = 0.9f), blurRadius = 6f))

private fun settingsSummary(settings: CameraStatus, camera: FoundCamera): String {
    val resolution = VideoResolution.fromRaw(settings.resolutionCode)?.label ?: "—"
    val fps = if (settings.fps > 0) "${settings.fps}p" else "—"
    val color = if (settings.colorMode < 0) "Color —" else CameraCommands.colorLabel(settings.colorMode, camera.model.family)
    return "$resolution · $fps · $color"
}

private fun exposureSummary(settings: CameraStatus): String {
    val iso = if (settings.iso > 0) "${settings.iso}" else "—"
    val shutter = if (settings.shutterDenom > 0) "1/${settings.shutterDenom}" else "—"
    val wb = when {
        settings.wbMode < 0 -> "—"
        settings.wbMode == CameraCommands.WB_AUTO -> "Auto"
        settings.wbKelvin > 0 -> "${settings.wbKelvin}K"
        else -> "—"
    }
    return "ISO $iso · $shutter · WB $wb"
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
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())
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
