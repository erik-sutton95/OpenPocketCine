package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.positionChange

internal suspend fun PointerInputScope.detectTapAndLongPress(
    longPressMs: Long,
    enabled: Boolean,
    onTap: () -> Unit,
    onLongPress: () -> Unit,
) {
    if (!enabled) return
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false)
        val up = withTimeoutOrNull(longPressMs) { waitForUpOrCancellation() }
        if (up == null) {
            onLongPress()
            waitForUpOrCancellation()
        } else {
            onTap()
        }
    }
}

/**
 * iOS `LongPressGesture(0.3).sequenced(before: DragGesture(minimumDistance: 0))`.
 *
 * Hold timeout is [AwaitPointerEventScope.withTimeoutOrNull] (Compose's pointer
 * timeout), **not** kotlinx `withTimeout` — that cancels the whole pointerInput
 * and the drag never starts. Drag deltas use [positionChange] so a moving
 * `offset` does not feed back into the translation.
 */
internal suspend fun PointerInputScope.detectHoldThenDrag(
    holdMs: Long,
    enabled: Boolean,
    onDown: () -> Unit = {},
    onHold: () -> Unit,
    onDrag: (translation: Offset) -> Unit,
    onEnd: (translation: Offset) -> Unit,
    /** Map a local pointer into a space that does not move with the panel (root). */
    toRoot: (Offset) -> Offset = { it },
) {
    if (!enabled) return
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        down.consume()
        onDown()
        val pointerId = down.id
        val downRoot = toRoot(down.position)
        // null = timeout = still down = hold succeeded (Compose pointer timeout).
        // false = lifted or lost the pointer before [holdMs].
        val releasedEarly =
            withTimeoutOrNull(holdMs) {
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == pointerId }
                        ?: return@withTimeoutOrNull true
                    change.consume()
                    if (!change.pressed) return@withTimeoutOrNull true
                }
                @Suppress("UNREACHABLE_CODE")
                false
            }
        if (releasedEarly != null) return@awaitEachGesture
        onHold()
        var total = Offset.Zero
        drag(pointerId) { change ->
            total = toRoot(change.position) - downRoot
            change.consume()
            onDrag(total)
        }
        onEnd(total)
    }
}
