package com.opencapture.openpocketcine.media

import android.os.SystemClock
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEvent
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.positionChanged
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max

/** Vertical swipe on the letterboxed frame — iOS `chromeSwipeGesture`. */
enum class PlaybackChromeSwipe {
    SHOW,
    HIDE,
    NONE,
    ;

    companion object {
        const val MIN_DISTANCE = 28f
        const val AXIS_BIAS = 8f
        const val MIN_VERTICAL = 44f

        fun classify(dx: Float, dy: Float): PlaybackChromeSwipe {
            if (hypot(dx, dy) < MIN_DISTANCE) return NONE
            if (abs(dy) <= abs(dx) + AXIS_BIAS) return NONE
            if (abs(dy) <= MIN_VERTICAL) return NONE
            return if (dy < 0f) SHOW else HIDE
        }
    }
}

/** Long-press then horizontal drag. iOS `FrameScrub`. */
object PlaybackFrameScrub {
    const val LONG_PRESS_MS = 350L
    const val SEEK_THROTTLE_SECONDS = 0.075
    const val PAN_SUPPRESS_SLOP = 8f
    const val PINCH_SUPPRESS = 0.02f

    fun timeAfterDelta(
        originSeconds: Float,
        deltaPx: Float,
        videoWidthPx: Float,
        durationSeconds: Float,
    ): Float {
        if (durationSeconds <= 0f || videoWidthPx <= 0f) return originSeconds.coerceIn(0f, max(0f, durationSeconds))
        val time = originSeconds + (deltaPx / videoWidthPx) * durationSeconds
        return time.coerceIn(0f, durationSeconds)
    }
}

data class PlaybackGestureConfig(
    val enableTap: Boolean = true,
    val enableScrub: Boolean = true,
    val enableSwipe: Boolean = true,
)

internal suspend fun PointerInputScope.detectPlaybackVideoGestures(
    isReady: () -> Boolean,
    isZoomed: () -> Boolean,
    config: PlaybackGestureConfig = PlaybackGestureConfig(),
    onTap: () -> Unit,
    onChromeSwipe: (PlaybackChromeSwipe) -> Unit,
    onScrubStart: () -> Unit,
    onScrubDelta: (dx: Float) -> Unit,
    onScrubEnd: () -> Unit,
    onPinch: (magnification: Float, centroid: Offset) -> Unit,
    onPinchEnd: () -> Unit,
    onPan: (translation: Offset) -> Unit,
    onPanEnd: () -> Unit,
) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val start = down.position
        var total = Offset.Zero
        var armedScrub = false
        var scrubbing = false
        var pinching = false
        var panning = false
        var suppressTap = false
        var twoFingerSeen = false
        var initialPinchSpan = 0f
        var pinchAnchor = Offset.Zero
        val slop = viewConfiguration.touchSlop
        val holdDeadline = down.uptimeMillis + PlaybackFrameScrub.LONG_PRESS_MS

        fun pressedOf(event: PointerEvent) = event.changes.filter { it.pressed }

        fun startPinch(pressed: List<PointerInputChange>) {
            twoFingerSeen = true
            pinching = true
            armedScrub = false
            suppressTap = true
            pinchAnchor = centroidOf(pressed)
            initialPinchSpan = fingerSpan(pressed).coerceAtLeast(1f)
            onPinch(1f, pinchAnchor)
            pressed.forEach { it.consume() }
        }

        // Arm long-press, or break out early for pinch / pan / drag.
        while (true) {
            val remaining = (holdDeadline - SystemClock.uptimeMillis()).coerceAtLeast(1L)
            val event = withTimeoutOrNull(remaining) { awaitPointerEvent() }
            if (event == null) {
                if (config.enableScrub && !twoFingerSeen && !isZoomed()) {
                    armedScrub = true
                }
                break
            }
            val pressed = pressedOf(event)
            if (pressed.isEmpty()) {
                total = (event.changes.firstOrNull()?.position ?: start) - start
                finishUp(
                    total = total,
                    suppressTap = suppressTap,
                    pinching = false,
                    panning = false,
                    scrubbing = false,
                    slop = slop,
                    isReady = isReady,
                    config = config,
                    onTap = onTap,
                    onChromeSwipe = onChromeSwipe,
                    onPinchEnd = onPinchEnd,
                    onPanEnd = onPanEnd,
                    onScrubEnd = onScrubEnd,
                )
                return@awaitEachGesture
            }
            if (pressed.size >= 2) {
                startPinch(pressed)
                break
            }
            val pos = pressed[0].position
            total = pos - start
            val distance = hypot(total.x, total.y)
            if (isZoomed() && distance > PlaybackFrameScrub.PAN_SUPPRESS_SLOP) {
                panning = true
                suppressTap = true
                onPan(total)
                break
            }
            if (distance > slop) {
                break
            }
        }

        while (true) {
            val event = awaitPointerEvent()
            val pressed = pressedOf(event)
            if (pressed.isEmpty()) {
                total = (event.changes.firstOrNull()?.position ?: (start + total)) - start
                break
            }
            if (pressed.size >= 2) {
                if (!pinching) startPinch(pressed)
                val mag = fingerSpan(pressed) / initialPinchSpan.coerceAtLeast(1f)
                if (abs(mag - 1f) > PlaybackFrameScrub.PINCH_SUPPRESS) suppressTap = true
                onPinch(mag, pinchAnchor)
                pressed.forEach { it.consume() }
                continue
            }
            val pos = pressed[0].position
            total = pos - start
            if (pinching) continue
            if (armedScrub && config.enableScrub && !isZoomed()) {
                if (!scrubbing) {
                    scrubbing = true
                    suppressTap = true
                    onScrubStart()
                }
                onScrubDelta(total.x)
                pressed.forEach { if (it.positionChanged()) it.consume() }
                continue
            }
            if (isZoomed()) {
                if (hypot(total.x, total.y) > PlaybackFrameScrub.PAN_SUPPRESS_SLOP) {
                    panning = true
                    suppressTap = true
                }
                onPan(total)
                continue
            }
        }

        finishUp(
            total = total,
            suppressTap = suppressTap,
            pinching = pinching,
            panning = panning,
            scrubbing = scrubbing,
            slop = slop,
            isReady = isReady,
            config = config,
            onTap = onTap,
            onChromeSwipe = onChromeSwipe,
            onPinchEnd = onPinchEnd,
            onPanEnd = onPanEnd,
            onScrubEnd = onScrubEnd,
        )
    }
}

