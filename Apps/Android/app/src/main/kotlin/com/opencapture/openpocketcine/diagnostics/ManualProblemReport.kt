package com.opencapture.openpocketcine.diagnostics

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.opencapture.openpocketcine.BuildConfig
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URI
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.min
import kotlin.math.pow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

internal enum class ManualProblemReportDelivery {
    IDLE,
    WAITING,
    SENT,
    FAILED,
}

internal data class ManualProblemReportSnapshot(
    val delivery: ManualProblemReportDelivery = ManualProblemReportDelivery.IDLE,
    val eventId: String? = null,
    val detail: String? = null,
    val expiredMetadataOnly: Boolean = false,
) {
    val statusLabel: String
        get() =
            when (delivery) {
                ManualProblemReportDelivery.IDLE -> detail.orEmpty()
                ManualProblemReportDelivery.WAITING -> "Waiting to send"
                ManualProblemReportDelivery.SENT -> "Sent"
                ManualProblemReportDelivery.FAILED -> "Failed"
            }

    val allowsDiscard: Boolean
        get() =
            delivery == ManualProblemReportDelivery.WAITING ||
                delivery == ManualProblemReportDelivery.FAILED

    val allowsNewSubmit: Boolean
        get() =
            delivery == ManualProblemReportDelivery.IDLE ||
                delivery == ManualProblemReportDelivery.SENT
}

internal data class ManualEnvelopeItem(
    val header: JSONObject,
    val payload: ByteArray,
)

internal data class ManualEnvelope(
    val header: JSONObject,
    val items: List<ManualEnvelopeItem>,
)

/**
 * Dedicated one-at-a-time operator feedback envelope. Independent of automatic
 * SDK consent and does not start [io.sentry.Sentry].
 */
internal object ManualProblemReport {
    const val MESSAGE_MAX = 4_000
    const val EMAIL_MAX = 254
    const val ATTACHMENT_MAX_CHARS = 32_000
    const val ATTACHMENT_MAX_BYTES = 128 * 1_024
    const val TTL_MS = 7L * 24 * 60 * 60 * 1_000
    const val MIN_RETRY_MS = 30_000L
    const val MAX_RETRY_MS = 300_000L
    const val POLL_MS = 2_000L

    @Volatile var filesRoot: File? = null
    @Volatile var envelopeUrlOverride: String? = null
    @Volatile var sentryKeyOverride: String? = null
    @Volatile var nowMs: () -> Long = { System.currentTimeMillis() }
    @Volatile var appInForeground: Boolean = true
    @Volatile var executeInlineForTests: Boolean = false
    @Volatile var httpClientOverride: OkHttpClient? = null

