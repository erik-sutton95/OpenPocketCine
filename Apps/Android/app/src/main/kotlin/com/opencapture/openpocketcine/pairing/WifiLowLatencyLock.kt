package com.opencapture.openpocketcine.pairing

import android.annotation.SuppressLint
import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log

/**
 * Holds Wi-Fi in low-latency mode while a wireless camera session is live.
 *
 * Ported from OpenZCine `WifiLowLatencyLock`. Live view is a strict request /
 * response pull; Wi-Fi power save is built for bursty traffic, so between
 * frames the radio dozes and every packet pays a wake. `WIFI_MODE_FULL_LOW_LATENCY`
 * is the platform mode for this case. It only applies in the foreground.
 */
class WifiLowLatencyLock(context: Context) {
    private val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
    private var lock: WifiManager.WifiLock? = null

    @SuppressLint("MissingPermission")
    fun acquire() {
        if (lock?.isHeld == true) return
        val manager = wifi ?: return
        val held =
            runCatching {
                    manager
                        .createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, TAG)
                        .apply {
                            setReferenceCounted(false)
                            acquire()
                        }
                }
                .onFailure { Log.w(TAG, "wifi low-latency lock unavailable: ${it.message}") }
                .getOrNull()
        lock = held
        if (held?.isHeld == true) Log.i(TAG, "wifi low-latency lock held")
    }

    @SuppressLint("MissingPermission")
    fun release() {
        val current = lock ?: return
        lock = null
        runCatching { if (current.isHeld) current.release() }
            .onFailure { Log.w(TAG, "wifi lock release failed: ${it.message}") }
    }

    private companion object {
        const val TAG = "opc:live-view"
    }
}
