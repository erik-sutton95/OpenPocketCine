package com.opencapture.openpocketcine

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.selection.selectable
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.material3.Slider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.opencapture.openpocketcine.session.GimbalHudCopy
import com.opencapture.openpocketcine.session.GimbalMode
import com.opencapture.openpocketcine.session.GimbalMoveEngine
import com.opencapture.openpocketcine.session.GimbalProgramCurve
import com.opencapture.openpocketcine.session.GimbalProgram
import com.opencapture.openpocketcine.session.GimbalRamp
import com.opencapture.openpocketcine.session.GimbalSpeed
import com.opencapture.openpocketcine.session.GimbalWaypointSlot
import kotlin.math.max
import kotlin.math.min

enum class LiveGimbalPanel {
    NONE,
    SHEET,
    EDITOR,
    RUN_PILL,
}

private const val SHEET_WIDTH_DP = 340f
private const val EDITOR_WIDTH_DP = 340f
private const val HOLD_MS = 300L

@Composable
fun LiveGimbalButton(
    locked: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier
            .size(LiveDesign.ZOOM_CHIP_DP.dp)
            .monitorGlass(CircleShape)
            .chromeClickable(enabled = !locked, onClick = onClick)
            .semantics { contentDescription = "Gimbal controls" },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(
            OpcIcon.CROSSHAIR,
            contentDescription = null,
            modifier = Modifier.size(18.dp).alpha(if (locked) 0.4f else 1f),
            tint = LiveDesign.text,
        )
    }
}

/** Same host as [LivePickerHost]: slide-up glass, 10dp above the capture bar. */
@Composable
fun LiveGimbalSheetHost(
    model: AppModel,
    layout: LiveMonitorLayout,
    cluster: GimbalCluster,
    safeLeading: Float,
    safeTrailing: Float,
    safeTop: Float,
    safeBottom: Float,
) {
    val density = LocalDensity.current
    var panelHeight by remember { mutableFloatStateOf(280f) }
    val tile = cluster.controls
    val bar = floorBar(layout, cluster)
    val place =
        LivePopupPlacement.capturePicker(
            tile = tile,
            bar = bar,
            panelHeight = panelHeight,
            viewportWidth = layout.viewportWidth,
            viewportHeight = layout.viewportHeight,
            safeLeading = safeLeading,
            safeTrailing = safeTrailing,
            safeTop = safeTop,
            safeBottom = safeBottom,
            ceilingY = max(LivePopupPlacement.EDGE_MARGIN, max(safeTop + LivePopupPlacement.ASSIST_TOP_INSET, 0f)),
            preferredWidth = SHEET_WIDTH_DP,
        )
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val revealed by
        animateFloatAsState(
            if (shown) 1f else 0f,
            tween(200, easing = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)),
            label = "gimbal-sheet-reveal",
        )
    val slide = place.maxHeight + 20f
    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures { model.liveGimbalPanel = LiveGimbalPanel.NONE }
            },
    ) {
        Box(
            Modifier
                .offset(place.x.dp, (place.y + (1f - revealed) * slide).dp)
                .width(place.width.dp)
                .heightIn(max = place.maxHeight.dp)
                .graphicsLayer { alpha = revealed }
                .onSizeChanged { panelHeight = it.height / density.density }
                .pointerInput(Unit) { detectTapGestures { } },
        ) {
            LiveGimbalSheet(model, maxHeightDp = place.maxHeight)
        }
    }
}

