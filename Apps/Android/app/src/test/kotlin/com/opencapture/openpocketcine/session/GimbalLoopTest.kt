package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GimbalLoopTest {
    private fun point(yaw: Double, pitch: Double = 0.0) = GimbalWaypoint(yaw, pitch, 1.0, -pitch)
    private fun program(smoothness: Double = 0.0, includeC: Boolean = false) = GimbalProgram(
        a = point(0.0), b = point(30.0), c = if (includeC) point(30.0, 20.0) else null,
        durationAB = 3.0, durationBC = 2.0, smoothness = smoothness, loop = true,
    )

    private class Camera(program: GimbalProgram) {
        data class Command(val at: Double, val target: GimbalWaypoint, val duration: Double, val phase: String)
        val engine = GimbalMoveEngine()
        var now = 0.0
        var live = program.a!!
        private var origin = live
        private var target = live
        private var motionAt = 0.0
        private var duration = 1.0
        val commands = mutableListOf<Command>()
        val starts = mutableListOf<Double>()
        var lastOutput: GimbalMoveEngine.Output? = null

        init { assertTrue(engine.start(program, live)) }

        fun step(transform: (GimbalWaypoint) -> GimbalWaypoint = { it }) {
            now += 0.01
            live = transform(GimbalMoveEngine.lerp(origin, target, (now - motionAt) / duration))
            val before = engine.readout(live)?.phase
            lastOutput = engine.tick(0.01, live)
            val phase = engine.readout(live)?.phase
            if (before == "HOLD" && phase == "RUN") starts += now
            lastOutput?.target?.let {
                commands += Command(now, it, lastOutput!!.duration, phase!!)
                origin = live
                target = it
                motionAt = now
                duration = lastOutput!!.duration
            }
        }

        fun until(predicate: () -> Boolean) {
            repeat(10_000) {
                if (predicate()) return
                assertTrue(engine.running, engine.failure ?: "Program finished unexpectedly")
                step()
            }
            error("Program did not reach expected state")
        }

        fun pauseAndResume(pose: GimbalWaypoint) {
            assertTrue(engine.pause(live))
            assertNull(engine.tick(100.0, live, 100.0))
            live = pose
            origin = pose
            target = pose
            motionAt = now
            assertTrue(engine.resume(live))
        }

        fun takeCommands(cycle: Int): List<Command> = commands.filter {
            it.phase == "RUN" && it.at >= starts[cycle] && it.at < starts[cycle + 1]
        }
    }

    @Test fun loopDefaultsOffAndOneShotStillFinishes() {
        assertFalse(GimbalProgram().loop)
        val camera = Camera(program().copy(loop = false))
        repeat(600) { camera.step() }
        assertFalse(camera.engine.running)
        assertNull(camera.engine.failure)
        assertEquals("DONE", camera.engine.readout(camera.live)?.phase)
        assertEquals(1, camera.starts.size)
    }

    @Test fun exactAndSmoothProgramsRepeatFullTimingAndGeometryForThreeCycles() {
        for (program in listOf(program(), program(includeC = true), program(1.0, includeC = true))) {
            val camera = Camera(program)
            camera.until { camera.starts.size == 4 }
            val first = camera.takeCommands(0)
            assertEquals(program.c ?: program.b, first.last().target)
            for (cycle in 1..2) {
                val repeated = camera.takeCommands(cycle)
                assertEquals(first.map { it.target }, repeated.map { it.target })
                assertEquals(first.map { it.duration }, repeated.map { it.duration })
                first.zip(repeated).forEach { (original, next) ->
                    assertEquals(original.at - first.first().at, next.at - repeated.first().at, 1e-8)
                }
            }
            val returns = camera.commands.filter { it.phase == "APPROACH" }
            assertEquals(3, returns.size)
            assertTrue(returns.all { GimbalMoveEngine.angularDistance(it.target, program.a!!) < 1e-8 })
            assertTrue(camera.engine.running)
            assertFalse(camera.lastOutput!!.finished)
            assertNull(camera.engine.failure)
        }
    }

    @Test fun returnUsesMeasuredFinalPoseAndSafeSubdivisionsBeforeTwoSecondHold() {
        val program = GimbalProgram(point(-40.0), point(220.0), durationAB = 3.0, loop = true)
        val camera = Camera(program)
        camera.until { camera.engine.readout(camera.live)?.phase == "VERIFY" }
        while (camera.engine.readout(camera.live)?.phase == "VERIFY") {
            camera.step { it.copy(yawDeg = 219.9) }
        }
        assertEquals("APPROACH", camera.engine.readout(camera.live)?.phase)
        assertNull(camera.lastOutput?.target, "Verification cannot dispatch the return in the same tick")
        assertFalse(camera.lastOutput!!.finished)
        camera.until { camera.starts.size == 2 }
        val returns = camera.commands.filter { it.phase == "APPROACH" }
        assertEquals(3, returns.size)
        var previous = 219.9
        returns.forEach {
            assertTrue(abs(it.target.yawDeg - previous) <= 120.0)
            previous = it.target.yawDeg
        }
        assertEquals(219.9 + (-40.0 - 219.9) / 3, returns.first().target.yawDeg, 1e-8)
        assertTrue(GimbalMoveEngine.angularDistance(program.a!!, returns.last().target) < 1e-8)
        assertEquals(2.0, camera.starts[1] - returns.last().at - returns.last().duration, 0.011)
    }

    @Test fun failedVerificationNeverReturnsToA() {
        val camera = Camera(program())
        camera.until { camera.engine.readout(camera.live)?.phase == "VERIFY" }
        repeat(60) { camera.step { it.copy(yawDeg = it.yawDeg - 0.4) } }
        assertFalse(camera.engine.running)
        assertEquals("Camera waypoint could not be verified", camera.engine.failure)
        assertEquals(1, camera.commands.size)
        assertNull(camera.engine.tick(0.01, camera.live))
    }

    @Test fun missedFinalPositionAfterEarlierSettledReportsDoesNotLoop() {
        val camera = Camera(program())
        camera.until { camera.engine.readout(camera.live)?.phase == "VERIFY" }
        repeat(20) { camera.step() }
        repeat(15) { camera.step { it.copy(yawDeg = it.yawDeg - 0.4) } }
        assertFalse(camera.engine.running)
        assertEquals("Camera missed its final position", camera.engine.failure)
        assertEquals(1, camera.commands.size)
    }

    @Test fun cancelAtCycleBoundaryPreventsAnyReturnCommand() {
        for (afterVerification in listOf(false, true)) {
            val camera = Camera(program())
            camera.until { camera.engine.readout(camera.live)?.phase == "VERIFY" }
            if (afterVerification) camera.until { camera.engine.readout(camera.live)?.phase == "APPROACH" }
            camera.engine.cancel()
            repeat(100) { camera.step() }
            assertNull(camera.lastOutput)
            assertFalse(camera.engine.running)
            assertEquals(1, camera.commands.size)
        }
    }

    @Test fun pauseResumeDoesNotShortenOrFlattenTheNextCycle() {
        for (program in listOf(program(includeC = true), program(1.0, includeC = true))) {
            val reference = Camera(program)
            reference.until { reference.starts.size == 2 }
            val camera = Camera(program)
            camera.until { camera.starts.size == 1 && camera.now >= camera.starts[0] + 1.23 }
            camera.pauseAndResume(point(15.0))
            camera.until { camera.starts.size == 3 }
            assertEquals(reference.takeCommands(0).map { it.target }, camera.takeCommands(1).map { it.target })
            assertEquals(reference.takeCommands(0).map { it.duration }, camera.takeCommands(1).map { it.duration })
            assertNull(camera.engine.failure)
            assertTrue(camera.engine.running)
        }
    }
}
