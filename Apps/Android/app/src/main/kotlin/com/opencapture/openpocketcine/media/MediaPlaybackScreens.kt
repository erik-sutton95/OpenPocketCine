@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.media

import com.opencapture.openpocketcine.feed.colorMode
import com.opencapture.monitorui.detectMonitorPlaybackVideoGestures as detectPlaybackVideoGestures
import com.opencapture.monitorui.monitorPlaybackUnitPoint as unitPoint

import com.opencapture.monitorui.LocalMonitorBackdrops
import com.opencapture.monitorui.monitorBackdropSource
import com.opencapture.openpocketcine.feed.rememberMonitorBackdropFeed
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.media.MonitorPlaybackLookTiming
import com.opencapture.monitorui.MonitorPlaybackPresentation
import com.opencapture.monitorui.MonitorPlaybackActions
import com.opencapture.monitorui.MonitorPlaybackScreen
import com.opencapture.monitorui.MonitorEditingCancellation
import com.opencapture.monitorui.MonitorLayoutPolicy
import com.opencapture.monitorui.MonitorPlaybackLayout
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.ChromeRect
import com.opencapture.openpocketcine.GlassTier
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.liveModuleFrame
import com.opencapture.openpocketcine.monitorBottomInsetDp
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.openpocketcine.LocalOperatorHaptics
import com.opencapture.openpocketcine.MonitorGlass
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.assists.AssistOptionsPopup
import com.opencapture.openpocketcine.assists.AudioAssist
import com.opencapture.openpocketcine.assists.AssistAudioOverlay
import com.opencapture.openpocketcine.assists.AssistRect
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistLayer
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.assists.MirrorAssist
import com.opencapture.openpocketcine.assists.PlaybackAssistBar
import com.opencapture.openpocketcine.assists.scopePanelChrome
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.feed.rememberLiveFeedEffectsPlan
import com.opencapture.openpocketcine.lut.PlaybackLutColor
import com.opencapture.opencine.dji.CameraStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@Composable
fun MediaPhotoViewer(
    model: AppModel,
    file: MediaFile,
    controller: MediaLibraryController,
    onClose: () -> Unit,
    onDeliver: (MediaFile) -> Unit = {},
) {
    val scope = rememberCoroutineScope()
    val assist = model.assist
    var showDesqueezeOptions by remember { mutableStateOf(false) }
    var bitmap by remember(file.id) { mutableStateOf<Bitmap?>(null) }
    var loading by remember { mutableStateOf(true) }
    var zoom by remember(file.id) { mutableStateOf(AnchoredPinchZoom()) }
    var confirmDelete by remember { mutableStateOf(false) }
    val photoDensity = LocalDensity.current
    val photoLayoutDir = LocalLayoutDirection.current
    val photoSafeLeading = with(photoDensity) {
        WindowInsets.displayCutout.getLeft(this, photoLayoutDir).toDp().value
    }
    val photoSafeTrailing = with(photoDensity) {
        WindowInsets.displayCutout.getRight(this, photoLayoutDir).toDp().value
    }
    val photoSafeTop = with(photoDensity) {
        WindowInsets.displayCutout.getTop(this).toDp().value
    }
    val favorite = controller.isFavorite(file)
    val glass = rememberPlaybackMonitorGlass()

    BackHandler {
        when {
            showDesqueezeOptions -> showDesqueezeOptions = false
            confirmDelete -> confirmDelete = false
            else -> onClose()
        }
    }

    LaunchedEffect(file.id) {
        loading = true
        zoom = AnchoredPinchZoom()
        bitmap =
            withContext(Dispatchers.IO) {
                val cached = controller.localFile(file) ?: controller.thumbnailFile(file)
                cached?.let { BitmapFactory.decodeFile(it.absolutePath) }
                    ?: run {
                        val play = controller.cacheForPlayback(file)
                        play?.let { BitmapFactory.decodeFile(it.absolutePath) }
                    }
            }
        loading = false
    }

    val backdrop = rememberPhotoBackdrop(bitmap, file.id)
    CompositionLocalProvider(LocalMonitorGlass provides glass, LocalMonitorBackdrops provides listOf(backdrop),
        com.opencapture.monitorui.LocalMonitorBackdropSurround provides LiveDesign.feedWell) {
    Box(Modifier.fillMaxSize().background(LiveDesign.feedWell)) {
        val image = bitmap
        if (image != null) {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val widthPx = constraints.maxWidth.toFloat()
                val heightPx = constraints.maxHeight.toFloat()
                val fitted = PlaybackVideoLayout.aspectFitRect(
                    PlaybackVideoLayout.Size(assist.presentedAspect(image.width.toFloat() / image.height, playback = true), 1f),
                    PlaybackVideoLayout.Rect(0f, 0f, widthPx, heightPx),
                )
                LaunchedEffect(fitted.width, fitted.height) { zoom = zoom.endGesture(fitted.width, fitted.height) }
                val imageW = fitted.width * zoom.scale
                val imageH = fitted.height * zoom.scale
                val left = (widthPx - imageW) / 2f + zoom.offsetX
                val top = (heightPx - imageH) / 2f + zoom.offsetY
                Box(Modifier.fillMaxSize().monitorBackdropSource(backdrop,
                    imageRect = androidx.compose.ui.geometry.Rect(left, top, left + imageW, top + imageH)))
                Box(Modifier.offset { IntOffset(fitted.x.roundToInt(), fitted.y.roundToInt()) }
                    .size(with(photoDensity) { fitted.width.toDp() }, with(photoDensity) { fitted.height.toDp() })
                    .clipToBounds()
                    .pointerInput(file.id, fitted.width, fitted.height) {
                        detectPlaybackVideoGestures(
                            isReady = { true }, isZoomed = { zoom.isZoomed },
                            config = PlaybackGestureConfig(enableTap = false, enableScrub = false, enableSwipe = false),
                            onTap = {}, onChromeSwipe = {}, onScrubStart = {}, onScrubDelta = {}, onScrubEnd = {},
                            onPinch = { magnification, centroid ->
                                val anchor = unitPoint(centroid, fitted.width, fitted.height)
                                zoom = zoom.pinchChanged(magnification, anchor.first, anchor.second, fitted.width, fitted.height)
                            },
                            onPinchEnd = { zoom = zoom.endGesture(fitted.width, fitted.height) },
                            onPan = { zoom = zoom.panChanged(it.x, it.y) },
                            onPanEnd = { zoom = zoom.endGesture(fitted.width, fitted.height) },
                        )
                    }) {
                    Image(image.asImageBitmap(), contentDescription = file.filename, contentScale = ContentScale.FillBounds,
                        modifier = Modifier.fillMaxSize().graphicsLayer {
                            scaleX = zoom.scale
                            scaleY = zoom.scale
                            translationX = zoom.offsetX
                            translationY = zoom.offsetY
                        })
                }
            }
        } else if (loading) {
            Column(
                Modifier
                    .align(Alignment.Center)
                    .clip(MediaCornerShape)
                    .mediaGlass(MediaCornerShape)
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator(color = LiveDesign.accent)
                Text("Preparing image…", color = LiveDesign.muted, style = LiveType.ui(14f, FontWeight.Medium))
            }
        }

        if (PlaybackChromeMetrics.usesDarkenedBars(glass.tier)) {
            PlaybackDarkenedBars()
        }

        Column(
            Modifier
                .fillMaxSize()
                .navigationBarsPadding()
                .padding(
                    start = (photoSafeLeading + MonitorPlaybackLayout.PHOTO_HEADER_HORIZONTAL).dp,
                    end = (photoSafeTrailing + MonitorPlaybackLayout.PHOTO_HEADER_HORIZONTAL).dp,
                ),
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(top = (photoSafeTop + MonitorPlaybackLayout.PHOTO_HEADER_TOP_EXTRA).dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                MediaCircleIconButton(OpcIcon.X, "Back to media", onClose)
                Text(
                    file.filename,
                    color = LiveDesign.text,
                    style = LiveType.ui(14f, FontWeight.SemiBold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (controller.canDelete(file)) {
                    MediaCircleIconButton(OpcIcon.TRASH, "Delete photo", { confirmDelete = true })
                }
                MediaCircleIconButton(OpcIcon.SHARE, "Share photo", { onDeliver(file) })
            }
            Spacer(Modifier.weight(1f))
            Box(
                Modifier
                    .fillMaxWidth()
                    .padding(bottom = MonitorPlaybackLayout.PHOTO_FAVORITE_BOTTOM.dp),
                contentAlignment = Alignment.Center,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    com.opencapture.openpocketcine.assists.AssistToolCell(
                        tool = LiveAssistTool.DESQ,
                        isOn = assist.isPlaybackVisible(LiveAssistTool.DESQ), enabled = true,
                        onClick = { assist.togglePlayback(LiveAssistTool.DESQ) },
                        onLongClick = { showDesqueezeOptions = true },
                    )
                    MediaCircleIconButton(
                        OpcIcon.STAR,
                        if (favorite) "Remove from favorites" else "Add to favorites",
                        { controller.toggleFavorite(file) },
                        filled = favorite,
                        tint = if (favorite) LiveDesign.accent else LiveDesign.text,
                    )
                }
            }
        }

        if (showDesqueezeOptions) {
            Popup(alignment = Alignment.Center, onDismissRequest = { showDesqueezeOptions = false },
                properties = PopupProperties(focusable = true)) {
                val popupWindow = androidx.compose.ui.platform.LocalWindowInfo.current.containerSize
                AssistOptionsPopup(LiveAssistTool.DESQ, assist, onDismiss = { showDesqueezeOptions = false },
                    playback = true,
                    maxHeightDp = with(photoDensity) { popupWindow.height.toDp().value * 0.8f })
            }
        }

        if (confirmDelete) {
            MediaConfirmPopup(
                title = "Delete this photo from the camera?",
                confirmTitle = "Delete",
                onDismiss = { confirmDelete = false },
                onConfirm = {
                    confirmDelete = false
                    scope.launch {
                        controller.delete(file)
                        onClose()
                    }
                },
            )
        }
    }
    }
}

