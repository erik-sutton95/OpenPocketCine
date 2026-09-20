package com.opencapture.openpocketcine.diagnostics

import android.content.SharedPreferences
import androidx.core.content.edit
import io.sentry.SentryEvent
import io.sentry.protocol.Message
import io.sentry.protocol.SentryId
import io.sentry.protocol.SentryStackFrame
import java.io.File
import java.net.URI
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import org.json.JSONObject

internal object ReliabilityReportingConsent {
    const val KEY = "opc.reliabilityReporting.optIn"

    @Volatile private var optedIn: Boolean = false
    @Volatile private var decided: Boolean = false
    @Volatile private var persist: ((Boolean) -> Unit)? = null

    val isOptedIn: Boolean
        get() = optedIn

    val hasDecision: Boolean
        get() = decided

    fun setOptedIn(on: Boolean) {
        optedIn = on
        decided = true
        persist?.invoke(on)
    }

    fun shouldOfferAutomaticPrompt(): Boolean =
        ReliabilityReportingDSN.isAvailable && !decided

    fun bind(prefs: SharedPreferences) {
        restorePersistedChoice(
            hasChoice = prefs.contains(KEY),
            optedIn = prefs.getBoolean(KEY, false),
            persist = { value -> prefs.edit { putBoolean(KEY, value) } },
        )
    }

    /** Absence of [KEY] is undecided; a stored false is an explicit decline. */
    fun restorePersistedChoice(
        hasChoice: Boolean,
        optedIn: Boolean = false,
        persist: ((Boolean) -> Unit)? = null,
    ) {
        decided = hasChoice
        this.optedIn = hasChoice && optedIn
        this.persist = persist
    }

    fun resetForTests() {
        optedIn = false
        decided = false
        persist = null
    }
}

internal object ReliabilityReportingDSN {
    @Volatile var buildDsn: String? = null
    @Volatile var environment: Map<String, String> = System.getenv()

    fun configured(): String? {
        val candidates =
            listOf(
                buildDsn,
                environment["SENTRY_DSN_ANDROID"],
                environment["SENTRY_DSN"],
            )
        for (raw in candidates) {
            val value = validated(raw) ?: continue
            return value
        }
        return null
    }

    fun validated(raw: String?): String? {
        if (raw == null) return null
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || trimmed.contains("YOUR_") || trimmed.contains("example")) {
            return null
        }
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        if (uri.scheme?.lowercase() != "https") return null
        val host = uri.host
        if (host.isNullOrEmpty()) return null
        val userInfo = uri.userInfo
        if (userInfo.isNullOrEmpty() || userInfo.contains(':')) return null
        if (uri.query != null || uri.fragment != null) return null
        val project = uri.path.split('/').lastOrNull().orEmpty()
        if (project.isEmpty() || !project.all { it.isDigit() }) return null
        return trimmed
    }

    val isAvailable: Boolean
        get() = configured() != null
}

internal object ReliabilityReportingPrivacy {
    val extraAllowlist: Set<String> =
        setOf(
            "schemaVersion",
            "failingStage",
            "errorClass",
            "outcome",
            "kind",
            "incidentCount",
            "sourceRevision",
            "hardwareClass",
            "cameraFirmware",
            "assistState",
            "decoderGeneration",
            "socketGeneration",
            "worstGapSeconds",
            "healthyExposureSeconds",
            "testSource",
            "buildIdentity",
        )

    val contextAllowlist: Map<String, Set<String>> =
        mapOf(
            "os" to setOf("name", "version", "build"),
            "device" to setOf("family", "model", "arch"),
            "app" to setOf("app_version", "app_build", "build_type"),
            "feed" to
                setOf(
                    "schemaVersion",
                    "failingStage",
                    "errorClass",
                    "outcome",
                    "kind",
                    "assistState",
                    "hardwareClass",
                    "testSource",
                    "buildIdentity",
                    "cameraFamily",
                ),
        )

    val tagAllowlist: Set<String> =
        setOf(
            "failingStage",
            "errorClass",
            "outcome",
            "kind",
            "sourceRevision",
            "cameraFamily",
            "cameraFirmware",
            "hardwareClass",
            "testSource",
            "buildIdentity",
        )

