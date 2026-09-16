package com.opencapture.openpocketcine.session

/**
 * One in-flight ML Kit face task. Watchdog and completion both [take] this
 * id; the loser must not deliver boxes. Only the completion listener recycles.
 */
internal class FaceDetectFlight {
    private var seq = 0

    fun begin(): Int {
        seq += 1
        return seq
    }

    fun take(id: Int): Boolean {
        if (seq != id) return false
        seq += 1
        return true
    }

    fun invalidate() {
        seq += 1
    }
}
