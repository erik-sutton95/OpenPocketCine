package com.opencapture.monitorui

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt

/** Mounted, enabled readout bounds in window pixels; no camera or picker taxonomy. */
@Stable
class MonitorReadoutRegions {
    private val frames = mutableStateMapOf<Any, Rect>()
    internal fun update(owner: Any, frame: Rect?) {
        if (frame == null) frames.remove(owner) else if (frames[owner] != frame) frames[owner] = frame
    }
    internal fun snapshot(): List<Rect> = frames.values.toList()
}

val LocalMonitorReadoutRegions = staticCompositionLocalOf<MonitorReadoutRegions?> { null }

/** Let an enabled, mounted control receive its original pointer through a picker backdrop. */
@Composable
fun Modifier.monitorPickerPassthrough(enabled: Boolean): Modifier = monitorReadoutRegion(enabled)

/** Register the actual recognizer bounds; disabling or unmounting retires its hole. */
@Composable
internal fun Modifier.monitorReadoutRegion(enabled: Boolean): Modifier {
    val regions = LocalMonitorReadoutRegions.current ?: return this
    val owner = remember { Any() }
    var frame by remember { mutableStateOf<Rect?>(null) }
    // Observe layout state during composition, not inside SideEffect. Otherwise
    // a static button never publishes its first measured bounds to the registry.
    val activeFrame = frame.takeIf { enabled }
    SideEffect { regions.update(owner, activeFrame) }
    DisposableEffect(regions, owner) { onDispose { regions.update(owner, null) } }
    return onGloballyPositioned { frame = it.boundsInWindow() }
}

/** Exact complement of the holes. Overlapping holes are a union, never XOR. */
internal fun monitorDismissRegions(viewport: Rect, holes: List<Rect>): List<Rect> {
    if (viewport.width <= 0f || viewport.height <= 0f) return emptyList()
    val clipped = holes.map { it.intersect(viewport) }.filter { it.width > 0f && it.height > 0f }
    val edges = (listOf(viewport.left, viewport.right) + clipped.flatMap { listOf(it.left, it.right) })
        .distinct().sorted()
    return buildList {
        edges.zipWithNext().forEach { (left, right) ->
            var top = viewport.top
            clipped.filter { it.left < right && it.right > left }.sortedBy { it.top }.forEach { hole ->
                if (hole.top > top) add(Rect(left, top, right, hole.top))
                top = maxOf(top, hole.bottom)
            }
            if (top < viewport.bottom) add(Rect(left, top, right, viewport.bottom))
        }
    }
}

/** Only the complement has input nodes, so original readouts receive down/hold/up. */
@Composable
fun MonitorReadoutDismissBackdrop(onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val regions = LocalMonitorReadoutRegions.current
    val density = LocalDensity.current
    val dismiss by rememberUpdatedState(onDismiss)
    var viewport by remember { mutableStateOf(Rect.Zero) }
    val holes = regions?.snapshot().orEmpty()
    val pieces = remember(viewport, holes) { monitorDismissRegions(viewport, holes) }
    val configuration = LocalViewConfiguration.current
    // Small complement rectangles must not expand their touch bounds into a hole.
    val exactTargets = remember(configuration) {
        object : ViewConfiguration by configuration {
            override val minimumTouchTargetSize: DpSize = DpSize.Zero
        }
    }
    CompositionLocalProvider(LocalViewConfiguration provides exactTargets) {
        Box(modifier.fillMaxSize().onGloballyPositioned { viewport = it.boundsInWindow() }) {
            pieces.forEach { rect ->
                Box(Modifier.absoluteOffset {
                    IntOffset((rect.left - viewport.left).roundToInt(), (rect.top - viewport.top).roundToInt())
                }.size(with(density) { rect.width.toDp() }, with(density) { rect.height.toDp() })
                    .pointerInput(Unit) { detectTapGestures { dismiss() } })
            }
        }
    }
}
