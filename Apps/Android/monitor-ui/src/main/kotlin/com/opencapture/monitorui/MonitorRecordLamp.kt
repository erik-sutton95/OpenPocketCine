package com.opencapture.monitorui

import android.animation.ValueAnimator
import android.graphics.Paint
import android.view.ViewTreeObserver
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import kotlin.math.round

/** Bright/dim phase; removed from composition while the window is inactive. */
@Composable
fun monitorPulsePhase(periodMillis: Int, enabled: Boolean = true): Float {
    val view = LocalView.current
    var active by remember(view) { mutableStateOf(view.hasWindowFocus() && view.isShown) }
    DisposableEffect(view) {
        val observer = view.viewTreeObserver
        val listener = ViewTreeObserver.OnWindowFocusChangeListener { focused ->
            active = focused && view.isShown && ValueAnimator.areAnimatorsEnabled()
        }
        observer.addOnWindowFocusChangeListener(listener)
        onDispose { if (observer.isAlive) observer.removeOnWindowFocusChangeListener(listener) }
    }
    if (!enabled || !active || !ValueAnimator.areAnimatorsEnabled()) return 0f
    val transition = rememberInfiniteTransition(label = "monitor-pulse")
    val phase by transition.animateFloat(0f, 1f,
        infiniteRepeatable(tween((periodMillis / 2).coerceAtLeast(1), easing = MonitorMotion.EaseInOut),
            repeatMode = RepeatMode.Reverse), label = "monitor-pulse-phase")
    return phase
}

/** Shared recording artwork. The shell owns confirmation, gestures and commands. */
@Composable
fun MonitorRecordLamp(recording: Boolean, modifier: Modifier = Modifier, photo: Boolean = false) {
    val morph by animateFloatAsState(if (recording) 1f else 0f,
        tween(MonitorMotion.REC_MORPH_MS, easing = MonitorMotion.Soft), label = "record-shape")
    val pulse = monitorPulsePhase(1600, enabled = recording)
    val paint = remember { Paint(Paint.ANTI_ALIAS_FLAG) }
    Canvas(modifier.fillMaxSize().monitorMaterial(MonitorMaterial.Record, androidx.compose.foundation.shape.CircleShape)) {
        val diameter = size.minDimension
        val inset = 5.dp.toPx()
        val stroke = 4.5.dp.toPx()
        val disc = (diameter - inset * 2).coerceAtLeast(0f)
        val ringColor = if (photo) Color.White else MonitorPalette.recording
        drawCircle(ringColor, radius = (disc - stroke).coerceAtLeast(0f) / 2, style = Stroke(stroke))
        if (photo && morph == 0f) {
            drawCircle(Color.White, radius = (diameter / 2 - 12.dp.toPx()).coerceAtLeast(0f))
        }
        val side = round(disc / density * .52f).dp.toPx() * morph
        if (side > 0f) {
            val radius = round(side / density * .24f).dp.toPx()
            val origin = center - Offset(side / 2, side / 2)
            fun core(blur: Float, color: Color) {
                paint.color = MonitorPalette.recording.toArgb()
                paint.setShadowLayer(blur.dp.toPx(), 0f, 0f, color.toArgb())
                drawContext.canvas.nativeCanvas.drawRoundRect(origin.x, origin.y,
                    origin.x + side, origin.y + side, radius, radius, paint)
            }
            // The core stays opaque. Only its two bounded shadows pulse.
            core(13f - 8.5f * pulse, MonitorPalette.recording.copy(alpha = .5f - .36f * pulse))
            core(6f - 4f * pulse, androidx.compose.ui.graphics.lerp(
                Color(0xFFE85A5E).copy(alpha = .9f), MonitorPalette.recording.copy(alpha = .3f), pulse))
            paint.clearShadowLayer()
        }
    }
}
