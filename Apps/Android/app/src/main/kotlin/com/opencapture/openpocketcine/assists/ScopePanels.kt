package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.LiveDesign
import kotlin.math.roundToInt

private val PanelShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
private val PanelFill = Color(0.025f, 0.036f, 0.03f, 0.72f)
private val Boundary = Color(220 / 255f, 235 / 255f, 225 / 255f, 0.8f)
private val ClipColor = Color(255 / 255f, 150 / 255f, 142 / 255f, 0.8f)
private val MiddleColor = Color(246 / 255f, 241 / 255f, 226 / 255f, 0.8f)
private val GridFaint = Color(220 / 255f, 235 / 255f, 225 / 255f, 0.10f)
private val HistoGreen = Color(0f, 238 / 255f, 70 / 255f, 0.15f)
private val VectorRing = Color(220 / 255f, 235 / 255f, 225 / 255f, 0.55f)
private val VectorFaint = Color(220 / 255f, 235 / 255f, 225 / 255f, 0.30f)
private val MeterRed = Color(255 / 255f, 92 / 255f, 82 / 255f)
private val MeterGreen = Color(86 / 255f, 235 / 255f, 132 / 255f)
private val MeterBlue = Color(96 / 255f, 158 / 255f, 255 / 255f)
private val MeterYellow = Color(245 / 255f, 208 / 255f, 82 / 255f)

@Composable
internal fun MovableAssistPanel(
    tool: LiveAssistTool,
    base: AssistSize,
    scale: Double,
    stored: StoredCenter?,
    canvas: AssistRect,
    defaultCenter: AssistPoint,
    enabled: Boolean,
    onStore: (StoredCenter) -> Unit,
    content: @Composable (AssistSize) -> Unit,
) {
    val density = LocalDensity.current
    val sizeDp = MovablePanelMath.panelSize(base, scale)
    val sizePx = with(density) { AssistSize(sizeDp.width.dp.toPx(), sizeDp.height.dp.toPx()) }
    var session by remember(tool, canvas.width, canvas.height) { mutableStateOf<AssistPoint?>(null) }
    var origin by remember { mutableStateOf<AssistPoint?>(null) }
    val center =
        MovablePanelMath.resolvedCenter(
            session = session,
            stored = stored,
            defaultCenter = defaultCenter,
            size = sizePx,
            bounds = canvas,
        )
    Box(
        Modifier
            .offset {
                IntOffset((center.x - sizePx.width / 2f).roundToInt(), (center.y - sizePx.height / 2f).roundToInt())
            }
            .size(sizeDp.width.dp, sizeDp.height.dp)
            .shadow(16.dp, PanelShape, ambientColor = Color.Black.copy(alpha = 0.34f))
            .clip(PanelShape)
            .background(PanelFill)
            .border(1.dp, LiveDesign.hairline, PanelShape)
            .pointerInput(tool, enabled, sizePx.width, sizePx.height, canvas.width, canvas.height) {
                detectHoldThenDrag(
                    holdMs = AssistLongPress.PANEL_MS,
                    enabled = enabled,
                    onHold = { origin = center },
                    onDrag = { translation ->
                        val start = origin ?: center
                        val proposed = AssistPoint(start.x + translation.x, start.y + translation.y)
                        session = MovablePanelMath.clamp(MovablePanelMath.snap(proposed), sizePx, canvas)
                    },
                    onEnd = {
                        val final = session ?: center
                        onStore(StoredCenter(final, canvas))
                        origin = null
                    },
                )
            },
    ) {
        content(sizeDp)
    }
}

@Composable
internal fun WaveformPanel(state: LiveAssistState, colorMode: Int, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.fillMaxSize()) {
        val plot = WaveformAxis.plotRect(this.size.width, this.size.height)
        drawWaveGuides(plot, state.waveGuides, colorMode)
        drawScopeTitle(measurer, "WAVE", state.waveMode.label.uppercase())
    }
}

@Composable
internal fun ParadePanel(state: LiveAssistState, colorMode: Int, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.fillMaxSize()) {
        val plot = WaveformAxis.plotRect(this.size.width, this.size.height)
        val laneW = ParadeAssist.laneWidth(state.paradeMode, plot)
        for (i in 1 until state.paradeMode.laneCount) {
            val x = plot.minX + i * laneW
            drawLine(GridFaint, Offset(x, plot.minY), Offset(x, plot.maxY), 1f)
        }
        drawWaveGuides(plot, state.paradeGuides, colorMode)
        val labels = state.paradeMode.laneLabels
        labels.forEachIndexed { i, label ->
            val x = plot.minX + i * laneW + 4f
            drawText(
                measurer,
                label,
                Offset(x, plot.maxY - 12f),
                TextStyle(color = LiveDesign.text.copy(alpha = 0.45f), fontSize = 8.sp, fontFamily = FontFamily.Monospace),
            )
        }
        drawScopeTitle(measurer, "PARADE", ParadeAssist.chip(state.paradeMode))
    }
}

