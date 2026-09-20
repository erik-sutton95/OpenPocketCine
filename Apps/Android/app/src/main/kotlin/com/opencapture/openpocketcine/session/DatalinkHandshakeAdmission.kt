package com.opencapture.openpocketcine.session

/** Evidence belonging to one UDP endpoint; the driver retains its bounded open lifetime. */
internal class DatalinkHandshakeAdmission {
    data class Evidence(val acknowledged: Boolean, val windowKnown: Boolean)

    private var epoch = 0L
    private var acknowledged = false
    private var window: Int? = null

    @Synchronized fun reset(epoch: Long) {
        if (epoch < this.epoch) return
        this.epoch = epoch
        acknowledged = false
        window = null
    }

    @Synchronized fun receive(bytes: ByteArray, epoch: Long) {
        if (epoch != this.epoch) return
        if (bytes.size >= 8 && bytes[6] == 0.toByte()) acknowledged = true
        // Mirrors MulticamCommands.controlSequence: a 15-byte ACK or a longer
        // status datagram is not evidence of the initial command window.
        // Zero and wraparound are valid, so absence is represented by null.
        if (window == null && bytes.size == 34 && bytes[6] == 1.toByte()) {
            window = (u16(bytes, 8) + 8) and 0xffff
        }
    }

    @Synchronized fun initialCommandSequence(): Int? = if (acknowledged) window else null

    @Synchronized fun evidence(): Evidence = Evidence(acknowledged, window != null)

    private fun u16(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)
}
