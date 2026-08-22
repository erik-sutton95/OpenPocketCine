package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitTouchSlopOrCancellation
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.positionChange
import kotlinx.coroutines.withTimeoutOrNull

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

internal suspend fun PointerInputScope.detectHoldThenDrag(
    holdMs: Long,
    enabled: Boolean,
    onHold: () -> Unit,
    onDrag: (Offset) -> Unit,
    onEnd: (translation: Offset) -> Unit,
) {
    if (!enabled) return
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val up = withTimeoutOrNull(holdMs) { waitForUpOrCancellation() }
        if (up != null) return@awaitEachGesture
        onHold()
        var total = Offset.Zero
        val slop =
            awaitTouchSlopOrCancellation(down.id) { change, _ ->
                change.consume()
            }
        if (slop != null) {
            drag(slop.id) { change ->
                total += change.positionChange()
                change.consume()
                onDrag(total)
            }
        }
        onEnd(total)
    }
}
