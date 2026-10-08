package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.*

import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.appkit.MonitorInteractionContext
import com.opencapture.opencine.appkit.MonitorInteractionEffect
import com.opencapture.opencine.appkit.MonitorInputAdmission
import com.opencapture.opencine.appkit.MonitorInputBlock

import com.opencapture.opencine.appkit.monitorChromeEditStroke
import com.opencapture.opencine.appkit.MonitorChromeEditBadgeLayer
import com.opencapture.opencine.appkit.MonitorChromeEditBanner
import com.opencapture.opencine.appkit.monitorChromeEditBoxes
import com.opencapture.opencine.appkit.ObservePhoneBattery
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.LiveAutoExposureUnlockButton
import com.opencapture.opencine.cameracontrols.LiveChromeReadout
import com.opencapture.opencine.cameracontrols.LiveControlSheet
import com.opencapture.opencine.cameracontrols.LiveFeedGestureWell
import com.opencapture.opencine.cameracontrols.LiveFocusResetButton
import com.opencapture.opencine.cameracontrols.LiveGimbalButton
import com.opencapture.opencine.cameracontrols.LiveGimbalOverlay
import com.opencapture.opencine.cameracontrols.LiveGimbalPanel
import com.opencapture.opencine.cameracontrols.LiveGimbalSheetHost
import com.opencapture.opencine.cameracontrols.LiveGimbalStick
import com.opencapture.opencine.cameracontrols.LivePickerHost
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.cameracontrols.LiveViewLink
import com.opencapture.opencine.cameracontrols.LiveZoom
import com.opencapture.opencine.cameracontrols.LiveZoomChip
import com.opencapture.opencine.cameracontrols.LocalLiveCanvasOrigin
import com.opencapture.opencine.cameracontrols.SdCardGlyph
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.opencine.cameracontrols.hidesLowerCaptureValues
import com.opencapture.opencine.cameracontrols.isTopAnchored
import com.opencapture.opencine.cameracontrols.opening
import com.opencapture.opencine.cameracontrols.reportChromeFrame
import com.opencapture.opencine.cameracontrols.retainedSheet
import com.opencapture.opencine.platform.LocalVPNProbe
import com.opencapture.opencine.runtime.MonitorHDRDisplay
import com.opencapture.opencine.media.CameraLinkHealthInputs
import com.opencapture.opencine.media.CameraLinkHealthScorer
import com.opencapture.opencine.media.FrameRateSampler
import com.opencapture.opencine.media.LinkSignalBars
import com.opencapture.monitorui.portraitZones
import com.opencapture.monitorui.portraitAssistToolbar
import com.opencapture.monitorui.portraitFillCropContent
import com.opencapture.monitorui.livePortraitReadoutFrame
import com.opencapture.monitorui.LivePortraitMetrics
import com.opencapture.monitorui.monitorChromeScale
import com.opencapture.monitorui.monitorLeadingInsetDp
import com.opencapture.monitorui.monitorBottomInsetDp
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
import com.opencapture.opencine.appkit.statusPresentation
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
import com.opencapture.opencine.core.LocalVPNFilter
import com.opencapture.opencine.appkit.MonitorRecoveryOverlay
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import com.opencapture.opencine.vocabulary.CamFov
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureShutterPolicy
import com.opencapture.opencine.vocabulary.ControlHud
import com.opencapture.opencine.vocabulary.FocusOverlay
import com.opencapture.opencine.vocabulary.LiveFeedFocusGesture
import com.opencapture.opencine.vocabulary.SessionRecoveryCopy
import com.opencapture.opencine.vocabulary.SessionRecoveryUi
import com.opencapture.opencine.vocabulary.TrackingBox
import com.opencapture.opencine.vocabulary.VideoResolution
import kotlinx.coroutines.delay
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.graphics.createBitmap
import com.opencapture.openpocketcine.assists.AssistOptionsPopup
import com.opencapture.openpocketcine.assists.LiveAssistBar
import com.opencapture.openpocketcine.assists.LiveAssistLayer
import com.opencapture.opencine.appkit.MonitorAssistState
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.media.FeedPresentPolicy
import com.opencapture.openpocketcine.feed.GpuOverlayBus
import com.opencapture.openpocketcine.feed.LiveFeedEffectsSession
import com.opencapture.openpocketcine.feed.LiveVulkanSession
import com.opencapture.openpocketcine.feed.LocalGpuLive
import com.opencapture.monitorui.LocalMonitorBackdrops
import com.opencapture.monitorui.monitorBackdropSource
import com.opencapture.monitorui.portraitVerticalPicture
import com.opencapture.openpocketcine.feed.MonitorBackdropFeed
import com.opencapture.openpocketcine.feed.rememberMonitorBackdropFeed
import com.opencapture.openpocketcine.feed.OpcVulkan
import com.opencapture.openpocketcine.feed.appVulkanCrashGuard
import com.opencapture.openpocketcine.feed.rememberLiveFeedEffectsPlan
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.session.LiveFaceDetector
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt
import kotlinx.coroutines.isActive
import com.opencapture.opencine.cameracontrols.PortraitFeedAspect
import com.opencapture.opencine.runtime.InspectorPreviewPipeline
import com.opencapture.opencine.runtime.ScopeSampleBus
import com.opencapture.opencine.appkit.MonitorDisplaySection
import com.opencapture.monitorui.LiveChromeMetrics
import com.opencapture.monitorui.LiveMonitorLayout
import com.opencapture.opencine.appkit.MonitorDisplayMode
import com.opencapture.monitorui.MonitorRect

