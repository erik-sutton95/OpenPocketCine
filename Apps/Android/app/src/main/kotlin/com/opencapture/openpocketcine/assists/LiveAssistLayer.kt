package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.feed.fromColorMode

import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import com.opencapture.opencine.dji.CameraStatus
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
        scopeBus = remember { LiveScopeSampleBus() },
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
    scopeBus: LiveScopeSampleBus,
    status: CameraStatus,
    focus: Pair<Float, Float>?,
    modifier: Modifier = Modifier,
    locked: Boolean = false,
    playback: Boolean = false,
    tracking: com.opencapture.opencine.dji.TrackingHud =
        com.opencapture.opencine.dji.TrackingHud(),
    showTapFocusBox: Boolean = true,
    /** AE lock: the focus box turns yellow with an `AE-L` tag. */
    aeLocked: Boolean = false,
    /** Long-press lock on the tap-focus box: a lock tag at its lower corner. */
    focusLocked: Boolean = false,
    /** Picture well in the same space as [modifier]; defaults to the layer box. */
    feedFrame: ChromeRect? = null,
    /** Recorded image within the source raster, excluding camera-added padding. AF keeps [feedFrame]. */
    framingFrame: ChromeRect? = null,
    /** Clear space between fixed controls, in dp. Storage still uses the full canvas. */
    placementFrame: ChromeRect? = null,
    /** Audio defaults at the safe leading edge, independent of the expanded palette. */
    audioPlacementFrame: ChromeRect? = null,
    /** Live 180 / MIRROR compose. Defaults to the MIRROR chip. */
    pictureMirrored: Boolean = state.mirrorsHorizontally,
    /** MIRROR Vertical. */
    pictureFlippedVertically: Boolean = state.flipsVertically,
    onOpenOptions: ((LiveAssistTool, ChromeRect) -> Unit)? = null,
    showsAudio: Boolean = true,
    /** WAVE / PARADE / FALSE ruler. Playback passes clip color; live uses [CameraStatus.monitorColorMode]. */
    colorMode: Int = status.monitorColorMode,
) {
    val density = LocalDensity.current
    val shown: (LiveAssistTool) -> Boolean =
        if (playback) {
            { state.isPlaybackVisible(it) }
        } else {
            { state.isVisible(it) }
        }
    val scopePublication by scopeBus.publications.collectAsState()
    state.acceptScopeBundle(scopePublication.bundle)
    BoxWithConstraints(
        modifier
            .fillMaxSize(),
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
        val framingFeed = framingFrame?.let { frame -> with(density) {
            AssistRect(frame.x.dp.toPx(), frame.y.dp.toPx(), frame.width.dp.toPx(), frame.height.dp.toPx())
        } } ?: feed
        val placement = with(density) {
            val frame = placementFrame ?: ChromeRect(56f, 56f,
                maxOf(0f, canvas.width / density.density - 112f),
                maxOf(0f, canvas.height / density.density - 166f))
            val padding = 8.dp.toPx()
            AssistRect(frame.x.dp.toPx() + padding, frame.y.dp.toPx() + padding,
                maxOf(0f, frame.width.dp.toPx() - 2 * padding),
                maxOf(0f, frame.height.dp.toPx() - 2 * padding))
        }
        if (shown(LiveAssistTool.GUIDES)) {
            GuidesOverlay(state, framingFeed)
        }
        if (shown(LiveAssistTool.GRID)) {
            GridOverlay(state, framingFeed)
        }
        if (shown(LiveAssistTool.CROSS)) {
            CrosshairOverlay(framingFeed)
        }
        if (shown(LiveAssistTool.FALSE) && state.falseColorReference) {
            val portrait = canvas.height > canvas.width
            MovableAssistPanel(LiveAssistTool.FALSE, ScopePanelSize.falseColorReference, 1.0,
                state.centerFor(LiveAssistTool.FALSE, portrait), canvas, placement, AssistPoint(canvas.midX, canvas.midY),
                enabled = !locked, onStore = { state.storeCenter(LiveAssistTool.FALSE, it, portrait) }, fillPlate = false,
                onOpenOptions = onOpenOptions?.let { open -> { open(LiveAssistTool.FALSE, it) } }) {
                FalseColorReferenceRuler(state, colorMode, Modifier.fillMaxSize())
            }
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
                    flippedVertically = pictureFlippedVertically,
                    showTapFocusBox = showTapFocusBox && focus != null,
                    aeLocked = aeLocked,
                    focusLocked = focusLocked,
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
                        canvas = canvas,
                        placementBounds = placement,
                        feed = feed,
                        density = density,
                        locked = locked,
                        onOpenOptions = onOpenOptions,
                        colorMode = colorMode,
                    )
                }
            }
        }
        if (!playback && showsAudio && shown(LiveAssistTool.AUDIO)) {
            val channels = audioOverlayChannels(status)
            val audioPlacement = audioPlacementFrame?.let { frame -> with(density) {
                val inset = 8.dp.toPx()
                AssistRect(frame.x.dp.toPx() + inset, frame.y.dp.toPx() + inset,
                    maxOf(0f, frame.width.dp.toPx() - 2 * inset), maxOf(0f, frame.height.dp.toPx() - 2 * inset))
            } } ?: placement
            AssistAudioOverlay(state, channels.first, channels.second, canvas, audioPlacement, locked,
                onOpenOptions = onOpenOptions?.let { open -> { open(LiveAssistTool.AUDIO, it) } })
        }
    }
}