    fun eventId(fromIncidentId: String): SentryId {
        val hex = fromIncidentId.filter { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }
        if (hex.length >= 32) return SentryId(hex.take(32))
        runCatching { UUID.fromString(fromIncidentId) }.getOrNull()?.let { uuid ->
            return SentryId(uuid)
        }
        return SentryId(hex.padEnd(32, '0').take(32))
    }

    fun fingerprint(schema: Int, kind: String, stage: String, errorClass: String): List<String> =
        listOf(
            "feed-incident",
            "schema:$schema",
            "kind:${FeedIncidentPrivacyToken.token(kind, 32)}",
            "stage:${FeedIncidentPrivacyToken.token(stage, 32)}",
            "errorClass:${FeedIncidentPrivacyToken.token(errorClass, 32)}",
        )

    fun validatedEnvelope(from: FeedIncidentBundle): FeedIncidentVendorEnvelope? {
        val envelope = FeedIncidentExport.envelope(from)
        if (envelope.schemaVersion < 1) return null
        if (envelope.eventName != "feed.incident") return null
        val id = envelope.incidentID.trim()
        if (id.isEmpty() || id == "unknown") return null
        if (!FeedIncidentFailingStage.isKnown(envelope.grouping.failingStage)) return null
        return envelope
    }

    fun scrub(event: SentryEvent): SentryEvent {
        event.user = null
        event.request = null
        event.breadcrumbs =
            event.breadcrumbs
                ?.mapNotNull { scrubBreadcrumb(it) }
                ?.takeLast(32)
                ?.toMutableList()
        event.serverName = null
        event.transaction = null
        val formatted = event.message?.formatted
        if (formatted != null) {
            val isTypedFeedEvent =
                event.fingerprints?.firstOrNull() == "feed-incident" ||
                    event.fingerprints?.firstOrNull() == "feed-session"
            val message = Message()
            message.formatted =
                if (isTypedFeedEvent) PrivacyRedactor.redact(formatted) else "Application diagnostic"
            event.message = message
        }
        val tags = event.tags
        if (tags != null) {
            val kept = tags.filterKeys { tagAllowlist.contains(it) }.toMutableMap()
            for (key in kept.keys) {
                val limit = if (key == "sourceRevision" || key == "buildIdentity") 64 else 32
                kept[key] = FeedIncidentPrivacyToken.token(kept[key].orEmpty(), limit)
            }
            event.tags = if (kept.isEmpty()) null else kept
        }
        val extras = event.extras
        if (extras != null) {
            val kept = extras.filterKeys { extraAllowlist.contains(it) }
            event.extras = if (kept.isEmpty()) null else kept.toMutableMap()
        }
        val contexts = event.contexts
        val keptSections = mutableMapOf<String, Any>()
        for ((section, allow) in contextAllowlist) {
            val values = contexts[section] as? Map<*, *> ?: continue
            val filtered = mutableMapOf<String, Any>()
            for (key in values.keys) {
                val name = key as? String ?: continue
                if (!allow.contains(name)) continue
                val value = values[key] ?: continue
                filtered[name] = value
            }
            if (filtered.isNotEmpty()) keptSections[section] = filtered
        }
        contexts.clear()
        for ((section, values) in keptSections) {
            contexts[section] = values
        }
        event.exceptions?.forEach { exception ->
            if (exception.value != null) exception.value = "Native exception"
            redact(exception.stacktrace?.frames)
        }
        event.threads?.forEach { thread ->
            redact(thread.stacktrace?.frames)
        }
        return event
    }

    fun scrubBreadcrumb(breadcrumb: io.sentry.Breadcrumb): io.sentry.Breadcrumb? {
        if (breadcrumb.category != "feed") return null
        val message = breadcrumb.message ?: return null
        if (!FeedIncidentNativeBreadcrumb.isAllowedMessage(message)) return null
        val strings = mutableMapOf<String, String>()
        val data = breadcrumb.data
        data.forEach { (key, value) ->
            if (value is String) strings[key] = value
        }
        val kept = FeedIncidentNativeBreadcrumb.sanitized(strings)
        data.clear()
        for ((key, value) in kept) {
            breadcrumb.setData(key, value)
        }
        return breadcrumb
    }

