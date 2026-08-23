package com.opencapture.openpocketcine

import android.view.MotionEvent
import android.view.ScaleGestureDetector
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.session.CamFov
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.LiveFeedFocusGesture
import com.opencapture.openpocketcine.session.PocketCameraSession
import com.opencapture.openpocketcine.session.TrackingBox
import kotlin.math.abs
import kotlin.math.hypot
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

object LiveZoom {
    fun factor(status: CameraStatus): Double =
        CamFov.readout(live = status.zoomFactor, preview = null, fallback = 1.0)

    fun label(factor: Double): String = CamFov.displayLabel(factor)

    fun nextJump(from: Double): Double = CamFov.nextJump(from)

    fun setZoom(session: PocketCameraSession, factor: Double) {
        session.setZoom(factor)
    }

    fun updatePinch(session: PocketCameraSession, magnification: Double) {
        session.updateZoomPinch(magnification)
    }

    fun endPinch(session: PocketCameraSession) {
        session.endZoomPinch()
    }
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
            .semantics {
                contentDescription = "Zoom ${LiveZoom.label(held)}. Cycles 1×, 3×, 6×, and 12×"
            },
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

/**
 * iOS `LiveZoomPinchWell` + `MagnifyGesture.simultaneously(DragGesture)`.
 * Pinch is Android `ScaleGestureDetector` (cumulative magnification from 1)
 * so two fingers stay on one MotionEvent stream over the Vulkan SurfaceView.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun LiveFeedGestureWell(
    enabled: Boolean,
    modifier: Modifier = Modifier,
    feed: ChromeRect? = null,
    onTap: (normalized: Offset) -> Unit,
    onSwipeClean: (clean: Boolean) -> Unit,
    onPinch: (magnification: Float) -> Unit,
    onPinchEnd: () -> Unit,
    onTrack: (TrackingBox) -> Unit = {},
) {
    val density = LocalDensity.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val latestOnPinch = rememberUpdatedState(onPinch)
    val latestOnPinchEnd = rememberUpdatedState(onPinchEnd)
    val latestOnTap = rememberUpdatedState(onTap)
    val latestOnSwipe = rememberUpdatedState(onSwipeClean)
    val latestOnTrack = rememberUpdatedState(onTrack)
    var draft by remember { mutableStateOf<TrackingBox?>(null) }
    val swipeFloor = with(density) { 44.dp.toPx() }
    val holdSlop = with(density) { LiveFeedFocusGesture.TRACK_HOLD_SLOP.dp.toPx() }
    val feedLeft = with(density) { (feed?.x ?: 0f).dp.toPx() }
    val feedTop = with(density) { (feed?.y ?: 0f).dp.toPx() }
    val feedW = with(density) { (feed?.width ?: 0f).dp.toPx() }.coerceAtLeast(1f)
    val feedH = with(density) { (feed?.height ?: 0f).dp.toPx() }.coerceAtLeast(1f)

    val gesture = rememberFeedGestureState()
    fun feedNorm(x: Float, y: Float): Offset? {
        if (feed == null) {
            return Offset(x, y)
        }
        val nx = ((x - feedLeft) / feedW).coerceIn(0f, 1f)
        val ny = ((y - feedTop) / feedH).coerceIn(0f, 1f)
        if (x < feedLeft || y < feedTop || x > feedLeft + feedW || y > feedTop + feedH) return null
        return Offset(nx, ny)
    }
    fun feedBox(ax: Float, ay: Float, bx: Float, by: Float): TrackingBox {
        if (feed == null) {
            return TrackingBox.normalized(ax.toDouble(), ay.toDouble(), bx.toDouble(), by.toDouble())
        }
        fun nx(v: Float) = ((v - feedLeft) / feedW).toDouble().coerceIn(0.0, 1.0)
        fun ny(v: Float) = ((v - feedTop) / feedH).toDouble().coerceIn(0.0, 1.0)
        return TrackingBox.normalized(nx(ax), ny(ay), nx(bx), ny(by))
    }
    val pinch =
        remember {
            object {
                var total = 1f
                var active = false
                var ended = false
            }
        }
    val detector =
        remember {
            ScaleGestureDetector(
                context,
                object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                    override fun onScaleBegin(d: ScaleGestureDetector): Boolean {
                        pinch.total = 1f
                        pinch.active = true
                        pinch.ended = false
                        return true
                    }

                    override fun onScale(d: ScaleGestureDetector): Boolean {
                        pinch.total = (pinch.total * d.scaleFactor).coerceIn(1f / 12f, 12f)
                        latestOnPinch.value(pinch.total)
                        return true
                    }

                    override fun onScaleEnd(d: ScaleGestureDetector) {
                        if (pinch.active && !pinch.ended) {
                            pinch.ended = true
                            latestOnPinchEnd.value()
                        }
                        pinch.active = false
                    }
                },
            ).also { it.isQuickScaleEnabled = false }
        }

    Box(
        modifier
            .fillMaxSize()
            .background(Color.White.copy(alpha = 0.001f))
            .pointerInteropFilter { event ->
                if (!enabled) return@pointerInteropFilter false
                detector.onTouchEvent(event)
                val count = event.pointerCount
                val action = event.actionMasked
                if (pinch.active || count >= 2) {
                    draft = null
                    if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                        if (pinch.active && !pinch.ended) {
                            pinch.ended = true
                            pinch.active = false
                            latestOnPinchEnd.value()
                        }
                    }
                    return@pointerInteropFilter true
                }
                when (action) {
                    MotionEvent.ACTION_DOWN -> {
                        gesture.startX = event.x
                        gesture.startY = event.y
                        gesture.lastX = event.x
                        gesture.lastY = event.y
                        gesture.armed = false
                        gesture.hold?.cancel()
                        gesture.hold =
                            scope.launch {
                                delay((LiveFeedFocusGesture.TRACK_HOLD_SEC * 1000).toLong())
                                val slop =
                                    hypot(gesture.lastX - gesture.startX, gesture.lastY - gesture.startY)
                                if (!pinch.active && slop <= holdSlop) {
                                    gesture.armed = true
                                    draft = feedBox(gesture.startX, gesture.startY, gesture.lastX, gesture.lastY)
                                }
                            }
                    }
                    MotionEvent.ACTION_MOVE -> {
                        gesture.lastX = event.x
                        gesture.lastY = event.y
                        val slop = hypot(gesture.lastX - gesture.startX, gesture.lastY - gesture.startY)
                        if (!gesture.armed && slop > holdSlop) {
                            gesture.hold?.cancel()
                            gesture.hold = null
                        }
                        if (gesture.armed) {
                            draft = feedBox(gesture.startX, gesture.startY, gesture.lastX, gesture.lastY)
                        }
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        gesture.hold?.cancel()
                        gesture.hold = null
                        val kind =
                            LiveFeedFocusGesture.classify(
                                gesture.lastX - gesture.startX,
                                gesture.lastY - gesture.startY,
                                pinched = false,
                                armed = gesture.armed,
                                swipeFloor = swipeFloor,
                            )
                        when (kind) {
                            LiveFeedFocusGesture.Kind.DISP_CLEAN -> latestOnSwipe.value(true)
                            LiveFeedFocusGesture.Kind.DISP_LIVE -> latestOnSwipe.value(false)
                            LiveFeedFocusGesture.Kind.TAP ->
                                feedNorm(gesture.lastX, gesture.lastY)?.let { latestOnTap.value(it) }
                            LiveFeedFocusGesture.Kind.TRACK ->
                                latestOnTrack.value(
                                    feedBox(gesture.startX, gesture.startY, gesture.lastX, gesture.lastY),
                                )
                            null -> Unit
                        }
                        gesture.armed = false
                        draft = null
                    }
                }
                true
            },
    ) {
        val box = draft
        if (box != null) {
            Canvas(Modifier.fillMaxSize()) {
                val originX = if (feed == null) 0f else feedLeft
                val originY = if (feed == null) 0f else feedTop
                val w = if (feed == null) size.width else feedW
                val h = if (feed == null) size.height else feedH
                val rect =
                    androidx.compose.ui.geometry.Rect(
                        originX + (box.x * w).toFloat(),
                        originY + (box.y * h).toFloat(),
                        originX + ((box.x + box.width) * w).toFloat(),
                        originY + ((box.y + box.height) * h).toFloat(),
                    )
                drawRoundRect(
                    LiveDesign.text.copy(alpha = 0.88f),
                    topLeft = Offset(rect.left, rect.top),
                    size = Size(rect.width, rect.height),
                    cornerRadius = CornerRadius(8f, 8f),
                    style = Stroke(1.5.dp.toPx()),
                )
            }
        }
    }
}

private class FeedGestureState {
    var startX = 0f
    var startY = 0f
    var lastX = 0f
    var lastY = 0f
    var armed = false
    var hold: Job? = null
}

@Composable
private fun rememberFeedGestureState(): FeedGestureState = remember { FeedGestureState() }
