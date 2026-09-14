package com.opencapture.openpocketcine.diagnostics

import io.sentry.Hint
import io.sentry.ITransportFactory
import io.sentry.RequestDetails
import io.sentry.SentryEnvelope
import io.sentry.SentryOptions
import io.sentry.transport.ITransport
import io.sentry.transport.ITransportGate
import io.sentry.transport.RateLimiter
import java.io.IOException
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.URI
import java.net.URL
import java.util.concurrent.CopyOnWriteArrayList

internal interface ReliabilityReportingCancellable {
    fun cancel()

    /** Manual operator reports keep transmitting after automatic-SDK opt-out. */
    val independentOfAutomaticConsent: Boolean
        get() = false
}

internal object ReliabilityReportingGate : ITransportGate {
    private val lock = Any()
    @Volatile private var cameraSessionActive = false
    @Volatile private var ipv4Override: Boolean? = null
    @Volatile private var validInternet = true
    @Volatile var extraCameraPathProbe: (() -> Boolean)? = null
    private val pending = CopyOnWriteArrayList<ReliabilityReportingCancellable>()

    val isCameraSessionActive: Boolean
        get() = synchronized(lock) { cameraSessionActive }

    /** Blocks SDK upload while a camera session is live or the camera IPv4 path is up. */
    val shouldBlockUpload: Boolean
        get() {
            val session = synchronized(lock) { cameraSessionActive }
            val ipv4 = ipv4Override ?: cameraIPv4PathReady()
            return session || ipv4
        }

    val hasValidInternet: Boolean
        get() = synchronized(lock) { validInternet }

    override fun isConnected(): Boolean =
        ReliabilityReportingConsent.isOptedIn && !shouldBlockUpload && hasValidInternet

    fun setCameraSessionActive(active: Boolean) {
        val toCancel = synchronized(lock) {
            cameraSessionActive = active
            if (active) {
                val copy = pending.toList()
                pending.clear()
                copy
            } else {
                emptyList()
            }
        }
        if (active) {
            for (task in toCancel) task.cancel()
        }
    }

    fun setCameraIPv4PathReadyForTests(ready: Boolean?) {
        synchronized(lock) { ipv4Override = ready }
        if (ready == true) cancelPending()
    }

    fun setValidInternetForTests(ready: Boolean) {
        synchronized(lock) { validInternet = ready }
    }

    fun register(task: ReliabilityReportingCancellable) {
        val blockNow = synchronized(lock) {
            pending.add(task)
            val cameraBlock = cameraSessionActive || cameraIPv4PathReady()
            val consentBlock =
                !task.independentOfAutomaticConsent && !ReliabilityReportingConsent.isOptedIn
            cameraBlock || consentBlock
        }
        if (blockNow) task.cancel()
    }

    fun unregister(task: ReliabilityReportingCancellable) {
        pending.remove(task)
    }

    fun cancelPending(includeIndependent: Boolean = true) {
        val toCancel = synchronized(lock) {
            val copy = pending.filter { includeIndependent || !it.independentOfAutomaticConsent }
            pending.removeAll(copy.toSet())
            copy
        }
        for (task in toCancel) task.cancel()
    }

    fun resetForTests() {
        ReliabilityReportingHostPolicy.requireHttps = true
        val toCancel = synchronized(lock) {
            cameraSessionActive = false
            ipv4Override = false
            validInternet = true
            extraCameraPathProbe = null
            val copy = pending.toList()
            pending.clear()
            copy
        }
        for (task in toCancel) task.cancel()
    }

    fun cameraIPv4PathReady(): Boolean {
        ipv4Override?.let { return it }
        if (extraCameraPathProbe?.invoke() == true) return true
        return hasAssociatedCameraIPv4()
    }

    fun hasAssociatedCameraIPv4(): Boolean {
        val ifaces = runCatching { NetworkInterface.getNetworkInterfaces() }.getOrNull() ?: return false
        for (iface in ifaces) {
            val addresses = runCatching { iface.inetAddresses }.getOrNull() ?: continue
            for (addr in addresses) {
                if (addr is Inet4Address) {
                    val host = addr.hostAddress ?: continue
                    if (host.startsWith("192.168.2.")) return true
                }
            }
        }
        return false
    }
}

internal object ReliabilityReportingHostPolicy {
    @Volatile var requireHttps: Boolean = true

    fun host(fromDSN: String): String? = runCatching { URI(fromDSN).host }.getOrNull()

    fun allows(url: URL?, dsnHost: String?): Boolean {
        if (url == null) return false
        val host = url.host
        if (host.isNullOrEmpty()) return false
        val scheme = url.protocol.lowercase()
        if (requireHttps && scheme != "https") return false
        if (!requireHttps && scheme != "https" && scheme != "http") return false
        if (dsnHost != null && host.equals(dsnHost, ignoreCase = true)) return true
        return false
    }
}

