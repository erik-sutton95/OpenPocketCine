package com.opencapture.openpocketcine.media

import android.app.ActivityManager
import android.graphics.Bitmap
import android.os.Build
import android.view.TextureView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.MonitorGlass
import com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan
import com.opencapture.openpocketcine.feed.LiveScopeSampleBus
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.PocketScopeSampler
import com.opencapture.openpocketcine.feed.ScopeAssistBundle
import com.opencapture.openpocketcine.feed.ScopeExposureCeiling
import com.opencapture.openpocketcine.resolveTier
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Compatibility environment; shared monitor materials receive passive image sources separately. */
@Composable
fun rememberPlaybackMonitorGlass(): MonitorGlass {
    return remember { MonitorGlass(com.opencapture.openpocketcine.GlassTier.FLAT) }
}

/** Edge scrims keep filename and transport controls readable over the picture. */
@Composable
fun BoxScope.PlaybackDarkenedBars(
    showTop: Boolean = true,
    showBottom: Boolean = true,
) {
    if (showTop) {
        Box(
            Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .height(PlaybackChromeMetrics.topScrimDp.dp)
                .clipToBounds()
                .background(
                    Brush.verticalGradient(
                        listOf(LiveDesign.playbackScrim, Color.Transparent),
                    ),
                ),
        )
    }
    if (showBottom) {
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(PlaybackChromeMetrics.bottomScrimDp.dp)
                .clipToBounds()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, LiveDesign.playbackScrim),
                    ),
                ),
        )
    }
}

/**
 * WAVE / HISTO tap. LUT / PEAK / FALSE / ZEBRA grade inside ExoPlayer at the
 * clip raster — this is display-size, scopes only.
 */
