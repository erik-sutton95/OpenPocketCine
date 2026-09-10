package com.opencapture.openpocketcine.session

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith

class MotionStartCountdownTest {
    @Test
    fun threeVisibleSecondsPrecedeTheNativeHandoff() = runBlocking {
        var second = 0
        val states = mutableListOf<Pair<Int, Int?>>()
        awaitMotionStartCountdown(pause = { second++ }) { states += second to it }
        assertEquals(listOf(0 to 3, 1 to 2, 2 to 1, 3 to null), states)
    }

    @Test
    fun cancellationDuringCountdownNeverHandsOffToNativeMotion() = runBlocking {
        var waits = 0
        var started = false
        val states = mutableListOf<Int?>()
        assertFailsWith<CancellationException> {
            awaitMotionStartCountdown(pause = {
                if (++waits == 2) throw CancellationException("operator stopped")
            }) { states += it }
            started = true
        }
        assertFalse(started)
        assertEquals(listOf<Int?>(3, 2), states)
    }
}