internal enum class ReliabilityReportingLoadDecision {
    FORWARD,
    BLOCK_CAMERA_PATH,
    REJECT_HOST,
    NO_INTERNET,
}

internal object ReliabilityReportingNetwork {
    fun decision(
        url: URL?,
        dsnHost: String?,
        gate: ReliabilityReportingGate = ReliabilityReportingGate,
    ): ReliabilityReportingLoadDecision {
        if (url == null) return ReliabilityReportingLoadDecision.REJECT_HOST
        if (gate.shouldBlockUpload) return ReliabilityReportingLoadDecision.BLOCK_CAMERA_PATH
        if (!ReliabilityReportingHostPolicy.allows(url, dsnHost)) {
            return ReliabilityReportingLoadDecision.REJECT_HOST
        }
        if (!gate.hasValidInternet) return ReliabilityReportingLoadDecision.NO_INTERNET
        return ReliabilityReportingLoadDecision.FORWARD
    }
}

internal class ReliabilityReportingTransportFactory : ITransportFactory {
    override fun create(options: SentryOptions, requestDetails: RequestDetails): ITransport {
        return ReliabilityReportingTransport(options, requestDetails)
    }
}

/**
 * Dedicated Sentry transport. Caches envelopes while the camera path is up, posts
 * only to the DSN host over OkHttp, and cancels in-flight calls when the camera
 * session starts or consent is revoked. HTTP 2xx is the only delivery confirmation.
 */