    private val executor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "opc.manual-report").apply { isDaemon = true }
        }
    private val sending = AtomicBoolean(false)
    private val generation = AtomicLong(0)
    private val pollScheduled = AtomicBoolean(false)
    private val lock = Any()
    private val _snapshot = MutableStateFlow(ManualProblemReportSnapshot())
    val snapshot: StateFlow<ManualProblemReportSnapshot> = _snapshot.asStateFlow()

    @Volatile private var activeCall: Call? = null
    @Volatile private var activeEventId: String? = null
    @Volatile private var activeGeneration: Long = -1

    fun current(): ManualProblemReportSnapshot = _snapshot.value

    fun currentGeneration(): Long = generation.get()

    fun isConfigured(): Boolean = endpointFromConfigured() != null || envelopeUrlOverride != null

    fun install(context: Context) {
        filesRoot = File(context.applicationContext.noBackupFilesDir, "opc-manual-report")
        loadFromDisk()
        schedulePoll()
        tick()
    }

    fun setForeground(on: Boolean) {
        appInForeground = on
        if (!on) cancelUpload()
        else tick()
    }

    fun noteCameraPathClear() {
        tick()
    }

    fun submit(
        message: String,
        replyEmail: String,
        diagnostics: String?,
        images: List<ByteArray> = emptyList(),
    ): ManualSubmitResult =
        try {
            storeSubmission(message, replyEmail, diagnostics, images)
        } catch (_: Exception) {
            ManualSubmitResult.STORAGE_ERROR
        }

    private fun storeSubmission(
        message: String,
        replyEmail: String,
        diagnostics: String?,
        images: List<ByteArray>,
    ): ManualSubmitResult {
        val trimmed = ManualProblemReportEnvelope.sanitizeMessage(message)
        val email = ManualProblemReportEnvelope.sanitizeEmail(replyEmail)
        if (trimmed.isEmpty()) return ManualSubmitResult.INVALID
        if (replyEmail.isNotBlank() && email == null) return ManualSubmitResult.INVALID
        val acceptedImages = ManualReportImages.accept(images) ?: return ManualSubmitResult.INVALID
        val resolved = endpointFromConfigured() ?: return ManualSubmitResult.UNAVAILABLE
        val dsn = ReliabilityReportingDSN.configured() ?: envelopeUrlOverride ?: return ManualSubmitResult.UNAVAILABLE
        synchronized(lock) {
            loadFromDiskLocked()
            if (!_snapshot.value.allowsNewSubmit) return ManualSubmitResult.PENDING_EXISTS
            generation.incrementAndGet()
            cancelUploadLocked()
            val eventId = ManualProblemReportEnvelope.newEventId()
            val envelope =
                ManualProblemReportEnvelope.compose(
                    eventId = eventId,
                    timestampMs = nowMs(),
                    release =
                        "com.opencapture.openpocketcine@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}",
                    message = trimmed,
                    contactEmail = email,
                    diagnostics = diagnostics,
                    images = acceptedImages,
                )
            val bytes = ManualProblemReportEnvelope.serialize(envelope)
            val dir = directory() ?: return ManualSubmitResult.UNAVAILABLE
            dir.mkdirs()
            envelopeFile(dir).writeBytes(bytes)
            writeMeta(
                ManualReportMeta(
                    eventId = eventId,
                    createdAtMs = nowMs(),
                    status = "waiting",
                    attempts = 0,
                    nextAttemptAtMs = 0L,
                    lastHttp = 0,
                    dsn = dsn,
                    url = resolved.url,
                    host = resolved.host,
                    sentryKey = resolved.sentryKey,
                    detail = null,
                    envelopePresent = true,
                ),
            )
            publishLocked()
        }
        tick()
        return ManualSubmitResult.QUEUED
    }

    fun discard() {
        synchronized(lock) {
            generation.incrementAndGet()
            cancelUploadLocked()
            val removed = runCatching { directory()?.deleteRecursively() != false }.getOrDefault(false)
            publishLocked(detail = if (removed) "Report removed from this phone" else "Could not remove this report. Please try again.")
        }
    }

    fun tick() {
        if (executeInlineForTests) {
            tickOnce()
            return
        }
        try {
            executor.execute { tickOnce() }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
        }
    }

    fun flush() = tick()

    fun finishForTests(eventId: String, gen: Long, code: Int, retryAfter: String? = null) {
        applyFinished(eventId, gen, code, retryAfter, cancelled = false)
    }

    fun resetForTests() {
        synchronized(lock) {
            generation.incrementAndGet()
            cancelUploadLocked()
            filesRoot?.deleteRecursively()
            envelopeUrlOverride = null
            sentryKeyOverride = null
            nowMs = { System.currentTimeMillis() }
            appInForeground = true
            executeInlineForTests = false
            httpClientOverride = null
            _snapshot.value = ManualProblemReportSnapshot()
        }
    }

    private fun tickOnce() {
        val prepared: Triple<ManualReportMeta, ManualReportEndpoint, ByteArray>
        val gen: Long
        synchronized(lock) {
            loadFromDiskLocked()
            val meta = readMeta() ?: return
            if (nowMs() - meta.createdAtMs > TTL_MS) {
                expireLocked(meta)
                return
            }
            if (meta.status == "sent") return
            if (meta.status == "failed") {
                publishLocked()
                return
            }
            if (!appInForeground) {
                cancelUploadLocked()
                meta.detail = "Waiting to send — keep the app open after leaving camera Wi-Fi"
                writeMeta(meta)
                publishLocked()
                return
            }
            if (ReliabilityReportingGate.shouldBlockUpload) {
                cancelUploadLocked()
                meta.detail = "Waiting to send — keep the app open after leaving camera Wi-Fi"
                writeMeta(meta)
                publishLocked()
                return
            }
            if (nowMs() < meta.nextAttemptAtMs) {
                publishLocked()
                return
            }
            if (sending.get() || activeCall != null) return
            val currentDsn = ReliabilityReportingDSN.configured()
            if (envelopeUrlOverride == null && currentDsn != null && currentDsn != meta.dsn) {
                meta.status = "failed"
                meta.detail = "Reporting destination changed. Remove this report and send again."
                deleteEnvelopeLocked()
                meta.envelopePresent = false
                writeMeta(meta)
                publishLocked()
                return
            }
            val endpoint =
                ManualReportEndpoint(url = meta.url, host = meta.host, sentryKey = meta.sentryKey)
            val url = runCatching { URL(endpoint.url) }.getOrNull()
            val decision = ReliabilityReportingNetwork.decision(url, endpoint.host)
            if (decision == ReliabilityReportingLoadDecision.REJECT_HOST) {
                meta.status = "failed"
                meta.detail = "Reporting is unavailable in this build"
                deleteEnvelopeLocked()
                meta.envelopePresent = false
                writeMeta(meta)
                publishLocked()
                return
            }
            if (decision != ReliabilityReportingLoadDecision.FORWARD) {
                writeMeta(meta)
                publishLocked()
                return
            }
            val bytes = envelopeFile(directory()).takeIf { it.isFile }?.readBytes()
            if (bytes == null) {
                meta.status = "failed"
                meta.detail = "The queued report is missing"
                meta.envelopePresent = false
                writeMeta(meta)
                publishLocked()
                return
            }
            gen = generation.get()
            prepared = Triple(meta, endpoint, bytes)
        }
        post(prepared.first, prepared.second, prepared.third, gen)
    }

    private fun post(
        meta: ManualReportMeta,
        endpoint: ManualReportEndpoint,
        bytes: ByteArray,
        gen: Long,
    ) {
        if (!sending.compareAndSet(false, true)) return
        var registered: ReliabilityReportingCancellable? = null
        var requestCall: Call? = null
        try {
            if (gen != generation.get() || !appInForeground) return
            if (ReliabilityReportingGate.shouldBlockUpload || !ReliabilityReportingGate.hasValidInternet) {
                return
            }
            val client =
                httpClientOverride
                    ?: OkHttpClient.Builder()
                        .followRedirects(false)
                        .followSslRedirects(false)
                        .retryOnConnectionFailure(false)
                        .connectTimeout(20, TimeUnit.SECONDS)
                        .readTimeout(60, TimeUnit.SECONDS)
                        .callTimeout(120, TimeUnit.SECONDS)
                        .build()
            val request =
                Request.Builder()
                    .url(endpoint.url)
                    .post(bytes.toRequestBody("application/x-sentry-envelope".toMediaType()))
                    .header("Content-Type", "application/x-sentry-envelope")
                    .header("Accept", "application/json")
                    .header(
                        "X-Sentry-Auth",
                        "Sentry sentry_version=7, sentry_client=openpocketcine-android/${BuildConfig.VERSION_NAME}, sentry_key=${endpoint.sentryKey}",
                    )
                    .build()
            val call = client.newCall(request)
            requestCall = call
            val cancellable =
                object : ReliabilityReportingCancellable {
                    override val independentOfAutomaticConsent = true
                    override fun cancel() {
                        call.cancel()
                    }
                }
            synchronized(lock) {
                if (gen != generation.get() || !appInForeground) {
                    call.cancel()
                    return
                }
                activeCall = call
                activeEventId = meta.eventId
                activeGeneration = gen
            }
            registered = cancellable
            ReliabilityReportingGate.register(cancellable)
            if (gen != generation.get() || !appInForeground ||
                ReliabilityReportingGate.shouldBlockUpload ||
                !ReliabilityReportingGate.hasValidInternet
            ) {
                call.cancel()
                return
            }
            call.execute().use { response ->
                applyFinished(
                    eventId = meta.eventId,
                    gen = gen,
                    code = response.code,
                    retryAfter = response.header("Retry-After"),
                    cancelled = false,
                )
            }
        } catch (_: Exception) {
            val cancelled = requestCall?.isCanceled() == true
            applyFinished(meta.eventId, gen, 0, null, cancelled = cancelled)
        } finally {
            registered?.let { ReliabilityReportingGate.unregister(it) }
            synchronized(lock) {
                if (activeGeneration == gen) {
                    activeCall = null
                    activeEventId = null
                    activeGeneration = -1
                }
            }
            sending.set(false)
            schedulePoll()
        }
    }

    internal fun applyFinished(
        eventId: String,
        gen: Long,
        code: Int,
        retryAfter: String?,
        cancelled: Boolean,
    ) {
        synchronized(lock) {
            if (gen != generation.get()) return
            val meta = readMeta() ?: return
            if (meta.eventId != eventId) return
            if (cancelled) {
                meta.detail = "Waiting to send"
                writeMeta(meta)
                publishLocked()
                return
            }
            meta.attempts += 1
            meta.lastHttp = code
            when {
                code in 200..299 -> {
                    meta.status = "sent"
                    meta.detail = "Report sent. Thank you for helping improve OpenPocketCine."
                    deleteEnvelopeLocked()
                    meta.envelopePresent = false
                    writeMeta(meta)
                    directory()?.let { dir ->
                        envelopeFile(dir).delete()
                    }
                }
                code == 429 || code == 408 -> {
                    meta.status = "waiting"
                    meta.nextAttemptAtMs = nowMs() + retryDelayMs(retryAfter, meta.attempts)
                    meta.detail = "Waiting for a connection — your report is saved on this phone"
                }
                code in 400..499 -> {
                    meta.status = "failed"
                    meta.detail =
                        "Report couldn't be sent. Remove it and try again, or contact support@openpocketcine.app."
                }
                else -> {
                    meta.status = "waiting"
                    meta.nextAttemptAtMs = nowMs() + retryDelayMs(retryAfter, meta.attempts)
                    meta.detail = "Waiting for a connection — your report is saved on this phone"
                }
            }
            writeMeta(meta)
            publishLocked()
        }
    }

    private fun retryDelayMs(retryAfter: String?, attempts: Int): Long {
        val backoff =
            min(MAX_RETRY_MS.toDouble(), MIN_RETRY_MS * 2.0.pow(min(attempts, 4).toDouble())).toLong()
        val header = parseRetryAfter(retryAfter, nowMs()) - nowMs()
        return maxOf(MIN_RETRY_MS, backoff, header)
    }

    private fun cancelUpload() {
        synchronized(lock) { cancelUploadLocked() }
    }

    private fun cancelUploadLocked() {
        activeCall?.cancel()
        activeCall = null
        activeEventId = null
        activeGeneration = -1
    }

    private fun expireLocked(meta: ManualReportMeta) {
        deleteEnvelopeLocked()
        meta.status = "failed"
        meta.envelopePresent = false
        meta.detail = "Report expired before it could be sent. Please create a new report."
        writeMeta(meta)
        publishLocked()
    }

    private fun deleteEnvelopeLocked() {
        envelopeFile(directory()).delete()
    }

    private fun schedulePoll() {
        if (executeInlineForTests) return
        if (!pollScheduled.compareAndSet(false, true)) return
        val looper = runCatching { Looper.getMainLooper() }.getOrNull() ?: run {
            pollScheduled.set(false)
            return
        }
        Handler(looper).postDelayed(
            {
                pollScheduled.set(false)
                if (_snapshot.value.allowsDiscard) {
                    tick()
                    schedulePoll()
                }
            },
            POLL_MS,
        )
    }

    private fun loadFromDisk() {
        synchronized(lock) { loadFromDiskLocked() }
    }

    private fun loadFromDiskLocked() {
        val meta = readMeta() ?: run {
            publishLocked()
            return
        }
        if (nowMs() - meta.createdAtMs > TTL_MS) {
            expireLocked(meta)
            return
        }
        publishLocked()
    }

    private fun publishLocked(detail: String? = null) {
        val meta = readMeta()
        _snapshot.value =
            if (meta == null) {
                ManualProblemReportSnapshot(detail = detail)
            } else {
                ManualProblemReportSnapshot(
                    delivery =
                        when (meta.status) {
                            "waiting" -> ManualProblemReportDelivery.WAITING
                            "sent" -> ManualProblemReportDelivery.SENT
                            "failed" -> ManualProblemReportDelivery.FAILED
                            else -> ManualProblemReportDelivery.IDLE
                        },
                    eventId = meta.eventId,
                    detail = detail ?: meta.detail,
                    expiredMetadataOnly = !meta.envelopePresent && meta.status == "failed",
                )
            }
    }

    private fun directory(): File? = filesRoot

    private fun metaFile(dir: File? = directory()): File = File(dir ?: File("."), "pending.json")

    private fun envelopeFile(dir: File? = directory()): File = File(dir ?: File("."), "pending.envelope")

    private fun readMeta(): ManualReportMeta? {
        val file = metaFile()
        if (!file.isFile) return null
        return runCatching { ManualReportMeta.from(JSONObject(file.readText())) }.getOrNull()
    }

    private fun writeMeta(meta: ManualReportMeta) {
        val dir = directory() ?: return
        dir.mkdirs()
        val file = metaFile(dir)
        val tmp = File(dir, "pending.json.tmp")
        tmp.writeText(meta.toJson().toString())
        if (!tmp.renameTo(file)) {
            file.writeText(meta.toJson().toString())
            tmp.delete()
        }
    }

    private fun endpointFromConfigured(): ManualReportEndpoint? {
        envelopeUrlOverride?.let { url ->
            val host = runCatching { URI(url).host }.getOrNull() ?: return null
            val key = sentryKeyOverride ?: "testkey"
            return ManualReportEndpoint(url = url, host = host, sentryKey = key)
        }
        val dsn = ReliabilityReportingDSN.configured() ?: return null
        return ManualReportEndpoint.fromDsn(dsn)
    }
}

