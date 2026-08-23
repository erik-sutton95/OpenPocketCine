package com.opencapture.openpocketcine.media

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.chromeClickable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

enum class MediaDeliveryDestination(
    val title: String,
    val subtitle: String,
    val actionTitle: String,
) {
    NATIVE_SHARE(
        title = "Share",
        subtitle = "Nearby Share, Files, and other apps",
        actionTitle = "Share",
    ),
}

enum class MediaDeliveryPostExportAction {
    SYSTEM_SHARE,
    SAVE_TO_PHOTOS,
}

data class MediaDeliveryOverlayState(
    val statusLine: String,
    val batchLine: String? = null,
    val overallFraction: Double = 0.0,
    val isPreparing: Boolean = true,
    val filename: String? = null,
)

private enum class DeliveryStep {
    DESTINATION,
    OPTIONS,
}

@Composable
fun MediaDeliveryHost(
    files: List<MediaFile>?,
    controller: MediaLibraryController,
    onDismissPopup: () -> Unit,
) {
    var overlay by remember { mutableStateOf<MediaDeliveryOverlayState?>(null) }
    var toast by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    fun presentToast(message: String) {
        toast = message
        scope.launch {
            kotlinx.coroutines.delay(2500)
            if (toast == message) toast = null
        }
    }

    if (files == null && overlay == null && toast == null) return

    Box(Modifier.fillMaxSize()) {
        files?.let { selection ->
            MediaDeliveryPopup(
                files = selection,
                controller = controller,
                busy = overlay != null,
                onDismiss = onDismissPopup,
                onDeliver = { action ->
                    overlay =
                        MediaDeliveryOverlayState(
                            statusLine = "Preparing…",
                            isPreparing = true,
                        )
                    onDismissPopup()
                    scope.launch {
                        val outcome =
                            runDelivery(
                                context = context,
                                controller = controller,
                                files = selection,
                                action = action,
                                onProgress = { overlay = it },
                            )
                        overlay = null
                        presentToast(outcome)
                    }
                },
            )
        }
        overlay?.let { state ->
            MediaDeliveryProgressOverlay(
                state,
                modifier =
                    Modifier
                        .align(Alignment.TopCenter)
                        .statusBarsPadding()
                        .padding(horizontal = 20.dp, vertical = 12.dp),
            )
        }
        toast?.let { message ->
            MediaDeliveryCompletionToast(message, modifier = Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
fun MediaDeliveryPopup(
    files: List<MediaFile>,
    controller: MediaLibraryController,
    onDismiss: () -> Unit,
    onDeliver: (MediaDeliveryPostExportAction) -> Unit,
    busy: Boolean = false,
) {
    var step by remember { mutableStateOf(DeliveryStep.DESTINATION) }
    var destination by remember { mutableStateOf<MediaDeliveryDestination?>(null) }
    var shareAction by remember { mutableStateOf(MediaDeliveryPostExportAction.SYSTEM_SHARE) }
    val cachedCount = files.count { controller.isDownloaded(it) }
    val hasDeliverable = cachedCount > 0 || (controller.isLive && files.isNotEmpty())
    val canContinue = destination == MediaDeliveryDestination.NATIVE_SHARE && hasDeliverable && !busy

    Dialog(
        onDismissRequest = { if (!busy) onDismiss() },
        properties =
            DialogProperties(
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
            ),
    ) {
    Box(
        Modifier
            .fillMaxSize()
            .background(LiveDesign.sheetScrim)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) {
                if (!busy) onDismiss()
            },
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            Modifier
                .statusBarsPadding()
                .padding(horizontal = 16.dp, vertical = 16.dp)
                .fillMaxWidth()
                .widthIn(max = 420.dp)
                .heightIn(max = 520.dp)
                .clip(MediaCornerShape)
                .mediaSheetPlate(MediaCornerShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) {}
                .padding(16.dp),
        ) {
            when (step) {
                DeliveryStep.DESTINATION -> DestinationHeader(onClose = onDismiss)
                DeliveryStep.OPTIONS ->
                    OptionsHeader(
                        title = destination?.title ?: "Share",
                        onBack = { step = DeliveryStep.DESTINATION },
                    )
            }
            Spacer(Modifier.height(12.dp))
            Column(
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    "${files.size} clip${if (files.size == 1) "" else "s"}",
                    style = LiveType.ui(15f, FontWeight.SemiBold),
                    color = LiveDesign.text,
                )
                if (cachedCount < files.size) {
                    Text(
                        if (controller.isLive) {
                            "${files.size - cachedCount} on-camera clip(s) will be cached from the camera first."
                        } else {
                            "${files.size - cachedCount} on-camera clip(s) will be skipped — reconnect to cache them."
                        },
                        style = LiveType.ui(12f, FontWeight.Medium),
                        color = LiveDesign.muted,
                    )
                }
                when (step) {
                    DeliveryStep.DESTINATION -> {
                        Text(
                            "DESTINATION",
                            style = LiveType.mono(10f, FontWeight.Bold),
                            color = LiveDesign.muted,
                        )
                        DestinationRow(
                            enabled = hasDeliverable,
                            onClick = {
                                destination = MediaDeliveryDestination.NATIVE_SHARE
                                step = DeliveryStep.OPTIONS
                            },
                        )
                    }
                    DeliveryStep.OPTIONS -> {
                        if (files.size == 1) {
                            Column(
                                Modifier
                                    .fillMaxWidth()
                                    .clip(MediaCornerShape)
                                    .background(LiveDesign.hairline.copy(alpha = 0.35f), MediaCornerShape)
                                    .padding(12.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Text("Filename", style = LiveType.ui(12f, FontWeight.SemiBold), color = LiveDesign.muted)
                                Text(
                                    files.first().filename,
                                    style = LiveType.mono(13f, FontWeight.Medium),
                                    color = LiveDesign.text,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                }
            }
            if (step == DeliveryStep.OPTIONS) {
                Spacer(Modifier.height(12.dp))
                SegmentedShareAction(selected = shareAction, onSelect = { shareAction = it })
                Spacer(Modifier.height(10.dp))
                FooterActionButton(
                    title =
                        if (shareAction == MediaDeliveryPostExportAction.SAVE_TO_PHOTOS) {
                            "Save to Photos"
                        } else {
                            "Share"
                        },
                    enabled = canContinue,
                    onClick = { onDeliver(shareAction) },
                )
            }
        }
    }
    }
}

@Composable
fun MediaDeliveryProgressOverlay(
    state: MediaDeliveryOverlayState,
    onCancel: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .widthIn(max = 420.dp)
            .fillMaxWidth()
            .shadow(12.dp, MediaCapsuleShape, ambientColor = Color.Black.copy(alpha = 0.35f))
            .clip(MediaCapsuleShape)
            .mediaSheetPlate(MediaCapsuleShape)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (state.isPreparing) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                color = LiveDesign.accent,
                strokeWidth = 2.dp,
            )
        }
        Column(Modifier.weight(1f)) {
            Text(
                state.statusLine,
                style = LiveType.ui(12f, FontWeight.SemiBold),
                color = LiveDesign.text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            state.batchLine?.let { batch ->
                Text(
                    batch,
                    style = LiveType.mono(10f, FontWeight.Medium),
                    color = LiveDesign.muted,
                    maxLines = 1,
                )
            }
        }
        if (!state.isPreparing) {
            MediaGlassTrack(fraction = state.overallFraction.toFloat(), trackWidth = 44.dp)
        }
        if (onCancel != null) {
            Text(
                "Cancel",
                style = LiveType.ui(11f, FontWeight.SemiBold),
                color = LiveDesign.muted,
                modifier = Modifier.chromeClickable(onClick = onCancel),
            )
        }
    }
}

@Composable
fun MediaDeliveryCompletionToast(message: String, modifier: Modifier = Modifier) {
    Text(
        message,
        style = LiveType.ui(13f, FontWeight.Medium),
        color = LiveDesign.text,
        modifier =
            modifier
                .navigationBarsPadding()
                .padding(bottom = 28.dp)
                .clip(MediaCapsuleShape)
                .mediaSheetPlate(MediaCapsuleShape)
                .padding(horizontal = 16.dp, vertical = 10.dp),
    )
}

@Composable
private fun DestinationHeader(onClose: () -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        OpcIcon(OpcIcon.SHARE, contentDescription = null, tint = LiveDesign.text, modifier = Modifier.size(13.dp))
        Text(
            "SHARE",
            style = LiveType.mono(14f, FontWeight.Bold),
            color = LiveDesign.text,
        )
        Spacer(Modifier.weight(1f))
        MediaCloseButton(onClick = onClose, size = 30.dp)
    }
}

@Composable
private fun OptionsHeader(title: String, onBack: () -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            "‹ Back",
            style = LiveType.ui(13f, FontWeight.SemiBold),
            color = LiveDesign.accent,
            modifier = Modifier.chromeClickable(onClick = onBack),
        )
        Column(Modifier.weight(1f)) {
            Text(title, style = LiveType.ui(15f, FontWeight.SemiBold), color = LiveDesign.text)
            Text("Options", style = LiveType.ui(11f, FontWeight.Medium), color = LiveDesign.muted)
        }
    }
}

@Composable
private fun DestinationRow(enabled: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(MediaCornerShape)
            .background(LiveDesign.hairline.copy(alpha = 0.35f), MediaCornerShape)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        OpcIcon(
            OpcIcon.SHARE,
            contentDescription = null,
            tint = if (enabled) LiveDesign.text else LiveDesign.faint,
            modifier = Modifier.size(18.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(
                MediaDeliveryDestination.NATIVE_SHARE.title,
                style = LiveType.ui(14f, FontWeight.SemiBold),
                color = if (enabled) LiveDesign.text else LiveDesign.faint,
            )
            Text(
                MediaDeliveryDestination.NATIVE_SHARE.subtitle,
                style = LiveType.ui(11f, FontWeight.Medium),
                color = LiveDesign.muted,
            )
        }
        OpcIcon(
            OpcIcon.CHEVRON_RIGHT,
            contentDescription = null,
            tint = LiveDesign.faint,
            modifier = Modifier.size(12.dp),
        )
    }
}

@Composable
private fun SegmentedShareAction(
    selected: MediaDeliveryPostExportAction,
    onSelect: (MediaDeliveryPostExportAction) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(MediaCornerShape)
            .background(LiveDesign.hairline.copy(alpha = 0.35f), MediaCornerShape)
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        listOf(
            MediaDeliveryPostExportAction.SYSTEM_SHARE to "Share",
            MediaDeliveryPostExportAction.SAVE_TO_PHOTOS to "Save to Photos",
        ).forEach { (action, label) ->
            val on = selected == action
            Box(
                Modifier
                    .weight(1f)
                    .clip(MediaCornerShape)
                    .background(if (on) LiveDesign.accent.copy(alpha = 0.28f) else Color.Transparent)
                    .chromeClickable { onSelect(action) }
                    .padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    style = LiveType.ui(12f, FontWeight.SemiBold),
                    color = if (on) LiveDesign.text else LiveDesign.muted,
                )
            }
        }
    }
}

