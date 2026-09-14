package com.opencapture.openpocketcine.session

internal enum class DecoderErrorOrigin(val wire: String) {
    CONFIGURE("configure"),
    QUEUE("queue"),
    OUTPUT("output"),
    OUTPUT_RELEASE("outputRelease"),
}

/**
 * Typed decoder failure for one codec generation. Reset with the decoder so a
 * previous lifetime cannot mark the next one wedged.
 */
internal data class DecoderErrorRecord(
    val origin: DecoderErrorOrigin,
    val code: String,
    val generation: Int,
    val formatGeneration: Int,
    val codec: String?,
    val width: Int,
    val height: Int,
    val inputIsIrap: Boolean?,
    val lastOutputAgeMs: Long?,
    val atElapsedMs: Long,
) {
    fun journalLine(): String =
        "decoder error origin=${origin.wire} code=$code gen=$generation fmt=$formatGeneration " +
            "codec=${codec ?: "none"} ${width}x$height irap=${
                when (inputIsIrap) {
                    true -> 1
                    false -> 0
                    null -> -1
                }
            } outAge=${lastOutputAgeMs ?: -1}ms"
}

internal class DecoderErrorLifetime {
    var generation: Int = 0
        private set
    var formatGeneration: Int = 0
        private set
    var lastError: DecoderErrorRecord? = null
        private set
    var countThisGeneration: Int = 0
        private set
    private var lastJournaledClass: String? = null
    private var lastJournaledAtMs: Long = Long.MIN_VALUE / 2

    val failedThisGeneration: Boolean
        get() = lastError != null

    fun resetLifetime() {
        generation += 1
        lastError = null
        countThisGeneration = 0
        lastJournaledClass = null
        lastJournaledAtMs = Long.MIN_VALUE / 2
    }

    fun bumpFormatGeneration() {
        formatGeneration += 1
    }

    /**
     * Record the error. Returns a journalable copy for the first error and for
     * a class change immediately, then at most once per second for repeats.
     */
    fun note(record: DecoderErrorRecord, nowMs: Long): DecoderErrorRecord? {
        lastError = record
        countThisGeneration += 1
        val key = "${record.origin.wire}:${record.code}"
        val firstOrChanged = lastJournaledClass != key
        val due = nowMs - lastJournaledAtMs >= 1_000L
        if (!firstOrChanged && !due) return null
        lastJournaledClass = key
        lastJournaledAtMs = nowMs
        return record
    }
}