internal enum class ManualSubmitResult {
    QUEUED,
    INVALID,
    UNAVAILABLE,
    PENDING_EXISTS,
    STORAGE_ERROR,
}

internal data class ManualReportEndpoint(
    val url: String,
    val host: String,
    val sentryKey: String,
) {
    companion object {
        fun fromDsn(dsn: String): ManualReportEndpoint? {
            val valid = ReliabilityReportingDSN.validated(dsn) ?: return null
            val uri = runCatching { URI(valid) }.getOrNull() ?: return null
            val host = uri.host ?: return null
            val key = uri.userInfo ?: return null
            val segments = uri.path.split('/').filter { it.isNotEmpty() }
            val project = segments.lastOrNull() ?: return null
            val prefix = segments.dropLast(1).joinToString("/")
            val scheme = if (ReliabilityReportingHostPolicy.requireHttps) "https" else (uri.scheme ?: "https")
            val path = (if (prefix.isEmpty()) "" else "/$prefix") + "/api/$project/envelope/"
            return ManualReportEndpoint(
                url = "$scheme://$host$path",
                host = host,
                sentryKey = key,
            )
        }
    }
}

internal object ManualProblemReportEnvelope {
    fun newEventId(): String =
        UUID.randomUUID().toString().replace("-", "").lowercase(Locale.US)