@Composable
private fun StackedScopePanel(
    tool: LiveAssistTool,
    state: LiveAssistState,
    canvas: AssistRect,
    placementBounds: AssistRect,
    feed: AssistRect,
    density: androidx.compose.ui.unit.Density,
    locked: Boolean,
    onOpenOptions: ((LiveAssistTool, ChromeRect) -> Unit)?,
    colorMode: Int,
) {
    val portrait = canvas.height > canvas.width
    val (base, scale, stored, onScale) =
        when (tool) {
            LiveAssistTool.WAVE ->
                ScopePanelSpec(
                    ScopePanelSize.waveform,
                    state.waveScale,
                    state.centerFor(LiveAssistTool.WAVE, portrait),
                    { state.setScale(LiveAssistTool.WAVE, it) },
                )
            LiveAssistTool.PARADE ->
                ScopePanelSpec(
                    ScopePanelSize.parade,
                    state.paradeScale,
                    state.centerFor(LiveAssistTool.PARADE, portrait),
                    { state.setScale(LiveAssistTool.PARADE, it) },
                )
            LiveAssistTool.VECTOR ->
                ScopePanelSpec(
                    ScopePanelSize.vectorscope,
                    state.vectorScale,
                    state.centerFor(LiveAssistTool.VECTOR, portrait),
                    { state.setScale(LiveAssistTool.VECTOR, it) },
                )
            LiveAssistTool.HISTO ->
                ScopePanelSpec(
                    ScopePanelSize.histogram,
                    state.histoScale,
                    state.centerFor(LiveAssistTool.HISTO, portrait),
                    { state.setScale(LiveAssistTool.HISTO, it) },
                )
            LiveAssistTool.LIGHTS ->
                ScopePanelSpec(
                    ScopePanelSize.trafficLights,
                    state.lightsScale,
                    state.centerFor(LiveAssistTool.LIGHTS, portrait),
                    { state.setScale(LiveAssistTool.LIGHTS, it) },
                )
            LiveAssistTool.ND ->
                ScopePanelSpec(
                    ScopePanelSize.ndMeter,
                    state.ndScale,
                    state.centerFor(LiveAssistTool.ND, portrait),
                    { state.setScale(LiveAssistTool.ND, it) },
                )
            LiveAssistTool.LUT,
            LiveAssistTool.PEAK,
            LiveAssistTool.FALSE,
            LiveAssistTool.ZEBRA,
            LiveAssistTool.EV,
            LiveAssistTool.LEVEL,
            LiveAssistTool.AUDIO,
            LiveAssistTool.GUIDES,
            LiveAssistTool.GRID,
            LiveAssistTool.CROSS,
            LiveAssistTool.MIRROR,
            LiveAssistTool.DESQ,
            -> return
        }
    MovableAssistPanel(
            tool = tool,
            base = base,
            scale = scale,
            stored = stored,
            canvas = canvas,
            placementBounds = placementBounds,
            defaultCenter = AssistPoint(canvas.midX, canvas.midY),
            enabled = !locked,
            onStore = { state.storeCenter(tool, it, portrait) },
            onScale = onScale,
            onOpenOptions = onOpenOptions?.let { present -> { frame -> present(tool, frame) } },
            onActivate = { state.bringToFront(tool) },
            fillPlate = true,
            chip = tool == LiveAssistTool.ND,
        ) {
            when (tool) {
                LiveAssistTool.WAVE -> WaveformPanel(state, colorMode, Modifier.fillMaxSize())
                LiveAssistTool.PARADE -> ParadePanel(state, colorMode, Modifier.fillMaxSize())
                LiveAssistTool.VECTOR -> VectorscopePanel(state, Modifier.fillMaxSize())
                LiveAssistTool.HISTO -> HistogramPanel(state, Modifier.fillMaxSize())
                LiveAssistTool.LIGHTS -> TrafficLightsPanel(state, Modifier.fillMaxSize())
                LiveAssistTool.ND -> NDMeterPanel(state, Modifier.fillMaxSize())
                LiveAssistTool.LUT,
                LiveAssistTool.PEAK,
                LiveAssistTool.FALSE,
                LiveAssistTool.ZEBRA,
                LiveAssistTool.EV,
                LiveAssistTool.LEVEL,
                LiveAssistTool.AUDIO,
                LiveAssistTool.GUIDES,
                LiveAssistTool.GRID,
                LiveAssistTool.CROSS,
                LiveAssistTool.MIRROR,
            LiveAssistTool.DESQ,
                -> {}
            }
        }
}

