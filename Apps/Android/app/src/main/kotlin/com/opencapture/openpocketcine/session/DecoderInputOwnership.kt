package com.opencapture.openpocketcine.session

/** Source ownership checked under the same lock as decoder state mutation. */
internal class DecoderInputOwnership(private val decoderLock: Any) {
    data class Token(val owner: Long, val epoch: Long)
    private var owner = 0L
    private var epoch = 0L

    fun capture(): Token = synchronized(decoderLock) { Token(owner, epoch) }

    fun claim(): Long = synchronized(decoderLock) {
        owner += 1
        epoch = 0
        owner
    }

    fun advance(inputOwner: Long, nextEpoch: Long) {
        synchronized(decoderLock) {
            if (inputOwner == owner && nextEpoch >= epoch) epoch = nextEpoch
        }
    }

    fun invalidate() {
        synchronized(decoderLock) {
            owner += 1
            epoch = 0
        }
    }

    fun <T> withCurrent(inputOwner: Long, inputEpoch: Long, rejected: T, mutation: () -> T): T =
        synchronized(decoderLock) {
            if (inputOwner != owner || inputEpoch != epoch) rejected else mutation()
        }
}
