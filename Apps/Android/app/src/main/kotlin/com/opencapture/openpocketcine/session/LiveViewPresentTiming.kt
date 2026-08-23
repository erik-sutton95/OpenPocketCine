package com.opencapture.openpocketcine.session

/**
 * SoftAP live HEVC is encoder-declared 25 fps (VPS/SPS `time_scale=25`). Stamp
 * wall-clock PTS anyway — a 30 fps staircase made MediaCodec hold frames until
 * they were "due" if the camera ever pushed faster than the hint.
 */
internal object LiveViewPresentTiming {
    const val FRAME_RATE_HINT = 60
    const val OPERATING_RATE = 120

    /** Never block the UDP ingest thread waiting for a P-frame slot. */
    const val INPUT_WAIT_US = 0L

    /** IDR must land — the GOP has no second chance for tens of seconds. */
    const val KEYFRAME_WAIT_US = 50_000L

    fun inputWaitUs(keyframe: Boolean): Long = if (keyframe) KEYFRAME_WAIT_US else INPUT_WAIT_US

    fun ptsUs(nowElapsedRealtimeNs: Long, lastPtsUs: Long): Long {
        val now = nowElapsedRealtimeNs / 1_000L
        return if (now > lastPtsUs) now else lastPtsUs + 1L
    }
}
