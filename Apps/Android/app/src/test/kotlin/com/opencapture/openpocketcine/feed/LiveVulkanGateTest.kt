package com.opencapture.openpocketcine.feed

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LiveVulkanGateTest {
    @Test
    fun liveAllowsSubmitAndAttach() {
        val gate = LiveVulkanGate()
        assertEquals(LiveVulkanGate.Phase.Live, gate.phase)
        assertTrue(gate.allowsSubmit())
        assertTrue(gate.allowsAttach())
    }

    @Test
    fun detachForbidsSubmitUntilAttach() {
        val gate = LiveVulkanGate()
        gate.detachWindow()
        assertEquals(LiveVulkanGate.Phase.WindowGone, gate.phase)
        assertFalse(gate.allowsSubmit())
        assertTrue(gate.allowsAttach())
        assertTrue(gate.attachWindow())
        assertTrue(gate.allowsSubmit())
    }

    @Test
    fun releaseDrainsImageThreadBeforeNativeDestroy() {
        val gate = LiveVulkanGate()
        val order = mutableListOf<String>()
        assertTrue(
            gate.release(
                drain = { order += "drain" },
                destroy = { order += "destroy" },
            ),
        )
        assertEquals(listOf("drain", "destroy"), order)
        assertEquals(LiveVulkanGate.Phase.Released, gate.phase)
        assertFalse(gate.allowsSubmit())
        assertFalse(gate.allowsAttach())
        assertFalse(gate.attachWindow())
    }

    @Test
    fun doubleReleaseDoesNotDestroyTwice() {
        val gate = LiveVulkanGate()
        val destroys = AtomicInteger(0)
        assertTrue(gate.release(drain = {}, destroy = { destroys.incrementAndGet() }))
        assertFalse(gate.release(drain = {}, destroy = { destroys.incrementAndGet() }))
        assertEquals(1, destroys.get())
    }

    @Test
    fun submitIsForbiddenWhileDrainRuns() {
        val gate = LiveVulkanGate()
        val draining = CountDownLatch(1)
        val finishDrain = CountDownLatch(1)
        val destroyed = AtomicBoolean(false)
        val worker = Thread {
            gate.release(
                drain = {
                    draining.countDown()
                    check(finishDrain.await(2, TimeUnit.SECONDS))
                },
                destroy = { destroyed.set(true) },
            )
        }
        worker.start()
        assertTrue(draining.await(2, TimeUnit.SECONDS))
        assertFalse(gate.allowsSubmit())
        assertFalse(destroyed.get())
        finishDrain.countDown()
        worker.join(2_000)
        assertTrue(destroyed.get())
    }
}
