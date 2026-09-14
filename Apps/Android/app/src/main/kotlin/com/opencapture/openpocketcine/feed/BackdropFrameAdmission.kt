package com.opencapture.openpocketcine.feed

/** Admission is retained across visibility, source and look changes, including unfinished jobs. */
internal class BackdropFrameAdmission {
    class Ticket internal constructor(val producer: Any, val epoch: Long)
    private var producer: Any? = null
    private var active = false
    private var epoch = 0L
    private var busy: Ticket? = null
    private var lastCaptureNs: Long? = null

    @Synchronized fun attach(value: Any) { producer = value; epoch += 1 }
    @Synchronized fun setActive(value: Boolean) { if (active != value) { active = value; epoch += 1 } }
    @Synchronized fun invalidate(value: Any): Boolean {
        if (producer !== value) return false
        epoch += 1; return true
    }
    @Synchronized fun owns(value: Any): Boolean = producer === value
    @Synchronized fun invalidateAll() { epoch += 1 }
    @Synchronized fun generation(): Long = epoch
    @Synchronized fun hasDemand(value: Any): Boolean = active && producer === value
    @Synchronized fun acquire(value: Any, nowNs: Long, thermal: Double): Ticket? {
        if (!hasDemand(value) || busy != null) return null
        val interval = com.opencapture.monitorui.MonitorBackdropPolicy.intervalNs(thermal)
        if (lastCaptureNs?.let { nowNs - it < interval } == true) return null
        return Ticket(value, epoch).also { busy = it; lastCaptureNs = nowNs }
    }
    @Synchronized fun isCurrent(ticket: Ticket): Boolean = hasDemand(ticket.producer) && epoch == ticket.epoch
    @Synchronized fun complete(ticket: Ticket) { if (busy === ticket) busy = null }
}
