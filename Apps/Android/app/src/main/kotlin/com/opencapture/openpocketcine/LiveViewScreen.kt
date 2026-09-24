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
import com.opencapture.monitorui.monitorReadoutShadow
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.ime
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
import androidx.compose.ui.semantics.clearAndSetSemantics
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
import com.opencapture.monitorui.MonitorQuickGestureOwner
import com.opencapture.monitorui.monitorReadoutGesture
import com.opencapture.openpocketcine.session.LocalVPNFilter
import com.opencapture.openpocketcine.session.SessionRecoveryCopy
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import kotlinx.coroutines.delay
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.graphics.createBitmap
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
import com.opencapture.monitorui.LocalMonitorBackdrops
import com.opencapture.monitorui.monitorBackdropSource
import com.opencapture.openpocketcine.feed.MonitorBackdropFeed
import com.opencapture.openpocketcine.feed.rememberMonitorBackdropFeed
import com.opencapture.openpocketcine.feed.OpcVulkan
import com.opencapture.openpocketcine.feed.rememberLiveFeedEffectsPlan
import com.opencapture.openpocketcine.media.MediaLibraryScreen
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.session.CamFov
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.ControlHud
import com.opencapture.openpocketcine.session.FocusOverlay
import com.opencapture.openpocketcine.session.TrackingBox
import com.opencapture.openpocketcine.session.VideoResolution
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

