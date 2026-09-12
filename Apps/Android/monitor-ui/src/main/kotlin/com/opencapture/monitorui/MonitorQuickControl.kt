package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import kotlin.math.roundToInt

@Immutable
data class MonitorQuickControl(val options: List<String>, val selection: String,
    val marked: Set<String> = emptySet(), val enabled: Boolean = true, val context: String = "")

/** One recognizer owns tap, 280ms hold, and >14dp travel. Only release commits. */
@Composable
internal fun Modifier.monitorReadoutGesture(control: MonitorQuickControl?, enabled: Boolean,
    onOpen: () -> Unit, onCommit: (String) -> Unit, bottomClearanceDp: Float,
    owner: MonitorQuickGestureOwner, ownerId: String): Modifier {
    var active by remember { mutableStateOf(false) }
    var position by remember { mutableFloatStateOf(0f) }
    val open by rememberUpdatedState(onOpen)
    val commit by rememberUpdatedState(onCommit)
    val density = LocalDensity.current
    val config = LocalConfiguration.current
    val margin = with(density) { 14.dp.roundToPx() }
    val bottomClearance = with(density) { bottomClearanceDp.dp.roundToPx() }
    val detent = with(density) { MonitorDrumSelection.POINTS_PER_VALUE.dp.toPx() }
    val threshold = with(density) { MonitorDrumSelection.DRAG_THRESHOLD.dp.toPx() }
    val origin = control?.options?.indexOf(control.selection)?.coerceAtLeast(0) ?: 0
    if (active && control != null) Popup(
        popupPositionProvider = remember(margin, bottomClearance) { object : PopupPositionProvider {
            override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize,
                layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset = IntOffset(
                (windowSize.width / 2 - popupContentSize.width / 2).coerceIn(margin,
                    (windowSize.width - popupContentSize.width - margin).coerceAtLeast(margin)),
                (windowSize.height - popupContentSize.height - bottomClearance).coerceAtLeast(margin))
        } }, properties = PopupProperties(focusable = false, dismissOnClickOutside = false)) {
        Box(Modifier.width(minOf(if (minOf(config.screenWidthDp, config.screenHeightDp) >= 600) 620 else 480,
            config.screenWidthDp - 28).dp).background(MonitorPalette.expandedGlass, RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)).padding(8.dp)) {
            MonitorValueDrum(control.options, control.selection, markedValues = control.marked,
                interactive = false, displayPosition = position, dimDisabled = false, onSelect = {})
        }
    }
    return this.semantics { role = Role.Button; if (enabled) onClick { open(); true } }
        .pointerInput(control, enabled, config.orientation, config.screenWidthDp, config.screenHeightDp, bottomClearanceDp, density.density, density.fontScale) {
            if (!enabled) { active = false; return@pointerInput }
            var held: MonitorQuickGestureOwner.Lease? = null
            try {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = true)
                    val token = owner.acquire(ownerId) ?: return@awaitEachGesture
                    held = token
                    down.consume()
                    var elapsed = 0L
                    var startX = down.position.x
                    var armed = false
                    var lastX = startX
                    try {
                        while (true) {
                            val event = if (!armed && control?.enabled == true && control.options.isNotEmpty()) {
                                withTimeoutOrNull((MonitorDrumSelection.HOLD_MILLISECONDS - elapsed).coerceAtLeast(1L)) { awaitPointerEvent() }
                            } else awaitPointerEvent()
                            if (event == null) {
                                armed = true; active = true; owner.setActive(token, true); startX = lastX; position = origin.toFloat()
                                continue
                            }
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (change.isConsumed || event.changes.count { it.pressed } > 1) break
                            lastX = change.position.x
                            elapsed = change.uptimeMillis - down.uptimeMillis
                            val delta = change.position - down.position
                            if (!armed && kotlin.math.abs(delta.y) > threshold && kotlin.math.abs(delta.y) > kotlin.math.abs(delta.x)) break
                            if (!armed && control?.enabled == true && control.options.isNotEmpty() && kotlin.math.abs(delta.x) > threshold) {
                                armed = true; active = true; owner.setActive(token, true); startX = lastX
                            }
                            if (armed) position = MonitorDrumSelection.position(origin.toFloat(), (lastX - startX) / density.density, control!!.options.size)
                            change.consume()
                            if (!change.pressed) {
                                active = false
                                if (armed) {
                                    val value = control!!.options[position.roundToInt()]
                                    if (MonitorDrumSelection.changedDetent(origin.toFloat(), position) && value != control.selection) commit(value)
                                } else if (delta.getDistance() <= with(density) { 8.dp.toPx() }) open()
                                break
                            }
                        }
                    } finally { active = false; owner.release(token); held = null }
                }
            } finally { active = false; held?.let(owner::release) }
        }
}
