package com.opencapture.openpocketcine.session

/** Preparation only; cancellation propagates before any native program can start. */
internal suspend fun awaitMotionStartCountdown(pause: suspend () -> Unit, update: (Int?) -> Unit) {
    update(3)
    for (count in 2 downTo 1) {
        pause()
        update(count)
    }
    pause()
    update(null)
}
