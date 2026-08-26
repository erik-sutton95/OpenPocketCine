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
    const val EXTRA_MIRROR_HOLD_FRAMES = 3
    const val EXTRA_MIRROR_HOLD_SECONDS = 0.2
    /** 3 frames at 25 fps. Compose delay while the last orientation stays on screen. */
    const val EXTRA_MIRROR_HOLD_MS = 120L

    fun shouldHoldPictureAcrossMirror(framesHeld: Int, secondsHeld: Double): Boolean =
        framesHeld <= EXTRA_MIRROR_HOLD_FRAMES && secondsHeld < EXTRA_MIRROR_HOLD_SECONDS

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

/** Delays extra-mirror so the on-screen orientation is not X-flipped in place. */
class ExtraMirrorHold {
    enum class Step {
        UNCHANGED,
        HOLD,
        COMMIT,
    }

    data class Result(val step: Step, val mirrored: Boolean)

    var displayed: Boolean? = null
        private set
    private var pending: Boolean? = null
    private var framesHeld = 0
    private var startedAt: Double? = null

    fun reset() {
        displayed = null
        pending = null
        framesHeld = 0
        startedAt = null
    }

    fun step(want: Boolean, now: Double): Result {
        val shown = displayed
        if (shown == null) {
            displayed = want
            pending = null
            framesHeld = 0
            startedAt = null
            return Result(Step.COMMIT, want)
        }
        if (pending == null) {
            if (want == shown) return Result(Step.UNCHANGED, shown)
            pending = want
            framesHeld = 0
            startedAt = now
        } else if (pending != want) {
            if (want == shown) {
                pending = null
                framesHeld = 0
                startedAt = null
                return Result(Step.UNCHANGED, shown)
            }
            pending = want
            framesHeld = 0
            startedAt = now
        }
        framesHeld += 1
        val age = now - (startedAt ?: now)
        if (FeedPresentPolicy.shouldHoldPictureAcrossMirror(framesHeld, age)) {
            return Result(Step.HOLD, shown)
        }
        displayed = want
        pending = null
        framesHeld = 0
        startedAt = null
        return Result(Step.COMMIT, want)
    }
}
