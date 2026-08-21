package com.opencapture.openpocketcine

import android.graphics.PixelFormat
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.opencapture.openpocketcine.assists.AssistOptionsPopup
import com.opencapture.openpocketcine.assists.LiveAssistBar
import com.opencapture.openpocketcine.assists.LiveAssistLayer
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.media.MediaLibraryScreen
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.math.hypot
import kotlinx.coroutines.delay

@Composable
fun LiveViewScreen(model: AppModel) {
    val status by model.session.status.collectAsState()
    val controlNote by model.session.controlNote.collectAsState()
    val controlBusy by model.session.controlBusy.collectAsState()
    val focusPoint by model.session.focusPoint.collectAsState()
    var tick by remember { mutableIntStateOf(0) }
    var uiLocked by remember { mutableStateOf(model.uiLocked) }
    var sheet by remember { mutableStateOf<LiveSheet?>(null) }
    val context = LocalContext.current
    val assist = remember { LiveAssistState.from(context) }
    var chromeNote by remember { mutableStateOf<String?>(null) }
    var showStorageDuration by remember { mutableStateOf(false) }
    val recovery by model.session.recoveryState.collectAsState()

    ObservePhoneBattery(model)
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            tick += 1
        }
    }
    LaunchedEffect(model.assistClean, model.chromeEditorMode) {
        sheet = null
        assist.clean = model.assistClean
        if (model.assistClean || model.chromeEditorMode != null) assist.configureTool = null
    }
    LaunchedEffect(chromeNote) {
        val note = chromeNote ?: return@LaunchedEffect
        delay(2_000)
        if (chromeNote == note) chromeNote = null
    }

    fun setLocked(value: Boolean) {
        uiLocked = value
        model.uiLocked = value
        if (value) {
            model.endGimbalStick()
            sheet = null
        }
    }

    fun setClean(clean: Boolean) {
        model.setDisplayMode(clean)
        assist.clean = clean
        if (clean) {
            sheet = null
            assist.configureTool = null
        }
    }

    val chromeInteractive = !model.isEditingChrome && model.liveChromeInteractive
    val showsBottomBars =
        model.chromeSectionMounts(PocketDispSection.TOOL_BAR) ||
            model.chromeSectionMounts(PocketDispSection.CAMERA_VALUES)
    val bars =
        when {
            model.session.hasVideoFormat -> 4
            model.session.videoPackets > 0 -> 2
            else -> 1
        }
    val fpsLabel =
        when {
            status.fps > 0 -> String.format("%.2f", status.fps.toFloat())
            model.session.hasVideoFormat -> "—"
            else -> "—"
        }
    tick

    val feedBackdrop = rememberLayerBackdrop()
    val sceneBackdrop =
        rememberLayerBackdrop {
            drawRect(LiveDesign.background)
            drawContent()
        }
    val activityManager =
        remember(context) {
            context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        }
    val totalRamBytes =
        remember(activityManager) {
            ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo).totalMem
        }
    val glass =
        remember(feedBackdrop, sceneBackdrop, totalRamBytes, activityManager.isLowRamDevice) {
            MonitorGlass(
                resolveTier(
                    sdkInt = Build.VERSION.SDK_INT,
                    isLowRamDevice = activityManager.isLowRamDevice,
                    totalRamBytes = totalRamBytes,
                ),
                layerBackdrop = feedBackdrop,
                overlayBackdrop = sceneBackdrop,
                allowDemote = true,
            )
        }
    MonitorGlassBudgetLoop(glass)

    CompositionLocalProvider(LocalMonitorGlass provides glass) {
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(LiveDesign.background),
    ) {
        val density = LocalDensity.current
        val layoutDir = LocalLayoutDirection.current
        val cutout = WindowInsets.displayCutout
        val barInsets = LocalImmersiveBarInsets.current
        val portrait = maxHeight > maxWidth
        val safeTop by animateFloatAsState(
            with(density) { maxOf(cutout.getTop(this), barInsets.top).toDp().value },
            label = "safeTop",
        )
        val safeBottom by animateFloatAsState(
            with(density) { maxOf(cutout.getBottom(this), barInsets.bottom).toDp().value },
            label = "safeBottom",
        )
        val safeLeading by animateFloatAsState(
            with(density) { maxOf(cutout.getLeft(this, layoutDir), barInsets.left).toDp().value },
            label = "safeLeading",
        )
        val safeTrailing = with(density) { cutout.getRight(this, layoutDir).toDp().value }
        val navLane by animateFloatAsState(
            if (portrait) {
                0f
            } else {
                with(density) {
                    maxOf(0, barInsets.right - cutout.getRight(this, layoutDir)).toDp().value
                }
            },
            label = "navLane",
        )
        val vw = maxWidth.value - navLane
        val vh = maxHeight.value
        val fill = model.portraitFeedAspect == PortraitFeedAspect.FILL
        val assistH =
            if (!model.assistClean && !fill && model.chromeSectionMounts(PocketDispSection.TOOL_BAR)) {
                LivePortraitMetrics.ASSIST
            } else {
                0f
            }
        val zones =
            if (portrait) {
                portraitZones(
                    viewportWidth = vw,
                    viewportHeight = vh,
                    safeTop = safeTop,
                    safeBottom = safeBottom,
                    clean = model.assistClean,
                    fill = fill,
                    assistToolbarHeight = assistH,
                )
            } else {
                null
            }
        val base =
            LiveMonitorLayout.fit(
                viewportWidth = vw,
                viewportHeight = vh,
                safeLeading = safeLeading,
                safeTrailing = safeTrailing,
                safeTop = safeTop,
                safeBottom = safeBottom,
                showsBottomBars = showsBottomBars,
            )
        val layout =
            if (zones != null) {
                base.copy(
                    feed = zones.feed,
                    picture = zones.feed,
                    topDeck = zones.topBar,
                    assist = zones.assistToolbar,
                    capture = zones.controls,
                )
            } else {
                base
            }
        val zoom = if (portrait) ChromeRect(0f, 0f, 0f, 0f) else layout.zoomButton
        val stick = if (portrait) ChromeRect(0f, 0f, 0f, 0f) else layout.gimbalStick
        val focusOffCenter =
            focusPoint?.let { hypot(it.first - 0.5f, it.second - 0.5f) > 0.08f } == true

        // Kyant sibling pattern: this box records feed + chrome; popups sit
        // outside so overlayGlass does not loop.
        val sceneLayer =
            if (glass.tier == GlassTier.FULL && glass.overlayBackdrop != null) {
                Modifier.layerBackdrop(glass.overlayBackdrop)
            } else {
                Modifier
            }
        Box(Modifier.fillMaxSize().then(sceneLayer)) {
            Box(
                Modifier
                    .liveModuleFrame(layout.feed)
                    .then(
                        if (glass.tier == GlassTier.FULL && glass.layerBackdrop != null) {
                            Modifier.layerBackdrop(glass.layerBackdrop)
                        } else {
                            Modifier
                        },
                    )
                    .background(LiveDesign.feedWell),
            )
            Box(
                Modifier
                    .liveModuleFrame(layout.feed)
                    .graphicsLayer { scaleX = if (assist.mirror) -1f else 1f },
            ) {
                AndroidView(
                    factory = { context ->
                        SurfaceView(context).apply {
                            holder.setFormat(PixelFormat.RGBX_8888)
                            holder.addCallback(
                                object : SurfaceHolder.Callback {
                                    override fun surfaceCreated(holder: SurfaceHolder) {
                                        model.session.attachSurface(holder.surface)
                                    }

                                    override fun surfaceChanged(
                                        holder: SurfaceHolder,
                                        format: Int,
                                        width: Int,
                                        height: Int,
                                    ) {}

                                    override fun surfaceDestroyed(holder: SurfaceHolder) {
                                        // Keep the codec; surfaceCreated will adopt the next buffer.
                                    }
                                },
                            )
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }

            Box(Modifier.liveModuleFrame(layout.onFeed)) {
                LiveAssistLayer(
                    state = assist,
                    status = status,
                    focus = if (model.chromeSectionMounts(PocketDispSection.FOCUS_BOX)) focusPoint else null,
                    locked = uiLocked,
                )
            }

            val hasPicture by model.session.decoder.hasPicture.collectAsState()
            if (!hasPicture) {
                Box(
                    Modifier.liveModuleFrame(layout.onFeed).background(Color.Black),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        CircularProgressIndicator(color = LiveDesign.text.copy(alpha = 0.72f))
                        Text(
                            "WAITING FOR LIVE VIEW",
                            color = LiveDesign.text.copy(alpha = 0.72f),
                            style = LiveType.mono(15f, FontWeight.SemiBold),
                        )
                    }
                }
            }

            Box(Modifier.liveModuleFrame(layout.onFeed)) {
                LiveFeedGestureWell(
                    enabled = !uiLocked && model.liveOperatorPanel == null && chromeInteractive,
                    onTap = { point -> model.tapFocus(point.x, point.y) },
                    onSwipeClean = { clean -> if (!uiLocked) setClean(clean) },
                    onPinch = { mag -> LiveZoom.updatePinch(model.session, mag.toDouble()) },
                    onPinchEnd = { LiveZoom.endPinch(model.session) },
                )
            }

            if (portrait && zones != null) {
                LivePortraitChrome(
                    model = model,
                    layout = layout,
                    zones = zones,
                    status = status,
                    uiLocked = uiLocked,
                    onLock = { setLocked(!uiLocked) },
                    sheet = sheet,
                    onSheet = { sheet = it },
                    assist = assist,
                    onAssistLongPress = { assist.configureTool = it },
                    chromeInteractive = chromeInteractive,
                    onZoomCycle = {
                        val next = LiveZoom.nextJump(LiveZoom.factor(status))
                        if (!LiveZoom.setZoom(model.session, next)) chromeNote = "Zoom not available"
                    },
                    controlBusy = controlBusy,
                )
            } else {
                LandscapeChrome(
                    model = model,
                    layout = layout,
                    status = status,
                    uiLocked = uiLocked,
                    onLock = { setLocked(!uiLocked) },
                    sheet = sheet,
                    onSheet = { sheet = it },
                    assist = assist,
                    onAssistLongPress = { assist.configureTool = it },
                    chromeInteractive = chromeInteractive,
                    controlBusy = controlBusy,
                    fpsLabel = fpsLabel,
                    bars = bars,
                    showStorageDuration = showStorageDuration,
                    onToggleStorage = { showStorageDuration = !showStorageDuration },
                    zoom = zoom,
                    stick = stick,
                    focusOffCenter = focusOffCenter,
                    onFocusReset = { model.tapFocus(0.5f, 0.5f) },
                    onZoomMissing = { chromeNote = "Zoom not available" },
                )
            }

            if (status.isRecording) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .border(4.dp, LiveDesign.rec, RoundedCornerShape(32.dp)),
                )
            }

            val toast = chromeNote ?: controlNote
            if (!toast.isNullOrEmpty()) {
                Text(
                    toast,
                    color = LiveDesign.text.copy(alpha = 0.92f),
                    style = LiveType.ui(12f, FontWeight.SemiBold),
                    modifier =
                        Modifier
                            .align(Alignment.TopCenter)
                            .offset(y = (layout.onFeed.minY + 36f).dp)
                            .clip(RoundedCornerShape(50))
                            .chipGlass(RoundedCornerShape(50))
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }

            if (chromeInteractive && sheet != null && !uiLocked) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .chromeClickable(onClick = { sheet = null }),
                ) {
                    val bottomPad =
                        if (showsBottomBars) {
                            (vh - minOf(layout.assist.minY, layout.capture.minY) + LiveChromeMetrics.POPUP_GAP)
                                .coerceAtLeast(8f)
                        } else {
                            24f
                        }
                    Box(
                        Modifier
                            .align(Alignment.BottomCenter)
                            .padding(start = 16.dp, end = 16.dp, bottom = bottomPad.dp)
                            .fillMaxWidth(),
                    ) {
                        LiveControlSheet(sheet!!, model, status, uiLocked) { sheet = null }
                    }
                }
            }

            val configure = assist.configureTool
            if (chromeInteractive && configure != null && !uiLocked) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .chromeClickable(onClick = { assist.configureTool = null }),
                    contentAlignment = Alignment.BottomStart,
                ) {
                    AssistOptionsPopup(
                        tool = configure,
                        state = assist,
                        onDismiss = { assist.configureTool = null },
                        modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 88.dp),
                        model = model,
                    )
                }
            }

            val panel = model.liveOperatorPanel
            if (panel != null && !model.isEditingChrome) {
                when (panel) {
                    LiveOperatorPanel.SETTINGS ->
                        OperatorSetupScreen(model, onClose = { model.liveOperatorPanel = null })
                    LiveOperatorPanel.MEDIA ->
                        MediaLibraryScreen(model, onClose = { model.liveOperatorPanel = null })
                }
            }

            if (recovery.isRecovering) {
                MonitorRecoveryOverlay(
                    state = recovery,
                    deviceName = model.session.connectedCamera?.name.orEmpty(),
                    onRetry = { model.session.retrySessionRecovery() },
                    onOperatorMenu = { model.disconnect() },
                )
            }

            val editing = model.chromeEditorMode
            if (editing != null) {
                val boxes =
                    chromeEditBoxes(
                        layout = layout,
                        model = model,
                        uiLocked = uiLocked,
                        zoom = if (portrait && zones != null) {
                            portraitOnFeedControls(
                                layout.onFeed,
                                fill,
                                if (fill) zones.controls.height + 10f else 0f,
                                if (fill && zones.controls.height > 1f) zones.controls.minY
                                else if (zones.assistToolbar.height > 1f) zones.assistToolbar.minY
                                else zones.systemBar.minY,
                            ).second
                        } else zoom,
                        stick = if (portrait && zones != null) {
                            portraitOnFeedControls(
                                layout.onFeed,
                                fill,
                                if (fill) zones.controls.height + 10f else 0f,
                                if (fill && zones.controls.height > 1f) zones.controls.minY
                                else if (zones.assistToolbar.height > 1f) zones.assistToolbar.minY
                                else zones.systemBar.minY,
                            ).first
                        } else stick,
                    )
                ChromeEditBadgeLayer(
                    mode = editing,
                    boxes = boxes,
                    viewportWidth = vw,
                    viewportHeight = vh,
                    visible = { model.chrome(editing).isVisible(it) },
                    onToggle = { model.toggleChrome(it, editing) },
                )
                val floor =
                    if (showsBottomBars) minOf(layout.assist.minY, layout.capture.minY)
                    else layout.feed.maxY
                ChromeEditBanner(
                    mode = editing,
                    modifier =
                        Modifier
                            .align(Alignment.TopCenter)
                            .offset(x = (layout.feed.midX - vw / 2f).dp, y = (floor - 28f).dp),
                    onDone = { model.endChromeEditing() },
                )
            }
    }
    }
}

