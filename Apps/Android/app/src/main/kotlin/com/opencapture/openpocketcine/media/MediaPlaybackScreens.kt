@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.media

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
import com.opencapture.openpocketcine.session.CameraStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
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
                        tint = if (favorite) LiveDesign.amber else LiveDesign.text,
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
    val scope = rememberCoroutineScope()
    val assist = model.assist
    val haptics = LocalOperatorHaptics.current
    var active by remember { mutableStateOf(startingAt) }
    val playlist = if (files.any { it.id == active.id }) files else listOf(active)
    val index = playlist.indexOfFirst { it.id == active.id }
    val canPrev = index > 0
    val canNext = index >= 0 && index < playlist.lastIndex
    var isPlaying by remember { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(false) }
    var currentTime by remember { mutableFloatStateOf(0f) }
    var duration by remember { mutableFloatStateOf(active.durationSeconds.toFloat()) }
    var scrubbing by remember { mutableStateOf(false) }
    var wasPlayingBeforeScrub by remember { mutableStateOf(false) }
    var lastScrubSeekAt by remember { mutableLongStateOf(0L) }
    var reachedEnd by remember { mutableStateOf(false) }
    var ready by remember(active.id) { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var chromeVisible by remember { mutableStateOf(true) }
    var assistMode by remember { mutableStateOf(false) }
    var conformMenu by remember { mutableStateOf(false) }
    var infoOpen by remember { mutableStateOf(false) }
    var looping by remember { mutableStateOf(false) }
    var playbackSource by remember { mutableStateOf("") }
    var conformSource by remember { mutableStateOf(ConformPreview.Source()) }
    var conformTarget by remember { mutableStateOf<Double?>(null) }
    var videoWidth by remember { mutableFloatStateOf(16f) }
    var videoHeight by remember { mutableFloatStateOf(9f) }
    var zoom by remember { mutableStateOf(AnchoredPinchZoom()) }
    var frameScrubbing by remember { mutableStateOf(false) }
    var frameScrubOrigin by remember { mutableFloatStateOf(0f) }
    var flashSymbol by remember { mutableStateOf<OpcIcon?>(null) }
    var flashVisible by remember { mutableStateOf(false) }
    var flashJob by remember { mutableStateOf<Job?>(null) }
    var meterLeft by remember { mutableStateOf(AudioMeterChannel.Silent) }
    var meterRight by remember { mutableStateOf(AudioMeterChannel.Silent) }
    val favorite = controller.isFavorite(active)
    val progress = controller.downloadProgress[active.path]
    val context = LocalContext.current
    val playbackWindow = androidx.compose.ui.platform.LocalWindowInfo.current.containerSize
    val portraitPlayback = playbackWindow.height > playbackWindow.width
    val density = LocalDensity.current
    val anyPlaybackAssistOn = assist.playbackVisibleTools.isNotEmpty()
    val audioMetersOn = assist.isPlaybackVisible(LiveAssistTool.AUDIO)
    val conformSpeed =
        run {
            val target = conformTarget
            val rate = conformSource.captureRate
            if (target == null || rate == null) 1.0 else ConformPreview.speed(rate, target)
        }
    val conformAvailability = ConformPreview.availability(conformSource)
    val meterBox = remember { AudioLevelTapBox() }
    val meterSink = remember { PlaybackPcmBufferSink(meterBox) }
    val glass = remember { MonitorGlass(GlassTier.FLAT) }

    fun handlePlaybackBack() {
        when {
            confirmDelete -> confirmDelete = false
            assist.configureTool != null -> assist.configureTool = null
            infoOpen -> infoOpen = false
            else -> onClose()
        }
    }
    BackHandler { handlePlaybackBack() }
    val backdrop = rememberMonitorBackdropFeed(active.id, enabled = ready)
    val status by model.session.chromeStatus.collectAsState()
    var decodeWidth by remember { mutableIntStateOf(1280) }
    var decodeHeight by remember { mutableIntStateOf(720) }
    var clipColorMode by remember { mutableIntStateOf(-1) }
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

    fun applyListedGeometry() {
        val listed = PlaybackVideoLayout.sizeFromResolution(active.resolution)
        videoWidth = listed?.width ?: 16f
        videoHeight = listed?.height ?: 9f
        conformTarget = null
        conformSource = ConformPreview.probe(listedRate = active.fps?.toDouble())
    }

    fun conformedLabel(seconds: Float): String =
        MediaClipFormatting.durationLabel(ConformPreview.conformedDuration(seconds.toDouble(), conformSpeed))

    val player =
        remember {
            createPlaybackExoPlayer(context, meterSink).apply { playWhenReady = true }
        }

    fun applyPlaybackRate() {
        player.playbackParameters = PlaybackParameters(conformSpeed.toFloat(), 1f)
        player.volume = if (isMuted || conformTarget != null) 0f else 1f
    }

    DisposableEffect(player) {
        val listener =
            object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_READY) {
                        ready = true
                        val dur = player.duration
                        if (dur > 0) duration = dur / 1000f
                    }
                    if (playbackState == Player.STATE_ENDED) {
                        reachedEnd = true
                        isPlaying = false
                    }
                }

                override fun onIsPlayingChanged(playing: Boolean) {
                    isPlaying = playing
                }

                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    if (videoSize.width > 1 && videoSize.height > 1) {
                        val ratio = videoSize.pixelWidthHeightRatio.takeIf { it.isFinite() && it > 0f } ?: 1f
                        videoWidth = videoSize.width * ratio
                        videoHeight = videoSize.height.toFloat()
                        decodeWidth = videoSize.width
                        decodeHeight = videoSize.height
                    }
                }
            }
        player.addListener(listener)
        onDispose {
            assist.configureTool = null
            flashJob?.cancel()
            player.removeListener(listener)
            player.release()
        }
    }

    LaunchedEffect(active.id) {
        assist.configureTool = null
        com.opencapture.openpocketcine.feed.InspectorPreviewPipeline.sourceChanged(playback = true)
        ready = false
        loadError = null
        reachedEnd = false
        currentTime = 0f
        duration = active.durationSeconds.toFloat()
        clipColorMode = -1
        zoom = AnchoredPinchZoom()
        frameScrubbing = false
        decodeWidth = 1280
        decodeHeight = 720
        applyListedGeometry()
        meterBox.readAndReset()
        player.stop()
        player.clearMediaItems()
        val local = controller.cacheForPlayback(active)
        if (local == null) {
            clipColorMode = -1
            loadError =
                if (controller.isLive) MediaOperatorCopy.CLIP_OPEN_FAILED
                else MediaOperatorCopy.CLIP_NOT_CACHED
            return@LaunchedEffect
        }
        clipColorMode =
            withContext(Dispatchers.IO) { controller.fetchShotColor(active) }
        playbackSource = if (local.extension.lowercase() in listOf("lrf", "xrf")) "PROXY" else "ORIGINAL"
        player.setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(local)))
        player.prepare()
        applyPlaybackRate()
        player.playWhenReady = true
        isPlaying = true
        if (model.cacheFullResolution && controller.isLive && !controller.isDownloaded(active)) {
            controller.download(active)
        }
    }

    LaunchedEffect(looping) { player.repeatMode = if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF }

    LaunchedEffect(progress, active.id) {
        if (progress != null && progress >= 1f && controller.isDownloaded(active)) {
            clipColorMode =
                withContext(Dispatchers.IO) { controller.fetchShotColor(active) }
        }
    }

    LaunchedEffect(ready, active.id) {
        if (!ready) return@LaunchedEffect
        val formatRate = player.videoFormat?.frameRate
        val nominal =
            if (formatRate != null && formatRate.isFinite() && formatRate > 1f) {
                formatRate.toDouble()
            } else {
                null
            }
        val probed =
            ConformPreview.probe(
                nominalFrameRate = nominal,
                listedRate = active.fps?.toDouble(),
            )
        conformSource = probed
        val target = conformTarget
        val rate = probed.captureRate
        if (target != null && rate != null && target >= rate * ConformPreview.conformFloor) {
            conformTarget = null
        }
    }

    LaunchedEffect(conformTarget, isMuted, conformSpeed) {
        applyPlaybackRate()
    }

    LaunchedEffect(player, isPlaying, scrubbing) {
        while (true) {
            if (!scrubbing) {
                currentTime = (player.currentPosition / 1000f).coerceAtLeast(0f)
                val dur = player.duration
                if (dur > 0) duration = dur / 1000f
            }
            delay(200)
        }
    }

    LaunchedEffect(audioMetersOn, conformTarget != null) {
        if (!audioMetersOn) {
            meterLeft = AudioMeterChannel.Silent
            meterRight = AudioMeterChannel.Silent
            meterBox.readAndReset()
            return@LaunchedEffect
        }
        var left = AudioMeterChannel.Silent
        var right = AudioMeterChannel.Silent
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
            val peaks = meterBox.peaksForMeters(conforming = conformTarget != null)
            left = AudioMeterBallistics.step(left, peaks.first.toDouble(), dt)
            right = AudioMeterBallistics.step(right, peaks.second.toDouble(), dt)
            meterLeft = left
            meterRight = right
        }
    }

    fun seekBy(delta: Float) {
        val target = (currentTime + delta).coerceIn(0f, max(duration, 0f))
        player.seekTo((target * 1000).toLong())
        currentTime = target
        if (reachedEnd && target + 0.05f < duration) reachedEnd = false
    }

    fun flashTransport(willPlay: Boolean) {
        flashJob?.cancel()
        flashJob =
            scope.launch {
                flashSymbol = if (willPlay) OpcIcon.PLAY else OpcIcon.PAUSE
                flashVisible = true
                delay(550)
                flashVisible = false
                delay(220)
                flashSymbol = null
            }
    }

    fun handleFrameTap() {
        if (!ready || frameScrubbing) return
        when (PlaybackFrameTap.action(chromeVisible, reachedEnd)) {
            PlaybackFrameTap.RESTART_PLAYBACK -> {
                player.seekTo(0)
                applyPlaybackRate()
                player.play()
                reachedEnd = false
                isPlaying = true
                flashTransport(true)
            }
            PlaybackFrameTap.TOGGLE_TRANSPORT -> {
                val willPlay = !isPlaying
                if (isPlaying) {
                    player.pause()
                } else {
                    applyPlaybackRate()
                    player.play()
                }
                flashTransport(willPlay)
            }
            PlaybackFrameTap.IGNORE -> Unit
        }
    }

    fun goToAdjacent(offset: Int) {
        val next = index + offset
        if (next !in playlist.indices) return
        player.pause()
        isPlaying = true
        reachedEnd = false
        ready = false
        zoom = AnchoredPinchZoom()
        active = playlist[next]
    }

    CompositionLocalProvider(LocalMonitorGlass provides glass, LocalMonitorBackdrops provides listOf(backdrop.source),
        com.opencapture.monitorui.LocalMonitorBackdropSurround provides LiveDesign.feedWell) {
    Box(Modifier.fillMaxSize().background(LiveDesign.feedWell)) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val container =
                PlaybackVideoLayout.Rect(0f, 0f, constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
            val fitted =
                PlaybackVideoLayout.aspectFitRect(
                    PlaybackVideoLayout.Size(assist.presentedAspect(videoWidth / videoHeight, playback = true), 1f),
                    container,
                )
            LaunchedEffect(fitted.width, fitted.height) {
                zoom = zoom.endGesture(fitted.width, fitted.height)
            }
            val mirror = MirrorAssist.feedScaleX(assist.isPlaybackVisible(LiveAssistTool.MIRROR))
            val overlayWidthPx = constraints.maxWidth
            val overlayHeightPx = constraints.maxHeight
            val viewportWidth = maxWidth.value
            val viewportHeight = maxHeight.value
            val layoutDir = LocalLayoutDirection.current
            val safeTop = with(density) {
                maxOf(
                    WindowInsets.displayCutout.getTop(this),
                    WindowInsets.statusBars.getTop(this),
                ).toDp().value
            }
            val safeLeading = with(density) {
                maxOf(
                    WindowInsets.displayCutout.getLeft(this, layoutDir),
                    WindowInsets.systemBars.getLeft(this, layoutDir),
                ).toDp().value
            }
            val safeTrailing = with(density) {
                maxOf(
                    WindowInsets.displayCutout.getRight(this, layoutDir),
                    WindowInsets.systemBars.getRight(this, layoutDir),
                ).toDp().value
            }
            val sideInset = max(safeLeading, safeTrailing)
            val safeBottom = monitorBottomInsetDp(
                rawInsetDp = with(density) {
                    maxOf(
                        WindowInsets.displayCutout.getBottom(this),
                        WindowInsets.navigationBars.getBottom(this),
                    ).toDp().value
                },
                isPortrait = portraitPlayback,
            )
            val fieldLayout = MonitorLayoutPolicy.fieldMonitor(
                viewportWidth, viewportHeight, safeTop, safeLeading, safeBottom, safeTrailing,
                hasDisplayCutout = max(safeLeading, safeTrailing) > 0f,
            )
            val headerTop = MonitorPlaybackLayout.headerTop(portraitPlayback, safeTop, fieldLayout.lock.y)
            val backX = if (portraitPlayback) safeLeading + 22f else fieldLayout.lock.x
            val navLeading = with(density) { WindowInsets.navigationBars.getLeft(this, layoutDir).toDp().value }
            val navTrailing = with(density) { WindowInsets.navigationBars.getRight(this, layoutDir).toDp().value }
            val assistFrame = MonitorLayoutPolicy.fieldMonitorAssists(
                viewportWidth - navLeading - navTrailing, viewportHeight, safeTop, safeBottom,
            )
            val assistRect = ChromeRect(assistFrame.x + navLeading, assistFrame.y, assistFrame.width, assistFrame.height)
            Box(
                Modifier
                    .offset { IntOffset(fitted.x.roundToInt(), fitted.y.roundToInt()) }
                    .size(
                        with(density) { fitted.width.toDp() },
                        with(density) { fitted.height.toDp() },
                    )
                    .clipToBounds(),
            ) {
                PlaybackFeedView(
                    player = player,
                    backdrop = backdrop,
                    plan = effectsPlan,
                    mirrored = mirror < 0f,
                    zoom = zoom,
                    sourceWidth = decodeWidth,
                    sourceHeight = decodeHeight,
                    sourceIdentity = active.id,
                    sourceReady = ready,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            Popup(
                alignment = Alignment.TopStart,
                onDismissRequest = { handlePlaybackBack() },
                properties =
                    PopupProperties(
                        // This native window owns the playback controls and
                        // adjustable scrubber; expose it to accessibility too.
                        focusable = true,
                        clippingEnabled = false,
                    ),
            ) {
            Box(
                Modifier.size(
                    with(density) { overlayWidthPx.toDp() },
                    with(density) { overlayHeightPx.toDp() },
                ),
            ) {
            Box(
                Modifier
                    .offset { IntOffset(fitted.x.roundToInt(), fitted.y.roundToInt()) }
                    .size(
                        with(density) { fitted.width.toDp() },
                        with(density) { fitted.height.toDp() },
                    ),
            ) {
                val latestReady by rememberUpdatedState(ready)
                val latestZoomed by rememberUpdatedState(zoom.isZoomed)
                val latestOnTap by rememberUpdatedState({ handleFrameTap() })
                val latestOnSwipe by rememberUpdatedState<(PlaybackChromeSwipe) -> Unit>({ swipe ->
                    chromeVisible = swipe == PlaybackChromeSwipe.SHOW
                })
                val latestOnScrubStart by rememberUpdatedState({
                    wasPlayingBeforeScrub = isPlaying
                    frameScrubOrigin = currentTime
                    scrubbing = true
                    frameScrubbing = true
                    player.pause()
                    isPlaying = false
                    haptics.longPress()
                })
                val latestOnScrubDelta by rememberUpdatedState<(Float) -> Unit>({ dx ->
                    val time =
                        PlaybackFrameScrub.timeAfterDelta(
                            originSeconds = frameScrubOrigin,
                            deltaPx = dx,
                            videoWidthPx = fitted.width,
                            durationSeconds = duration,
                        )
                    currentTime = time
                    if (reachedEnd && time + 0.05f < duration) reachedEnd = false
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastScrubSeekAt >=
                        (PlaybackFrameScrub.SEEK_THROTTLE_SECONDS * 1000).toLong()
                    ) {
                        lastScrubSeekAt = now
                        player.seekTo((time * 1000).toLong())
                    }
                })
                val latestOnScrubEnd by rememberUpdatedState({
                    player.seekTo((currentTime * 1000).toLong())
                    scrubbing = false
                    frameScrubbing = false
                    if (reachedEnd && currentTime + 0.05f < duration) reachedEnd = false
                    if (wasPlayingBeforeScrub) {
                        applyPlaybackRate()
                        player.play()
                    }
                })
                val latestOnPinch by rememberUpdatedState<(Float, Offset) -> Unit>({ magnification, centroid ->
                    val anchor = unitPoint(centroid, fitted.width, fitted.height)
                    zoom =
                        zoom.pinchChanged(
                            magnification,
                            anchor.first,
                            anchor.second,
                            fitted.width,
                            fitted.height,
                        )
                })
                val latestOnPinchEnd by rememberUpdatedState({
                    zoom = zoom.endGesture(fitted.width, fitted.height)
                })
                val latestOnPan by rememberUpdatedState<(Offset) -> Unit>({ translation ->
                    zoom = zoom.panChanged(translation.x, translation.y)
                })
                val latestOnPanEnd by rememberUpdatedState({
                    zoom = zoom.endGesture(fitted.width, fitted.height)
                })
                // Gesture well matches iOS: hits the unzoomed letterbox, not the scaled raster.
                Box(
                    Modifier
                        .fillMaxSize()
                        .pointerInput(active.id) {
                            detectPlaybackVideoGestures(
                                isReady = { latestReady },
                                isZoomed = { latestZoomed },
                                onTap = { latestOnTap() },
                                onChromeSwipe = { latestOnSwipe(it) },
                                onScrubStart = { latestOnScrubStart() },
                                onScrubDelta = { latestOnScrubDelta(it) },
                                onScrubEnd = { latestOnScrubEnd() },
                                onPinch = { mag, centroid -> latestOnPinch(mag, centroid) },
                                onPinchEnd = { latestOnPinchEnd() },
                                onPan = { latestOnPan(it) },
                                onPanEnd = { latestOnPanEnd() },
                            )
                        },
                )
                LiveAssistLayer(
                    state = assist,
                    status = status,
                    focus = null,
                    playback = true,
                    colorMode = effectsPlan.scopeTap.colorMode,
                    modifier = Modifier.fillMaxSize(),
                    onOpenOptions = { tool, frame ->
                        assist.longPressAnchor = frame
                        assist.configureTool = tool
                    },
                )
                if (playlist.size > 1) {
                    if (canPrev) {
                        ClipNavButton(
                            icon = OpcIcon.CHEVRON_LEFT,
                            label = "Previous clip",
                            modifier = Modifier.align(Alignment.CenterStart)
                                .padding(start = MonitorPlaybackLayout.clipNavEdgePadding().dp),
                        ) { goToAdjacent(-1) }
                    }
                    if (canNext) {
                        ClipNavButton(
                            icon = OpcIcon.CHEVRON_RIGHT,
                            label = "Next clip",
                            modifier = Modifier.align(Alignment.CenterEnd)
                                .padding(end = MonitorPlaybackLayout.clipNavEdgePadding().dp),
                        ) { goToAdjacent(1) }
                    }
                }
                PlaybackTransportFlash(
                    symbol = flashSymbol,
                    visible = flashVisible,
                    modifier = Modifier.align(Alignment.Center),
                )
                if (frameScrubbing && duration > 0f) {
                    PlaybackFrameScrubOverlay(
                        scrubSeconds = currentTime,
                        durationSeconds = duration,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                if (audioMetersOn) {
                    val local =
                        PlaybackVideoLayout.Rect(0f, 0f, fitted.width, fitted.height)
                    PlaybackAudioMetersOverlay(
                        video = local,
                        canvas = local,
                        left = meterLeft,
                        right = meterRight,
                        state = assist,
                    )
                }
            }
            if (!ready || loadError != null) {
                Box(
                    Modifier.fillMaxSize().background(LiveDesign.feedWell.copy(alpha = 0.72f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        Modifier
                            .clip(MediaCornerShape)
                            .mediaGlass(MediaCornerShape)
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        if (loadError == null) {
                            if (progress != null && progress > 0 && progress < 1) {
                                MediaGlassTrack(fraction = progress.toFloat(), trackWidth = 120.dp)
                            } else {
                                CircularProgressIndicator(color = LiveDesign.accent)
                            }
                        }
                        Text(
                            loadError
                                ?: if (progress != null) "Buffering from camera…" else "Preparing playback…",
                            color = LiveDesign.muted,
                            style = LiveType.ui(14f, FontWeight.Medium),
                            modifier = Modifier.padding(top = 12.dp),
                        )
                    }
                }
            }
            if (chromeVisible) {
                com.opencapture.monitorui.MonitorPlaybackHeader(
                    title = active.filename,
                    subtitle = listOfNotNull(active.resolution, active.fps?.let { "${it}p" }, active.fileExtension).joinToString(" · "),
                    source = playbackSource, portrait = portraitPlayback,
                    modifier = Modifier.align(Alignment.TopCenter)
                        .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.7f), Color.Transparent)))
                        .padding(
                        start = max(MonitorPlaybackLayout.headerGutter(sideInset), backX + fieldLayout.lock.width + 12f).dp,
                        end = MonitorPlaybackLayout.headerGutter(sideInset).dp,
                        top = headerTop.dp,
                        bottom = MonitorPlaybackLayout.HEADER_BOTTOM.dp,
                    ),
                    actions = {
                        PlaybackActionChip(
                            OpcIcon.STAR, "Favorite clip", { controller.toggleFavorite(active) },
                            filled = favorite, tint = if (favorite) LiveDesign.amber else LiveDesign.text.copy(alpha = 0.86f),
                        )
                        PlaybackActionChip(OpcIcon.INFO, "Clip info", { infoOpen = !infoOpen }, active = infoOpen)
                        PlaybackActionChip(
                            OpcIcon.SHARE, "Share clip", { player.pause(); onDeliver(active) },
                            title = if (portraitPlayback) null else "SHARE", active = true,
                        )
                        if (controller.canDelete(active)) {
                            PlaybackActionChip(OpcIcon.TRASH, "Delete clip", { confirmDelete = true }, destructive = true)
                        }
                    },
                )
                com.opencapture.openpocketcine.AuxCircleButton(
                    modifier = Modifier.align(Alignment.TopStart)
                        .offset(x = backX.dp, y = headerTop.dp)
                        .size(fieldLayout.lock.width.dp, fieldLayout.lock.height.dp)
                        .semantics { contentDescription = "Back to media" },
                    onClick = onClose,
                ) { tint ->
                    OpcIcon(OpcIcon.CHEVRON_LEFT, contentDescription = null, tint = tint,
                        modifier = Modifier.size(29.dp))
                }
                com.opencapture.monitorui.MonitorPlaybackFooter(
                    position = conformedLabel(currentTime), duration = conformedLabel(duration), portrait = portraitPlayback,
                    modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                        .windowInsetsPadding(WindowInsets.navigationBars.only(WindowInsetsSides.Bottom))
                        .background(Brush.verticalGradient(
                            0f to Color.Transparent, 0.38f to Color.Black.copy(alpha = 0.4f),
                            1f to Color.Black.copy(alpha = 0.78f),
                        ))
                        .padding(horizontal = (if (portraitPlayback) sideInset
                            else max(sideInset, assistFrame.x + assistFrame.width + 8f)).dp)
                        .padding(
                            start = MonitorPlaybackLayout.FOOTER_INNER_HORIZONTAL.dp,
                            end = MonitorPlaybackLayout.FOOTER_INNER_HORIZONTAL.dp,
                            top = MonitorPlaybackLayout.FOOTER_INNER_TOP.dp,
                            bottom = MonitorPlaybackLayout.FOOTER_INNER_BOTTOM.dp,
                        ),
                    scrubber = {
                        MediaPlaybackScrubber(
                            progressSeconds = if (duration > 0f) currentTime.coerceIn(0f, duration) else 0f,
                            durationSeconds = duration,
                            onScrubbingChanged = { dragging ->
                                if (dragging) {
                                    if (!scrubbing) {
                                        wasPlayingBeforeScrub = isPlaying
                                        player.pause()
                                    }
                                    scrubbing = true
                                } else {
                                    scrubbing = false
                                }
                            },
                            onProgressChange = { time ->
                                currentTime = time
                                if (reachedEnd && time + 0.05f < duration) reachedEnd = false
                                val now = SystemClock.elapsedRealtime()
                                if (now - lastScrubSeekAt >=
                                    (PlaybackFrameScrub.SEEK_THROTTLE_SECONDS * 1000).toLong()
                                ) {
                                    lastScrubSeekAt = now
                                    player.seekTo((time * 1000).toLong())
                                }
                            },
                            onSeek = {
                                currentTime = it
                                player.seekTo((it * 1000).toLong())
                                if (reachedEnd && it + 0.05f < duration) reachedEnd = false
                                scrubbing = false
                                if (wasPlayingBeforeScrub) {
                                    applyPlaybackRate()
                                    player.play()
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    },
                    transport = {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(MonitorPlaybackLayout.TRANSPORT_SPACING.dp),
                        ) {
                            PlaybackTransportButton(OpcIcon.SKIP_BACK, "Back 15 seconds") { seekBy(-15f) }
                            PlaybackTransportButton(
                                if (reachedEnd) OpcIcon.ROTATE_CW else if (isPlaying) OpcIcon.PAUSE else OpcIcon.PLAY,
                                if (reachedEnd) "Restart clip" else if (isPlaying) "Pause" else "Play",
                                iconSize = MonitorPlaybackLayout.PLAY_ICON_SIZE.dp,
                            ) {
                                if (reachedEnd) {
                                    player.seekTo(0)
                                    reachedEnd = false
                                    applyPlaybackRate()
                                    player.play()
                                } else if (isPlaying) {
                                    player.pause()
                                } else {
                                    applyPlaybackRate()
                                    player.play()
                                }
                            }
                            PlaybackTransportButton(OpcIcon.SKIP_FORWARD, "Forward 15 seconds") { seekBy(15f) }
                        }
                    },
                    options = {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(MonitorPlaybackLayout.ACTION_SPACING.dp),
                        ) {
                            PlaybackConformButton(conformAvailability, conformSource.captureRate ?: 0.0, conformTarget,
                                conformMenu, { conformMenu = it }, { conformTarget = it })
                            PlaybackActionChip(
                                if (isMuted) OpcIcon.VOLUME_X else OpcIcon.VOLUME_2,
                                if (isMuted) "Unmute" else "Mute", { isMuted = !isMuted }, active = isMuted,
                            )
                            PlaybackActionChip(OpcIcon.REPEAT, "Loop clip", { looping = !looping }, active = looping)
                            PlaybackActionChip(PlaybackChromeMetrics.hideChromeIcon, "Hide playback controls", { chromeVisible = false })
                        }
                    },
                )
                com.opencapture.openpocketcine.assists.MonitorAssistCluster(
                    portrait = portraitPlayback, locked = false,
                    playback = true,
                    isOn = assist::isPlaybackVisible, onToggle = { assist.togglePlayback(it) },
                    onLongPress = { assist.configureTool = it },
                    requestExpand = assistMode, onExpansionHandled = { assistMode = false },
                    modifier = Modifier.liveModuleFrame(assistRect),
                )
            } else {
                Box(
                    Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = (sideInset + 12f).dp)
                        .navigationBarsPadding()
                        .padding(12.dp),
                ) {
                    PlaybackActionChip(
                        PlaybackChromeMetrics.showChromeIcon,
                        "Show playback controls",
                        { chromeVisible = true },
                    )
                }
            }
            if (infoOpen) {
                Box(Modifier.fillMaxSize().chromeClickable { infoOpen = false }) {
                    val rows = buildList {
                        fun row(label: String, value: String?) { if (!value.isNullOrBlank()) add(com.opencapture.monitorui.MonitorMetadataRow(label, value)) }
                        row("File", active.filename)
                        row("Format", active.fileExtension)
                        row("Resolution", active.resolution)
                        row("Frame rate", active.fps?.let { "${it} fps" })
                        row("Duration", conformedLabel(duration))
                        row("Playback source", playbackSource)
                        row("Size", active.sizeBytes.takeIf { it > 0 }?.let { android.text.format.Formatter.formatShortFileSize(context, it) })
                        row("Created", active.filenameTimestamp?.let { "${it.take(4)}-${it.substring(4,6)}-${it.substring(6,8)} ${it.substring(8,10)}:${it.substring(10,12)}:${it.substring(12,14)}" })
                        row("Favorite", if (favorite) "Yes" else "No")
                    }
                    com.opencapture.monitorui.MonitorMetadataDrawer(rows,
                        modifier = Modifier.align(Alignment.CenterEnd)
                            .padding(
                                end = (sideInset + 12f).dp,
                                top = (safeTop + 12f).dp,
                                bottom = (safeBottom + 12f).dp,
                            )
                            .chromeClickable { },
                        close = { MediaCircleIconButton(OpcIcon.X, "Close clip information", { infoOpen = false }) })
                }
            }

            val configure = assist.configureTool
            if (configure != null) {
                com.opencapture.openpocketcine.assists.MonitorAssistInspector(
                    configure, assist, model,
                    PlaybackLutColor.resolve(clip = clipColorMode, live = status.colorMode,
                        last = OperatorPrefs.lastMonitorColorMode(context)),
                    viewportWidth, viewportHeight,
                    safeLeading, safeTop, safeBottom, viewportHeight - 120f,
                    onDismiss = { assist.configureTool = null }, playback = true,
                    safeTrailing = safeTrailing,
                )
            }

            // Inside the overlay window: in the host window it sits under the gesture well.
            if (confirmDelete) {
                MediaConfirmPopup(
                    title = "Delete this clip from the camera?",
                    confirmTitle = "Delete",
                    onDismiss = { confirmDelete = false },
                    onConfirm = {
                        confirmDelete = false
                        scope.launch {
                            val dying = active
                            controller.delete(dying)
                            when {
                                canNext -> active = playlist[index + 1]
                                canPrev -> active = playlist[index - 1]
                                else -> onClose()
                            }
                        }
                    },
                )
            }

            }
            }
        }
    }
    }
}

