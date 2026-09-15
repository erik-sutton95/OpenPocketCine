package com.opencapture.openpocketcine.diagnostics

import java.io.File
import java.util.Locale

/** On-device incident spool. Journal-independent. No upload. Atomic writes. */
internal class FeedIncidentStore(
    val directory: File,
    private val limits: FeedIncidentLimits = FeedIncidentLimits(),
) {
    init {
        directory.mkdirs()
    }

    fun persist(job: FeedIncidentPersistenceJob, nowMs: Long = System.currentTimeMillis()) {
        val bundle = enforceSize(job.bundle, limits.maxBundleBytes)
        write(bundle)
        applyRetention(nowMs)
    }

    fun loadAll(): List<FeedIncidentBundle> =
        urls().mapNotNull { load(it) }.sortedByDescending { it.header.startedAtWallClockMs }

    fun markInterrupted(nowMs: Long = System.currentTimeMillis()): List<String> {
        applyRetention(nowMs)
        val changed = mutableListOf<String>()
        for (url in urls()) {
            val bundle = load(url) ?: continue
            if (bundle.header.outcome != FeedIncidentOutcome.OPEN) continue
            bundle.header.outcome = FeedIncidentOutcome.INTERRUPTED
            write(bundle)
            changed += bundle.header.incidentId
        }
        return changed
    }

    fun applyRetention(nowMs: Long) {
        val entries = mutableListOf<Triple<File, Long, Int>>()
        for (file in urls()) {
            val started = load(file)?.header?.startedAtWallClockMs ?: nowMs
            if (nowMs - started > limits.ttlMs) {
                file.delete()
                continue
            }
            entries += Triple(file, started, file.length().toInt())
        }
        entries.sortBy { it.second }
        var total = entries.sumOf { it.third }
        while (entries.size > limits.maxBundles || total > limits.maxSpoolBytes) {
            val oldest = entries.firstOrNull() ?: break
            oldest.first.delete()
            total -= oldest.third
            entries.removeAt(0)
        }
    }

    fun deleteAll(): Boolean = urls().map { it.delete() || !it.exists() }.all { it }

    fun exportText(): String = text(loadAll())

    /** Typed attachments: listing plus one JSON bundle each. No footage or credentials. */
    fun exportExtras(
        maxBundles: Int = limits.maxBundles,
        maxTotalBytes: Int = limits.maxSpoolBytes.coerceAtMost(2_097_152),
    ): List<Pair<String, String>> {
        val bundles = loadAll().take(maxBundles)
        val extras = mutableListOf<Pair<String, String>>()
        val listing = text(bundles)
        extras += "incidents.txt" to listing
        var total = listing.length
        for (bundle in bundles) {
            val capped = enforceSize(bundle, limits.maxBundleBytes)
            val body = PrivacyRedactor.redact(String(FeedIncidentJson.encode(capped), Charsets.UTF_8))
            if (total + body.length > maxTotalBytes) break
            extras += FeedIncidentFileNaming.incident(capped.header.incidentId) to body
            total += body.length
        }
        return extras
    }

    companion object {
        fun text(bundles: List<FeedIncidentBundle>): String {
            val lines = mutableListOf(
                "OpenPocketCine feed incidents (typed snapshots, no journal)",
                "count=${bundles.size} schema=${FeedIncidentSchema.VERSION}",
            )
            for (bundle in bundles) {
                val header = bundle.header
                lines += "---"
                lines +=
                    "id=${header.incidentId} kind=${header.kind.wire} stage=${header.failingStage.wire} outcome=${header.outcome.wire}"
                lines +=
                    "session=${header.sessionId} started=${FeedIncidentJson.formatWall(header.startedAtWallClockMs)} gap=${"%.3f".format(Locale.US, header.worstGapSeconds)}s"
                lines +=
                    "release=${header.appVersion}(${header.appBuild}) rev=${header.sourceRevision} identity=${header.buildIdentity} source=${header.testSource.wire} os=${header.osName} ${header.osVersion} hw=${header.hardwareClass}"
                lines +=
                    "camera=${header.cameraFamily} fw=${header.cameraFirmware ?: "none"} decoderGen=${header.decoderGeneration} socketGen=${header.socketGeneration} assist=${header.assistState}"
                header.errorClass?.let { lines += "errorClass=$it" }
                lines +=
                    "snapshots prelude=${bundle.prelude.size} during=${bundle.during.size} aftermath=${bundle.aftermath.size} repairs=${bundle.repairs.size} breadcrumbs=${bundle.breadcrumbs.size} evictions=${header.evictions} healthySeconds=${"%.1f".format(Locale.US, header.healthyExposureSeconds)}"
                if (header.processInterrupted) lines += "process=interrupted"
            }
            return PrivacyRedactor.redact(lines.joinToString("\n"))
        }

        fun enforceSize(bundle: FeedIncidentBundle, maxBytes: Int): FeedIncidentBundle {
            var current = bundle
            repeat(6) {
                if (FeedIncidentJson.encodedSize(current) <= maxBytes) return current
                current.header.evictions += 1
                current =
                    when {
                        current.during.size > 8 ->
                            current.copy(during = FeedIncidentSampling.downsample(current.during, 8))
                        current.prelude.size > 8 ->
                            current.copy(prelude = FeedIncidentSampling.downsample(current.prelude, 8))
                        current.aftermath.size > 4 ->
                            current.copy(aftermath = FeedIncidentSampling.downsample(current.aftermath, 4))
                        current.breadcrumbs.size > 4 ->
                            current.copy(breadcrumbs = current.breadcrumbs.takeLast(4))
                        current.repairs.size > 4 ->
                            current.copy(repairs = current.repairs.takeLast(4))
                        else ->
                            current.copy(
                                during = emptyList(),
                                prelude = current.prelude.takeLast(2),
                                aftermath = current.aftermath.takeLast(2),
                            )
                    }
            }
            return current
        }
    }

    private fun write(bundle: FeedIncidentBundle) {
        directory.mkdirs()
        val file = File(directory, FeedIncidentFileNaming.incident(bundle.header.incidentId))
        val bytes = FeedIncidentJson.encode(bundle)
        val tmp = File(directory, file.name + ".tmp")
        tmp.writeBytes(bytes)
        if (!tmp.renameTo(file)) {
            file.writeBytes(bytes)
            tmp.delete()
        }
    }

    private fun load(file: File): FeedIncidentBundle? {
        if (!file.isFile) return null
        return runCatching { FeedIncidentJson.decode(file.readBytes()) }.getOrNull()
    }

    private fun urls(): List<File> {
        val files = directory.listFiles() ?: return emptyList()
        return files.filter { it.name.startsWith("incident-") && it.extension == "json" }
    }
}
