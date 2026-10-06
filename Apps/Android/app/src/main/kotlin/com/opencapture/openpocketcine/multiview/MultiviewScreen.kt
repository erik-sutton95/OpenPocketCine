package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.openpocketcine.pairing.lastSSID

import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.opencapture.monitorui.MonitorIcon
import com.opencapture.monitorui.MonitorPalette
import com.opencapture.monitorui.MultiviewArrangement
import com.opencapture.monitorui.MultiviewPresentationLayout
import com.opencapture.monitorui.MultiviewSafeArea
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.opencine.appkit.MultiviewCameraPicker
import com.opencapture.opencine.appkit.MultiviewPickerRow
import com.opencapture.opencine.appkit.MultiviewStage
import com.opencapture.opencine.appkit.MultiviewStageActions
import com.opencapture.opencine.appkit.MultiviewStageButton
import com.opencapture.opencine.appkit.MultiviewTool
import com.opencapture.opencine.dji.MultiviewNetworkStore
import com.opencapture.opencine.dji.appearsInMultiview
import com.opencapture.opencine.dji.hasMultiviewPreview
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LiveViewScreen
import com.opencapture.openpocketcine.feed.LiveFeedEffectsSession
import com.opencapture.openpocketcine.liveChromeGlass
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

private val StageCanvas = MonitorPalette.backgroundDeep

/**
 * Android Multiview stage. iOS `MultiviewView`: the shared stage (OpenCine appkit) over one
 * persistent tile per camera, the network popup, the camera picker and borrowed Live View.
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
            borrowed.multiviewExit = { borrowed.shell.close(); liveTile = null }
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
    val haptics = LocalOperatorHaptics.current

    BoxWithConstraints(Modifier.fillMaxSize().background(StageCanvas)) {
        val layout = MultiviewPresentationLayout.compute(
            width = maxWidth.value, height = maxHeight.value, safeArea = safe,
            arrangement = session.layout.arrangement, selected = session.focusedIndex,
        )
        MultiviewStageContent(
            session, layout, confirmsRecord = model.recordConfirmationEnabled, interactive = !overlayOpen,
            onAdd = { empty -> if (session.networkConfigured) adding = empty else showNetwork = true },
            onOpenLive = { tile ->
                session.openLiveView(tile)
                if (tile.liveModel != null) liveTile = tile
            },
            onSettings = { cameraSettings = true },
            onNetwork = { showNetwork = true },
            onExit = { if (session.tiles.any { it.camera != null }) showLeave = true else closeStage() },
            scope = scope,
        ) { tile -> if (tile.liveModel == null) TileFeed(session, tile, session.fill) }
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
                cameraSsids = model.savedCameras.mapNotNull { it.lastSSID }.toSet(),
                cancel = {
                    showNetwork = false
                    if (!session.networkConfigured) closeStage()
                },
                complete = { showNetwork = false },
            )
        } else {
            adding?.let { tile ->
                val available = session.found.filter { camera ->
                    camera.appearsInMultiview && session.tiles.none { it.camera?.id == camera.id }
                }
                MultiviewCameraPicker(
                    rows = available.map { camera ->
                        MultiviewPickerRow(
                            camera.id, camera.name,
                            detail = if (camera.hasMultiviewPreview) null
                            else "Try experimental shared Wi-Fi · Preview unavailable",
                            limited = !camera.hasMultiviewPreview,
                        )
                    },
                    onCancel = { adding = null },
                    onPick = { id ->
                        available.firstOrNull { it.id == id }?.let { camera ->
                            adding = null
                            session.enqueueAdd(camera, tile, experimental = !camera.hasMultiviewPreview)
                        }
                    },
                    footer = "Each camera will join ${session.ssid}. Approve on the camera if asked.",
                    feedback = { haptics.selection() },
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

/** The shared stage over this session: its values in, its actions out. */
@Composable
internal fun MultiviewStageContent(
    session: MultiviewSession,
    layout: MultiviewPresentationLayout,
    confirmsRecord: Boolean,
    interactive: Boolean,
    onAdd: (MultiviewSession.Tile) -> Unit,
    onOpenLive: (MultiviewSession.Tile) -> Unit,
    onSettings: () -> Unit,
    onNetwork: () -> Unit,
    onExit: () -> Unit,
    /** Outlives the stage: Live View replaces it while a record or reconnect is in flight. */
    scope: CoroutineScope = rememberCoroutineScope(),
    picture: @Composable (MultiviewSession.Tile) -> Unit,
) {
    val haptics = LocalOperatorHaptics.current
    val assigned = session.tiles.filter { it.camera != null }
    MultiviewStage(
        tiles = session.tiles.indices.map { session.stageTile(it) },
        layout = layout, arrangement = session.layout.arrangement, selected = session.focusedIndex,
        fill = session.fill,
        tools = listOf(MultiviewTool.LAYOUT, MultiviewTool.LUT, MultiviewTool.FIT, MultiviewTool.CAMERA),
        readouts = multiviewStageReadouts(session.tiles.getOrNull(session.focusedIndex)?.settings ?: CameraStatus()),
        recording = session.anyRecording, groupBusy = session.groupRecordingBusy, confirmsRecord = confirmsRecord,
        actions = MultiviewStageActions(
            select = { session.focusedIndex = it },
            arrange = {
                session.layout = if (it == MultiviewArrangement.GRID) MultiviewLayout.GRID else MultiviewLayout.CENTER_STAGE
            },
            setFill = {
                session.fill = it
                session.persistStage()
            },
            openLiveView = { slot -> session.tiles[slot].takeIf { it.controlHost != null }?.let(onOpenLive) },
            add = { onAdd(session.tiles[it]) },
            perform = { action, slot ->
                val tile = session.tiles[slot]
                when (action) {
                    MultiviewTileAction.LUT -> {
                        tile.toggleLUT()
                        session.persistStage()
                    }
                    MultiviewTileAction.RECONNECT -> scope.launch { session.reconnect(tile) }
                    MultiviewTileAction.EXPERIMENTAL -> scope.launch { session.tryExperimentalNetwork(tile) }
                    MultiviewTileAction.REMOVE -> session.remove(tile)
                }
            },
            close = onExit,
            recordContext = session::recordContext,
            record = { plan, slot -> scope.launch { session.record(plan, together = slot == null) } },
            toggleLut = {
                val enabled = !assigned.all { it.lutEnabled }
                assigned.forEach { if (it.lutEnabled != enabled) it.toggleLUT() }
                session.persistStage()
            },
            openSettings = { onSettings() },
            feedback = { haptics.selection() },
        ),
        lut = assigned.any { it.lutEnabled },
        busy = session.busy, closing = session.closing, interactive = interactive,
        network = MultiviewStageButton(
            "Shared Wi-Fi", MonitorIcon.WIFI, enabled = !session.busy && !session.connectingCameras,
            identifier = "multiview.network", action = onNetwork,
        ),
    ) { slot -> picture(session.tiles[slot]) }
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
            scopeBus = tile.scopeBus,
            preview = tile.inspectorPreview,
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
            feed.close()
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
private fun MultiviewNetworkSetup(
    session: MultiviewSession,
    cameraSsids: Set<String>,
    cancel: () -> Unit,
    complete: () -> Unit,
) {
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
        cameraSsids = cameraSsids,
    )
}
