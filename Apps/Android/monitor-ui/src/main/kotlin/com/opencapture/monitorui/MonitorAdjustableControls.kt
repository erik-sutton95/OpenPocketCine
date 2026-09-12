package com.opencapture.monitorui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.unit.dp

/** Compact visual; the owning row supplies its toggle action and 44dp hit target. */
@Composable
fun MonitorSwitchGraphic(isOn: Boolean) {
    val position by animateFloatAsState(if (isOn) 18f else 2f, tween(150), label = "switch-thumb")
    Box(Modifier.size(38.dp, 22.dp).background(
        if (isOn) MonitorPalette.accent else Color.White.copy(alpha = .12f), CircleShape)) {
        Box(Modifier.offset(position.dp, 2.dp).size(18.dp).background(Color.White, CircleShape))
    }
}

/** A 3dp track and 14dp thumb inside an accessible 44dp interaction area. */
@Composable
fun MonitorSlider(value: Float, range: ClosedFloatingPointRange<Float>,
    modifier: Modifier = Modifier, onChange: (Float) -> Unit) {
    val start = range.start
    val end = range.endInclusive.coerceAtLeast(start)
    val span = (end - start).coerceAtLeast(.0001f)
    val current by rememberUpdatedState(value.coerceIn(start, end))
    val send by rememberUpdatedState(onChange)
    var cursor by remember { mutableFloatStateOf(current) }
    var dragging by remember { mutableStateOf(false) }
    LaunchedEffect(value, start, end) { if (!dragging) cursor = current }
    fun update(next: Float) {
        if (next.isFinite()) { cursor = next.coerceIn(start, end); send(cursor) }
    }
    Canvas(modifier.fillMaxWidth().height(44.dp).semantics {
        progressBarRangeInfo = ProgressBarRangeInfo(current, start..end)
        setProgress { update(it); true }
    }.pointerInput(start, end) {
        val inset = 7.dp.toPx()
        fun at(x: Float) = start + ((x - inset) / (size.width - 2 * inset).coerceAtLeast(1f)).coerceIn(0f, 1f) * span
        detectTapGestures { update(at(it.x)) }
    }.pointerInput(start, end) {
        val inset = 7.dp.toPx()
        fun at(x: Float) = start + ((x - inset) / (size.width - 2 * inset).coerceAtLeast(1f)).coerceIn(0f, 1f) * span
        detectDragGestures(onDragStart = { dragging = true; update(at(it.x)) },
            onDragEnd = { dragging = false }, onDragCancel = { dragging = false; cursor = current }) { change, _ ->
            change.consume(); update(at(change.position.x))
        }
    }) {
        val inset = 7.dp.toPx()
        val y = size.height / 2f
        val x = inset + ((cursor - start) / span).coerceIn(0f, 1f) * (size.width - 2 * inset)
        drawLine(Color.White.copy(alpha = .12f), Offset(inset, y), Offset(size.width - inset, y), 3.dp.toPx(), StrokeCap.Round)
        drawLine(MonitorPalette.accent, Offset(inset, y), Offset(x, y), 3.dp.toPx(), StrokeCap.Round)
        drawCircle(Color.White, inset, Offset(x, y))
    }
}