private data class ScopePanelSpec(
    val base: AssistSize,
    val scale: Double,
    val stored: StoredCenter?,
    val onScale: (Double) -> Unit,
)

private fun scopePanelShape() = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

@Composable
private fun GuidesOverlay(state: LiveAssistState, feed: AssistRect) {
    com.opencapture.monitorui.MonitorAspectGuideFrames(
        state.selectedGuides.ifEmpty { setOf(state.guideAspect) }, feed, state.guideMask,
        maskPolicy = com.opencapture.monitorui.MonitorGuideMaskPolicy.ENVELOPE,
    )
}

@Composable
private fun GridOverlay(state: LiveAssistState, feed: AssistRect) {
    com.opencapture.monitorui.MonitorFeedGrid(feed, state.gridThirds, state.gridPhi, state.gridDiagonal)
}

@Composable
private fun CrosshairOverlay(feed: AssistRect) {
    com.opencapture.monitorui.MonitorFeedCrosshair(feed)
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
internal fun FalseColorReferenceRuler(state: LiveAssistState, colorMode: Int, modifier: Modifier = Modifier) {
    com.opencapture.monitorui.MonitorFalseColorReference(falseColorReferenceValues(state, colorMode), modifier)
}

internal fun falseColorReferenceValues(state: LiveAssistState, colorMode: Int):
    com.opencapture.monitorui.MonitorFalseColorReferenceValues {
    val transfer = MonitorTransfer.fromColorMode(colorMode)
    val rec709 = state.falseColorRec709
    val segments = FalseColorReference.segments(state.falseColorScale, transfer, rec709, state.scopeDisplayCeiling)
    val markers =
        if (state.falseColorScale.usesSceneStops) {
            FalseColorReference.sceneStopMarkers(transfer, rec709, state.scopeDisplayCeiling)
        } else {
            emptyList()
        }
    return com.opencapture.monitorui.MonitorFalseColorReferenceValues(
            subtitle = "${state.falseColorScale.menuLabel} · ${FalseColorReference.curveKeyLabel(colorMode, rec709)}",
            segments = segments.mapIndexed { index, segment ->
                com.opencapture.monitorui.MonitorFalseColorReferenceSegment(index,
                    segment.lowerFraction, segment.upperFraction, segment.band.red, segment.band.green, segment.band.blue)
            },
            markers = markers.mapIndexed { index, marker ->
                com.opencapture.monitorui.MonitorFalseColorReferenceMarker(index, marker.label, marker.fraction)
            },
            axisLabels = FalseColorReference.axisLabels(state.falseColorScale))
}

private fun panelPx(
    base: AssistSize,
    scale: Double,
    density: androidx.compose.ui.unit.Density,
): AssistSize {
    val scaled = MovablePanelMath.panelSize(base, scale)
    return with(density) { AssistSize(scaled.width.dp.toPx(), scaled.height.dp.toPx()) }
}
