package com.opencapture.openpocketcine.feed

/** Retained display pixels are not proof that a new source has produced a frame. */
internal class InspectorPreviewSource {
    private var identity: Any? = null
    private var ready = true
    private var epoch = 0L
    private var latchedEpoch: Long? = null

    @Synchronized fun configure(sourceIdentity: Any, sourceReady: Boolean): Boolean {
        if (identity == sourceIdentity && ready == sourceReady) return false
        identity = sourceIdentity
        ready = sourceReady
        invalidate()
        return true
    }

    @Synchronized fun invalidate() { epoch += 1; latchedEpoch = null }
    @Synchronized fun beginLatch(): Long? = epoch.takeIf { ready }
    @Synchronized fun didLatch(ticket: Long?) {
        if (ready && ticket == epoch) latchedEpoch = epoch
    }
    @Synchronized fun captureEpoch(): Long? = epoch.takeIf { ready && latchedEpoch == epoch }
    @Synchronized fun isCurrent(ticket: Long?): Boolean = ticket != null && captureEpoch() == ticket
}
