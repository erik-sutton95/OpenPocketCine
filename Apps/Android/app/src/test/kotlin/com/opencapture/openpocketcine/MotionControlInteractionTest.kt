package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.GimbalMoveEngine
import com.opencapture.openpocketcine.session.GimbalProgram
import com.opencapture.openpocketcine.session.GimbalProgramCurve
import com.opencapture.openpocketcine.session.GimbalStickMapping
import com.opencapture.openpocketcine.session.GimbalWaypoint
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MotionControlInteractionTest {
    @Test
    fun defaultPortraitEditorLeavesTheProductionZoomChipVisible() {
        for (safeTop in listOf(0f, 44f, 59f)) {
            for ((width, height) in listOf(390f to 844f, 360f to 640f, 320f to 568f)) {
                val layout = LiveMonitorLayout.fieldMonitor(width, height, 0f, 0f, safeTop, 24f, showsBottomBars = true)
                val zoom = layout.gimbalCluster(true).zoom
                val top = maxOf(8f, safeTop)
                val bounds = ChromeRect(8f, top, width - 16f, height - top - 24f)
                val editor = motionEditorDefaultFrame(bounds, zoom, portrait = true)
                assertFalse(editor.intersects(zoom), "$width × $height must expose the actual zoom chip")
                assertTrue(editor.maxY <= zoom.minY - 8f)
                assertTrue(editor.minY >= maxOf(top, 44f), "Header must avoid system top-edge gestures")
                assertEquals(minOf(420f, zoom.minY - 8f - maxOf(top, 44f)), editor.height)
            }
        }
    }

    @Test
    fun defaultLandscapeOrMissingZoomPreservesCenteredPlacement() {
        val bounds = ChromeRect(8f, 8f, 828f, 374f)
        val zoom = ChromeRect(650f, 220f, 44f, 36f)
        assertEquals(ChromeRect(252f, 8f, 340f, 374f), motionEditorDefaultFrame(bounds, zoom, portrait = false))
        val portrait = ChromeRect(8f, 44f, 374f, 776f)
        assertEquals(ChromeRect(25f, 222f, 340f, 420f),
            motionEditorDefaultFrame(portrait, ChromeRect(0f, 0f, 0f, 0f), portrait = true))
    }

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
    fun selfieRotationAndMirrorReflectBothMarkersAndPreviewCoordinates() {
        for (selfieFlip in listOf(false, true)) {
            for (selfie in listOf(false, true)) {
                val mapping = GimbalStickMapping(commanded180 = selfie, selfieFlip = selfieFlip)
                for (mirror in listOf(false, true)) {
                    assertEquals(if (selfie != mirror) 0.8 else 0.2,
                        motionOverlayX(0.2, mapping.invertPan, mirror), 1e-9)
                    assertEquals(0.5, motionOverlayX(0.5, mapping.invertPan, mirror), 1e-9)
                }
            }
        }
    }

    @Test
    fun selfieMarkerMotionMatchesTheVisibleImageWithoutChangingSavedOrNativeCoordinates() {
        val a = GimbalWaypoint(175.0, 0.0, 1.0, 175.0)
        val b = GimbalWaypoint(180.0, 0.0, 1.0, 175.0)
        val c = GimbalWaypoint(185.0, 10.0, 1.0, 165.0)
        val program = GimbalProgram(a, b, c, 3.0, 2.0, 1.0, loop = true)
        val savedCommand = CameraCommands.gimbalTimedTarget(b, 3.0)!!
        val before = GimbalMoveEngine.project(b, a, 16.0 / 9.0)
        val after = GimbalMoveEngine.project(b, a.copy(yawDeg = 176.0), 16.0 / 9.0)
        assertTrue(before.first > 0.5)
        assertTrue(motionOverlayX(before.first, true, false) < 0.5)
        assertTrue(motionOverlayX(after.first, true, false) > motionOverlayX(before.first, true, false))
        assertEquals(before.first, motionOverlayX(before.first, true, true), 1e-9)
        val samples = GimbalProgramCurve.create(program)!!.samples()
        for (point in samples + listOf(a, b, c)) {
            val projection = GimbalMoveEngine.project(point, a, 16.0 / 9.0)
            assertEquals(1 - projection.first, motionOverlayX(projection.first, true, false), 1e-9)
            assertEquals(projection, GimbalMoveEngine.project(point, a, 16.0 / 9.0))
        }
        assertEquals(listOf(a, b, c), listOf(program.a, program.b, program.c))
        assertContentEquals(savedCommand, CameraCommands.gimbalTimedTarget(program.b!!, 3.0)!!)
    }

    @Test
    fun markerInversionUsesSettledRotationOrReconnectSeedRatherThanManualPanAngle() {
        fun attitude(yaw: Int) = byteArrayOf(0, 0, 0, 0, yaw.toByte(), (yaw shr 8).toByte())
        val front = GimbalStickMapping().applyAttitude(attitude(0))
            .applyAttitude(attitude(0)).applyAttitude(attitude(0))
        val manual = front.applyAttitude(attitude(1800))
        val rotating = front.noteRotate180().applyAttitude(attitude(1000))
        val settled = rotating.applyAttitude(attitude(1800))
        val reconnect = GimbalStickMapping().applyAttitude(attitude(1800))
        for (mapping in listOf(front, manual, rotating)) {
            assertFalse(mapping.invertPan)
            assertEquals(0.2, motionOverlayX(0.2, mapping.invertPan, false), 1e-9)
        }
        for (mapping in listOf(settled, reconnect)) {
            assertTrue(mapping.invertPan)
            assertEquals(0.8, motionOverlayX(0.2, mapping.invertPan, false), 1e-9)
        }
    }
}
