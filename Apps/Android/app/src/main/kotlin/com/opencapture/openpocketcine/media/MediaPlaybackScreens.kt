@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import com.kyant.backdrop.backdrops.layerBackdrop
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.GlassTier
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.openpocketcine.LocalOperatorHaptics
import com.opencapture.openpocketcine.MonitorGlass
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.assists.AssistOptionsPopup
import com.opencapture.openpocketcine.assists.AudioAssist
import com.opencapture.openpocketcine.assists.AudioMetersPanel
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
    file: MediaFile,
    controller: MediaLibraryController,
    onClose: () -> Unit,
    onDeliver: (MediaFile) -> Unit = {},
) {
    val scope = rememberCoroutineScope()
    var bitmap by remember(file.id) { mutableStateOf<Bitmap?>(null) }
    var loading by remember { mutableStateOf(true) }
    var zoom by remember(file.id) { mutableStateOf(AnchoredPinchZoom()) }
    var confirmDelete by remember { mutableStateOf(false) }
    val favorite = controller.isFavorite(file)
    val glass = rememberPlaybackMonitorGlass()
    val recorded =
        if (glass.tier == GlassTier.FULL && glass.layerBackdrop != null) {
            Modifier.layerBackdrop(glass.layerBackdrop)
        } else {
            Modifier
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

    CompositionLocalProvider(LocalMonitorGlass provides glass) {
    Box(Modifier.fillMaxSize().background(LiveDesign.feedWell)) {
        val image = bitmap
        if (image != null) {
            BoxWithConstraints(Modifier.fillMaxSize().then(recorded)) {
                val widthPx = constraints.maxWidth.toFloat()
                val heightPx = constraints.maxHeight.toFloat()
                Image(
                    image.asImageBitmap(),
                    contentDescription = file.filename,
                    contentScale = ContentScale.Fit,
                    modifier =
                        Modifier
                            .fillMaxSize()
                            .graphicsLayer {
                                scaleX = zoom.scale
                                scaleY = zoom.scale
                                translationX = zoom.offsetX
                                translationY = zoom.offsetY
                            }
                            .pointerInput(file.id) {
                                detectPlaybackVideoGestures(
                                    isReady = { true },
                                    isZoomed = { zoom.isZoomed },
                                    config =
                                        PlaybackGestureConfig(
                                            enableTap = false,
                                            enableScrub = false,
                                            enableSwipe = false,
                                        ),
                                    onTap = {},
                                    onChromeSwipe = {},
                                    onScrubStart = {},
                                    onScrubDelta = {},
                                    onScrubEnd = {},
                                    onPinch = { magnification, centroid ->
                                        val anchor = unitPoint(centroid, widthPx, heightPx)
                                        zoom =
                                            zoom.pinchChanged(
                                                magnification,
                                                anchor.first,
                                                anchor.second,
                                                widthPx,
                                                heightPx,
                                            )
                                    },
                                    onPinchEnd = { zoom = zoom.endGesture(widthPx, heightPx) },
                                    onPan = { translation ->
                                        zoom = zoom.panChanged(translation.x, translation.y)
                                    },
                                    onPanEnd = { zoom = zoom.endGesture(widthPx, heightPx) },
                                )
                            },
                )
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

        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            MediaCloseButton(onClick = onClose, size = 34.dp)
            Text(
                file.filename,
                color = LiveDesign.text,
                style = LiveType.ui(14f, FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (controller.canDelete(file)) {
                MediaCircleIconButton(OpcIcon.TRASH, "Delete", onClick = { confirmDelete = true })
            }
            MediaCircleIconButton(OpcIcon.SHARE, "Share photo", onClick = { onDeliver(file) })
        }

        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 18.dp),
        ) {
            MediaFavoriteButton(favorite) { controller.toggleFavorite(file) }
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
    var ready by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var chromeVisible by remember { mutableStateOf(true) }
    var assistMode by remember { mutableStateOf(false) }
    var conformMenu by remember { mutableStateOf(false) }
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
    val status by model.session.status.collectAsState()
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
        player.setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(local)))
        player.prepare()
        applyPlaybackRate()
        player.playWhenReady = true
        isPlaying = true
        if (model.cacheFullResolution && controller.isLive && !controller.isDownloaded(active)) {
            controller.download(active)
        }
    }

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

    CompositionLocalProvider(LocalMonitorGlass provides glass) {
    Box(Modifier.fillMaxSize().background(LiveDesign.feedWell)) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val container =
                PlaybackVideoLayout.Rect(0f, 0f, constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
            val fitted =
                PlaybackVideoLayout.aspectFitRect(
                    PlaybackVideoLayout.Size(videoWidth, videoHeight),
                    container,
                )
            val mirror = MirrorAssist.feedScaleX(assist.isPlaybackVisible(LiveAssistTool.MIRROR))
            val overlayWidthPx = constraints.maxWidth
            val overlayHeightPx = constraints.maxHeight
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
                    plan = effectsPlan,
                    mirrored = mirror < 0f,
                    zoom = zoom,
                    sourceWidth = decodeWidth,
                    sourceHeight = decodeHeight,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            Popup(
                alignment = Alignment.TopStart,
                properties =
                    PopupProperties(
                        focusable = false,
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
                            modifier = Modifier.align(Alignment.CenterStart).padding(start = 12.dp),
                        ) { goToAdjacent(-1) }
                    }
                    if (canNext) {
                        ClipNavButton(
                            icon = OpcIcon.CHEVRON_RIGHT,
                            label = "Next clip",
                            modifier = Modifier.align(Alignment.CenterEnd).padding(end = 12.dp),
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
            val overlayWidth = with(density) { overlayWidthPx.toDp() }
            val panelClicks = remember { MutableInteractionSource() }
            if (chromeVisible) {
                Row(
                    Modifier
                        .align(Alignment.TopCenter)
                        .fillMaxWidth()
                        .statusBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    MediaBackButton(onClick = onClose, size = 34.dp)
                    Text(
                        active.filename,
                        color = LiveDesign.text,
                        style =
                            LiveType.ui(14f, FontWeight.SemiBold).copy(
                                shadow =
                                    Shadow(
                                        color = Color.Black.copy(alpha = 0.72f),
                                        offset = Offset(0f, 1f),
                                        blurRadius = 8f,
                                    ),
                            ),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    if (controller.cacheGrade(active).isProxyOnly) {
                        MediaBadge(
                            MediaLibraryCopy.PROXY_TAG,
                            modifier =
                                Modifier.semantics { contentDescription = MediaLibraryCopy.PROXY_HELP },
                        )
                    }
                    MediaFavoriteButton(favorite) { controller.toggleFavorite(active) }
                }
                Column(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .width(overlayWidth)
                        .navigationBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 14.dp)
                        .clip(MediaCornerShape)
                        .playbackFrost(MediaCornerShape)
                        .clickable(
                            indication = null,
                            interactionSource = panelClicks,
                            onClick = {},
                        )
                        .padding(horizontal = 10.dp, vertical = 9.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                if (assistMode) {
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        PlaybackAssistBar(
                            state = assist,
                            onLongPress = { assist.configureTool = it },
                            modifier = Modifier.weight(1f),
                        )
                        MediaTransportIconButton(
                            PlaybackChromeMetrics.viewAssistIcon,
                            "View Assist",
                            action = true,
                            highlighted = true,
                            onClick = { assistMode = false },
                        )
                    }
                } else {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        Text(
                            conformedLabel(currentTime),
                            color = LiveDesign.muted,
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier.width(40.dp),
                        )
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
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            conformedLabel(duration),
                            color = LiveDesign.muted,
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier.width(40.dp),
                        )
                    }
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        MediaTransportSkipButton("−15", "Back 15 seconds") { seekBy(-15f) }
                        if (reachedEnd) {
                            MediaTransportIconButton(OpcIcon.ROTATE_CW, "Restart", primary = true, onClick = {
                                player.seekTo(0)
                                applyPlaybackRate()
                                player.play()
                                reachedEnd = false
                                isPlaying = true
                            })
                        } else {
                            MediaTransportIconButton(
                                if (isPlaying) OpcIcon.PAUSE else OpcIcon.PLAY,
                                if (isPlaying) "Pause" else "Play",
                                primary = true,
                                onClick = {
                                    if (isPlaying) {
                                        player.pause()
                                    } else {
                                        applyPlaybackRate()
                                        player.play()
                                    }
                                },
                            )
                        }
                        MediaTransportSkipButton("+15", "Forward 15 seconds") { seekBy(15f) }
                        Row(
                            Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.End),
                        ) {
                            Spacer(Modifier.width(6.dp))
                            MediaTransportIconButton(
                                if (isMuted) OpcIcon.VOLUME_X else OpcIcon.VOLUME_2,
                                if (isMuted) "Unmute" else "Mute",
                                action = true,
                                highlighted = isMuted,
                                onClick = { isMuted = !isMuted },
                            )
                            PlaybackConformButton(
                                availability = conformAvailability,
                                captureRate = conformSource.captureRate ?: 0.0,
                                selected = conformTarget,
                                menuOpen = conformMenu,
                                onMenuOpenChange = { conformMenu = it },
                                onSelect = { conformTarget = it },
                            )
                            MediaTransportIconButton(
                                PlaybackChromeMetrics.hideChromeIcon,
                                "Hide playback controls",
                                action = true,
                                onClick = { chromeVisible = false },
                            )
                            MediaTransportIconButton(
                                PlaybackChromeMetrics.viewAssistIcon,
                                "View Assist",
                                action = true,
                                highlighted = assistMode || anyPlaybackAssistOn,
                                onClick = { assistMode = true },
                            )
                            if (controller.canDelete(active)) {
                                MediaTransportIconButton(OpcIcon.TRASH, "Delete", action = true, onClick = { confirmDelete = true })
                            }
                            MediaTransportIconButton(
                                OpcIcon.SHARE,
                                "Share clip",
                                action = true,
                                onClick = {
                                    player.pause()
                                    onDeliver(active)
                                },
                            )
                        }
                    }
                }
                }
            } else {
                Box(
                    Modifier
                        .align(Alignment.BottomEnd)
                        .navigationBarsPadding()
                        .padding(16.dp),
                ) {
                    MediaCircleIconButton(
                        icon = PlaybackChromeMetrics.showChromeIcon,
                        contentDescription = "Show playback controls",
                        onClick = { chromeVisible = true },
                    )
                }
            }
            }
            }
        }

        val chromeWidth = LocalConfiguration.current.screenWidthDp.dp
        val configure = assist.configureTool
        if (configure != null) {
            Popup(
                alignment = Alignment.BottomCenter,
                properties = PopupProperties(focusable = false, clippingEnabled = false),
            ) {
            Box(
                Modifier
                    .width(chromeWidth)
                    .chromeClickable(onClick = { assist.configureTool = null }),
                contentAlignment = Alignment.BottomCenter,
            ) {
                AssistOptionsPopup(
                    tool = configure,
                    state = assist,
                    onDismiss = { assist.configureTool = null },
                    maxHeightDp = 420f,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 88.dp),
                    model = model,
                    colorMode =
                        PlaybackLutColor.resolve(
                            clip = clipColorMode,
                            live = status.colorMode,
                            last = OperatorPrefs.lastMonitorColorMode(context),
                        ),
                )
            }
            }
        }

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
                fontFamily = FontFamily.Monospace,
            )
            Text(
                "/ ${MediaClipFormatting.durationLabel(durationSeconds.toDouble())}",
                color = LiveDesign.muted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                fontFamily = FontFamily.Monospace,
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
) {
    val density = LocalDensity.current
    val panelW = with(density) { AudioAssist.PANEL_WIDTH_DP.dp.toPx() }
    val panelH = with(density) { AudioAssist.PANEL_HEIGHT_DP.dp.toPx() }
    val cx = min(video.maxX - 22f, canvas.maxX - 28f)
    val cy = min(video.maxY - 96f, canvas.maxY - 120f)
    Box(
        Modifier
            .offset { IntOffset((cx - panelW / 2f).roundToInt(), (cy - panelH / 2f).roundToInt()) }
            .size(AudioAssist.PANEL_WIDTH_DP.dp, AudioAssist.PANEL_HEIGHT_DP.dp)
            .scopePanelChrome(),
    ) {
        AudioMetersPanel(left = left.asReading(), right = right.asReading(), sensitivity = null)
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
            .size(32.dp)
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
        MediaTransportIconButton(
            OpcIcon.TIMER,
            "Conform preview",
            action = true,
            enabled = availability.isAvailable,
            highlighted = selected != null,
            onClick = { onMenuOpenChange(true) },
        )
        DropdownMenu(
            expanded = menuOpen,
            onDismissRequest = { onMenuOpenChange(false) },
            containerColor = LiveDesign.surface,
        ) {
            Text(
                ConformPreview.menuHeader(captureRate),
                color = LiveDesign.muted,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            )
            DropdownMenuItem(
                text = { Text("Real time", color = LiveDesign.text) },
                onClick = {
                    onSelect(null)
                    onMenuOpenChange(false)
                },
                trailingIcon = {
                    if (selected == null) {
                        OpcIcon(OpcIcon.CHECK, contentDescription = null, tint = LiveDesign.accent)
                    }
                },
            )
            for (target in availability.targets) {
                DropdownMenuItem(
                    text = {
                        Text(ConformPreview.targetLabel(captureRate, target), color = LiveDesign.text)
                    },
                    onClick = {
                        onSelect(target)
                        onMenuOpenChange(false)
                    },
                    trailingIcon = {
                        if (selected == target) {
                            OpcIcon(OpcIcon.CHECK, contentDescription = null, tint = LiveDesign.accent)
                        }
                    },
                )
            }
            val reason = availability.unavailableReason
            if (reason != null) {
                HorizontalDivider(color = LiveDesign.hairline)
                DropdownMenuItem(
                    text = { Text(reason, color = LiveDesign.muted) },
                    enabled = false,
                    onClick = {},
                )
            } else if (selected != null) {
                HorizontalDivider(color = LiveDesign.hairline)
                DropdownMenuItem(
                    text = { Text(ConformPreview.audioLabel, color = LiveDesign.muted) },
                    enabled = false,
                    onClick = {},
                )
            }
        }
    }
}