@Composable
internal fun HistogramPanel(state: LiveAssistState, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val bins = state.lumaHistogram ?: LiveLumaHistogram.empty()
    Canvas(modifier.fillMaxSize()) {
        val plot = HistogramAssist.plotRect(this.size.width, this.size.height)
        for (step in 1 until 4) {
            val y = plot.minY + plot.height * step / 4f
            drawLine(GridFaint.copy(alpha = 0.06f), Offset(plot.minX, y), Offset(plot.maxX, y), 1f)
        }
        val peak = bins.maxOrNull()?.coerceAtLeast(1) ?: 1
        val last = bins.size - 1
        if (last > 0 && bins.any { it > 0 }) {
            val path = Path()
            var started = false
            for (i in bins.indices) {
                val x = HistogramAssist.plotX(i / last.toDouble() * 100.0, plot)
                val h = (bins[i].toFloat() / peak) * plot.height
                val y = plot.maxY - h
                if (!started) {
                    path.moveTo(x, plot.maxY)
                    path.lineTo(x, y)
                    started = true
                } else {
                    path.lineTo(x, y)
                }
            }
            path.lineTo(HistogramAssist.plotX(100.0, plot), plot.maxY)
            path.close()
            drawPath(path, HistoGreen)
        } else {
            val binW = (plot.width / LiveLumaHistogram.BINS).coerceAtLeast(0.4f)
            for (i in 0 until LiveLumaHistogram.BINS) {
                val x = HistogramAssist.plotX(i / 255.0 * 100.0, plot)
                drawRect(GridFaint.copy(alpha = 0.18f), Offset(x, plot.maxY - 2f), Size(binW, 2f))
            }
        }
        val x0 = HistogramAssist.ireX(0.0, plot)
        val x100 = HistogramAssist.ireX(100.0, plot)
        drawLine(Boundary, Offset(x0, plot.minY), Offset(x0, plot.maxY), 1.25f)
        drawLine(Boundary, Offset(x100, plot.minY), Offset(x100, plot.maxY), 1.25f)
        if (state.histoTrafficLights) {
            drawTrafficLamps(plot)
        }
        drawScopeTitle(measurer, HistogramAssist.PANEL_TITLE.uppercase(), HistogramAssist.CHIP)
    }
}

@Composable
internal fun VectorscopePanel(state: LiveAssistState, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.fillMaxSize()) {
        val plot = VectorscopeGraticule.plotSquare(this.size.width, this.size.height)
        drawCircle(VectorRing, radius = plot.width / 2f, center = Offset(plot.midX, plot.midY), style = Stroke(1.25f))
        drawLine(
            VectorFaint,
            Offset(plot.midX - VectorscopeGraticule.CROSS_ARM, plot.midY),
            Offset(plot.midX + VectorscopeGraticule.CROSS_ARM, plot.midY),
            1f,
        )
        drawLine(
            VectorFaint,
            Offset(plot.midX, plot.midY - VectorscopeGraticule.CROSS_ARM),
            Offset(plot.midX, plot.midY + VectorscopeGraticule.CROSS_ARM),
            1f,
        )
        val skin = VectorscopeGraticule.skinEnd(plot)
        drawLine(
            MiddleColor,
            Offset(plot.midX, plot.midY),
            Offset(skin.x, skin.y),
            1f,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f)),
        )
        val box = VectorscopeGraticule.BOX_SIDE
        for (target in VectorscopeGraticule.targets) {
            val pt = VectorscopeGraticule.targetCenter(target.red, target.green, target.blue, plot)
            drawRect(VectorRing, Offset(pt.x - box / 2f, pt.y - box / 2f), Size(box, box), style = Stroke(1f))
            val dx = pt.x - plot.midX
            val dy = pt.y - plot.midY
            val len = maxOf(1f, kotlin.math.hypot(dx, dy))
            drawText(
                measurer,
                target.label,
                Offset(pt.x + dx / len * VectorscopeGraticule.LABEL_PUSH - 4f, pt.y + dy / len * VectorscopeGraticule.LABEL_PUSH - 4f),
                TextStyle(color = VectorRing, fontSize = 6.5.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold),
            )
        }
        drawScopeTitle(measurer, "VECTOR", VectorscopeAssist.chip(state.vectorZoom))
    }
}

