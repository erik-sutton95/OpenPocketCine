package com.opencapture.openpocketcine

import android.os.Build
import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial

// UI 2.0 uses the shared controlled blur renderer and passive low-resolution image sources.
// Legacy Kyant capability types remain for callers outside the floating monitor chrome.

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
 * Existing media/assist controls use the shared controlled material renderer.
 * Source sampling belongs to the shell and never to an individual widget.
 */
fun Modifier.panelGlass(shape: Shape = ChromeShape): Modifier =
    background(LiveDesign.surface, shape).border(1.dp, LiveDesign.hairline, shape)

@Composable
fun Modifier.glass(shape: Shape = ChromeShape): Modifier = liveChromeGlass(shape)

@Composable
fun Modifier.overlayGlass(shape: Shape = ChromeShape): Modifier = pickerPanelGlass(shape)

@Composable
fun Modifier.liveChromeGlass(shape: Shape = ChromeShape): Modifier =
    monitorMaterial(MonitorMaterial.Compact, shape)

@Composable
fun Modifier.playbackBarGlass(shape: Shape = ChromeShape): Modifier = liveChromeGlass(shape)

@Composable
fun Modifier.pickerPanelGlass(shape: Shape = ChromeShape): Modifier =
    monitorMaterial(MonitorMaterial.Expanded, shape)

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