@Composable
fun LiveGimbalOverlay(
    model: AppModel,
    layout: LiveMonitorLayout,
    feed: ChromeRect,
    uiLocked: Boolean,
) {
    if (uiLocked) return
    val panel = model.liveGimbalPanel
    val program by model.session.gimbalProgram.collectAsState()
    val running by model.session.gimbalMoveRunning.collectAsState()
    var frameTick by remember { mutableIntStateOf(0) }
    LaunchedEffect(panel, running) {
        if (panel == LiveGimbalPanel.EDITOR || panel == LiveGimbalPanel.RUN_PILL || running) {
            while (true) {
                delay(40)
                frameTick += 1
            }
        }
    }
    val live = if (frameTick >= 0) {
        model.session.predictedGimbalWaypoint(android.os.SystemClock.elapsedRealtime() / 1000.0)
    } else null
    val bounds =
        ChromeRect(
            max(8f, layout.safeLeading),
            max(8f, layout.safeTop),
            max(
                1f,
                layout.viewportWidth - max(8f, layout.safeLeading) - max(8f, layout.safeTrailing),
            ),
            max(
                1f,
                layout.viewportHeight - max(8f, layout.safeTop) - max(8f, layout.safeBottom),
            ),
        )
    val defaultEditor =
        Offset(
            min(max(feed.minX + 16f + EDITOR_WIDTH_DP / 2f, 16f + EDITOR_WIDTH_DP / 2f),
                layout.viewportWidth - 16f - EDITOR_WIDTH_DP / 2f),
            min(max(feed.midY, 140f), layout.viewportHeight - 180f),
        )
    val defaultPill =
        Offset(
            defaultEditor.x,
            min(feed.maxY - 36f, layout.viewportHeight - 80f),
        )
    Box(Modifier.fillMaxSize()) {
        if (live != null &&
            (panel == LiveGimbalPanel.EDITOR || panel == LiveGimbalPanel.RUN_PILL || running)
        ) {
            val aspect = (feed.width / feed.height.coerceAtLeast(1f)).toDouble()
            val preview = remember(program) { GimbalProgramCurve.create(program)?.samples() }
            if (preview != null) {
                Canvas(Modifier.fillMaxSize()) {
                    val path = Path()
                    var connected = false
                    for (sample in preview) {
                        val (nx, ny, onScreen) = GimbalMoveEngine.project(sample, live, aspect)
                        if (!onScreen) { connected = false; continue }
                        val x = (feed.minX + motionOverlayX(nx, model.assist.mirror).toFloat() * feed.width).dp.toPx()
                        val y = (feed.minY + ny.toFloat() * feed.height).dp.toPx()
                        if (connected) path.lineTo(x, y) else path.moveTo(x, y)
                        connected = true
                    }
                    drawPath(path, LiveDesign.text.copy(alpha = 0.3f), style = Stroke(
                        width = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 5.dp.toPx()))))
                }
            }
            for (slot in GimbalWaypointSlot.entries) {
                val point = program.point(slot) ?: continue
                val (nx, ny, onScreen) = GimbalMoveEngine.project(point, live, aspect)
                Box(
                    Modifier
                        .offset(
                            (feed.minX + motionOverlayX(nx, model.assist.mirror).toFloat() * feed.width - 13f).dp,
                            (feed.minY + ny.toFloat() * feed.height - 13f).dp,
                        )
                        .size(26.dp)
                        .background(
                            LiveDesign.accent.copy(alpha = if (onScreen) 0.92f else 0.45f),
                            CircleShape,
                        )
                        .alpha(if (onScreen) 1f else 0.7f)
                        .zIndex(0f),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        slot.letter,
                        color = LiveDesign.text,
                        style = LiveType.ui(13f, FontWeight.Bold),
                    )
                }
            }
        }
        if (panel == LiveGimbalPanel.EDITOR) {
            GimbalFloatMove(
                model = model,
                sizeHintW = EDITOR_WIDTH_DP,
                sizeHintH = 280f,
                bounds = bounds,
                defaultCenter = defaultEditor,
            ) {
                LiveGimbalEditor(model, program, running)
            }
        }
        if (panel == LiveGimbalPanel.RUN_PILL) {
            GimbalFloatMove(
                model = model,
                sizeHintW = 200f,
                sizeHintH = 44f,
                bounds = bounds,
                defaultCenter = defaultPill,
                immediateDrag = true,
            ) {
                LiveGimbalRunPill(model, program, running)
            }
        }
    }
}

