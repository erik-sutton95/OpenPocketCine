@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.TextureView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CropFree
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Timelapse
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
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
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.assists.AssistOptionsPopup
import com.opencapture.openpocketcine.assists.LiveAssistLayer
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.assists.MirrorAssist
import com.opencapture.openpocketcine.assists.PlaybackAssistBar
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.panelGlass
import com.opencapture.openpocketcine.session.CameraStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.max
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
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var confirmDelete by remember { mutableStateOf(false) }
    val favorite = controller.isFavorite(file)

    LaunchedEffect(file.id) {
        loading = true
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

    Box(Modifier.fillMaxSize().background(LiveDesign.feedWell)) {
        val image = bitmap
        if (image != null) {
            Image(
                image.asImageBitmap(),
                contentDescription = file.filename,
                contentScale = ContentScale.Fit,
                modifier =
                    Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            scaleX = scale
                            scaleY = scale
                            translationX = offset.x
                            translationY = offset.y
                        }
                        .pointerInput(Unit) {
                            detectTransformGestures { _, pan, zoom, _ ->
                                val next = (scale * zoom).coerceIn(1f, 4f)
                                scale = next
                                offset = if (next > 1.05f) offset + pan else Offset.Zero
                            }
                        },
            )
        } else if (loading) {
            Column(
                Modifier
                    .align(Alignment.Center)
                    .clip(MediaCornerShape)
                    .panelGlass(MediaCornerShape)
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator(color = LiveDesign.accent)
                Text("Preparing image…", color = LiveDesign.muted, style = LiveType.ui(14f, FontWeight.Medium))
            }
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
                MediaCircleIconButton(Icons.Filled.Delete, "Delete", onClick = { confirmDelete = true })
            }
            MediaCircleIconButton(Icons.Filled.Share, "Share photo", onClick = { onDeliver(file) })
        }

        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 18.dp),
        ) {
            FavoriteStar(favorite) { controller.toggleFavorite(file) }
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
    val favorite = controller.isFavorite(active)
    val progress = controller.downloadProgress[active.path]
    val context = LocalContext.current
    val density = LocalDensity.current
    val anyPlaybackAssistOn = assist.playbackVisibleTools.isNotEmpty()
    val conformSpeed =
        run {
            val target = conformTarget
            val rate = conformSource.captureRate
            if (target == null || rate == null) 1.0 else ConformPreview.speed(rate, target)
        }
    val conformAvailability = ConformPreview.availability(conformSource)

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
            ExoPlayer.Builder(context).build().apply {
                playWhenReady = true
            }
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
                    }
                }
            }
        player.addListener(listener)
        onDispose {
            assist.configureTool = null
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
        applyListedGeometry()
        player.stop()
        player.clearMediaItems()
        val local =
            controller.localPlaybackFile(active)
                ?: controller.cacheForPlayback(active)
        if (local == null) {
            loadError =
                if (controller.isLive) MediaOperatorCopy.CLIP_OPEN_FAILED
                else MediaOperatorCopy.CLIP_NOT_CACHED
            return@LaunchedEffect
        }
        player.setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(local)))
        player.prepare()
        applyPlaybackRate()
        player.playWhenReady = true
        isPlaying = true
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

    fun seekBy(delta: Float) {
        val target = (currentTime + delta).coerceIn(0f, max(duration, 0f))
        player.seekTo((target * 1000).toLong())
        currentTime = target
        if (reachedEnd && target + 0.05f < duration) reachedEnd = false
    }

    Box(Modifier.fillMaxSize().background(LiveDesign.feedWell)) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val container =
                PlaybackVideoLayout.Rect(0f, 0f, constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
            val fitted =
                PlaybackVideoLayout.aspectFitRect(
                    PlaybackVideoLayout.Size(videoWidth, videoHeight),
                    container,
                )
            Box(
                Modifier
                    .offset { IntOffset(fitted.x.roundToInt(), fitted.y.roundToInt()) }
                    .size(
                        with(density) { fitted.width.toDp() },
                        with(density) { fitted.height.toDp() },
                    ),
            ) {
                AndroidView(
                    factory = { ctx ->
                        TextureView(ctx).also { view ->
                            player.setVideoTextureView(view)
                        }
                    },
                    update = { view -> player.setVideoTextureView(view) },
                    modifier =
                        Modifier
                            .fillMaxSize()
                            .graphicsLayer {
                                scaleX = MirrorAssist.feedScaleX(assist.isPlaybackVisible(LiveAssistTool.MIRROR))
                            }
                            .pointerInput(ready, reachedEnd, isPlaying) {
                                detectTapGestures {
                                    if (!ready) return@detectTapGestures
                                    when (PlaybackFrameTap.action(chromeVisible, reachedEnd)) {
                                        PlaybackFrameTap.RESTART_PLAYBACK -> {
                                            player.seekTo(0)
                                            applyPlaybackRate()
                                            player.play()
                                            reachedEnd = false
                                            isPlaying = true
                                        }
                                        PlaybackFrameTap.TOGGLE_TRANSPORT -> {
                                            if (isPlaying) player.pause() else {
                                                applyPlaybackRate()
                                                player.play()
                                            }
                                        }
                                        PlaybackFrameTap.IGNORE -> Unit
                                    }
                                }
                            },
                )
                LiveAssistLayer(
                    state = assist,
                    status = CameraStatus(),
                    focus = null,
                    playback = true,
                    modifier = Modifier.fillMaxSize(),
                )
                if (playlist.size > 1) {
                    if (canPrev) {
                        ClipNavButton(
                            icon = Icons.Filled.ChevronLeft,
                            label = "Previous clip",
                            modifier = Modifier.align(Alignment.CenterStart).padding(start = 12.dp),
                        ) { active = playlist[index - 1] }
                    }
                    if (canNext) {
                        ClipNavButton(
                            icon = Icons.Filled.ChevronRight,
                            label = "Next clip",
                            modifier = Modifier.align(Alignment.CenterEnd).padding(end = 12.dp),
                        ) { active = playlist[index + 1] }
                    }
                }
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
                        .panelGlass(MediaCornerShape)
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
            Column(
                Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 14.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MediaBackButton(onClick = onClose, size = 34.dp)
                    Text(
                        active.filename,
                        color = LiveDesign.text,
                        style = LiveType.ui(14f, FontWeight.SemiBold),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    MediaCircleIconButton(
                        icon = if (favorite) Icons.Filled.Star else Icons.Outlined.StarOutline,
                        contentDescription = if (favorite) "Remove from favorites" else "Add to favorites",
                        onClick = { controller.toggleFavorite(active) },
                        tint = if (favorite) LiveDesign.accent else LiveDesign.text,
                        highlighted = favorite,
                    )
                }
                Spacer(Modifier.weight(1f))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(MediaCornerShape)
                        .panelGlass(MediaCornerShape)
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
                                Icons.Filled.CropFree,
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
                                onScrubbingChanged = { scrubbing = it },
                                onProgressChange = { currentTime = it },
                                onSeek = {
                                    currentTime = it
                                    player.seekTo((it * 1000).toLong())
                                    if (reachedEnd && it + 0.05f < duration) reachedEnd = false
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
                                MediaTransportIconButton(Icons.Filled.Replay, "Restart", primary = true, onClick = {
                                    player.seekTo(0)
                                    applyPlaybackRate()
                                    player.play()
                                    reachedEnd = false
                                    isPlaying = true
                                })
                            } else {
                                MediaTransportIconButton(
                                    if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
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
                                    if (isMuted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp,
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
                                    Icons.Filled.Fullscreen,
                                    "Hide playback controls",
                                    action = true,
                                    onClick = { chromeVisible = false },
                                )
                                MediaTransportIconButton(
                                    Icons.Filled.CropFree,
                                    "View Assist",
                                    action = true,
                                    highlighted = assistMode || anyPlaybackAssistOn,
                                    onClick = { assistMode = true },
                                )
                                if (controller.canDelete(active)) {
                                    MediaTransportIconButton(Icons.Filled.Delete, "Delete", action = true, onClick = { confirmDelete = true })
                                }
                                MediaTransportIconButton(
                                    Icons.Filled.Share,
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
            }
        } else {
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .navigationBarsPadding()
                    .padding(16.dp),
            ) {
                MediaCircleIconButton(
                    icon = Icons.Filled.FullscreenExit,
                    contentDescription = "Show playback controls",
                    onClick = { chromeVisible = true },
                )
            }
        }

        val configure = assist.configureTool
        if (configure != null) {
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

@Composable
private fun ClipNavButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(32.dp)
            .clip(CircleShape)
            .panelGlass(CircleShape)
            .chromeClickable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = LiveDesign.accent, modifier = Modifier.size(13.dp))
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
            Icons.Filled.Timelapse,
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
                        Icon(Icons.Filled.Check, contentDescription = null, tint = LiveDesign.accent)
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
                            Icon(Icons.Filled.Check, contentDescription = null, tint = LiveDesign.accent)
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
