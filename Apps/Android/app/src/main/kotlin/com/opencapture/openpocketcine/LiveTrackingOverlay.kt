package com.opencapture.openpocketcine

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.opencapture.opencine.vocabulary.TrackingHud
import com.opencapture.opencine.vocabulary.TrackingBox

/** Compatibility names over the exercised common focus renderer. */
@Composable
fun LiveFocusTrackingLayer(hud: TrackingHud, focus: Pair<Float, Float>?, mirrored: Boolean,
    showTapFocusBox: Boolean, modifier: Modifier = Modifier, aeLocked: Boolean = false,
    flippedVertically: Boolean = false, focusLocked: Boolean = false) {
    com.opencapture.opencine.cameracontrols.MonitorOperatorFocusLayer(hud, focus, mirrored, showTapFocusBox,
        modifier, aeLocked, flippedVertically, focusLocked)
}

@Composable
fun LiveTrackingCancelButton(box: TrackingBox, feedWidth: Float, feedHeight: Float,
    mirrored: Boolean, flippedVertically: Boolean = false, onClick: () -> Unit) {
    com.opencapture.opencine.cameracontrols.MonitorOperatorTrackingCancelButton(box, feedWidth, feedHeight,
        mirrored, flippedVertically, onClick)
}