    fun sanitizeMessage(raw: String): String = raw.trim().take(ManualProblemReport.MESSAGE_MAX)

    fun sanitizeEmail(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        if (trimmed.length > ManualProblemReport.EMAIL_MAX) return null
        if (!trimmed.contains('@') || trimmed.any { it.isWhitespace() }) return null
        return trimmed
    }

    fun utf8Prefix(text: String, maxBytes: Int): String {
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (bytes.size <= maxBytes) return text
        var end = maxBytes.coerceAtLeast(0)
        while (end > 0 && bytes[end - 1].toInt() and 0xC0 == 0x80) end--
        if (end > 0 && bytes[end - 1].toInt() and 0x80 != 0) end--
        return String(bytes, 0, end, Charsets.UTF_8)
    }

    fun compose(
        eventId: String,
        timestampMs: Long,
        release: String,
        message: String,
        contactEmail: String?,
        diagnostics: String?,
        images: List<ByteArray> = emptyList(),
        environment: String = if (BuildConfig.DEBUG) "development" else "production",
        dist: String = BuildConfig.VERSION_CODE.toString(),
        sourceRevision: String = BuildConfig.SOURCE_REVISION.take(64),
    ): ManualEnvelope {
        val iso = isoMs(timestampMs)
        val acceptedImages = ManualReportImages.accept(images) ?: emptyList()
        val feedbackFields =
            JSONObject()
                .put("message", message)
                .put("source", "custom")
        if (contactEmail != null) feedbackFields.put("contact_email", contactEmail)
        val payload =
            JSONObject()
                .put("type", "feedback")
                .put("event_id", eventId)
                .put("timestamp", iso)
                .put("platform", "java")
                .put("release", release)
                .put("environment", environment)
                .put("dist", dist)
                .put("tags", JSONObject().put("sourceRevision", sourceRevision))
                .put("contexts", JSONObject().put("feedback", feedbackFields))
        val items = mutableListOf(
            ManualEnvelopeItem(
                header =
                    JSONObject()
                        .put("type", "feedback")
                        .put("content_type", "application/json"),
                payload = payload.toString().toByteArray(Charsets.UTF_8),
            ),
        )
        if (diagnostics != null) {
            val clipped = diagnostics.take(ManualProblemReport.ATTACHMENT_MAX_CHARS)
            val redacted =
                utf8Prefix(
                    PrivacyRedactor.redact(clipped),
                    ManualProblemReport.ATTACHMENT_MAX_BYTES,
                )
            items +=
                ManualEnvelopeItem(
                    header =
                        JSONObject()
                            .put("type", "attachment")
                            .put("filename", "diagnostics.txt")
                            .put("content_type", "text/plain")
                            .put("attachment_type", "event.attachment"),
                    payload = redacted.toByteArray(Charsets.UTF_8),
                )
        }
        for ((index, jpeg) in acceptedImages.withIndex()) {
            items +=
                ManualEnvelopeItem(
                    header =
                        JSONObject()
                            .put("type", "attachment")
                            .put("filename", ManualReportImages.generatedName(index))
                            .put("content_type", "image/jpeg")
                            .put("attachment_type", "event.attachment"),
                    payload = jpeg,
                )
        }
        return ManualEnvelope(
            header = JSONObject().put("event_id", eventId).put("sent_at", iso),
            items = items,
        )
    }

