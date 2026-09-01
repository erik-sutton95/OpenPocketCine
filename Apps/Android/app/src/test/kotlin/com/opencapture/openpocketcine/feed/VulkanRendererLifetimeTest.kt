package com.opencapture.openpocketcine.feed

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VulkanRendererLifetimeTest {
    @Test
    fun submitRequiresLiveHandleAndWindow() {
        val life = VulkanRendererLifetime(42L)
        assertTrue(life.isReady)
        assertFalse(life.canSubmit())
        assertEquals(42L, life.liveHandle())

        life.markWindowAttached(true)
        assertTrue(life.canSubmit())

        life.markWindowAttached(false)
        assertFalse(life.canSubmit())

        life.markWindowAttached(true)
        life.markWindowDetached()
        assertFalse(life.canSubmit())
        assertEquals(42L, life.liveHandle())
        assertTrue(life.isReady)
    }

    @Test
    fun releaseZerosHandleAndBlocksSubmit() {
        val life = VulkanRendererLifetime(7L)
        life.markWindowAttached(true)
        val destroyed = life.beginRelease()
        assertEquals(7L, destroyed)
        assertEquals(0L, life.liveHandle())
        assertFalse(life.canSubmit())
        assertFalse(life.isReady)
        assertFalse(life.windowReady)
        assertEquals(0L, life.beginRelease())
    }

    @Test
    fun failedCreateNeverSubmits() {
        val life = VulkanRendererLifetime(0L)
        life.markWindowAttached(true)
        assertFalse(life.isReady)
        assertFalse(life.canSubmit())
        assertEquals(0L, life.beginRelease())
    }

    @Test
    fun detachThenAttachRestoresSubmit() {
        val life = VulkanRendererLifetime(3L)
        life.markWindowAttached(true)
        life.markWindowDetached()
        assertFalse(life.canSubmit())
        assertTrue(life.isReady)
        life.markWindowAttached(true)
        assertTrue(life.canSubmit())
    }

    @Test
    fun attachAfterReleaseDoesNotReopenWindow() {
        val life = VulkanRendererLifetime(1L)
        life.beginRelease()
        life.markWindowAttached(true)
        assertFalse(life.windowReady)
        assertFalse(life.canSubmit())
        assertEquals(0L, life.liveHandle())
    }

    @Test
    fun concurrentReleaseStopsNewSubmits() {
        val life = VulkanRendererLifetime(99L)
        life.markWindowAttached(true)
        val sawZero = CountDownLatch(1)
        val pool = Executors.newSingleThreadExecutor()
        pool.execute {
            while (life.liveHandle() != 0L) {
                life.canSubmit()
            }
            sawZero.countDown()
        }
        val destroyed = life.beginRelease()
        assertEquals(99L, destroyed)
        assertTrue(sawZero.await(5, TimeUnit.SECONDS))
        pool.shutdownNow()
        assertEquals(0L, life.liveHandle())
        assertFalse(life.canSubmit())
        assertFalse(life.windowReady)
    }
}