@Composable
private fun LandscapeChrome(
    model: AppModel,
    layout: LiveMonitorLayout,
    status: CameraStatus,
    uiLocked: Boolean,
    onLock: () -> Unit,
    sheet: LiveSheet?,
    onSheet: (LiveSheet?) -> Unit,
    assist: LiveAssistState,
    onAssistLongPress: (LiveAssistTool) -> Unit,
    chromeInteractive: Boolean,
    controlBusy: Boolean,
    fpsLabel: String,
    bars: Int,
    showStorageDuration: Boolean,
    onToggleStorage: () -> Unit,
    zoom: ChromeRect,
    stick: ChromeRect,
    focusOffCenter: Boolean,
    onFocusReset: () -> Unit,
    onZoomMissing: () -> Unit,
) {
    val editing = model.chromeEditorMode
    val showsStatus = model.chromeSectionMounts(PocketDispSection.STATUS_BAR)
    val showsLock = model.chromeSectionMounts(PocketDispSection.LOCK_BUTTON) || uiLocked
    val showsBatteries = model.chromeSectionMounts(PocketDispSection.BATTERIES)
    val showsSettings = model.chromeSectionMounts(PocketDispSection.RAIL_SETTINGS) || status.isRecording
    val showsMedia = model.chromeSectionMounts(PocketDispSection.RAIL_MEDIA)
    val showsRecord = model.chromeSectionMounts(PocketDispSection.RAIL_RECORD) || status.isRecording
    val showsAssist = model.chromeSectionMounts(PocketDispSection.TOOL_BAR)
    val showsCapture = model.chromeSectionMounts(PocketDispSection.CAMERA_VALUES)
    val hits = chromeInteractive

    Box(Modifier.fillMaxSize()) {
        if (showsStatus) {
            Box(
                Modifier.liveModuleFrame(layout.topDeck).chromeEditStroke(editing != null, true),
                contentAlignment = Alignment.Center,
            ) {
                LiveTopDeck(
                    model = model,
                    status = status,
                    fps = fpsLabel,
                    bars = bars,
                    enabled = !uiLocked && hits,
                    active = sheet,
                    showStorageDuration = showStorageDuration,
                    onToggleStorage = onToggleStorage,
                    onOpen = { if (!uiLocked && hits) onSheet(if (sheet == it) null else it) },
                    maxWidth = layout.topDeck.width,
                )
            }
        }
        if (showsLock) {
            Box(Modifier.liveModuleFrame(layout.lock).chromeEditStroke(editing != null, true)) {
                LockButton(uiLocked, onClick = onLock)
            }
        }
        if (showsBatteries) {
            Box(Modifier.liveModuleFrame(layout.battery).chromeEditStroke(editing != null, true)) {
                BatteryPair(
                    phonePercent = model.phoneBatteryPercent,
                    phoneCharging = model.phoneCharging,
                    cameraPercent = status.batteryPercent,
                    cameraCharging = status.charging,
                )
            }
        }
        if (showsSettings) {
            Box(Modifier.liveModuleFrame(layout.settings).chromeEditStroke(editing != null, true)) {
                AuxCircleButton(onClick = { if (hits) model.liveOperatorPanel = LiveOperatorPanel.SETTINGS }) {
                    GearGlyph(it)
                }
            }
        }
        if (showsMedia) {
            Box(Modifier.liveModuleFrame(layout.media).chromeEditStroke(editing != null, true)) {
                AuxCircleButton(onClick = { if (hits) model.liveOperatorPanel = LiveOperatorPanel.MEDIA }) {
                    MediaGlyph(it)
                }
            }
        }
        if (showsRecord) {
            Box(Modifier.liveModuleFrame(layout.record).chromeEditStroke(editing != null, true)) {
                RecordButton(
                    recording = status.isRecording,
                    enabled = !controlBusy,
                    confirm = model.recordConfirmationEnabled,
                    onClick = model::pressRecord,
                )
            }
        }
        Box(Modifier.liveModuleFrame(layout.disp)) {
            DispButton(
                clean = model.assistClean,
                onClick = {
                    if (!uiLocked && hits) {
                        val next = !model.assistClean
                        model.setDisplayMode(next)
                        assist.clean = next
                    }
                },
            )
        }
        if (model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP) && !zoom.isEmpty) {
            LiveZoomChip(
                factor = LiveZoom.factor(status),
                locked = uiLocked,
                modifier =
                    Modifier
                        .liveModuleFrame(zoom)
                        .alpha(if (uiLocked) 0.4f else 1f)
                        .chromeEditStroke(editing != null, true),
                onCycle = {
                    val next = LiveZoom.nextJump(LiveZoom.factor(status))
                    if (!LiveZoom.setZoom(model.session, next)) onZoomMissing()
                },
            )
        }
        if (model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK) && !stick.isEmpty) {
            Box(Modifier.liveModuleFrame(stick).chromeEditStroke(editing != null, true)) {
                LiveGimbalStick(
                    enabled = !uiLocked && model.liveOperatorPanel == null && hits,
                    onMove = model::updateGimbalStick,
                    onRelease = model::endGimbalStick,
                    onRecenter = { model.session.recenterGimbal() },
                    onFlip = { model.session.flipGimbal() },
                )
            }
        }
        if (!uiLocked && focusOffCenter && hits) {
            Box(Modifier.liveModuleFrame(layout.focusReset)) {
                LiveFocusResetButton(onClick = onFocusReset)
            }
        }
        if (showsAssist) {
            Box(
                Modifier
                    .liveModuleFrame(layout.assist)
                    .alpha(if (uiLocked) 0.4f else 1f)
                    .chromeEditStroke(editing != null, true),
            ) {
                LiveAssistBar(
                    state = assist,
                    locked = uiLocked || !hits,
                    onLongPress = onAssistLongPress,
                )
            }
        }
        if (showsCapture) {
            Box(
                Modifier
                    .liveModuleFrame(layout.capture)
                    .alpha(if (uiLocked) 0.4f else 1f)
                    .chromeEditStroke(editing != null, true),
                contentAlignment = Alignment.CenterEnd,
            ) {
                LiveCaptureStrip(
                    status = status,
                    active = sheet,
                    enabled = !uiLocked && !controlBusy && hits,
                    onOpen = { onSheet(if (sheet == it) null else it) },
                )
            }
        }
    }
}

