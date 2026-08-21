package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.ChromeShape
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.chromeClickable

/**
 * OpenZCine `AssistToolCell`: 19dp glyph over a 9sp mono label. On-state is
 * iOS `AssistToolChip`: accent-dim fill plus a 1pt accent stroke.
 */
@Composable
internal fun AssistToolCell(
    tool: LiveAssistTool,
    isOn: Boolean,
    enabled: Boolean,
    onLongClick: (() -> Unit)?,
    onClick: () -> Unit,
) {
    val tint = if (isOn) LiveDesign.accent else LiveDesign.muted
    Column(
        modifier =
            Modifier
                .background(if (isOn) LiveDesign.accentDim else Color.Transparent, ChromeShape)
                .border(1.dp, if (isOn) LiveDesign.accent else Color.Transparent, ChromeShape)
                .chromeClickable(
                    enabled = enabled,
                    onLongClick = onLongClick,
                    onClick = onClick,
                )
                .padding(vertical = 5.dp, horizontal = 8.dp)
                .widthIn(min = 36.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.height(23.dp), contentAlignment = Alignment.Center) {
            AssistToolGlyph(tool, tint, Modifier.size(19.dp))
        }
        Text(
            tool.chipLabel,
            style = LiveType.mono(9f, FontWeight.Medium).copy(letterSpacing = 0.9.sp),
            color = tint,
            maxLines = 1,
        )
    }
}

