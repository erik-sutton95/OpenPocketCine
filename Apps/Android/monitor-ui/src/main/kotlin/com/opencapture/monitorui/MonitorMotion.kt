package com.opencapture.monitorui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.FastOutSlowInEasing

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/** Pointer samples remain local; only a completed drag stores a preference. */
@Stable
class MonitorFloatingDrag<Position> {
    var origin: Position? = null
        private set
    var preview: Position? by mutableStateOf(null)
        private set

    fun begin(at: Position) { origin = at; preview = null }
    fun move(to: Position) { if (origin != null) preview = to }
    fun end(store: (Position) -> Unit) {
        val final = preview
        cancel()
        if (final != null) store(final)
    }
    fun cancel() { origin = null; preview = null }
}

/** Original pointer input reaches the excluded control; other outside taps minimize. */
@Composable
fun MonitorMotionDismissBackdrop(viewport: Rect, excluding: Rect, onDismiss: () -> Unit) {
    val density = LocalDensity.current
    val dismiss by rememberUpdatedState(onDismiss)
    val pieces = remember(viewport, excluding) { monitorDismissRegions(viewport, listOf(excluding)) }
    val configuration = LocalViewConfiguration.current
    val exactTargets = remember(configuration) {
        object : ViewConfiguration by configuration {
            override val minimumTouchTargetSize: DpSize = DpSize.Zero
        }
    }
    CompositionLocalProvider(LocalViewConfiguration provides exactTargets) {
        pieces.forEach { rect ->
            Box(Modifier.absoluteOffset {
                IntOffset(with(density) { rect.left.dp.toPx() }.roundToInt(),
                    with(density) { rect.top.dp.toPx() }.roundToInt())
            }.size(rect.width.dp, rect.height.dp)
                .pointerInput(Unit) { detectTapGestures { dismiss() } })
        }
    }
}

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