internal class ReliabilityReportingTransport(
    private val options: SentryOptions,
    private val requestDetails: RequestDetails,
    client: okhttp3.OkHttpClient? = null,
) : ITransport, ReliabilityReportingCancellable {
    private val http =
        client
            ?: okhttp3.OkHttpClient.Builder()
                .followRedirects(false)
                .followSslRedirects(false)
                .retryOnConnectionFailure(false)
                .connectTimeout(options.connectionTimeoutMillis.toLong(), java.util.concurrent.TimeUnit.MILLISECONDS)
                .readTimeout(options.readTimeoutMillis.toLong(), java.util.concurrent.TimeUnit.MILLISECONDS)
                .callTimeout(20, java.util.concurrent.TimeUnit.SECONDS)
                .build()
    private val executor =
        java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "opc.reliability.http").apply { isDaemon = true }
        }
    private val inflight = CopyOnWriteArrayList<okhttp3.Call>()
    private val closed = java.util.concurrent.atomic.AtomicBoolean(false)
    private val drainScheduled = java.util.concurrent.atomic.AtomicBoolean(false)
    private val pending = java.util.concurrent.ConcurrentHashMap<String, Pair<SentryEnvelope, Hint>>()
    private val limiter = RateLimiter(options)
    @Volatile private var nextAttemptAt = 0L
    private var failures = 0

    private fun finishHint(hint: Hint, success: Boolean) {
        val sdkHint = io.sentry.util.HintUtils.getSentrySdkHint(hint)
        (sdkHint as? io.sentry.hints.Retryable)?.setRetry(!success)
        (sdkHint as? io.sentry.hints.SubmissionResult)?.setResult(success)
    }

    private fun key(envelope: SentryEnvelope): String =
        envelope.header.eventId?.toString() ?: System.identityHashCode(envelope).toString()

    private fun scheduleDrain() {
        if (closed.get() || !drainScheduled.compareAndSet(false, true)) return
        try {
            executor.execute {
                try {
                    if (ReliabilityReportingGate.shouldBlockUpload ||
                        !ReliabilityReportingConsent.isOptedIn ||
                        System.currentTimeMillis() < nextAttemptAt || limiter.isAnyRateLimitActive
                    ) return@execute
                    // Reload disk on every idle flush, including native reports cached
                    // before the camera gate opened. Bound memory and queued work.
                    for (envelope in options.envelopeDiskCache.take(options.maxCacheItems)) {
                        if (pending.size >= options.maxCacheItems) break
                        pending.putIfAbsent(key(envelope), envelope to Hint())
                    }
                    for ((id, entry) in pending.entries.toList()) {
                        if (closed.get() || ReliabilityReportingGate.shouldBlockUpload ||
                            !ReliabilityReportingConsent.isOptedIn ||
                            System.currentTimeMillis() < nextAttemptAt || limiter.isAnyRateLimitActive
                        ) break
                        if (post(entry.first)) {
                            pending.remove(id, entry)
                            finishHint(entry.second, true)
                            failures = 0
                        } else {
                            finishHint(entry.second, false)
                            failures = minOf(failures + 1, 6)
                            nextAttemptAt = System.currentTimeMillis() +
                                (ReliabilityReportingBackoff.delaySeconds(failures, 0.5) * 1000).toLong()
                            break
                        }
                    }
                } finally {
                    drainScheduled.set(false)
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            drainScheduled.set(false)
        }
    }

    @Synchronized
    override fun send(envelope: SentryEnvelope, hint: Hint) {
        if (closed.get()) throw IOException("not connected")
        if (!ReliabilityReportingConsent.isOptedIn) {
            options.envelopeDiskCache.discard(envelope)
            throw IOException("not connected")
        }
        val url = requestDetails.url
        val decision = ReliabilityReportingNetwork.decision(url, ReliabilityReporting.dsnHost)
        if (decision == ReliabilityReportingLoadDecision.REJECT_HOST) {
            throw IOException("cannot find host")
        }
        // Own a bounded durable copy even for native/outbox hints. The SDK's
        // original is acknowledged only after HTTP acceptance.
        val stored = options.envelopeDiskCache.storeEnvelope(envelope, hint)
        val diskHint = io.sentry.util.HintUtils.getSentrySdkHint(hint) as?
            io.sentry.hints.DiskFlushNotification
        if (stored && diskHint != null && diskHint.isFlushable(envelope.header.eventId)) {
            diskHint.markFlushed()
        }
        if (pending.size < options.maxCacheItems || pending.containsKey(key(envelope))) {
            pending.putIfAbsent(key(envelope), envelope to hint)
        }
        if (decision != ReliabilityReportingLoadDecision.FORWARD) {
            finishHint(hint, false)
            return
        }
        scheduleDrain()
    }

    override fun flush(timeoutMillis: Long) {
        if (closed.get() || ReliabilityReportingGate.shouldBlockUpload ||
            !ReliabilityReportingConsent.isOptedIn) return
        scheduleDrain()
        val done = java.util.concurrent.CountDownLatch(1)
        try {
            executor.execute { done.countDown() }
            done.await(timeoutMillis, java.util.concurrent.TimeUnit.MILLISECONDS)
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            // Closing concurrently: cached envelopes remain durable.
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    override fun close() {
        close(false)
    }

    @Synchronized
    override fun close(isRestarting: Boolean) {
        closed.set(true)
        cancel()
        executor.shutdownNow()
        pending.values.forEach { finishHint(it.second, false) }
        pending.clear()
        limiter.close()
    }

    override fun getRateLimiter(): RateLimiter = limiter

    override fun cancel() {
        for (call in inflight.toList()) {
            runCatching { call.cancel() }
        }
        inflight.clear()
    }

    private fun post(envelope: SentryEnvelope): Boolean {
        if (closed.get() ||
            !ReliabilityReportingConsent.isOptedIn ||
            ReliabilityReportingGate.shouldBlockUpload
        ) {
            return false
        }
        val url = requestDetails.url
        if (ReliabilityReportingNetwork.decision(url, ReliabilityReporting.dsnHost) !=
            ReliabilityReportingLoadDecision.FORWARD
        ) {
            return false
        }
        val body =
            java.io.ByteArrayOutputStream().use { raw ->
                java.util.zip.GZIPOutputStream(raw).use { gzip ->
                    options.serializer.serialize(envelope, gzip)
                }
                raw.toByteArray()
            }
        val builder =
            okhttp3.Request.Builder()
                .url(url.toString())
                .post(body.toRequestBody("application/x-sentry-envelope".toMediaType()))
                .header("Content-Encoding", "gzip")
                .header("Content-Type", "application/x-sentry-envelope")
                .header("Accept", "application/json")
        for ((key, value) in requestDetails.headers) {
            builder.header(key, value)
        }
        val call = http.newCall(builder.build())
        inflight.add(call)
        ReliabilityReportingGate.register(this)
        try {
            if (closed.get() || !ReliabilityReportingConsent.isOptedIn ||
                ReliabilityReportingGate.shouldBlockUpload) {
                call.cancel()
                return false
            }
            call.execute().use { response ->
                limiter.updateRetryAfterLimits(
                    response.header("X-Sentry-Rate-Limits"), response.header("Retry-After"), response.code)
                if (!ReliabilityReportingConsent.isOptedIn ||
                    ReliabilityReportingGate.shouldBlockUpload
                ) {
                    return false
                }
                if (response.isSuccessful) {
                    options.envelopeDiskCache.discard(envelope)
                    envelope.header.eventId?.toString()?.let { eventId ->
                        if (eventId.isNotEmpty() && eventId != "00000000000000000000000000000000") {
                            ReliabilityReporting.noteTransportSuccess(eventId)
                        }
                    }
                    return true
                }
            }
        } catch (_: IOException) {
            // Keep the cached envelope. Camera cancel and network loss both land here.
        } finally {
            inflight.remove(call)
            ReliabilityReportingGate.unregister(this)
        }
        return false
    }
}



internal object ReliabilityReportingBackoff {
    fun delaySeconds(attempt: Int, jitter: Double): Double {
        val exponent = minOf(6, maxOf(0, attempt)).toDouble()
        val base = minOf(30.0, Math.pow(2.0, exponent) * 0.5)
        val spread = minOf(1.0, maxOf(0.0, jitter))
        return minOf(30.0, maxOf(0.25, base * (0.7 + 0.6 * spread)))
    }
}
