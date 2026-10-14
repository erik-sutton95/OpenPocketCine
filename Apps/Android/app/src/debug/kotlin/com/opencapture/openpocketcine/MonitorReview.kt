package com.opencapture.openpocketcine

import android.content.Context
import android.content.Intent
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import com.opencapture.monitorui.ReviewLaunch
import com.opencapture.opencine.platform.ReviewMediaSeed
import com.opencapture.opencine.vocabulary.MediaFile
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal fun Modifier.reviewMetadata(review: ReviewLaunch?): Modifier =
    if (review == null) this else semantics { testTagsAsResourceId = true }

/** SIMULATED local review through the production cache, catalog, gallery and player. */
internal object MonitorReview {
    fun decode(intent: Intent?): ReviewLaunch? = ReviewLaunch.decode { intent?.getStringExtra(it) }
        ?.takeIf { it.screen == ReviewLaunch.Screen.MEDIA && it.source == ReviewLaunch.Source.LOCAL && !it.connected }

    suspend fun start(context: Context, model: AppModel, review: ReviewLaunch) {
        val namespace = "SIMULATED-S1"
        withContext(Dispatchers.IO) {
            val cache = model.mediaCache
            val clips = ReviewMediaSeed.write(File(context.cacheDir, "SIMULATED-S1"), review.mediaCount) { clip ->
                val file = file(clip)
                ReviewMediaSeed.Destination(cache.fileCache(namespace, file), cache.thumbnailFile(namespace, file))
            }
            cache.persistCatalog(clips.map(::file), namespace)
            cache.rememberCameraId(namespace)
        }
        model.homePanel = AppPanel.MEDIA
    }

    private fun file(clip: ReviewMediaSeed.Clip): MediaFile = MediaFile(
        path = "DCIM/SIMULATED/${clip.filename}", thumbPath = "DCIM/SIMULATED/${clip.filename}",
        sizeBytes = clip.byteCount, durationSeconds = clip.durationSeconds,
        resolution = "${clip.width}x${clip.height}", fps = clip.frameRate,
    )
}