@Composable
private fun GimbalFloatMove(
    model: AppModel,
    sizeHintW: Float,
    sizeHintH: Float,
    bounds: ChromeRect,
    defaultCenter: Offset,
    immediateDrag: Boolean = false,
    content: @Composable () -> Unit,
) {
    val density = LocalDensity.current
    val haptics = LocalOperatorHaptics.current
    var measuredW by remember { mutableFloatStateOf(sizeHintW) }
    var measuredH by remember { mutableFloatStateOf(sizeHintH) }
    var origin by remember { mutableStateOf<Offset?>(null) }
    var coords by remember { mutableStateOf<LayoutCoordinates?>(null) }
    LaunchedEffect(Unit) {
        if (model.gimbalFloatCenter == null) model.gimbalFloatCenter = defaultCenter
    }
    val raw = model.gimbalFloatCenter ?: defaultCenter
    val center = clampCenter(raw, measuredW, measuredH, bounds)
    val currentCenter by rememberUpdatedState(center)
    val dragModifier = Modifier
            .pointerInput(bounds, measuredW, measuredH, immediateDrag) {
                detectHoldThenDragAllowClicks(
                    holdMs = HOLD_MS,
                    immediate = immediateDrag,
                    onHold = {
                        origin = currentCenter
                        haptics.confirm()
                    },
                    onDrag = { translation ->
                        val start = origin ?: currentCenter
                        val dx = translation.x / density.density
                        val dy = translation.y / density.density
                        val next =
                            clampCenter(
                                Offset(start.x + dx, start.y + dy),
                                measuredW,
                                measuredH,
                                bounds,
                            )
                        model.gimbalFloatCenter = next
                    },
                    onEnd = { origin = null },
                    toRoot = { local -> coords?.localToRoot(local) ?: local },
                )
            }

    Box(
        Modifier
            .offset((center.x - measuredW / 2f).dp, (center.y - measuredH / 2f).dp)
            .onSizeChanged {
                measuredW = it.width / density.density
                measuredH = it.height / density.density
            }
            .onGloballyPositioned { coords = it }
            .then(dragModifier)
            .zIndex(1f),
    ) {
        content()
    }
}

private enum class GimbalSettingsTab(val title: String) {
    MODE("Mode"), SPEED("Speed"), RAMP("Ramp")
}

@Composable
private fun LiveGimbalSheet(model: AppModel, maxHeightDp: Float) {
    var selectedTab by remember { mutableStateOf(GimbalSettingsTab.MODE) }
    val mode by model.session.gimbalMode.collectAsState()
    val speed by model.session.gimbalSpeed.collectAsState()
    val program by model.session.gimbalProgram.collectAsState()
    Column(
        Modifier
            .monitorGlass(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))
            .heightIn(max = maxHeightDp.dp)
            .padding(top = 10.dp, start = 20.dp, end = 20.dp, bottom = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                GimbalHudCopy.TITLE.uppercase(),
                color = LiveDesign.text,
                style = LiveType.ui(18f, FontWeight.ExtraBold).copy(letterSpacing = 2.sp),
                maxLines = 1,
            )
            Spacer(Modifier.weight(1f))
            LivePopupCloseButton(
                onClick = { model.liveGimbalPanel = LiveGimbalPanel.NONE },
            )
        }
        Row {
            GimbalSettingsTab.entries.forEach { tab ->
                Column(
                    Modifier.weight(1f).heightIn(min = 44.dp)
                        .selectable(selected = selectedTab == tab, role = Role.Tab) { selectedTab = tab }
                        .padding(top = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(tab.title,
                        color = if (selectedTab == tab) LiveDesign.text else LiveDesign.muted,
                        style = LiveType.ui(13f, FontWeight.SemiBold))
                    Box(Modifier.fillMaxWidth().height(2.dp)
                        .background(if (selectedTab == tab) LiveDesign.accent else LiveDesign.hairline))
                }
            }
        }
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).heightIn(min = 76.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            when (selectedTab) {
                GimbalSettingsTab.MODE ->
                    chipGrid(GimbalMode.pickerOrder, mode, { it.label }) { model.session.setGimbalMode(it) }
                GimbalSettingsTab.SPEED ->
                    chipRow(GimbalSpeed.pickerOrder, speed, { it.label }) { model.session.setGimbalSpeed(it) }
                GimbalSettingsTab.RAMP ->
                    chipRow(GimbalRamp.pickerOrder, model.gimbalRamp, { it.label }) { model.updateGimbalRamp(it) }
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(LiveDesign.hairline))
        Text("GIMBAL TOOLS", color = LiveDesign.muted,
            style = LiveType.ui(11f, FontWeight.SemiBold).copy(letterSpacing = 0.8.sp))
        Row(
            Modifier
                .fillMaxWidth()
                .background(LiveDesign.glassBright, RoundedCornerShape(12.dp))
                .chromeClickable(onClick = { model.liveGimbalPanel = LiveGimbalPanel.EDITOR })
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(GimbalHudCopy.PROGRAMMED, color = LiveDesign.text,
                    style = LiveType.ui(14f, FontWeight.SemiBold))
                Text("Experimental", color = LiveDesign.muted, style = LiveType.ui(11f, FontWeight.Medium))
            }
            Spacer(Modifier.weight(1f))
            Text(
                program.summary,
                color = LiveDesign.muted,
                style = LiveType.ui(14f, FontWeight.SemiBold),
            )
        }
    }
}

