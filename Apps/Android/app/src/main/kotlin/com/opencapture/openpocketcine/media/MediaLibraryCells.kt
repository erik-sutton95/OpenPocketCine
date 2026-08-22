package com.opencapture.openpocketcine.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.chromeClickable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun MediaClipCell(
    file: MediaFile,
    controller: MediaLibraryController,
    onOpen: () -> Unit,
    isSelecting: Boolean = false,
    isSelected: Boolean = false,
    onBeginSelection: (() -> Unit)? = null,
    onToggleSelection: (() -> Unit)? = null,
) {
    val downloaded = controller.isDownloaded(file)
    val progress = controller.downloadProgress[file.path]
    val favorite = controller.isFavorite(file)
    val isPhoto = file.kind == MediaKind.PHOTO
    var thumb by remember(file.id) { mutableStateOf<Bitmap?>(null) }
    var duration by remember(file.id) { mutableStateOf<String?>(null) }
    LaunchedEffect(file.id, controller.thumbnailFile(file)?.path) {
        thumb = MediaThumbs.load(file, controller, maxPx = 640)
        duration = MediaThumbs.durationLabel(file, controller)
    }
    val interaction =
        if (isSelecting) {
            Modifier.chromeClickable(onClick = { onToggleSelection?.invoke() ?: onOpen() })
        } else {
            Modifier.chromeClickable(
                onClick = onOpen,
                onLongClick = { onBeginSelection?.invoke() },
            )
        }
    Column(
        Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = file.filename
                role = Role.Button
            }
            .then(interaction),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f)
                .clip(MediaCornerShape)
                .background(LiveDesign.surface)
                .border(
                    if (isSelected) 2.dp else 1.dp,
                    if (isSelected) LiveDesign.accent else LiveDesign.hairline,
                    MediaCornerShape,
                ),
        ) {
            val bitmap = thumb
            if (bitmap != null) {
                Image(
                    bitmap.asImageBitmap(),
                    contentDescription = file.filename,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                OpcIcon(
                    icon = if (isPhoto) OpcIcon.IMAGE else OpcIcon.FILM,
                    contentDescription = null,
                    tint = LiveDesign.faint,
                    modifier = Modifier.size(28.dp).align(Alignment.Center),
                )
            }
            when {
                progress != null -> {
                    Box(
                        Modifier.fillMaxSize().background(LiveDesign.feedWell.copy(alpha = 0.45f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                "${(progress * 100).toInt()}%",
                                color = LiveDesign.text,
                                fontSize = 11.sp,
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Bold,
                            )
                            MediaGlassTrack(
                                fraction = progress.toFloat(),
                                modifier = Modifier.padding(top = 6.dp),
                                trackWidth = 120.dp,
                            )
                        }
                    }
                }
                !downloaded -> {
                    Box(
                        Modifier.fillMaxSize().background(LiveDesign.feedWell.copy(alpha = 0.35f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            OpcIcon(
                                icon = if (isPhoto) OpcIcon.IMAGE else OpcIcon.CIRCLE_PLAY,
                                contentDescription = null,
                                tint = LiveDesign.text,
                                modifier = Modifier.size(26.dp),
                            )
                            Text(
                                "On camera",
                                color = LiveDesign.text,
                                style = LiveType.ui(10f, FontWeight.SemiBold),
                            )
                        }
                    }
                }
                !isPhoto -> {
                    OpcIcon(
                        icon = OpcIcon.CIRCLE_PLAY,
                        contentDescription = null,
                        tint = LiveDesign.text.copy(alpha = 0.9f),
                        modifier = Modifier.align(Alignment.BottomStart).padding(8.dp).size(22.dp),
                    )
                }
            }
            if (!isPhoto && duration != null && progress == null && !isSelecting) {
                MediaBadge(
                    duration!!,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(8.dp),
                )
            }
            if (isSelecting) {
                SelectionMarker(selected = isSelected, modifier = Modifier.align(Alignment.TopEnd).padding(8.dp))
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                file.filename,
                color = LiveDesign.text,
                style = LiveType.ui(12f, FontWeight.Medium),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            FavoriteStar(favorite) { controller.toggleFavorite(file) }
        }
    }
}

@Composable
fun MediaClipListRow(
    file: MediaFile,
    controller: MediaLibraryController,
    onOpen: () -> Unit,
    isSelecting: Boolean = false,
    isSelected: Boolean = false,
    onBeginSelection: (() -> Unit)? = null,
    onToggleSelection: (() -> Unit)? = null,
) {
    val downloaded = controller.isDownloaded(file)
    val progress = controller.downloadProgress[file.path]
    val favorite = controller.isFavorite(file)
    val isPhoto = file.kind == MediaKind.PHOTO
    var thumb by remember(file.id) { mutableStateOf<Bitmap?>(null) }
    var duration by remember(file.id) { mutableStateOf<String?>(null) }
    LaunchedEffect(file.id, controller.thumbnailFile(file)?.path) {
        thumb = MediaThumbs.load(file, controller, maxPx = 480)
        duration = MediaThumbs.durationLabel(file, controller)
    }
    val meta = MediaClipPresentation.metadataLine(file, duration)
    val line =
        meta.ifEmpty {
            if (downloaded) "Cached" else "On camera"
        }
    val interaction =
        if (isSelecting) {
            Modifier.chromeClickable(onClick = { onToggleSelection?.invoke() ?: onOpen() })
        } else {
            Modifier.chromeClickable(
                onClick = onOpen,
                onLongClick = { onBeginSelection?.invoke() },
            )
        }
    Row(
        Modifier
            .fillMaxWidth()
            .clip(MediaCornerShape)
            .background(
                if (isSelected) LiveDesign.accentDim.copy(alpha = 0.55f) else LiveDesign.surface.copy(alpha = 0.45f),
                MediaCornerShape,
            )
            .border(
                1.dp,
                if (isSelected) LiveDesign.accent.copy(alpha = 0.45f) else LiveDesign.hairline,
                MediaCornerShape,
            )
            .semantics {
                contentDescription = file.filename
                role = Role.Button
            }
            .then(interaction)
            .padding(start = 12.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .width(96.dp)
                .height(54.dp)
                .clip(MediaCornerShape)
                .background(LiveDesign.surface)
                .border(1.dp, LiveDesign.hairline, MediaCornerShape),
        ) {
            val bitmap = thumb
            if (bitmap != null) {
                Image(
                    bitmap.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                OpcIcon(
                    icon = if (isPhoto) OpcIcon.IMAGE else OpcIcon.FILM,
                    contentDescription = null,
                    tint = LiveDesign.faint,
                    modifier = Modifier.size(20.dp).align(Alignment.Center),
                )
            }
            when {
                progress != null -> {
                    Box(
                        Modifier.fillMaxSize().background(LiveDesign.feedWell.copy(alpha = 0.45f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "${(progress * 100).toInt()}%",
                            color = LiveDesign.text,
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
                !downloaded -> {
                    OpcIcon(
                        icon = if (isPhoto) OpcIcon.IMAGE else OpcIcon.CIRCLE_PLAY,
                        contentDescription = null,
                        tint = LiveDesign.text.copy(alpha = 0.9f),
                        modifier = Modifier.size(18.dp).align(Alignment.Center),
                    )
                }
            }
            if (isSelecting) {
                SelectionMarker(selected = isSelected, modifier = Modifier.align(Alignment.TopEnd).padding(4.dp))
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                file.filename,
                color = LiveDesign.text,
                style = LiveType.ui(13f, FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                line,
                color = LiveDesign.muted,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
            )
        }
        if (!isSelecting) {
            FavoriteStar(favorite, iconSize = 14.dp) { controller.toggleFavorite(file) }
        }
    }
}

@Composable
fun FavoriteStar(
    favorite: Boolean,
    iconSize: androidx.compose.ui.unit.Dp = 13.dp,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .size(44.dp)
            .chromeClickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(
            icon = OpcIcon.STAR,
            contentDescription = if (favorite) "Remove from favorites" else "Add to favorites",
            tint = if (favorite) LiveDesign.accent else LiveDesign.faint,
            modifier = Modifier.size(iconSize),
            filled = favorite,
        )
    }
}

@Composable
fun SelectionMarker(selected: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(30.dp)
            .background(
                if (selected) LiveDesign.accent else Color.Black.copy(alpha = 0.56f),
                CircleShape,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (selected) "✓" else "○",
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = if (selected) LiveDesign.background else LiveDesign.text,
        )
    }
}

object MediaThumbs {
    suspend fun load(file: MediaFile, controller: MediaLibraryController, maxPx: Int): Bitmap? =
        withContext(Dispatchers.IO) {
            decode(controller.thumbnailFile(file), maxPx)?.let { return@withContext it }
            if (file.kind == MediaKind.PHOTO && controller.isDownloaded(file)) {
                decode(controller.localFile(file), maxPx)?.let { return@withContext it }
            }
            controller.ensureThumbnail(file)
            decode(controller.thumbnailFile(file), maxPx)?.let { return@withContext it }
            if (controller.isLive) {
                runCatching {
                    val storage = file.storage
                    val data = MediaTransfer.fetchBytes(storage, file.thumbPath).first
                    if (data.isNotEmpty()) {
                        controller.thumbnailFile(file)
                        decodeBytes(data, maxPx)
                    } else {
                        null
                    }
                }.getOrNull()?.let { return@withContext it }
            }
            if (file.kind == MediaKind.VIDEO && controller.isDownloaded(file)) {
                frameGrab(controller.localFile(file), maxPx)
            } else {
                null
            }
        }

    suspend fun durationLabel(file: MediaFile, controller: MediaLibraryController): String? {
        if (file.kind != MediaKind.VIDEO) return null
        if (file.durationSeconds > 0) return MediaClipFormatting.durationLabel(file.durationSeconds)
        val local = controller.localFile(file) ?: return null
        return withContext(Dispatchers.IO) {
            val retriever = MediaMetadataRetriever()
            runCatching {
                retriever.setDataSource(local.absolutePath)
                val ms = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                ms?.let { MediaClipFormatting.durationLabel((it / 1000L).toInt()) }
            }.getOrNull().also { retriever.release() }
        }
    }

    private fun decode(file: File?, maxPx: Int): Bitmap? {
        if (file == null) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maxPx) }
        return BitmapFactory.decodeFile(file.absolutePath, options)
    }

    private fun decodeBytes(data: ByteArray, maxPx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maxPx) }
        return BitmapFactory.decodeByteArray(data, 0, data.size, options)
    }

    private fun frameGrab(file: File?, maxPx: Int): Bitmap? {
        if (file == null) return null
        val retriever = MediaMetadataRetriever()
        return runCatching {
            retriever.setDataSource(file.absolutePath)
            retriever.getFrameAtTime(200_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        }.getOrNull().also { retriever.release() }
    }

    private fun sampleSize(w: Int, h: Int, maxPx: Int): Int {
        if (w <= 0 || h <= 0) return 1
        var sample = 1
        val longest = maxOf(w, h)
        while (longest / sample > maxPx) sample *= 2
        return sample
    }
}
