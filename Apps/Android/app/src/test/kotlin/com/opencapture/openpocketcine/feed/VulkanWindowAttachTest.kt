package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VulkanWindowAttachTest {
    @Test
    fun zeroSizeSurfaceIsNotASwapchain() {
        assertFalse(VulkanWindowAttach.shouldCreateSwapchain(0, 1080))
        assertFalse(VulkanWindowAttach.shouldCreateSwapchain(2340, 0))
        assertFalse(VulkanWindowAttach.shouldCreateSwapchain(1, 1))
        assertTrue(VulkanWindowAttach.shouldCreateSwapchain(2, 2))
        assertTrue(VulkanWindowAttach.shouldCreateSwapchain(2340, 1080))
    }

    @Test
    fun attachFailureIsNotAGlesFallback() {
        assertFalse(VulkanWindowAttach.shouldFallbackToGlesOnAttachFailure())
    }

    @Test
    fun api34KeepsTheSurfaceWhileAnOverlayCoversTheMonitor() {
        assertFalse(VulkanWindowAttach.keepSurfaceWhileAttached(33))
        assertTrue(VulkanWindowAttach.keepSurfaceWhileAttached(34))
        assertTrue(VulkanWindowAttach.keepSurfaceWhileAttached(35))
    }
}