@Composable
private fun LiveGimbalEditor(model: AppModel, program: GimbalProgram, running: Boolean) {
    val countdown by model.session.gimbalMoveCountdown.collectAsState()
    val paused by model.session.gimbalMovePaused.collectAsState()
    Column(
        Modifier
            .width(EDITOR_WIDTH_DP.dp)
            .monitorGlass(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))
            .padding(top = 10.dp, start = 14.dp, end = 14.dp, bottom = 14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(GimbalHudCopy.PROGRAMMED, color = LiveDesign.text,
                style = LiveType.ui(15f, FontWeight.Bold), modifier = Modifier.weight(1f))
            Box(
                Modifier
                    .size(30.dp)
                    .chromeClickable(onClick = { model.liveGimbalPanel = LiveGimbalPanel.RUN_PILL }),
                contentAlignment = Alignment.Center,
            ) {
                OpcIcon(
                    OpcIcon.MINIMIZE,
                    contentDescription = "Minimize",
                    modifier = Modifier.size(16.dp),
                    tint = LiveDesign.text,
                )
            }
            LivePopupCloseButton(
                onClick = { model.liveGimbalPanel = LiveGimbalPanel.NONE },
                size = 30.dp,
            )
        }
        waypointRow(model, program, GimbalWaypointSlot.A, duration = null, floor = null)
        waypointRow(
            model,
            program,
            GimbalWaypointSlot.B,
            duration = program.durationAB,
            floor = GimbalProgram.minTravelDuration(program.a, program.b),
        )
        if (program.b != null) {
            waypointRow(
                model,
                program,
                GimbalWaypointSlot.C,
                duration = program.durationBC,
                floor = GimbalProgram.minTravelDuration(program.b, program.c),
            )
        }
        if (program.b != null && program.c != null) {
            Text(String.format(java.util.Locale.US, "Smoothness %.2f", program.smoothness),
                color = LiveDesign.text, style = LiveType.ui(13f, FontWeight.SemiBold))
            Slider(value = program.smoothness.toFloat(),
                onValueChange = { model.session.setGimbalSmoothness(it.toDouble()) },
                valueRange = 0f..1f, steps = 19)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!running) {
                Chip("Clear", selected = false, modifier = Modifier.weight(1f)) { model.session.clearGimbalProgram() }
                Chip(GimbalHudCopy.RUN, selected = model.session.canRunProgrammedMove,
                    modifier = Modifier.weight(1f).testTag("motion.startStop"),
                    enabled = model.session.canRunProgrammedMove) { model.session.runProgrammedMove() }
            } else {
                if (countdown == null) {
                    Chip(if (paused) "Resume" else "Pause", selected = true,
                        modifier = Modifier.weight(1f).testTag("motion.pauseResume")) {
                        if (paused) model.session.resumeProgrammedMove() else model.session.pauseProgrammedMove()
                    }
                }
                Chip(countdown?.let { "Stop · $it" } ?: "Stop", selected = true,
                    modifier = Modifier.weight(1f).testTag("motion.startStop")) { model.session.cancelProgrammedMove() }
            }
        }
    }
}

