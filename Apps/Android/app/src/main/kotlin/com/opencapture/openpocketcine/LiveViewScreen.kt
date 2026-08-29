package com.opencapture.openpocketcine

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.zIndex
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import android.os.SystemClock
import com.opencapture.openpocketcine.session.SessionRecoveryCopy
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.opencapture.openpocketcine.assists.AssistLongPress
import com.opencapture.openpocketcine.assists.AssistOptionsPopup
import com.opencapture.openpocketcine.assists.LiveAssistBar
import com.opencapture.openpocketcine.assists.LiveAssistLayer
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan
import com.opencapture.openpocketcine.feed.FeedPresentPolicy
import com.opencapture.openpocketcine.feed.GpuOverlayBus
import com.opencapture.openpocketcine.feed.LiveFeedEffectsSession
import com.opencapture.openpocketcine.feed.LiveVulkanSession
import com.opencapture.openpocketcine.feed.LocalGpuLive
import com.opencapture.openpocketcine.feed.OpcVulkan
import com.opencapture.openpocketcine.feed.rememberLiveFeedEffectsPlan
import com.opencapture.openpocketcine.media.MediaLibraryScreen
import com.opencapture.openpocketcine.session.CamFov
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.ControlHud
import com.opencapture.openpocketcine.session.FocusOverlay
import com.opencapture.openpocketcine.session.TrackingBox
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

