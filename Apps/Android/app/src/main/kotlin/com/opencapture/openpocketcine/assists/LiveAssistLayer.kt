package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.zIndex
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.ChromeRect
import com.opencapture.openpocketcine.LiveDesign

import com.opencapture.openpocketcine.feed.GpuOverlayBus
import com.opencapture.openpocketcine.feed.LiveScopeSampleBus
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.math.roundToInt

/**
 * Feed-aligned assist overlays. LUT / PEAK / FALSE / ZEBRA paint through the
 * GLES live feed (`LiveFeedEffectsSession`); this layer draws guides, scopes,
 * and the false-colour ruler. WAVE / PARADE / HISTO / VECTOR / LIGHTS read
 * the GLES tap on [com.opencapture.openpocketcine.feed.LiveScopeSampleBus].
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
    onOpenOptions: ((LiveAssistTool, ChromeRect) -> Unit)? = null,
) {
    val state = remember { LiveAssistState() }
    state.syncVisible(tools, guideRatio)
    LiveAssistLayer(
        state = state,
        status = status,
        focus = focus,
        modifier = modifier,
        locked = locked,
        onOpenOptions = onOpenOptions,
    )
}

@Composable
fun LiveAssistLayer(
    state: LiveAssistState,
    status: CameraStatus,
    focus: Pair<Float, Float>?,
    modifier: Modifier = Modifier,
    locked: Boolean = false,
    playback: Boolean = false,
    tracking: com.opencapture.openpocketcine.session.TrackingHud =
        com.opencapture.openpocketcine.session.TrackingHud(),
    showTapFocusBox: Boolean = true,
    /** Picture well in the same space as [modifier]; defaults to the layer box. */
    feedFrame: ChromeRect? = null,
    /** Live 180 / MIRROR compose. Defaults to the MIRROR chip. */
    pictureMirrored: Boolean = state.mirror,
    onOpenOptions: ((LiveAssistTool, ChromeRect) -> Unit)? = null,
) {
    val density = LocalDensity.current
    val shown: (LiveAssistTool) -> Boolean =
        if (playback) {
            { state.isPlaybackVisible(it) }
        } else {
            { state.isVisible(it) }
        }
    state.acceptScopeBundle(LiveScopeSampleBus.bundle)
    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .onGloballyPositioned { GpuOverlayBus.layerRoot = it.positionInRoot() },
    ) {
        val canvas =
            AssistRect(0f, 0f, constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        val feed =
            if (feedFrame == null) {
                canvas
            } else {
                with(density) {
                    AssistRect(
                        feedFrame.x.dp.toPx(),
                        feedFrame.y.dp.toPx(),
                        feedFrame.width.dp.toPx(),
                        feedFrame.height.dp.toPx(),
                    )
                }
            }
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
        if (!playback) {
            Box(
                Modifier
                    .offset { IntOffset(feed.minX.roundToInt(), feed.minY.roundToInt()) }
                    .size(
                        with(density) { feed.width.toDp() },
                        with(density) { feed.height.toDp() },
                    )
                    .zIndex(0f),
            ) {
                com.opencapture.openpocketcine.LiveFocusTrackingLayer(
                    hud = tracking,
                    focus = focus,
                    mirrored = pictureMirrored,
                    showTapFocusBox = showTapFocusBox && focus != null,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        val stack = state.scopeStack
        LaunchedEffect(stack) { GpuOverlayBus.onSlotsMoved?.invoke() }
        val zRanks = stack.withIndex().associate { it.value to it.index + 1f }
        LiveAssistState.stackableScopeTools.forEach { tool ->
            if (!shown(tool)) return@forEach
            key(tool) {
                Box(Modifier.fillMaxSize().zIndex(zRanks[tool] ?: 1f)) {
                    StackedScopePanel(
                        tool = tool,
                        state = state,
                        status = status,
                        canvas = canvas,
                        feed = feed,
                        density = density,
                        locked = locked,
                        onOpenOptions = onOpenOptions,
                    )
                }
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
                        .clip(scopePanelShape())
                        .background(LiveDesign.scopePlate)
                        .border(1.dp, LiveDesign.hairline, scopePanelShape())
                        .zIndex(0.5f),
                ) {
                    AudioMetersPanel(
                        left = channels.first,
                        right = channels.second,
                        sensitivity = status.audioLabel,
                    )
                }
            }
        }
    }
}

@Composable
private fun StackedScopePanel(
    tool: LiveAssistTool,
    state: LiveAssistState,
    status: CameraStatus,
    canvas: AssistRect,
    feed: AssistRect,
    density: androidx.compose.ui.unit.Density,
    locked: Boolean,
    onOpenOptions: ((LiveAssistTool, ChromeRect) -> Unit)?,
) {
    val (base, scale, stored, defaultCenter, onScale) =
        when (tool) {
            LiveAssistTool.WAVE ->
                ScopePanelSpec(
                    ScopePanelSize.waveform,
                    state.waveScale,
                    state.waveCenter,
                    MovablePanelMath.defaultCenterTopLeading(
                        feed,
                        panelPx(ScopePanelSize.waveform, state.waveScale, density),
                        canvas,
                        topClearance = 8f,
                    ),
                    { state.setScale(LiveAssistTool.WAVE, it) },
                )
            LiveAssistTool.PARADE ->
                ScopePanelSpec(
                    ScopePanelSize.parade,
                    state.paradeScale,
                    state.paradeCenter,
                    MovablePanelMath.defaultCenterTopTrailing(
                        feed,
                        panelPx(ScopePanelSize.parade, state.paradeScale, density),
                        canvas,
                        topClearance = 8f,
                    ),
                    { state.setScale(LiveAssistTool.PARADE, it) },
                )
            LiveAssistTool.VECTOR ->
                ScopePanelSpec(
                    ScopePanelSize.vectorscope,
                    state.vectorScale,
                    state.vectorCenter,
                    MovablePanelMath.defaultCenterTopTrailing(
                        feed,
                        panelPx(ScopePanelSize.vectorscope, state.vectorScale, density),
                        canvas,
                        topClearance = 8f,
                    ),
                    { state.setScale(LiveAssistTool.VECTOR, it) },
                )
            LiveAssistTool.HISTO ->
                ScopePanelSpec(
                    ScopePanelSize.histogram,
                    state.histoScale,
                    state.histoCenter,
                    MovablePanelMath.defaultCenterBottomTrailing(
                        feed,
                        panelPx(ScopePanelSize.histogram, state.histoScale, density),
                        canvas,
                        bottomClearance = 80f,
                    ),
                    { state.setScale(LiveAssistTool.HISTO, it) },
                )
            LiveAssistTool.LIGHTS ->
                ScopePanelSpec(
                    ScopePanelSize.trafficLights,
                    state.lightsScale,
                    state.lightsCenter,
                    MovablePanelMath.defaultCenterBottomLeading(
                        feed,
                        panelPx(ScopePanelSize.trafficLights, state.lightsScale, density),
                        canvas,
                        bottomClearance = 80f,
                    ),
                    { state.setScale(LiveAssistTool.LIGHTS, it) },
                )
            LiveAssistTool.LUT,
            LiveAssistTool.PEAK,
            LiveAssistTool.FALSE,
            LiveAssistTool.ZEBRA,
            LiveAssistTool.AUDIO,
            LiveAssistTool.GUIDES,
            LiveAssistTool.GRID,
            LiveAssistTool.CROSS,
            LiveAssistTool.MIRROR,
            -> return
        }
    MovableAssistPanel(
            tool = tool,
            base = base,
            scale = scale,
            stored = stored,
            canvas = canvas,
            defaultCenter = defaultCenter,
            enabled = !locked,
            onStore = { state.storeCenter(tool, it) },
            onScale = onScale,
            onOpenOptions = onOpenOptions?.let { present -> { frame -> present(tool, frame) } },
            onActivate = { state.bringToFront(tool) },
            fillPlate = tool == LiveAssistTool.LIGHTS,
        ) {
            when (tool) {
                LiveAssistTool.WAVE -> WaveformPanel(state, status.colorMode, Modifier.fillMaxSize())
                LiveAssistTool.PARADE -> ParadePanel(state, status.colorMode, Modifier.fillMaxSize())
                LiveAssistTool.VECTOR -> VectorscopePanel(state, Modifier.fillMaxSize())
                LiveAssistTool.HISTO -> HistogramPanel(state, Modifier.fillMaxSize())
                LiveAssistTool.LIGHTS -> TrafficLightsPanel(state, Modifier.fillMaxSize())
                LiveAssistTool.LUT,
                LiveAssistTool.PEAK,
                LiveAssistTool.FALSE,
                LiveAssistTool.ZEBRA,
                LiveAssistTool.AUDIO,
                LiveAssistTool.GUIDES,
                LiveAssistTool.GRID,
                LiveAssistTool.CROSS,
                LiveAssistTool.MIRROR,
                -> {}
            }
        }
}

private data class ScopePanelSpec(
    val base: AssistSize,
    val scale: Double,
    val stored: StoredCenter?,
    val defaultCenter: AssistPoint,
    val onScale: (Double) -> Unit,
)

private fun scopePanelShape() = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

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
    val transfer = MonitorTransfer.fromColorMode(colorMode)
    val segments = FalseColorReference.segments(state.falseColorScale, transfer)
    val markers =
        if (state.falseColorScale == FalseColorScale.STOPS) {
            FalseColorReference.stopAxisMarkers(transfer)
        } else {
            emptyList()
        }
    val axis = FalseColorReference.axisLabels(state.falseColorScale)
    val curve = FalseColorReference.curveKeyLabel(colorMode)
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
            for (segment in segments) {
                val lo = segment.lowerFraction.toFloat()
                val hi = segment.upperFraction.toFloat()
                drawRect(
                    Color(
                        segment.band.red.toFloat(),
                        segment.band.green.toFloat(),
                        segment.band.blue.toFloat(),
                    ),
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
        if (markers.isNotEmpty()) {
            Box(Modifier.align(Alignment.BottomStart).fillMaxSize().padding(top = 26.dp)) {
                markers.forEach { marker ->
                    Text(
                        marker.label,
                        color = LiveDesign.muted,
                        fontSize = 5.5.sp,
                        fontFamily = FontFamily.Monospace,
                        modifier =
                            Modifier.offset(
                                x = (ScopePanelSize.falseColorReference.width * marker.fraction.toFloat() - 10f).dp,
                                y = 0.dp,
                            ),
                    )
                }
            }
        } else if (axis.isNotEmpty()) {
            Row(
                Modifier.align(Alignment.BottomStart).fillMaxSize().padding(top = 26.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                axis.forEach { label ->
                    Text(
                        label,
                        color = LiveDesign.muted,
                        fontSize = 5.5.sp,
                        fontFamily = FontFamily.Monospace,
                    )
                }
            }
        }
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
