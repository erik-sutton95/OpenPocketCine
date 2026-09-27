package com.opencapture.openpocketcine.session

/** One popup tab's permission to use an existing camera endpoint. Never owns feed I/O. */
class MultiviewControlLease(
    private val isCurrent: () -> Boolean,
    private val onSet: (Long) -> Unit,
) {
    private var active = true
    fun allows(): Boolean = active && isCurrent()
    fun noteSet(at: Long) { if (allows()) onSet(at) }
    fun invalidate() { active = false }
}
