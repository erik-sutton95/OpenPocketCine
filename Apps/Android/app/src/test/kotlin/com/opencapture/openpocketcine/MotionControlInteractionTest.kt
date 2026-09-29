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
    fun heightLimitedEditorNeverCrashesOnFractionalOrTinyBounds() {
        // Sentry OPENPOCKETCINE-ANDROID-6/7/8: (maxY - minY) rounds so maxY - height lands an ULP
        // below minY, and coerceIn threw on the empty range.
        val rounding = ChromeRect(8f, 81.297005f, 700f, 419.5853f)
        assertEquals(81.297005f, motionEditorDefaultFrame(rounding, ChromeRect(0f, 0f, 0f, 0f), portrait = false).minY)
        // Portrait bounds ending above the 44 dp gesture reserve must not yield a negative height.
        val tiny = motionEditorDefaultFrame(ChromeRect(8f, 8f, 300f, 20f), ChromeRect(0f, 0f, 0f, 0f), portrait = true)
        assertTrue(tiny.height >= 0f)
    }

    /** One pointer sample; a null [expected] feeds the gesture without asserting. */
    private data class DragStep(
        val elapsedMs: Long,
        val distance: Float,
        val expected: MotionControlDragGesture.Ownership?,
        val childConsumed: Boolean = false,
    )

    @Test
    fun dragOwnershipFollowsImmediacyHoldSlopAndChildConsumption() {
        val tracking = MotionControlDragGesture.Ownership.TRACKING
        val dragging = MotionControlDragGesture.Ownership.DRAGGING
        val yielded = MotionControlDragGesture.Ownership.YIELDED
        // why to (immediate, pointer samples); each case starts a fresh gesture with 8 dp slop.
        val cases = listOf(
            "pill drag keeps exclusive ownership through release even after returning to start" to (true to listOf(
                DragStep(10, 2f, tracking),
                DragStep(30, 12f, dragging),
                DragStep(70, 0f, dragging),
                DragStep(90, 0f, dragging), // release
            )),
            "intentional pill tap passes" to (true to listOf(DragStep(140, 2f, tracking))),
            "long pill hold consumes release" to (true to listOf(DragStep(300, 0f, dragging))),
            "editor direct drag starts without hold like scopes" to (false to listOf(
                DragStep(40, 2f, tracking),
                DragStep(50, 12f, dragging),
                DragStep(80, 30f, dragging),
            )),
            "editor hold without move does not claim so waypoint taps fire" to (false to listOf(
                DragStep(300, 0f, tracking),
                DragStep(450, 2f, tracking),
            )),
            "editor yields when child consumes for duration dial or slider" to (false to listOf(
                DragStep(50, 12f, yielded, childConsumed = true),
                DragStep(500, 30f, yielded, childConsumed = true),
            )),
            "yielded ownership stays even if child stops consuming" to (false to listOf(
                DragStep(50, 12f, null, childConsumed = true),
                DragStep(80, 0f, yielded),
            )),
        )
        for ((why, case) in cases) {
            val (immediate, steps) = case
            val drag = MotionControlDragGesture(immediate = immediate, slop = 8f)
            for (step in steps) {
                val ownership = drag.update(step.elapsedMs, step.distance, childConsumed = step.childConsumed)
                if (step.expected != null) assertEquals(step.expected, ownership, "$why at ${step.elapsedMs} ms")
            }
        }
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
        fun attitude(yaw: Int) = byteArrayOf(0, 0, 0, 0, yaw.toByte(), (yaw shr 8).toByte()) + ByteArray(44)
        val front = GimbalStickMapping().applyAttitude(attitude(0))
            .applyAttitude(attitude(0)).applyAttitude(attitude(0))
        val manual = front.applyAttitude(attitude(1800))
        val rotating = front.noteRotate180().applyAttitude(attitude(1000))
        val settled = rotating.applyAttitude(attitude(1800))
        val reconnect = GimbalStickMapping().applyAttitude(attitude(1800))
        val stickFirst = GimbalStickMapping().applyAttitude(attitude(300)).noteAppMotion()
            .applyAttitude(attitude(944))
        for (mapping in listOf(front, manual, rotating, stickFirst)) {
            assertFalse(mapping.invertPan)
            assertEquals(0.2, motionOverlayX(0.2, mapping.invertPan, false), 1e-9)
        }
        for (mapping in listOf(settled, reconnect)) {
            assertTrue(mapping.invertPan)
            assertEquals(0.8, motionOverlayX(0.2, mapping.invertPan, false), 1e-9)
        }
    }
}
