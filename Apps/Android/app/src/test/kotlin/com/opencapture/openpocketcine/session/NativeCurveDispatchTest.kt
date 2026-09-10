package com.opencapture.openpocketcine.session

import java.util.PriorityQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class NativeCurveDispatchTest {
    private class Queue {
        data class Task(val at: Long, val sequence: Int, val action: () -> Unit)
        var now = 0L
        private var sequence = 0
        val tasks = PriorityQueue<Task>(compareBy<Task> { it.at }.thenBy { it.sequence })
        fun schedule(delay: Long, action: () -> Unit) {
            tasks.add(Task(now + delay, sequence++, action))
        }
        fun next() {
            val task = tasks.remove()
            now = maxOf(now, task.at)
            task.action()
        }
        fun finish() { while (tasks.isNotEmpty()) next() }
    }

    @Test
    fun latestOnlyAndDelayedDrainCannotBurstWithNextSubmission() {
        val queue = Queue()
        val sends = mutableListOf<Pair<Long, Int>>()
        val dispatch = NativeCurveDispatch({ queue.now }, queue::schedule) {
            sends += queue.now to it[0].toInt()
        }
        repeat(49) { dispatch.note(byteArrayOf(it.toByte())) }
        assertEquals(1, queue.tasks.size)
        queue.now = 49
        queue.next()
        queue.now = 50
        dispatch.note(byteArrayOf(99))
        queue.next() // Must defer despite the fresh submission being due immediately.
        assertEquals(listOf(49L to 48), sends)
        queue.finish()
        assertEquals(listOf(49L to 48, 89L to 99), sends)
    }

    @Test
    fun duplicateAndExpiredTargetsDoNotWrite() {
        val queue = Queue()
        val sends = mutableListOf<Int>()
        val dispatch = NativeCurveDispatch({ queue.now }, queue::schedule) { sends += it[0].toInt() }
        dispatch.note(byteArrayOf(1))
        queue.finish()
        dispatch.note(byteArrayOf(1))
        queue.finish()
        dispatch.note(byteArrayOf(2))
        queue.now = 121
        queue.finish()
        assertEquals(listOf(1), sends)
    }

    @Test
    fun clearFencesQueuedTargetsAndStopPrecedesNewManualCommand() {
        val queue = Queue()
        val events = mutableListOf<String>()
        val dispatch = NativeCurveDispatch({ queue.now }, queue::schedule) { events += "target" }
        dispatch.note(byteArrayOf(1))
        dispatch.clear()
        queue.schedule(0) { events += "stop" }
        queue.schedule(0) { events += "manual" }
        queue.finish()
        assertEquals(listOf("stop", "manual"), events)
    }

    @Test
    fun slowWriteDoesNotBlockNoteOrClearAndCannotSendOldWorkAfterStop() {
        val queue = Queue()
        val events = mutableListOf<String>()
        val callerFinished = CountDownLatch(1)
        var responsive = false
        lateinit var dispatch: NativeCurveDispatch
        dispatch = NativeCurveDispatch({ queue.now }, queue::schedule) {
            events += "old write"
            val caller = thread {
                dispatch.note(byteArrayOf(2))
                dispatch.clear()
                queue.schedule(0) { events += "stop" }
                queue.schedule(0) { events += "manual" }
                callerFinished.countDown()
            }
            responsive = callerFinished.await(1, TimeUnit.SECONDS)
            caller.join(1000)
            queue.now += 80 // Socket work finishes later; pacing starts from completion.
        }
        dispatch.note(byteArrayOf(1))
        queue.next()
        assertTrue(responsive, "caller must finish while socket write remains in flight")
        queue.finish()
        assertEquals(listOf("old write", "stop", "manual"), events)
    }

    @Test
    fun slowWriteCompletionDefinesPacingForPendingReplacement() {
        val queue = Queue()
        val sends = mutableListOf<Long>()
        lateinit var dispatch: NativeCurveDispatch
        dispatch = NativeCurveDispatch({ queue.now }, queue::schedule) {
            sends += queue.now
            if (sends.size == 1) {
                dispatch.note(byteArrayOf(2))
                queue.now += 80
            }
        }
        dispatch.note(byteArrayOf(1))
        queue.finish()
        assertEquals(listOf(0L, 120L), sends)
    }
}
