package com.opencapture.openpocketcine.feed

/** One retained sample, one job, and an epoch that makes late results harmless. */
internal class InspectorPreviewAdmission {
    class Ticket internal constructor(val owner: Any, val epoch: Long)
    private var owner: Any? = null
    private var playback = false
    private var epoch = 0L
    private var busy: Ticket? = null
    private var lastCaptureNs: Long? = null

    @Synchronized fun activate(nextOwner: Any, nextPlayback: Boolean) {
        owner = nextOwner
        playback = nextPlayback
        epoch += 1
    }

    @Synchronized fun invalidate(activeOwner: Any) {
        if (owner !== activeOwner) return
        epoch += 1
    }

    @Synchronized fun deactivate(activeOwner: Any) {
        if (owner !== activeOwner) return
        owner = null
        epoch += 1
        // Keep the old job busy until it finishes; opening another tool must
        // not create concurrent workers or queue another frame behind it.
    }

    @Synchronized fun acquire(activeOwner: Any?, sourcePlayback: Boolean, nowNs: Long): Ticket? {
        if (owner == null || owner !== activeOwner || playback != sourcePlayback || busy != null) return null
        if (lastCaptureNs?.let { nowNs - it < MIN_INTERVAL_NS } == true) return null
        return Ticket(checkNotNull(owner), epoch).also { busy = it; lastCaptureNs = nowNs }
    }

    @Synchronized fun isCurrent(ticket: Ticket): Boolean = owner === ticket.owner && epoch == ticket.epoch

    @Synchronized fun complete(ticket: Ticket) {
        if (busy === ticket) busy = null
    }

    companion object { const val MIN_INTERVAL_NS = 200_000_000L }
}

/** Top-to-bottom RGBA from the existing tap, fitted inside a 213 × 120 budget. */
internal data class InspectorPreviewFrame(val width: Int, val height: Int, val rgba: ByteArray) {
    init { require(width in 1..213 && height in 1..120 && rgba.size == width * height * 4) }

    companion object {
        fun fromTap(bytes: ByteArray, width: Int, height: Int, bottomUp: Boolean): InspectorPreviewFrame {
            require(width > 0 && height > 0 && bytes.size >= width.toLong() * height * 4)
            val scale = minOf(1.0, 213.0 / width, 120.0 / height)
            val w = (width * scale).toInt().coerceAtLeast(1)
            val h = (height * scale).toInt().coerceAtLeast(1)
            val output = ByteArray(w * h * 4)
            for (y in 0 until h) {
                val sourceY = y * height / h
                val row = if (bottomUp) height - 1 - sourceY else sourceY
                for (x in 0 until w) {
                    val src = (row * width + x * width / w) * 4
                    bytes.copyInto(output, (y * w + x) * 4, src, src + 4)
                }
            }
            return InspectorPreviewFrame(w, h, output)
        }
    }
}
