package com.opencapture.openpocketcine.pairing

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Handler
import android.os.Looper
import java.net.DatagramSocket
import java.net.Socket
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Camera-AP Wi-Fi join via [WifiNetworkSpecifier] + [ConnectivityManager.bindProcessToNetwork].
 * Simplified from OpenZCine's joiner: Pocket has one SSID, no Nikon prefix fallback.
 */
class CameraApJoiner(context: Context) {
    private val appContext = context.applicationContext
    private val connectivity =
        appContext.getSystemService(ConnectivityManager::class.java)
            ?: error("ConnectivityManager unavailable")
    private val wifi = appContext.getSystemService(WifiManager::class.java)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var joinContinuation: CancellableContinuation<Boolean>? = null
    private var boundNetwork: Network? = null
    var onPathLost: (() -> Unit)? = null

    suspend fun join(
        ssid: String,
        passphrase: String,
        wpa3: Boolean,
        timeoutMillis: Int = 45_000,
    ): Boolean {
        val trimmed = ssid.trim()
        if (trimmed.isEmpty()) return false
        release()
        if (wifi != null && !wifi.isWifiEnabled) return false
        awaitCameraApVisibleInScan(trimmed, PRE_JOIN_SCAN_WAIT_MILLIS)
        return requestSpecifierNetwork(trimmed, passphrase, wpa3, timeoutMillis)
    }

    fun bindSocket(socket: DatagramSocket) {
        synchronized(lock) { boundNetwork }?.bindSocket(socket)
    }

    fun bindSocket(socket: Socket) {
        synchronized(lock) { boundNetwork }?.bindSocket(socket)
    }

    fun isProcessBound(): Boolean = synchronized(lock) { boundNetwork != null }

    fun release() {
        val toUnregister: ConnectivityManager.NetworkCallback?
        val pending: CancellableContinuation<Boolean>?
        synchronized(lock) {
            toUnregister = callback
            pending = joinContinuation
            callback = null
            joinContinuation = null
            boundNetwork = null
        }
        connectivity.bindProcessToNetwork(null)
        toUnregister?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
        if (pending?.isActive == true) pending.resume(false)
    }

    private suspend fun requestSpecifierNetwork(
        ssid: String,
        passphrase: String,
        wpa3: Boolean,
        timeoutMillis: Int,
    ): Boolean {
        val specifier =
            WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .apply {
                    if (passphrase.isNotEmpty()) {
                        if (wpa3) setWpa3Passphrase(passphrase) else setWpa2Passphrase(passphrase)
                    }
                }
                .build()
        val request =
            NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()
        return suspendCancellableCoroutine { continuation ->
            val networkCallback =
                object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        val resumeNow =
                            synchronized(lock) {
                                if (callback !== this) return
                                boundNetwork = network
                                connectivity.bindProcessToNetwork(network)
                                val pending = joinContinuation
                                joinContinuation = null
                                pending
                            }
                        if (resumeNow?.isActive == true) resumeNow.resume(true)
                    }

                    override fun onUnavailable() {
                        val pending =
                            synchronized(lock) {
                                if (callback !== this) return
                                val wait = joinContinuation
                                joinContinuation = null
                                wait
                            }
                        if (pending?.isActive == true) pending.resume(false)
                    }

                    override fun onLost(network: Network) {
                        val notify =
                            synchronized(lock) {
                                if (callback !== this || boundNetwork != network) {
                                    false
                                } else {
                                    boundNetwork = null
                                    connectivity.bindProcessToNetwork(null)
                                    true
                                }
                            }
                        if (notify) onPathLost?.invoke()
                    }
                }
            synchronized(lock) {
                callback = networkCallback
                joinContinuation = continuation
            }
            mainHandler.post {
                if (!continuation.isActive) {
                    release()
                    return@post
                }
                try {
                    connectivity.requestNetwork(request, networkCallback, mainHandler, timeoutMillis)
                } catch (_: RuntimeException) {
                    val pending =
                        synchronized(lock) {
                            val wait = joinContinuation
                            joinContinuation = null
                            wait
                        }
                    if (pending?.isActive == true) pending.resume(false)
                }
            }
            continuation.invokeOnCancellation { release() }
        }
    }

    private suspend fun awaitCameraApVisibleInScan(ssid: String, maxWaitMillis: Long): Boolean {
        if (wifi == null || maxWaitMillis <= 0L) return false
        kickWifiScan()
        if (scanResultsContainSsid(ssid)) return true
        val deadline = System.nanoTime() + maxWaitMillis * 1_000_000L
        var lastScanKick = System.nanoTime()
        while (System.nanoTime() < deadline) {
            delay(350)
            if (scanResultsContainSsid(ssid)) return true
            if (System.nanoTime() - lastScanKick >= 1_500L * 1_000_000L) {
                kickWifiScan()
                lastScanKick = System.nanoTime()
            }
        }
        kickWifiScan()
        return scanResultsContainSsid(ssid)
    }

    private fun kickWifiScan() {
        val manager = wifi ?: return
        try {
            @Suppress("DEPRECATION")
            manager.startScan()
        } catch (_: SecurityException) {
        } catch (_: RuntimeException) {
        }
    }

    private fun scanResultsContainSsid(ssid: String): Boolean {
        val results =
            try {
                wifi?.scanResults
            } catch (_: SecurityException) {
                null
            } ?: return false
        val target = ssid.trim()
        if (target.isEmpty()) return false
        return results.any { result ->
            result.SSID?.trim()?.removeSurrounding("\"")?.equals(target, ignoreCase = true) == true
        }
    }

    private companion object {
        const val PRE_JOIN_SCAN_WAIT_MILLIS: Long = 8_000L
    }
}
