package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GimbalSafeRouteTest {
    private fun point(yaw: Double) = GimbalWaypoint(yaw, 0.2, 1.0, -180.0)

    @Test
    fun selfieRestartApproachesThroughVerifiedIntermediateTarget() {
        val live = point(225.0)
        val a = point(28.7)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a, point(62.8), live), live))
        val first = engine.tick(0.04, live)!!
        assertEquals(126.85, first.target!!.yawDeg, 1e-9)
        assertTrue(GimbalMoveEngine.canSendNativeTarget(live, first.target))
        assertTrue(first.duration >= 0.8)
        // Time passing alone must not advance to the next approach target.
        repeat((first.duration / 0.04).toInt()) { assertEquals(null, engine.tick(0.04, live)?.target) }
        val reached = engine.tick(0.04, first.target)
        assertTrue(GimbalMoveEngine.angularDistance(a, reached!!.target!!) < 1e-9)
    }

    @Test
    fun bothFullArcDirectionsCompleteApproachAndLongExactLegsWithoutUnsafeTargets() {
        for ((from, to) in listOf(-48.0 to 225.0, 225.0 to -48.0, 225.0 to 28.7, 28.7 to 225.0)) {
            val initial = point(from)
            val a = point(to)
            val b = point(from)
            val c = point(to)
            val engine = GimbalMoveEngine()
            assertTrue(engine.start(GimbalProgram(a, b, c, 3.0, 3.0), initial))
            var live = initial
            var motionFrom = initial
            var motionTo = initial
            var motionAt = 0.0
            var motionDuration = 1.0
            val commands = mutableListOf<Triple<Double, GimbalWaypoint, Double>>()
            val takeCommands = mutableListOf<Triple<Double, GimbalWaypoint, Double>>()
            for (step in 1..1600) {
                val now = step * 0.01
                live = GimbalMoveEngine.lerp(motionFrom, motionTo, (now - motionAt) / motionDuration)
                val out = engine.tick(0.01, live) ?: break
                out.target?.let { target ->
                    assertTrue(abs(target.yawDeg - live.yawDeg) < 180,
                        "unsafe $from->$to command ${live.yawDeg}->${target.yawDeg}")
                    assertEquals(target, target.clamped())
                    commands += Triple(now, target, out.duration)
                    if (engine.readout(live)?.phase == "RUN") takeCommands += Triple(now, target, out.duration)
                    motionFrom = live
                    motionTo = target
                    motionAt = now
                    motionDuration = out.duration
                }
                if (out.finished) break
            }
            assertFalse(engine.running)
            assertEquals(null, engine.failure, "$from->$to")
            assertEquals("DONE", engine.readout(live)?.phase)
            assertEquals(c, commands.last().second)
            val partsPerLeg = kotlin.math.ceil(abs(to - from) / 120).toInt()
            assertEquals(2 * partsPerLeg, takeCommands.size)
            assertEquals(6.0, takeCommands.sumOf { it.third }, 1e-8)
            assertEquals(6.0, takeCommands.last().first + takeCommands.last().third - takeCommands.first().first, 1e-8)
        }
    }

    @Test
    fun routedLongLegCannotSkipSubBoundaryOrContinueWhenLiveLeavesSafeArc() {
        val a = point(-48.0)
        val b = point(225.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a, b, durationAB = 0.5), a))
        for (step in 1..219) {
            val live = GimbalMoveEngine.lerp(a, b, (step * 0.01 - 2.0) / 0.5)
            engine.tick(0.01, live)
        } // Second native part due at elapsed0.2 remains unsent.
        val late = engine.tick(0.11, GimbalMoveEngine.lerp(a, b, 0.6))
        assertEquals(true, late?.stop)
        assertEquals(null, late?.target)
        assertFalse(GimbalMoveEngine.canSendNativeTarget(point(260.0), b))
        assertFalse(GimbalMoveEngine.canSendNativeTarget(point(225.0), point(45.0)))
    }
    @Test
    fun routedPartDurationsSplitIntegerTenthsWithoutChangingVelocity() {
        val a = point(-48.0)
        val b = point(225.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a, b, durationAB = 0.5), a))
        val sends = mutableListOf<Pair<GimbalWaypoint, Double>>()
        for (step in 1..260) {
            val live = GimbalMoveEngine.lerp(a, b, (step * 0.01 - 2) / 0.5)
            engine.tick(0.01, live)?.let { out -> out.target?.let { sends += it to out.duration } }
        }
        assertEquals(3, sends.size)
        listOf(0.2, 0.2, 0.1).zip(sends).forEach { (seconds, send) ->
            assertEquals(seconds, send.second)
            val packet = CameraCommands.gimbalTimedTarget(send.first, send.second)
            assertTrue(packet != null, "each routed part must satisfy native packet duration bounds")
            assertEquals((seconds * 10).toInt(), packet[7].toInt() and 0xff)
        }
        listOf(0.4, 0.8, 1.0).zip(sends).forEach { (fraction, send) ->
            assertEquals(GimbalMoveEngine.lerp(a, b, fraction).yawDeg, send.first.yawDeg, 1e-9)
        }
    }

    @Test
    fun safetyGuardChecksYawAfterNativeTenthDegreeQuantization() {
        assertFalse(GimbalMoveEngine.canSendNativeTarget(point(0.0), point(179.96)))
        assertTrue(GimbalMoveEngine.canSendNativeTarget(point(0.0), point(179.94)))
    }
}
