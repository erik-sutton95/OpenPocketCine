package com.opencapture.openpocketcine.session

/**
 * Bounded compressed-AU admission matching iOS `SoftAPVideoAssembler` overflow.
 * After any compressed loss, dependent P-frames are discarded until random
 * access. Parameter/key AUs may be retained. This is not a PLI owner.
 */
internal class CompressedAccessUnitAdmission(
    private val maxPending: Int = MAX_PENDING,
    private val maxBytes: Int = MAX_BYTES,
) {
    data class Delivery(
        val accessUnits: List<ByteArray>,
        val discontinuity: Boolean,
        val dropped: Int,
    )

    private val lock = Any()
    private val pending = ArrayDeque<ByteArray>()
    private var pendingBytes = 0
    private var awaitingRandomAccess = false
    private var discontinuity = false
    private var hopScheduled = false
    var drops: Int = 0
        private set
    var peakCount: Int = 0
        private set
    var peakBytes: Int = 0
        private set

    val pendingCount: Int get() = synchronized(lock) { pending.size }
    val queuedBytes: Int get() = synchronized(lock) { pendingBytes }

    fun noteIncompleteLoss(): Boolean =
        synchronized(lock) {
            if (pending.isNotEmpty()) {
                drops += pending.size
                pending.clear()
                pendingBytes = 0
            }
            awaitingRandomAccess = true
            discontinuity = true
            scheduleHopLocked()
        }

    fun offer(accessUnit: ByteArray): Boolean =
        synchronized(lock) {
            val irap = hasRandomAccess(accessUnit)
            val key = carriesKeyframe(accessUnit)
            if (irap) awaitingRandomAccess = false
            if (!awaitingRandomAccess || key) {
                pending.addLast(accessUnit)
                pendingBytes += accessUnit.size
            } else {
                drops += 1
            }
            if (pending.size > maxPending || pendingBytes > maxBytes) {
                trimOverflowLocked()
                discontinuity = true
            }
            peakCount = maxOf(peakCount, pending.size)
            peakBytes = maxOf(peakBytes, pendingBytes)
            scheduleHopLocked()
        }

    fun takeDelivery(): Delivery =
        synchronized(lock) {
            hopScheduled = false
            val dropped = 0
            val aus = pending.toList()
            pending.clear()
            pendingBytes = 0
            val disc = discontinuity
            discontinuity = false
            Delivery(aus, disc, dropped)
        }

    fun reset() {
        synchronized(lock) {
            pending.clear()
            pendingBytes = 0
            awaitingRandomAccess = false
            discontinuity = false
            hopScheduled = false
            drops = 0
            peakCount = 0
            peakBytes = 0
        }
    }

    /** Executor rejected the drain; allow a later offer to schedule again. */
    fun releaseScheduledHop() {
        synchronized(lock) { hopScheduled = false }
    }

    private fun scheduleHopLocked(): Boolean {
        if (hopScheduled) return false
        if (pending.isEmpty() && !discontinuity) return false
        hopScheduled = true
        return true
    }

    private fun trimOverflowLocked() {
        val lastIrap = pending.indexOfLast { hasRandomAccess(it) }
        val suffixCount = if (lastIrap >= 0) pending.size - lastIrap else Int.MAX_VALUE
        val suffixBytes =
            if (lastIrap >= 0) pending.drop(lastIrap).sumOf { it.size } else Int.MAX_VALUE
        if (lastIrap >= 0 && suffixCount <= maxPending && suffixBytes <= maxBytes) {
            repeat(lastIrap) {
                val removed = pending.removeFirst()
                pendingBytes -= removed.size
                drops += 1
            }
            return
        }
        val retained = pending.lastOrNull { it.size <= maxBytes && carriesKeyframe(it) }
        drops += pending.size - if (retained == null) 0 else 1
        pending.clear()
        pendingBytes = 0
        if (retained != null) {
            pending.addLast(retained)
            pendingBytes = retained.size
        }
        awaitingRandomAccess = true
    }

    companion object {
        const val MAX_PENDING = 8
        // Admit a maximum-sized protocol AU, but never an unbounded keyframe.
        const val MAX_BYTES = 4 * 1024 * 1024

        internal fun hasRandomAccess(accessUnit: ByteArray): Boolean =
            HevcDecoder.isIdrPicture("", accessUnit)

        internal fun carriesKeyframe(accessUnit: ByteArray): Boolean =
            hasRandomAccess(accessUnit) || HevcDecoder.parameterSetNals(accessUnit).isNotEmpty()
    }
}
