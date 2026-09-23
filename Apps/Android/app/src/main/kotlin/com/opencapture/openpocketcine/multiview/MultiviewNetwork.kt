package com.opencapture.openpocketcine.multiview

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Handler
import android.os.Looper
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.session.BleLink
import com.opencapture.openpocketcine.session.CameraNetworkPath
import com.opencapture.openpocketcine.session.DumlFrame
import com.opencapture.openpocketcine.session.FoundCamera
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import kotlin.coroutines.resume

/**
 * The operator's shared IPv4 path. iOS `SharedWiFiPath` plus the host join that
 * `NEHotspotConfiguration` performs there. Local Wi-Fi sockets are bound to the
 * Wi-Fi [Network]; Android otherwise routes LAN traffic over cellular when the
 * Wi-Fi has no internet. The phone's own hotspot uses its tethering interface.
 */
class SharedWiFi(context: Context) : CameraNetworkPath {
    private val app = context.applicationContext
    private val connectivity = app.getSystemService(ConnectivityManager::class.java)
    private val wifi = app.getSystemService(WifiManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var requested: Network? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    @Volatile var hotspot = false

    /** Current station SSID, or null when unknown (location off or not on Wi-Fi). */
    @Suppress("DEPRECATION")
    fun currentSsid(): String? {
        val raw = runCatching { wifi?.connectionInfo?.ssid }.getOrNull() ?: return null
        val name = raw.removeSurrounding("\"")
        return name.takeIf { it.isNotEmpty() && it != "<unknown ssid>" }
    }

    fun address(hotspot: Boolean = this.hotspot): String? = ipv4(hotspot)?.first

    fun netmask(hotspot: Boolean = this.hotspot): String? = ipv4(hotspot)?.second?.let(::mask)

    /** Local Wi-Fi only; the hosting phone never joins its own hotspot. */
    suspend fun join(ssid: String, password: String): Boolean {
        if (hotspot) return true
        if (currentSsid() == ssid && address(false) != null) return true
        release()
        val builder = WifiNetworkSpecifier.Builder().setSsid(ssid)
        if (password.isNotEmpty()) builder.setWpa2Passphrase(password)
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(builder.build())
            .build()
        DiagnosticCenter.log("info", "multiview", "wifi", "multiview: request shared Wi-Fi")
        val network = withTimeoutOrNull(JOIN_TIMEOUT_MS + 5_000L) {
            suspendCancellableCoroutine<Network?> { continuation ->
                val networkCallback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        synchronized(lock) { requested = network }
                        if (continuation.isActive) continuation.resume(network)
                    }

                    override fun onUnavailable() {
                        if (continuation.isActive) continuation.resume(null)
                    }

                    override fun onLost(network: Network) {
                        synchronized(lock) { if (requested == network) requested = null }
                    }
                }
                synchronized(lock) { callback = networkCallback }
                runCatching {
                    connectivity?.requestNetwork(request, networkCallback, main, JOIN_TIMEOUT_MS)
                }.onFailure { if (continuation.isActive) continuation.resume(null) }
                continuation.invokeOnCancellation { release() }
            }
        }
        if (network == null) {
            release()
            return false
        }
        repeat(60) {
            if (address(false) != null) return true
            delay(200)
        }
        return address(false) != null
    }

    fun release() {
        val registered = synchronized(lock) {
            val current = callback
            callback = null
            requested = null
            current
        }
        registered?.let { runCatching { connectivity?.unregisterNetworkCallback(it) } }
    }

    override fun bindSocket(socket: DatagramSocket) {
        if (!hotspot) wifiNetwork()?.let { runCatching { it.bindSocket(socket) } }
    }

    override fun bindSocket(socket: Socket) {
        if (!hotspot) wifiNetwork()?.let { runCatching { it.bindSocket(socket) } }
    }

    override fun isProcessBound(): Boolean = address() != null

    override fun cameraLocalIPv4(): String? = address()

    @Suppress("DEPRECATION")
    private fun wifiNetwork(): Network? {
        synchronized(lock) { requested }?.let { return it }
        val manager = connectivity ?: return null
        return manager.allNetworks.firstOrNull { network ->
            val caps = manager.getNetworkCapabilities(network) ?: return@firstOrNull false
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                manager.getLinkProperties(network)?.linkAddresses?.any { it.address is Inet4Address } == true
        }
    }

    private fun wifiInterface(): String? =
        wifiNetwork()?.let { connectivity?.getLinkProperties(it)?.interfaceName }

    /** Address and prefix length of the selected path. */
    private fun ipv4(hotspot: Boolean): Pair<String, Int>? {
        if (!hotspot) {
            val network = wifiNetwork() ?: return null
            val link = connectivity?.getLinkProperties(network)?.linkAddresses
                ?.firstOrNull { it.address is Inet4Address } ?: return null
            return link.address.hostAddress?.let { it to link.prefixLength }
        }
        val station = wifiInterface()
        val interfaces = runCatching { NetworkInterface.getNetworkInterfaces()?.toList() }.getOrNull() ?: return null
        // ponytail: tethering interface names are vendor-specific (Samsung swlan0,
        // AOSP ap0/wlan1). Extend the prefix list when a device reports another.
        for (item in interfaces) {
            val name = item.name ?: continue
            if (name == station || !runCatching { item.isUp }.getOrDefault(false)) continue
            if (HOTSPOT_PREFIXES.none { name.startsWith(it) }) continue
            val address = item.interfaceAddresses.firstOrNull { it.address is Inet4Address } ?: continue
            val host = address.address.hostAddress ?: continue
            return host to address.networkPrefixLength.toInt()
        }
        return null
    }

    companion object {
        private const val JOIN_TIMEOUT_MS = 45_000
        private val HOTSPOT_PREFIXES = listOf("swlan", "ap", "softap", "wlan1", "wigig")

        fun mask(prefix: Int): String {
            val bits = if (prefix <= 0) 0L else (0xFFFFFFFFL shl (32 - prefix.coerceAtMost(32))) and 0xFFFFFFFFL
            return listOf(24, 16, 8, 0).joinToString(".") { ((bits shr it) and 0xFF).toString() }
        }

        /** iOS `SharedWiFiPath.validAddress`: unicast IPv4, not loopback. */
        fun validAddress(value: String): Boolean {
            val parts = value.split(".")
            if (parts.size != 4) return false
            val bytes = parts.map { it.toIntOrNull() ?: return false }
            if (bytes.any { it !in 0..255 }) return false
            return bytes[0] in 1..223 && bytes[0] != 127
        }
    }
}

