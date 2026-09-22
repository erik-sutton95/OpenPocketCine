package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.math.min
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GimbalLoopVerificationTest {
    private val a = GimbalWaypoint(172.1, -5.6, 1.0, -177.2)
    private val b = GimbalWaypoint(130.4, -4.6, 1.0, -177.2)
    private val program = GimbalProgram(a, b, durationAB = 3.5, loop = true)
    private val boundary = GimbalMoveEngine.HOLD_SECONDS + program.durationAB

    private data class Command(val at: Double, val from: GimbalWaypoint, val to: GimbalWaypoint, val duration: Double)
    private data class Result(val engine: GimbalMoveEngine, val commands: List<Command>, val stoppedAt: Double)

    private fun run(
        program: GimbalProgram = this.program,
        rampSeconds: Double = 0.12,
        feedbackDelay: Double = 0.06,
        reportEvery: Int = 10,
        reportOffset: Int = 6,
        lastReceipt: Double = Double.POSITIVE_INFINITY,
        transform: (Double, GimbalWaypoint) -> GimbalWaypoint = { _, pose -> pose },
    ): Result {
        val engine = GimbalMoveEngine()
        val origin = program.a!!
        val commands = mutableListOf(Command(0.0, origin, origin, 1.0))
        fun physical(time: Double): GimbalWaypoint {
            val command = commands.lastOrNull { it.at <= time } ?: commands.first()
            val elapsed = (time - command.at).coerceIn(0.0, command.duration)
            val ramp = min(rampSeconds, command.duration / 2)
            val speed = 1 / (command.duration - ramp)
            val fraction = when {
                elapsed < ramp -> speed * elapsed * elapsed / (2 * ramp)
                elapsed > command.duration - ramp -> {
                    val remaining = command.duration - elapsed
                    1 - speed * remaining * remaining / (2 * ramp)
                }
                else -> speed * (elapsed - ramp / 2)
            }
            return GimbalMoveEngine.lerp(command.from, command.to, fraction)
        }
        assertTrue(engine.start(program, origin))
        var reported = origin
        var receipt = 0.0
        var now = 0.0
        for (step in 1..1_300) {
            now = step / 100.0
            if (step % reportEvery == reportOffset && now <= lastReceipt + 1e-9) {
                reported = transform(now, physical(now - feedbackDelay))
                receipt = now
            }
            val output = engine.tick(0.01, reported, now - receipt)!!
            output.target?.let { target ->
                val actual = physical(now)
                assertTrue(GimbalMoveEngine.angularDistance(actual, commands.last().to) < 1e-8,
                    "The simulated camera reaches each commanded endpoint before reversing")
                commands += Command(now, actual, target, output.duration)
            }
            if (output.finished) break
        }
        return Result(engine, commands.drop(1), now)
    }

    @Test fun nativeEndpointEasingCanRepeatWithoutAConstantVelocityAssumption() {
        val cases = listOf(false to 0.12, true to 0.0, true to 0.12)
        for ((loop, ramp) in cases) {
            val result = run(program.copy(loop = loop), rampSeconds = ramp)
            assertNull(result.engine.failure, "loop=$loop ramp=$ramp")
            assertEquals(loop, result.engine.running)
            if (loop) {
                assertTrue(result.commands.size >= 4)
                result.commands.zipWithNext().forEach { (first, next) ->
                    assertEquals(program.durationAB, next.at - first.at, 1e-8)
                }
                assertEquals(listOf(b, a, b, a), result.commands.take(4).map { it.to })
            } else {
                assertEquals(1, result.commands.size)
            }
        }
    }

    @Test fun directArrivalUsesShortestNativePitchAcrossTheWrap() {
        val wrapped = program.copy(a = a.copy(nativePitchDeg = 175.0), b = b.copy(nativePitchDeg = -175.0))
        val result = run(wrapped)
        assertNull(result.engine.failure)
        assertTrue(result.engine.running)
        assertTrue(result.commands.size >= 4)
    }

    @Test fun nativeEasingDoesNotBypassAnExactIntermediateBCheckpoint() {
        val result = run(program.copy(c = b.copy(yawDeg = 90.0), durationBC = 3.5))
        assertEquals("Camera waypoint could not be verified", result.engine.failure)
        assertFalse(result.engine.running)
        assertEquals(2, result.commands.size)
        assertTrue(result.stoppedAt <= boundary + 0.411)
    }

    @Test fun observedContactDoesNotExcuseStallOffAxisOvershootOrWrongDirection() {
        val cases: Map<String, (Double, GimbalWaypoint) -> GimbalWaypoint> = mapOf(
            "stalled" to { time, pose -> if (time >= boundary) b else pose },
            "off axis" to { time, pose ->
                if (abs(time - (boundary - 0.04)) < 1e-8) pose.copy(nativePitchDeg = b.nativePitchDeg!! + 0.3) else pose
            },
            "overshoot" to { time, pose ->
                if (abs(time - (boundary - 0.04)) < 1e-8) b.copy(yawDeg = b.yawDeg - 0.35) else pose
            },
            "approach reversed" to { time, pose ->
                when {
                    abs(time - (boundary - 0.14)) < 1e-8 -> b.copy(yawDeg = b.yawDeg + 0.25)
                    abs(time - (boundary - 0.04)) < 1e-8 -> b.copy(yawDeg = b.yawDeg + 0.55)
                    else -> pose
                }
            },
            "approach retreat hidden by radial error" to { time, pose ->
                when {
                    abs(time - (boundary - 0.14)) < 1e-8 ->
                        b.copy(yawDeg = b.yawDeg + 0.30, nativePitchDeg = b.nativePitchDeg!! + 0.15)
                    abs(time - (boundary - 0.04)) < 1e-8 -> b.copy(yawDeg = b.yawDeg + 0.46)
                    else -> pose
                }
            },
            "departure reversed" to { time, pose ->
                if (abs(time - (boundary + 0.26)) < 1e-8) b.copy(yawDeg = b.yawDeg + 0.25) else pose
            },
        )
        for ((name, transform) in cases) {
            val result = run(transform = transform)
            assertEquals("Camera waypoint could not be verified", result.engine.failure, name)
            assertFalse(result.engine.running, name)
            assertEquals(2, result.commands.size, name)
            assertTrue(result.stoppedAt <= boundary + 0.411, name)
        }
    }

    @Test fun cumulativeWrongWayDriftCannotHideBehindPairwiseAngularTolerance() {
        for (approachDrift in listOf(true, false)) {
            val result = run(reportEvery = 2, reportOffset = 0) { time, pose ->
                val offset = kotlin.math.round((time - boundary) * 100).toInt()
                if (offset !in -30..30) return@run pose
                val distance = if (approachDrift) {
                    when (offset) {
                        -14 -> 0.3
                        -12 -> 0.4
                        -10 -> 0.5
                        -8 -> 0.6
                        else -> abs(offset - 6) * 0.05
                    }
                } else {
                    when (offset) {
                        8 -> 0.2
                        10 -> 0.4
                        12 -> 0.6
                        14 -> 0.8
                        16 -> 0.7
                        18 -> 0.6
                        20 -> 0.5
                        22 -> 0.4
                        else -> abs(offset - 6) * 0.05
                    }
                }
                b.copy(yawDeg = b.yawDeg + distance)
            }
            assertEquals("Camera waypoint could not be verified", result.engine.failure, "approach=$approachDrift")
            assertFalse(result.engine.running)
            assertTrue(result.stoppedAt <= boundary + 0.411)
        }
    }

    @Test fun lateEndpointOrRepeatedStaleReceiptCannotQualifyTurnaround() {
        val late = run(feedbackDelay = 0.26)
        assertEquals("Camera waypoint could not be verified", late.engine.failure)
        assertFalse(late.engine.running)
        assertTrue(late.stoppedAt <= boundary + 0.411)
        val stale = run(lastReceipt = boundary + 0.06)
        assertEquals("Move interrupted — timing or camera feedback lost", stale.engine.failure)
        assertFalse(stale.engine.running)
        assertTrue(stale.stoppedAt <= boundary + 0.411)
        assertEquals(2, stale.commands.size)
    }
}
