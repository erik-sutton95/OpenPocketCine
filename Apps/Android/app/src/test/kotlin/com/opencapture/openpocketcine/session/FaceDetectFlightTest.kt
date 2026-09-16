package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FaceDetectFlightTest {
    @Test
    fun completionTakesTheFlightOnce() {
        val flight = FaceDetectFlight()
        val id = flight.begin()
        assertTrue(flight.take(id))
        assertFalse(flight.take(id), "watchdog must not deliver after completion")
    }

    @Test
    fun watchdogTakesTheFlightSoCompletionDoesNotDeliver() {
        val flight = FaceDetectFlight()
        val id = flight.begin()
        assertTrue(flight.take(id), "watchdog unsticks Face AF")
        assertFalse(flight.take(id), "completion must only recycle, not deliver")
    }

    @Test
    fun nextBeginIsANewFlight() {
        val flight = FaceDetectFlight()
        val first = flight.begin()
        assertTrue(flight.take(first))
        val second = flight.begin()
        assertTrue(second != first)
        assertTrue(flight.take(second))
    }

    @Test
    fun invalidateDropsAnInFlightId() {
        val flight = FaceDetectFlight()
        val id = flight.begin()
        flight.invalidate()
        assertFalse(flight.take(id))
    }
}