/** Service candidates only. The session verifies the BLE identity before preview. */
class MultiviewDiscovery(private val path: SharedWiFi) {
    @Volatile private var cancelled = false
    fun cancel() { cancelled = true }

    suspend fun candidates(excluding: Set<String>): List<String> {
        val address = path.address() ?: throw UnsupportedSubnet()
        val mask = path.netmask() ?: throw UnsupportedSubnet()
        val request = JSONObject().put("address", address).put("mask", mask)
            .put("excluding", excluding.joinToString(",")).toString()
        val reply = SwiftCore.multicamDecision("discoveryHosts", request)
        if (reply == null || reply == "unsupported") throw UnsupportedSubnet()
        val hosts = reply.split(",").filter { it.isNotEmpty() }
        val found = mutableListOf<String>()
        for (batch in hosts.chunked(BATCH)) {
            currentCoroutineContext().ensureActive()
            if (cancelled) throw kotlinx.coroutines.CancellationException("discovery cancelled")
            found += coroutineScope {
                batch.map { host -> async(Dispatchers.IO) { if (probe(host, address)) host else null } }.awaitAll()
            }.filterNotNull()
            if (found.size >= MAX_CANDIDATES) break
        }
        return found.take(MAX_CANDIDATES)
    }

    private fun probe(host: String, local: String): Boolean {
        if (cancelled) return false
        return runCatching {
            Socket().use { socket ->
                path.bindSocket(socket)
                if (path.hotspot) socket.bind(InetSocketAddress(local, 0))
                socket.connect(InetSocketAddress(host, 7001), PROBE_MS)
                true
            }
        }.getOrDefault(false)
    }

    class UnsupportedSubnet :
        Exception("Automatic discovery needs a shared IPv4 network with at most 1,022 device addresses.")

    private companion object {
        const val BATCH = 24
        const val MAX_CANDIDATES = 8
        const val PROBE_MS = 800
    }
}

/** One camera owns one BLE link, sequence space, reply router and keepalive. iOS `MultiviewProvisioner`. */
class MultiviewProvisioner(context: Context) {
    private val ble = BleLink(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val replies = HashMap<Int, DumlFrame>()
    private var router: Job? = null
    private var keepalive: Job? = null
    private var sequence = 1200
    private var approved = false
    @Volatile private var closed = false

    /** Reported Wi-Fi networks from a `07/AC` scan result. */
    var onWiFiScan: ((List<String>) -> Unit)? = null

    fun next(): Int {
        sequence = (sequence + 1) and 0xFFFF
        return sequence
    }

    fun send(kind: Int, extra: String? = null): Int {
        val seq = next()
        if (!closed) ble.send(SwiftCore.command(kind, seq, extra))
        return seq
    }

    suspend fun exchange(kind: Int, extra: String? = null, timeoutMs: Long = 12_000): DumlFrame {
        if (closed) throw kotlinx.coroutines.CancellationException("provisioner closed")
        val seq = next()
        val bytes = SwiftCore.command(kind, seq, extra)
        require(bytes.size > 10) { "command not encoded" }
        val cmdSet = bytes[9].toInt() and 0xFF
        val cmdId = bytes[10].toInt() and 0xFF
        replies.remove(seq)
        ble.send(bytes)
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (closed) throw kotlinx.coroutines.CancellationException("provisioner closed")
            val reply = replies.remove(seq)
            if (reply != null && reply.cmdSet == cmdSet && reply.cmdId == cmdId) return reply
            delay(50)
        }
        android.util.Log.i(
            "Multiview",
            "multiview: BLE ${"%02x".format(cmdSet)}/${"%02x".format(cmdId)} seq=$seq reply timeout",
        )
        throw MultiviewFailure.Timeout()
    }

