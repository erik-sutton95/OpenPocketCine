package com.opencapture.monitorui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt

/** 56dp detents and continuously projected 78dp cells, independent of camera commands. */
@Composable
fun MonitorValueDrum(options: List<String>, selection: String, modifier: Modifier = Modifier,
    markedValues: Set<String> = emptySet(), interactive: Boolean = true,
    displayPosition: Float? = null, dimDisabled: Boolean = true, onSelect: (String) -> Unit) {
    if (options.isEmpty()) return
    var cursor by remember(options) { mutableFloatStateOf(options.indexOf(selection).coerceAtLeast(0).toFloat()) }
    var dragging by remember(options) { mutableStateOf(false) }
    var expected by remember(options) { mutableStateOf<String?>(null) }
    var cancelled by remember(options) { mutableStateOf(false) }
    val send by rememberUpdatedState(onSelect)
    val actualSelection by rememberUpdatedState(selection)
    val density = LocalDensity.current
    val detent = with(density) { 56.dp.toPx() }
    val cell = with(density) { 78.dp.toPx() }
    val textMeasurer = rememberTextMeasurer()
    LaunchedEffect(selection, options, interactive) {
        if (selection != expected || !interactive) {
            // An authoritative change cancels the pending gesture. Unknown values
            // seat visually on the first option but do not send a camera write.
            cancelled = dragging
            dragging = false
            cursor = options.indexOf(selection).coerceAtLeast(0).toFloat()
        }
        expected = null
    }
    fun choose(position: Float) {
        cursor = position.coerceIn(0f, options.lastIndex.toFloat())
        val value = options[cursor.roundToInt()]
        if (value != expected && value != actualSelection) {
            expected = value
            send(value)
        }
    }
    val rendered by animateFloatAsState(displayPosition ?: cursor, animationSpec = if (dragging || displayPosition != null) snap() else tween(160), label = "drum detent")
    Canvas(modifier.fillMaxWidth().height(86.dp).alpha(if (interactive || !dimDisabled) 1f else .45f)
        .semantics {
            contentDescription = selection.ifBlank { "Choose value" }
            progressBarRangeInfo = ProgressBarRangeInfo(cursor, 0f..options.lastIndex.toFloat(), (options.size - 2).coerceAtLeast(0))
            if (interactive) setProgress { choose(it.roundToInt().toFloat()); true }
        }
        .pointerInput(options, interactive) {
            if (interactive) detectTapGestures { point ->
                choose((cursor + (point.x - size.width / 2f) / cell).roundToInt().toFloat())
            }
        }
        .pointerInput(options, interactive) {
            if (interactive) detectHorizontalDragGestures(
                onDragStart = { dragging = true; cancelled = false },
                onDragCancel = { dragging = false; cursor = options.indexOf(actualSelection).coerceAtLeast(0).toFloat() },
                onDragEnd = { dragging = false; if (!cancelled) choose(cursor.roundToInt().toFloat()) },
                onHorizontalDrag = { change, delta ->
                    change.consume()
                    if (!cancelled) cursor = (cursor - delta / detent).coerceIn(0f, options.lastIndex.toFloat())
                })
        }) {
        val center = size.width / 2f
        val visible = (size.width / cell / 2f).toInt() + 2
        val projectedPosition = MonitorDrumSelection.projectedPosition(rendered)
        val base = rendered.roundToInt()
        for (index in (base - visible).coerceAtLeast(0)..(base + visible).coerceAtMost(options.lastIndex)) {
            val distance = index - projectedPosition
            val projection = cos((distance * .24f).coerceIn(-1.4f, 1.4f))
            val emphasis = (1f - abs(distance)).coerceIn(0f, 1f)
            val x = center + distance * cell
            val edgeAlpha = (minOf(x, size.width - x) / (size.width * .14f)).coerceIn(0f, 1f)
            val tint = androidx.compose.ui.graphics.lerp(MonitorPalette.muted, MonitorPalette.text, emphasis).copy(alpha = edgeAlpha)
            val text = options[index]
            val layout = textMeasurer.measure(text, MonitorTypography.readout(15f + 8f * emphasis, FontWeight.Medium), maxLines = 1)
            withTransform({ scale(projection, projection, Offset(x, size.height * .43f)) }) {
                drawText(layout, color = tint, topLeft = Offset(x - layout.size.width / 2f, size.height * .43f - layout.size.height / 2f))
            }
            if (options[index] in markedValues) drawCircle(MonitorPalette.accent.copy(alpha = edgeAlpha),
                radius = 2.dp.toPx(), center = Offset(x, 9.dp.toPx()))
            drawLine(if (index == base) MonitorPalette.accent else MonitorPalette.faint.copy(alpha = edgeAlpha),
                Offset(x, size.height - 8.dp.toPx()), Offset(x, size.height - (17f + 6f * emphasis).dp.toPx()),
                strokeWidth = 2.dp.toPx())
        }
    }
}
