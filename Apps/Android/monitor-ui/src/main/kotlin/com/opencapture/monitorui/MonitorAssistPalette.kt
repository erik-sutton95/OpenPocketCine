@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
package com.opencapture.monitorui

import android.view.MotionEvent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/** One palette for live, playback and multi-view, without any camera or tool taxonomy. */
@Composable
fun <T> MonitorAssistPalette(tools: List<T>, portrait: Boolean, locked: Boolean,
    isOn: (T) -> Boolean, title: (T) -> String, label: (T) -> String, hasOptions: (T) -> Boolean,
    onToggle: (T) -> Unit, onOptions: (T) -> Unit,
    glyph: @Composable (T, Color, Modifier) -> Unit,
    chevron: @Composable (expanded: Boolean, portrait: Boolean) -> Unit,
    modifier: Modifier = Modifier, requestExpand: Boolean = false, onExpansionHandled: () -> Unit = {},
    usageSeed: Map<String, Int> = emptyMap(),
    idOf: (T) -> String = { it.toString() },
    usage: MonitorToolUsageState = MonitorToolUsageState(),
    onUsageChange: (MonitorToolUsageState) -> Unit = {},
    onBoundsInRootChanged: (Rect?) -> Unit = {}) {
    var expanded by remember { mutableStateOf(false) }
    var dragging by remember { mutableStateOf(false) }
    var pinnedIds by remember { mutableStateOf<List<String>>(emptyList()) }
    val progress = remember { Animatable(0f) }
    var scrub by remember { mutableFloatStateOf(0f) }
    val scope = rememberCoroutineScope()
    val nowLocked by rememberUpdatedState(locked)
    val nowUsage by rememberUpdatedState(usage)
    val nowBoundsChanged by rememberUpdatedState(onBoundsInRootChanged)
    DisposableEffect(Unit) { onDispose { nowBoundsChanged(null) } }
    val liveRanked = remember(tools, usage) {
        MonitorAssistUsage.ranked(tools, idOf, usage, usageSeed)
    }
    val frozen = expanded || dragging || progress.value > 0.02f
    val rankedIds = remember(frozen, pinnedIds, liveRanked) {
        MonitorAssistPaletteReveal.pinnedOrder(liveRanked.map(idOf), pinnedIds, frozen)
    }
    val ranked = remember(rankedIds, tools) {
        val byId = tools.associateBy(idOf)
        rankedIds.mapNotNull { byId[it] }
    }
    LaunchedEffect(tools, usageSeed) {
        if (pinnedIds.isEmpty()) pinnedIds = liveRanked.map(idOf)
    }
    LaunchedEffect(expanded, dragging, progress.value, liveRanked) {
        if (!expanded && !dragging && progress.value <= 0.02f) {
            pinnedIds = liveRanked.map(idOf)
        }
    }
    fun used(tool: T) {
        onUsageChange(nowUsage.recording(idOf(tool), System.currentTimeMillis() / 1000.0))
    }
    val config = LocalConfiguration.current
    val density = LocalDensity.current
    val tablet = minOf(config.screenWidthDp, config.screenHeightDp) >= 600
    val buttonSize = MonitorLayoutPolicy.assistButtonSize(tablet).dp
    val iconSize = MonitorLayoutPolicy.assistIconSize(tablet).dp
    val expansionLane = MonitorLayoutPolicy.ASSIST_EXPANSION_BUTTON_WIDTH.dp
    val horizontalInsets = MonitorLayoutPolicy.ASSIST_HORIZONTAL_INSETS.dp
    val columns = maxOf(1, (tools.size + 1) / 2)
    val catalogWidth = buttonSize * columns + 3.dp * maxOf(0, columns - 1) + horizontalInsets
    val available = MonitorLayoutPolicy.assistAvailableWidth(
        config.screenWidthDp.toFloat(), portrait, tablet).dp
    val compactW = buttonSize + if (portrait) 8.dp else horizontalInsets
    val compactH = if (portrait) buttonSize + 35.dp else buttonSize * 2 + 11.dp
    val fullW = if (portrait) buttonSize + 8.dp else minOf(available, maxOf(buttonSize + horizontalInsets, catalogWidth))
    val fullH = if (portrait) minOf((config.screenHeightDp * .62f).dp,
        buttonSize * tools.size + (maxOf(0, tools.size - 1) * 3 + 35).dp) else buttonSize * 2 + 11.dp
    val reveal = if (portrait && dragging) scrub else progress.value
    val visibleW = compactW + (fullW - compactW) * reveal
    val visibleH = compactH + (fullH - compactH) * reveal
    val spanPx = with(density) {
        if (portrait) (fullH - compactH).toPx() else (fullW - compactW).toPx()
    }
    val settle = spring<Float>(dampingRatio = 0.84f, stiffness = Spring.StiffnessMedium)
    LaunchedEffect(requestExpand) { if (requestExpand) { expanded = true; onExpansionHandled() } }
    LaunchedEffect(locked) {
        if (locked) { expanded = false; dragging = false; scrub = 0f; progress.snapTo(0f) }
    }
    LaunchedEffect(expanded) {
        if (!dragging) progress.animateTo(if (expanded) 1f else 0f, settle)
    }
    val scrollState = rememberScrollState()
    var slotInWindow by remember { mutableStateOf(IntRect.Zero) }
    var windowToRoot by remember { mutableStateOf(Offset.Zero) }
    var popupWindowWidth by remember(config.screenWidthDp, density.density) {
        mutableIntStateOf(with(density) { config.screenWidthDp.dp.roundToPx() })
    }
    val popupPosition = remember(slotInWindow) {
        object : PopupPositionProvider {
            override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize,
                layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
                popupWindowWidth = windowSize.width
                val bounds = MonitorAssistPaletteReveal.popupBounds(slotInWindow, windowSize.width, popupContentSize)
                return IntOffset(bounds.left, bounds.top)
            }
        }
    }
    val reservedSize = with(density) {
        MonitorAssistPaletteReveal.reservationSize(expanded, dragging, progress.isRunning, reveal,
            IntSize(compactW.roundToPx(), compactH.roundToPx()), IntSize(fullW.roundToPx(), fullH.roundToPx()))
    }
    val reservedBounds = if (slotInWindow.width > 0 && slotInWindow.height > 0) {
        val bounds = MonitorAssistPaletteReveal.popupBounds(slotInWindow, popupWindowWidth, reservedSize)
        Rect(bounds.left + windowToRoot.x, bounds.top + windowToRoot.y,
            bounds.right + windowToRoot.x, bounds.bottom + windowToRoot.y)
    } else null
    SideEffect { nowBoundsChanged(reservedBounds) }
    val labelOpacity = ((reveal - 0.7f) / 0.3f).coerceIn(0f, 1f)
    val extraOpacity = MonitorAssistPaletteReveal.extraToolOpacity(reveal)
    val compactCount = MonitorAssistPaletteReveal.compactToolCount(portrait)
    val key: @Composable (T, Int) -> Unit = { tool, index ->
        val active = isOn(tool)
        val tint = if (active) MonitorPalette.accent else MonitorPalette.text
        val shown = if (index < compactCount) 1f else extraOpacity
        Box(Modifier.size(buttonSize).graphicsLayer { alpha = shown }
            .clip(RoundedCornerShape(9.dp)).background(if (active) MonitorPalette.accent.copy(alpha = .13f) else Color.Transparent)
            .combinedClickable(enabled = !locked && shown > 0.35f, onClick = { used(tool); onToggle(tool) },
                onLongClick = if (hasOptions(tool)) { { used(tool); onOptions(tool); expanded = false } } else null)
            .semantics { contentDescription = "${title(tool)}, ${if (active) "on" else "off"}" },
            contentAlignment = Alignment.Center) {
            glyph(tool, tint, Modifier.size(iconSize))
            Text(label(tool), color = tint.copy(alpha = tint.alpha * labelOpacity),
                style = MonitorTypography.text(7.5f, FontWeight.SemiBold).copy(letterSpacing = .75.sp),
                maxLines = 1, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 3.dp))
        }
    }
    val handleDrag = rememberDraggableState { delta ->
        val next = ((progress.value * spanPx + delta) / spanPx).coerceIn(0f, 1f)
        scope.launch { progress.snapTo(next) }
    }
    val slotBottomScreen = remember { FloatArray(1) }
    val compactHPx = with(density) { compactH.toPx() }
    val fullHPx = with(density) { fullH.toPx() }
    val expandHit: @Composable () -> Unit = {
        val open = reveal < 0.5f
        Box(Modifier.size(if (portrait) visibleW - 8.dp else expansionLane, if (portrait) 24.dp else visibleH - 8.dp)
            .then(
                if (portrait) {
                    Modifier.pointerInput(locked, compactHPx, fullHPx, spanPx, density.density) {
                        if (locked) return@pointerInput
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            val nativeDown = currentEvent.motionEvent ?: return@awaitEachGesture
                            val nativeId = nativeDown.getPointerId(nativeDown.actionIndex)
                            val start = Offset(nativeDown.getRawX(nativeDown.actionIndex),
                                nativeDown.getRawY(nativeDown.actionIndex))
                            val plateBottom = slotBottomScreen[0]
                            val wasExpanded = expanded
                            var armed = false
                            var released = false
                            var grab = 0f
                            val tracker = VelocityTracker()
                            tracker.addPosition(down.uptimeMillis, start)
                            try {
                                while (true) {
                                    val event = awaitPointerEvent()
                                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                    // Relayout can generate pointer events without a physical move.
                                    // Only native screen coordinates may move this resizing popup.
                                    val motion = event.motionEvent ?: continue
                                    if (motion.actionMasked == MotionEvent.ACTION_CANCEL || motion.pointerCount != 1) break
                                    val index = motion.findPointerIndex(nativeId)
                                    if (index < 0) break
                                    val screen = Offset(motion.getRawX(index), motion.getRawY(index))
                                    tracker.addPosition(change.uptimeMillis, screen)
                                    if (!change.pressed) {
                                        released = motion.actionMasked == MotionEvent.ACTION_UP
                                        break
                                    }
                                    val finger = MonitorAssistPaletteReveal.paletteFingerY(
                                        screen.y, plateBottom, fullHPx)
                                    if (!armed) {
                                        if ((screen - start).getDistance() < MonitorAssistPaletteReveal.SLOP * density.density) {
                                            change.consume()
                                            continue
                                        }
                                        val visible = compactHPx + spanPx * progress.value
                                        grab = MonitorAssistPaletteReveal.portraitGrabOffset(finger, visible, fullHPx)
                                        scrub = progress.value
                                        armed = true
                                        dragging = true
                                    }
                                    val height = MonitorAssistPaletteReveal.portraitVisibleHeight(
                                        finger, grab, compactHPx, fullHPx)
                                    scrub = MonitorAssistPaletteReveal.progress(height, compactHPx, fullHPx)
                                    change.consume()
                                }
                            } finally {
                                if (!released || nowLocked) {
                                    // Cancellation/lock must never act like a tap or fling.
                                    dragging = false
                                    expanded = if (nowLocked) false else wasExpanded
                                    scope.launch { progress.animateTo(if (expanded) 1f else 0f, settle) }
                                } else if (!armed) {
                                    expanded = !expanded
                                } else {
                                    val alongPx = -tracker.calculateVelocity().y
                                    val projected = MonitorAssistPaletteReveal.projectedProgress(scrub, alongPx, spanPx)
                                    val shouldOpen = MonitorAssistPaletteReveal.shouldOpen(
                                        scrub, alongPx / density.density, projected)
                                    val end = scrub
                                    scope.launch {
                                        if (nowLocked || !dragging) return@launch
                                        progress.snapTo(end)
                                        dragging = false
                                        if (expanded != shouldOpen) expanded = shouldOpen
                                        else progress.animateTo(if (shouldOpen) 1f else 0f, settle)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Modifier
                        .clickable(enabled = !locked) { if (!dragging) expanded = !expanded }
                        .draggable(
                            orientation = Orientation.Horizontal,
                            state = handleDrag, enabled = !locked,
                            onDragStarted = { dragging = true },
                            onDragStopped = { velocity ->
                                val projected = MonitorAssistPaletteReveal.projectedProgress(
                                    reveal, velocity, spanPx)
                                val shouldOpen = MonitorAssistPaletteReveal.shouldOpen(
                                    reveal, velocity, projected)
                                dragging = false
                                expanded = shouldOpen
                                scope.launch {
                                    progress.animateTo(if (shouldOpen) 1f else 0f, settle)
                                }
                            },
                        )
                },
            )
            .semantics { contentDescription = if (open) "Show view assists" else "Collapse view assists" },
            contentAlignment = if (portrait) Alignment.Center else Alignment.CenterStart) {
            chevron(!open, portrait)
        }
    }
    @Composable fun plate() {
        Box(Modifier.requiredSize(visibleW, visibleH)
            .clip(RoundedCornerShape(14.dp))
            .monitorMaterial(if (reveal > 0.5f) MonitorMaterial.Expanded else MonitorMaterial.Compact)
            .padding(4.dp)) {
            if (portrait) {
                Column(Modifier.matchParentSize(), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    expandHit()
                    Column(Modifier.weight(1f, fill = true).verticalScroll(scrollState),
                        verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        ranked.forEachIndexed { index, tool -> key(tool, index) }
                    }
                }
            } else {
                Row(Modifier.matchParentSize(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(Modifier.weight(1f, fill = true).horizontalScroll(scrollState),
                        horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        repeat(columns) { column ->
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                repeat(2) { row ->
                                    val index = MonitorAssistPaletteReveal.landscapeCellIndex(column, row)
                                    if (index < ranked.size) key(ranked[index], index)
                                    else Box(Modifier.size(buttonSize))
                                }
                            }
                        }
                    }
                    expandHit()
                }
            }
        }
    }
    Box(modifier.size(compactW, compactH), contentAlignment = Alignment.BottomStart) {
        Box(Modifier.matchParentSize().onGloballyPositioned { coords ->
            val root = coords.positionInRoot()
            val pos = coords.positionInWindow()
            windowToRoot = root - pos
            val next = IntRect(
                left = pos.x.roundToInt(),
                top = pos.y.roundToInt(),
                right = pos.x.roundToInt() + coords.size.width,
                bottom = pos.y.roundToInt() + coords.size.height,
            )
            if (next != slotInWindow) slotInWindow = next
            slotBottomScreen[0] = coords.positionOnScreen().y + coords.size.height
        })
        val anchored = slotInWindow.width > 0 && slotInWindow.height > 0
        if (locked || !anchored) {
            plate()
        } else {
            Popup(popupPositionProvider = popupPosition,
                onDismissRequest = { if (expanded) expanded = false },
                properties = PopupProperties(focusable = expanded, clippingEnabled = false)) {
                plate()
            }
        }
    }
}
