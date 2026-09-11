package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals

class CoalescedGimbalTickTest {
    @Test
    fun blockedTxAcrossThrowsAndReleaseDoesNotReplayCapturedAxes() {
        val tx = ArrayDeque<() -> Unit>()
        val sent = mutableListOf<Int>()
        var currentAxis = 0
        val dispatch = CoalescedGimbalTick({ tx.addLast(it) }) { sent += currentAxis }
        // Executor remains blocked while ACK ticks see several different throws.
        for (axis in 1..20) {
            currentAxis = axis
            dispatch.request()
        }
        assertEquals(1, tx.size)
        // Release fences the old tick before updating the state, as the driver does.
        dispatch.invalidate()
        currentAxis = 0
        repeat(10) { dispatch.request() }
        assertEquals(2, tx.size) // One inert old token, one pending current read.
        while (tx.isNotEmpty()) tx.removeFirst()()
        assertEquals(listOf(0), sent)
    }

    @Test
    fun pendingTickReadsLatestThrowAndNativeStopPrecedesNewOwnership() {
        val tx = ArrayDeque<() -> Unit>()
        val events = mutableListOf<String>()
        var currentAxis = 1
        val dispatch = CoalescedGimbalTick({ tx.addLast(it) }) { events += "axis $currentAxis" }
        dispatch.request()
        currentAxis = 2
        dispatch.request()
        tx.removeFirst()()
        assertEquals(listOf("axis 2"), events)
        dispatch.request()
        dispatch.invalidate()
        tx.addLast { events += "native stop" }
        currentAxis = 3
        repeat(10) { dispatch.request() }
        while (tx.isNotEmpty()) tx.removeFirst()()
        assertEquals(listOf("axis 2", "native stop", "axis 3"), events)
    }
}
