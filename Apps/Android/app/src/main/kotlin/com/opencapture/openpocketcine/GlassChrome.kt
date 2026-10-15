package com.opencapture.openpocketcine

import android.os.Build
import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
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
fun Modifier.liveChromeGlass(shape: Shape = ChromeShape): Modifier =
    monitorMaterial(MonitorMaterial.Compact, shape)