@Composable
internal fun PlaybackFrameSample(
    textureView: TextureView,
    enabled: Boolean,
    plan: FeedEffectsRenderPlan,
    colorMode: Int,
    iso: Int,
) {
    LaunchedEffect(textureView, enabled, plan, colorMode, iso) {
        if (!enabled) return@LaunchedEffect
        var previousBundle = ScopeAssistBundle.EMPTY
        val buf = arrayOfNulls<Bitmap>(2)
        var slot = 0
        while (isActive) {
            delay(PlaybackChromeMetrics.SAMPLE_MS)
            if (!textureView.isAvailable) continue
            val srcW = textureView.width
            val srcH = textureView.height
            if (srcW <= 1 || srcH <= 1) continue
            val longest = max(srcW, srcH).toFloat()
            val scale = min(1f, PlaybackChromeMetrics.SAMPLE_MAX_SIDE / longest)
            val dw = (srcW * scale).roundToInt().coerceAtLeast(1)
            val dh = (srcH * scale).roundToInt().coerceAtLeast(1)
            val dst =
                buf[slot]?.takeIf { it.width == dw && it.height == dh && it.isMutable }
                    ?: createBitmap(dw, dh, Bitmap.Config.ARGB_8888).also { buf[slot] = it }
            textureView.getBitmap(dst)
            previousBundle = publishPlaybackScopeTap(dst, colorMode, iso, plan, previousBundle)
            slot = 1 - slot
        }
    }
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

internal fun applyPlaybackLookPixels(
    px: IntArray,
    width: Int,
    height: Int,
    plan: FeedEffectsRenderPlan,
) {
    val lut = plan.lutCube
    val falsePaint = plan.falseColorPaint
    val zebraOn = plan.zebraHighlightOn
    val zebraCode = (plan.zebraHighlightCode * 255f).toInt().coerceIn(0, 255)
    val zr = (plan.zebraHighlightColor.getOrElse(0) { 1f } * 255f).toInt().coerceIn(0, 255)
    val zg = (plan.zebraHighlightColor.getOrElse(1) { 1f } * 255f).toInt().coerceIn(0, 255)
    val zb = (plan.zebraHighlightColor.getOrElse(2) { 1f } * 255f).toInt().coerceIn(0, 255)
    val midOn = plan.zebraMidtoneOn
    val midCode = (plan.zebraMidtoneCode * 255f).toInt().coerceIn(0, 255)
    val midHalf = (plan.zebraMidtoneHalf * 255f).toInt().coerceAtLeast(1)
    val mr = (plan.zebraMidtoneColor.getOrElse(0) { 1f } * 255f).toInt().coerceIn(0, 255)
    val mg = (plan.zebraMidtoneColor.getOrElse(1) { 1f } * 255f).toInt().coerceIn(0, 255)
    val mb = (plan.zebraMidtoneColor.getOrElse(2) { 0f } * 255f).toInt().coerceIn(0, 255)
    val peakOn = plan.peaking
    val pr = (plan.peakingColor.getOrElse(0) { 1f } * 255f).toInt().coerceIn(0, 255)
    val pg = (plan.peakingColor.getOrElse(1) { 0f } * 255f).toInt().coerceIn(0, 255)
    val pb = (plan.peakingColor.getOrElse(2) { 0f } * 255f).toInt().coerceIn(0, 255)
    val src = px.copyOf()
    for (i in px.indices) {
        val p = src[i]
        var r = (p ushr 16) and 0xFF
        var g = (p ushr 8) and 0xFF
        var b = p and 0xFF
        val a = p ushr 24
        if (lut != null) {
            val mapped = lut.map(r / 255f, g / 255f, b / 255f)
            r = (mapped.first * 255f).toInt().coerceIn(0, 255)
            g = (mapped.second * 255f).toInt().coerceIn(0, 255)
            b = (mapped.third * 255f).toInt().coerceIn(0, 255)
        }
        if (falsePaint != null) {
            val mapped = falsePaint.map(r / 255f, g / 255f, b / 255f)
            r = (mapped.first * 255f).toInt().coerceIn(0, 255)
            g = (mapped.second * 255f).toInt().coerceIn(0, 255)
            b = (mapped.third * 255f).toInt().coerceIn(0, 255)
        }
        val luma = (0.2126f * r + 0.7152f * g + 0.0722f * b).toInt()
        if (midOn && kotlin.math.abs(luma - midCode) <= midHalf) {
            r = mr
            g = mg
            b = mb
        }
        // Highlight rides the max channel: same byte WAVE draws at 100 (#136).
        if (zebraOn && maxOf(r, g, b) >= zebraCode) {
            r = zr
            g = zg
            b = zb
        }
        if (peakOn && i >= width && i < px.size - width) {
            val up = src[i - width]
            val ur = (up ushr 16) and 0xFF
            val ug = (up ushr 8) and 0xFF
            val ub = up and 0xFF
            val edge = kotlin.math.abs(r - ur) + kotlin.math.abs(g - ug) + kotlin.math.abs(b - ub)
            if (edge > 80) {
                r = pr
                g = pg
                b = pb
            }
        }
        px[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
    }
}

internal fun argb8888ToRgba(pixels: IntArray): ByteArray {
    val packed = ByteArray(pixels.size * 4)
    var o = 0
    for (p in pixels) {
        packed[o] = (p ushr 16).toByte()
        packed[o + 1] = (p ushr 8).toByte()
        packed[o + 2] = p.toByte()
        packed[o + 3] = (p ushr 24).toByte()
        o += 4
    }
    return packed
}

private fun publishPlaybackScopeTap(
    src: Bitmap,
    colorMode: Int,
    iso: Int,
    plan: FeedEffectsRenderPlan,
    previous: ScopeAssistBundle,
): ScopeAssistBundle {
    val tapW = src.width
    val tapH = src.height
    val pixels = IntArray(tapW * tapH)
    src.getPixels(pixels, 0, tapW, 0, 0, tapW, tapH)
    val packed = argb8888ToRgba(pixels)
    var transfer = MonitorTransfer.fromColorMode(colorMode)
    ScopeExposureCeiling.syncISO(iso)
    val (minC, maxC) = PocketScopeSampler.minMaxRGB(packed)
    transfer = MonitorTransfer.inferred(minC, maxC, transfer)
    ScopeExposureCeiling.observeTapMax(maxC, transfer)
    val bundle =
        PocketScopeSampler.sample(
            bytes = packed,
            width = tapW,
            height = tapH,
            bytesPerRow = tapW * 4,
            transfer = transfer,
            includePoints = true,
            includeVectorPoints = true,
            look = plan.scopeTap.vectorLut ?: plan.lutCube,
            previous = previous,
            iso = ScopeExposureCeiling.resolvedISO(),
        )
    LiveScopeSampleBus.publish(bundle)
    return bundle
}

/** Static photo input follows the same passive geometry contract as video. */
@Composable
internal fun rememberPhotoBackdrop(bitmap: Bitmap?, identity: Any): com.opencapture.monitorui.MonitorBackdropSource {
    val source = remember { com.opencapture.monitorui.MonitorBackdropSource() }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    var resumed by remember { androidx.compose.runtime.mutableStateOf(false) }
    androidx.compose.runtime.DisposableEffect(source, lifecycle) {
        fun update() { resumed = lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)
            if (!resumed) source.image = null }
        val observer = androidx.lifecycle.LifecycleEventObserver { _, _ -> update() }
        lifecycle.addObserver(observer); update()
        onDispose { lifecycle.removeObserver(observer); source.image = null }
    }
    LaunchedEffect(bitmap, identity, resumed) {
        source.image = null
        if (bitmap != null && resumed) {
            source.image = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                val scale = minOf(1f, 213f / bitmap.width, 120f / bitmap.height)
                bitmap.scale(
                    (bitmap.width * scale).toInt().coerceAtLeast(1),
                    (bitmap.height * scale).toInt().coerceAtLeast(1),
                )
            }
        }
    }
    return source
}