@Composable
private fun FooterActionButton(title: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .clip(MediaCornerShape)
            .background(
                if (enabled) LiveDesign.accent.copy(alpha = 0.22f) else LiveDesign.hairline.copy(alpha = 0.25f),
                MediaCornerShape,
            )
            .border(
                1.dp,
                if (enabled) LiveDesign.accent.copy(alpha = 0.55f) else LiveDesign.hairline.copy(alpha = 0.35f),
                MediaCornerShape,
            )
            .chromeClickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            style = LiveType.ui(15f, FontWeight.SemiBold),
            color = if (enabled) LiveDesign.text else LiveDesign.faint,
        )
    }
}

private suspend fun runDelivery(
    context: Context,
    controller: MediaLibraryController,
    files: List<MediaFile>,
    action: MediaDeliveryPostExportAction,
    onProgress: (MediaDeliveryOverlayState) -> Unit,
): String {
    // Original camera file only — never the LRF/XRF 720p playback proxy.
    val toCache = files.filter { !controller.isDownloaded(it) }
    if (toCache.isNotEmpty()) {
        coroutineScope {
            for ((index, file) in toCache.withIndex()) {
                fun emit(fraction: Double) {
                    onProgress(
                        MediaDeliveryOverlayState(
                            statusLine =
                                if (fraction > 0.0) "Caching from camera" else "Caching from camera…",
                            batchLine = if (toCache.size > 1) "Clip ${index + 1} of ${toCache.size}" else null,
                            overallFraction = fraction,
                            isPreparing = fraction <= 0.0,
                            filename = file.filename,
                        ),
                    )
                }
                emit(controller.downloadProgress[file.path] ?: 0.0)
                val poll =
                    launch {
                        while (isActive) {
                            delay(200)
                            emit(controller.downloadProgress[file.path] ?: 0.0)
                        }
                    }
                try {
                    controller.download(file)
                } finally {
                    poll.cancel()
                }
            }
        }
    }
    val ready =
        files.mapNotNull { file ->
            if (controller.isDownloaded(file)) controller.localFile(file) else null
        }
    if (ready.isEmpty()) {
        return if (toCache.isNotEmpty()) {
            "Couldn't cache ${toCache.size} clip(s) from the camera — check the connection and try again."
        } else {
            "Select at least one clip."
        }
    }
    return when (action) {
        MediaDeliveryPostExportAction.SYSTEM_SHARE -> {
            for ((index, file) in ready.withIndex()) {
                onProgress(
                    MediaDeliveryOverlayState(
                        statusLine = "Preparing to share",
                        batchLine = if (ready.size > 1) "Clip ${index + 1} of ${ready.size}" else null,
                        overallFraction = (index + 1).toDouble() / ready.size,
                        isPreparing = false,
                        filename = file.name,
                    ),
                )
            }
            shareFiles(context, ready)
            "Ready to share ${ready.size} clip${if (ready.size == 1) "" else "s"}"
        }
        MediaDeliveryPostExportAction.SAVE_TO_PHOTOS -> {
            var saved = 0
            for ((index, file) in ready.withIndex()) {
                onProgress(
                    MediaDeliveryOverlayState(
                        statusLine = "Saving to Photos ${(index * 100 / ready.size)}%",
                        batchLine = if (ready.size > 1) "Clip ${index + 1} of ${ready.size}" else null,
                        overallFraction = (index + 1).toDouble() / ready.size,
                        isPreparing = false,
                        filename = file.name,
                    ),
                )
                val ok =
                    withContext(Dispatchers.IO) {
                        insertIntoGallery(context, file) != null
                    }
                if (ok) saved += 1
            }
            if (saved == 0) "Couldn't save clips to Photos."
            else "Saved $saved clip${if (saved == 1) "" else "s"} to Photos"
        }
    }
}

