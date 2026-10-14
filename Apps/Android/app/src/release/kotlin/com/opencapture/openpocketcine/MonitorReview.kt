package com.opencapture.openpocketcine

import android.content.Context
import android.content.Intent
import androidx.compose.ui.Modifier
import com.opencapture.monitorui.ReviewLaunch

internal fun Modifier.reviewMetadata(review: ReviewLaunch?): Modifier = this

/** The Debug-only local review is unavailable in shipped builds. */
internal object MonitorReview {
    fun decode(intent: Intent?): ReviewLaunch? = null
    suspend fun start(context: Context, model: AppModel, review: ReviewLaunch) = Unit
}
