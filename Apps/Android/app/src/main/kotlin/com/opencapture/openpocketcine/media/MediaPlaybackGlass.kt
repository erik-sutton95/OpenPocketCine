package com.opencapture.openpocketcine.media

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.opencapture.openpocketcine.MonitorGlass
import com.opencapture.opencine.media.FeedEffectsRenderPlan

/** Compatibility environment; shared monitor materials receive passive image sources separately. */
@Composable
fun rememberPlaybackMonitorGlass(): MonitorGlass {
    return remember { MonitorGlass(com.opencapture.openpocketcine.GlassTier.FLAT) }
}

internal fun applyPlaybackLook(src: Bitmap, dst: Bitmap, plan: FeedEffectsRenderPlan) {
    val w = src.width
    val h = src.height
    if (dst.width != w || dst.height != h) return
    val px = IntArray(w * h)
    src.getPixels(px, 0, w, 0, 0, w, h)
    applyPlaybackLookPixels(px, w, h, plan)
    dst.setPixels(px, 0, w, 0, 0, w, h)
}

internal fun applyPlaybackLookPixels(px: IntArray, width: Int, height: Int, plan: FeedEffectsRenderPlan) =
    com.opencapture.opencine.media.MonitorPlaybackPixelEffects.apply(px, width, height, plan)

internal fun argb8888ToRgba(pixels: IntArray): ByteArray =
    com.opencapture.opencine.media.MonitorPlaybackPixelEffects.argb8888ToRgba(pixels)

/** Static photo input follows the same passive geometry contract as video. */
@Composable
internal fun rememberPhotoBackdrop(bitmap: Bitmap?, identity: Any): com.opencapture.monitorui.MonitorBackdropSource =
    com.opencapture.monitorui.rememberMonitorPhotoBackdrop(bitmap, identity)
