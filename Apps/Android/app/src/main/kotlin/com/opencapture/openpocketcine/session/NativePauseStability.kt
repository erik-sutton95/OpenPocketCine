package com.opencapture.openpocketcine.session

/** A fixed actual-pose anchor after STOP, fed by distinct camera receipts. */
internal class NativePauseStability {
    private var stoppedAt = Double.POSITIVE_INFINITY
    private var anchor: NativeGimbalFeedback? = null
    private var latest: NativeGimbalFeedback? = null

    fun reset(now: Double) {
        stoppedAt = now
        anchor = null
        latest = null
    }

    fun observe(sample: NativeGimbalFeedback?) {
        if (sample == null || sample.receivedAt <= stoppedAt ||
            sample.receivedAt <= (latest?.receivedAt ?: Double.NEGATIVE_INFINITY)) return
        if (!nativeGimbalTargetIsSafe(sample.pose, sample, sample.receivedAt)) {
            anchor = null
            latest = null
            return
        }
        val first = anchor
        val gap = latest?.let { sample.receivedAt - it.receivedAt } ?: Double.POSITIVE_INFINITY
        if (first == null || gap > 0.3 || GimbalMoveEngine.angularDistance(first.pose, sample.pose) > 0.1) anchor = sample
        latest = sample
    }

    fun ready(now: Double): NativeGimbalFeedback? {
        val first = anchor ?: return null
        val last = latest ?: return null
        return last.takeIf { now - it.receivedAt in 0.0..0.3 && it.receivedAt - first.receivedAt >= 0.2 - 1e-9 }
    }
}
