package com.opencapture.monitorui

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Exclusive readout pointer lease; a late cancellation cannot release a newer owner. */
@Stable
class MonitorQuickGestureOwner {
    data class Lease(val id: String, val revision: Long)
    private var revision = 0L
    private var lease: Lease? by mutableStateOf(null)
    val owner: String? get() = lease?.id
    var active: String? by mutableStateOf(null)
        private set

    fun acquire(id: String): Lease? {
        if (lease != null) return null
        return Lease(id, ++revision).also { lease = it }
    }

    fun setActive(token: Lease, value: Boolean) {
        if (lease == token) active = if (value) token.id else null
    }

    fun release(token: Lease) {
        if (lease != token) return
        active = null
        lease = null
    }
}
