package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.monitorGlass
import kotlin.math.sqrt

private val ChipShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

@Composable
fun LiveAssistBar(
    enabled: Boolean,
    on: Set<LiveAssistTool>,
    modifier: Modifier = Modifier,
    onToggle: (LiveAssistTool) -> Unit,
) {
    LiveAssistBarRow(
        locked = !enabled,
        isOn = { it in on },
        onClick = onToggle,
        onLongPress = {},
        modifier = modifier,
    )
}

@Composable
fun LiveAssistBar(
    state: LiveAssistState,
    locked: Boolean,
    onLongPress: (LiveAssistTool) -> Unit,
    modifier: Modifier = Modifier,
) {
    LiveAssistBarRow(
        locked = locked,
        isOn = { state.isOn(it) },
        onClick = { state.toggle(it) },
        onLongPress = { tool ->
            if (tool.hasConfiguration) {
                state.configureTool = tool
                onLongPress(tool)
            }
        },
        modifier = modifier,
    )
}

@Composable
private fun LiveAssistBarRow(
    locked: Boolean,
    isOn: (LiveAssistTool) -> Boolean,
    onClick: (LiveAssistTool) -> Unit,
    onLongPress: (LiveAssistTool) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scroll = rememberScrollState()
    val leadingFade = scroll.value > 6
    val trailingFade = scroll.maxValue - scroll.value > 28
    Box(
        modifier
            .height(LiveDesign.CONTROL_HEIGHT_DP.dp)
            .fillMaxWidth()
            .monitorGlass(),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight()
                .horizontalScroll(scroll, enabled = !locked)
                .padding(start = 7.dp, end = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            LiveAssistTool.toolbarCases.forEachIndexed { index, tool ->
                if (index > 0 && index % 3 == 0) AssistDivider()
                AssistBarChip(
                    tool = tool,
                    on = isOn(tool),
                    locked = locked,
                    onClick = { onClick(tool) },
                    onLongPress = { onLongPress(tool) },
                )
            }
            AssistDivider()
            AssistBarChip(
                tool = LiveAssistTool.AUDIO,
                on = isOn(LiveAssistTool.AUDIO),
                locked = locked,
                onClick = { onClick(LiveAssistTool.AUDIO) },
                onLongPress = { onLongPress(LiveAssistTool.AUDIO) },
            )
        }
        if (leadingFade) {
            Box(
                Modifier
                    .align(Alignment.CenterStart)
                    .width(18.dp)
                    .fillMaxHeight()
                    .background(
                        Brush.horizontalGradient(listOf(LiveDesign.glassOpaque, Color.Transparent)),
                    ),
            )
            Text(
                "‹",
                color = LiveDesign.accent,
                fontSize = 14.sp,
                modifier = Modifier.align(Alignment.CenterStart).padding(start = 4.dp),
            )
        }
        if (trailingFade) {
            Box(
                Modifier
                    .align(Alignment.CenterEnd)
                    .width(18.dp)
                    .fillMaxHeight()
                    .background(
                        Brush.horizontalGradient(listOf(Color.Transparent, LiveDesign.glassOpaque)),
                    ),
            )
            Text(
                "›",
                color = LiveDesign.accent,
                fontSize = 14.sp,
                modifier = Modifier.align(Alignment.CenterEnd).padding(end = 4.dp),
            )
        }
    }
}

@Composable
private fun AssistDivider() {
    Box(
        Modifier
            .padding(horizontal = 3.dp)
            .width(1.dp)
            .height(28.dp)
            .background(LiveDesign.hairlineStrong),
    )
}