@Composable
internal fun TrafficLightsPanel(@Suppress("UNUSED_PARAMETER") state: LiveAssistState, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.fillMaxSize()) {
        val ui = minOf(this.size.width / ScopePanelSize.trafficLights.width, this.size.height / ScopePanelSize.trafficLights.height)
        val pad = TrafficLightsAssist.PANEL_PAD * ui
        drawText(
            measurer,
            TrafficLightsAssist.METER_TITLE,
            Offset(pad, pad),
            TextStyle(
                color = LiveDesign.text.copy(alpha = 0.58f),
                fontSize = 8.5.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
            ),
        )
        val colW = TrafficLightsAssist.TRACK_WIDTH * ui
        val colH = TrafficLightsAssist.COLUMN_HEIGHT * ui
        val gap = TrafficLightsAssist.COLUMN_SPACING * ui
        val startX = (this.size.width - (colW * 3 + gap * 2)) / 2f
        val top = pad + TrafficLightsAssist.TITLE_SIZE * ui + TrafficLightsAssist.TITLE_SPACING * ui
        val colors = listOf(MeterRed, MeterGreen, MeterBlue)
        colors.forEachIndexed { i, color ->
            val x = startX + i * (colW + gap)
            drawGoalPost(x, top, colW, colH, color, ui)
        }
    }
}

@Composable
internal fun AudioMetersPanel(
    left: AudioMeterReading,
    right: AudioMeterReading,
    sensitivity: String?,
    modifier: Modifier = Modifier,
) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.size(AudioAssist.PANEL_WIDTH_DP.dp, AudioAssist.PANEL_HEIGHT_DP.dp)) {
        drawText(
            measurer,
            "AUDIO",
            Offset(2f, 4f),
            TextStyle(color = LiveDesign.text.copy(alpha = 0.58f), fontSize = 6.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold),
        )
        val labelReserve = 22f
        val bars = AssistRect(0f, 16f, this.size.width, this.size.height - labelReserve - 16f)
        for (mark in AudioAssist.guideMarks) {
            val y = AudioAssist.y(mark, bars.minY, bars.maxY)
            drawLine(Color(220 / 255f, 235 / 255f, 225 / 255f, 0.10f), Offset(bars.minX, y), Offset(bars.maxX, y), 1f)
        }
        val gap = 2f
        val inset = 1f
        val barW = (bars.width - gap - inset * 2) / 2f
        listOf("L" to left, "R" to right).forEachIndexed { index, pair ->
            val x = bars.minX + inset + index * (barW + gap)
            val track = AssistRect(x, bars.minY, barW, bars.height)
            drawRoundRect(
                LiveDesign.text.copy(alpha = 0.08f),
                Offset(track.minX, track.minY),
                Size(track.width, track.height),
                CornerRadius(2f, 2f),
            )
            val levelY = AudioAssist.y(pair.second.levelDB, track.minY, track.maxY)
            if (levelY < track.maxY - 0.5f) {
                val bands =
                    listOf(
                        AudioAssist.FLOOR_DB to AudioAssist.YELLOW_FROM_DB,
                        AudioAssist.YELLOW_FROM_DB to AudioAssist.RED_FROM_DB,
                        AudioAssist.RED_FROM_DB to 0.0,
                    )
                for (band in bands) {
                    val top = AudioAssist.y(band.second, track.minY, track.maxY).coerceAtLeast(levelY)
                    val bottom = AudioAssist.y(band.first, track.minY, track.maxY).coerceAtLeast(levelY)
                    if (bottom > top) {
                        drawRect(zoneColor(band.first), Offset(track.minX, top), Size(track.width, bottom - top))
                    }
                }
            }
            if (pair.second.peakDB > AudioAssist.FLOOR_DB + 0.5) {
                val peakY = AudioAssist.y(pair.second.peakDB, track.minY, track.maxY)
                drawLine(zoneColor(pair.second.peakDB), Offset(track.minX, peakY), Offset(track.maxX, peakY), 1.5f)
            }
            drawText(
                measurer,
                pair.first,
                Offset(track.midX - 3f, this.size.height - 18f),
                TextStyle(color = LiveDesign.text.copy(alpha = 0.58f), fontSize = 7.5.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold),
            )
        }
        drawText(
            measurer,
            "SENS",
            Offset(2f, this.size.height - 12f),
            TextStyle(color = LiveDesign.text.copy(alpha = 0.42f), fontSize = 5.sp, fontFamily = FontFamily.Monospace),
        )
        drawText(
            measurer,
            AudioAssist.displayedSensitivity(sensitivity),
            Offset(this.size.width / 2f - 6f, this.size.height - 12f),
            TextStyle(color = LiveDesign.text.copy(alpha = 0.72f), fontSize = 8.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold),
        )
    }
}

