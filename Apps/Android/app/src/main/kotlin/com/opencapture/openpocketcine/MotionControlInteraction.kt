package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.GimbalProgram
import kotlin.math.round

/** Gesture ownership is sticky until release, even when a drag returns to its origin. */
internal class MotionControlDragGesture(private val immediate: Boolean, private val slop: Float,
    private val holdMs: Long = 300) {
    enum class Ownership { TRACKING, DRAGGING, YIELDED }
    var ownership = Ownership.TRACKING
        private set

    fun update(elapsedMs: Long, distance: Float): Ownership {
        if (ownership != Ownership.TRACKING) return ownership
        if (distance > slop) ownership = if (immediate) Ownership.DRAGGING else Ownership.YIELDED
        else if (elapsedMs >= holdMs) ownership = Ownership.DRAGGING
        return ownership
    }
}

internal fun motionDurationAfterDrag(start: Double, translationDp: Float, floor: Double): Double =
    GimbalProgram.steppedDuration(start, -round(translationDp / 12f).toDouble() * 0.5, floor)

/** MIRROR assist changes display only; native body coordinates and capture stay unchanged. */
internal fun motionOverlayX(normalizedX: Double, mirrored: Boolean): Double =
    if (mirrored) 1.0 - normalizedX else normalizedX