@Composable
private fun waypointRow(
    model: AppModel,
    program: GimbalProgram,
    slot: GimbalWaypointSlot,
    duration: Double?,
    floor: Double?,
) {
    val set = program.point(slot) != null
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            slot.letter,
            color = if (set) LiveDesign.accent else LiveDesign.text,
            style = LiveType.ui(16f, FontWeight.Bold),
            modifier = Modifier.width(20.dp),
        )
        Spacer(Modifier.weight(1f))
        if (set && duration != null && floor != null) {
            DurationDial(
                value = duration,
                floor = floor,
                label = slot.letter,
                onDuration = { next ->
                    when (slot) {
                        GimbalWaypointSlot.B -> model.session.setGimbalLegDuration(ab = next)
                        GimbalWaypointSlot.C -> model.session.setGimbalLegDuration(bc = next)
                        GimbalWaypointSlot.A -> Unit
                    }
                },
            )
        }
        if (set) {
            Box(Modifier.size(32.dp).testTag("motion.waypoint.${slot.letter}")
                .background(LiveDesign.glassBright, CircleShape)
                .chromeClickable(onClick = { model.session.setGimbalWaypoint(slot) }),
                contentAlignment = Alignment.Center) {
                OpcIcon(OpcIcon.REFRESH_CW, contentDescription = "Update ${slot.letter}",
                    modifier = Modifier.size(15.dp), tint = LiveDesign.text)
            }
        } else {
            Chip("Set", selected = false, compact = true,
                modifier = Modifier.testTag("motion.waypoint.${slot.letter}")) {
                model.session.setGimbalWaypoint(slot)
            }
        }
        if (set) {
            Box(
                Modifier
                    .size(26.dp)
                    .chromeClickable(onClick = { model.session.clearGimbalWaypoint(slot) }),
                contentAlignment = Alignment.Center,
            ) {
                OpcIcon(
                    OpcIcon.X,
                    contentDescription = "Clear ${slot.letter}",
                    modifier = Modifier.size(12.dp),
                    tint = LiveDesign.muted,
                )
            }
        }
    }
}