@Composable
private fun LiveTopDeck(
    model: AppModel,
    status: CameraStatus,
    fps: String,
    bars: Int,
    enabled: Boolean,
    active: LiveSheet?,
    showStorageDuration: Boolean,
    onToggleStorage: () -> Unit,
    onOpen: (LiveSheet) -> Unit,
    maxWidth: Float,
) {
    FitScale(maxWidth.dp) {
    InfoPill {
        if (model.chromeSectionMounts(PocketDispSection.REC_READOUT)) RecChip(status.isRecording)
        if (model.chromeSectionMounts(PocketDispSection.TIMECODE)) TimecodeReadout(status.timecode)
        if (model.chromeSectionMounts(PocketDispSection.FORMAT)) {
            val label =
                buildString {
                    append(status.resolutionLabel.replace("—", "—"))
                    append("·")
                    append(if (status.fps > 0) "${status.fps}" else "—")
                }
            ReadoutPill(
                label,
                active = active == LiveSheet.FORMAT,
                enabled = enabled,
                onClick = { onOpen(LiveSheet.FORMAT) },
            ) { VideoGlyph(it) }
        }
        if (model.chromeSectionMounts(PocketDispSection.COLOR)) {
            ReadoutPill(
                status.colorLabel,
                active = active == LiveSheet.COLOR,
                enabled = enabled,
                onClick = { onOpen(LiveSheet.COLOR) },
            ) { ColorGlyph(it) }
        }
        if (model.chromeSectionMounts(PocketDispSection.STORAGE)) {
            val storage =
                if (showStorageDuration) {
                    if (status.recordRemainingSec > 0) "${status.recordRemainingSec / 60} Min" else "— Min"
                } else {
                    status.storageLabel
                }
            ReadoutPill(storage, onClick = onToggleStorage) { SdCardGlyph(it) }
        }
        if (model.chromeSectionMounts(PocketDispSection.FPS)) FpsChip(fps, bars)
    }
    }
}