@Composable
private fun PlaybackTransportFlash(
    symbol: OpcIcon?,
    visible: Boolean,
    modifier: Modifier = Modifier,
) {
    if (symbol == null) return
    OpcIcon(
        icon = symbol,
        contentDescription = null,
        tint = LiveDesign.text.copy(alpha = if (visible) 1f else 0f),
        modifier = modifier.size(48.dp),
    )
}

@Composable
private fun PlaybackFrameScrubOverlay(
    scrubSeconds: Float,
    durationSeconds: Float,
    modifier: Modifier = Modifier,
) {
    val fraction = if (durationSeconds > 0f) (scrubSeconds / durationSeconds).coerceIn(0f, 1f) else 0f
    Box(modifier, contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .clip(RoundedCornerShape(percent = 50))
                .mediaGlass(RoundedCornerShape(percent = 50))
                .padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                MediaClipFormatting.durationLabel(scrubSeconds.toDouble()),
                color = LiveDesign.text,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
            )
            Text(
                "/ ${MediaClipFormatting.durationLabel(durationSeconds.toDouble())}",
                color = LiveDesign.muted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
            )
        }
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 16.dp, vertical = 18.dp)
                .fillMaxWidth()
                .height(3.dp)
                .clip(RoundedCornerShape(percent = 50))
                .background(LiveDesign.hairline),
        ) {
            Box(
                Modifier
                    .fillMaxWidth(fraction.coerceAtLeast(0.01f))
                    .height(3.dp)
                    .clip(RoundedCornerShape(percent = 50))
                    .background(LiveDesign.accent),
            )
        }
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

