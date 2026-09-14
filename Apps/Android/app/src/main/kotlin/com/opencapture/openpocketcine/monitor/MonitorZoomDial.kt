package com.opencapture.openpocketcine.monitor

import android.content.res.Configuration
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.runtime.Composable
import com.opencapture.monitorui.MonitorZoomAttachment
import com.opencapture.monitorui.MonitorZoomCaption
import com.opencapture.openpocketcine.LiveZoom
import com.opencapture.openpocketcine.LocalOperatorHaptics

/** Existing session gestures adapt to the shared native logarithmic zoom scale. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MonitorZoomDial(initial: Double, maximum: Double, onChange: (Double) -> Unit, onDismiss: () -> Unit,
    opticalStops: List<Double> = listOf(1.0)) {
    val density = LocalDensity.current
    val configuration = LocalConfiguration.current
    val layoutDirection = LocalLayoutDirection.current
    val inset = WindowInsets.displayCutout.getRight(density, layoutDirection) / density.density
    val portrait = configuration.orientation == Configuration.ORIENTATION_PORTRAIT ||
        configuration.screenHeightDp > configuration.screenWidthDp
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorZoomDisc(initial, maximum, LiveZoom::label, onChange, onDismiss,
        opticalStops = opticalStops,
        caption = { factor -> MonitorZoomCaption.label(factor, opticalStops) },
        trailingInset = if (inset > 0f) inset + 6f else 0f,
        attachment = if (portrait) MonitorZoomAttachment.Bottom else MonitorZoomAttachment.Trailing,
        bottomClearance = 0f,
        onDetent = { haptics.confirm() })
}