@Composable
fun LiveViewScreen(model: AppModel) {
    val status by model.session.status.collectAsState()
    val controlNote by model.session.controlNote.collectAsState()
    val controlBusy by model.session.controlBusy.collectAsState()
    val focusPoint by model.session.focusPoint.collectAsState()
    val zoomReadout by model.session.zoomReadout.collectAsState()
    val zoomPinching by model.session.zoomPinching.collectAsState()
    val trackingHud by model.session.trackingHud.collectAsState()
    val poseViewFlip by model.session.gimbalPoseViewFlip.collectAsState()
    var tick by remember { mutableIntStateOf(0) }
    var uiLocked by remember { mutableStateOf(model.uiLocked) }
    var sheet by remember { mutableStateOf<LiveSheet?>(null) }
    val context = LocalContext.current
    val assist = model.assist
    val wantedViewFlip = CameraCommands.liveViewFlip(poseViewFlip, assist.mirror)
    var liveViewFlip by remember { mutableStateOf(wantedViewFlip) }
    LaunchedEffect(wantedViewFlip) {
        if (liveViewFlip == wantedViewFlip) return@LaunchedEffect
        delay(FeedPresentPolicy.EXTRA_MIRROR_HOLD_MS)
        liveViewFlip = wantedViewFlip
    }
    var chromeNote by remember { mutableStateOf<String?>(null) }
    var showStorageDuration by remember { mutableStateOf(false) }
    val recovery by model.session.recoveryState.collectAsState()
    val verticalPicture by model.session.decoder.isVerticalPicture.collectAsState()

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
    LaunchedEffect(
        sheet,
        model.session.connectedCamera?.model?.supportsFocusMode,
        model.session.connectedCamera?.model?.family,
        model.session.connectedCamera?.model?.name,
    ) {
        if (sheet == LiveSheet.FOCUS &&
            !CaptureLists.supportsFocusModeOrDefault(model.session.connectedCamera?.model)
        ) {
            sheet = null
        }
    }
    LaunchedEffect(chromeNote) {
        val note = chromeNote ?: return@LaunchedEffect
        delay((ControlHud.TOAST_HOLD_SECONDS * 1000).toLong())
        if (chromeNote == note) chromeNote = null
    }
    LaunchedEffect(controlNote) {
        val note = controlNote ?: return@LaunchedEffect
        delay((ControlHud.TOAST_HOLD_SECONDS * 1000).toLong())
        model.session.clearControlNoteIf(note)
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
    val pickerFrames = remember { mutableStateMapOf<LiveSheet, ChromeRect>() }
    val statusChipFrames = remember { mutableStateMapOf<PocketDispSection, ChromeRect>() }
    var fpsLabel by remember { mutableStateOf("—") }
    var bars by remember { mutableIntStateOf(0) }
    val fpsSampler = remember { FrameRateSampler() }
    val signalBars = remember { LinkSignalBars() }
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
            )
        }

    var vulkanFailed by remember { mutableStateOf(false) }
    val vulkanSession =
        remember {
            if (OpcVulkan.isAvailable) {
                LiveVulkanSession(
                    context = context,
                    onDecoderSurface = { model.session.attachSurface(it) },
                    onFirstFrame = { model.session.noteLiveFrame() },
                    onFailed = { vulkanFailed = true },
                )
            } else {
                null
            }
        }
    DisposableEffect(vulkanSession) {
        onDispose {
            vulkanSession?.release()
            model.session.attachSurface(null)
        }
    }
    val useVulkan = vulkanSession != null && !vulkanFailed
    LaunchedEffect(model.session, useVulkan, vulkanSession) {
        var lastCount = 0
        var lastAt = 0L
        var held = "—"
        while (true) {
            val now = SystemClock.elapsedRealtime()
            val count =
                if (useVulkan) {
                    vulkanSession?.framesPresented?.get() ?: 0
                } else {
                    model.session.decoder.framesPresented.get()
                }
            if (lastAt > 0L && now > lastAt) {
                val instant = (count - lastCount) * 1000.0 / (now - lastAt).toDouble()
                if (instant >= 0.0) fpsSampler.recordFrameRate(instant)
            }
            lastCount = count
            lastAt = now
            val presented = model.session.decoder.lastPresentedAt
            val recovering = model.session.isFeedRecovering
            val phase = model.session.phaseFlow.value
            val label =
                if (model.session.recoveryState.value.isRecovering) {
                    SessionRecoveryCopy.HELD_FRAME_BADGE
                } else {
                    LiveViewLink.fpsChipLabel(
                        connection = phase,
                        recovering = recovering,
                        formattedFPS = fpsSampler.formatted,
                        measuredFPS = fpsSampler.displayFPS,
                    )
                }
            held = LiveChromeReadout.holdFPS(label, held)
            fpsLabel = held
            val measured = fpsSampler.displayFPS
            val snapshot =
                CameraLinkHealthScorer.score(
                    CameraLinkHealthInputs(
                        phase = LiveViewLink.cameraLinkPhase(phase, recovering, measured),
                        liveViewFPS = measured.takeIf { it > 0 },
                        targetLiveViewFPS = LiveViewLink.TARGET_FPS,
                        secondsSinceLastGoodFrame = presented?.let { (now - it) / 1000.0 },
                        isRecoveringStream = recovering,
                    ),
                )
            bars = signalBars.update(snapshot.linkHealthScore)
            delay(200)
        }
    }

    CompositionLocalProvider(LocalMonitorGlass provides glass) {
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(if (useVulkan) Color.Transparent else LiveDesign.background),
    ) {
        val density = LocalDensity.current
        val layoutDir = LocalLayoutDirection.current
        val cutout = WindowInsets.displayCutout
        val barInsets = LocalImmersiveBarInsets.current
        val portrait = maxHeight > maxWidth
        val chromeScale =
            monitorChromeScale(LocalConfiguration.current.smallestScreenWidthDp.toFloat())
        LiveChromeMetrics.scale = chromeScale
        // Live safe area: punch-hole cutout plus applied system-bar lanes.
        // Landscape leading is floored at the iPhone island lane so the 16:9
        // feed sits right of lock/battery (OpenZCine `monitorLeadingInsetDp`).
        // Trailing gets no floor; `feedFrame` yields a RAIL_W lane so the
        // record rail clears the picture.
        fun edgeDp(cutoutPx: Int, barPx: Int): Float =
            with(density) { maxOf(cutoutPx, barPx).toDp().value }
        val safeTop by animateFloatAsState(
            edgeDp(cutout.getTop(density), barInsets.top),
            label = "safeTop",
        )
        val safeBottom by animateFloatAsState(
            monitorBottomInsetDp(
                rawInsetDp = edgeDp(cutout.getBottom(density), barInsets.bottom),
                isPortrait = portrait,
            ),
            label = "safeBottom",
        )
        val safeLeading by animateFloatAsState(
            with(density) {
                val cutoutDp = cutout.getLeft(this, layoutDir).toDp().value
                if (portrait) {
                    cutoutDp
                } else {
                    monitorLeadingInsetDp(
                        cutoutDp = cutoutDp,
                        transientBarDp = barInsets.left.toDp().value,
                        chromeScale = chromeScale,
                    )
                }
            },
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
        val fill =
            if (verticalPicture) true else model.portraitFeedAspect == PortraitFeedAspect.FILL
        val feedAspectRatio = if (verticalPicture) 9f / 16f else 16f / 9f
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
                    feedAspectRatio = feedAspectRatio,
                )
            } else {
                null
            }
        val pictureAspect = model.session.decoder.pictureAspect.toFloat()
        val base =
            LiveMonitorLayout.fit(
                viewportWidth = vw,
                viewportHeight = vh,
                safeLeading = safeLeading,
                safeTrailing = safeTrailing,
                safeTop = safeTop,
                safeBottom = safeBottom,
                showsBottomBars = showsBottomBars,
                chromeScale = chromeScale,
                pictureAspect = pictureAspect,
            )
        val layout =
            if (zones != null) {
                val well = zones.feed
                val picture =
                    if (verticalPicture && well.height > 1f) {
                        val width = well.height * 9f / 16f
                        ChromeRect(well.midX - width / 2f, well.minY, width, well.height)
                    } else {
                        well
                    }
                base.copy(
                    feed = well,
                    picture = picture,
                    topDeck = zones.topBar,
                    assist = zones.assistToolbar,
                    capture = zones.controls,
                )
            } else {
                base
            }
        // iOS fillCrop: landscape fill over-widens 16:9 to the well height
        // then clips (center crop). Vertical Pocket fill stays 9:16 pillars.
        val fillCrop = zones != null && fill && !verticalPicture
        val pictureContent =
            if (fillCrop) portraitFillCropContent(layout.feed) else layout.onFeed
        val zoom = if (portrait) ChromeRect(0f, 0f, 0f, 0f) else layout.zoomButton
        val stick = if (portrait) ChromeRect(0f, 0f, 0f, 0f) else layout.gimbalStick
        val focusOffCenter = model.session.isFocusResetAvailable

        // Kyant sibling pattern: this box records feed + chrome; popups sit
        // outside so overlayGlass does not loop.
        val effectsPlan =
            rememberLiveFeedEffectsPlan(
                assist = assist,
                lutSelection = model.lutSelection,
                status = status,
                family = model.session.connectedCamera?.model?.family.orEmpty(),
                cameraName = model.session.connectedCamera?.name,
            )
        val sceneLayer =
            if (glass.tier == GlassTier.FULL && glass.overlayBackdrop != null) {
                Modifier.layerBackdrop(glass.overlayBackdrop)
            } else {
                Modifier
            }
        var vulkanSurfaceView by remember { mutableStateOf<SurfaceView?>(null) }
        var glesTextureView by remember { mutableStateOf<TextureView?>(null) }
        val wantsFaceDetect by model.session.wantsFaceDetect.collectAsState()
        var canvasOrigin by remember { mutableStateOf(Offset.Zero) }
        val platesGen = GpuOverlayBus.platesGeneration
        DisposableEffect(vulkanSession) {
            GpuOverlayBus.onSlotsMoved = { vulkanSession?.slotsMoved() }
            model.session.decoder.onOutputSizeChanged = { w, h ->
                vulkanSession?.setSourceSize(w, h)
            }
            onDispose {
                GpuOverlayBus.onSlotsMoved = null
                model.session.decoder.onOutputSizeChanged = null
            }
        }
        LaunchedEffect(
            useVulkan,
            effectsPlan,
            canvasOrigin,
            platesGen,
            layout.onFeed,
            density.density,
            liveViewFlip,
        ) {
            val session = vulkanSession ?: return@LaunchedEffect
            if (!useVulkan) return@LaunchedEffect
            val picture = layout.onFeed
            session.setFeedRect(
                with(density) { picture.x.dp.toPx() },
                with(density) { picture.y.dp.toPx() },
                with(density) { picture.width.dp.toPx() },
                with(density) { picture.height.dp.toPx() },
            )
            session.setPlates(GpuOverlayBus.plateSnapshot())
            session.syncAssists(
                assist = assist,
                plan = effectsPlan,
                canvasOriginX = canvasOrigin.x,
                canvasOriginY = canvasOrigin.y,
                wave = GpuOverlayBus.wave,
                parade = GpuOverlayBus.parade,
                histoRect = GpuOverlayBus.histo,
                vector = GpuOverlayBus.vector,
                uiScale = density.density,
                pictureMirrored = liveViewFlip,
            )
        }
        CompositionLocalProvider(
            LocalDensity provides Density(density.density, density.fontScale * chromeScale),
            LocalLiveCanvasOrigin provides canvasOrigin,
            LocalGpuLive provides if (useVulkan) vulkanSession else null,
        ) {
        Box(
            Modifier
                .fillMaxSize()
                .then(sceneLayer)
                .onGloballyPositioned {
                    if (!useVulkan) canvasOrigin = it.positionInRoot()
                },
        ) {
            if (useVulkan) {
                VulkanLivePresenter(
                    session = checkNotNull(vulkanSession),
                    onSurfaceView = { vulkanSurfaceView = it },
                    modifier =
                        Modifier
                            .fillMaxSize()
                            .onGloballyPositioned { canvasOrigin = it.positionInRoot() },
                )
                if (glass.tier == GlassTier.FULL && glass.layerBackdrop != null) {
                    Box(
                        Modifier
                            .liveModuleFrame(layout.onFeed)
                            .layerBackdrop(glass.layerBackdrop)
                            .clipToBounds(),
                    ) {
                        vulkanSurfaceView?.let { view ->
                            VulkanKyantCapture(view, Modifier.fillMaxSize())
                        }
                    }
                }
            }
            // GLES TextureView stays inside the feed well so Kyant can sample it
            // when Vulkan is unavailable. Vulkan presents a full-canvas SurfaceView;
            // FULL glass PixelCopies that surface into the recorded well.
            if (!useVulkan) {
            Box(
                Modifier
                    .liveModuleFrame(layout.onFeed)
                    .then(
                        if (glass.tier == GlassTier.FULL && glass.layerBackdrop != null) {
                            Modifier.layerBackdrop(glass.layerBackdrop)
                        } else {
                            Modifier
                        },
                    )
                    .clipToBounds(),
            ) {
                LiveFeedPresenter(
                    mirrored = liveViewFlip,
                    captureFrames = glass.tier == GlassTier.FULL,
                    plan = effectsPlan,
                    onDecoderSurface = { model.session.attachSurface(it) },
                    onPresented = { model.session.noteLiveFrame() },
                    onTextureView = { glesTextureView = it },
                    modifier =
                        Modifier
                            .offset(
                                (pictureContent.x - layout.onFeed.x).dp,
                                (pictureContent.y - layout.onFeed.y).dp,
                            )
                            .size(pictureContent.width.dp, pictureContent.height.dp),
                )
            }
            }

            // iOS `LiveZoomPinchWell` sits under chip + scopes so hold-drag
            // on WAVE / PARADE / HISTO / VECTOR still reaches MovableAssistPanel.
            Box(Modifier.liveModuleFrame(layout.onFeed)) {
                LiveFeedGestureWell(
                    enabled = !uiLocked && model.liveOperatorPanel == null && chromeInteractive,
                    feed = ChromeRect(0f, 0f, layout.onFeed.width, layout.onFeed.height),
                    onTap = { point ->
                        val x = if (liveViewFlip) 1f - point.x else point.x
                        model.session.handleFeedTap(x, point.y)
                    },
                    onSwipeClean = { clean -> if (!uiLocked) setClean(clean) },
                    onPinch = { mag -> model.session.updateZoomPinch(mag.toDouble()) },
                    onPinchEnd = { model.session.endZoomPinch() },
                    onTrack = { box ->
                        model.session.startTracking(if (liveViewFlip) box.mirrored() else box)
                    },
                )
            }

            Box(Modifier.fillMaxSize().zIndex(1f)) {
                LiveAssistLayer(
                    state = assist,
                    status = status,
                    focus = if (model.chromeSectionMounts(PocketDispSection.FOCUS_BOX)) focusPoint else null,
                    tracking = trackingHud,
                    showTapFocusBox =
                        model.chromeSectionMounts(PocketDispSection.FOCUS_BOX) &&
                            model.session.supportsTapFocus,
                    locked = uiLocked,
                    feedFrame = layout.onFeed,
                    pictureMirrored = liveViewFlip,
                    onOpenOptions = { tool, frame ->
                        assist.longPressAnchor = frame
                        assist.configureTool = tool
                    },
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

            LiveFaceFramePump(
                surfaceView = vulkanSurfaceView,
                textureView = glesTextureView,
                feed = layout.onFeed,
                enabled = wantsFaceDetect && hasPicture,
                onFrame = { bmp -> model.session.considerFaceFrame(bmp) },
            )
            Box(Modifier.liveModuleFrame(layout.onFeed)) {
                val subject = trackingHud.overlay as? FocusOverlay.Subject
                if (!uiLocked && chromeInteractive && subject != null) {
                    LiveTrackingCancelButton(
                        box = subject.box,
                        feedWidth = layout.onFeed.width,
                        feedHeight = layout.onFeed.height,
                        mirrored = liveViewFlip,
                        onClick = { model.session.cancelSubjectTracking() },
                    )
                }
            }

            if (portrait && zones != null) {
                Box(Modifier.zIndex(2f)) {
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
                    controlBusy = controlBusy,
                    onTileFrame = { key, rect -> pickerFrames[key] = rect },
                )
                }
            } else {
                Box(Modifier.zIndex(2f)) {
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
                    onFocusReset = { model.session.resetFocusPoint() },
                    zoomReadout = zoomReadout,
                    zoomPinching = zoomPinching,
                    onTileFrame = { key, rect -> pickerFrames[key] = rect },
                    onStatusChipFrame = { section, rect -> statusChipFrames[section] = rect },
                )
                }
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
                val chromeBottom =
                    if (model.chromeSectionMounts(PocketDispSection.STATUS_BAR) &&
                        layout.topDeck.height > 1f
                    ) {
                        layout.topDeck.maxY.toDouble()
                    } else {
                        null
                    }
                val toastY =
                    ControlHud.toastCenterY(
                        layout.onFeed.minY.toDouble(),
                        chromeBottom,
                    ).toFloat()
                val parkedY by animateFloatAsState(toastY, tween(180), label = "toastY")
                var toastHeightPx by remember { mutableIntStateOf(0) }
                val toastDensity = LocalDensity.current
                Text(
                    toast,
                    color = LiveDesign.text.copy(alpha = 0.92f),
                    style = LiveType.ui(12f, FontWeight.SemiBold),
                    modifier =
                        Modifier
                            .align(Alignment.TopCenter)
                            .onSizeChanged { toastHeightPx = it.height }
                            .offset {
                                IntOffset(
                                    0,
                                    with(toastDensity) { parkedY.dp.roundToPx() } - toastHeightPx / 2,
                                )
                            }
                            .clip(RoundedCornerShape(50))
                            .chipGlass(RoundedCornerShape(50))
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }

            val popupCeilingY =
                if (layout.topDeck.height > 1f) {
                    layout.topDeck.maxY + LiveChromeMetrics.TOP_PICKER_GAP
                } else {
                    maxOf(safeTop + 4f, LiveChromeMetrics.CHROME_TOP)
                }
            if (chromeInteractive && sheet != null && !uiLocked) {
                val floorY =
                    if (showsBottomBars) {
                        minOf(layout.assist.minY, layout.capture.minY) - LiveChromeMetrics.POPUP_GAP
                    } else {
                        null
                    }
                LivePickerHost(
                    sheet = sheet!!,
                    frames = pickerFrames.toMap(),
                    bar = layout.capture,
                    topDeck = layout.topDeck,
                    viewportWidth = vw,
                    viewportHeight = vh,
                    safeLeading = safeLeading,
                    safeTrailing = safeTrailing,
                    safeTop = safeTop,
                    safeBottom = safeBottom,
                    ceilingY = 0f,
                    floorY = floorY,
                    model = model,
                    status = status,
                    locked = uiLocked,
                    onSelect = { sheet = it },
                )
            }

            val configure = assist.configureTool
            if (chromeInteractive && configure != null && !uiLocked) {
                val preferred = AssistLongPress.preferredWidthDp(configure)
                var panelH by remember(configure) { mutableStateOf(240f) }
                var assistShown by remember(configure) { mutableStateOf(false) }
                LaunchedEffect(configure) { assistShown = true }
                val assistRevealed by
                    animateFloatAsState(
                        if (assistShown) 1f else 0f,
                        tween(200, easing = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)),
                        label = "assist-popup-reveal",
                    )
                val toolbar =
                    if (portrait && zones != null && zones.assistToolbar.height > 1f) {
                        zones.assistToolbar
                    } else {
                        layout.assist
                    }
                // Same well as LUT: nearly to the top edge (ASSIST_MARGIN), so
                // ZEBRA / GUIDES can grow instead of sitting under STBY / TC.
                val place =
                    LivePopupPlacement.assistOptions(
                        icon = assist.longPressAnchor,
                        toolbar = toolbar,
                        preferredWidth = preferred,
                        panelHeight = panelH,
                        viewportWidth = vw,
                        viewportHeight = vh,
                        safeLeading = safeLeading,
                        safeTrailing = safeTrailing,
                        safeTop = safeTop,
                        safeBottom = safeBottom,
                        ceilingY = 0f,
                    )
                val assistSlide = place.maxHeight + 20f
                Box(
                    Modifier
                        .fillMaxSize()
                        .zIndex(8f)
                        .chromeClickable(onClick = { assist.configureTool = null }),
                ) {
                    AssistOptionsPopup(
                        tool = configure,
                        state = assist,
                        onDismiss = { assist.configureTool = null },
                        maxHeightDp = place.maxHeight,
                        modifier =
                            Modifier
                                .offset(
                                    place.x.dp,
                                    (place.y + (1f - assistRevealed) * assistSlide).dp,
                                )
                                .graphicsLayer { alpha = assistRevealed }
                                .onSizeChanged { panelH = it.height / density.density },
                        model = model,
                        colorMode = status.colorMode,
                    )
                }
            }

            val panel = model.liveOperatorPanel
            LaunchedEffect(panel) { model.session.setOperatorOverlayHeld(panel != null) }
            if (panel != null && !model.isEditingChrome) {
                Box(Modifier.fillMaxSize().zIndex(10f)) {
                    when (panel) {
                        LiveOperatorPanel.SETTINGS ->
                            OperatorSetupScreen(model, onClose = { model.liveOperatorPanel = null })
                        LiveOperatorPanel.MEDIA ->
                            MediaLibraryScreen(model, onClose = { model.liveOperatorPanel = null })
                    }
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
                        statusChips = statusChipFrames.toMap(),
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
}

@Composable
private fun LiveFaceFramePump(
    surfaceView: SurfaceView?,
    textureView: TextureView?,
    feed: ChromeRect,
    enabled: Boolean,
    onFrame: (Bitmap) -> Unit,
) {
    val density = LocalDensity.current
    val handler = remember { Handler(Looper.getMainLooper()) }
    val inFlight = remember { AtomicBoolean(false) }
    val latest = rememberUpdatedState(onFrame)
    LaunchedEffect(surfaceView, textureView, enabled, feed.x, feed.y, feed.width, feed.height) {
        if (!enabled) return@LaunchedEffect
        val tapW = 320
        while (isActive) {
            delay(com.opencapture.openpocketcine.session.LiveFaceDetector.INTERVAL_MS)
            if (!inFlight.compareAndSet(false, true)) continue
            val tapH =
                ((tapW * feed.height / feed.width.coerceAtLeast(1f)).toInt() and 1.inv())
                    .coerceAtLeast(16)
            val gles = textureView
            if (gles != null && gles.isAvailable) {
                val src = gles.getBitmap(tapW, tapH)
                inFlight.set(false)
                if (src != null) latest.value(src)
                continue
            }
            val view = surfaceView
            if (view == null || !view.holder.surface.isValid) {
                inFlight.set(false)
                continue
            }
            val left = with(density) { feed.x.dp.toPx() }.roundToInt().coerceAtLeast(0)
            val top = with(density) { feed.y.dp.toPx() }.roundToInt().coerceAtLeast(0)
            val right =
                (left + with(density) { feed.width.dp.toPx() }.roundToInt())
                    .coerceAtMost(view.width.coerceAtLeast(left + 1))
            val bottom =
                (top + with(density) { feed.height.dp.toPx() }.roundToInt())
                    .coerceAtMost(view.height.coerceAtLeast(top + 1))
            if (right - left < 8 || bottom - top < 8) {
                inFlight.set(false)
                continue
            }
            val dest = Bitmap.createBitmap(tapW, tapH, Bitmap.Config.ARGB_8888)
            try {
                PixelCopy.request(
                    view,
                    Rect(left, top, right, bottom),
                    dest,
                    { result ->
                        inFlight.set(false)
                        if (result == PixelCopy.SUCCESS) {
                            latest.value(dest)
                        } else {
                            dest.recycle()
                        }
                    },
                    handler,
                )
            } catch (_: Exception) {
                inFlight.set(false)
                dest.recycle()
            }
        }
    }
}

private val GLASS_BLIT_PAINT =
    Paint().apply {
        isFilterBitmap = false
        isAntiAlias = false
        isDither = false
    }

@Composable
private fun VulkanLivePresenter(
    session: LiveVulkanSession,
    onSurfaceView: (SurfaceView?) -> Unit,
    modifier: Modifier = Modifier,
) {
    DisposableEffect(Unit) { onDispose { onSurfaceView(null) } }
    AndroidView(
        factory = { viewContext ->
            SurfaceView(viewContext).apply {
                isClickable = false
                isFocusable = false
                setZOrderMediaOverlay(false)
                unsplitMotionEvents()
                onSurfaceView(this)
                holder.addCallback(
                    object : SurfaceHolder.Callback {
                        override fun surfaceCreated(holder: SurfaceHolder) = Unit

                        override fun surfaceChanged(
                            holder: SurfaceHolder,
                            format: Int,
                            width: Int,
                            height: Int,
                        ) {
                            this@apply.unsplitMotionEvents()
                            session.attachWindow(holder.surface, width, height)
                        }

                        override fun surfaceDestroyed(holder: SurfaceHolder) {
                            session.detachWindow()
                        }
                    },
                )
            }
        },
        modifier = modifier,
    )
}

/** Keep both pinch fingers on one view — Android otherwise splits pointer 2 onto SurfaceView. */
private fun View.unsplitMotionEvents() {
    var walk: View? = this
    while (walk != null) {
        (walk as? ViewGroup)?.isMotionEventSplittingEnabled = false
        walk = walk.parent as? View
    }
}

/**
 * Kyant cannot sample a SurfaceView. FULL glass copies the feed well from the
 * Vulkan surface into a Compose Canvas so [Modifier.layerBackdrop] records it.
 */
@Composable
private fun VulkanKyantCapture(
    surfaceView: SurfaceView,
    modifier: Modifier = Modifier,
) {
    var frameGen by remember { mutableIntStateOf(0) }
    val frameBmp = remember { arrayOfNulls<Bitmap>(1) }
    var srcRect by remember { mutableStateOf(Rect()) }
    val inFlight = remember { AtomicBoolean(false) }
    val handler = remember { Handler(Looper.getMainLooper()) }

    LaunchedEffect(surfaceView) {
        while (isActive) {
            withFrameNanos { }
            val rect = Rect(srcRect)
            val w = rect.width()
            val h = rect.height()
            if (w <= 1 || h <= 1) continue
            if (!surfaceView.holder.surface.isValid) continue
            if (!inFlight.compareAndSet(false, true)) continue
            val dst =
                frameBmp[0]?.takeIf { it.width == w && it.height == h }
                    ?: Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { frameBmp[0] = it }
            PixelCopy.request(surfaceView, rect, dst, { result ->
                inFlight.set(false)
                if (result == PixelCopy.SUCCESS) frameGen += 1
            }, handler)
            // HUD glass does not need 120 Hz copies — that plus per-scope lens
            // is what cooked the S25.
            delay(48)
        }
    }

    Canvas(
        modifier.onGloballyPositioned { coords ->
            val pos = coords.positionInWindow()
            val size = coords.size
            val loc = IntArray(2)
            surfaceView.getLocationInWindow(loc)
            val left = (pos.x - loc[0]).roundToInt().coerceIn(0, surfaceView.width)
            val top = (pos.y - loc[1]).roundToInt().coerceIn(0, surfaceView.height)
            val right = (left + size.width).coerceIn(0, surfaceView.width)
            val bottom = (top + size.height).coerceIn(0, surfaceView.height)
            srcRect = Rect(left, top, right, bottom)
        },
    ) {
        @Suppress("UNUSED_EXPRESSION")
        val gen = frameGen
        val bmp = frameBmp[0]
        if (gen > 0 && bmp != null && !bmp.isRecycled) {
            drawIntoCanvas { canvas ->
                val dstW = size.width.toInt()
                val dstH = size.height.toInt()
                if (bmp.width == dstW && bmp.height == dstH) {
                    canvas.nativeCanvas.drawBitmap(bmp, 0f, 0f, GLASS_BLIT_PAINT)
                } else {
                    val dst = Rect(0, 0, dstW, dstH)
                    canvas.nativeCanvas.drawBitmap(bmp, null, dst, GLASS_BLIT_PAINT)
                }
            }
        }
    }
}

/**
 * GLES fallback when Vulkan cannot init. Kyant cannot sample a TextureView, so
 * FULL glass still blits each frame into a Compose Canvas.
 *
 * LUT / PEAK / FALSE / ZEBRA paint through GLES on a `GL_TEXTURE_EXTERNAL_OES`
 * producer so the identity HEVC surface is never remade when those tools toggle.
 */
@Composable
private fun LiveFeedPresenter(
    mirrored: Boolean,
    captureFrames: Boolean,
    plan: FeedEffectsRenderPlan,
    onDecoderSurface: (Surface) -> Unit,
    onPresented: () -> Unit = {},
    onTextureView: (TextureView?) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var frameGen by remember { mutableIntStateOf(0) }
    val frameBmp = remember { arrayOfNulls<Bitmap>(1) }
    val capture = rememberUpdatedState(captureFrames)
    val attach = rememberUpdatedState(onDecoderSurface)
    val presented = rememberUpdatedState(onPresented)
    val textureViewOut = rememberUpdatedState(onTextureView)
    val context = LocalContext.current
    var gpuFailed by remember { mutableStateOf(false) }
    val session =
        remember {
            LiveFeedEffectsSession(
                context = context,
                onDecoderSurface = { attach.value(it) },
                onGpuFailed = { gpuFailed = true },
                onFirstFrame = { presented.value() },
            )
        }
    DisposableEffect(session) {
        onDispose {
            session.detachDisplay()
            textureViewOut.value(null)
        }
    }
    LaunchedEffect(plan) { session.updatePlan(plan) }

    Box(modifier.graphicsLayer { scaleX = if (mirrored) -1f else 1f }) {
        key(gpuFailed) {
            AndroidView(
                factory = { viewContext ->
                    TextureView(viewContext).apply {
                        isOpaque = true
                        textureViewOut.value(this)
                        val onUpdated: (TextureView) -> Unit = { tv ->
                            presented.value()
                            if (capture.value) {
                                val w = tv.width
                                val h = tv.height
                                if (w > 0 && h > 0) {
                                    val dst =
                                        frameBmp[0]?.takeIf { it.width == w && it.height == h }
                                            ?: Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                                                .also { frameBmp[0] = it }
                                    tv.getBitmap(dst)
                                    tv.post { frameGen += 1 }
                                }
                            }
                        }
                        surfaceTextureListener =
                            if (gpuFailed) {
                                TextureFeedListener(
                                    host = this,
                                    onSurface = { attach.value(it) },
                                    onUpdated = onUpdated,
                                )
                            } else {
                                EffectsFeedListener(
                                    host = this,
                                    session = session,
                                    onUpdated = onUpdated,
                                )
                            }
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
        }
        val gen = frameGen
        val bmp = frameBmp[0]
        if (captureFrames && gen > 0 && bmp != null && !bmp.isRecycled) {
            Canvas(Modifier.fillMaxSize()) {
                @Suppress("UNUSED_EXPRESSION")
                gen
                drawIntoCanvas { canvas ->
                    val dstW = size.width.toInt()
                    val dstH = size.height.toInt()
                    if (bmp.width == dstW && bmp.height == dstH) {
                        canvas.nativeCanvas.drawBitmap(bmp, 0f, 0f, GLASS_BLIT_PAINT)
                    } else {
                        val dst = android.graphics.Rect(0, 0, dstW, dstH)
                        canvas.nativeCanvas.drawBitmap(bmp, null, dst, GLASS_BLIT_PAINT)
                    }
                }
            }
        }
    }
}

/** GPU path: TextureView is the EGL window; MediaCodec writes an OES SurfaceTexture. */
private class EffectsFeedListener(
    private val host: TextureView,
    private val session: LiveFeedEffectsSession,
    private val onUpdated: ((TextureView) -> Unit)?,
) : TextureView.SurfaceTextureListener {
    override fun onSurfaceTextureAvailable(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        session.attachDisplay(surfaceTexture, width, height)
    }

    override fun onSurfaceTextureSizeChanged(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        session.resize(width, height)
    }

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        session.detachDisplay()
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) {
        onUpdated?.invoke(host)
    }
}

/** Hands MediaCodec a TextureView surface without resetting the GOP on teardown. */
private class TextureFeedListener(
    private val host: TextureView,
    private val onSurface: (Surface) -> Unit,
    private val onUpdated: ((TextureView) -> Unit)?,
) : TextureView.SurfaceTextureListener {
    private var surface: Surface? = null

    override fun onSurfaceTextureAvailable(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        val next = Surface(surfaceTexture)
        surface?.release()
        surface = next
        onSurface(next)
    }

    override fun onSurfaceTextureSizeChanged(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) = Unit

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        surface?.release()
        surface = null
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) {
        onUpdated?.invoke(host)
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
    zoomReadout: Double,
    zoomPinching: Boolean,
    onTileFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
    onStatusChipFrame: (PocketDispSection, ChromeRect) -> Unit = { _, _ -> },
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
                Modifier
                    .liveModuleFrame(layout.topDeck)
                    .chromeEditStroke(
                        editing != null,
                        model.chrome(editing ?: model.currentDispMode).isVisible(PocketDispSection.STATUS_BAR),
                    ),
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
                    editing = editing,
                    onChipFrame = onStatusChipFrame,
                    onPickerFrame = onTileFrame,
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
                    OpcIcon(OpcIcon.SETTINGS, contentDescription = null, tint = it, modifier = Modifier.fillMaxSize())
                }
            }
        }
        if (showsMedia) {
            Box(Modifier.liveModuleFrame(layout.media).chromeEditStroke(editing != null, true)) {
                AuxCircleButton(onClick = { if (hits) model.liveOperatorPanel = LiveOperatorPanel.MEDIA }) {
                    OpcIcon(OpcIcon.LAYERS, contentDescription = null, tint = it, modifier = Modifier.fillMaxSize())
                }
            }
        }
        if (showsRecord) {
            Box(Modifier.liveModuleFrame(layout.record).chromeEditStroke(editing != null, true)) {
                RecordButton(
                    recording = status.isRecording,
                    enabled = !controlBusy,
                    confirm = model.recordConfirmationEnabled,
                    photo = CameraCommands.isPhotoMode(status.shootingMode),
                    onClick = model::pressShutter,
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
            val zoomBlocked =
                CamFov.zoomNeedsColorHopWhileRecording(
                    model.session.zoomNextJump(),
                    status.colorMode,
                    status.isRecording,
                )
            LiveZoomChip(
                factor = zoomReadout,
                locked = uiLocked,
                pinching = zoomPinching,
                dimmed = zoomBlocked,
                modifier =
                    Modifier
                        .liveModuleFrame(zoom)
                        .alpha(if (uiLocked || zoomBlocked) 0.4f else 1f)
                        .chromeEditStroke(editing != null, true),
                onCycle = {
                    model.session.setZoom(model.session.zoomNextJump())
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
        if (showsAssist || showsCapture) {
            val bandMinX = minOf(layout.assist.minX, layout.capture.minX)
            val band =
                ChromeRect(
                    bandMinX,
                    minOf(layout.assist.minY, layout.capture.minY),
                    maxOf(layout.assist.maxX, layout.capture.maxX) - bandMinX,
                    maxOf(layout.assist.height, layout.capture.height),
                )
            LiveBottomChromeBand(
                band = band,
                showAssist = showsAssist,
                showCapture = showsCapture,
                assist = {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .alpha(if (uiLocked) 0.4f else 1f)
                            .chromeEditStroke(editing != null, true),
                    ) {
                        LiveAssistBar(
                            state = assist,
                            locked = uiLocked || !hits,
                            onLongPress = onAssistLongPress,
                        )
                    }
                },
                capture = {
                    Box(
                        Modifier
                            .alpha(if (uiLocked) 0.4f else 1f)
                            .chromeEditStroke(editing != null, true),
                    ) {
                        LiveCaptureStrip(
                            status = status,
                            active = sheet,
                            enabled = !uiLocked && !controlBusy && hits,
                            showFocus =
                                CaptureLists.supportsFocusModeOrDefault(model.session.connectedCamera?.model),
                            facePriority = model.facePriorityExposureEnabled,
                            shutterUsesAngle = model.shutterUsesAngle,
                            onOpen = { onSheet(if (sheet == it) null else it) },
                            onTileFrame = onTileFrame,
                        )
                    }
                },
            )
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
    editing: PocketDispMode? = null,
    onChipFrame: (PocketDispSection, ChromeRect) -> Unit = { _, _ -> },
    onPickerFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
) {
    val family = model.session.connectedCamera?.model?.family ?: "pocket"
    fun chipMod(section: PocketDispSection, picker: LiveSheet? = null): Modifier {
        val visible = editing == null || model.chrome(editing).isVisible(section)
        return Modifier
            .then(if (editing != null) Modifier.graphicsLayer { alpha = if (visible) 1f else 0.3f } else Modifier)
            .chromeEditStroke(editing != null, visible)
            .reportChromeFrame { rect ->
                onChipFrame(section, rect)
                if (picker != null) onPickerFrame(picker, rect)
            }
    }
    FitScale(maxWidth.dp) {
    InfoPill {
        if (model.chromeSectionMounts(PocketDispSection.REC_READOUT)) {
            Box(chipMod(PocketDispSection.REC_READOUT)) { RecChip(status.isRecording) }
        }
        if (model.chromeSectionMounts(PocketDispSection.TIMECODE)) {
            Box(chipMod(PocketDispSection.TIMECODE)) { TimecodeReadout(status.timecode) }
        }
        if (model.chromeSectionMounts(PocketDispSection.FORMAT)) {
            ReadoutPill(
                CaptureLists.recFormatChipLabel(status),
                active = active == LiveSheet.FORMAT,
                enabled = enabled,
                onClick = { onOpen(LiveSheet.FORMAT) },
                accessibilityLabel = "Recording format",
                modifier = chipMod(PocketDispSection.FORMAT, LiveSheet.FORMAT),
            ) { VideoGlyph(it) }
        }
        if (model.chromeSectionMounts(PocketDispSection.COLOR)) {
            ReadoutPill(
                CameraCommands.colorLabel(status.colorMode, family),
                active = active == LiveSheet.COLOR,
                enabled = enabled,
                onClick = { onOpen(LiveSheet.COLOR) },
                accessibilityLabel = "Color mode",
                modifier = chipMod(PocketDispSection.COLOR, LiveSheet.COLOR),
            ) { ColorGlyph(it) }
        }
        if (model.chromeSectionMounts(PocketDispSection.STORAGE)) {
            ReadoutPill(
                CaptureLists.storageLabel(status, showStorageDuration),
                onClick = onToggleStorage,
                accessibilityLabel = "Storage remaining",
                modifier = chipMod(PocketDispSection.STORAGE),
            ) { SdCardGlyph(it) }
        }
        if (model.chromeSectionMounts(PocketDispSection.FPS)) {
            Box(chipMod(PocketDispSection.FPS)) { FpsChip(fps, bars) }
        }
    }
    }
}