    fun serialize(envelope: ManualEnvelope): ByteArray {
        val out = ByteArrayOutputStream()
        fun writeLine(obj: JSONObject) {
            out.write(obj.toString().toByteArray(Charsets.UTF_8))
            out.write('\n'.code)
        }
        writeLine(envelope.header)
        for (item in envelope.items) {
            val header = JSONObject(item.header.toString()).put("length", item.payload.size)
            writeLine(header)
            out.write(item.payload)
            out.write('\n'.code)
        }
        return out.toByteArray()
    }

    fun parse(bytes: ByteArray): ManualEnvelope {
        var offset = 0
        fun readLine(): ByteArray {
            val start = offset
            while (offset < bytes.size && bytes[offset] != '\n'.code.toByte()) offset++
            val line = bytes.copyOfRange(start, offset)
            if (offset < bytes.size) offset++
            return line
        }
        val header = JSONObject(String(readLine(), Charsets.UTF_8))
        val items = mutableListOf<ManualEnvelopeItem>()
        while (offset < bytes.size) {
            val itemHeader = JSONObject(String(readLine(), Charsets.UTF_8))
            val length = itemHeader.getInt("length")
            val payload = bytes.copyOfRange(offset, (offset + length).coerceAtMost(bytes.size))
            offset += length
            if (offset < bytes.size && bytes[offset] == '\n'.code.toByte()) offset++
            items += ManualEnvelopeItem(itemHeader, payload)
        }
        return ManualEnvelope(header, items)
    }

