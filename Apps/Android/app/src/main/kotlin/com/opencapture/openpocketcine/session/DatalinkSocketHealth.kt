package com.opencapture.openpocketcine.session

import java.util.concurrent.atomic.AtomicBoolean

/** Sending locally cannot prove a terminated UDP receiver is alive again. */
internal class DatalinkSocketHealth {
    private val writeRejected = AtomicBoolean(false)
    private val receiverFailed = AtomicBoolean(false)
    val needsRebuild: Boolean get() = receiverFailed.get() || writeRejected.get()
    fun noteWriteSucceeded() { writeRejected.set(false) }
    fun noteWriteRejected() { writeRejected.set(true) }
    fun noteReceiverFailed() { receiverFailed.set(true) }
    fun noteReceiverStarted() { receiverFailed.set(false); writeRejected.set(false) }
}
