package com.opencapture.openpocketcine.feed

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Kotlin-side gate for the live Vulkan JNI handle.
 *
 * `nativeSubmit` must not run after window detach or `release()`: Adreno
 * aborts in `vkCreateImage` / `vkQueuePresentKHR` when the swapchain or
 * device is already gone (Play Vitals #186 / #187).
 */
internal class VulkanRendererLifetime(initialHandle: Long) {
    private val released = AtomicBoolean(false)
    private val handle = AtomicLong(initialHandle)
    private val window = AtomicBoolean(false)

    val isReady: Boolean
        get() = liveHandle() != 0L

    val windowReady: Boolean
        get() = window.get() && !released.get()

    fun liveHandle(): Long = if (released.get()) 0L else handle.get()

    fun canSubmit(): Boolean = liveHandle() != 0L && window.get()

    fun markWindowAttached(ok: Boolean) {
        if (released.get()) {
            window.set(false)
            return
        }
        window.set(ok)
    }

    fun markWindowDetached() {
        window.set(false)
    }

    /** Handle to `nativeDestroy` after the image thread has drained. */
    fun beginRelease(): Long {
        if (!released.compareAndSet(false, true)) return 0L
        window.set(false)
        return handle.getAndSet(0L)
    }
}
