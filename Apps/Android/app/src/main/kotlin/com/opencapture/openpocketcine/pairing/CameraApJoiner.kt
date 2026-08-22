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
import android.util.Log
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.Socket
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Camera-AP Wi-Fi join via [WifiNetworkSpecifier] + [ConnectivityManager.bindProcessToNetwork].
 * Pocket has one SSID (no Nikon prefix fallback). SoftAP `onLost` waits for
 * reassociation like OpenZCine — Android often replaces the Network object a
 * few seconds after join without the camera actually leaving.
 */
class CameraApJoiner(context: Context) {
    private val appContext = context.applicationContext
    private val connectivity =
        appContext.getSystemService(ConnectivityManager::class.java)
            ?: error("ConnectivityManager unavailable")
    private val wifi = appContext.getSystemService(WifiManager::class.java)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val availability = CameraApAvailabilityTracker<Network>()
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var joinContinuation: CancellableContinuation<Boolean>? = null
    private var boundNetwork: Network? = null
    private var reassociationGrace: Runnable? = null
    var onPathLost: (() -> Unit)? = null
    /** SoftAP Network object replaced; UDP must rebind. Session stays LIVE. */
    var onReassociated: (() -> Unit)? = null

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
        awaitCameraApVisibleInScan(trimmed, PRE_JOIN_SCAN_WAIT_MILLIS, requireVisible = false)
        return requestSpecifierNetwork(trimmed, passphrase, wpa3, timeoutMillis)
    }

    fun bindSocket(socket: DatagramSocket) {
        val network = synchronized(lock) { boundNetwork } ?: return
        runCatching { network.bindSocket(socket) }
            .onFailure { Log.w(TAG, "wifi: UDP bindSocket failed", it) }
    }

    fun bindSocket(socket: Socket) {
        val network = synchronized(lock) { boundNetwork } ?: return
        runCatching { network.bindSocket(socket) }
            .onFailure { Log.w(TAG, "wifi: TCP bindSocket failed", it) }
    }

    fun isProcessBound(): Boolean =
        synchronized(lock) { boundNetwork != null }

    /**
     * Phone IPv4 on the camera AP (`192.168.2.2…254`). iOS
     * `WiFiJoiner.cameraLocalIPv4` / `CameraSoftAP.isAssociatedIPv4`.
     */
    fun cameraLocalIPv4(): String? {
        val network = synchronized(lock) { boundNetwork } ?: return null
        val props = connectivity.getLinkProperties(network) ?: return null
        return cameraLocalIPv4(
            props.linkAddresses.mapNotNull { addr ->
                (addr.address as? Inet4Address)?.hostAddress
            },
        )
    }

    fun release() {
        val toUnregister: ConnectivityManager.NetworkCallback?
        val pending: CancellableContinuation<Boolean>?
        synchronized(lock) {
            toUnregister = callback
            pending = joinContinuation
            callback = null
            joinContinuation = null
            boundNetwork = null
            availability.release()
            cancelReassociationGraceLocked()
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
                        handleAvailable(this, network)
                    }

                    override fun onUnavailable() {
                        val pending =
                            synchronized(lock) {
                                if (callback !== this) return
                                availability.onUnavailable()
                                cancelReassociationGraceLocked()
                                val wait = joinContinuation
                                joinContinuation = null
                                wait
                            }
                        if (pending?.isActive == true) pending.resume(false)
                    }

                    override fun onLost(network: Network) {
                        handleLost(this, network)
                    }
                }
            synchronized(lock) {
                availability.requestStarted()
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

    private suspend fun awaitCameraApVisibleInScan(
        ssid: String,
        maxWaitMillis: Long,
        requireVisible: Boolean,
    ): Boolean {
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
        if (requireVisible) kickWifiScan()
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

    private fun handleAvailable(
        expectedCallback: ConnectivityManager.NetworkCallback,
        network: Network,
    ) {
        val resumeNow: CancellableContinuation<Boolean>?
        val reassociated: Boolean
        synchronized(lock) {
            if (callback !== expectedCallback) return
            val result = availability.onAvailable(network)
            if (!result.shouldBind) return
            boundNetwork = network
            connectivity.bindProcessToNetwork(network)
            cancelReassociationGraceLocked()
            reassociated = result.reassociationGeneration != null
            val pending = joinContinuation.takeIf { availability.hasEstablishedNetwork() }
            joinContinuation = null
            resumeNow = pending
        }
        Log.i(TAG, "wifi: available $network reassoc=$reassociated")
        if (resumeNow?.isActive == true) resumeNow.resume(true)
        if (reassociated) onReassociated?.invoke()
    }

    private fun handleLost(
        expectedCallback: ConnectivityManager.NetworkCallback,
        network: Network,
    ) {
        val scheduleGrace: Boolean
        synchronized(lock) {
            if (callback !== expectedCallback) return
            if (!availability.onLost(network)) return
            if (boundNetwork == network) boundNetwork = null
            // Keep process bound to the SoftAP until grace expires so UDP
            // rebuild cannot leak onto home Wi-Fi (iOS pathLost ≠ default route).
            scheduleReassociationGraceLocked()
            scheduleGrace = true
        }
        if (scheduleGrace) Log.i(TAG, "wifi: lost $network — waiting for reassociation")
    }

    private fun scheduleReassociationGraceLocked() {
        cancelReassociationGraceLocked()
        val grace =
            Runnable {
                val expired =
                    synchronized(lock) {
                        reassociationGrace = null
                        boundNetwork == null && availability.hasEstablishedNetwork()
                    }
                if (expired) {
                    Log.i(TAG, "wifi: reassociation grace expired")
                    connectivity.bindProcessToNetwork(null)
                    onPathLost?.invoke()
                }
            }
        reassociationGrace = grace
        mainHandler.postDelayed(grace, REASSOCIATION_GRACE_MS)
    }

    private fun cancelReassociationGraceLocked() {
        reassociationGrace?.let { mainHandler.removeCallbacks(it) }
        reassociationGrace = null
    }

    companion object {
        private const val TAG = "CameraApJoiner"
        private const val PRE_JOIN_SCAN_WAIT_MILLIS: Long = 3_000L
        /** Samsung often replaces the SoftAP Network a few seconds after join. */
        private const val REASSOCIATION_GRACE_MS: Long = 8_000L

        /**
         * Phone address on the camera AP. `.1` is the camera; `.0` / `.255` are
         * not hosts. Matches `CameraSoftAP.isAssociatedIPv4` exactly.
         */
        fun isAssociatedIPv4(ip: String): Boolean {
            val parts = ip.split('.')
            if (parts.size != 4) return false
            if (parts[0] != "192" || parts[1] != "168" || parts[2] != "2") return false
            val host = parts[3].toIntOrNull() ?: return false
            return host in 2..254
        }

        fun cameraLocalIPv4(ipv4s: Iterable<String>): String? =
            ipv4s.firstOrNull { isAssociatedIPv4(it) }
    }
}

/**
 * OpenZCine `CameraApAvailabilityTracker`: duplicate `onAvailable` is ignored;
 * loss then a new network, or a replacement callback with no loss, is a
 * reassociation the live session must rebind onto instead of disconnecting.
 */
internal class CameraApAvailabilityTracker<NetworkToken : Any> {
    internal data class AvailableResult(
        val shouldBind: Boolean,
        val reassociationGeneration: Long?,
    )

    private var requestActive: Boolean = false
    private var activeNetwork: NetworkToken? = null
    private var hasEstablishedNetwork: Boolean = false
    private var awaitingReassociation: Boolean = false
    private var reassociationGeneration: Long = 0L

    fun requestStarted() {
        requestActive = true
        activeNetwork = null
        hasEstablishedNetwork = false
        awaitingReassociation = false
        reassociationGeneration = 0L
    }

    fun onAvailable(network: NetworkToken): AvailableResult {
        if (!requestActive) {
            return AvailableResult(shouldBind = false, reassociationGeneration = null)
        }
        val previousNetwork = activeNetwork
        if (previousNetwork == network) {
            return AvailableResult(shouldBind = false, reassociationGeneration = null)
        }
        val completedReassociation =
            hasEstablishedNetwork && (awaitingReassociation || previousNetwork != null)
        activeNetwork = network
        hasEstablishedNetwork = true
        awaitingReassociation = false
        val generation = if (completedReassociation) ++reassociationGeneration else null
        return AvailableResult(shouldBind = true, reassociationGeneration = generation)
    }

    fun onLost(network: NetworkToken): Boolean {
        if (activeNetwork != network) return false
        activeNetwork = null
        awaitingReassociation = true
        return true
    }

    fun onUnavailable() {
        requestActive = false
    }

    fun release() {
        requestActive = false
        activeNetwork = null
        hasEstablishedNetwork = false
        awaitingReassociation = false
        reassociationGeneration = 0L
    }

    fun nextReassociationGeneration(): Long? =
        if (requestActive && hasEstablishedNetwork) reassociationGeneration + 1L else null

    fun hasEstablishedNetwork(): Boolean = hasEstablishedNetwork
}
