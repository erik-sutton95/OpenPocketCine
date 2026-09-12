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
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
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
import androidx.compose.ui.layout.onSizeChanged
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
    var infoOpen by remember { mutableStateOf(false) }
    val photoConfig = LocalConfiguration.current
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

        com.opencapture.monitorui.MonitorPlaybackHeader(file.filename,
            listOfNotNull(file.resolution, file.fileExtension).joinToString(" · "),
            if (controller.isDownloaded(file)) "ORIGINAL" else "PREVIEW",
            photoConfig.screenHeightDp > photoConfig.screenWidthDp,
            Modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 14.dp),
            back = { MediaTransportIconButton(OpcIcon.CHEVRON_LEFT, "Back to media", action = true, onClick = onClose) },
            actions = {
                MediaTransportIconButton(OpcIcon.INFO, "Photo info", action = true, highlighted = infoOpen, onClick = { infoOpen = !infoOpen })
                MediaTransportIconButton(OpcIcon.STAR, "Favorite photo", action = true, highlighted = favorite,
                    onClick = { controller.toggleFavorite(file) })
                if (controller.canDelete(file)) MediaTransportIconButton(OpcIcon.TRASH, "Delete photo", action = true, onClick = { confirmDelete = true })
                MediaTransportIconButton(OpcIcon.SHARE, "Share photo", action = true, onClick = { onDeliver(file) })
            })
        if (infoOpen) {
            Box(Modifier.fillMaxSize().chromeClickable { infoOpen = false }) {
                com.opencapture.monitorui.MonitorMetadataDrawer(
                    listOf(com.opencapture.monitorui.MonitorMetadataRow("File", file.filename),
                        com.opencapture.monitorui.MonitorMetadataRow("Resolution", file.resolution.orEmpty()),
                        com.opencapture.monitorui.MonitorMetadataRow("Format", file.fileExtension),
                        com.opencapture.monitorui.MonitorMetadataRow("Source", if (controller.isDownloaded(file)) "Original" else "Preview"),
                        com.opencapture.monitorui.MonitorMetadataRow("Size", MediaClipFormatting.byteLabel(file.sizeBytes))),
                    Modifier.align(Alignment.CenterEnd).statusBarsPadding().navigationBarsPadding().chromeClickable { },
                    close = { MediaTransportIconButton(OpcIcon.X, "Close photo info", action = true, onClick = { infoOpen = false }) })
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
    var ready by remember { mutableStateOf(false) }
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
    val playbackConfiguration = LocalConfiguration.current
    val portraitPlayback = playbackConfiguration.screenHeightDp > playbackConfiguration.screenWidthDp
    var footerHeightPx by remember { mutableIntStateOf(0) }
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
                    sourceIdentity = active.id,
                    sourceReady = ready,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            Popup(
                alignment = Alignment.TopStart,
                onDismissRequest = {
                    when {
                        assist.configureTool != null -> assist.configureTool = null
                        infoOpen -> infoOpen = false
                        else -> onClose()
                    }
                },
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
                com.opencapture.monitorui.MonitorPlaybackHeader(
                    title = active.filename,
                    subtitle = listOfNotNull(active.resolution, active.fps?.let { "${it}p" }, active.fileExtension).joinToString(" · "),
                    source = playbackSource, portrait = portraitPlayback,
                    modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(horizontal = 14.dp, vertical = 12.dp),
                    back = { MediaBackButton(onClose, size = 37.dp) },
                    actions = {
                        MediaTransportIconButton(OpcIcon.INFO, "Clip info", action = true, highlighted = infoOpen, onClick = { infoOpen = !infoOpen })
                        MediaFavoriteButton(favorite, size = 37.dp) { controller.toggleFavorite(active) }
                        if (controller.canDelete(active)) MediaTransportIconButton(OpcIcon.TRASH, "Delete clip", action = true, onClick = { confirmDelete = true })
                        MediaTransportIconButton(OpcIcon.SHARE, "Share clip", action = true, onClick = { player.pause(); onDeliver(active) })
                    },
                )
                com.opencapture.monitorui.MonitorPlaybackFooter(
                    position = conformedLabel(currentTime), duration = conformedLabel(duration), portrait = portraitPlayback,
                    modifier = Modifier.align(Alignment.BottomCenter).width(overlayWidth)
                        .onSizeChanged { footerHeightPx = it.height }.navigationBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
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
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            MediaTransportIconButton(OpcIcon.SKIP_BACK, "Previous clip", enabled = canPrev, onClick = { goToAdjacent(-1) })
                            MediaTransportSkipButton("−15", "Back 15 seconds") { seekBy(-15f) }
                            MediaTransportIconButton(if (reachedEnd) OpcIcon.ROTATE_CW else if (isPlaying) OpcIcon.PAUSE else OpcIcon.PLAY,
                                if (reachedEnd) "Restart" else if (isPlaying) "Pause" else "Play", primary = true, onClick = {
                                    if (reachedEnd) { player.seekTo(0); reachedEnd = false; applyPlaybackRate(); player.play() }
                                    else if (isPlaying) player.pause() else { applyPlaybackRate(); player.play() }
                                })
                            MediaTransportSkipButton("+15", "Forward 15 seconds") { seekBy(15f) }
                            MediaTransportIconButton(OpcIcon.SKIP_FORWARD, "Next clip", enabled = canNext, onClick = { goToAdjacent(1) })
                        }
                    },
                    options = {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            MediaTransportIconButton(if (isMuted) OpcIcon.VOLUME_X else OpcIcon.VOLUME_2,
                                if (isMuted) "Unmute" else "Mute", action = true, highlighted = isMuted, onClick = { isMuted = !isMuted })
                            MediaTransportIconButton(OpcIcon.REPEAT, "Loop clip", action = true, highlighted = looping, onClick = { looping = !looping })
                            PlaybackConformButton(conformAvailability, conformSource.captureRate ?: 0.0, conformTarget,
                                conformMenu, { conformMenu = it }, { conformTarget = it })
                            MediaTransportIconButton(PlaybackChromeMetrics.hideChromeIcon, "Hide playback controls",
                                action = true, onClick = { chromeVisible = false })
                        }
                    },
                )
                com.opencapture.openpocketcine.assists.MonitorAssistCluster(
                    portrait = portraitPlayback, locked = false,
                    isOn = assist::isPlaybackVisible, onToggle = { assist.togglePlayback(it) },
                    onLongPress = { assist.configureTool = it },
                    requestExpand = assistMode, onExpansionHandled = { assistMode = false },
                    modifier = Modifier.align(Alignment.BottomStart)
                        .padding(start = 14.dp, bottom = with(density) { footerHeightPx.toDp() } + 8.dp),
                )
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
                        modifier = Modifier.align(Alignment.CenterEnd).statusBarsPadding().navigationBarsPadding().chromeClickable { },
                        close = { MediaCircleIconButton(OpcIcon.X, "Close clip info", { infoOpen = false }, size = 34.dp) })
                }
            }

            val reviewConfiguration = LocalConfiguration.current
            val configure = assist.configureTool
            if (configure != null) {
                com.opencapture.openpocketcine.assists.MonitorAssistInspector(
                    configure, assist, model,
                    PlaybackLutColor.resolve(clip = clipColorMode, live = status.colorMode,
                        last = OperatorPrefs.lastMonitorColorMode(context)),
                    reviewConfiguration.screenWidthDp.toFloat(), reviewConfiguration.screenHeightDp.toFloat(),
                    0f, 0f, 0f, (reviewConfiguration.screenHeightDp - 120).toFloat(),
                    onDismiss = { assist.configureTool = null }, playback = true,
                )
            }

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
                    .background(Color(0xFF141618).copy(alpha = .62f)).navigationBarsPadding()
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
                    com.opencapture.monitorui.MonitorValueDrum(labels,
                        if (selected == null) "Real time" else ConformPreview.targetLabel(captureRate, selected)) { label ->
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
