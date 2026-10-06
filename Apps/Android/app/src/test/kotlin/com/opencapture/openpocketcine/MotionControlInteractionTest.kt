package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.motionOverlayX
import com.opencapture.opencine.dji.applyAttitude
import com.opencapture.opencine.dji.gimbalTimedTarget
import com.opencapture.opencine.dji.project
import com.opencapture.opencine.motion.GimbalProgram
import com.opencapture.opencine.motion.GimbalProgramCurve
import com.opencapture.opencine.motion.GimbalWaypoint
import com.opencapture.opencine.motion.GimbalWaypointOverlay
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.GimbalStickMapping
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MotionControlInteractionTest {
    @Test
    fun selfieMarkerMotionMatchesTheVisibleImageWithoutChangingSavedOrNativeCoordinates() {
        val a = GimbalWaypoint(175.0, 0.0, 1.0, 175.0)
        val b = GimbalWaypoint(180.0, 0.0, 1.0, 175.0)
        val c = GimbalWaypoint(185.0, 10.0, 1.0, 165.0)
        val program = GimbalProgram(a, b, c, 3.0, 2.0, 1.0, loop = true)
        val savedCommand = CameraCommands.gimbalTimedTarget(b, 3.0)!!
        val before = GimbalWaypointOverlay.project(b, a, 16.0 / 9.0)
        val after = GimbalWaypointOverlay.project(b, a.copy(yawDeg = 176.0), 16.0 / 9.0)
        assertTrue(before.first > 0.5)
        assertTrue(motionOverlayX(before.first, true, false) < 0.5)
        assertTrue(motionOverlayX(after.first, true, false) > motionOverlayX(before.first, true, false))
        assertEquals(before.first, motionOverlayX(before.first, true, true), 1e-9)
        val samples = GimbalProgramCurve.create(program)!!.samples()
        for (point in samples + listOf(a, b, c)) {
            val projection = GimbalWaypointOverlay.project(point, a, 16.0 / 9.0)
            assertEquals(1 - projection.first, motionOverlayX(projection.first, true, false), 1e-9)
            assertEquals(projection, GimbalWaypointOverlay.project(point, a, 16.0 / 9.0))
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
