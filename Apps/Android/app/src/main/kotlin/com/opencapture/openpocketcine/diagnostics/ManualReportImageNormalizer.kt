package com.opencapture.openpocketcine.diagnostics

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

/**
 * Downsamples and re-encodes picker images off the UI thread. Output is JPEG
 * pixels only: no EXIF, GPS, or source filename.
 */
internal object ManualReportImageNormalizer {
    sealed class Result {
        data class Ok(val jpeg: ByteArray) : Result()
        data object Unreadable : Result()
        data object TooLarge : Result()
    }

    fun prepare(context: Context, uri: Uri): Result {
        val type = context.contentResolver.getType(uri)
        if (type != null && !type.startsWith("image/")) return Result.Unreadable
        val bytes =
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { ManualReportImages.readSource(it) }
            }.getOrNull() ?: return Result.Unreadable
        return prepare(bytes)
    }

    fun prepare(bytes: ByteArray): Result {
        if (bytes.isEmpty()) return Result.Unreadable
        if (bytes.size > ManualReportImages.SOURCE_MAX_BYTES) return Result.TooLarge
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return Result.Unreadable
        val options =
            BitmapFactory.Options().apply {
                inSampleSize =
                    ManualReportImages.sampleSize(bounds.outWidth, bounds.outHeight)
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return Result.Unreadable
        var oriented = applyOrientation(decoded, bytes)
        if (oriented !== decoded) decoded.recycle()
        val max = ManualReportImages.MAX_DIMENSION
        if (oriented.width > max || oriented.height > max) {
            val scale = max.toFloat() / maxOf(oriented.width, oriented.height).toFloat()
            val w = (oriented.width * scale).toInt().coerceAtLeast(1)
            val h = (oriented.height * scale).toInt().coerceAtLeast(1)
            val scaled = Bitmap.createScaledBitmap(oriented, w, h, true)
            if (scaled !== oriented) oriented.recycle()
            oriented = scaled
        }
        try {
            encode(oriented)?.let { jpeg ->
                return if (ManualReportImages.accept(listOf(jpeg)) != null) Result.Ok(jpeg)
                else Result.TooLarge
            }
            val shrink =
                Bitmap.createScaledBitmap(
                    oriented,
                    (oriented.width * 0.7f).toInt().coerceAtLeast(1),
                    (oriented.height * 0.7f).toInt().coerceAtLeast(1),
                    true,
                )
            if (shrink !== oriented) oriented.recycle()
            oriented = shrink
            val retry = encode(oriented)
            return if (retry != null && ManualReportImages.accept(listOf(retry)) != null) Result.Ok(retry)
            else Result.TooLarge
        } finally {
            if (!oriented.isRecycled) oriented.recycle()
        }
    }

    private fun encode(bitmap: Bitmap): ByteArray? {
        for (quality in intArrayOf(80, 60, 40)) {
            val out = ByteArrayOutputStream()
            if (bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out) &&
                out.size() <= ManualReportImages.MAX_EACH_BYTES
            ) {
                return out.toByteArray()
            }
        }
        return null
    }

    private fun applyOrientation(bitmap: Bitmap, jpegBytes: ByteArray): Bitmap {
        val orientation =
            runCatching {
                ExifInterface(ByteArrayInputStream(jpegBytes))
                    .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.preScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.preScale(-1f, 1f)
            }
            else -> return bitmap
        }
        return runCatching {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }.getOrDefault(bitmap)
    }
}
