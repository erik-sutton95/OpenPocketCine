package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.math.roundToInt

/**
 * Feed-aligned assist overlays. ZEBRA / FALSE / PEAK do not paint the picture
 * until GPU/AGSL exists; chips still toggle. WAVE / PARADE / VECTOR / LIGHTS
 * draw empty traces + axis — JNI LiveColorScience will feed samples later.
 *
 * [LiveAssistLayer] does not flip the video. See [LiveAssistState.mirror].
 * Pass [playback] to gate chips on [LiveAssistState.isPlaybackVisible] instead of
 * live [LiveAssistState.isVisible] (clean-view pins do not apply).
 */
@Composable
fun LiveAssistLayer(
    tools: Set<LiveAssistTool>,
    guideRatio: Float,
    focus: Pair<Float, Float>?,
    modifier: Modifier = Modifier,
    status: CameraStatus = CameraStatus(),
    locked: Boolean = false,
) {
    val state = remember { LiveAssistState() }
    state.syncVisible(tools, guideRatio)
    LiveAssistLayer(state = state, status = status, focus = focus, modifier = modifier, locked = locked)
}

@Composable
fun LiveAssistLayer(
    state: LiveAssistState,
    status: CameraStatus,
    focus: Pair<Float, Float>?,
    modifier: Modifier = Modifier,
    locked: Boolean = false,
    playback: Boolean = false,
) {
    val density = LocalDensity.current
    val shown: (LiveAssistTool) -> Boolean =
        if (playback) {
            { state.isPlaybackVisible(it) }
        } else {
            { state.isVisible(it) }
        }
    BoxWithConstraints(modifier.fillMaxSize()) {
        val canvas =
            AssistRect(0f, 0f, constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        val feed = canvas
        if (shown(LiveAssistTool.GUIDES)) {
            GuidesOverlay(state, feed)
        }
        if (shown(LiveAssistTool.GRID)) {
            GridOverlay(state, feed)
        }
        if (shown(LiveAssistTool.CROSS)) {
            CrosshairOverlay(feed)
        }
        if (shown(LiveAssistTool.FALSE) && state.falseColorReference) {
            FalseColorReferenceRuler(state, status.colorMode, Modifier.align(Alignment.BottomStart).padding(14.dp, 0.dp, 0.dp, 86.dp))
        }
        if (shown(LiveAssistTool.WAVE)) {
            val sizePx = panelPx(ScopePanelSize.waveform, state.waveScale, density)
            MovableAssistPanel(
                tool = LiveAssistTool.WAVE,
                base = ScopePanelSize.waveform,
                scale = state.waveScale,
                stored = state.waveCenter,
                canvas = canvas,
                defaultCenter = MovablePanelMath.defaultCenterTopLeading(feed, sizePx, canvas, topClearance = 8f),
                enabled = !locked,
                onStore = { state.storeCenter(LiveAssistTool.WAVE, it) },
            ) {
                WaveformPanel(state, status.colorMode, Modifier.fillMaxSize())
            }
        }
        if (shown(LiveAssistTool.PARADE)) {
            val sizePx = panelPx(ScopePanelSize.parade, state.paradeScale, density)
            MovableAssistPanel(
                tool = LiveAssistTool.PARADE,
                base = ScopePanelSize.parade,
                scale = state.paradeScale,
                stored = state.paradeCenter,
                canvas = canvas,
                defaultCenter = MovablePanelMath.defaultCenterTopTrailing(feed, sizePx, canvas, topClearance = 8f),
                enabled = !locked,
                onStore = { state.storeCenter(LiveAssistTool.PARADE, it) },
            ) {
                ParadePanel(state, status.colorMode, Modifier.fillMaxSize())
            }
        }
        if (shown(LiveAssistTool.VECTOR)) {
            val sizePx = panelPx(ScopePanelSize.vectorscope, state.vectorScale, density)
            MovableAssistPanel(
                tool = LiveAssistTool.VECTOR,
                base = ScopePanelSize.vectorscope,
                scale = state.vectorScale,
                stored = state.vectorCenter,
                canvas = canvas,
                defaultCenter = MovablePanelMath.defaultCenterTopTrailing(feed, sizePx, canvas, topClearance = 8f),
                enabled = !locked,
                onStore = { state.storeCenter(LiveAssistTool.VECTOR, it) },
            ) {
                VectorscopePanel(state, Modifier.fillMaxSize())
            }
        }
        if (shown(LiveAssistTool.HISTO)) {
            val sizePx = panelPx(ScopePanelSize.histogram, state.histoScale, density)
            MovableAssistPanel(
                tool = LiveAssistTool.HISTO,
                base = ScopePanelSize.histogram,
                scale = state.histoScale,
                stored = state.histoCenter,
                canvas = canvas,
                defaultCenter = MovablePanelMath.defaultCenterBottomTrailing(feed, sizePx, canvas, bottomClearance = 80f),
                enabled = !locked,
                onStore = { state.storeCenter(LiveAssistTool.HISTO, it) },
            ) {
                HistogramPanel(state, Modifier.fillMaxSize())
            }
        }
        if (shown(LiveAssistTool.LIGHTS)) {
            val sizePx = panelPx(ScopePanelSize.trafficLights, state.lightsScale, density)
            MovableAssistPanel(
                tool = LiveAssistTool.LIGHTS,
                base = ScopePanelSize.trafficLights,
                scale = state.lightsScale,
                stored = state.lightsCenter,
                canvas = canvas,
                defaultCenter = MovablePanelMath.defaultCenterBottomLeading(feed, sizePx, canvas, bottomClearance = 80f),
                enabled = !locked,
                onStore = { state.storeCenter(LiveAssistTool.LIGHTS, it) },
            ) {
                TrafficLightsPanel(state, Modifier.fillMaxSize())
            }
        }
        if (!playback && shown(LiveAssistTool.AUDIO)) {
            val meters = status.audioMetersLeftRight()
            if (meters != null) {
                val channels = meters.asMeterChannels()
                Box(
                    Modifier
                        .align(Alignment.BottomStart)
                        .padding(start = 14.dp, bottom = 86.dp)
                        .size(AudioAssist.PANEL_WIDTH_DP.dp, AudioAssist.PANEL_HEIGHT_DP.dp)
                        .scopePanelChrome(),
                ) {
                    AudioMetersPanel(
                        left = channels.first,
                        right = channels.second,
                        sensitivity = status.audioLabel,
                    )
                }
            }
        }
        if (!playback && focus != null) {
            val fx = if (shown(LiveAssistTool.MIRROR)) 1f - focus.first else focus.first
            FocusBox(fx, focus.second)
        }
    }
}

@Composable
private fun GuidesOverlay(state: LiveAssistState, feed: AssistRect) {
    val selected = state.selectedGuides.ifEmpty { setOf(state.guideAspect) }
    val frames =
        selected.sortedBy { it.ratio }.map { it to GuidesAssist.rectForRatio(feed, it.ratio) }
    Canvas(Modifier.fillMaxSize()) {
        if (state.guideMask && frames.isNotEmpty()) {
            val mask = Color.Black.copy(alpha = 0.6f)
            val holes = frames.map { it.second }
            val minL = holes.minOf { it.minX }
            val maxR = holes.maxOf { it.maxX }
            val minT = holes.minOf { it.minY }
            val maxB = holes.maxOf { it.maxY }
            drawRect(mask, Offset(feed.minX, feed.minY), Size(feed.width, (minT - feed.minY).coerceAtLeast(0f)))
            drawRect(mask, Offset(feed.minX, maxB), Size(feed.width, (feed.maxY - maxB).coerceAtLeast(0f)))
            drawRect(mask, Offset(feed.minX, minT), Size((minL - feed.minX).coerceAtLeast(0f), (maxB - minT).coerceAtLeast(0f)))
            drawRect(mask, Offset(maxR, minT), Size((feed.maxX - maxR).coerceAtLeast(0f), (maxB - minT).coerceAtLeast(0f)))
        }
        for ((aspect, frame) in frames) {
            drawRect(
                LiveDesign.accent.copy(alpha = 0.85f),
                Offset(frame.minX, frame.minY),
                Size(frame.width, frame.height),
                style = Stroke(1.dp.toPx()),
            )
        }
    }
    frames.forEach { (aspect, frame) ->
        Text(
            aspect.label,
            color = LiveDesign.accent,
            fontSize = 10.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.2.sp,
            modifier =
                Modifier
                    .offset { IntOffset((frame.minX + 34f).roundToInt(), (frame.minY + 13f).roundToInt()) }
                    .clip(RoundedCornerShape(5.dp))
                    .background(Color.Black.copy(alpha = 0.42f))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

@Composable
private fun GridOverlay(state: LiveAssistState, feed: AssistRect) {
    val lines = GridAssist.segments(feed, state.gridThirds, state.gridPhi, state.gridDiagonal)
    Canvas(Modifier.fillMaxSize()) {
        val stroke = GridAssist.STROKE_WIDTH_DP.dp.toPx()
        val color = Color.White.copy(alpha = GridAssist.STROKE_OPACITY)
        for (segment in lines) {
            drawLine(color, Offset(segment.from.x, segment.from.y), Offset(segment.to.x, segment.to.y), stroke)
        }
    }
}

@Composable
private fun CrosshairOverlay(feed: AssistRect) {
    Canvas(Modifier.fillMaxSize()) {
        val color = Color.White.copy(alpha = CrosshairAssist.OPACITY)
        val arm = CrosshairAssist.ARM_LENGTH_DP.dp.toPx()
        val stroke = CrosshairAssist.STROKE_WIDTH_DP.dp.toPx()
        val cx = feed.midX
        val cy = feed.midY
        drawRect(color, Offset(cx - stroke / 2f, cy - arm / 2f), Size(stroke, arm))
        drawRect(color, Offset(cx - arm / 2f, cy - stroke / 2f), Size(arm, stroke))
    }
}

@Composable
private fun FocusBox(nx: Float, ny: Float) {
    Canvas(Modifier.fillMaxSize()) {
        val side = minOf(size.width, size.height) * 0.14f
        val cx = nx * size.width
        val cy = ny * size.height
        drawRect(
            LiveDesign.accent,
            Offset(cx - side / 2f, cy - side / 2f),
            Size(side, side),
            style = Stroke(1.5.dp.toPx()),
        )
    }
}

@Composable
private fun FalseColorReferenceRuler(state: LiveAssistState, colorMode: Int, modifier: Modifier = Modifier) {
    val bands =
        when (state.falseColorScale) {
            FalseColorScale.IRE -> FalseColorBands.ireBands()
            FalseColorScale.LIMITS -> FalseColorBands.limitBands()
            FalseColorScale.STOPS -> FalseColorBands.ireBands()
        }
    val curve =
        when (colorMode) {
            com.opencapture.openpocketcine.session.CameraCommands.COLOR_DLOG2 -> "D-Log2"
            com.opencapture.openpocketcine.session.CameraCommands.COLOR_DLOG -> "D-Log"
            com.opencapture.openpocketcine.session.CameraCommands.COLOR_HDR -> "HLG"
            else -> "709"
        }
    Box(
        modifier
            .size(ScopePanelSize.falseColorReference.width.dp, ScopePanelSize.falseColorReference.height.dp)
            .clip(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))
            .background(LiveDesign.glass)
            .padding(7.dp),
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val barH = 8.dp.toPx()
            val barY = 14.dp.toPx()
            val barW = size.width
            drawRect(Color.White.copy(alpha = 0.12f), Offset(0f, barY), Size(barW, barH))
            for (band in bands) {
                val lo = (band.lowerBound / 100.0).toFloat().coerceIn(0f, 1f)
                val hi =
                    if (band.upperBound.isFinite()) {
                        (band.upperBound / 100.0).toFloat().coerceIn(0f, 1f)
                    } else {
                        1f
                    }
                drawRect(
                    Color(band.red.toFloat(), band.green.toFloat(), band.blue.toFloat()),
                    Offset(barW * lo, barY),
                    Size(maxOf(1f, barW * (hi - lo)), barH),
                )
            }
        }
        Text(
            "False Color",
            color = LiveDesign.text,
            fontSize = 8.5.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.align(Alignment.TopStart),
        )
        Text(
            "${state.falseColorScale.menuLabel} · $curve",
            color = LiveDesign.muted,
            fontSize = 7.5.sp,
            fontFamily = FontFamily.Monospace,
            modifier = Modifier.align(Alignment.TopEnd),
        )
    }
}

private fun panelPx(
    base: AssistSize,
    scale: Double,
    density: androidx.compose.ui.unit.Density,
): AssistSize {
    val scaled = MovablePanelMath.panelSize(base, scale)
    return with(density) { AssistSize(scaled.width.dp.toPx(), scaled.height.dp.toPx()) }
}
