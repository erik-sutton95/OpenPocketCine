package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.GimbalProgram
import com.opencapture.openpocketcine.session.CameraCommands
import kotlin.math.round

/**
 * Sticky ownership until release. Editor and pill both drag on slop; a child
 * that already consumed the pointer (duration dial, slider) keeps it. Hold
 * without movement claims only the compact pill, so waypoint taps still fire.
 */
internal class MotionControlDragGesture(private val immediate: Boolean, private val slop: Float,
    private val holdMs: Long = 300) {
    enum class Ownership { TRACKING, DRAGGING, YIELDED }
    var ownership = Ownership.TRACKING
        private set

    fun update(elapsedMs: Long, distance: Float, childConsumed: Boolean = false): Ownership {
        if (ownership != Ownership.TRACKING) return ownership
        if (childConsumed) {
            ownership = Ownership.YIELDED
            return ownership
        }
        if (distance > slop) ownership = Ownership.DRAGGING
        else if (immediate && elapsedMs >= holdMs) ownership = Ownership.DRAGGING
        return ownership
    }
}

internal fun motionDurationAfterDrag(start: Double, translationDp: Float, floor: Double): Double =
    GimbalProgram.steppedDuration(start, -round(translationDp / 12f).toDouble() * 0.5, floor)

/** Match settled selfie rotation and MIRROR in display space; native coordinates stay unchanged. */
internal fun motionOverlayX(normalizedX: Double, poseInvertPan: Boolean, mirrored: Boolean): Double =
    if (CameraCommands.liveInvertPan(poseInvertPan, mirrored)) 1.0 - normalizedX else normalizedX
