package com.opencapture.openpocketcine.feed

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Serializes live Vulkan present against window detach and native destroy.
 *
 * `vkQueuePresentKHR` must not run after `surfaceDestroyed` returns — Android
 * then destroys the `ANativeWindow` mutex. `vkCreateImage` /
 * `DestroySwapchainKHR` must not run after `nativeDestroy`.
 */
internal class VulkanPresentGate {
    private val lock = ReentrantLock()
    private val idle = lock.newCondition()
    private var attached = false
    private var released = false
    private var inFlight = 0

    val windowReady: Boolean
        get() = lock.withLock { attached && !released }

    val isReleased: Boolean
        get() = lock.withLock { released }

    fun attach() {
        lock.withLock {
            if (released) return
            attached = true
        }
    }

    /** Stop new presents and wait for in-flight submit. Then drop the native window. */
    fun detach() {
        lock.withLock {
            attached = false
            waitIdleLocked()
        }
    }

    /** Stop new presents, wait for in-flight submit, then `nativeDestroy` is safe. */
    fun release() {
        lock.withLock {
            attached = false
            released = true
            waitIdleLocked()
        }
    }

    fun beginSubmit(): Boolean {
        lock.withLock {
            if (!attached || released) return false
            inFlight += 1
            return true
        }
    }

    fun endSubmit() {
        lock.withLock {
            if (inFlight > 0) inFlight -= 1
            if (inFlight == 0) idle.signalAll()
        }
    }

    fun shouldFallbackOnSubmitFailure(): Boolean = windowReady

    private fun waitIdleLocked() {
        while (inFlight > 0) {
            idle.await()
        }
    }
}
