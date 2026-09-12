package com.opencapture.openpocketcine.monitor

import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import kotlin.math.abs
import androidx.compose.runtime.Composable
import com.opencapture.openpocketcine.LiveZoom

/** Existing session gestures adapt to the shared native logarithmic zoom scale. */
@Composable
fun MonitorZoomDial(initial: Double, maximum: Double, onChange: (Double) -> Unit, onDismiss: () -> Unit,
    foreground: @Composable BoxScope.() -> Unit = {}, opticalStops: List<Double> = listOf(1.0)) {
    val config = LocalConfiguration.current
    val density = LocalDensity.current
    val inset = WindowInsets.displayCutout.getRight(density, LocalLayoutDirection.current) / density.density
    com.opencapture.monitorui.MonitorZoomDisc(initial, maximum, LiveZoom::label, onChange, onDismiss, foreground,
        opticalStops = opticalStops, caption = { factor ->
            when {
                abs(factor - 1.0) < .05 -> "WIDE"
                3.0 in opticalStops && abs(factor - 3.0) < .05 -> "TELE"
                3.0 in opticalStops && factor > 3.0 -> "DIGITAL · SOFT"
                3.0 in opticalStops -> "WIDE CROP"
                else -> "DIGITAL CROP"
            }
        }, trailingInset = if (config.screenWidthDp > config.screenHeightDp && inset > 0f) inset + 6f else 0f)
}