    private fun redact(frames: List<SentryStackFrame>?) {
        if (frames == null) return
        for (frame in frames) {
            frame.vars = null
            frame.contextLine = null
            frame.preContext = null
            frame.postContext = null
            frame.filename = frame.filename?.let { PrivacyRedactor.redact(it) }
            frame.function = frame.function?.let { PrivacyRedactor.redact(it) }
        }
    }

    fun typedJson(from: FeedIncidentBundle): ByteArray? {
        if (validatedEnvelope(from) == null) return null
        val data = runCatching { FeedIncidentJson.encode(from) }.getOrNull() ?: return null
        if (data.size > 262_144) return null
        return data
    }
}

internal object FeedIncidentPrivacyToken {
    fun token(raw: String, max: Int = 32): String {
        val clipped = raw.trim().take(max)
        return PrivacyRedactor.redact(clipped)
    }
}

internal enum class ReliabilityReportingReceiptState {
    QUEUED,
    CONFIRMED,
}

internal data class ReliabilityReportingReceipt(
    val incidentID: String,
    val eventID: String,
    val state: ReliabilityReportingReceiptState,
    val updatedAt: Long,
)

internal object ReliabilityReportingReceipts {
    private val iso =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

    fun directory(root: File): File = File(root, "receipts")

    fun load(incidentID: String, root: File): ReliabilityReportingReceipt? {
        val file = File(directory(root), "$incidentID.json")
        if (!file.isFile) return null
        return runCatching { decode(file.readText()) }.getOrNull()
    }

    fun store(receipt: ReliabilityReportingReceipt, root: File) {
        val dir = directory(root)
        dir.mkdirs()
        val file = File(dir, "${receipt.incidentID}.json")
        val tmp = File(dir, "${receipt.incidentID}.json.tmp")
        tmp.writeText(encode(receipt))
        if (!tmp.renameTo(file)) {
            file.writeText(encode(receipt))
            tmp.delete()
        }
    }

    fun markConfirmed(eventID: String, root: File, now: Long = System.currentTimeMillis()) {
        val needle = eventID.filter { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }.lowercase()
        for (receipt in loadAll(root)) {
            if (receipt.state != ReliabilityReportingReceiptState.QUEUED) continue
            val stored =
                receipt.eventID.filter { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }
                    .lowercase()
            if (stored != needle) continue
            store(receipt.copy(state = ReliabilityReportingReceiptState.CONFIRMED, updatedAt = now), root)
            return
        }
    }

    fun applyTTL(root: File, now: Long = System.currentTimeMillis(), ttlMs: Long = 604_800_000L) {
        val files = directory(root).listFiles() ?: return
        for (file in files) {
            if (file.extension != "json") continue
            if (now - file.lastModified() > ttlMs) file.delete()
        }
    }

    fun loadAll(root: File): List<ReliabilityReportingReceipt> {
        val files = directory(root).listFiles() ?: return emptyList()
        return files.mapNotNull { file ->
            if (file.extension != "json") return@mapNotNull null
            runCatching { decode(file.readText()) }.getOrNull()
        }
    }

    fun purge(root: File) {
        root.deleteRecursively()
    }

    private fun encode(receipt: ReliabilityReportingReceipt): String =
        JSONObject()
            .put("incidentID", receipt.incidentID)
            .put("eventID", receipt.eventID)
            .put("state", receipt.state.name.lowercase())
            .put("updatedAt", iso.format(Date(receipt.updatedAt)))
            .toString()

    private fun decode(raw: String): ReliabilityReportingReceipt? {
        val json = JSONObject(raw)
        val stateRaw = json.optString("state")
        val state =
            when (stateRaw.lowercase()) {
                "queued" -> ReliabilityReportingReceiptState.QUEUED
                "confirmed" -> ReliabilityReportingReceiptState.CONFIRMED
                else -> return null
            }
        val updatedAt = parseIso(json.optString("updatedAt")) ?: return null
        return ReliabilityReportingReceipt(
            incidentID = json.optString("incidentID"),
            eventID = json.optString("eventID"),
            state = state,
            updatedAt = updatedAt,
        )
    }

    private fun parseIso(raw: String): Long? =
        runCatching { iso.parse(raw)?.time }.getOrNull()
}
