package com.opencapture.openpocketcine.session

import java.util.PriorityQueue
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NativeGimbalProgramRunnerTest {
    private class Tx {
        data class Task(val at: Double, val order: Int, val action: () -> Unit)
        val pending = PriorityQueue<Task>(compareBy<Task> { it.at }.thenBy { it.order })
        var now = 0.0
        private var order = 0
        fun schedule(delay: Double, action: () -> Unit) { pending += Task(now + delay, order++, action) }
        fun through(until: Double) {
            while (pending.peek()?.at?.let { it <= until } == true) {
                val task = pending.remove()
                now = maxOf(now, task.at)
                task.action()
            }
            now = maxOf(now, until)
        }
    }

    private val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
    private val b = GimbalWaypoint(30.0, 0.0, 1.0, 175.0)
    private val c = GimbalWaypoint(30.0, 20.0, 1.0, 155.0)

    @Test
    fun pauseFencesTimersAndResumeNeedsStableReceiptsWithoutCountdown() {
        val tx = Tx()
        var sample = NativeGimbalFeedback(a, 0.0)
        val sent = mutableListOf<Pair<Double, GimbalWaypoint>>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule, { sample }, { point, _ ->
            sent += tx.now to point; true
        }, { stops++ })
        fun receive() {
            sample = NativeGimbalFeedback(a, tx.now)
            if (tx.now < 4.0) tx.schedule(0.05) { receive() }
        }
        receive()
        val token = runner.start(GimbalProgram(a, b, durationAB = 4.0)) { updates += it }
        tx.through(2.5)
        assertEquals(1, sent.size)
        val oldProgress = updates.last()
        assertTrue(runner.pause(token))
        assertFalse(runner.isCurrentProgress(oldProgress))
        tx.through(2.51)
        assertEquals(1, stops)
        assertTrue(updates.last().paused)
        assertTrue(runner.resume(token))
        tx.through(2.52)
        assertTrue(updates.last().paused)
        assertTrue(updates.last().note != null)
        tx.through(2.9)
        assertEquals(1, sent.size, "paused timers cannot send another target")
        val pausedProgress = updates.last()
        assertTrue(runner.resume(token))
        tx.through(2.91)
        assertEquals(2, sent.size, "stable resume sends immediately without preparation/countdown")
        assertFalse(updates.last().paused)
        assertFalse(runner.isCurrentProgress(pausedProgress))
        assertTrue(runner.pause(token))
        tx.through(2.92)
        assertTrue(runner.cancel(token))
        assertFalse(runner.resume(token))
        tx.through(4.0)
        assertEquals(2, sent.size)
    }

    @Test
    fun continuousCurveCompletesWhileUiNeverDrainsItsCallbackQueue() {
        val tx = Tx()
        var sample = NativeGimbalFeedback(a, 0.0)
        var origin = a
        var target = a
        var motionAt = 0.0
        var duration = 1.0
        fun physical() = GimbalMoveEngine.lerp(origin, target, (tx.now - motionAt) / duration)
        fun receive() {
            sample = NativeGimbalFeedback(physical(), tx.now)
            if (tx.now < 8.0) tx.schedule(0.01) { receive() }
        }
        val sends = mutableListOf<Pair<Double, GimbalWaypoint>>()
        val queuedUi = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule, { sample }, { next, seconds ->
            origin = physical()
            target = next
            motionAt = tx.now
            duration = seconds
            sends += tx.now to next
            true
        }, { stops++ })
        receive()
        runner.start(GimbalProgram(a, b, c, 3.0, 2.0, 1.0)) { queuedUi += it }
        tx.through(8.0) // No UI callbacks are consumed during the entire take.
        assertEquals(99, sends.size)
        assertEquals(4.9, sends.last().first - sends.first().first, 0.00001)
        assertEquals(c, sends.last().second)
        assertEquals(0, stops)
        assertTrue(queuedUi.last().finished)
        assertEquals(null, queuedUi.last().failure)
        assertEquals("DONE", queuedUi.last().readout?.phase)
        assertTrue(queuedUi.size <= 40, "progress must stay within 5 Hz plus start/finish")
    }

    @Test
    fun startReadsNewFeedbackAfterPreparationAndRejectsOldReceipt() {
        val tx = Tx()
        var sample = NativeGimbalFeedback(a, 0.0)
        var stops = 0
        val sent = mutableListOf<GimbalWaypoint>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule, { sample }, { point, _ ->
            sent += point; true
        }, { stops++ })
        // A blocked preparation queue advances clock before the start task can run.
        tx.schedule(0.0) { tx.now = 1.0 }
        runner.start(GimbalProgram(a, b)) { updates += it }
        tx.through(1.5)
        assertTrue(sent.isEmpty())
        assertTrue(updates.last().finished)
        assertTrue(updates.last().failure != null)
        assertEquals(1, stops)
        // A fresh post-preparation observation replaces the old UI-cached A pose.
        sample = NativeGimbalFeedback(c, tx.now)
        runner.start(GimbalProgram(a, b)) { updates += it }
        tx.schedule(0.24) { sample = NativeGimbalFeedback(c, tx.now) }
        tx.through(1.9)
        assertEquals(a, sent.first())
        assertEquals("APPROACH", updates.last().readout?.phase)
    }

    @Test
    fun cancelBeforePreparationFencesStartAndStopPrecedesManualCommand() {
        val tx = Tx()
        val events = mutableListOf<String>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(a, tx.now) }, { _, _ -> events += "target"; true }, { events += "stop" })
        val token = runner.start(GimbalProgram(a, b)) { events += "progress" }
        assertTrue(runner.cancel(token))
        assertFalse(runner.cancel(token))
        tx.schedule(0.0) { events += "manual" }
        tx.through(1.0)
        assertEquals(listOf("stop", "manual"), events)
    }

    @Test
    fun oldCancellationCannotStopNewRunAndMissingFeedbackStopsActiveRun() {
        val tx = Tx()
        var sample: NativeGimbalFeedback? = NativeGimbalFeedback(a, 0.0)
        var stops = 0
        val progress = mutableListOf<NativeGimbalProgramRunner.Progress>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule, { sample }, { _, _ -> true }, { stops++ })
        val old = runner.start(GimbalProgram(a, b)) { progress += it }
        runner.cancel(old)
        val current = runner.start(GimbalProgram(a, b)) { progress += it }
        assertFalse(runner.cancel(old))
        tx.schedule(0.24) { sample = NativeGimbalFeedback(a, tx.now) }
        tx.through(0.26)
        assertEquals(current, progress.last().token)
        sample = null
        tx.through(0.4)
        assertTrue(progress.last().finished)
        assertTrue(progress.last().failure != null)
        assertEquals(2, stops)
    }

    @Test
    fun directWireFeedbackRetainsSamePacketRawPitchAndReceipt() {
        val bytes = ByteArray(22)
        fun i16(at: Int, value: Int) {
            bytes[at] = value.toByte()
            bytes[at + 1] = (value shr 8).toByte()
        }
        i16(0, -1718)
        i16(4, 330)
        i16(20, 89)
        val frame = DumlFrame(0, 0, 1, 0, 4, 5, bytes)
        val sample = NativeGimbalFeedback.from(frame, 12.34)!!
        assertEquals(12.34, sample.receivedAt)
        assertEquals(-171.8, sample.pose.nativePitchDeg)
        assertEquals(-8.9, sample.pose.pitchDeg)
        assertEquals(33.0, sample.pose.yawDeg)
        assertEquals(null, NativeGimbalFeedback.from(frame.copy(payload = bytes.copyOf(21)), 12.35))
    }
    @Test
    fun rebindInterruptsPendingPreparationAndActiveTimerWithoutStoppingReplacementSocket() {
        for (duringPreparation in listOf(true, false)) {
            val tx = Tx()
            val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
            var targets = 0
            var stops = 0
            val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
                { NativeGimbalFeedback(a, tx.now) }, { _, _ -> targets++; true }, { stops++ })
            runner.start(GimbalProgram(a, b)) { updates += it }
            tx.through(if (duringPreparation) 0.1 else 0.5)
            runner.interrupt()
            tx.through(3.0)
            assertEquals(0, targets)
            assertEquals(0, stops, "rebind cleanup must not STOP a replacement connection")
            assertTrue(updates.last().finished)
            assertEquals("Move interrupted — camera connection changed", updates.last().failure)
        }
    }

    @Test
    fun rejectedSocketWriteStopsRunInsteadOfClaimingTargetWasDispatched() {
        val tx = Tx()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var rejectedTargets = 0
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(c, tx.now) }, { _, _ -> rejectedTargets++; false }, { stops++ })
        runner.start(GimbalProgram(a, b)) { updates += it }
        tx.through(1.0)
        assertEquals(1, rejectedTargets)
        assertEquals(1, stops)
        assertTrue(updates.last().finished)
        assertTrue(updates.last().failure != null)
    }
    @Test
    fun lastMileYawGateRejectsLongShortcutAndExactlyHalfTurn() {
        val selfie = NativeGimbalFeedback(a.copy(yawDeg = 225.0), 1.0)
        assertFalse(nativeGimbalTargetIsSafe(a.copy(yawDeg = 28.7), selfie, 1.1))
        assertFalse(nativeGimbalTargetIsSafe(a.copy(yawDeg = 45.0), selfie, 1.1))
        assertTrue(nativeGimbalTargetIsSafe(a.copy(yawDeg = 45.1), selfie, 1.1))
        assertTrue(nativeGimbalTargetIsSafe(a.copy(yawDeg = 126.85), selfie, 1.1))
        assertFalse(nativeGimbalTargetIsSafe(a.copy(yawDeg = 126.85), selfie, 1.31))
        assertFalse(nativeGimbalTargetIsSafe(a.copy(yawDeg = 260.0), selfie, 1.1))
        assertFalse(nativeGimbalTargetIsSafe(a, selfie.copy(pose = a.copy(pitchDeg = -60.0)), 1.1))
    }

}
