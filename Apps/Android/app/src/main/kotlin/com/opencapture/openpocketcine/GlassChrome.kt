package com.opencapture.openpocketcine

import android.os.Build
import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CornerBasedShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import com.kyant.backdrop.backdrops.LayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.effects.vibrancy
import com.kyant.backdrop.highlight.Highlight
import com.kyant.backdrop.highlight.HighlightStyle

// Liquid glass via Kyant0/AndroidLiquidGlass — same package OpenZCine uses.
// Pocket tokens stay DJI-black / cyan (iOS LiveDesign), not OpenZCine gold.
//
// HEVC live view is a SurfaceView and cannot be sampled by Kyant. Chrome
// still records the Compose scene so pills blur sibling chrome; the feed
// itself stays a hole-punched surface (iOS samples VT separately too).

private const val TAG = "OpcGlass"

enum class GlassTier {
    FLAT,
    FULL,
}

fun resolveTier(
    sdkInt: Int,
    override: String? = null,
    isLowRamDevice: Boolean = false,
    totalRamBytes: Long = Long.MAX_VALUE,
): GlassTier {
    val lowEnd =
        isLowRamDevice ||
            (totalRamBytes in 1L until MIN_FULL_GLASS_RAM_BYTES)
    val capability =
        when {
            sdkInt < 33 -> GlassTier.FLAT
            lowEnd -> GlassTier.FLAT
            else -> GlassTier.FULL
        }
    val requested =
        when (override?.lowercase()) {
            "full" -> GlassTier.FULL
            "flat", "blur" -> GlassTier.FLAT
            else -> capability
        }
    return if (requested.ordinal < capability.ordinal) requested else capability
}

const val MIN_FULL_GLASS_RAM_BYTES: Long = 4L * 1024L * 1024L * 1024L

class FrameBudgetWindow(
    private val budgetNanos: Long = 48_000_000L,
    private val window: Int = 90,
    private val maxOverBudget: Int = 45,
    private val warmup: Int = 45,
) {
    private var skipped = 0
    private var seen = 0
    private var overBudget = 0

    fun frame(deltaNanos: Long): Boolean {
        if (skipped < warmup) {
            skipped++
            return false
        }
        seen++
        if (deltaNanos > budgetNanos) overBudget++
        if (seen < window) return false
        val demote = overBudget > maxOverBudget
        seen = 0
        overBudget = 0
        return demote
    }
}

class MonitorGlass(
    initialTier: GlassTier,
    val layerBackdrop: LayerBackdrop? = null,
    val overlayBackdrop: LayerBackdrop? = null,
    val allowDemote: Boolean = false,
) {
    var tier: GlassTier by mutableStateOf(initialTier)
        private set

    init {
        runCatching {
            Log.i(
                TAG,
                "glass session tier=$initialTier allowDemote=$allowDemote " +
                    "sdk=${Build.VERSION.SDK_INT} feedBackdrop=${layerBackdrop != null} " +
                    "overlayBackdrop=${overlayBackdrop != null}",
            )
        }
    }

    fun demote() {
        if (!allowDemote || tier == GlassTier.FLAT) return
        runCatching { Log.w(TAG, "sustained frame-budget overrun — FULL -> FLAT") }
        tier = GlassTier.FLAT
    }
}

val LocalMonitorGlass = compositionLocalOf<MonitorGlass?> { null }

/** iOS `Glass.regular` over DJI black — alpha 0.24 matches LiveDesign.glass. */
private val GlassSurfaceTint = Color(0f, 0f, 0f, 0.24f)
private val ChipGlassFill = Color(0f, 0f, 0f, 0.38f)

private val GlassEdgeHighlight =
    Highlight(
        width = 0.45.dp,
        blurRadius = 0.3.dp,
        alpha = 0.70f,
        style =
            HighlightStyle.Default(
                color = Color.White.copy(alpha = 0.42f),
                falloff = 1.7f,
            ),
    )

@Composable
fun Modifier.glass(shape: Shape = ChromeShape): Modifier {
    val glass = LocalMonitorGlass.current
    return glassBackdrop(
        backdrop = glass?.layerBackdrop,
        tier = glass?.tier ?: GlassTier.FLAT,
        shape = shape,
    )
}

@Composable
fun Modifier.overlayGlass(shape: Shape = ChromeShape): Modifier {
    val glass = LocalMonitorGlass.current
    return glassBackdrop(
        backdrop = glass?.overlayBackdrop ?: glass?.layerBackdrop,
        tier = glass?.tier ?: GlassTier.FLAT,
        shape = shape,
    )
}

@Composable
private fun Modifier.glassBackdrop(
    backdrop: LayerBackdrop?,
    tier: GlassTier,
    shape: Shape,
): Modifier {
    if (backdrop == null || tier == GlassTier.FLAT || Build.VERSION.SDK_INT < 33) {
        return background(LiveDesign.glassOpaque, shape)
            .border(1.dp, LiveDesign.hairlineStrong, shape)
    }
    return this.drawBackdrop(
        backdrop = backdrop,
        shape = { shape },
        effects = {
            vibrancy()
            blur(12f.dp.toPx())
            if (shape is CornerBasedShape) {
                lens(
                    refractionHeight = 10f.dp.toPx(),
                    refractionAmount = 20f.dp.toPx(),
                    depthEffect = true,
                )
            }
        },
        highlight = { GlassEdgeHighlight },
        onDrawSurface = { drawRect(GlassSurfaceTint) },
    )
}

fun Modifier.chipGlass(shape: Shape = ChromeShape): Modifier =
    background(ChipGlassFill, shape)
        .border(0.5.dp, LiveDesign.hairline.copy(alpha = 0.10f), shape)

internal data class LiveFeedContentRect(
    val left: Int,
    val top: Int,
    val width: Int,
    val height: Int,
)

internal fun liveFeedContentRect(
    containerWidth: Float,
    containerHeight: Float,
    sourceWidth: Int,
    sourceHeight: Int,
    aspectFill: Boolean = false,
): LiveFeedContentRect? {
    if (containerWidth <= 0f || containerHeight <= 0f || sourceWidth <= 0 || sourceHeight <= 0) {
        return null
    }
    val scale =
        if (aspectFill) {
            max(containerWidth / sourceWidth, containerHeight / sourceHeight)
        } else {
            min(containerWidth / sourceWidth, containerHeight / sourceHeight)
        }
    val width = (sourceWidth * scale).roundToInt()
    val height = (sourceHeight * scale).roundToInt()
    if (width <= 0 || height <= 0) return null
    return LiveFeedContentRect(
        left = ((containerWidth - width) / 2f).roundToInt(),
        top = ((containerHeight - height) / 2f).roundToInt(),
        width = width,
        height = height,
    )
}

internal fun glassBackdropContentRect(
    feedWidth: Float,
    feedHeight: Float,
    sourceWidth: Int,
    sourceHeight: Int,
    aspectFill: Boolean,
): LiveFeedContentRect? =
    liveFeedContentRect(
        containerWidth = feedWidth,
        containerHeight = feedHeight,
        sourceWidth = sourceWidth,
        sourceHeight = sourceHeight,
        aspectFill = aspectFill,
    )

@Composable
fun MonitorGlassBudgetLoop(glass: MonitorGlass) {
    if (!glass.allowDemote || glass.tier == GlassTier.FLAT) return
    LaunchedEffect(glass) {
        val budget = FrameBudgetWindow()
        var last = 0L
        while (glass.tier != GlassTier.FLAT) {
            withFrameNanos { now ->
                if (last != 0L && budget.frame(now - last)) glass.demote()
                last = now
            }
        }
    }
}
