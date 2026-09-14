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

    fun install(directory: File) {
        writer.execute {
            val created = FeedIncidentStore(File(directory, "incidents"))
            store = created
            created.markInterrupted()
        }
    }

    fun beginSession(context: FeedIncidentSessionContext) {
        writer.execute { persist(recorder.beginSession(context)) }
    }

    fun endSession(nowSeconds: Double) {
        writer.execute { persist(recorder.endSession(nowSeconds)) }
    }

    fun ingestSnapshot(snapshot: FeedIncidentSnapshot) {
        latestSnapshot = snapshot
        if (snapshotScheduled.compareAndSet(false, true)) {
            writer.execute { drainSnapshot() }
        }
    }

    fun recordBreadcrumb(breadcrumb: FeedIncidentBreadcrumb) {
        writer.execute { recorder.recordBreadcrumb(breadcrumb) }
    }

    fun recordRepair(repair: FeedRepairRecord) {
        writer.execute { persist(recorder.recordRepair(repair)) }
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

    private fun drainSnapshot() {
        val snapshot = latestSnapshot
        latestSnapshot = null
        snapshotScheduled.set(false)
        if (snapshot != null) persist(recorder.recordSnapshot(snapshot))
    }

    private fun persist(job: FeedIncidentPersistenceJob?) {
        if (job == null) return
        runCatching { store?.persist(job) }
    }
}
