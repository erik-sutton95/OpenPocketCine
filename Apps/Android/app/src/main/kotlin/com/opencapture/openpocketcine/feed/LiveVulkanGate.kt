package com.opencapture.openpocketcine.feed

import java.util.concurrent.atomic.AtomicReference

/**
 * Kotlin-side lifetime for the live Vulkan renderer.
 *
 * ImageReader submit on `opc.vk.img` must not overlap `DestroySwapchainKHR` or
 * device destroy. Native still serializes on `OpcVk.lock`; this gate stops new
 * presents after the window is gone and forces drain-then-destroy on release
 * (#186, #187, #190).
 */
internal class LiveVulkanGate {
    enum class Phase {
        Live,
        WindowGone,
        Released,
    }

    private val phaseRef = AtomicReference(Phase.Live)

    val phase: Phase
        get() = phaseRef.get()

    fun allowsSubmit(): Boolean = phaseRef.get() == Phase.Live

    fun allowsAttach(): Boolean = phaseRef.get() != Phase.Released

    fun attachWindow(): Boolean {
        while (true) {
            val cur = phaseRef.get()
            if (cur == Phase.Released) return false
            if (phaseRef.compareAndSet(cur, Phase.Live)) return true
        }
    }

    fun detachWindow() {
        while (true) {
            val cur = phaseRef.get()
            if (cur != Phase.Live) return
            if (phaseRef.compareAndSet(cur, Phase.WindowGone)) return
        }
    }

    fun release(
        drain: () -> Unit,
        destroy: () -> Unit,
    ): Boolean {
        while (true) {
            val cur = phaseRef.get()
            if (cur == Phase.Released) return false
            if (phaseRef.compareAndSet(cur, Phase.Released)) {
                drain()
                destroy()
                return true
            }
        }
    }
}
