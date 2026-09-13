package com.opencapture.monitorui

import androidx.compose.foundation.gestures.ScrollableState
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.findViewTreeLifecycleOwner
import kotlin.math.abs
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Photos-style one-finger range selection over a lazy catalog. Visible hits only;
 * edge autoscroll runs on the frame clock while the finger stays in the band.
 */
@Composable
fun MonitorMediaSelectionHost(
    ids: List<String>,
    selecting: Boolean,
    selected: Set<String>,
    scroll: ScrollableState,
    onOpen: (String) -> Unit,
    onSelectionChange: (Boolean, Set<String>) -> Unit,
    modifier: Modifier = Modifier,
    sessionKey: Any = Unit,
    content: @Composable (MonitorMediaHitRegistry) -> Unit,
) {
    val density = LocalDensity.current
    val registry = remember { MonitorMediaHitRegistry() }
    val controller = remember { MonitorMediaSelectionController() }
    val steal = remember { mutableStateOf(false) }
    var inBand by remember { mutableStateOf(false) }
    var viewportH by remember { mutableStateOf(0f) }
    var viewportW by remember { mutableStateOf(0f) }
    val densityValue = density.density
    val latestIds by rememberUpdatedState(ids)
    val latestSelecting by rememberUpdatedState(selecting)
    val latestSelected by rememberUpdatedState(selected)
    val latestOpen by rememberUpdatedState(onOpen)
    val latestChange by rememberUpdatedState(onSelectionChange)
    val latestScroll by rememberUpdatedState(scroll)
    controller.slop = with(density) { MonitorMediaSelectionPolicy.HOLD_SLOP.dp.toPx() }
    controller.bind(latestIds, latestSelecting, latestSelected)
    fun abort() {
        controller.cancel()
        steal.value = false
        inBand = false
    }
    SideEffect {
        if (!controller.consuming) {
            steal.value = false
            inBand = false
        }
    }

    val nested = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (!steal.value) return Offset.Zero
                return if (source == NestedScrollSource.UserInput) available else Offset.Zero
            }
        }
    }

    val orientation = LocalConfiguration.current.orientation
    DisposableEffect(orientation, sessionKey) {
        onDispose { abort() }
    }
    val view = LocalView.current
    DisposableEffect(view) {
        val lifecycle = view.findViewTreeLifecycleOwner()?.lifecycle
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE) abort()
        }
        lifecycle?.addObserver(observer)
        onDispose {
            lifecycle?.removeObserver(observer)
            abort()
        }
    }
    LaunchedEffect(selecting) {
        if (!selecting) abort()
    }
    LaunchedEffect(steal.value, inBand) {
        if (!steal.value || !inBand) return@LaunchedEffect
        var last = 0L
        while (isActive) {
            val dt = withFrameNanos { now ->
                val step = if (last == 0L) 0f else (now - last) / 1_000_000_000f
                last = now
                step
            }
            val height = viewportH
            val width = viewportW
            val hit = registry.resolve(controller.fingerX, controller.fingerY, width, height, nearest = true)
            dispatch(controller.afterScroll(hit), latestOpen, latestChange, steal)
            val delta = controller.edgeScroll(dt, height, densityValue)
            if (delta != 0f) {
                val consumed = latestScroll.scrollBy(delta)
                if (abs(consumed) < 0.01f) inBand = false
            }
            if (inBand) inBand = controller.inEdgeBand(height, densityValue)
        }
    }

    Box(
        modifier
            .nestedScroll(nested)
            .onGloballyPositioned { coords ->
                registry.host = coords
                val width = coords.size.width.toFloat()
                val height = coords.size.height.toFloat()
                // Height changes when the selection tray appears. That must
                // not cancel a live hold-to-sweep; iOS only cancels on width.
                if (controller.consuming && viewportW > 0f && abs(width - viewportW) >= 1f) {
                    abort()
                }
                viewportW = width
                viewportH = height
            }
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    controller.bind(latestIds, latestSelecting, latestSelected)
                    val startHit = registry.resolve(
                        down.position.x, down.position.y, viewportW, viewportH, nearest = false)
                    controller.down(startHit, down.position.x, down.position.y, down.uptimeMillis)
                    var childConsumed = down.isConsumed
                    val first = withTimeoutOrNull(controller.holdMs) {
                        while (true) {
                            val pass =
                                if (latestSelecting || controller.consuming) PointerEventPass.Initial
                                else PointerEventPass.Main
                            val event = awaitPointerEvent(pass)
                            val change = event.changes.firstOrNull { it.id == down.id }
                                ?: return@withTimeoutOrNull "end"
                            childConsumed = change.isConsumed
                            val local = change.position
                            val current = registry.resolve(
                                local.x, local.y, viewportW, viewportH, nearest = controller.consuming)
                            dispatch(
                                controller.move(current, local.x, local.y),
                                latestOpen, latestChange, steal,
                            )
                            inBand = controller.inEdgeBand(viewportH, densityValue)
                            if (controller.consuming) {
                                event.changes.forEach { it.consume() }
                                if (!change.pressed) return@withTimeoutOrNull "up"
                                return@withTimeoutOrNull "stolen"
                            }
                            if (!change.pressed) {
                                if (pass == PointerEventPass.Initial) {
                                    val main = awaitPointerEvent(PointerEventPass.Main)
                                    childConsumed = main.changes.firstOrNull { it.id == down.id }?.isConsumed == true
                                }
                                return@withTimeoutOrNull "up"
                            }
                            if (controller.shouldYieldToScroll()) {
                                return@withTimeoutOrNull "scroll"
                            }
                        }
                    }
                    when (first) {
                        "scroll", "end" -> {
                            controller.cancel()
                            steal.value = false
                            inBand = false
                            return@awaitEachGesture
                        }
                        "up" -> {
                            dispatch(controller.up(childConsumed), latestOpen, latestChange, steal)
                            steal.value = false
                            inBand = false
                            return@awaitEachGesture
                        }
                        null -> dispatch(
                            controller.holdDue(down.uptimeMillis + controller.holdMs),
                            latestOpen, latestChange, steal,
                        )
                    }
                    steal.value = controller.consuming
                    inBand = controller.inEdgeBand(viewportH, densityValue)
                    while (controller.consuming) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val change = event.changes.firstOrNull { it.id == down.id }
                        event.changes.forEach { it.consume() }
                        if (change == null || !change.pressed) {
                            controller.up(false)
                            steal.value = false
                            inBand = false
                            break
                        }
                        val local = change.position
                        val current = registry.resolve(
                            local.x, local.y, viewportW, viewportH, nearest = true)
                        dispatch(
                            controller.move(current, local.x, local.y),
                            latestOpen, latestChange, steal,
                        )
                        inBand = controller.inEdgeBand(viewportH, densityValue)
                    }
                    if (!controller.consuming) {
                        steal.value = false
                        inBand = false
                    }
                }
            },
    ) { content(registry) }
}

@Composable
fun MonitorMediaHitTarget(
    registry: MonitorMediaHitRegistry,
    id: String,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    DisposableEffect(id, registry) { onDispose { registry.remove(id) } }
    Box(
        modifier.onGloballyPositioned { coords -> registry.putFrom(id, coords) },
        content = content,
    )
}

private fun dispatch(
    news: MonitorMediaSelectionController.News?,
    onOpen: (String) -> Unit,
    onSelectionChange: (Boolean, Set<String>) -> Unit,
    steal: MutableState<Boolean>,
) {
    when (news) {
        is MonitorMediaSelectionController.News.Open -> onOpen(news.id)
        is MonitorMediaSelectionController.News.Selection -> {
            steal.value = true
            onSelectionChange(news.selecting, news.selected)
        }
        null -> Unit
    }
}
