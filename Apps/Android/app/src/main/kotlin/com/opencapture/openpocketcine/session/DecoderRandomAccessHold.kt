package com.opencapture.openpocketcine.session

/**
 * GOP hold for a MediaCodec lifetime. A surviving decoder that already queued
 * an IRAP may release the hold when inter frames resume. A newly created
 * decoder has no references — releasing it cannot recreate them.
 */
internal class DecoderRandomAccessHold {
    var generation: Int = 0
        private set
    var awaitingIdr: Boolean = false
        private set
    var hasDecodableReferences: Boolean = false
        private set
    var referenceRecoveryNeeded: Boolean = false
        private set

    fun shouldAccept(isIrap: Boolean): Boolean = !awaitingIdr || isIrap

    fun onNewDecoder() {
        generation += 1
        awaitingIdr = true
        hasDecodableReferences = false
    }

    fun onIrapAccepted() {
        hasDecodableReferences = true
        awaitingIdr = false
        referenceRecoveryNeeded = false
    }

    fun beginHold() {
        awaitingIdr = true
    }

    /** Incomplete / overflowed compressed AUs broke the GOP. Keep the last picture. */
    fun noteBrokenReferences() {
        // Startup and an intentional decoder replacement have no references
        // yet. Only a real discontinuity of an established chain fast-tracks
        // the existing watchdog; a pending loss survives its codec rebuild.
        referenceRecoveryNeeded = referenceRecoveryNeeded || hasDecodableReferences
        hasDecodableReferences = false
        awaitingIdr = true
    }

    fun endHold(): Boolean {
        if (!awaitingIdr) return false
        if (!hasDecodableReferences) return false
        awaitingIdr = false
        return true
    }

    fun reset() {
        generation += 1
        awaitingIdr = false
        hasDecodableReferences = false
        referenceRecoveryNeeded = false
    }

    /** Test seam: a configured decoder that already acquired random access. */
    fun adoptDecodableReferencesForTest() {
        hasDecodableReferences = true
    }
}

internal object AccessUnitDiscontinuity {
    fun shouldNote(previousDropped: Int, currentDropped: Int): Boolean =
        currentDropped > previousDropped
}