private fun shareFiles(context: Context, files: List<File>) {
    if (files.size == 1) {
        MediaShare.shareCachedFile(context, files.first(), MediaHTTP.playbackMIMEType(files.first().name))
        return
    }
    val uris = ArrayList<Uri>()
    for (file in files) {
        val uri =
            runCatching { FileProvider.getUriForFile(context, MediaShare.authority(context), file) }.getOrNull()
                ?: continue
        uris.add(uri)
    }
    if (uris.isEmpty()) {
        files.firstOrNull()?.let { MediaShare.shareCachedFile(context, it, MediaHTTP.playbackMIMEType(it.name)) }
        return
    }
    val mime = if (uris.size == 1) MediaHTTP.playbackMIMEType(files.first().name) else "*/*"
    val intent =
        Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = mime
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    val chooser = Intent.createChooser(intent, null)
    if (context !is android.app.Activity) chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(chooser)
}

private fun insertIntoGallery(context: Context, file: File): Uri? {
    val mime = MediaHTTP.playbackMIMEType(file.name)
    val collection =
        if (mime.startsWith("image/")) {
            if (Build.VERSION.SDK_INT >= 29) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
        } else {
            if (Build.VERSION.SDK_INT >= 29) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }
        }
    val values =
        ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= 29) {
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    if (mime.startsWith("image/")) Environment.DIRECTORY_PICTURES + "/OpenPocketCine"
                    else Environment.DIRECTORY_MOVIES + "/OpenPocketCine",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
    val uri = context.contentResolver.insert(collection, values) ?: return null
    context.contentResolver.openOutputStream(uri)?.use { out ->
        file.inputStream().use { it.copyTo(out) }
    } ?: return null
    if (Build.VERSION.SDK_INT >= 29) {
        val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
        context.contentResolver.update(uri, done, null, null)
    }
    return uri
}
