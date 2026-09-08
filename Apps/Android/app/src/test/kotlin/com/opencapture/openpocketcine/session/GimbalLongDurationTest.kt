package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GimbalLongDurationTest {
    private val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
    private val b = GimbalWaypoint(30.0, 0.0, 1.0, 175.0)
    private val c = GimbalWaypoint(30.0, 20.0, 1.0, 155.0)
    private data class Command(val at: Double, val target: GimbalWaypoint, val duration: Double)

    private fun simulate(program: GimbalProgram): List<Command> {
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(program, a))
        var live = a
        var from = a
        var target = a
        var sentAt = 0.0
        var duration = 1.0
        var clock = 0.0
        val commands = mutableListOf<Command>()
        repeat(30000) {
            if (!engine.running) return@repeat
            val dt = engine.nextWakeInterval.coerceAtLeast(0.000001)
            clock += dt
            live = GimbalMoveEngine.lerp(from, target, (clock - sentAt) / duration)
            val output = engine.tick(dt, live)!!
            output.target?.let { next ->
                val packet = CameraCommands.gimbalTimedTarget(next, output.duration)
                assertTrue(packet != null, "every native command must fit the25.5s byte duration")
                assertTrue(output.duration in 0.1..25.5)
                assertTrue(GimbalMoveEngine.canSendNativeTarget(live, next))
                commands += Command(clock, next, output.duration)
                from = live
                target = next
                sentAt = clock
                duration = output.duration
            }
        }
        assertEquals(null, engine.failure)
        assertEquals("DONE", engine.readout(live)?.phase)
        val total = program.durationAB + if (program.c == null) 0.0 else program.durationBC
        assertEquals(total, commands.last().at + commands.last().duration - commands.first().at, 1e-6)
        return commands
    }

    @Test
    fun exact120SecondLegUsesFiveNative24SecondPartsAndFinishesOnTime() {
        val commands = simulate(GimbalProgram(a, b, durationAB = 120.0))
        assertEquals(5, commands.size)
        assertTrue(commands.all { it.duration == 24.0 })
        assertEquals(b, commands.last().target)
        assertEquals(6.0, commands.first().target.yawDeg, 1e-9)
    }

    @Test
    fun curveWithTwo120SecondLegsKeeps240SecondTakeAndValidNativePackets() {
        val commands = simulate(GimbalProgram(a, b, c, 120.0, 120.0, 0.5))
        assertEquals(4799, commands.size)
        assertTrue(commands.all { it.duration == 0.1 })
        assertEquals(c, commands.last().target)
    }

    @Test
    fun durationAboveOnePacketLimitPartitionsEvenForSmallAngle() {
        val commands = simulate(GimbalProgram(a, b, durationAB = 26.0))
        assertEquals(2, commands.size)
        assertTrue(commands.all { it.duration == 13.0 })
        assertEquals(120.0, GimbalProgram.snapDuration(130.0))
    }
}