@Composable
fun LiveViewScreen(model: AppModel) {
    val status by model.session.chromeStatus.collectAsState()
    val cameraGalleryOpen by model.session.cameraGalleryOpen.collectAsState()
    var followedGallery by remember { mutableStateOf(cameraGalleryOpen) }
    LaunchedEffect(cameraGalleryOpen) {
        if (cameraGalleryOpen == followedGallery) return@LaunchedEffect
        followedGallery = cameraGalleryOpen
        if (cameraGalleryOpen && model.liveOperatorPanel == null) {
            model.liveOperatorPanel = LiveOperatorPanel.MEDIA
        } else if (!cameraGalleryOpen && model.liveOperatorPanel == LiveOperatorPanel.MEDIA) {
            model.liveOperatorPanel = null
        }
    }
    val controlNote by model.session.controlNote.collectAsState()
    val controlBusy by model.session.controlBusy.collectAsState()
    val focusPoint by model.session.focusPoint.collectAsState()
    val zoomReadout by model.session.zoomReadout.collectAsState()
    val zoomDialReadout by model.session.zoomDialReadout.collectAsState()
    val zoomPinching by model.session.zoomPinching.collectAsState()
    val trackingHud by model.session.trackingHud.collectAsState()
    val poseViewFlip by model.session.gimbalPoseViewFlip.collectAsState()
    val poseInvertPan by model.session.gimbalPoseInvertPan.collectAsState()
    val gimbalLimitPulse by model.session.gimbalLimitPulse.collectAsState()
    val operatorHaptics = LocalOperatorHaptics.current
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
    val hasPicture by model.session.decoder.hasPicture.collectAsState()

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
    LaunchedEffect(status.shootingMode) {
        sheet = CaptureShutterPolicy.retainedSheet(sheet, status.shootingMode)
        if (!CaptureShutterPolicy.showsAudioControls(status.shootingMode) &&
            assist.configureTool == LiveAssistTool.AUDIO
        ) {
            assist.configureTool = null
        }
    }
    LaunchedEffect(
        sheet,
        model.session.connectedCamera?.model?.supportsFocusMode,
        model.session.connectedCamera?.model?.supportsAperture,
        model.session.connectedCamera?.model?.family,
        model.session.connectedCamera?.model?.name,
    ) {
        if (sheet == LiveSheet.FOCUS &&
            !CaptureLists.supportsFocusModeOrDefault(model.session.connectedCamera?.model)
        ) {
            sheet = null
        }
        if (sheet == LiveSheet.APERTURE && model.session.connectedCamera?.model?.supportsAperture != true) {
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

    LaunchedEffect(gimbalLimitPulse) {
        if (gimbalLimitPulse == 0) return@LaunchedEffect
        model.gimbalGamepad.pulseLimit(model, operatorHaptics)
    }
    LaunchedEffect(model.liveOperatorPanel, model.chromeEditorMode) {
        if (model.liveOperatorPanel != null || model.chromeEditorMode != null) {
            model.gimbalGamepad.noteBlocked(model)
        }
    }

    fun setLocked(value: Boolean) {
        uiLocked = value
        model.uiLocked = value
        if (value) {
            model.session.cancelProgrammedMove()
            model.gimbalGamepad.noteBlocked(model)
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

    val chromeInteractive = !model.isEditingChrome && model.liveChromeInteractive && model.liveOperatorPanel == null
    val showsBottomBars =
        model.chromeSectionMounts(PocketDispSection.TOOL_BAR) ||
            model.chromeSectionMounts(PocketDispSection.CAMERA_VALUES)
    val statusChipFrames = remember { mutableStateMapOf<PocketDispSection, ChromeRect>() }
    var fpsLabel by remember { mutableStateOf("—") }
    var bars by remember { mutableIntStateOf(0) }
    val fpsSampler = remember { FrameRateSampler() }
    val signalBars = remember { LinkSignalBars() }
    tick

    val glass = remember { MonitorGlass(GlassTier.FLAT) }
    val backdrop = rememberMonitorBackdropFeed(model.session.connectedCamera ?: model.session,
        enabled = model.liveOperatorPanel == null && hasPicture)

    var vulkanFailed by remember { mutableStateOf(false) }
    val vulkanSession =
        remember {
            if (OpcVulkan.isAvailable) {
                LiveVulkanSession(
                    context = context,
                    backdrop = backdrop,
                    onDecoderSurface = { model.session.attachSurface(it) },
                    onFirstFrame = { model.session.noteLiveFrame() },
                    onFailed = { vulkanFailed = true },
                    onFramePresented = { model.session.decoder.notePresented(it) },
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
    val scopeSourceIdentity = model.session.connectedCamera ?: model.session
    val scopeSourceActive = model.liveOperatorPanel != LiveOperatorPanel.MEDIA
    LaunchedEffect(vulkanSession, useVulkan, scopeSourceIdentity, hasPicture, scopeSourceActive) {
        vulkanSession?.configureScopeSource(scopeSourceIdentity, hasPicture, scopeSourceActive && useVulkan)
    }
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

    CompositionLocalProvider(LocalMonitorGlass provides glass, LocalMonitorBackdrops provides listOf(backdrop.source),
        com.opencapture.monitorui.LocalMonitorBackdropSurround provides if (useVulkan) Color.Black else LiveDesign.background) {
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(if (useVulkan) Color.Transparent else LiveDesign.background)
            .windowInsetsPadding(WindowInsets.navigationBars),
    ) {
        val density = LocalDensity.current
        val layoutDir = LocalLayoutDirection.current
        val cutout = WindowInsets.displayCutout
        val portrait = maxHeight > maxWidth
        val chromeScale =
            monitorChromeScale(LocalConfiguration.current.smallestScreenWidthDp.toFloat())
        LiveChromeMetrics.scale = chromeScale
        // Navigation is consumed by the outer viewport. Only cutouts and a
        // temporarily revealed status bar remain inside the live safe area.
        // Landscape leading is floored at the iPhone island lane so the 16:9
        // feed sits right of lock/battery (OpenZCine `monitorLeadingInsetDp`).
        // Trailing gets no floor; `feedFrame` yields a RAIL_W lane so the
        // record rail clears the picture.
        fun edgeDp(cutoutPx: Int, barPx: Int): Float =
            with(density) { maxOf(cutoutPx, barPx).toDp().value }
        val safeTop by animateFloatAsState(
            edgeDp(cutout.getTop(density), WindowInsets.systemBars.getTop(density)),
            label = "safeTop",
        )
        val safeBottom by animateFloatAsState(
            monitorBottomInsetDp(
                rawInsetDp = edgeDp(cutout.getBottom(density), 0),
                isPortrait = portrait && model.liveOperatorPanel == null,
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
                        transientBarDp = 0f,
                        chromeScale = chromeScale,
                    )
                }
            },
            label = "safeLeading",
        )
        val safeTrailing = with(density) { cutout.getRight(this, layoutDir).toDp().value }
        val vw = maxWidth.value
        val vh = maxHeight.value
        val desqueezeVisible = assist.isVisible(LiveAssistTool.DESQ)
        val fill = verticalPicture || (!desqueezeVisible && model.portraitFeedAspect == PortraitFeedAspect.FILL)
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
        val hasDisplayCutout = with(density) {
            cutout.getTop(this) > 0 || cutout.getBottom(this) > 0 ||
                cutout.getLeft(this, layoutDir) > 0 || cutout.getRight(this, layoutDir) > 0
        }
        val base =
            LiveMonitorLayout.fieldMonitor(
                viewportWidth = vw,
                viewportHeight = vh,
                safeLeading = safeLeading,
                safeTrailing = safeTrailing,
                safeTop = safeTop,
                safeBottom = safeBottom,
                showsBottomBars = showsBottomBars,
                chromeScale = chromeScale,
                pictureAspect = pictureAspect,
                hasDisplayCutout = hasDisplayCutout,
                fill = fill,
                showsValues = model.chromeSectionMounts(PocketDispSection.CAMERA_VALUES),
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
                base.copy(feed = well, picture = picture, usesFieldMonitor = true)
            } else {
                base
            }
        val topReadoutFrame = zones?.let { livePortraitReadoutFrame(layout, it) }
        // iOS fillCrop: landscape fill over-widens 16:9 to the well height
        // then clips (center crop). Vertical Pocket fill stays 9:16 pillars.
        val fillCrop = zones != null && fill && !verticalPicture
        val pictureContent =
            if (desqueezeVisible) layout.onFeed.fittedContent(assist.presentedAspect(pictureAspect))
            else if (fillCrop) portraitFillCropContent(layout.feed) else layout.onFeed
        var assistPaletteBounds by remember(vw, vh) { mutableStateOf<ChromeRect?>(null) }
        val showGimbalButton =
            model.monitorCapabilities(status).gimbal &&
                model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK)
        val cluster = layout.gimbalCluster(showGimbalButton)
        val zoom = cluster.zoom
        val stick = cluster.stick
        val gimbalButton = cluster.controls
        // Scopes may sit under the joystick/zoom cluster; it draws above them.
        // The main record/media/settings rail still reserves space.
        var scopeTop = layout.safeTop
        var scopeBottom = layout.viewportHeight
        var scopeLeft = layout.safeLeading
        var scopeRight = layout.viewportWidth - layout.safeTrailing
        if (portrait && zones != null) {
            // iOS scopes sit on the picture; exclude the camera-value strip so
            // HISTO / WAVE cannot cover ISO / shutter.
            scopeBottom =
                if (layout.capture.height > 1f) layout.capture.y else zones.systemBar.minY
            if (fill && model.chromeSectionMounts(PocketDispSection.TOOL_BAR)) {
                scopeLeft = maxOf(scopeLeft, layout.feed.minX + LivePortraitMetrics.ASSIST_RAIL_EDGE +
                    LivePortraitMetrics.ASSIST_RAIL_EXPANDED)
            }
        } else {
            scopeRight = minOf(scopeRight, layout.settings.minX - 6f)
        }
        if (!portrait && model.session.isFocusResetAvailable) scopeTop = maxOf(scopeTop, layout.focusReset.maxY)
        val scopePlacement = ChromeRect(scopeLeft, scopeTop, maxOf(0f, scopeRight - scopeLeft),
            maxOf(0f, minOf(scopeBottom, layout.viewportHeight) - scopeTop))
        val focusOffCenter = model.session.isFocusResetAvailable

        val effectsPlan =
            rememberLiveFeedEffectsPlan(
                assist = assist,
                lutSelection = model.lutSelection,
                status = status,
                family = model.session.connectedCamera?.model?.family.orEmpty(),
                cameraName = model.session.connectedCamera?.name,
            )
        var vulkanSurfaceView by remember { mutableStateOf<SurfaceView?>(null) }
        LaunchedEffect(vulkanSurfaceView, model.hdrDisplayActive) {
            val surface = vulkanSurfaceView ?: return@LaunchedEffect
            HdrDisplay.apply(surface, enabled = model.hdrDisplayActive)
        }
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
            pictureContent,
            desqueezeVisible,
            density.density,
            liveViewFlip,
        ) {
            val session = vulkanSession ?: return@LaunchedEffect
            if (!useVulkan) return@LaunchedEffect
            val picture = if (desqueezeVisible) pictureContent else layout.onFeed
            session.setFeedRect(
                with(density) { picture.x.dp.toPx() },
                with(density) { picture.y.dp.toPx() },
                with(density) { picture.width.dp.toPx() },
                with(density) { picture.height.dp.toPx() },
                stretchToRect = desqueezeVisible,
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
        val readoutRegions = remember { com.opencapture.monitorui.MonitorReadoutRegions() }
        CompositionLocalProvider(
            com.opencapture.monitorui.LocalMonitorReadoutRegions provides readoutRegions,
            LocalDensity provides Density(density.density, density.fontScale * chromeScale),
            LocalLiveCanvasOrigin provides canvasOrigin,
            LocalGpuLive provides if (useVulkan) vulkanSession else null,
        ) {
        Box(
            Modifier
                .fillMaxSize()
                .then(if (model.liveOperatorPanel != null) Modifier.clearAndSetSemantics { } else Modifier)
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
            }
            // The native image stays in its existing SurfaceView/TextureView.
            if (!useVulkan) {
            Box(
                Modifier
                    .liveModuleFrame(layout.onFeed)
                    .clipToBounds(),
            ) {
                LiveFeedPresenter(
                    mirrored = liveViewFlip,
                    stretchToRect = desqueezeVisible,
                    backdrop = backdrop,
                    sourceIdentity = model.session.connectedCamera ?: model.session,
                    sourceReady = hasPicture,
                    sourceActive = scopeSourceActive,
                    plan = effectsPlan,
                    onDecoderSurface = { model.session.attachSurface(it) },
                    onPresented = { model.session.noteLiveFrame() },
                    onSourcePresented = { model.session.decoder.notePresented(it) },
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

            // Passive source geometry; this box draws and captures nothing.
            Box(Modifier.liveModuleFrame(layout.onFeed).monitorBackdropSource(backdrop.source,
                imageRect = androidx.compose.ui.geometry.Rect(
                    (pictureContent.x - layout.onFeed.x) * density.density,
                    (pictureContent.y - layout.onFeed.y) * density.density,
                    (pictureContent.maxX - layout.onFeed.x) * density.density,
                    (pictureContent.maxY - layout.onFeed.y) * density.density), mirrored = liveViewFlip))

            // iOS `LiveZoomPinchWell` sits under chip + scopes so direct drag
            // on WAVE / PARADE / HISTO / VECTOR still reaches MovableAssistPanel.
            val gestureFrame = if (desqueezeVisible) pictureContent else layout.onFeed
            Box(Modifier.liveModuleFrame(gestureFrame)) {
                LiveFeedGestureWell(
                    enabled = !uiLocked && model.liveOperatorPanel == null && chromeInteractive,
                    feed = ChromeRect(0f, 0f, gestureFrame.width, gestureFrame.height),
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
                    feedFrame = if (desqueezeVisible) pictureContent else layout.onFeed.fittedContent(
                        VideoResolution.fromRaw(status.resolutionCode)?.ratio ?: pictureAspect),
                    framingFrame = if (desqueezeVisible) pictureContent.fittedContent(
                        assist.presentedAspect(VideoResolution.fromRaw(status.resolutionCode)?.ratio ?: pictureAspect)) else null,
                    placementFrame = scopePlacement,
                    audioPlacementFrame = scopePlacement.copy(x = layout.safeLeading,
                        width = maxOf(0f, scopePlacement.maxX - layout.safeLeading)),
                    pictureMirrored = liveViewFlip,
                    showsAudio = CaptureShutterPolicy.showsAudioControls(status.shootingMode),
                    onOpenOptions = { tool, frame ->
                        assist.longPressAnchor = frame
                        assist.configureTool = tool
                    },
                )
            }

            if (!hasPicture) {
                val context = LocalContext.current
                var showVpnHint by remember { mutableStateOf(false) }
                LaunchedEffect(hasPicture) {
                    showVpnHint = false
                    delay(LocalVPNFilter.LIVE_HINT_DELAY_MS)
                    showVpnHint =
                        LocalVPNFilter.shouldHintOnLiveWait(
                            vpnActive = LocalVPNFilter.isActive(context),
                            hadVideo = false,
                            secondsWithoutVideo = LocalVPNFilter.LIVE_HINT_DELAY_SECONDS,
                        )
                }
                Box(
                    Modifier.liveModuleFrame(layout.onFeed).background(Color.Black),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        CircularProgressIndicator(color = LiveDesign.text.copy(alpha = 0.72f))
                        Text(
                            "WAITING FOR LIVE VIEW",
                            color = LiveDesign.text.copy(alpha = 0.72f),
                            style = LiveType.mono(15f, FontWeight.SemiBold),
                        )
                        if (showVpnHint) {
                            Text(
                                LocalVPNFilter.LIVE_HINT,
                                color = LiveDesign.muted,
                                style = LiveType.ui(12f, design = LiveTypeDesign.Rounded),
                                textAlign = TextAlign.Center,
                                modifier = Modifier.padding(horizontal = 28.dp),
                            )
                        }
                    }
                }
            }

            // EV and LEVEL share the left-edge slot and its View Assist toolbar avoidance.
            val showsAssist = model.chromeSectionMounts(PocketDispSection.TOOL_BAR) &&
                model.liveOperatorPanel == null && assist.configureTool == null
            val collapsedPalette = if (!showsAssist) null else if (zones != null) {
                portraitAssistToolbar(zones.assistToolbar.minY, minOf(vw, vh) >= 600f)
            } else layout.assist
            val meterAvoid = if (showsAssist) assistPaletteBounds ?: collapsedPalette else null
            val meterFeed = if (desqueezeVisible) pictureContent else layout.onFeed
            val evShown = assist.evMeter && model.currentDispMode == PocketDispMode.LIVE
            if (evShown) {
                LiveCameraExposureMeter(
                    raw = status.meteredEv,
                    available = !recovery.isRecovering && !model.session.isFeedRecovering,
                    feed = meterFeed,
                    mode = model.currentDispMode,
                    avoid = meterAvoid,
                    modifier = Modifier.zIndex(1f),
                )
            }

            if (assist.isVisible(LiveAssistTool.LEVEL)) {
                LiveLevelOverlay(
                    reading = model.session.levelReading,
                    // Picture-relative like the stick: TT180 mirrors the shown picture in both Selfie Flip states.
                    viewFlip = CameraCommands.liveInvertPan(poseInvertPan, assist.mirror),
                    feed = meterFeed,
                    viewport = ChromeRect(0f, 0f, vw, vh),
                    portrait = portrait,
                    modifier = Modifier.zIndex(1f),
                )
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
                    readoutFrame = checkNotNull(topReadoutFrame),
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
                    sourceIsVertical = verticalPicture,
                    onAssistBoundsChanged = { assistPaletteBounds = it },
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
                    gimbalButton = gimbalButton,
                    focusOffCenter = focusOffCenter,
                    onFocusReset = { model.session.resetFocusPoint() },
                    zoomReadout = zoomReadout,
                    zoomDialReadout = zoomDialReadout,
                    zoomPinching = zoomPinching,
                    onStatusChipFrame = { section, rect -> statusChipFrames[section] = rect },
                    onAssistBoundsChanged = { assistPaletteBounds = it },
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

            if (chromeInteractive && sheet != null && !uiLocked) {
                LivePickerHost(
                    sheet = sheet!!,
                    viewportWidth = vw,
                    viewportHeight = vh,
                    safeLeading = safeLeading,
                    safeTrailing = safeTrailing,
                    safeTop = safeTop,
                    safeBottom = safeBottom,
                    floorY = zones?.systemBar?.minY,
                    model = model,
                    status = status,
                    locked = uiLocked,
                    onSelect = { sheet = it },
                    ceilingY = topReadoutFrame?.maxY,
                )
            }

            if (chromeInteractive &&
                showGimbalButton &&
                model.liveGimbalPanel == LiveGimbalPanel.SHEET &&
                !uiLocked
            ) {
                LiveGimbalSheetHost(
                    model = model,
                    layout = layout,
                    cluster = cluster,
                    safeLeading = safeLeading,
                    safeTrailing = safeTrailing,
                    safeTop = safeTop,
                    safeBottom = safeBottom,
                )
            }

            val configure = assist.configureTool
            if (chromeInteractive && configure != null && !uiLocked && model.liveOperatorPanel == null) {
                Box(Modifier.fillMaxSize().zIndex(8f)) {
                    com.opencapture.openpocketcine.assists.MonitorAssistInspector(
                        configure, assist, model, status.monitorColorMode, vw, vh,
                        safeLeading, safeTop, safeBottom,
                        if (layout.capture.height > 1f) layout.capture.y else zones?.systemBar?.minY ?: vh,
                        onDismiss = { assist.configureTool = null },
                        isPhoto = status.isPhoto,
                    )
                }
            }

            val panel = model.liveOperatorPanel
            LaunchedEffect(panel) {
                assist.configureTool = null
                model.session.setOperatorOverlayHeld(panel != null)
                if (panel == null) {
                    val ready = vulkanSession?.windowReady == true
                    DiagnosticCenter.log(
                        "info",
                        "feed",
                        "overlay",
                        "feed: overlay dismissed windowReady=${if (ready) 1 else 0} " +
                            "frames=${vulkanSession?.framesPresented?.get() ?: -1}",
                    )
                    vulkanSession?.redrawLast()
                } else {
                    DiagnosticCenter.log(
                        "info",
                        "feed",
                        "overlay",
                        "feed: overlay held $panel windowReady=${if (vulkanSession?.windowReady == true) 1 else 0}",
                    )
                }
            }
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
                        zoom = zoom,
                        stick = stick,
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
    val vulkan = LocalGpuLive.current
    LaunchedEffect(surfaceView, textureView, vulkan, enabled, feed.x, feed.y, feed.width, feed.height) {
        if (!enabled) return@LaunchedEffect
        val tapW = com.opencapture.openpocketcine.session.LiveFaceDetector.TAP_WIDTH
        while (isActive) {
            delay(com.opencapture.openpocketcine.session.LiveFaceDetector.INTERVAL_MS)
            if (!inFlight.compareAndSet(false, true)) continue
            // Vulkan: identity 720p RGB, same space as iOS Vision / 0xA6.
            // PixelCopy of the swapchain is already mirrored when TT180/MIRROR
            // is on, and the overlay mirrors again — box on the opposite side.
            val session = vulkan
            if (session != null) {
                session.requestFaceTap()
                val src = session.takeFaceBitmap()
                inFlight.set(false)
                if (src != null) latest.value(src)
                continue
            }
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
            val dest = createBitmap(tapW, tapH, Bitmap.Config.ARGB_8888)
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
                // API 34+ default destroys this surface when Settings / Media
                // cover it. Pocket has no periodic GOP — keep the surface while
                // the view stays attached (#248).
                if (Build.VERSION.SDK_INT >= 34) {
                    setSurfaceLifecycle(SurfaceView.SURFACE_LIFECYCLE_FOLLOWS_ATTACHMENT)
                }
                unsplitMotionEvents()
                onSurfaceView(this)
                holder.addCallback(
                    object : SurfaceHolder.Callback {
                        override fun surfaceCreated(holder: SurfaceHolder) {
                            DiagnosticCenter.log(
                                "info",
                                "feed",
                                "surface",
                                "feed: surface created",
                            )
                        }

                        override fun surfaceChanged(
                            holder: SurfaceHolder,
                            format: Int,
                            width: Int,
                            height: Int,
                        ) {
                            this@apply.unsplitMotionEvents()
                            DiagnosticCenter.log(
                                "info",
                                "feed",
                                "surface",
                                "feed: surface changed ${width}x${height}",
                            )
                            session.attachWindow(holder.surface, width, height)
                        }

                        override fun surfaceDestroyed(holder: SurfaceHolder) {
                            DiagnosticCenter.log(
                                "info",
                                "feed",
                                "surface",
                                "feed: surface destroyed",
                            )
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

/** GLES fallback; the same bounded raw tap supplies chrome after the native present. */
@Composable
private fun LiveFeedPresenter(
    mirrored: Boolean,
    stretchToRect: Boolean,
    backdrop: MonitorBackdropFeed,
    sourceIdentity: Any,
    sourceReady: Boolean,
    sourceActive: Boolean,
    plan: FeedEffectsRenderPlan,
    onDecoderSurface: (Surface) -> Unit,
    onPresented: () -> Unit = {},
    onSourcePresented: (Long) -> Unit = {},
    onTextureView: (TextureView?) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val attach = rememberUpdatedState(onDecoderSurface)
    val presented = rememberUpdatedState(onPresented)
    val sourcePresented = rememberUpdatedState(onSourcePresented)
    val textureViewOut = rememberUpdatedState(onTextureView)
    val context = LocalContext.current
    var gpuFailed by remember { mutableStateOf(false) }
    val session =
        remember {
            LiveFeedEffectsSession(
                context = context,
                backdrop = backdrop,
                onDecoderSurface = { attach.value(it) },
                onGpuFailed = { gpuFailed = true },
                onFirstFrame = { presented.value() },
                onFramePresented = { sourcePresented.value(it) },
            )
        }
    DisposableEffect(session) {
        onDispose {
            session.detachDisplay()
            textureViewOut.value(null)
        }
    }
    LaunchedEffect(sourceIdentity, sourceReady, sourceActive) {
        session.configurePreviewSource(sourceIdentity, sourceReady, sourceActive)
    }
    LaunchedEffect(plan) { session.updatePlan(plan) }
    LaunchedEffect(stretchToRect) { session.setStretchToRect(stretchToRect) }

    Box(modifier.graphicsLayer { scaleX = if (mirrored) -1f else 1f }) {
        key(gpuFailed) {
            AndroidView(
                factory = { viewContext ->
                    TextureView(viewContext).apply {
                        isOpaque = true
                        textureViewOut.value(this)
                        val onUpdated: (TextureView) -> Unit = { tv ->
                            if (gpuFailed) tv.surfaceTexture?.let { sourcePresented.value(it.timestamp) }
                            presented.value()
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
        DiagnosticCenter.log(
            "info",
            "feed",
            "surface",
            "feed: gles surface available ${width}x${height}",
        )
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
        DiagnosticCenter.log("info", "feed", "surface", "feed: gles surface destroyed")
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
internal fun LandscapeChrome(
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
    gimbalButton: ChromeRect,
    focusOffCenter: Boolean,
    onFocusReset: () -> Unit,
    zoomReadout: Double,
    zoomPinching: Boolean,
    zoomDialReadout: Double = zoomReadout,
    onTileFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
    onStatusChipFrame: (PocketDispSection, ChromeRect) -> Unit = { _, _ -> },
    capabilities: com.opencapture.monitorui.MonitorCapabilities = model.monitorCapabilities(status),
    onAssistBoundsChanged: (ChromeRect?) -> Unit = {},
) {
    var stripQuick by remember { mutableStateOf(false) }
    var topQuick by remember { mutableStateOf(false) }
    val captureOpen = sheet != null || stripQuick || topQuick
    val hidesCaptureValues = hidesLowerCaptureValues(sheet, stripQuick, topQuick)
    val editing = model.chromeEditorMode
    val showsStatus = model.chromeSectionMounts(PocketDispSection.STATUS_BAR)
    val showsLock = model.chromeSectionMounts(PocketDispSection.LOCK_BUTTON) || uiLocked
    val showsBatteries = model.chromeSectionMounts(PocketDispSection.BATTERIES)
    val showsSettings = !captureOpen && (model.chromeSectionMounts(PocketDispSection.RAIL_SETTINGS) || status.isRecording)
    // Media browsing is not adapted to shared Wi-Fi; a borrowed Multiview tile hides it.
    val showsMedia = !captureOpen && model.chromeSectionMounts(PocketDispSection.RAIL_MEDIA) &&
        !model.session.isMultiviewBorrowed
    val showsRecord = model.chromeSectionMounts(PocketDispSection.RAIL_RECORD) || status.isRecording
    val showsAssist = model.chromeSectionMounts(PocketDispSection.TOOL_BAR) &&
        model.liveOperatorPanel == null && assist.configureTool == null
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
                    onOpen = {
                        if (!uiLocked && hits) {
                            val next = CaptureShutterPolicy.opening(it, status.shootingMode)
                            onSheet(if (sheet == next) null else next)
                        }
                    },
                    maxWidth = layout.topDeck.width,
                    viewportWidth = layout.viewportWidth,
                    readoutTrailingInset = com.opencapture.monitorui.MonitorLayoutPolicy.recordingReadoutTrailingInset(
                        layout.topDeck.maxX, layout.picture.maxX),
                    showsTimecode = capabilities.timecode,
                    editing = editing,
                    onChipFrame = onStatusChipFrame,
                    onPickerFrame = onTileFrame,
                    onQuickActiveChange = {
                        topQuick = it
                        if (it) onSheet(null)
                    },
                )
            }
        }
        val multiviewExit = model.multiviewExit
        if (multiviewExit != null) {
            Box(Modifier.liveModuleFrame(layout.lock)) { MultiviewReturnButton(onClick = multiviewExit) }
        } else if (showsLock) {
            Box(Modifier.liveModuleFrame(layout.lock).chromeEditStroke(editing != null, true)) {
                LockButton(uiLocked, onClick = onLock)
            }
        }
        if (showsBatteries) {
            Box(Modifier.liveModuleFrame(layout.battery).chromeEditStroke(editing != null, true)) {
                com.opencapture.openpocketcine.monitor.MonitorTelemetry(bars, fpsLabel,
                    model.phoneBatteryPercent, status.batteryPercent, horizontal = false)
            }
        }
        if (showsSettings) {
            Box(Modifier.liveModuleFrame(layout.settings).chromeEditStroke(editing != null, true)) {
                AuxCircleButton(onClick = { if (hits) model.liveOperatorPanel = LiveOperatorPanel.SETTINGS }) {
                    OpcIcon(OpcIcon.SETTINGS, contentDescription = "Settings", tint = it, modifier = Modifier.fillMaxSize())
                }
            }
        }
        if (showsMedia) {
            Box(Modifier.liveModuleFrame(layout.media).chromeEditStroke(editing != null, true)) {
                AuxCircleButton(onClick = { if (hits) model.liveOperatorPanel = LiveOperatorPanel.MEDIA }) {
                    OpcIcon(OpcIcon.FILM, contentDescription = "Media", tint = it, modifier = Modifier.fillMaxSize())
                }
            }
        }
        if (showsRecord) {
            Box(Modifier.liveModuleFrame(layout.record).chromeEditStroke(editing != null, true)) {
                RecordButton(
                    recording = status.isRecording,
                    enabled = !controlBusy && !uiLocked,
                    diameter = layout.record.width,
                    confirm = CaptureShutterPolicy.requiresRecordConfirmation(
                        model.recordConfirmationEnabled, status.shootingMode,
                    ),
                    photo = CaptureShutterPolicy.isStillCapture(status.shootingMode),
                    request = CaptureShutterPolicy.request(
                        status.shootingMode, status.isRecording, uiLocked, controlBusy, model.session.phase,
                    ),
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
        if (!captureOpen && capabilities.zoom && model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP) && !zoom.isEmpty) {
            val zoomBlocked =
                CamFov.zoomNeedsColorHopWhileRecording(
                    model.session.zoomNextJump(),
                    status.colorMode,
                    status.isRecording,
                )
            LiveZoomChip(
                factor = zoomReadout,
                dialFactor = zoomDialReadout,
                locked = uiLocked,
                pinching = zoomPinching,
                dimmed = zoomBlocked,
                modifier =
                    Modifier
                        .liveModuleFrame(zoom)
                        .alpha(if (uiLocked || zoomBlocked) 0.4f else 1f)
                        .chromeEditStroke(editing != null, true),
                onCycle = {
                    model.session.setZoom(LiveZoom.nextJump(model.session.zoomCycleFrom(), model.monitorZoomStops().primary))
                },
                onDigitalCycle = model.monitorZoomStops().secondary.takeIf { it.isNotEmpty() }?.let { stops ->
                    { model.session.setZoom(LiveZoom.nextJump(model.session.zoomCycleFrom(), stops)) }
                },
                maximum = model.session.zoomMax(),
                opticalStops = if (3.0 in model.session.zoomStops()) listOf(1.0, 3.0) else listOf(1.0),
                onDial = model.session::updateZoomPinch,
                onDialEnd = model.session::endZoomPinch,
            )
        }
        if (!captureOpen && capabilities.gimbal &&
            model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK) &&
            !gimbalButton.isEmpty
        ) {
            LiveGimbalButton(
                locked = uiLocked,
                onClick = {
                    model.liveGimbalPanel =
                        if (model.liveGimbalPanel == LiveGimbalPanel.SHEET) LiveGimbalPanel.NONE
                        else LiveGimbalPanel.SHEET
                },
                modifier =
                    Modifier
                        .liveModuleFrame(gimbalButton)
                        .alpha(if (uiLocked) 0.4f else 1f),
            )
        }
        if (capabilities.gimbal && model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK) && !stick.isEmpty) {
            Box(Modifier.liveModuleFrame(stick).alpha(if (captureOpen) 0f else 1f).chromeEditStroke(editing != null, true)) {
                LiveGimbalStick(
                    enabled = !captureOpen && !uiLocked && model.liveOperatorPanel == null && hits,
                    onMove = model::updateGimbalStick,
                    onRelease = model::endGimbalStick,
                    onRecenter = { model.session.performGimbalDoubleTap() },
                    onFlip = { model.session.flipGimbal() },
                )
            }
        }
        if (!captureOpen && capabilities.gimbal &&
            model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK) &&
            hits &&
            !uiLocked &&
            model.liveOperatorPanel == null
        ) {
            LiveGimbalOverlay(
                model = model,
                layout = layout,
                feed = layout.onFeed,
                joystickBounds = stick,
                zoomBounds = if (capabilities.zoom && model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP)) zoom
                    else ChromeRect(0f, 0f, 0f, 0f),
                uiLocked = uiLocked,
            )
        }
        if (!uiLocked && focusOffCenter && hits) {
            Box(Modifier.liveModuleFrame(layout.focusReset)) {
                LiveFocusResetButton(onClick = onFocusReset)
            }
        }
        if (showsAssist) {
            Box(Modifier.liveModuleFrame(layout.assist).alpha(if (uiLocked) .4f else 1f)) {
                com.opencapture.openpocketcine.assists.MonitorAssistCluster(
                    portrait = false, locked = uiLocked || !hits,
                    isOn = assist::isOn, onToggle = { assist.toggle(it) }, onLongPress = onAssistLongPress,
                    showsAudio = CaptureShutterPolicy.showsAudioControls(status.shootingMode),
                    onBoundsChanged = onAssistBoundsChanged,
                )
            }
        }
        if (showsCapture) {
            Box(Modifier.liveModuleFrame(layout.capture, Alignment.BottomCenter)
                .alpha(if (hidesCaptureValues) 0f else if (uiLocked) .4f else 1f)
                .then(if (hidesCaptureValues) Modifier.clearAndSetSemantics { } else Modifier)) {
                LiveCaptureStrip(status, sheet, !uiLocked && !controlBusy && hits && (sheet == null || sheet.isTopAnchored), model = model,
                    portrait = false,
                    onQuickActiveChange = {
                        stripQuick = it
                        if (it) onSheet(null)
                    },
                    quickBottomClearanceDp = layout.safeBottom,
                    showFocus = capabilities.focus,
                    showAperture = capabilities.iris,
                    facePriority = model.facePriorityExposureEnabled, shutterUsesAngle = model.shutterUsesAngle,
                    onOpen = {
                        val next = CaptureShutterPolicy.opening(it, status.shootingMode)
                        onSheet(if (sheet == next) null else next)
                    }, onTileFrame = onTileFrame)
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
    viewportWidth: Float,
    readoutTrailingInset: Float,
    showsTimecode: Boolean = true,
    editing: PocketDispMode? = null,
    onChipFrame: (PocketDispSection, ChromeRect) -> Unit = { _, _ -> },
    onPickerFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
    onQuickActiveChange: (Boolean) -> Unit = {},
) {
    val config = LocalConfiguration.current
    val topFont = if (minOf(config.screenWidthDp, config.screenHeightDp) >= 600) 18f else 16f
    val family = model.session.connectedCamera?.model?.family ?: "pocket"
    val context = LocalContext.current
    val quickLifetime = rememberCaptureQuickLifetime(model)
    val gestureOwner = remember { MonitorQuickGestureOwner() }
    val interactive = enabled
    val notifyQuick by rememberUpdatedState(onQuickActiveChange)
    LaunchedEffect(gestureOwner.active) { notifyQuick(gestureOwner.active != null) }
    DisposableEffect(Unit) { onDispose { notifyQuick(false) } }
    @Composable
    fun Modifier.topCapture(sheet: LiveSheet): Modifier = monitorReadoutGesture(
        captureQuickControl(sheet, status, model, context, quickLifetime),
        interactive && quickLifetime.active && (gestureOwner.owner == null || gestureOwner.owner == sheet.name),
        { onOpen(CaptureShutterPolicy.opening(sheet, status.shootingMode)) },
        { source, value ->
            releaseCaptureQuickControl(sheet, source, value, model, context, quickLifetime, interactive)
        },
        0f,
        gestureOwner,
        sheet.name,
        { preview, maxHeight ->
            LiveControlSheet(sheet, model, status, locked = false,
                onDismiss = {}, maxHeightDp = maxHeight, preview = preview,
                portrait = false)
        },
        fromTop = true,
        onPreviewBegin = { notifyQuick(true) },
    )
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
    androidx.compose.foundation.layout.Row(
        Modifier.fillMaxWidth().monitorReadoutShadow(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        FlowRow(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(24.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (model.chromeSectionMounts(PocketDispSection.STORAGE)) {
            androidx.compose.foundation.layout.Row(
                chipMod(PocketDispSection.STORAGE).chromeClickable(onClick = onToggleStorage),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                SdCardGlyph(LiveDesign.text)
                Text(CaptureLists.storageLabel(status, showStorageDuration).substringBefore(" ·"),
                    style = LiveType.mono(topFont, FontWeight.SemiBold), maxLines = 1)
            }
        }
        if (model.chromeSectionMounts(PocketDispSection.FORMAT) &&
            !CameraCommands.isPhotoMode(status.shootingMode)
        ) {
            Text(CaptureLists.recFormatChipLabel(status), style = LiveType.mono(topFont, FontWeight.Medium), maxLines = 1,
                modifier = chipMod(PocketDispSection.FORMAT, LiveSheet.FORMAT).topCapture(LiveSheet.FORMAT))
        }
        if (model.chromeSectionMounts(PocketDispSection.COLOR) &&
            CaptureShutterPolicy.showsColorReadout(status.shootingMode)
        ) {
            Text(CameraCommands.colorLabel(status.colorMode, family), style = LiveType.ui(topFont, FontWeight.Medium), maxLines = 1,
                modifier = chipMod(PocketDispSection.COLOR, LiveSheet.COLOR).topCapture(LiveSheet.COLOR))
        }
        if (model.chromeSectionMounts(PocketDispSection.FORMAT)) {
            Text(CameraCommands.shootingModeLabel(status.shootingMode, model.session.connectedCamera?.model?.name) ?: "—",
                color = LiveDesign.accent, style = LiveType.ui(topFont, FontWeight.Medium), maxLines = 1,
                modifier = Modifier.reportChromeFrame { onPickerFrame(LiveSheet.MODE, it) }.topCapture(LiveSheet.MODE))
        }
        }
        androidx.compose.foundation.layout.Row(Modifier.padding(end = readoutTrailingInset.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically) {
        if (CaptureShutterPolicy.showsVideoTransport(status.shootingMode) &&
            model.chromeSectionMounts(PocketDispSection.REC_READOUT)
        ) {
            Box(chipMod(PocketDispSection.REC_READOUT)) { RecChip(status.isRecording, status.recordElapsedSec) }
        }
        if (CaptureShutterPolicy.showsVideoTransport(status.shootingMode) &&
            showsTimecode && model.chromeSectionMounts(PocketDispSection.TIMECODE)
        ) {
            Box(chipMod(PocketDispSection.TIMECODE)) { TimecodeReadout(status.timecode) }
        }
        }
    }
}
