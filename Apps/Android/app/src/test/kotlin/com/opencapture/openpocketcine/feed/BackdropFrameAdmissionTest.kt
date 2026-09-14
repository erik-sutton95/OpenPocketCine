package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BackdropFrameAdmissionTest {
    @Test fun oneJobSurvivesSourceAndVisibilityReplacement() {
        val gate = BackdropFrameAdmission()
        val live = Any(); val playback = Any()
        gate.attach(live); gate.setActive(true)
        val first = assertNotNull(gate.acquire(live, 0, 1.0))
        gate.setActive(false); gate.attach(playback); gate.setActive(true)
        assertFalse(gate.isCurrent(first))
        assertNull(gate.acquire(live, 1_000_000_000, 1.0))
        assertNull(gate.acquire(playback, 1_000_000_000, 1.0))
        gate.complete(first)
        val next = assertNotNull(gate.acquire(playback, 1_000_000_000, 1.0))
        assertTrue(gate.isCurrent(next))
        gate.complete(first) // an old completion cannot free the next slot
        assertNull(gate.acquire(playback, 2_000_000_000, 1.0))
    }

    @Test fun thermalBackoffAndAdmissionFloorPersistAcrossLookChanges() {
        val gate = BackdropFrameAdmission(); val producer = Any()
        gate.attach(producer); gate.setActive(true)
        val first = assertNotNull(gate.acquire(producer, 0, 1.0))
        gate.invalidate(producer)
        assertFalse(gate.isCurrent(first)); gate.complete(first)
        val step = com.opencapture.monitorui.MonitorBackdropPolicy.MINIMUM_INTERVAL_NS
        assertNull(gate.acquire(producer, step - 1, 1.0))
        val second = assertNotNull(gate.acquire(producer, step, 1.0)); gate.complete(second)
        assertNull(gate.acquire(producer, step * 4 - 1, 3.0))
        val serious = assertNotNull(gate.acquire(producer, step * 4, 3.0)); gate.complete(serious)
        assertNull(gate.acquire(producer, step * 9 - 1, 5.0))
        assertNotNull(gate.acquire(producer, step * 9, 5.0))
    }

    @Test fun retiredProducerCannotInvalidateReplacement() {
        val gate = BackdropFrameAdmission(); val old = Any(); val next = Any()
        gate.attach(old); gate.setActive(true); gate.attach(next)
        val frame = assertNotNull(gate.acquire(next, 0, 1.0))
        assertFalse(gate.invalidate(old))
        assertFalse(gate.owns(old)); assertTrue(gate.owns(next))
        assertTrue(gate.isCurrent(frame))
    }

    @Test fun hiddenSceneAndDetachedProducerHaveNoDemand() {
        val gate = BackdropFrameAdmission(); val old = Any(); val next = Any()
        gate.attach(old)
        assertFalse(gate.hasDemand(old)); assertNull(gate.acquire(old, 0, 1.0))
        gate.setActive(true); gate.attach(next)
        assertFalse(gate.hasDemand(old)); assertTrue(gate.hasDemand(next))
        val frame = assertNotNull(gate.acquire(next, 0, 1.0))
        gate.invalidateAll()
        assertFalse(gate.isCurrent(frame))
        assertNull(gate.acquire(next, 1_000_000_000, 1.0))
    }
}
