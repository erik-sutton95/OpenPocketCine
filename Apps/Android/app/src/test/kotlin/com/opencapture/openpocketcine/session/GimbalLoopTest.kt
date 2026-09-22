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

    private class Camera(private val program: GimbalProgram) {
        data class Command(val at: Double, val from: GimbalWaypoint, val target: GimbalWaypoint,
            val duration: Double, val phase: String, val label: String)
        val engine = GimbalMoveEngine()
        var now = 0.0
        var live = program.a!!
        private var origin = live
        private var target = live
        private var motionAt = 0.0
        private var duration = 1.0
        val commands = mutableListOf<Command>()
        val starts = mutableListOf<Double>()
        var repeatedPreparation = false
        var lastOutput: GimbalMoveEngine.Output? = null

        init { assertTrue(engine.start(program, live)) }

        fun step(transform: (GimbalWaypoint) -> GimbalWaypoint = { it }) {
            now += 0.01
            live = transform(GimbalMoveEngine.lerp(origin, target, (now - motionAt) / duration))
            val before = engine.readout(live)
            lastOutput = engine.tick(0.01, live)
            val readout = engine.readout(live)
            val phase = readout?.phase
            val turned = (before?.label == "B→C" && readout?.label == "C→B") ||
                (before?.label == "B→A" && readout?.label == "A→B") ||
                (program.c == null && before?.label == "A→B" && readout?.label == "B→A")
            if (phase == "RUN" && (before?.phase == "HOLD" || turned)) starts += now
            if (starts.isNotEmpty() && (phase == "HOLD" || phase == "APPROACH")) repeatedPreparation = true
            lastOutput?.target?.let {
                commands += Command(now, live, it, lastOutput!!.duration, phase!!, engine.readout(live)!!.label)
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

    @Test fun exactProgramsAlternateWaypointsAndUnequalLegDurationsWithoutAnotherHold() {
        for (program in listOf(program(), program(includeC = true))) {
            val camera = Camera(program)
            camera.until { camera.starts.size == 5 }
            for (pass in 0..3) {
                val reversed = pass % 2 == 1
                val commands = camera.takeCommands(pass)
                val targets = if (reversed) listOfNotNull(program.b.takeIf { program.c != null }, program.a)
                    else listOfNotNull(program.b, program.c)
                val durations = if (program.c == null) listOf(program.durationAB)
                    else if (reversed) listOf(program.durationBC, program.durationAB)
                    else listOf(program.durationAB, program.durationBC)
                val labels = if (reversed) listOfNotNull("C→B".takeIf { program.c != null }, "B→A")
                    else listOfNotNull("A→B", "B→C".takeIf { program.c != null })
                assertEquals(targets, commands.map { it.target })
                assertEquals(durations, commands.map { it.duration })
                assertEquals(labels, commands.map { it.label })
                assertEquals(durations.sum(), camera.starts[pass + 1] - camera.starts[pass], 1e-8)
            }
            assertFalse(camera.repeatedPreparation)
            assertTrue(camera.commands.none { it.phase == "APPROACH" })
            assertTrue(camera.engine.running)
            assertFalse(camera.lastOutput!!.finished)
            assertNull(camera.engine.failure)
        }
    }

    @Test fun smoothPassesFollowTheSameCurveBackwardsWithOriginalWaypointLabels() {
        val program = program(1.0, includeC = true)
        val curve = GimbalProgramCurve.create(program)!!
        val camera = Camera(program)
        camera.until { camera.starts.size == 5 }
        for (pass in 0..3) {
            val commands = camera.takeCommands(pass)
            val reversed = pass % 2 == 1
            assertEquals(99, commands.size)
            assertEquals(if (reversed) "C→B" else "A→B", commands.first().label)
            assertEquals(if (reversed) "B→A" else "B→C", commands.last().label)
            assertEquals(if (reversed) program.a else program.c, commands.last().target)
            commands.forEach { command ->
                val elapsed = (command.at - commands.first().at + 0.1).coerceIn(0.0, curve.duration)
                val expected = curve.position(if (reversed) curve.duration - elapsed else elapsed)
                assertTrue(GimbalMoveEngine.angularDistance(expected, command.target) < 1e-8)
                assertEquals(0.1, command.duration)
            }
            commands.zipWithNext().forEach { (first, second) -> assertEquals(0.05, second.at - first.at, 1e-8) }
            assertEquals(5.0, camera.starts[pass + 1] - camera.starts[pass], 1e-8)
        }
        assertFalse(camera.repeatedPreparation)
        assertNull(camera.engine.failure)
    }

    @Test fun wideArcUsesTimedSafeSubdivisionsInBothDirectionsWithoutResetTravel() {
        val program = GimbalProgram(point(-40.0), point(220.0), durationAB = 3.0, loop = true)
        val camera = Camera(program)
        camera.until { camera.starts.size == 5 }
        for (pass in 0..3) {
            val commands = camera.takeCommands(pass)
            assertEquals(3, commands.size)
            assertEquals(3.0, commands.sumOf { it.duration })
            assertEquals(if (pass % 2 == 0) program.b else program.a, commands.last().target)
            commands.forEach {
                assertTrue(abs(it.target.yawDeg - it.from.yawDeg) <= 120.0)
                assertTrue(if (pass % 2 == 0) it.target.yawDeg > it.from.yawDeg else it.target.yawDeg < it.from.yawDeg)
                assertEquals(if (pass % 2 == 0) "A→B" else "B→A", it.label)
            }
        }
        assertFalse(camera.repeatedPreparation)
        assertNull(camera.engine.failure)
    }

    @Test fun missedArrivalStopsDuringReturnWithinTheVerificationDeadline() {
        val camera = Camera(program())
        camera.until { camera.starts.size == 1 && camera.now >= camera.starts[0] + 2.99 - 1e-8 }
        val boundary = camera.starts[0] + 3.0
        while (camera.engine.running && camera.now < boundary + 1) {
            camera.step { it.copy(yawDeg = it.yawDeg - 0.4) }
        }
        assertFalse(camera.engine.running)
        assertEquals("Camera waypoint could not be verified", camera.engine.failure)
        assertTrue(camera.now <= boundary + 0.411)
        assertEquals(2, camera.commands.size, "The timed reverse starts immediately, then failed feedback stops it")
        assertNull(camera.engine.tick(0.01, camera.live))
    }

    @Test fun oneShotMissedFinalPositionAfterEarlierSettledReportsStillFails() {
        val camera = Camera(program().copy(loop = false))
        camera.until { camera.engine.readout(camera.live)?.phase == "VERIFY" }
        repeat(20) { camera.step() }
        repeat(15) { camera.step { it.copy(yawDeg = it.yawDeg - 0.4) } }
        assertFalse(camera.engine.running)
        assertEquals("Camera missed its final position", camera.engine.failure)
        assertEquals(1, camera.commands.size)
    }

    @Test fun cancelBeforeOrAfterTurnaroundPreventsAnyFurtherCommand() {
        for (afterTurnaround in listOf(false, true)) {
            val camera = Camera(program())
            camera.until { camera.starts.size == 1 && camera.now >= camera.starts[0] + 2.99 - 1e-8 }
            if (afterTurnaround) camera.until { camera.starts.size == 2 }
            val commandsAtCancel = camera.commands.size
            camera.engine.cancel()
            repeat(100) { camera.step() }
            assertNull(camera.lastOutput)
            assertFalse(camera.engine.running)
            assertEquals(commandsAtCancel, camera.commands.size)
        }
    }

    @Test fun shortSmoothLoopsAcceptSparseFeedbackWithFractionalDelayWithoutEndpointHolds() {
        for (legDuration in listOf(0.5, 1.0)) {
            val program = program(1.0, includeC = true).copy(durationAB = legDuration, durationBC = legDuration)
            val engine = GimbalMoveEngine()
            val origin = program.a!!
            data class Segment(val at: Double, val from: GimbalWaypoint, val to: GimbalWaypoint, val duration: Double)
            val segments = mutableListOf(Segment(0.0, origin, origin, 1.0))
            fun physical(time: Double): GimbalWaypoint {
                val segment = segments.lastOrNull { it.at <= time } ?: segments.first()
                return GimbalMoveEngine.lerp(segment.from, segment.to, (time - segment.at) / segment.duration)
            }
            assertTrue(engine.start(program, origin))
            var reported = origin
            var receipt = 0.0
            val turns = mutableListOf<Double>()
            for (step in 1..1_200) {
                val now = step * 0.01
                if (step % 10 == 7) {
                    reported = physical(now - 0.137)
                    receipt = now
                }
                val before = engine.readout(reported)?.label
                val out = engine.tick(0.01, reported, now - receipt)!!
                val after = engine.readout(reported)!!
                if ((before == "B→C" && after.label == "C→B") ||
                    (before == "B→A" && after.label == "A→B")) turns += now
                out.target?.let { segments += Segment(now, physical(now), it, out.duration) }
                assertFalse(out.stop || out.finished, "duration=$legDuration now=$now failure=${engine.failure}")
                if (now >= 2.0) assertEquals("RUN", after.phase)
            }
            assertTrue(turns.size >= 4)
            turns.zipWithNext().forEach { (first, next) -> assertEquals(legDuration * 2, next - first, 1e-8) }
            assertNull(engine.failure)
        }
    }

    @Test fun pauseOnReverseKeepsDirectionAndDoesNotShortenOrFlattenLaterPasses() {
        for (program in listOf(program(includeC = true), program(1.0, includeC = true))) {
            val reference = Camera(program)
            reference.until { reference.starts.size == 3 }
            val camera = Camera(program)
            camera.until { camera.starts.size == 2 && camera.now >= camera.starts[1] + 1.23 }
            val commandsBeforePause = camera.commands.size
            camera.pauseAndResume(camera.live)
            camera.step()
            assertEquals("C→B", camera.commands[commandsBeforePause].label)
            camera.until { camera.starts.size == 5 }
            assertEquals(program.a, camera.takeCommands(1).last().target)
            for (pass in 2..3) {
                val original = reference.takeCommands(pass - 2)
                val repeated = camera.takeCommands(pass)
                assertEquals(original.map { it.target }, repeated.map { it.target })
                assertEquals(original.map { it.duration }, repeated.map { it.duration })
                assertEquals(original.map { it.label }, repeated.map { it.label })
            }
            assertFalse(camera.repeatedPreparation)
            assertNull(camera.engine.failure)
            assertTrue(camera.engine.running)
        }
    }
}
