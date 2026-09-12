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
fun MediaClipCell(file: MediaFile, controller: MediaLibraryController, onOpen: () -> Unit,
    isSelecting: Boolean = false, isSelected: Boolean = false,
    onBeginSelection: (() -> Unit)? = null, onToggleSelection: (() -> Unit)? = null) =
    MediaCatalogClip(file, controller, onOpen, false, isSelecting, isSelected, onBeginSelection, onToggleSelection)

@Composable
fun MediaClipListRow(file: MediaFile, controller: MediaLibraryController, onOpen: () -> Unit,
    isSelecting: Boolean = false, isSelected: Boolean = false,
    onBeginSelection: (() -> Unit)? = null, onToggleSelection: (() -> Unit)? = null) =
    MediaCatalogClip(file, controller, onOpen, true, isSelecting, isSelected, onBeginSelection, onToggleSelection)

/** The adapter owns cache lookup and bounded thumbnail IO; shared UI owns both renderers. */
@Composable
private fun MediaCatalogClip(file: MediaFile, controller: MediaLibraryController, onOpen: () -> Unit,
    list: Boolean, isSelecting: Boolean, isSelected: Boolean,
    onBeginSelection: (() -> Unit)?, onToggleSelection: (() -> Unit)?) {
    var thumbnail by remember(file.id) { mutableStateOf<Bitmap?>(null) }
    var duration by remember(file.id) { mutableStateOf<String?>(null) }
    LaunchedEffect(file.id, controller.thumbnailFile(file)?.path, list) {
        thumbnail = MediaThumbs.load(file, controller, maxPx = if (list) 480 else 640)
        duration = MediaThumbs.durationLabel(file, controller)
    }
    val grade = controller.cacheGrade(file)
    val source = if (grade == MediaCacheGrade.ORIGINAL) "CACHED" else if (grade.isProxyOnly) "PROXY" else "ON CAMERA"
    val clip = com.opencapture.monitorui.MonitorClipValue(file.id, file.filename,
        listOfNotNull(file.resolution, file.fileExtension.uppercase()).joinToString(" · "),
        duration, source, controller.isFavorite(file), controller.downloadProgress[file.path]?.toFloat())
    com.opencapture.monitorui.MonitorClipCard(clip, list, isSelecting, isSelected,
        onOpen = onOpen,
        onSelect = { if (isSelecting) onToggleSelection?.invoke() else onBeginSelection?.invoke() },
        onFavorite = { controller.toggleFavorite(file) }) {
        val bitmap = thumbnail
        if (bitmap != null) Image(bitmap.asImageBitmap(), contentDescription = null,
            contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        else OpcIcon(if (file.kind == MediaKind.PHOTO) OpcIcon.IMAGE else OpcIcon.FILM, null,
            Modifier.size(if (list) 20.dp else 28.dp).align(Alignment.Center), LiveDesign.faint)
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
            tint = if (favorite) Color(0xFFE9C35A) else LiveDesign.faint,
            modifier = Modifier.size(iconSize),
            filled = favorite,
        )
    }
}

@Composable
fun SelectionMarker(selected: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(22.dp)
            .background(
                if (selected) LiveDesign.accent else Color.Black.copy(alpha = 0.56f),
                CircleShape,
            ),
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(if (selected) OpcIcon.CHECK else OpcIcon.CIRCLE, null, Modifier.size(12.dp),
            if (selected) LiveDesign.background else LiveDesign.text)
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
