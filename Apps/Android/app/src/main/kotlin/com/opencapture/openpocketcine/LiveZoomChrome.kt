package com.opencapture.openpocketcine

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.PocketCameraSession
import kotlin.math.abs
import kotlin.math.roundToInt

object LiveZoom {
    fun factor(status: CameraStatus): Double =
        if (status.zoomFactorRaw > 0) status.zoomFactorRaw / 1024.0 else 1.0

    fun label(factor: Double): String {
        val shown = (factor * 10.0).roundToInt() / 10.0
        if (abs(shown - 12.0) < 0.05) return "12×"
        val nearest = shown.roundToInt()
        if (abs(shown - nearest) < 0.05 && nearest in 1..12) return "${nearest}×"
        return String.format("%.1f×", shown)
    }

    fun nextJump(from: Double): Double =
        when {
            from < 3.0 -> 3.0
            from < 5.5 -> 6.0
            from < 11.5 -> 12.0
            else -> 1.0
        }

    fun setZoom(session: PocketCameraSession, factor: Double): Boolean =
        LiveSessionBridge.call(session, "setZoom", factor)

    fun updatePinch(session: PocketCameraSession, magnification: Double): Boolean {
        if (LiveSessionBridge.call(session, "updateZoomPinch", magnification)) return true
        return LiveSessionBridge.call(session, "setZoomSlider", factorFromPinch(magnification))
    }

    fun endPinch(session: PocketCameraSession) {
        LiveSessionBridge.call(session, "endZoomPinch")
    }

    private fun factorFromPinch(magnification: Double): Double =
        (1.0 * magnification).coerceIn(1.0, 12.0)
}

/** Ignore sub-tenth `cam_fov` jitter on the chip unless the operator is pinching. */
object LiveZoomLabelHold {
    fun shouldReplace(
        held: Double,
        next: Double,
        pinching: Boolean,
        epsilon: Double = 0.12,
    ): Boolean {
        if (pinching) return true
        return abs(next - held) >= epsilon
    }
}

@Composable
fun LiveZoomChip(
    factor: Double,
    locked: Boolean,
    modifier: Modifier = Modifier,
    pinching: Boolean = false,
    onCycle: () -> Unit,
) {
    var held by remember { mutableStateOf(factor) }
    LaunchedEffect(factor, pinching) {
        if (LiveZoomLabelHold.shouldReplace(held, factor, pinching)) {
            held = factor
        }
    }
    Box(
        modifier
            .size(LiveDesign.ZOOM_CHIP_DP.dp)
            .monitorGlass(CircleShape)
            .chromeClickable(enabled = !locked, onClick = onCycle)
            .semantics { contentDescription = "Zoom ${LiveZoom.label(held)}" },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            LiveZoom.label(held),
            color = LiveDesign.text.copy(alpha = if (locked) 0.4f else 1f),
            style = LiveType.ui(13f, FontWeight.Bold),
            maxLines = 1,
        )
    }
}

@Composable
fun LiveFeedGestureWell(
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onTap: (normalized: Offset) -> Unit,
    onSwipeClean: (clean: Boolean) -> Unit,
    onPinch: (magnification: Float) -> Unit,
    onPinchEnd: () -> Unit,
) {
    val density = LocalDensity.current
    Box(
        modifier
            .fillMaxSize()
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                val swipeFloor = with(density) { 44.dp.toPx() }
                val tapSlop = with(density) { 24.dp.toPx() }
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val start = down.position
                    var last = start
                    var initialSpan = 0f
                    var pinched = false
                    var maxPointers = 1
                    while (true) {
                        val event = awaitPointerEvent()
                        val pressed = event.changes.filter { it.pressed }
                        maxPointers = maxOf(maxPointers, pressed.size)
                        if (pressed.size >= 2) {
                            val span = (pressed[0].position - pressed[1].position).getDistance()
                            if (initialSpan <= 1f) initialSpan = span
                            if (initialSpan > 1f) {
                                pinched = true
                                onPinch(span / initialSpan)
                            }
                            pressed.forEach { if (it.positionChanged()) it.consume() }
                        } else if (pressed.size == 1) {
                            last = pressed[0].position
                        }
                        if (pressed.isEmpty()) {
                            if (pinched) {
                                onPinchEnd()
                            } else {
                                val translation = last - start
                                val dy = translation.y
                                val dx = translation.x
                                if (abs(dy) > abs(dx) + 8f && abs(dy) > swipeFloor) {
                                    onSwipeClean(dy > 0f)
                                } else if (translation.getDistance() < tapSlop) {
                                    val nx = (last.x / size.width.toFloat()).coerceIn(0f, 1f)
                                    val ny = (last.y / size.height.toFloat()).coerceIn(0f, 1f)
                                    onTap(Offset(nx, ny))
                                }
                            }
                            break
                        }
                    }
                }
            },
    )
}
