package com.opencapture.openpocketcine.diagnostics

import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Shell owner for feed-incident persistence. Recorder stays in memory; this
 * type writes on a dedicated utility thread. Never call persist from receive,
 * decode, display, or fatal-signal handlers.
 */
internal object FeedIncidentRuntime {
    private val writer =
        Executors.newSingleThreadExecutor { thread ->
            Thread(thread, "opc.feed-incident").apply { isDaemon = true }
        }
    private val recorder = FeedIncidentRecorder()
    private var store: FeedIncidentStore? = null
    @Volatile private var latestSnapshot: FeedIncidentSnapshot? = null
    private val snapshotScheduled = AtomicBoolean(false)
    private var sessionContext: FeedIncidentSessionContext? = null
    private var lastSummaryCheckpoint = 0.0

    fun install(directory: File) {
        writer.execute {
            val created = FeedIncidentStore(File(directory, "incidents"))
            store = created
            created.markInterrupted()
            FeedSessionSummaryStore.markInterrupted(created.directory)
        }
    }

    fun deleteStoredReports(completion: (Boolean) -> Unit) {
        writer.execute {
            val deleted = runCatching {
                val saved = store ?: return@runCatching false
                val incidentsDeleted = saved.deleteAll()
                val summariesDeleted = FeedSessionSummaryStore.deleteAll(saved.directory)
                incidentsDeleted && summariesDeleted
            }.getOrDefault(false)
            android.os.Handler(android.os.Looper.getMainLooper()).post { completion(deleted) }
        }
    }

    fun beginSession(context: FeedIncidentSessionContext) {
        writer.execute {
            persist(recorder.beginSession(context))
            sessionContext = context
            lastSummaryCheckpoint = 0.0
            persistSessionSummary("live")
        }
    }

    fun endSession(nowSeconds: Double) {
        writer.execute {
            persist(recorder.endSession(nowSeconds))
            persistSessionSummary(summaryOutcome(recorder.incidentCount, recorder.healthyExposure))
            sessionContext = null
            ReliabilityReporting.enqueueFinalizedFromSpool()
        }
    }

    fun ingestSnapshot(snapshot: FeedIncidentSnapshot) {
        latestSnapshot = snapshot
        if (snapshotScheduled.compareAndSet(false, true)) {
            writer.execute { drainSnapshot() }
        }
    }

    fun recordBreadcrumb(breadcrumb: FeedIncidentBreadcrumb) {
        writer.execute {
            recorder.recordBreadcrumb(breadcrumb)
            ReliabilityReporting.noteBreadcrumb(breadcrumb)
        }
    }

    fun recordRepair(repair: FeedRepairRecord) {
        writer.execute {
            persist(recorder.recordRepair(repair))
            ReliabilityReporting.noteRepair(repair)
        }
    }

    fun noteTestSource(source: FeedIncidentTestSource) {
        writer.execute {
            recorder.noteTestSource(source)
            val context = sessionContext
            if (context != null && source.rank > context.testSource.rank) {
                context.testSource = source
            }
        }
    }

    fun noteDecoderGeneration(generation: Int) {
        writer.execute { recorder.noteDecoderGeneration(generation) }
    }

    fun noteSocketGeneration(generation: Int) {
        writer.execute { recorder.noteSocketGeneration(generation) }
    }

    fun noteExhausted(nowSeconds: Double) {
        writer.execute { persist(recorder.noteExhausted(nowSeconds)) }
    }

    fun noteUnexpectedDisconnect(nowSeconds: Double) {
        writer.execute { persist(recorder.noteUnexpectedDisconnect(nowSeconds)) }
    }

    fun exportText(): String {
        val future = writer.submit<String> { store?.exportText().orEmpty() }
        return runCatching { future.get(2, java.util.concurrent.TimeUnit.SECONDS) }.getOrDefault("")
    }

    fun exportExtras(): List<Pair<String, String>> {
        val future =
            writer.submit<List<Pair<String, String>>> { store?.exportExtras().orEmpty() }
        return runCatching { future.get(2, java.util.concurrent.TimeUnit.SECONDS) }.getOrDefault(emptyList())
    }

    /** Manual-report extras: typed incidents plus compact session summaries. */
    fun reportExtras(): List<Pair<String, String>> {
        val extras = exportExtras().toMutableList()
        val summaries = loadSessionSummaries().sortedByDescending { it.recordedAtMs }
        summaries.firstOrNull()?.let { newest ->
            extras += "session-summary.json" to PrivacyRedactor.redact(FeedSessionSummaryStore.encodeForReport(newest))
        }
        for (summary in summaries.drop(1).take(4)) {
            extras +=
                "session-${summary.sessionID}.json" to
                    PrivacyRedactor.redact(FeedSessionSummaryStore.encodeForReport(summary))
        }
        return extras
    }

    fun loadFinalized(): List<FeedIncidentBundle> {
        val future =
            writer.submit<List<FeedIncidentBundle>> {
                store?.loadAll()?.filter { ReliabilityReporting.isFinalized(it) }.orEmpty()
            }
        return runCatching { future.get(2, java.util.concurrent.TimeUnit.SECONDS) }.getOrDefault(emptyList())
    }

    fun loadSessionSummaries(): List<FeedIncidentSessionSummary> {
        val future =
            writer.submit<List<FeedIncidentSessionSummary>> {
                val root = store?.directory ?: return@submit emptyList()
                FeedSessionSummaryStore.load(root).filter { it.outcome != "live" }
            }
        return runCatching { future.get(2, java.util.concurrent.TimeUnit.SECONDS) }.getOrDefault(emptyList())
    }

    fun summaryOutcome(incidentCount: Int, exposure: Double): String {
        if (incidentCount > 0) return "ended"
        if (exposure > 0.0) return "healthy"
        return "no-exposure"
    }

    private fun drainSnapshot() {
        val snapshot = latestSnapshot
        latestSnapshot = null
        snapshotScheduled.set(false)
        if (snapshot != null) {
            persist(recorder.recordSnapshot(snapshot))
            if (snapshot.monotonicNow - lastSummaryCheckpoint >= 30.0) {
                lastSummaryCheckpoint = snapshot.monotonicNow
                persistSessionSummary("live")
            }
        }
    }

    private fun persistSessionSummary(outcome: String) {
        val context = sessionContext ?: return
        val summary =
            FeedIncidentSessionSummary(
                sessionID = context.sessionId,
                healthyExposureSeconds = recorder.healthyExposure,
                incidentCount = recorder.incidentCount,
                outcome = outcome,
                sourceRevision = context.sourceRevision,
                appVersion = context.appVersion,
                appBuild = context.appBuild,
                testSource = context.testSource,
                buildIdentity = context.buildIdentity,
            )
        val root = store?.directory ?: return
        FeedSessionSummaryStore.persist(summary, root)
        if (summary.outcome != "live") ReliabilityReporting.noteSessionSummary(summary)
    }

    private fun persist(job: FeedIncidentPersistenceJob?) {
        if (job == null) return
        runCatching { store?.persist(job) }
        if (ReliabilityReporting.isFinalized(job.bundle)) {
            ReliabilityReporting.enqueueFinalized(job.bundle)
        }
    }
}
