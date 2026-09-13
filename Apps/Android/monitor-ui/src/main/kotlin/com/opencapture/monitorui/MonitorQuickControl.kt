package com.opencapture.monitorui

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
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
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.roundToInt

/** Display values plus an opaque, immutable adapter identity used only for equality. */
@Immutable
data class MonitorQuickControl(val options: List<String>, val selection: String,
    val marked: Set<String> = emptySet(), val enabled: Boolean = true, val context: String = "",
    val identity: Any? = null)

/** Read-only projection of the original pointer; this never owns an input recognizer. */
@Immutable
data class MonitorQuickPreview(val control: MonitorQuickControl, val position: Float) {
    val selection: String get() = if (MonitorDrumSelection.changedDetent(
        control.options.indexOf(control.selection).coerceAtLeast(0).toFloat(), position)) {
        control.options.getOrNull(position.roundToInt()).orEmpty()
    } else control.selection
}

/** Deterministic recognizer policy. Cancellation is terminal, including after re-enabling. */
internal class MonitorQuickInteraction(private val control: MonitorQuickControl?) {
    sealed interface Release {
        data object Open : Release
        data class Commit(val control: MonitorQuickControl, val value: String) : Release
    }
    private val origin = control?.options?.indexOf(control.selection)?.coerceAtLeast(0)?.toFloat() ?: 0f
    private var startX = 0f
    private var lastX = 0f
    private var lastY = 0f
    private var ended = false
    var preview: MonitorQuickPreview? = null
        private set
    val finished: Boolean get() = ended
    private val canArm get() = control?.enabled == true && control.options.isNotEmpty()

    fun hold(elapsedMillis: Long) {
        if (!ended && preview == null && canArm && elapsedMillis >= MonitorDrumSelection.HOLD_MILLISECONDS) arm()
    }

    fun move(x: Float, y: Float, consumed: Boolean = false, pointerCount: Int = 1) {
        if (ended) return
        if (consumed || pointerCount > 1 || !x.isFinite() || !y.isFinite()) { cancel(); return }
        lastX = x
        lastY = y
        if (preview == null) {
            if (abs(y) > MonitorDrumSelection.DRAG_THRESHOLD && abs(y) > abs(x)) { cancel(); return }
            if (canArm && abs(x) > MonitorDrumSelection.DRAG_THRESHOLD) arm()
        }
        if (preview != null) preview = MonitorQuickPreview(control!!,
            MonitorDrumSelection.position(origin, x - startX, control.options.size))
    }

    private fun arm() {
        startX = lastX
        preview = MonitorQuickPreview(control!!, origin)
    }

    fun release(current: MonitorQuickControl?, enabled: Boolean): Release? {
        if (ended) return null
        val held = preview
        cancel()
        if (!enabled || current != control) return null
        if (held == null) return if (hypot(lastX, lastY) <= 8f) Release.Open else null
        if (!MonitorDrumSelection.changedDetent(origin, held.position)) return null
        val value = control?.options?.getOrNull(held.position.roundToInt()) ?: return null
        return if (value != control.selection) Release.Commit(control, value) else null
    }

    fun cancel() { ended = true; preview = null }
}

