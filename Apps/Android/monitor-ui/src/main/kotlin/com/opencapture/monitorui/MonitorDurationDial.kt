package com.opencapture.monitorui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round

/** Stepped duration ruler. Adapters inject range, formatting and the write. */
object MonitorDurationDialMetrics {
    const val WIDTH = 180f
    const val HEIGHT = 44f
    const val MIN = 0.5
    const val MAX = 120.0
    const val STEP = 0.5
    const val POINTS_PER_STEP = 12f

    /** One normalized domain serves drawing, gestures and accessibility. */
    class Scale(range: ClosedFloatingPointRange<Double>, requestedStep: Double) {
        val range: ClosedFloatingPointRange<Double> = if (
            range.start.toFloat().isFinite() && range.endInclusive.toFloat().isFinite()
        ) min(range.start, range.endInclusive)..max(range.start, range.endInclusive) else MIN..MAX
        private val span = this.range.endInclusive - this.range.start
        val step = requestedStep.takeIf { it.isFinite() && it > 0.0 &&
            span / it < Int.MAX_VALUE - 2.0 } ?: max(STEP, span / (Int.MAX_VALUE - 3.0))
        val accessibilitySteps: Int get() = ((span / step).toInt() - 1).coerceAtLeast(0)
        fun clamp(value: Double): Double = if (value.isFinite()) value.coerceIn(range) else range.start
        fun snap(value: Double): Double {
            val clamped = clamp(value)
            val position = clamped / step
            return if (position.isFinite()) (round(position) * step).coerceIn(range) else clamped
        }
        fun position(value: Double): Float = ((clamp(value) - range.start) / step).toFloat()
        fun valueAt(position: Double): Double = range.start + position * step
    }

    fun snap(value: Double, range: ClosedFloatingPointRange<Double> = MIN..MAX, step: Double = STEP): Double =
        Scale(range, step).snap(value)

    fun afterDrag(
        start: Double,
        translationDp: Float,
        range: ClosedFloatingPointRange<Double> = MIN..MAX,
        step: Double = STEP,
    ): Double {
        val scale = Scale(range, step)
        val translation = translationDp.takeIf { it.isFinite() } ?: 0f
        val delta = -round(translation / POINTS_PER_STEP).toDouble() * scale.step
        return scale.snap(scale.clamp(start) + delta)
    }

    fun label(value: Double, range: ClosedFloatingPointRange<Double> = MIN..MAX, step: Double = STEP): String {
        val snap = snap(value, range, step)
        return if (abs(snap - round(snap)) < 0.05) String.format(Locale.ROOT, "%.0fs", snap)
            else String.format(Locale.ROOT, "%.1fs", snap)
    }

    /** Drop a late SET when the pointer's generation no longer matches. */
    fun accept(token: Int, generation: Int, enabled: Boolean): Boolean =
        enabled && token == generation
}

/**
 * Event-driven stepped number. No idle timer. A generation token drops late
 * SET callbacks when enabled, range or source identity changes.
 */
