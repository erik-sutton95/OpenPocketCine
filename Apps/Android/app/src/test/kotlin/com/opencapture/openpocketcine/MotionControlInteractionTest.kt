package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals

class MotionControlInteractionTest {
    @Test
    fun pillDragKeepsExclusiveOwnershipThroughReleaseEvenAfterReturningToStart() {
        val drag = MotionControlDragGesture(immediate = true, slop = 8f)
        assertEquals(MotionControlDragGesture.Ownership.TRACKING, drag.update(10, 2f))
        assertEquals(MotionControlDragGesture.Ownership.DRAGGING, drag.update(30, 12f))
        assertEquals(MotionControlDragGesture.Ownership.DRAGGING, drag.update(70, 0f))
        assertEquals(MotionControlDragGesture.Ownership.DRAGGING, drag.update(90, 0f)) // release
    }

    @Test
    fun intentionalTapPassesButLongHoldConsumesRelease() {
        assertEquals(MotionControlDragGesture.Ownership.TRACKING,
            MotionControlDragGesture(true, 8f).update(140, 2f))
        assertEquals(MotionControlDragGesture.Ownership.DRAGGING,
            MotionControlDragGesture(true, 8f).update(300, 0f))
    }

    @Test
    fun editorDirectDragStartsWithoutHoldLikeScopes() {
        val drag = MotionControlDragGesture(immediate = false, slop = 8f)
        assertEquals(MotionControlDragGesture.Ownership.TRACKING, drag.update(40, 2f))
        assertEquals(MotionControlDragGesture.Ownership.DRAGGING, drag.update(50, 12f))
        assertEquals(MotionControlDragGesture.Ownership.DRAGGING, drag.update(80, 30f))
    }

    @Test
    fun editorHoldWithoutMoveDoesNotClaimSoWaypointTapsFire() {
        val drag = MotionControlDragGesture(immediate = false, slop = 8f)
        assertEquals(MotionControlDragGesture.Ownership.TRACKING, drag.update(300, 0f))
        assertEquals(MotionControlDragGesture.Ownership.TRACKING, drag.update(450, 2f))
    }

    @Test
    fun editorYieldsWhenChildConsumesForDurationDialOrSlider() {
        val drag = MotionControlDragGesture(immediate = false, slop = 8f)
        assertEquals(MotionControlDragGesture.Ownership.YIELDED, drag.update(50, 12f, childConsumed = true))
        assertEquals(MotionControlDragGesture.Ownership.YIELDED, drag.update(500, 30f, childConsumed = true))
    }

    @Test
    fun yieldedOwnershipStaysEvenIfChildStopsConsuming() {
        val drag = MotionControlDragGesture(immediate = false, slop = 8f)
        drag.update(50, 12f, childConsumed = true)
        assertEquals(MotionControlDragGesture.Ownership.YIELDED, drag.update(80, 0f, childConsumed = false))
    }

    @Test
    fun rulerUsesHalfSecondStepsAndStopsAtBothBounds() {
        assertEquals(5.5, motionDurationAfterDrag(5.0, -12f, 0.5))
        assertEquals(4.5, motionDurationAfterDrag(5.0, 12f, 0.5))
        assertEquals(0.5, motionDurationAfterDrag(5.0, 1000f, 0.5))
        assertEquals(120.0, motionDurationAfterDrag(5.0, -4000f, 0.5))
    }

    @Test
    fun mirrorAssistReflectsBothMarkersAndPreviewCoordinates() {
        assertEquals(0.2, motionOverlayX(0.2, false), 1e-9)
        assertEquals(0.8, motionOverlayX(0.2, true), 1e-9)
        assertEquals(0.5, motionOverlayX(0.5, true), 1e-9)
    }
}