    private fun isoMs(timestampMs: Long): String {
        val iso =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
        return iso.format(Date(timestampMs))
    }
}

internal data class ManualReportMeta(
    val eventId: String,
    val createdAtMs: Long,
    var status: String,
    var attempts: Int,
    var nextAttemptAtMs: Long,
    var lastHttp: Int,
    val dsn: String,
    val url: String,
    val host: String,
    val sentryKey: String,
    var detail: String?,
    var envelopePresent: Boolean,
) {
    fun toJson(): JSONObject =
        JSONObject()
            .put("eventId", eventId)
            .put("createdAtMs", createdAtMs)
            .put("status", status)
            .put("attempts", attempts)
            .put("nextAttemptAtMs", nextAttemptAtMs)
            .put("lastHttp", lastHttp)
            .put("dsn", dsn)
            .put("url", url)
            .put("host", host)
            .put("sentryKey", sentryKey)
            .put("detail", detail ?: JSONObject.NULL)
            .put("envelopePresent", envelopePresent)

    companion object {
        fun from(json: JSONObject): ManualReportMeta =
            ManualReportMeta(
                eventId = json.getString("eventId"),
                createdAtMs = json.getLong("createdAtMs"),
                status = json.getString("status"),
                attempts = json.optInt("attempts"),
                nextAttemptAtMs = json.optLong("nextAttemptAtMs"),
                lastHttp = json.optInt("lastHttp"),
                dsn = json.optString("dsn"),
                url = json.getString("url"),
                host = json.getString("host"),
                sentryKey = json.getString("sentryKey"),
                detail = json.optString("detail").ifEmpty { null },
                envelopePresent = json.optBoolean("envelopePresent", true),
            )
    }
}

internal fun parseRetryAfter(raw: String?, nowMs: Long): Long {
    if (raw.isNullOrBlank()) return nowMs + ManualProblemReport.MIN_RETRY_MS
    raw.trim().toLongOrNull()?.let { seconds ->
        return nowMs + (seconds.coerceIn(1L, ManualProblemReport.TTL_MS / 1_000L) * 1_000L)
    }
    val parsed = runCatching {
        SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("GMT")
            isLenient = false
        }.parse(raw.trim())?.time
    }.getOrNull()
    return parsed?.coerceAtLeast(nowMs + ManualProblemReport.MIN_RETRY_MS)
        ?: (nowMs + ManualProblemReport.MIN_RETRY_MS)
}
