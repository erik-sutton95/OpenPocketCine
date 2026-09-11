package com.opencapture.openpocketcine.session

import kotlin.test.*

class GimbalPauseTest {
    private fun point(yaw: Double, pitch: Double = 0.0) = GimbalWaypoint(yaw, pitch, 1.0, -pitch)
    private fun ready(program: GimbalProgram) = GimbalMoveEngine().also {
        assertTrue(it.start(program, program.a!!))
        repeat(200) { _ -> it.tick(0.01, program.a!!) }
    }

    @Test fun frozenTimeCoastAndFutureLegs() {
        val a = point(0.0); val b = point(40.0); val c = point(50.0)
        val engine = ready(GimbalProgram(a, b, c, 4.0, 2.0))
        repeat(123) { engine.tick(0.01, point((it + 1) / 10.0)) }
        assertTrue(engine.pause(point(12.3)))
        val elapsed = engine.readout(a)!!.elapsed
        assertTrue(engine.running && engine.isPaused)
        assertNull(engine.tick(100.0, a, 100.0))
        assertEquals(elapsed, engine.readout(a)!!.elapsed)
        assertTrue(engine.resume(point(15.0)))
        val command = engine.tick(0.01, point(15.0))!!
        assertEquals(b, command.target)
        assertEquals(2.8, command.duration, 1e-9)
        assertEquals(0.0, engine.readout(a)!!.elapsed)
        repeat(280) { engine.tick(0.01, point(15 + 25.0 * (it + 1) / 280)) }
        assertEquals("B→C", engine.readout(b)!!.label)
        assertEquals(2.0, engine.readout(b)!!.setDuration)
        assertTrue(engine.pause(b))
        assertTrue(engine.verificationInterruptedByPause)
        engine.cancel()
        assertFalse(engine.resume(b))
        assertFalse(engine.isPaused)
    }

    @Test fun curveCutsPreserveFutureGeometryAndRepeatedCoast() {
        val program = GimbalProgram(point(0.0), point(30.0), point(30.0, 20.0), 3.0, 2.0, 1.0)
        val original = GimbalProgramCurve.create(program)!!
        for (cut in listOf(1.0, 2.5, 4.5)) {
            val actual = point(12.0, 3.0)
            val rest = original.remaining(cut, actual)
            assertEquals(actual, rest.position(0.0))
            assertEquals(5 - cut, rest.duration, 1e-9)
            assertEquals(program.c, rest.position(rest.duration))
            assertTrue(rest.samples().all { it == it.clamped() })
            if (cut < 4) assertEquals(original.position(4.0), rest.position(4 - cut))
            val again = rest.remaining(0.1, point(13.0, 3.0))
            assertEquals(rest.duration - 0.1, again.duration, 1e-9)
            assertEquals(program.c, again.position(again.duration))
        }
        val cut = original.remaining(2.5, original.position(2.5))
        assertTrue(GimbalMoveEngine.angularDistance(cut.position(0.4), original.position(2.9)) < 1e-9)
    }

    @Test fun fractionalCurveResumeCompletes() {
        val engine = ready(GimbalProgram(point(0.0), point(30.0), point(30.0, 20.0), 3.0, 2.0, 1.0))
        repeat(253) { engine.tick(0.01, point(20.0)) }
        assertTrue(engine.pause(point(20.0)))
        assertTrue(engine.resume(point(22.0, 2.0)))
        var live = point(22.0, 2.0)
        val first = engine.tick(0.01, live)!!
        assertEquals(0.0, engine.readout(live)!!.elapsed)
        var from = live; var target = first.target!!; var since = 0.0
        repeat(300) {
            since += 0.01
            live = GimbalMoveEngine.lerp(from, target, since / 0.1)
            val output = engine.tick(0.01, live)
            output?.target?.let { from = live; target = it; since = 0.0 }
        }
        assertNull(engine.failure)
        assertFalse(engine.running)
    }

    @Test fun stabilityNeedsDistinctFreshPostStopSamplesAndFixedAnchor() {
        val stable = NativePauseStability()
        stable.reset(1.0)
        stable.observe(NativeGimbalFeedback(point(0.0), 1.0))
        assertNull(stable.ready(1.0))
        stable.observe(NativeGimbalFeedback(point(0.0), 1.1))
        stable.observe(NativeGimbalFeedback(point(0.06), 1.2))
        stable.observe(NativeGimbalFeedback(point(0.12), 1.3))
        assertNull(stable.ready(1.3))
        stable.observe(NativeGimbalFeedback(point(0.12), 1.4))
        stable.observe(NativeGimbalFeedback(point(0.12), 1.5))
        assertNotNull(stable.ready(1.5))
        assertNull(stable.ready(1.81))
        stable.reset(2.0)
        assertNull(stable.ready(2.0))
    }
}