private fun DrawScope.drawWaveGuides(plot: AssistRect, guides: ScopeGuides, colorMode: Int) {
    val gray = WaveformAxis.middleGrayIRE(colorMode)
    for (stroke in WaveformAxis.guideStrokes(guides.clip, guides.crush, guides.middle, colorMode)) {
        val y = WaveformAxis.plotY(stroke.ire, plot)
        val isGray = kotlin.math.abs(stroke.ire - gray) < 0.05
        val color = if (stroke.crushClip) ClipColor else if (isGray) MiddleColor else Boundary
        val effect = if (stroke.dashed) PathEffect.dashPathEffect(WaveformAxis.crushClipDash) else null
        drawLine(color, Offset(plot.minX, y), Offset(plot.maxX, y), if (isGray) 1f else 1.25f, pathEffect = effect)
    }
}

private fun DrawScope.drawScopeTitle(measurer: TextMeasurer, title: String, chip: String) {
    drawText(
        measurer,
        title,
        Offset(8f, 4f),
        TextStyle(color = LiveDesign.text.copy(alpha = 0.66f), fontSize = 10.5.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold),
    )
    val chipLayout =
        measurer.measure(
            chip,
            TextStyle(color = LiveDesign.text.copy(alpha = 0.58f), fontSize = 9.5.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold),
        )
    drawText(chipLayout, topLeft = Offset(size.width - chipLayout.size.width - 8f, 5f))
}

private fun DrawScope.drawTrafficLamps(plot: AssistRect) {
    val w = HistogramAssist.TRAFFIC_LAMP_WIDTH
    val h = HistogramAssist.TRAFFIC_LAMP_HEIGHT
    val left = HistogramAssist.TRAFFIC_OUTER_PAD
    val right = size.width - HistogramAssist.TRAFFIC_OUTER_PAD - w
    val colors = listOf(MeterRed, MeterGreen, MeterBlue)
    colors.forEachIndexed { i, color ->
        val y = 12f + i * (h + 3f)
        drawRoundRect(Color.Transparent, Offset(left, y), Size(w, h), CornerRadius(2f), style = Stroke(1.5f))
        drawRoundRect(color.copy(alpha = 0.8f), Offset(left, y), Size(w, h), CornerRadius(2f), style = Stroke(1.5f))
        drawRoundRect(color.copy(alpha = 0.8f), Offset(right, y), Size(w, h), CornerRadius(2f), style = Stroke(1.5f))
    }
}

private fun DrawScope.drawGoalPost(x: Float, top: Float, colW: Float, colH: Float, color: Color, ui: Float) {
    val indicator = TrafficLightsAssist.INDICATOR_SIZE * ui
    val postGap = TrafficLightsAssist.POST_SPACING * ui
    drawCircle(Color.Transparent, indicator / 2f, Offset(x + colW / 2f, top + indicator / 2f), style = Stroke(maxOf(1f, 1.5f * ui)))
    drawCircle(color.copy(alpha = 0.75f), indicator / 2f, Offset(x + colW / 2f, top + indicator / 2f), style = Stroke(maxOf(1f, 1.5f * ui)))
    val trackTop = top + indicator + postGap
    val trackH = colH
    val centerH = maxOf(1f, ui * TrafficLightsAssist.CENTER_LINE_FACTOR)
    val half = (trackH - centerH) / 2f
    val corner = CornerRadius(TrafficLightsAssist.TRACK_CORNER * ui)
    drawRoundRect(LiveDesign.text.copy(alpha = 0.08f), Offset(x, trackTop), Size(colW, half), corner)
    drawRect(LiveDesign.text.copy(alpha = 0.14f), Offset(x, trackTop + half), Size(colW, centerH))
    drawRoundRect(LiveDesign.text.copy(alpha = 0.08f), Offset(x, trackTop + half + centerH), Size(colW, half), corner)
    val crushY = trackTop + trackH + postGap + indicator / 2f
    drawCircle(color.copy(alpha = 0.75f), indicator / 2f, Offset(x + colW / 2f, crushY), style = Stroke(maxOf(1f, 1.5f * ui)))
}

private fun zoneColor(db: Double): Color =
    when {
        db >= AudioAssist.RED_FROM_DB -> MeterRed.copy(alpha = 0.95f)
        db >= AudioAssist.YELLOW_FROM_DB -> MeterYellow.copy(alpha = 0.95f)
        else -> MeterGreen.copy(alpha = 0.9f)
    }

internal fun Modifier.scopePanelChrome(): Modifier =
    clip(PanelShape).background(PanelFill).border(1.dp, LiveDesign.hairline, PanelShape)
