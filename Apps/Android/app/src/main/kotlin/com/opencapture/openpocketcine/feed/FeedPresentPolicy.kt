package com.opencapture.openpocketcine.feed

/**
 * OpenPocketViewCore `FeedPresentPolicy` — present-path hygiene.
 *
 * Freeze is a flag, not a flush. Latest frame wins. A hidden GLES window is a
 * black well. Keep in lockstep with the Swift tests.
 */
object FeedPresentPolicy {
    const val FREEZE_THRESHOLD_SECONDS = 2.0
    const val MAX_WORKING_WIDTH = 1440

    fun shouldRender(
        attached: Boolean,
        enabled: Boolean,
        hidden: Boolean,
        hasDrawable: Boolean,
    ): Boolean = attached && enabled && !hidden && hasDrawable

    fun shouldScheduleBake(enabled: Boolean, hasDrawable: Boolean): Boolean = enabled && hasDrawable

    fun isDuplicateFrameTime(timeNs: Long, lastPresentedNs: Long): Boolean =
        timeNs != 0L && lastPresentedNs != 0L && timeNs == lastPresentedNs

    fun isFrozen(secondsSinceLastPresent: Double?): Boolean {
        val age = secondsSinceLastPresent ?: return false
        return age >= FREEZE_THRESHOLD_SECONDS
    }

    fun replaceOwnsPicture(hasPresentedFrame: Boolean, lastPresentWasOverlay: Boolean): Boolean =
        hasPresentedFrame && !lastPresentWasOverlay

    fun unhideMetalBeforeBake(overlay: Boolean): Boolean = !overlay

    fun preferProxyForMonitorGrade(hasProxy: Boolean): Boolean = hasProxy

    fun shouldFlushDisplayedImage(
        disconnecting: Boolean,
        layerFailed: Boolean,
        nextFrameReady: Boolean,
    ): Boolean {
        if (disconnecting) return true
        if (layerFailed) return nextFrameReady
        return false
    }
}

/** One live-enable write in flight. Overlapping `0x09/0xa8` is a black well. */
class SerialSessionGate {
    var inFlight: Boolean = false
        private set

    fun begin(): Boolean {
        if (inFlight) return false
        inFlight = true
        return true
    }

    fun end() {
        inFlight = false
    }
}
