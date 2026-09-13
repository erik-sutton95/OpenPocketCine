package com.opencapture.monitorui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.FastOutSlowInEasing

/**
 * Field Monitor motion, taken from the mockup's CSS keyframes and JS morphs.
 * `1-(1-k)^3` is ease-out cubic.
 */
object MonitorMotion {
    val EaseOutCubic: Easing = Easing { fraction -> 1f - (1f - fraction) * (1f - fraction) * (1f - fraction) }
    val EaseInOut: Easing = CubicBezierEasing(.42f, 0f, .58f, 1f)
    val Soft: Easing = CubicBezierEasing(.2f, .9f, .2f, 1f)
    val DrumSettle: Easing = CubicBezierEasing(.22f, 1.2f, .36f, 1f)
    val TypeSettle: Easing = CubicBezierEasing(.2f, .8f, .2f, 1f)
    val ZoomOut: Easing = CubicBezierEasing(.4f, 0f, 1f, 1f)
    val Chip: Easing = CubicBezierEasing(.2f, .9f, .2f, 1f)
    val Default: Easing = FastOutSlowInEasing

    const val PALETTE_MS = 150
    const val PALETTE_SETTLE_MS = 180
    const val INSPECTOR_MS = 150
    const val PICKER_MORPH_MS = 85
    const val BAR_HEIGHT_MS = 260
    const val DRUM_SETTLE_MS = 220
    const val TYPE_MS = 180
    const val TICK_MS = 140
    const val TAB_MS = 140
    const val TOGGLE_MS = 160
    const val LOCK_FILTER_MS = 200
    const val OPACITY_MS = 180
    const val REC_MORPH_MS = 220
    const val ZOOM_IN_MS = 260
    const val ZOOM_OUT_MS = 180
    const val ZOOM_HOST_MS = 190
    const val PRESS_MS = 120
    const val KNOB_RETURN_MS = 300
    const val CHIP_MS = 220
    const val INSPECTOR_FROM_PX = 28f
}