private fun finishUp(
    total: Offset,
    suppressTap: Boolean,
    pinching: Boolean,
    panning: Boolean,
    scrubbing: Boolean,
    slop: Float,
    isReady: () -> Boolean,
    config: PlaybackGestureConfig,
    onTap: () -> Unit,
    onChromeSwipe: (PlaybackChromeSwipe) -> Unit,
    onPinchEnd: () -> Unit,
    onPanEnd: () -> Unit,
    onScrubEnd: () -> Unit,
) {
    if (pinching) onPinchEnd()
    if (panning) onPanEnd()
    if (scrubbing) onScrubEnd()
    var blocked = suppressTap
    if (!pinching && !panning && !scrubbing && config.enableSwipe) {
        val swipe = PlaybackChromeSwipe.classify(total.x, total.y)
        if (swipe != PlaybackChromeSwipe.NONE) {
            onChromeSwipe(swipe)
            blocked = true
        }
    }
    if (!blocked &&
        config.enableTap &&
        hypot(total.x, total.y) < slop &&
        isReady()
    ) {
        onTap()
    }
}

private fun centroidOf(changes: List<PointerInputChange>): Offset {
    var x = 0f
    var y = 0f
    for (change in changes) {
        x += change.position.x
        y += change.position.y
    }
    val n = max(1, changes.size)
    return Offset(x / n, y / n)
}

private fun fingerSpan(changes: List<PointerInputChange>): Float {
    if (changes.size < 2) return 0f
    val a = changes[0].position
    val b = changes[1].position
    return hypot(a.x - b.x, a.y - b.y)
}

internal fun unitPoint(centroid: Offset, width: Float, height: Float): Pair<Float, Float> {
    val x = if (width <= 0f) 0.5f else (centroid.x / width).coerceIn(0f, 1f)
    val y = if (height <= 0f) 0.5f else (centroid.y / height).coerceIn(0f, 1f)
    return x to y
}