@Composable
private fun LiveGimbalRunPill(model: AppModel, program: GimbalProgram, running: Boolean) {
    val countdown by model.session.gimbalMoveCountdown.collectAsState()
    val paused by model.session.gimbalMovePaused.collectAsState()
    Row(
        Modifier.monitorGlass(RoundedCornerShape(50)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (running && countdown == null) {
            Text(if (paused) "RESUME" else "PAUSE", color = LiveDesign.text,
                style = LiveType.ui(13f, FontWeight.Bold),
                modifier = Modifier.testTag("motion.pauseResume")
                    .chromeClickable(onClick = {
                        if (paused) model.session.resumeProgrammedMove() else model.session.pauseProgrammedMove()
                    }).padding(horizontal = 14.dp, vertical = 12.dp))
        }
        Text(countdown?.let { "STOP · $it" } ?: if (running) "STOP" else GimbalHudCopy.RUN.uppercase(),
            color = LiveDesign.text, style = LiveType.ui(13f, FontWeight.Bold),
            modifier = Modifier.testTag("motion.startStop")
                .chromeClickable(enabled = model.session.canRunProgrammedMove || running,
                    onClick = { if (running) model.session.cancelProgrammedMove() else model.session.runProgrammedMove() })
                .padding(horizontal = 14.dp, vertical = 12.dp))
        Box(
            Modifier
                .size(44.dp, 40.dp)
                .chromeClickable(onClick = { model.liveGimbalPanel = LiveGimbalPanel.EDITOR }),
            contentAlignment = Alignment.Center,
        ) {
            OpcIcon(
                OpcIcon.MAXIMIZE,
                contentDescription = "Expand Motion Control",
                modifier = Modifier.size(16.dp),
                tint = LiveDesign.text,
            )
        }
    }
}

@Composable
private fun DurationDial(value: Double, floor: Double, label: String, onDuration: (Double) -> Unit) {
    val density = LocalDensity.current
    val currentValue by rememberUpdatedState(value)
    val update by rememberUpdatedState(onDuration)
    var dragStart by remember { mutableStateOf(value) }
    var translation by remember { mutableFloatStateOf(0f) }
    var dragging by remember { mutableStateOf(false) }
    var lastEmitted by remember { mutableStateOf(value) }
    val haptics = LocalOperatorHaptics.current
    val rulerTarget = if (dragging) (dragStart / 0.5 - translation / 12f)
        .coerceIn(floor / 0.5, GimbalProgram.MAX_DURATION / 0.5).toFloat() else (value / 0.5).toFloat()
    val rulerPosition by animateFloatAsState(rulerTarget,
        animationSpec = if (dragging) snap() else spring(dampingRatio = 0.8f, stiffness = 500f),
        label = "motion-duration-settle")
    Box(
        Modifier.size(180.dp, 44.dp).testTag("motion.duration.$label")
            .background(LiveDesign.glassBright, RoundedCornerShape(8.dp))
            .semantics {
                contentDescription = "Movement duration"
                stateDescription = String.format(java.util.Locale.US, "%.1f seconds", value)
                progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), floor.toFloat()..GimbalProgram.MAX_DURATION.toFloat(),
                    ((GimbalProgram.MAX_DURATION - floor) / 0.5).toInt() - 1)
                setProgress { requested ->
                    update(GimbalProgram.steppedDuration(requested.toDouble(), 0.0, floor)); true
                }
                customActions = listOf(
                    CustomAccessibilityAction("Increase duration") {
                        update(GimbalProgram.steppedDuration(currentValue, 0.5, floor)); true
                    },
                    CustomAccessibilityAction("Decrease duration") {
                        update(GimbalProgram.steppedDuration(currentValue, -0.5, floor)); true
                    },
                )
            }
            .pointerInput(floor) {
                detectHorizontalDragGestures(
                    onDragStart = { dragStart = currentValue; lastEmitted = currentValue; translation = 0f; dragging = true },
                    onDragEnd = { dragging = false },
                    onDragCancel = { dragging = false },
                ) { change, amount ->
                    change.consume()
                    translation += amount / density.density
                    val next = motionDurationAfterDrag(dragStart, translation, floor)
                    if (next != lastEmitted) { lastEmitted = next; haptics.selection(); update(next) }
                }
            },
        contentAlignment = Alignment.TopCenter,
    ) {
        Crossfade(targetState = value, animationSpec = tween(100), label = "motion-duration-number",
            modifier = Modifier.padding(top = 4.dp)) { shown ->
            Text(GimbalProgram.durationLabel(shown), color = LiveDesign.text,
                style = LiveType.ui(13f, FontWeight.SemiBold))
        }
        Canvas(Modifier.fillMaxSize()) {
            val step = 12.dp.toPx()
            val position = rulerPosition.coerceIn((floor / 0.5).toFloat(), (GimbalProgram.MAX_DURATION / 0.5).toFloat())
            val index = kotlin.math.round(position).toInt()
            for (offset in -8..8) {
                val number = index + offset
                if (number * 0.5 < floor || number * 0.5 > GimbalProgram.MAX_DURATION) continue
                val x = size.width / 2 + (number - position).toFloat() * step
                val tall = number % 2 == 0
                drawLine(LiveDesign.text.copy(alpha = if (offset == 0) 0.85f else 0.3f),
                    Offset(x, size.height - if (tall) 13.dp.toPx() else 8.dp.toPx()),
                    Offset(x, size.height - 3.dp.toPx()), strokeWidth = 1.dp.toPx())
            }
            drawLine(LiveDesign.accent, Offset(size.width / 2, size.height - 15.dp.toPx()),
                Offset(size.width / 2, size.height - 2.dp.toPx()), strokeWidth = 2.dp.toPx())
        }
    }
}

@Composable
private fun section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            title.uppercase(),
            color = LiveDesign.muted,
            style = LiveType.ui(11f, FontWeight.SemiBold).copy(letterSpacing = 0.8.sp),
        )
        content()
    }
}