@Composable
private fun AssistBarChip(
    tool: LiveAssistTool,
    on: Boolean,
    locked: Boolean,
    onClick: () -> Unit,
    onLongPress: () -> Unit,
) {
    val tint = if (on) LiveDesign.accent else LiveDesign.muted
    Column(
        modifier =
            Modifier
                .clip(ChipShape)
                .background(if (on) LiveDesign.accentDim else Color.Transparent)
                .then(if (on) Modifier.border(1.dp, LiveDesign.accent, ChipShape) else Modifier)
                .then(
                    if (tool.hasConfiguration) {
                        Modifier.pointerInput(tool, locked) {
                            detectTapAndLongPress(
                                longPressMs = AssistLongPress.CHIP_MS,
                                enabled = !locked,
                                onTap = onClick,
                                onLongPress = onLongPress,
                            )
                        }
                    } else {
                        Modifier.chromeClickable(enabled = !locked, onClick = onClick)
                    },
                )
                .padding(horizontal = 5.dp, vertical = 5.dp)
                .width(48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        AssistToolGlyph(tool = tool, tint = tint, modifier = Modifier.size(19.dp))
        Text(
            tool.chipLabel,
            color = tint,
            fontSize = 9.sp,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
            letterSpacing = 0.9.sp,
        )
    }
}

@Composable
internal fun AssistToolGlyph(tool: LiveAssistTool, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        val stroke = Stroke(width = maxOf(1.4f, w * 0.09f), cap = StrokeCap.Round)
        val glyphSize = Size(w, h)
        when (tool) {
            LiveAssistTool.LUT -> {
                drawCircle(tint, radius = w * 0.28f, center = Offset(w * 0.38f, h * 0.55f), style = stroke)
                drawCircle(tint, radius = w * 0.22f, center = Offset(w * 0.62f, h * 0.42f), style = stroke)
            }
            LiveAssistTool.PEAK -> {
                val path =
                    Path().apply {
                        moveTo(w * 0.08f, h * 0.82f)
                        lineTo(w * 0.32f, h * 0.42f)
                        lineTo(w * 0.52f, h * 0.62f)
                        lineTo(w * 0.78f, h * 0.22f)
                        lineTo(w * 0.92f, h * 0.82f)
                    }
                drawPath(path, tint, style = stroke)
            }
            LiveAssistTool.FALSE -> {
                drawCircle(tint, radius = w * 0.36f, center = Offset(w / 2f, h / 2f), style = stroke)
                drawArc(
                    tint,
                    -90f,
                    180f,
                    useCenter = true,
                    topLeft = Offset(w * 0.14f, h * 0.14f),
                    size = Size(glyphSize.width * 0.72f, glyphSize.height * 0.72f),
                )
            }
            LiveAssistTool.ZEBRA -> {
                val diag = sqrt(0.5f)
                val half = w * 0.40f / 2f
                val step = w * 0.27f
                for (index in 0 until 3) {
                    val offset = index - 1f
                    val cx = w / 2f + offset * step * diag
                    val cy = h / 2f + offset * step * diag
                    drawLine(
                        tint,
                        Offset(cx - half * diag, cy + half * diag),
                        Offset(cx + half * diag, cy - half * diag),
                        stroke.width,
                        StrokeCap.Round,
                    )
                }
            }
            LiveAssistTool.WAVE -> {
                val path =
                    Path().apply {
                        moveTo(w * 0.08f, h * 0.62f)
                        cubicTo(w * 0.22f, h * 0.18f, w * 0.32f, h * 0.86f, w * 0.48f, h * 0.50f)
                        cubicTo(w * 0.62f, h * 0.18f, w * 0.74f, h * 0.82f, w * 0.92f, h * 0.40f)
                    }
                drawPath(path, tint, style = stroke)
            }
            LiveAssistTool.PARADE -> {
                drawLine(tint, Offset(w * 0.22f, h * 0.82f), Offset(w * 0.22f, h * 0.38f), stroke.width, StrokeCap.Round)
                drawLine(tint, Offset(w * 0.50f, h * 0.82f), Offset(w * 0.50f, h * 0.22f), stroke.width, StrokeCap.Round)
                drawLine(tint, Offset(w * 0.78f, h * 0.82f), Offset(w * 0.78f, h * 0.50f), stroke.width, StrokeCap.Round)
                drawLine(tint, Offset(w * 0.10f, h * 0.82f), Offset(w * 0.90f, h * 0.82f), stroke.width, StrokeCap.Round)
            }
            LiveAssistTool.HISTO -> {
                val path =
                    Path().apply {
                        moveTo(w * 0.08f, h * 0.78f)
                        lineTo(w * 0.22f, h * 0.52f)
                        lineTo(w * 0.38f, h * 0.62f)
                        lineTo(w * 0.58f, h * 0.22f)
                        lineTo(w * 0.78f, h * 0.48f)
                        lineTo(w * 0.92f, h * 0.36f)
                    }
                drawPath(path, tint, style = stroke)
            }
            LiveAssistTool.VECTOR -> {
                drawCircle(tint, radius = w * 0.36f, center = Offset(w / 2f, h / 2f), style = stroke)
                drawLine(tint, Offset(w * 0.22f, h / 2f), Offset(w * 0.78f, h / 2f), 1.2f)
                drawLine(tint, Offset(w / 2f, h * 0.22f), Offset(w / 2f, h * 0.78f), 1.2f)
            }
            LiveAssistTool.LIGHTS -> {
                drawCircle(tint, radius = w * 0.12f, center = Offset(w * 0.28f, h * 0.32f))
                drawCircle(tint, radius = w * 0.12f, center = Offset(w * 0.50f, h * 0.32f))
                drawCircle(tint, radius = w * 0.12f, center = Offset(w * 0.72f, h * 0.32f), style = stroke)
                drawLine(tint, Offset(w * 0.50f, h * 0.46f), Offset(w * 0.50f, h * 0.82f), stroke.width)
            }
            LiveAssistTool.AUDIO -> {
                drawLine(tint, Offset(w * 0.28f, h * 0.72f), Offset(w * 0.28f, h * 0.42f), stroke.width, StrokeCap.Round)
                drawLine(tint, Offset(w * 0.50f, h * 0.72f), Offset(w * 0.50f, h * 0.22f), stroke.width, StrokeCap.Round)
                drawLine(tint, Offset(w * 0.72f, h * 0.72f), Offset(w * 0.72f, h * 0.52f), stroke.width, StrokeCap.Round)
            }
            LiveAssistTool.GUIDES -> {
                drawRect(
                    tint,
                    topLeft = Offset(w * 0.16f, h * 0.22f),
                    size = Size(w * 0.68f, h * 0.56f),
                    style = Stroke(1.4f),
                )
            }
            LiveAssistTool.GRID -> {
                drawLine(tint, Offset(w * 0.16f, h * 0.38f), Offset(w * 0.84f, h * 0.38f), 1.2f)
                drawLine(tint, Offset(w * 0.16f, h * 0.62f), Offset(w * 0.84f, h * 0.62f), 1.2f)
                drawLine(tint, Offset(w * 0.38f, h * 0.18f), Offset(w * 0.38f, h * 0.82f), 1.2f)
                drawLine(tint, Offset(w * 0.62f, h * 0.18f), Offset(w * 0.62f, h * 0.82f), 1.2f)
            }
            LiveAssistTool.CROSS -> {
                drawLine(tint, Offset(w / 2f, h * 0.18f), Offset(w / 2f, h * 0.82f), stroke.width, StrokeCap.Round)
                drawLine(tint, Offset(w * 0.18f, h / 2f), Offset(w * 0.82f, h / 2f), stroke.width, StrokeCap.Round)
            }
            LiveAssistTool.MIRROR -> {
                drawLine(tint, Offset(w * 0.18f, h * 0.50f), Offset(w * 0.82f, h * 0.50f), stroke.width, StrokeCap.Round)
                val left =
                    Path().apply {
                        moveTo(w * 0.32f, h * 0.32f)
                        lineTo(w * 0.18f, h * 0.50f)
                        lineTo(w * 0.32f, h * 0.68f)
                    }
                val right =
                    Path().apply {
                        moveTo(w * 0.68f, h * 0.32f)
                        lineTo(w * 0.82f, h * 0.50f)
                        lineTo(w * 0.68f, h * 0.68f)
                    }
                drawPath(left, tint, style = stroke)
                drawPath(right, tint, style = stroke)
            }
        }
    }
}
