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

// UI 2.0 composites translucent monitor chrome without copying camera frames.
// Page surfaces remain opaque. The compatibility gate is retained for legacy
// callers, but production live/playback choose FLAT and never sample a backdrop.

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

/**
 * UI 2.0 uses composited tint plates. These compatibility modifiers let existing
 * media/assist controls share the new renderer without changing their ownership
 * or reattaching a decoder surface. No backdrop sampling runs in these modifiers.
 */
fun Modifier.panelGlass(shape: Shape = ChromeShape): Modifier =
    background(LiveDesign.surface, shape).border(1.dp, LiveDesign.hairline, shape)

@Composable
fun Modifier.glass(shape: Shape = ChromeShape): Modifier = panelGlass(shape)

@Composable
fun Modifier.overlayGlass(shape: Shape = ChromeShape): Modifier = pickerPanelGlass(shape)

@Composable
fun Modifier.liveChromeGlass(shape: Shape = ChromeShape): Modifier =
    background(Color(0xFF141618).copy(alpha = .52f), shape)

@Composable
fun Modifier.playbackBarGlass(shape: Shape = ChromeShape): Modifier = liveChromeGlass(shape)

@Composable
fun Modifier.pickerPanelGlass(shape: Shape = ChromeShape): Modifier =
    background(com.opencapture.monitorui.MonitorPalette.overlayPanel, shape)
        .border(1.dp, LiveDesign.hairline, shape)

fun Modifier.chipGlass(shape: Shape = ChromeShape): Modifier =
    background(LiveDesign.tile, shape)

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