    suspend fun connect(camera: FoundCamera, pairingTimeoutMs: Long = 90_000) {
        val powerDeadline = System.currentTimeMillis() + 8_000
        while (!ble.radioOn.value && System.currentTimeMillis() < powerDeadline) {
            if (closed) throw kotlinx.coroutines.CancellationException("provisioner closed")
            delay(100)
        }
        if (!ble.radioOn.value) throw MultiviewFailure.Unavailable()
        if (closed) throw kotlinx.coroutines.CancellationException("provisioner closed")
        try {
            ble.connect(camera)
        } catch (error: kotlinx.coroutines.CancellationException) {
            throw error
        } catch (error: Exception) {
            android.util.Log.i("Multiview", "multiview: BLE connect failed ${error.javaClass.simpleName}: ${error.message}")
            throw MultiviewFailure.Unavailable()
        }
        if (closed) throw kotlinx.coroutines.CancellationException("provisioner closed")
        router = scope.launch {
            ble.frames.collect { frame ->
                if (closed) return@collect
                android.util.Log.d(
                    "Multiview",
                    "ble frame ${"%02x".format(frame.cmdSet)}/${"%02x".format(frame.cmdId)} " +
                        "seq=${frame.seq} flags=${"%02x".format(frame.flags)} bytes=${frame.payload.size}",
                )
                if (frame.cmdSet == 0x07 && frame.cmdId == 0xAC && frame.sender == 0x07) {
                    val names = SwiftCore.multicamDecision(
                        "wifiScanNames", JSONObject().put("payload", hex(frame.payload)).toString())
                    onWiFiScan?.invoke(names.orEmpty().split('\u001f').filter { it.isNotEmpty() })
                }
                if (frame.cmdSet == 0x07 && frame.cmdId == 0x46 && (frame.flags and 0x80) == 0) {
                    ble.send(SwiftCore.command(SwiftCore.CMD_PAIR_APPROVAL_ACK, frame.seq))
                    approved = true
                } else if ((frame.flags and 0x80) != 0) {
                    if (replies.size > 128) replies.clear()
                    replies[frame.seq] = frame
                }
            }
        }
        send(SwiftCore.CMD_SESSION_WAKE)
        val pair = send(SwiftCore.CMD_SET_PAIRING_PIN, camera.model.pairingToken)
        val deadline = System.currentTimeMillis() + pairingTimeoutMs
        while (!approved && System.currentTimeMillis() < deadline) {
            if (closed) throw kotlinx.coroutines.CancellationException("provisioner closed")
            replies.remove(pair)?.let { response ->
                val payload = response.payload.map { it.toInt() and 0xFF }
                if (payload == listOf(0, 1)) approved = true
                else if (payload != listOf(0, 2)) throw MultiviewFailure.Rejected()
            }
            if (!approved) delay(100)
        }
        if (!approved) throw MultiviewFailure.Timeout()
        keepalive = scope.launch {
            while (!closed) {
                send(SwiftCore.CMD_SESSION_KEEPALIVE)
                delay(1_000)
            }
        }
    }

    fun close() {
        if (closed) return
        closed = true
        keepalive?.cancel()
        router?.cancel()
        scope.cancel()
        replies.clear()
        // BleLink owns a HandlerThread and a radio receiver; close() also disconnects.
        ble.close()
    }
}

/** iOS `MultiviewSession.Failure`. */
sealed class MultiviewFailure(message: String) : Exception(message) {
    class Timeout : MultiviewFailure("Camera did not respond. Close other camera apps and try again.")
    class Unavailable : MultiviewFailure("Camera is not nearby. Check that it is powered on.")
    class Rejected : MultiviewFailure("Camera could not complete this step. Check the Wi-Fi details and try again.")
    class Network : MultiviewFailure("Join the shared Wi-Fi network on this device first.")
    class Message(text: String) : MultiviewFailure(text)
}
