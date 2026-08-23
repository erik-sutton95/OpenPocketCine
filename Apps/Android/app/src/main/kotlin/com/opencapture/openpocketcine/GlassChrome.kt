package com.opencapture.openpocketcine

import android.os.Build
import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CornerBasedShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
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

// Liquid glass via Kyant0/AndroidLiquidGlass (`io.github.kyant0:backdrop`).
// Pocket tokens stay DJI-black / cyan (iOS LiveDesign), not OpenZCine gold.
//
// FULL glass is a hardware gate (API 33+ and ≥4 GB, not low-RAM). There is
// no frame-budget demote — if FULL is selected, Kyant stays on even when
// the HUD is expensive. Operator Setup and the media list stay solid frost.
// Playback HUD uses the same Kyant path as live; FLAT falls back to darkened bars.

private const val TAG = "OpcGlass"

enum class GlassTier {
    FLAT,
    FULL,
}

/**
 * Kyant `drawBackdrop` must not be a descendant of the `layerBackdrop` it
 * samples. That pairing overflows HWUI `RenderNode::prepareTreeImpl` (native
 * stack overflow on opening playback).
 */
fun kyantWouldLoop(chromeInsideRecordedLayer: Boolean): Boolean = chromeInsideRecordedLayer

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

class MonitorGlass(
    initialTier: GlassTier,
    val layerBackdrop: LayerBackdrop? = null,
    val overlayBackdrop: LayerBackdrop? = null,
) {
    val tier: GlassTier = initialTier

    init {
        runCatching {
            Log.i(
                TAG,
                "glass session tier=$initialTier " +
                    "sdk=${Build.VERSION.SDK_INT} feedBackdrop=${layerBackdrop != null} " +
                    "overlayBackdrop=${overlayBackdrop != null}",
            )
        }
    }
}

val LocalMonitorGlass = compositionLocalOf<MonitorGlass?> { null }

/** iOS `LiveDesign.glass` — light frost only, no HUD plate. */
private val GlassSurfaceTint = LiveDesign.glass
private val ChipGlassFill = LiveDesign.glassOpaque

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

/**
 * Solid frost for Operator Setup and the media list. Not Kyant — those pages
 * sit on DJI-black, so liquid glass has nothing to sample.
 */
fun Modifier.panelGlass(shape: Shape = ChromeShape): Modifier =
    background(LiveDesign.glassOpaque, shape).border(1.dp, LiveDesign.hairlineStrong, shape)

/**
 * Kyant liquid glass for the live HUD and playback chrome (`liveChromeGlass`).
 * Operator Setup and the media list use [panelGlass].
 */
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

/**
 * iOS `liveChromeGlass`: frost + black ND over a DJI-black plate so a
 * bright window cannot bleach the HUD.
 */
@Composable
fun Modifier.liveChromeGlass(shape: Shape = ChromeShape): Modifier {
    val glass = LocalMonitorGlass.current
    return liveChromeBackdrop(
        backdrop = glass?.layerBackdrop,
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

@Composable
private fun Modifier.liveChromeBackdrop(
    backdrop: LayerBackdrop?,
    tier: GlassTier,
    shape: Shape,
    extraNd: Color = Color.Transparent,
    plate: Color = LiveDesign.chromePlate,
    tint: Color = LiveDesign.chromeTint,
): Modifier {
    val flatFill =
        if (extraNd.alpha > 0f) {
            plate.copy(alpha = (plate.alpha + extraNd.alpha).coerceAtMost(0.72f))
        } else {
            plate
        }
    if (backdrop == null || tier == GlassTier.FLAT || Build.VERSION.SDK_INT < 33) {
        return background(flatFill, shape)
            .border(1.dp, LiveDesign.hairlineStrong, shape)
    }
    return this
        .background(plate, shape)
        .drawBackdrop(
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
            onDrawSurface = {
                drawRect(plate)
                drawRect(tint)
                if (extraNd.alpha > 0f) drawRect(extraNd)
            },
        )
}

/** Playback transport — half the HUD ND so the clip stays readable. */
@Composable
fun Modifier.playbackBarGlass(shape: Shape = ChromeShape): Modifier {
    val glass = LocalMonitorGlass.current
    return liveChromeBackdrop(
        backdrop = glass?.layerBackdrop,
        tier = glass?.tier ?: GlassTier.FLAT,
        shape = shape,
        plate = LiveDesign.playbackBarPlate,
        tint = LiveDesign.playbackBarTint,
    )
}

/**
 * iOS picker / assist / capture cards: HUD glass plus extra ND. Samples the
 * scene backdrop (feed + chrome) so liquid glass blurs UI under the sheet,
 * not only the live well. Popups sit outside the recorded scene layer so
 * this does not loop.
 */
@Composable
fun Modifier.pickerPanelGlass(shape: Shape = ChromeShape): Modifier {
    val glass = LocalMonitorGlass.current
    return liveChromeBackdrop(
        backdrop = glass?.overlayBackdrop ?: glass?.layerBackdrop,
        tier = glass?.tier ?: GlassTier.FLAT,
        shape = shape,
        extraNd = LiveDesign.pickerNd,
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


