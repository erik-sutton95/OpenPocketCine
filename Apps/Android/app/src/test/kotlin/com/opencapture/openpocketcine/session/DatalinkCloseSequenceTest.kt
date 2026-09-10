package com.opencapture.openpocketcine.session

import java.util.concurrent.atomic.AtomicBoolean
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DatalinkCloseSequenceTest {
    @Test
    fun blockedTxCloseImmediatelyFencesMotionThenStopsBeforeSocketTeardown() {
        val tx = ArrayDeque<() -> Unit>()
        val closed = AtomicBoolean(false)
        val events = mutableListOf<String>()
        val program = NativeGimbalProgramRunner({ 0.0 }, { _, action -> tx.addLast(action) },
            { NativeGimbalFeedback(GimbalWaypoint(0.0, 0.0, 1.0, 175.0), 0.0) },
            { _, _ -> events += "native target"; true }, { events += "ordinary stop" })
        val manual = CoalescedGimbalTick({ tx.addLast(it) }) { events += "manual throw" }
        val curve = NativeCurveDispatch({ 0 }, { _, action -> tx.addLast(action) }) { events += "curve target" }
        program.start(GimbalProgram(GimbalWaypoint(0.0, 0.0, 1.0, 175.0),
            GimbalWaypoint(20.0, 0.0, 1.0, 175.0))) { events += "progress" }
        repeat(10) { manual.request(); curve.note(byteArrayOf(it.toByte())) }
        val close = DatalinkCloseSequence(closed,
            fence = { program.invalidate(); manual.invalidate(); curve.clear(); events += "fenced" },
            enqueue = { tx.addLast(it) },
            stop = { events += "close stop" },
            teardown = { events += "socket teardown" })
        close.close()
        close.close()
        assertTrue(closed.get())
        assertEquals(listOf("fenced"), events, "close returns before blocked TX executes any I/O")
        // Ordinary commands submitted after close are rejected by the driver's closed gate.
        if (!closed.get()) tx.addLast { events += "late manual" }
        while (tx.isNotEmpty()) tx.removeFirst()()
        assertEquals(listOf("fenced", "close stop", "socket teardown"), events)
    }

    @Test
    fun bestEffortStopFailureStillClosesSocketExactlyOnce() {
        val tx = ArrayDeque<() -> Unit>()
        val events = mutableListOf<String>()
        val close = DatalinkCloseSequence(AtomicBoolean(false), {}, { tx.addLast(it) },
            stop = { events += "stop attempt"; throw java.io.IOException("link lost") },
            teardown = { events += "socket teardown" })
        close.close()
        close.close()
        while (tx.isNotEmpty()) tx.removeFirst()()
        assertEquals(listOf("stop attempt", "socket teardown"), events)
    }
}
