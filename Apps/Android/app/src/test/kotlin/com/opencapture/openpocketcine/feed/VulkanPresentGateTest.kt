package com.opencapture.openpocketcine.feed

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VulkanPresentGateTest {
    @Test
    fun submitIsRefusedUntilWindowAttaches() {
        val gate = VulkanPresentGate()
        assertFalse(gate.windowReady)
        assertFalse(gate.beginSubmit())
        gate.attach()
        assertTrue(gate.windowReady)
        assertTrue(gate.beginSubmit())
        gate.endSubmit()
    }

    @Test
    fun detachRefusesFurtherSubmit() {
        val gate = VulkanPresentGate()
        gate.attach()
        gate.detach()
        assertFalse(gate.windowReady)
        assertFalse(gate.beginSubmit())
    }

    @Test
    fun attachAfterDetachAllowsSubmitAgain() {
        val gate = VulkanPresentGate()
        gate.attach()
        gate.detach()
        gate.attach()
        assertTrue(gate.windowReady)
        assertTrue(gate.beginSubmit())
        gate.endSubmit()
    }

    @Test
    fun detachWaitsForInFlightSubmitBeforeReturning() {
        val gate = VulkanPresentGate()
        gate.attach()
        assertTrue(gate.beginSubmit())
        val started = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val worker =
            Thread {
                started.countDown()
                gate.detach()
                finished.countDown()
            }
        worker.start()
        assertTrue(started.await(1, TimeUnit.SECONDS))
        assertFalse(finished.await(80, TimeUnit.MILLISECONDS))
        gate.endSubmit()
        assertTrue(finished.await(1, TimeUnit.SECONDS))
        worker.join(1_000)
        assertFalse(gate.beginSubmit())
    }

    @Test
    fun releaseWaitsForInFlightSubmitThenIsTerminal() {
        val gate = VulkanPresentGate()
        gate.attach()
        assertTrue(gate.beginSubmit())
        val started = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val worker =
            Thread {
                started.countDown()
                gate.release()
                finished.countDown()
            }
        worker.start()
        assertTrue(started.await(1, TimeUnit.SECONDS))
        assertFalse(finished.await(80, TimeUnit.MILLISECONDS))
        gate.endSubmit()
        assertTrue(finished.await(1, TimeUnit.SECONDS))
        worker.join(1_000)
        assertTrue(gate.isReleased)
        assertFalse(gate.windowReady)
        assertFalse(gate.beginSubmit())
        gate.attach()
        assertFalse(gate.beginSubmit())
    }

    @Test
    fun submitFailureFallsBackOnlyWhileWindowIsReady() {
        val gate = VulkanPresentGate()
        assertFalse(gate.shouldFallbackOnSubmitFailure())
        gate.attach()
        assertTrue(gate.shouldFallbackOnSubmitFailure())
        gate.detach()
        assertFalse(gate.shouldFallbackOnSubmitFailure())
        gate.attach()
        assertTrue(gate.shouldFallbackOnSubmitFailure())
        gate.release()
        assertFalse(gate.shouldFallbackOnSubmitFailure())
    }

    @Test
    fun extraEndSubmitDoesNotBlockDetach() {
        val gate = VulkanPresentGate()
        gate.attach()
        gate.endSubmit()
        gate.detach()
        assertFalse(gate.beginSubmit())
    }
}