@Composable
fun LiveViewScreen(model: AppModel) {
    val cover = model.shellState.cover
    val status by model.session.chromeStatus.collectAsState()
    val capabilities = model.monitorLayout()
    val cameraGalleryOpen by model.session.cameraGalleryOpen.collectAsState()
    var followedGallery by remember { mutableStateOf(cameraGalleryOpen) }
    LaunchedEffect(cameraGalleryOpen) {
        if (cameraGalleryOpen == followedGallery) return@LaunchedEffect
        followedGallery = cameraGalleryOpen
        if (cameraGalleryOpen && model.shellState.cover == null) {
            model.shell.open(ShellModel.Cover.MEDIA)
        } else if (!cameraGalleryOpen && model.shellState.cover == ShellModel.Cover.MEDIA) {
            model.shell.dismissCover()
        }
    }
    val controlNote by model.session.controlNote.collectAsState()
    val controlBusy by model.session.controlBusy.collectAsState()
    val focusPoint by model.session.focusPoint.collectAsState()
    val trackingHud by model.session.trackingHud.collectAsState()
    val aeLock by model.session.aeLock.collectAsState()
    val poseViewFlip by model.session.gimbalPoseViewFlip.collectAsState()
    val poseInvertPan by model.session.gimbalPoseInvertPan.collectAsState()
    val gimbalLimitPulse by model.session.gimbalLimitPulse.collectAsState()
    val operatorHaptics = LocalOperatorHaptics.current
    var tick by remember { mutableIntStateOf(0) }
    val liveState = remember(model) { MonitorOperatorLiveState(model.uiLocked) }
    val context = LocalContext.current
    val assist = model.assist
    val wantedViewFlip = CameraCommands.liveViewFlip(poseViewFlip, assist.mirrorsHorizontally)
    // MIRROR Vertical has no pose latch, so it applies on the toggle.
    val flipV = assist.flipsVertically
    var liveViewFlip by remember { mutableStateOf(wantedViewFlip) }
    LaunchedEffect(wantedViewFlip) {
        if (liveViewFlip == wantedViewFlip) return@LaunchedEffect
        delay(FeedPresentPolicy.EXTRA_MIRROR_HOLD_MS)
        liveViewFlip = wantedViewFlip
    }


    val recovery by model.session.recoveryState.collectAsState()
    val verticalPicture by model.session.decoder.isVerticalPicture.collectAsState()
    val hasPicture by model.session.decoder.hasPicture.collectAsState()

    ObservePhoneBattery { model.applyPhoneBattery(it.percent ?: -1, it.externalPower == true) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            tick += 1
        }
    }

    LaunchedEffect(gimbalLimitPulse) {
        if (gimbalLimitPulse == 0) return@LaunchedEffect
        model.gimbalGamepad.pulseLimit(model, operatorHaptics)
    }

    var fpsLabel by remember { mutableStateOf("\u2014") }
    var bars by remember { mutableIntStateOf(0) }
    val fpsSampler = remember { FrameRateSampler() }
    val signalBars = remember { LinkSignalBars() }
    tick

    val glass = remember { MonitorGlass(GlassTier.FLAT) }
    val backdrop = rememberMonitorBackdropFeed(model.session.connectedCamera ?: model.session,
        enabled = model.shellState.cover == null && hasPicture)

    var vulkanFailed by remember { mutableStateOf(false) }
    val vulkanSession =
        remember {
            if (OpcVulkan.isAvailable && !appVulkanCrashGuard.isTripped(context)) {
                LiveVulkanSession(
                    context = context,
                    scopeBus = model.scopeBus,
                    preview = model.inspectorPreview,
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
    val scopeSourceActive = model.shellState.cover != ShellModel.Cover.MEDIA
    LaunchedEffect(vulkanSession, useVulkan, scopeSourceIdentity, hasPicture, scopeSourceActive) {
        vulkanSession?.configureScopeSource(scopeSourceIdentity, hasPicture, scopeSourceActive && useVulkan)
    }
    LaunchedEffect(model.session, useVulkan, vulkanSession) {
        var lastCount = 0
        var lastAt = 0L
        var held = "\u2014"
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
                isPortrait = portrait && model.shellState.cover == null,
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
        val pictureAspect = model.session.decoder.pictureAspect.toFloat()
        val desqueezeVisible = assist.isVisible(MonitorAssistTool.DESQ)
        val focusOffCenter = model.session.isFocusResetAvailable
        val geometry = monitorOperatorLiveLayout(
            MonitorOperatorViewport(vw, vh, safeLeading, safeTrailing, safeTop, safeBottom, chromeScale,
                with(density) { cutout.getTop(this) > 0 || cutout.getBottom(this) > 0 ||
                    cutout.getLeft(this, layoutDir) > 0 || cutout.getRight(this, layoutDir) > 0 }),
            assist, model::chromeSectionMounts, model.portraitFeedAspect, pictureAspect, verticalPicture,
            model.virtualJoystickSize, focusOffCenter)
        val layout = geometry.layout
        val pictureContent = geometry.pictureContent
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
            MonitorHDRDisplay.apply(surface, enabled = model.hdrDisplayActive)
        }
        var glesTextureView by remember { mutableStateOf<TextureView?>(null) }
        val wantsFaceDetect by model.session.wantsFaceDetect.collectAsState()

        var canvasOrigin by remember { mutableStateOf(Offset.Zero) }
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
            session.updateEffects(
                plan = effectsPlan,
                uiScale = density.density,
                pictureMirrored = liveViewFlip,
                pictureFlippedVertically = flipV,
            )
        }
        val readoutRegions = remember { com.opencapture.monitorui.MonitorReadoutRegions() }
        CompositionLocalProvider(
            com.opencapture.monitorui.LocalMonitorReadoutRegions provides readoutRegions,
            LocalDensity provides Density(density.density, density.fontScale * chromeScale),
            LocalLiveCanvasOrigin provides canvasOrigin,
            LocalGpuLive provides if (useVulkan) vulkanSession else null,
        ) {
        val metering: MonitorOperatorMeteringTile? = null
        val chrome = rememberOperatorChromeSource(model, status)
        val focus = MonitorOperatorFocusObservation(focusPoint, trackingHud, model.session.supportsTapFocus,
            aeLock != null, model.focusBoxLocked, focusOffCenter)
        val focusActions = MonitorOperatorFocusActions(
            { x, y -> model.session.handleFeedTap(x, y); Unit },
            { box -> model.session.startTracking(box); Unit }, model.session::lockAutoExposure,
            { model.session.canLockAutoExposure }, { model.session.unlockAutoExposure() },
            { model.focusBoxLocked = !model.focusBoxLocked; model.focusBoxLocked },
            model::resetFocusPoint, { model.session.cancelSubjectTracking() }, model.session::presentControlNote)
        MonitorOperatorLiveSurface(chrome,
            geometry, liveState,
            MonitorOperatorLivePresentation(status, capabilities, fpsLabel, bars,
                model.phoneBatteryPercent.takeIf { it >= 0 }, hasPicture, verticalPicture, liveViewFlip, flipV,
                recovery.isRecovering, controlBusy, controlNote, metering),
            assist, rememberOperatorAssistSource(model, status), focus, focusActions, model.session.levelReading,
            CameraCommands.liveInvertPan(poseInvertPan, assist.mirrorsHorizontally) != flipV,
            readExposure = { status.meteredEv },
            exposureAvailable = !recovery.isRecovering && !model.session.isFeedRecovering,
            vpnActive = { LocalVPNProbe.isActive(context) }, clearNote = model.session::clearControlNoteIf,
            lockedChanged = { model.uiLocked = it }, nativeInputBlocked = { reason ->
                model.gimbalGamepad.noteBlocked(model)
                model.endGimbalStick()
                if (reason == MonitorInputBlock.LOCK) model.session.cancelProgrammedMove()
            }, modifier = Modifier.onGloballyPositioned { if (!useVulkan) canvasOrigin = it.positionInRoot() },
            picture = {
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
                    scopeBus = model.scopeBus,
                    preview = model.inspectorPreview,
                    mirrored = liveViewFlip,
                    flippedVertically = flipV,
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
                    (pictureContent.maxY - layout.onFeed.y) * density.density), mirrored = liveViewFlip,
                flippedVertically = flipV))


            LiveFaceFramePump(surfaceView = vulkanSurfaceView, textureView = glesTextureView,
                feed = layout.onFeed, enabled = wantsFaceDetect && hasPicture,
                wantsFrame = model.session::wantsFaceFrame, onFrame = { model.session.considerFaceFrame(it) })
            })
        Box(Modifier.fillMaxSize().zIndex(20f)) {
            val panel = model.shellState.cover
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


                    }
        Box(Modifier.fillMaxSize().zIndex(30f)) {
            if (recovery.isRecovering) {
                MonitorRecoveryOverlay(
                    retrying = recovery is SessionRecoveryUi.Retrying,
                    title = SessionRecoveryCopy.title(recovery),
                    detail = SessionRecoveryCopy.detail(recovery, model.session.connectedCamera?.name.orEmpty()),
                    retryTitle = SessionRecoveryCopy.RETRY_CONNECTION,
                    operatorMenuTitle = SessionRecoveryCopy.OPERATOR_MENU,
                    onRetry = { model.session.retrySessionRecovery() },
                    onOperatorMenu = { model.disconnect() },
                )
            }
        }

    }
    }
}
}

