package com.opencapture.openpocketcine.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.TextureView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.max

@Composable
fun MediaPhotoViewer(
    file: MediaFile,
    controller: MediaLibraryController,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
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
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
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
                CircleAction(Icons.Filled.Delete, "Delete") { confirmDelete = true }
            }
            CircleAction(Icons.Filled.Share, "Share photo") {
                scope.launch {
                    val local = controller.cacheForPlayback(file) ?: controller.localFile(file) ?: return@launch
                    MediaShare.shareCachedFile(context, local, MediaHTTP.playbackMIMEType(file.path))
                }
            }
        }

        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 18.dp),
        ) {
            FavoriteStar(favorite) { controller.toggleFavorite(file) }
        }
    }

    if (confirmDelete) {
        DeleteConfirmDialog(
            title = "Delete this photo from the camera?",
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

@Composable
fun MediaPlayerScreen(
    files: List<MediaFile>,
    startingAt: MediaFile,
    controller: MediaLibraryController,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
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
    val favorite = controller.isFavorite(active)
    val progress = controller.downloadProgress[active.path]

    val player =
        remember {
            ExoPlayer.Builder(context).build().apply {
                playWhenReady = true
            }
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
            }
        player.addListener(listener)
        onDispose {
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
        player.volume = if (isMuted) 0f else 1f
        player.playWhenReady = true
        isPlaying = true
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
                    .pointerInput(ready, reachedEnd, isPlaying) {
                        detectTapGestures {
                            if (!ready) return@detectTapGestures
                            if (reachedEnd) {
                                player.seekTo(0)
                                player.play()
                                reachedEnd = false
                                isPlaying = true
                            } else if (isPlaying) {
                                player.pause()
                            } else {
                                player.play()
                            }
                        }
                    },
        )

        if (!ready || loadError != null) {
            Box(
                Modifier.fillMaxSize().background(LiveDesign.feedWell.copy(alpha = 0.72f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (loadError == null) {
                        if (progress != null && progress > 0 && progress < 1) {
                            LinearProgressIndicator(
                                progress = { progress.toFloat() },
                                modifier = Modifier.width(120.dp),
                                color = LiveDesign.accent,
                            )
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

        if (playlist.size > 1) {
            if (canPrev) {
                CircleAction(Icons.Filled.ChevronLeft, "Previous clip", modifier = Modifier.align(Alignment.CenterStart).padding(start = 12.dp)) {
                    active = playlist[index - 1]
                }
            }
            if (canNext) {
                CircleAction(Icons.Filled.ChevronRight, "Next clip", modifier = Modifier.align(Alignment.CenterEnd).padding(end = 12.dp)) {
                    active = playlist[index + 1]
                }
            }
        }

        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(
                    Modifier
                        .size(34.dp)
                        .mediaGlass(CircleShape)
                        .clickable(onClick = onClose),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = LiveDesign.text, modifier = Modifier.size(16.dp))
                }
                Text(
                    active.filename,
                    color = LiveDesign.text,
                    style = LiveType.ui(14f, FontWeight.SemiBold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Box(
                    Modifier
                        .size(34.dp)
                        .mediaGlass(CircleShape)
                        .clickable { controller.toggleFavorite(active) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (favorite) Icons.Filled.Star else Icons.Outlined.StarOutline,
                        contentDescription = if (favorite) "Remove from favorites" else "Add to favorites",
                        tint = if (favorite) LiveDesign.accent else LiveDesign.text,
                        modifier = Modifier.size(17.dp),
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            Column(
                Modifier
                    .fillMaxWidth()
                    .mediaGlass(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))
                    .padding(horizontal = 10.dp, vertical = 9.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        MediaClipFormatting.durationLabel(currentTime.toDouble()),
                        color = LiveDesign.muted,
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace,
                        modifier = Modifier.width(40.dp),
                    )
                    Slider(
                        value = if (duration > 0f) currentTime.coerceIn(0f, duration) else 0f,
                        onValueChange = {
                            scrubbing = true
                            currentTime = it
                            player.seekTo((it * 1000).toLong())
                        },
                        onValueChangeFinished = { scrubbing = false },
                        valueRange = 0f..max(duration, 0.1f),
                        modifier = Modifier.weight(1f).height(22.dp),
                        colors =
                            SliderDefaults.colors(
                                thumbColor = LiveDesign.accent,
                                activeTrackColor = LiveDesign.accent,
                                inactiveTrackColor = LiveDesign.hairline,
                            ),
                    )
                    Text(
                        MediaClipFormatting.durationLabel(duration.toInt()),
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
                    TransportLabel("−15", "Back 15 seconds") { seekBy(-15f) }
                    if (reachedEnd) {
                        TransportIcon(Icons.Filled.Replay, "Restart") {
                            player.seekTo(0)
                            player.play()
                            reachedEnd = false
                            isPlaying = true
                        }
                    } else {
                        TransportIcon(
                            if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            if (isPlaying) "Pause" else "Play",
                        ) {
                            if (isPlaying) player.pause() else player.play()
                        }
                    }
                    TransportLabel("+15", "Forward 15 seconds") { seekBy(15f) }
                    Spacer(Modifier.weight(1f))
                    TransportIcon(
                        if (isMuted) Icons.Filled.VolumeOff else Icons.Filled.VolumeUp,
                        if (isMuted) "Unmute" else "Mute",
                    ) {
                        isMuted = !isMuted
                        player.volume = if (isMuted) 0f else 1f
                    }
                    if (controller.canDelete(active)) {
                        TransportIcon(Icons.Filled.Delete, "Delete") { confirmDelete = true }
                    }
                    TransportIcon(Icons.Filled.Share, "Share clip") {
                        player.pause()
                        scope.launch {
                            val local =
                                controller.localPlaybackFile(active)
                                    ?: controller.cacheForPlayback(active)
                                    ?: return@launch
                            MediaShare.shareCachedFile(context, local, MediaHTTP.playbackMIMEType(active.path))
                        }
                    }
                }
            }
        }
    }

    if (confirmDelete) {
        DeleteConfirmDialog(
            title = "Delete this clip from the camera?",
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

@Composable
private fun CircleAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(34.dp)
            .mediaGlass(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = LiveDesign.text, modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun TransportLabel(
    text: String,
    label: String,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(width = 38.dp, height = 36.dp)
            .mediaGlass(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))
            .clickable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = LiveDesign.text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
    }
}

@Composable
private fun TransportIcon(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(width = 38.dp, height = 36.dp)
            .mediaGlass(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = LiveDesign.text, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun DeleteConfirmDialog(title: String, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, color = LiveDesign.text) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text("Delete", color = LiveDesign.rec, fontWeight = FontWeight.SemiBold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel", color = LiveDesign.muted) }
        },
        containerColor = LiveDesign.surface,
    )
}
