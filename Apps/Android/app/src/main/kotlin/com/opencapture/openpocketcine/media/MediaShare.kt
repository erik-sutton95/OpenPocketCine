package com.opencapture.openpocketcine.media

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import android.content.ContentValues
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

object MediaShare {
    fun authority(context: Context): String = "${context.packageName}.mediafileprovider"

    fun shareCachedFile(context: Context, file: File, mime: String): Boolean {
        val uri = uriFor(context, file, mime) ?: return false
        val intent =
            Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        val chooser = Intent.createChooser(intent, null)
        if (context !is android.app.Activity) {
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(chooser)
        return true
    }

    private fun uriFor(context: Context, file: File, mime: String): Uri? {
        runCatching {
            return FileProvider.getUriForFile(context, authority(context), file)
        }
        return insertIntoGallery(context, file, mime)
    }

    fun insertIntoGallery(context: Context, file: File, mime: String): Uri? {
        val isImage = MediaStoreInsertPolicy.isImage(mime)
        val collection =
            if (isImage) {
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
                put(
                    MediaStore.MediaColumns.DISPLAY_NAME,
                    MediaStoreInsertPolicy.sanitizeDisplayName(file.name),
                )
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                if (Build.VERSION.SDK_INT >= 29) {
                    // Images must land under DCIM/Pictures, video under Movies.
                    // "Movies" for the images collection is rejected with
                    // IllegalArgumentException (#348).
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        MediaStoreInsertPolicy.relativePath(mime),
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }
        // A bad name/mime/volume must skip the share, never crash the sheet.
        val uri =
            runCatching { context.contentResolver.insert(collection, values) }.getOrNull()
                ?: return null
        val copied =
            runCatching {
                context.contentResolver.openOutputStream(uri)?.use { out ->
                    file.inputStream().use { it.copyTo(out) }
                } ?: return@runCatching false
                true
            }.getOrDefault(false)
        if (!copied) {
            runCatching { context.contentResolver.delete(uri, null, null) }
            return null
        }
        if (Build.VERSION.SDK_INT >= 29) {
            val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            runCatching { context.contentResolver.update(uri, done, null, null) }
        }
        return uri
    }
}