/** One recognizer owns tap, 280ms hold, and >14dp travel. Only release commits. */
@Composable
fun Modifier.monitorReadoutGesture(control: MonitorQuickControl?, enabled: Boolean,
    onOpen: () -> Unit, onCommit: (MonitorQuickControl, String) -> Unit, bottomClearanceDp: Float,
    owner: MonitorQuickGestureOwner, ownerId: String,
    previewContent: (@Composable (MonitorQuickPreview, Float) -> Unit)? = null,
    fromTop: Boolean = false, ceilingY: Float? = null,
    onPreviewBegin: () -> Unit = {}): Modifier {
    var preview by remember { mutableStateOf<MonitorQuickPreview?>(null) }
    val open by rememberUpdatedState(onOpen)
    val beginPreview by rememberUpdatedState(onPreviewBegin)
    val commit by rememberUpdatedState(onCommit)
    val currentControl by rememberUpdatedState(control)
    val currentEnabled by rememberUpdatedState(enabled)
    val density = LocalDensity.current
    val config = LocalConfiguration.current
    val direction = LocalLayoutDirection.current
    val insets = WindowInsets.safeDrawing
    val leading = insets.getLeft(density, direction) / density.density
    val trailing = insets.getRight(density, direction) / density.density
    val top = insets.getTop(density) / density.density
    val bottom = insets.getBottom(density) / density.density
    fun place(height: Float, width: Float, heightWindow: Float) = if (fromTop) {
        MonitorLayoutPolicy.topPanel(height, width, heightWindow, leading, trailing, top, bottom,
            ceilingY, if (bottomClearanceDp > 0f) heightWindow - bottomClearanceDp + 12f else null)
    } else {
        MonitorLayoutPolicy.bottomPanel(height, width, heightWindow, leading, trailing, top, bottom,
            if (bottomClearanceDp > 0f) heightWindow - bottomClearanceDp + 12f else null)
    }
    val layout = place(0f, config.screenWidthDp.toFloat(), config.screenHeightDp.toFloat())
    val heldPreview = preview
    if (heldPreview != null && heldPreview.control == control && enabled && previewContent != null) Popup(
        popupPositionProvider = remember(bottomClearanceDp, top, bottom, leading, trailing, density.density, fromTop, ceilingY) {
            object : PopupPositionProvider {
                override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize,
                    layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
                    val scale = density.density
                    val placed = place(popupContentSize.height / scale, windowSize.width / scale, windowSize.height / scale)
                    return IntOffset((placed.x * scale).roundToInt(), (placed.y * scale).roundToInt())
                }
            }
        }, properties = PopupProperties(focusable = false, dismissOnBackPress = false, dismissOnClickOutside = false)) {
        MonitorCaptureReveal(Modifier.width(layout.width.dp).heightIn(max = layout.maxHeight.dp)
            .clearAndSetSemantics { }, fromTop = fromTop) {
            previewContent(heldPreview, layout.maxHeight)
        }
    }
    return this.monitorReadoutRegion(enabled).semantics { role = Role.Button; if (enabled) onClick { open(); true } }
        .pointerInput(control, enabled, config.orientation, config.screenWidthDp, config.screenHeightDp,
            bottomClearanceDp, leading, trailing, top, bottom, density.density, density.fontScale, fromTop, ceilingY) {
            if (!enabled) { preview = null; return@pointerInput }
            var held: MonitorQuickGestureOwner.Lease? = null
            try {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = true)
                    val token = owner.acquire(ownerId) ?: return@awaitEachGesture
                    held = token
                    val interaction = MonitorQuickInteraction(if (previewContent != null) control else null)
                    // Do not consume a pending down: the parent can still claim a scroll.
                    var elapsed = 0L
                    try {
                        while (!interaction.finished) {
                            val event = if (interaction.preview == null && control?.enabled == true &&
                                control.options.isNotEmpty() && previewContent != null) {
                                withTimeoutOrNull((MonitorDrumSelection.HOLD_MILLISECONDS - elapsed).coerceAtLeast(1L)) { awaitPointerEvent() }
                            } else awaitPointerEvent()
                            if (event == null) {
                                interaction.hold(MonitorDrumSelection.HOLD_MILLISECONDS)
                                if (preview == null && interaction.preview != null) beginPreview()
                                preview = interaction.preview
                                owner.setActive(token, preview != null)
                                continue
                            }
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            val delta = change.position - down.position
                            elapsed = change.uptimeMillis - down.uptimeMillis
                            interaction.move(delta.x / density.density, delta.y / density.density,
                                change.isConsumed, event.changes.count { it.pressed })
                            if (previewContent != null) interaction.hold(elapsed)
                            if (preview == null && interaction.preview != null) beginPreview()
                            preview = interaction.preview
                            owner.setActive(token, preview != null)
                            if (interaction.finished) break
                            // Reserve horizontal motion for this readout while it approaches
                            // 14dp; a parent row's smaller touch slop must not steal a slow drag.
                            // Vertical intent and already-consumed scroll events still cancel.
                            if (preview != null || (control?.enabled == true && previewContent != null &&
                                abs(delta.x) > abs(delta.y))) change.consume()
                            if (!change.pressed) {
                                when (val release = interaction.release(if (previewContent != null) currentControl else null, currentEnabled)) {
                                    MonitorQuickInteraction.Release.Open -> { change.consume(); open() }
                                    is MonitorQuickInteraction.Release.Commit -> commit(release.control, release.value)
                                    null -> Unit
                                }
                                break
                            }
                        }
                    } finally { interaction.cancel(); preview = null; owner.release(token); held = null }
                }
            } finally { preview = null; held?.let(owner::release) }
        }
}
