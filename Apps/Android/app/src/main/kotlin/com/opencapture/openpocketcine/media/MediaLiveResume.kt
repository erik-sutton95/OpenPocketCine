package com.opencapture.openpocketcine.media

/**
 * Leave camera playback and bring live view back — Mimo's "Back to live view".
 *
 * `0x02/0x0c` `01 01 00 00` exits playback. Enable (`0x09/0xa8`) while still in
 * playback ACKs `E0`/`D6` and produces no video. Keep exiting until the
 * `0x02/0x80` playback bit clears, then enable.
 */
object MediaLiveResume {
    const val MAX_EXIT_ATTEMPTS = 8

    enum class Action {
        EXIT_PLAYBACK,
        ENABLE_LIVE_VIEW,
        DONE,
    }

    fun action(
        attempt: Int,
        inPlayback: Boolean,
        exitAcknowledged: Boolean,
        pictureFresh: Boolean,
    ): Action {
        if (pictureFresh && !inPlayback) return Action.DONE
        if (attempt > MAX_EXIT_ATTEMPTS) {
            return if (pictureFresh) Action.DONE else Action.ENABLE_LIVE_VIEW
        }
        if (inPlayback || !exitAcknowledged) return Action.EXIT_PLAYBACK
        return Action.ENABLE_LIVE_VIEW
    }

    fun strayPlaybackAction(browsing: Boolean, inPlayback: Boolean): Action? {
        if (browsing || !inPlayback) return null
        return Action.EXIT_PLAYBACK
    }
}
