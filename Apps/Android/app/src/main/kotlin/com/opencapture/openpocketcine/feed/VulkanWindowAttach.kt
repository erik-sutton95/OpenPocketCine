package com.opencapture.openpocketcine.feed

/**
 * Swapchain attach rules for the live SurfaceView.
 *
 * API 34+ SurfaceView follows visibility by default: Settings / Media covering
 * the monitor destroys the surface. That is not a leave-live teardown. Pocket
 * has no periodic GOP, and the watchdog will not PLI while UDP `0x02` is still
 * arriving, so a destroyed surface returns as a black well with live HUD (#248).
 */
internal object VulkanWindowAttach {
    const val SURFACE_LIFECYCLE_FOLLOWS_ATTACHMENT_API = 34

    fun shouldCreateSwapchain(width: Int, height: Int): Boolean = width >= 2 && height >= 2

    /**
     * A failed attach is a retry on the next `surfaceChanged`, not a GLES
     * fallback. Falling back unbound MediaCodec from the ImageReader and left
     * the well black while UDP stayed live.
     */
    fun shouldFallbackToGlesOnAttachFailure(): Boolean = false

    fun keepSurfaceWhileAttached(sdkInt: Int): Boolean =
        sdkInt >= SURFACE_LIFECYCLE_FOLLOWS_ATTACHMENT_API
}
