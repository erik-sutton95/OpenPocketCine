package com.opencapture.openpocketcine.diagnostics

import java.io.File
import java.util.UUID
import org.json.JSONObject

/** Bounded denominator records, including sessions with no dropout. */
internal object FeedSessionSummaryStore {
    private const val MAX_BYTES = 4_096
    private const val MAX_FILES = 20
    private const val TTL_MS = 604_800_000L

    fun directory(root: File): File = File(root, "sessions")

    fun persist(summary: FeedIncidentSessionSummary, root: File, nowMs: Long = System.currentTimeMillis()) {
        if (uuidOrNull(summary.sessionID) == null) return
        if (!summary.healthyExposureSeconds.isFinite() || summary.healthyExposureSeconds < 0.0) return
        val body = encode(summary)
        if (body.size > MAX_BYTES) return
        val dir = directory(root)
        dir.mkdirs()
        val file = File(dir, "${summary.sessionID}.json")
        val tmp = File(dir, "${summary.sessionID}.json.tmp")
        tmp.writeBytes(body)
        if (!tmp.renameTo(file)) {
            file.writeBytes(body)
            tmp.delete()
        }
        val files = urls(root).sortedByDescending { it.lastModified() }
        files.forEachIndexed { index, existing ->
            if (index >= MAX_FILES || nowMs - existing.lastModified() > TTL_MS) existing.delete()
        }
    }

    fun load(root: File): List<FeedIncidentSessionSummary> =
        urls(root).mapNotNull { file ->
            if (file.length() > MAX_BYTES) return@mapNotNull null
            runCatching { decode(file.readText()) }.getOrNull()
        }

    fun markInterrupted(root: File) {
        for (summary in load(root)) {
            if (summary.outcome != "live") continue
            persist(summary.copy(outcome = "interrupted"), root)
        }
    }

    fun deleteAll(root: File): Boolean = directory(root).let { !it.exists() || it.deleteRecursively() }

    fun encodeForReport(summary: FeedIncidentSessionSummary): String =
        JSONObject()
            .put("sessionID", summary.sessionID)
            .put("healthyExposureSeconds", summary.healthyExposureSeconds)
            .put("incidentCount", summary.incidentCount)
            .put("outcome", summary.outcome)
            .put("sourceRevision", summary.sourceRevision)
            .put("recordedAtMs", summary.recordedAtMs)
            .also { json ->
                summary.appVersion?.let { json.put("appVersion", it) }
                summary.appBuild?.let { json.put("appBuild", it) }
                summary.testSource?.let { json.put("testSource", it.wire) }
                summary.buildIdentity?.let { json.put("buildIdentity", it) }
            }
            .toString()

    private fun urls(root: File): List<File> {
        val files = directory(root).listFiles() ?: return emptyList()
        return files.filter { it.extension == "json" }
    }

    private fun encode(summary: FeedIncidentSessionSummary): ByteArray =
        JSONObject()
            .put("sessionID", summary.sessionID)
            .put("healthyExposureSeconds", summary.healthyExposureSeconds)
            .put("incidentCount", summary.incidentCount)
            .put("outcome", summary.outcome)
            .put("sourceRevision", summary.sourceRevision)
            .put("recordedAtMs", summary.recordedAtMs)
            .put("appVersion", summary.appVersion)
            .put("appBuild", summary.appBuild)
            .also { json ->
                summary.testSource?.let { json.put("testSource", it.wire) }
                summary.buildIdentity?.let { json.put("buildIdentity", it) }
            }
            .toString()
            .toByteArray(Charsets.UTF_8)

    private fun decode(raw: String): FeedIncidentSessionSummary {
        val json = JSONObject(raw)
        return FeedIncidentSessionSummary(
            sessionID = json.getString("sessionID"),
            healthyExposureSeconds = json.optDouble("healthyExposureSeconds", 0.0),
            incidentCount = json.optInt("incidentCount"),
            outcome = json.optString("outcome"),
            sourceRevision = json.optString("sourceRevision"),
            recordedAtMs = json.optLong("recordedAtMs"),
            appVersion = json.optString("appVersion").takeIf { it.isNotBlank() },
            appBuild = json.optString("appBuild").takeIf { it.isNotBlank() },
            testSource =
                if (json.has("testSource")) FeedIncidentTestSource.fromWire(json.optString("testSource"))
                else null,
            buildIdentity = json.optString("buildIdentity").takeIf { it.isNotBlank() },
        )
    }

    private fun uuidOrNull(raw: String): UUID? =
        runCatching { UUID.fromString(raw) }.getOrNull()
}
