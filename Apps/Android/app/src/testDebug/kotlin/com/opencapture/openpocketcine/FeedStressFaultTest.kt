package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FeedStressFaultTest {
    @Test fun faultsExpireEvenIfTheTestOwnerStopsRunning() {
        var now = 1L
        val fault = FeedStressFault(401) { now }
        assertTrue((1..100).all { fault.admit() })
        fault.arm("combined")
        repeat(1000) { fault.admit() }
        assertTrue(fault.dropped > 0)
        now += 8_000
        assertTrue((1..100).all { fault.admit() })
        fault.arm("burst")
        fault.disarm()
        assertTrue((1..100).all { fault.admit() })
    }

    @Test fun seedReproducesThePacketDecisions() {
        val a = FeedStressFault(401) { 1 }
        val b = FeedStressFault(401) { 1 }
        a.arm("combined")
        b.arm("combined")
        assertEquals(List(1000) { a.admit() }, List(1000) { b.admit() })
    }
}