@Composable
private fun <T> chipRow(
    items: List<T>,
    selected: T,
    title: (T) -> String,
    onSelect: (T) -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
        for (item in items) {
            Chip(title(item), selected = item == selected, modifier = Modifier.weight(1f)) {
                onSelect(item)
            }
        }
    }
}

@Composable
private fun <T> chipGrid(
    items: List<T>,
    selected: T,
    title: (T) -> String,
    onSelect: (T) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                for (item in row) {
                    Chip(title(item), selected = item == selected, modifier = Modifier.weight(1f)) {
                        onSelect(item)
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun Chip(
    title: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    compact: Boolean = false,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .background(
                if (selected) LiveDesign.accent else LiveDesign.glassBright,
                RoundedCornerShape(50),
            )
            .chromeClickable(enabled = enabled, onClick = onClick)
            .padding(vertical = if (compact) 7.dp else 8.dp, horizontal = if (compact) 12.dp else 0.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            color = if (selected) LiveDesign.background else LiveDesign.text,
            style = LiveType.ui(if (compact) 12f else 13f, FontWeight.SemiBold),
        )
    }
}

private fun floorBar(layout: LiveMonitorLayout, cluster: GimbalCluster): ChromeRect {
    if (layout.capture.width > 1f) return layout.capture
    if (layout.assist.width > 1f) return layout.assist
    val tops =
        listOf(cluster.zoom, cluster.controls, cluster.stick)
            .filter { it.height > 1f }
            .map { it.minY }
    val top = tops.minOrNull() ?: max(8f, layout.viewportHeight - 80f)
    return ChromeRect(0f, top, layout.viewportWidth, 1f)
}

private fun clampCenter(point: Offset, width: Float, height: Float, bounds: ChromeRect): Offset {
    val halfW = max(width / 2f, 20f)
    val halfH = max(height / 2f, 16f)
    return Offset(
        min(max(point.x, bounds.minX + halfW), max(bounds.minX + halfW, bounds.maxX - halfW)),
        min(max(point.y, bounds.minY + halfH), max(bounds.minY + halfH, bounds.maxY - halfH)),
    )
}

/** Initial-pass ownership cancels child clicks before drag events or the release reach them. */
private suspend fun PointerInputScope.detectHoldThenDragAllowClicks(
    holdMs: Long,
    immediate: Boolean,
    onHold: () -> Unit,
    onDrag: (Offset) -> Unit,
    onEnd: () -> Unit,
    toRoot: (Offset) -> Offset,
) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        val pointerId = down.id
        val downRoot = toRoot(down.position)
        val gesture = MotionControlDragGesture(immediate, if (immediate) 8.dp.toPx() else viewConfiguration.touchSlop, holdMs)
        var elapsed = 0L
        var started = false
        while (true) {
            val event = if (gesture.ownership == MotionControlDragGesture.Ownership.TRACKING) {
                withTimeoutOrNull((holdMs - elapsed).coerceAtLeast(1)) { awaitPointerEvent(PointerEventPass.Initial) }
            } else awaitPointerEvent(PointerEventPass.Initial)
            if (event == null) {
                gesture.update(holdMs, 0f)
                if (!started) { started = true; onHold() }
                continue
            }
            val change = event.changes.firstOrNull { it.id == pointerId } ?: break
            elapsed = change.uptimeMillis - down.uptimeMillis
            val translation = toRoot(change.position) - downRoot
            when (gesture.update(elapsed, translation.getDistance())) {
                MotionControlDragGesture.Ownership.YIELDED -> break
                MotionControlDragGesture.Ownership.DRAGGING -> {
                    if (!started) { started = true; onHold() }
                    // Includes the UP event: a completed drag never becomes a child click.
                    event.changes.forEach { it.consume() }
                    if (change.pressed) onDrag(translation)
                }
                MotionControlDragGesture.Ownership.TRACKING -> Unit
            }
            if (!change.pressed) break
            if (!started) {
                val final = awaitPointerEvent(PointerEventPass.Final)
                if (final.changes.any { it.isConsumed }) break
            }
        }
        if (started) onEnd()
    }
}
