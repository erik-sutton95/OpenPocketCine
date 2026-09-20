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
        WAIT_FOR_PICTURE,
        DONE,
        EXHAUSTED,
    }

    fun action(
        attempt: Int,
        inPlayback: Boolean,
        exitAcknowledged: Boolean,
        pictureFresh: Boolean,
        enableSent: Boolean = false,
        deadlineExpired: Boolean = false,
    ): Action {
        if (pictureFresh && !inPlayback) return Action.DONE
        if (deadlineExpired) return Action.EXHAUSTED
        if (inPlayback || !exitAcknowledged) {
            return if (attempt > MAX_EXIT_ATTEMPTS) Action.EXHAUSTED else Action.EXIT_PLAYBACK
        }
        if (enableSent) return Action.WAIT_FOR_PICTURE
        return Action.ENABLE_LIVE_VIEW
    }

    fun strayPlaybackAction(browsing: Boolean, inPlayback: Boolean): Action? {
        if (browsing || !inPlayback) return null
        return Action.EXIT_PLAYBACK
    }

    /**
     * Leftover GOP packets are not a live picture. Resume is done only when a
     * frame presented after the resume started.
     */
    fun isPictureFresh(lastPresentedAt: Long?, since: Long): Boolean =
        lastPresentedAt != null && lastPresentedAt >= since

    fun isCurrentPictureOwner(generation: Long, currentGeneration: Long, browsing: Boolean): Boolean =
        generation == currentGeneration && !browsing
}

/** The production media-return loop; the session claims its one repair slot before calling. */
internal object MediaLiveResumeRunner {
    enum class Result { RESTORED, EXHAUSTED, SUPERSEDED }

    /** Link absence during an existing negotiation is not loss of the media-return owner. */
    suspend fun awaitRepairSlot(
        isCurrent: () -> Boolean,
        repairBusy: () -> Boolean,
        sleep: suspend (Long) -> Unit = { kotlinx.coroutines.delay(it) },
    ): Boolean {
        while (isCurrent() && repairBusy()) sleep(100)
        return isCurrent()
    }

    suspend fun run(
        timeoutMs: Long,
        nowMs: () -> Long,
        isCurrent: () -> Boolean,
        inPlayback: () -> Boolean,
        pictureFresh: () -> Boolean,
        exitPlayback: suspend () -> Boolean,
        enableLiveView: () -> Boolean,
        sleep: suspend (Long) -> Unit = { kotlinx.coroutines.delay(it) },
    ): Result {
        val startedAt = nowMs()
        var attempt = 1
        var exitAcked = false
        var enableSent = false
        while (isCurrent()) {
            when (MediaLiveResume.action(attempt, inPlayback(), exitAcked, pictureFresh(),
                    enableSent, nowMs() - startedAt >= timeoutMs)) {
                MediaLiveResume.Action.DONE -> return Result.RESTORED
                MediaLiveResume.Action.EXHAUSTED -> return Result.EXHAUSTED
                MediaLiveResume.Action.EXIT_PLAYBACK -> {
                    exitAcked = exitPlayback() || exitAcked
                    attempt += 1
                    sleep(180)
                }
                MediaLiveResume.Action.ENABLE_LIVE_VIEW -> {
                    enableSent = enableLiveView()
                    sleep(100)
                }
                MediaLiveResume.Action.WAIT_FOR_PICTURE -> sleep(100)
            }
        }
        return Result.SUPERSEDED
    }
}

/** What to do after `0x02/0x0c` enter-playback. Newest list page needs no playback. */
data class MediaBrowsePolicy(
    val listNewestPage: Boolean,
    val listOlderPages: Boolean,
    val keepBrowsing: Boolean,
) {
    companion object {
        /**
         * Newest `0x00/0x26` page needs no playback. Keep the browse flag so a
         * failed `0x02/0x0c` (Pocket 3 E0 after a take) cannot arm stray exit.
         */
        fun afterEnterPlayback(entered: Boolean): MediaBrowsePolicy =
            MediaBrowsePolicy(
                listNewestPage = true,
                listOlderPages = entered,
                keepBrowsing = true,
            )
    }
}