/** Cyan edge chevron hinting at off-screen tools (OpenZCine `ScrollChevron`). */
@Composable
internal fun AssistScrollChevron(leading: Boolean, visible: Boolean, modifier: Modifier = Modifier) {
    Canvas(
        modifier
            .padding(horizontal = 5.dp)
            .size(8.dp, 12.dp)
            .alpha(if (visible) 1f else 0f),
    ) {
        val path =
            Path().apply {
                if (leading) {
                    moveTo(size.width, 0f)
                    lineTo(0f, size.height / 2)
                    lineTo(size.width, size.height)
                } else {
                    moveTo(0f, 0f)
                    lineTo(size.width, size.height / 2)
                    lineTo(0f, size.height)
                }
            }
        drawPath(
            path,
            LiveDesign.accent,
            style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
    }
}

/** Canvas stand-ins for the iOS SF Symbol per Pocket tool (`AssistToolIcon`). */
@Composable
internal fun AssistToolGlyph(tool: LiveAssistTool, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val stroke = Stroke(1.6.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
        when (tool) {
            // SF `camera.filters`: three overlapping circles.
            LiveAssistTool.LUT -> {
                val r = size.minDimension * 0.28f
                drawCircle(tint, r, Offset(size.width / 2, r), style = stroke)
                drawCircle(tint, r, Offset(r, size.height - r), style = stroke)
                drawCircle(tint, r, Offset(size.width - r, size.height - r), style = stroke)
            }
            // SF `mountain.2`: two peaks.
            LiveAssistTool.PEAK -> {
                val base = size.height * 0.85f
                val path =
                    Path().apply {
                        moveTo(0f, base)
                        lineTo(size.width * 0.32f, size.height * 0.25f)
                        lineTo(size.width * 0.52f, base * 0.72f)
                        lineTo(size.width * 0.70f, size.height * 0.42f)
                        lineTo(size.width, base)
                    }
                drawPath(path, tint, style = stroke)
            }
            // SF `circle.lefthalf.filled`.
            LiveAssistTool.FALSE -> {
                val r = size.minDimension / 2 - 1.dp.toPx()
                val c = Offset(size.width / 2, size.height / 2)
                drawCircle(tint, r, c, style = stroke)
                drawArc(
                    tint,
                    startAngle = 90f,
                    sweepAngle = 180f,
                    useCenter = true,
                    topLeft = Offset(c.x - r, c.y - r),
                    size = Size(2 * r, 2 * r),
                )
            }
            // Three diagonal stripes (iOS `ZebraStripesShape`).
            LiveAssistTool.ZEBRA -> {
                val diag = 0.7071f
                val halfLen = size.minDimension * 0.40f / 2
                val step = size.minDimension * 0.27f
                for (index in 0 until 3) {
                    val offset = index - 1f
                    val cx = size.width / 2 + offset * step * diag
                    val cy = size.height / 2 + offset * step * diag
                    drawLine(
                        tint,
                        Offset(cx - halfLen * 2 * diag, cy + halfLen * 2 * diag),
                        Offset(cx + halfLen * 2 * diag, cy - halfLen * 2 * diag),
                        strokeWidth = 2.dp.toPx(),
                        cap = StrokeCap.Round,
                    )
                }
            }
            // SF `waveform.path`: one luma trace line.
            LiveAssistTool.WAVE -> {
                val midY = size.height / 2
                val path =
                    Path().apply {
                        moveTo(0f, midY)
                        lineTo(size.width * 0.2f, midY - size.height * 0.32f)
                        lineTo(size.width * 0.4f, midY + size.height * 0.28f)
                        lineTo(size.width * 0.6f, midY - size.height * 0.18f)
                        lineTo(size.width * 0.8f, midY + size.height * 0.34f)
                        lineTo(size.width, midY)
                    }
                drawPath(path, tint, style = stroke)
            }
            // SF `chart.bar.xaxis`: bars on a baseline.
            LiveAssistTool.PARADE -> {
                val base = size.height * 0.82f
                drawLine(tint, Offset(0f, base), Offset(size.width, base), 1.6.dp.toPx())
                val barW = size.width * 0.17f
                for ((index, heightScale) in listOf(0.45f, 0.75f, 0.6f).withIndex()) {
                    drawRoundRect(
                        tint,
                        topLeft = Offset(size.width * (0.1f + 0.3f * index), base - base * heightScale),
                        size = Size(barW, base * heightScale),
                        cornerRadius = CornerRadius(barW * 0.3f),
                    )
                }
            }
            // SF `waveform`: symmetric level bars.
            LiveAssistTool.HISTO -> {
                val midY = size.height / 2
                for ((index, heightScale) in listOf(0.25f, 0.55f, 0.9f, 0.45f, 0.7f, 0.3f).withIndex()) {
                    val x = size.width * (0.08f + 0.168f * index)
                    drawLine(
                        tint,
                        Offset(x, midY - size.height * heightScale / 2),
                        Offset(x, midY + size.height * heightScale / 2),
                        strokeWidth = 1.8.dp.toPx(),
                        cap = StrokeCap.Round,
                    )
                }
            }
            // SF `circle.grid.cross`: graticule circle + cross.
            LiveAssistTool.VECTOR -> {
                val r = size.minDimension / 2 - 1.dp.toPx()
                val c = Offset(size.width / 2, size.height / 2)
                drawCircle(tint, r, c, style = stroke)
                val gap = r * 0.4f
                drawLine(tint, Offset(c.x, c.y - r), Offset(c.x, c.y - gap), 1.6.dp.toPx())
                drawLine(tint, Offset(c.x, c.y + gap), Offset(c.x, c.y + r), 1.6.dp.toPx())
                drawLine(tint, Offset(c.x - r, c.y), Offset(c.x - gap, c.y), 1.6.dp.toPx())
                drawLine(tint, Offset(c.x + gap, c.y), Offset(c.x + r, c.y), 1.6.dp.toPx())
            }
            // Three compact RED-style goal posts: top clip dots, centre line, bottom crush dots.
            LiveAssistTool.LIGHTS -> {
                val columns = listOf(0.2f, 0.5f, 0.8f)
                val top = size.height * 0.16f
                val bottom = size.height * 0.84f
                val centre = size.height / 2
                for (xFraction in columns) {
                    val x = size.width * xFraction
                    drawCircle(tint, size.minDimension * 0.075f, Offset(x, top))
                    drawLine(
                        tint,
                        Offset(x, top + size.height * 0.13f),
                        Offset(x, bottom - size.height * 0.13f),
                        1.6.dp.toPx(),
                    )
                    drawLine(
                        tint,
                        Offset(x - size.width * 0.10f, centre),
                        Offset(x + size.width * 0.10f, centre),
                        1.2.dp.toPx(),
                    )
                    drawCircle(tint, size.minDimension * 0.075f, Offset(x, bottom))
                }
            }
            // SF `rectangle.dashed`: delivery frame guides.
            LiveAssistTool.GUIDES -> {
                val inset = size.minDimension * 0.16f
                val dash = size.minDimension * 0.16f
                val top = inset
                val bottom = size.height - inset
                val left = inset * 0.58f
                val right = size.width - left
                drawLine(tint, Offset(left, top), Offset(left + dash, top), 1.5.dp.toPx())
                drawLine(tint, Offset(right - dash, top), Offset(right, top), 1.5.dp.toPx())
                drawLine(tint, Offset(left, bottom), Offset(left + dash, bottom), 1.5.dp.toPx())
                drawLine(tint, Offset(right - dash, bottom), Offset(right, bottom), 1.5.dp.toPx())
                drawLine(tint, Offset(left, top), Offset(left, top + dash), 1.5.dp.toPx())
                drawLine(tint, Offset(right, top), Offset(right, top + dash), 1.5.dp.toPx())
                drawLine(tint, Offset(left, bottom - dash), Offset(left, bottom), 1.5.dp.toPx())
                drawLine(tint, Offset(right, bottom - dash), Offset(right, bottom), 1.5.dp.toPx())
            }
            // SF `grid`: thirds and phi composition lines.
            LiveAssistTool.GRID -> {
                val fractions = listOf(1f / 3f, 2f / 3f)
                fractions.forEach { fraction ->
                    val x = size.width * fraction
                    val y = size.height * fraction
                    drawLine(tint, Offset(x, 1.dp.toPx()), Offset(x, size.height - 1.dp.toPx()), 1.3.dp.toPx())
                    drawLine(tint, Offset(1.dp.toPx(), y), Offset(size.width - 1.dp.toPx(), y), 1.3.dp.toPx())
                }
            }
            // SF `plus`: centre crosshair.
            LiveAssistTool.CROSS -> {
                val centre = Offset(size.width / 2, size.height / 2)
                val arm = size.minDimension * 0.42f
                drawLine(tint, Offset(centre.x - arm, centre.y), Offset(centre.x + arm, centre.y), 1.7.dp.toPx())
                drawLine(tint, Offset(centre.x, centre.y - arm), Offset(centre.x, centre.y + arm), 1.7.dp.toPx())
            }
            // SF `arrow.left.and.right.righttriangle.left.righttriangle.right`.
            LiveAssistTool.MIRROR -> {
                val y = size.height / 2
                val inset = size.width * 0.10f
                val head = size.minDimension * 0.26f
                drawLine(
                    tint,
                    Offset(size.width / 2, size.height * 0.12f),
                    Offset(size.width / 2, size.height * 0.88f),
                    1.4.dp.toPx(),
                    StrokeCap.Round,
                )
                drawPath(
                    Path().apply {
                        moveTo(inset, y - head)
                        lineTo(inset, y + head)
                        lineTo(inset + head, y)
                        close()
                    },
                    tint,
                )
                drawPath(
                    Path().apply {
                        moveTo(size.width - inset, y - head)
                        lineTo(size.width - inset, y + head)
                        lineTo(size.width - inset - head, y)
                        close()
                    },
                    tint,
                )
            }
            // SF `slider.vertical.3`: three compact audio level bars.
            LiveAssistTool.AUDIO -> {
                val columns = listOf(0.25f, 0.5f, 0.75f)
                val levels = listOf(0.48f, 0.84f, 0.62f)
                val top = size.height * 0.14f
                val bottom = size.height * 0.86f
                columns.zip(levels).forEach { (fraction, level) ->
                    val x = size.width * fraction
                    drawLine(tint.copy(alpha = 0.36f), Offset(x, top), Offset(x, bottom), 1.4.dp.toPx())
                    drawLine(
                        tint,
                        Offset(x, bottom - (bottom - top) * level),
                        Offset(x, bottom),
                        2.2.dp.toPx(),
                        cap = StrokeCap.Round,
                    )
                }
            }
        }
    }
}