@Composable
fun MonitorDurationDial(
    value: Double,
    onChange: (Double) -> Unit,
    modifier: Modifier = Modifier,
    range: ClosedFloatingPointRange<Double> = MonitorDurationDialMetrics.MIN..MonitorDurationDialMetrics.MAX,
    step: Double = MonitorDurationDialMetrics.STEP,
    formatter: (Double) -> String = { MonitorDurationDialMetrics.label(it, range, step) },
    enabled: Boolean = true,
    source: Any? = null,
    onStep: () -> Unit = {},
) {
    val density = LocalDensity.current
    val scale = remember(range, step) { MonitorDurationDialMetrics.Scale(range, step) }
    val displayValue = scale.clamp(value)
    val currentValue by rememberUpdatedState(displayValue)
    val update by rememberUpdatedState(onChange)
    val stepFeedback by rememberUpdatedState(onStep)
    var dragStart by remember { mutableStateOf(value) }
    var translation by remember { mutableFloatStateOf(0f) }
    var dragging by remember { mutableStateOf(false) }
    var lastEmitted by remember { mutableStateOf(value) }
    var generation by remember { mutableIntStateOf(0) }
    DisposableEffect(enabled, range.start, range.endInclusive, step, source) {
        generation += 1
        dragging = false
        lastEmitted = value
        onDispose {
            generation += 1
            dragging = false
        }
    }
    val lo = scale.range.start
    val hi = scale.range.endInclusive
    val rulerTarget = if (dragging) {
        (scale.position(dragStart) - translation / MonitorDurationDialMetrics.POINTS_PER_STEP)
            .coerceIn(0f, scale.position(hi))
    } else scale.position(displayValue)
    val rulerPosition by animateFloatAsState(
        rulerTarget,
        animationSpec = if (dragging) snap() else tween(MonitorMotion.DRUM_SETTLE_MS, easing = MonitorMotion.DrumSettle),
        label = "duration-settle",
    )
    fun emit(next: Double, token: Int = generation) {
        if (!MonitorDurationDialMetrics.accept(token, generation, enabled)) return
        val snapped = scale.snap(next)
        if (snapped == lastEmitted) return
        val previous = lastEmitted
        lastEmitted = snapped
        if (MonitorDialHaptic.shouldTick(previous, snapped)) stepFeedback()
        update(snapped)
    }
    Box(
        modifier.size(MonitorDurationDialMetrics.WIDTH.dp, MonitorDurationDialMetrics.HEIGHT.dp)
            .background(ColorWhite07, RoundedCornerShape(8.dp))
            .semantics {
                contentDescription = "Duration"
                stateDescription = formatter(displayValue)
                if (!enabled) disabled()
                progressBarRangeInfo = ProgressBarRangeInfo(
                    displayValue.toFloat(), lo.toFloat()..hi.toFloat(), scale.accessibilitySteps,
                )
                if (enabled) {
                    setProgress { requested ->
                        emit(MonitorDurationDialMetrics.snap(requested.toDouble(), range, step), generation); true
                    }
                    customActions = listOf(
                        CustomAccessibilityAction("Increase duration") {
                            emit(currentValue + scale.step, generation); true
                        },
                        CustomAccessibilityAction("Decrease duration") {
                            emit(currentValue - scale.step, generation); true
                        },
                    )
                }
            }
            .pointerInput(enabled, lo, hi, step, source, generation) {
                if (!enabled) return@pointerInput
                val token = generation
                detectHorizontalDragGestures(
                    onDragStart = {
                        if (token != generation) return@detectHorizontalDragGestures
                        dragStart = currentValue
                        lastEmitted = currentValue
                        translation = 0f
                        dragging = true
                    },
                    onDragEnd = { dragging = false },
                    onDragCancel = { dragging = false },
                ) { change, amount ->
                    if (token != generation || !enabled) return@detectHorizontalDragGestures
                    change.consume()
                    translation += amount / density.density
                    emit(MonitorDurationDialMetrics.afterDrag(dragStart, translation, range, step), token)
                }
            },
        contentAlignment = Alignment.TopCenter,
    ) {
        Text(
            formatter(displayValue),
            color = MonitorPalette.text,
            style = MonitorTypography.text(13f, FontWeight.SemiBold),
            modifier = Modifier.padding(top = 4.dp),
        )
        Canvas(Modifier.fillMaxSize()) {
            val px = 12.dp.toPx()
            val position = rulerPosition.coerceIn(0f, scale.position(hi))
            val index = round(position).toInt()
            for (offset in -8..8) {
                val number = index + offset
                val mark = scale.valueAt(number.toDouble())
                if (mark < lo || mark > hi) continue
                val x = size.width / 2 + (number - position) * px
                val tall = abs(mark - round(mark)) < 0.001
                drawLine(
                    MonitorPalette.text.copy(alpha = if (offset == 0) 0.85f else 0.3f),
                    Offset(x, size.height - if (tall) 13.dp.toPx() else 8.dp.toPx()),
                    Offset(x, size.height - 3.dp.toPx()),
                    strokeWidth = 1.dp.toPx(),
                )
            }
            drawLine(
                MonitorPalette.accent,
                Offset(size.width / 2, size.height - 15.dp.toPx()),
                Offset(size.width / 2, size.height - 2.dp.toPx()),
                strokeWidth = 2.dp.toPx(),
            )
        }
    }
}

private val ColorWhite07 = androidx.compose.ui.graphics.Color.White.copy(alpha = .07f)