@Composable
private fun LiveFaceFramePump(
    surfaceView: SurfaceView?,
    textureView: TextureView?,
    feed: MonitorRect,
    enabled: Boolean,
    wantsFrame: () -> Boolean,
    onFrame: (LiveFaceDetector.Frame) -> Unit,
) {
    val density = LocalDensity.current
    val handler = remember { Handler(Looper.getMainLooper()) }
    val inFlight = remember { AtomicBoolean(false) }
    val latest = rememberUpdatedState(onFrame)
    val wanted = rememberUpdatedState(wantsFrame)
    val vulkan = LocalGpuLive.current
    LaunchedEffect(surfaceView, textureView, vulkan, enabled, feed.x, feed.y, feed.width, feed.height) {
        if (!enabled) return@LaunchedEffect
        val tapW = LiveFaceDetector.TAP_WIDTH
        while (isActive) {
            delay(LiveFaceDetector.INTERVAL_MS)
            // Vulkan: identity 720p RGB, same space as iOS Vision / 0xA6.
            // PixelCopy of the swapchain is already mirrored when TT180/MIRROR
            // is on, and the overlay mirrors again - box on the opposite side.
            val session = vulkan
            if (session != null) {
                // Take a fresh readback first, then ask for the next only when the
                // detector will use it (10 Hz idle pace skips the GPU readback too).
                session.takeFaceNv21()?.let {
                    latest.value(LiveFaceDetector.Frame.nv21(it, LiveFaceDetector.TAP_WIDTH, LiveFaceDetector.TAP_HEIGHT))
                }
                if (wanted.value()) session.requestFaceTap()
                continue
            }
            if (!wanted.value() || !inFlight.compareAndSet(false, true)) continue
            val tapH =
                ((tapW * feed.height / feed.width.coerceAtLeast(1f)).toInt() and 1.inv())
                    .coerceAtLeast(16)
            val gles = textureView
            if (gles != null && gles.isAvailable) {
                val src = gles.getBitmap(tapW, tapH)
                inFlight.set(false)
                if (src != null) latest.value(LiveFaceDetector.Frame.of(src))
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
                            latest.value(LiveFaceDetector.Frame.of(dest))
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
                // cover it. Pocket has no periodic GOP - keep the surface while
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

/** Keep both pinch fingers on one view - Android otherwise splits pointer 2 onto SurfaceView. */
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
    scopeBus: com.opencapture.opencine.runtime.ScopeSampleBus,
    preview: com.opencapture.opencine.runtime.InspectorPreviewPipeline,
    mirrored: Boolean,
    flippedVertically: Boolean,
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
                scopeBus = scopeBus,
                preview = preview,
                backdrop = backdrop,
                onDecoderSurface = { attach.value(it) },
                onGpuFailed = { gpuFailed = true },
                onFirstFrame = { presented.value() },
                onFramePresented = { sourcePresented.value(it) },
            )
        }
    DisposableEffect(session) {
        onDispose {
            session.close()
            textureViewOut.value(null)
        }
    }
    LaunchedEffect(sourceIdentity, sourceReady, sourceActive) {
        session.configurePreviewSource(sourceIdentity, sourceReady, sourceActive)
    }
    LaunchedEffect(plan) { session.updatePlan(plan) }
    LaunchedEffect(stretchToRect) { session.setStretchToRect(stretchToRect) }

    Box(modifier.graphicsLayer {
        scaleX = if (mirrored) -1f else 1f
        scaleY = if (flippedVertically) -1f else 1f
    }) {
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