@Composable
private fun PlaybackTransportButton(
    icon: OpcIcon,
    label: String,
    iconSize: Dp = MonitorPlaybackLayout.TRANSPORT_ICON_SIZE.dp,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(MonitorPlaybackLayout.TRANSPORT_SIZE.dp)
            .chromeClickable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(
            icon = icon,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(iconSize).shadow(5.dp, CircleShape),
        )
    }
}

@Composable
private fun ClipNavButton(
    icon: OpcIcon,
    label: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(MonitorPlaybackLayout.CLIP_NAV_SIZE.dp)
            .clip(CircleShape)
            .mediaGlass(CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(icon = icon, contentDescription = null, tint = LiveDesign.accent, modifier = Modifier.size(13.dp))
    }
}

@Composable
private fun PlaybackConformButton(
    availability: ConformPreview.Availability,
    captureRate: Double,
    selected: Double?,
    menuOpen: Boolean,
    onMenuOpenChange: (Boolean) -> Unit,
    onSelect: (Double?) -> Unit,
) {
    Box {
        PlaybackActionChip(
            OpcIcon.TIMER,
            "Conform preview",
            { onMenuOpenChange(true) },
            active = selected != null,
            enabled = availability.isAvailable,
        )
        if (menuOpen) {
            val config = LocalConfiguration.current
            val width = minOf(620, config.screenWidthDp - 28).dp
            val provider = remember {
                object : androidx.compose.ui.window.PopupPositionProvider {
                    override fun calculatePosition(anchorBounds: androidx.compose.ui.unit.IntRect,
                        windowSize: androidx.compose.ui.unit.IntSize, layoutDirection: androidx.compose.ui.unit.LayoutDirection,
                        popupContentSize: androidx.compose.ui.unit.IntSize): IntOffset =
                        IntOffset((windowSize.width - popupContentSize.width) / 2, windowSize.height - popupContentSize.height)
                }
            }
            Popup(popupPositionProvider = provider, onDismissRequest = { onMenuOpenChange(false) },
                properties = PopupProperties(focusable = true)) {
                Column(Modifier.width(width).clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
                    .monitorMaterial(MonitorMaterial.Expanded).navigationBarsPadding()
                    .padding(horizontal = 14.dp, vertical = 11.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("CONFORM", style = LiveType.ui(9f, FontWeight.SemiBold))
                            Text(ConformPreview.menuHeader(captureRate), color = LiveDesign.muted, style = LiveType.ui(8.5f))
                        }
                        MediaCircleIconButton(OpcIcon.X, "Close conform preview", { onMenuOpenChange(false) }, size = 34.dp)
                    }
                    val choices = listOf<Double?>(null) + availability.targets
                    val labels = choices.map { if (it == null) "Real time" else ConformPreview.targetLabel(captureRate, it) }
                    val haptics = LocalOperatorHaptics.current
                    com.opencapture.monitorui.MonitorValueDrum(
                        labels,
                        if (selected == null) "Real time" else ConformPreview.targetLabel(captureRate, selected),
                        onDetent = { haptics.confirm() },
                    ) { label ->
                        val index = labels.indexOf(label)
                        if (index >= 0) onSelect(choices[index])
                    }
                    availability.unavailableReason?.let { Text(it, color = LiveDesign.muted, style = LiveType.ui(10f)) }
                    if (selected != null) Text(ConformPreview.audioLabel, color = LiveDesign.muted, style = LiveType.ui(10f))
                }
            }
        }
    }
}