@Composable
fun MediaPlayerScreen(
    files: List<MediaFile>,
    startingAt: MediaFile,
    controller: MediaLibraryController,
    model: AppModel,
    onClose: () -> Unit,
    onDeliver: (MediaFile) -> Unit = {},
) {
    val assist = model.assist
    val haptics = LocalOperatorHaptics.current
    var active by remember { mutableStateOf(startingAt) }
    val playlist = if (files.any { it.id == active.id }) files else listOf(active)
    var meterLeft by remember { mutableStateOf(AudioMeterChannel.Silent) }
    var meterRight by remember { mutableStateOf(AudioMeterChannel.Silent) }
    val libraryState by controller.library.state.collectAsState()
    val activeRecord = controller.record(active)
    val favorite = activeRecord?.favorite ?: active.isStarred
    val progress = controller.downloadProgress[active.path]
    val audioMetersOn = assist.isPlaybackVisible(LiveAssistTool.AUDIO)
    val glass = remember { MonitorGlass(GlassTier.FLAT) }

    val context = LocalContext.current
    var composition by remember(controller) { mutableStateOf(PocketAndroidPlaybackOwner(context, controller)) }
    val capturedComposition = composition
    val scope = capturedComposition.scope
    val native = capturedComposition.native
    val playback = capturedComposition.playback
    val meterBox = capturedComposition.meterBox
    val meterSampler = capturedComposition.meterSampler
    val playbackState by playback.state.collectAsState()
    val canPrev = playback.canGoPrevious
    val canNext = playback.canGoNext
    val player = native.player
    val isPlaying = (playbackState.reportedPlaying ?: playbackState.playRequested) && !playbackState.scrubbing
    val isMuted = playbackState.muted
    val scrubbing = playbackState.scrubbing
    val currentTime = (if (scrubbing) playbackState.scrubPosition else playbackState.position).toFloat()
    val duration = (playbackState.duration ?: active.durationSeconds.toDouble()).toFloat()
    val reachedEnd = playbackState.reachedEnd
    val ready = playbackState.ready
    val loadError = playbackState.error ?: if (playbackState.closed) MediaOperatorCopy.CLIP_NOT_CACHED else null
    val looping = playbackState.looping
    val conformSource = playbackState.metadata.conform
    val conformTarget = playbackState.conformTarget
    val conformSpeed = playback.rate
    val listed = PlaybackVideoLayout.sizeFromResolution(active.resolution)
    val videoWidth = playbackState.metadata.width?.toFloat() ?: listed?.width ?: 16f
    val videoHeight = playbackState.metadata.height?.toFloat() ?: listed?.height ?: 9f
    val decodeWidth = player.videoSize.width.takeIf { it > 1 } ?: 1280
    val decodeHeight = player.videoSize.height.takeIf { it > 1 } ?: 720
    val clipColorMode = playbackState.look?.source?.colorMode ?: -1
    val playbackSource = when (playbackState.item?.role) {
        com.opencapture.opencine.media.MediaRepresentationRole.PROXY -> "PROXY"
        com.opencapture.opencine.media.MediaRepresentationRole.ORIGINAL -> "ORIGINAL"
        null -> ""
    }

    val backdrop = rememberMonitorBackdropFeed(active.id, enabled = ready)
    val status by model.session.chromeStatus.collectAsState()
    val effectsPlan =
        rememberLiveFeedEffectsPlan(
            assist = assist,
            lutSelection = model.lutSelection,
            status = status,
            family = model.session.connectedCamera?.model?.family.orEmpty(),
            cameraName = model.session.connectedCamera?.name,
            playback = true,
            clipColorMode = clipColorMode,
        )

    fun conformedLabel(seconds: Float): String =
        MediaClipFormatting.durationLabel(ConformPreview.conformedDuration(seconds.toDouble(), conformSpeed))

    DisposableEffect(capturedComposition) {
        onDispose {
            assist.configureTool = null
            capturedComposition.close()
        }
    }
    LaunchedEffect(playback, activeRecord?.asset?.id) {
        assist.configureTool = null
        meterBox.readAndReset()
        controller.record(active)?.let { record ->
            if (playback.state.value.active?.asset?.id != record.asset.id) playback.load(record, playlist.mapNotNull(controller::record))
        } ?: playback.close()
    }
    LaunchedEffect(playbackState.token, playbackState.nativeItemInstalled) {
        if (playback.isActive && playbackState.nativeItemInstalled && playback.state.value.token == playbackState.token &&
            playbackState.active?.asset?.id == activeRecord?.asset?.id &&
            model.cacheFullResolution && controller.isLive && !controller.isDownloaded(active)) controller.download(active)
    }
    LaunchedEffect(progress, active.id) {
        if (progress != null && progress >= 1f && controller.isDownloaded(active)) playback.refreshTransfer()
    }

    LaunchedEffect(playbackState.token, playbackState.look) {
        val look = playbackState.look ?: return@LaunchedEffect
        if (playback.isActive && playback.state.value.token == playbackState.token && playback.state.value.look == look) Unit
    }

    LaunchedEffect(composition, audioMetersOn, conformTarget != null) {
        meterSampler.reset()
        if (!audioMetersOn) {
            meterLeft = AudioMeterChannel.Silent
            meterRight = AudioMeterChannel.Silent
            meterBox.readAndReset()
            return@LaunchedEffect
        }
        var last = System.nanoTime()
        val conforming = conformTarget != null
        if (conforming) {
            meterBox.readAndReset()
            meterLeft = AudioMeterChannel.Silent
            meterRight = AudioMeterChannel.Silent
        }
        while (true) {
            delay(42)
            val now = System.nanoTime()
            val dt = (now - last) / 1_000_000_000.0
            last = now
            val levels = meterSampler.step(dt, outputMuted = conformTarget != null) ?: AudioMeterLevels.Silent
            meterLeft = levels.left
            meterRight = levels.right
        }
    }

    fun withCurrentItem(token: com.opencapture.opencine.media.MonitorPlaybackItemToken, action: () -> Unit) {
        if (playback.isActive && playback.state.value.token == token) action()
    }
    fun goToAdjacent(offset: Int) {
        if (if (offset < 0) !playback.canGoPrevious else !playback.canGoNext) return
        playback.setPresentationActive(false); playback.goToAdjacent(offset)
        active = playback.state.value.active?.payload ?: return
        playback.setPresentationActive(true)
    }
    val metadata = buildList {
        fun row(label: String, value: String?) { if (!value.isNullOrBlank()) add(com.opencapture.monitorui.MonitorMetadataRow(label, value)) }
        row("File", active.filename); row("Format", active.fileExtension); row("Resolution", active.resolution)
        row("Frame rate", active.fps?.let { "${it} fps" }); row("Duration", conformedLabel(duration))
        row("Playback source", playbackSource)
        row("Size", active.sizeBytes.takeIf { it > 0 }?.let { android.text.format.Formatter.formatShortFileSize(context, it) })
        row("Created", active.filenameTimestamp?.let { "${it.take(4)}-${it.substring(4,6)}-${it.substring(6,8)} ${it.substring(8,10)}:${it.substring(10,12)}:${it.substring(12,14)}" })
        row("Favorite", if (favorite) "Yes" else "No")
    }
    val presentation = MonitorPlaybackPresentation(playbackState.token, active.filename,
        listOfNotNull(active.resolution, active.fps?.let { "${it}p" }, active.fileExtension).joinToString(" · "),
        playbackSource.takeIf(String::isNotBlank), metadata,
        assist.presentedAspect(videoWidth / videoHeight, playback = true), ready, loadError,
        progress?.toDouble(), currentTime, duration, conformedLabel(currentTime), conformedLabel(duration),
        isPlaying, reachedEnd, scrubbing, isMuted, looping, canPrev, canNext, favorite, conformSource, conformTarget)
    val actions = MonitorPlaybackActions(back = onClose,
        play = { token, play -> withCurrentItem(token) { playback.setPlaying(play) } },
        restart = { token -> withCurrentItem(token) { playback.restart() } },
        seekBy = { token, delta -> withCurrentItem(token) { playback.seekBy(delta) } },
        mute = { token, muted -> withCurrentItem(token) { playback.setMuted(muted) } },
        loop = { token, loop -> withCurrentItem(token) { playback.setLooping(loop) } },
        conform = { token, target -> withCurrentItem(token) { playback.setConformTarget(target) } },
        adjacent = { token, offset -> withCurrentItem(token) { goToAdjacent(offset) } },
        favorite = { token -> withCurrentItem(token) { controller.toggleFavorite(active) } },
        share = { token -> withCurrentItem(token) { playback.setPlaying(false); onDeliver(active) } },
        delete = if (controller.canDelete(active)) { token ->
            val dying = active
            val lease = controller.library.state.value.lifetimeToken
            val candidates = playback.state.value.playlist
            val index = candidates.indexOfFirst { it.asset.id == playback.state.value.active?.asset?.id }
            val adjacent = candidates.getOrNull(index + 1) ?: candidates.getOrNull(index - 1)
            scope.launch {
                if (!playback.isActive || playback.state.value.token != token) return@launch
                val removed = controller.delete(dying)
                val captured = candidates.getOrNull(index)?.asset?.id ?: return@launch
                if (!mayAdvancePocketPlaybackAfterRemoval(removed, captured, token, playback.state.value,
                    sameComposition = composition === capturedComposition,
                    sameGallery = controller.library.state.value.lifetimeToken == lease,
                    sameContent = com.opencapture.opencine.dji.DjiAndroidMediaAssets.asset(active).id == captured) ||
                    controller.record(dying) != null) return@launch
                // Deleting the captured content retires that native owner. Recompose a new owner
                // for the next real row; an unrelated current page is never advanced by this result.
                if (adjacent != null && controller.library.record(adjacent.asset.id) != null) {
                    composition = PocketAndroidPlaybackOwner(context, controller,
                        muted = playback.state.value.muted, looping = playback.state.value.looping)
                    active = adjacent.payload
                } else onClose()
            }
        } else null,
        beginScrub = { token -> if (playback.isActive && playback.state.value.token == token) playback.beginScrub() else null },
        updateScrub = { edit, time -> playback.updateScrub(time, edit) },
        updateFrameScrub = { edit, delta, width -> playback.updateFrameScrub(delta, width, edit) },
        commitScrub = playback::commitScrub,
        cancelScrub = { edit, reason -> playback.cancelScrub(reason == MonitorEditingCancellation.INTERRUPTED, edit) },
        longPressFeedback = haptics::longPress, detentFeedback = haptics::confirm, selectionFeedback = haptics::selection,
        dismissAssistInspector = {
            if (assist.configureTool != null) { assist.configureTool = null; true } else false
        })

    CompositionLocalProvider(LocalMonitorGlass provides glass, LocalMonitorBackdrops provides listOf(backdrop.source),
        com.opencapture.monitorui.LocalMonitorBackdropSurround provides LiveDesign.feedWell) {
        MonitorPlaybackScreen(presentation, actions, backHandler = { handleBack -> BackHandler(onBack = handleBack) },
            picture = { geometry ->
                val mirrorOn = assist.isPlaybackVisible(LiveAssistTool.MIRROR)
                PlaybackFeedView(native = native, scopeBus = model.scopeBus, preview = model.inspectorPreview,
                    backdrop = backdrop, plan = effectsPlan,
                    mirrored = MirrorAssist.feedScaleX(mirrorOn && assist.mirrorHorizontal) < 0f,
                    flippedVertically = mirrorOn && assist.mirrorVertical,
                    zoom = geometry.zoom, sourceWidth = decodeWidth, sourceHeight = decodeHeight,
                    sourceIdentity = playbackState.token, sourceReady = ready,
                    sourceAdmission = { token -> playback.state.value.token == token && playback.isActive }, modifier = Modifier.fillMaxSize())
            }, feedAssists = {
                LiveAssistLayer(state = assist, scopeBus = model.scopeBus, status = status, focus = null,
                    playback = true, colorMode = effectsPlan.scopeTap.transfer.colorMode, modifier = Modifier.fillMaxSize(),
                    onOpenOptions = { tool, frame -> assist.longPressAnchor = com.opencapture.monitorui.MonitorRect(frame.x, frame.y, frame.width, frame.height); assist.configureTool = tool })
            }, canvasAssists = { geometry ->
                if (audioMetersOn) {
                    val local = PlaybackVideoLayout.Rect(0f, 0f, geometry.feed.width, geometry.feed.height)
                    PlaybackAudioMetersOverlay(video = local, canvas = local, left = meterLeft, right = meterRight, state = assist)
                }
            }, tools = { chrome ->
                com.opencapture.openpocketcine.assists.MonitorAssistCluster(portrait = chrome.portrait,
                    locked = false, playback = true, isOn = assist::isPlaybackVisible, onToggle = { assist.togglePlayback(it) },
                    onLongPress = { assist.configureTool = it }, requestExpand = chrome.expanded,
                    onExpansionHandled = chrome.onExpansionHandled, modifier = Modifier.liveModuleFrame(ChromeRect(chrome.frame.x, chrome.frame.y, chrome.frame.width, chrome.frame.height)))
            }, assistInspector = { chrome ->
                assist.configureTool?.let { configure ->
                    com.opencapture.openpocketcine.assists.MonitorAssistInspector(configure, assist, model,
                        PlaybackLutColor.resolve(clip = clipColorMode, live = status.colorMode, last = OperatorPrefs.lastMonitorColorMode(context)),
                        chrome.width, chrome.height, chrome.leading, chrome.top, chrome.bottom, chrome.toolbarFloor,
                        onDismiss = { assist.configureTool = null }, playback = true, safeTrailing = chrome.trailing)
                }
            })
    }
}


@Composable
private fun PlaybackAudioMetersOverlay(
    video: PlaybackVideoLayout.Rect,
    canvas: PlaybackVideoLayout.Rect,
    left: AudioMeterChannel,
    right: AudioMeterChannel,
    state: LiveAssistState,
) {
    val density = LocalDensity.current.density
    val bounds = AssistRect(0f, 0f, canvas.width, canvas.height)
    val edge = 14f * density
    val placement = AssistRect(edge, edge, (canvas.width - 2 * edge).coerceAtLeast(1f),
        (canvas.height - 2 * edge).coerceAtLeast(1f))
    AssistAudioOverlay(state, left.asReading(), right.asReading(), bounds, placement,
        onOpenOptions = { state.configureTool = LiveAssistTool.AUDIO })
}
