package com.opencapture.openpocketcine.diagnostics

import java.util.UUID

/**
 * Bounded in-memory recorder. Persistence is a returned job; this type never
 * writes files. One open incident covers a continuous outage.
 */
internal class FeedIncidentRecorder(
    private val makeIncidentId: () -> String = { UUID.randomUUID().toString() },
) {
    private var session: FeedIncidentSessionContext? = null
    private val ring = ArrayDeque<FeedIncidentSnapshot>(FeedIncidentBounds.RING_COUNT)
    private val breadcrumbs = ArrayDeque<FeedIncidentBreadcrumb>(FeedIncidentBounds.BREADCRUMB_RING)
    private val repairs = ArrayDeque<FeedRepairRecord>(FeedIncidentBounds.REPAIR_RING)
    private var open: OpenIncident? = null
    private var lastSampleAt: Double? = null
    var healthyExposure: Double = 0.0
        private set
    var incidentCount: Int = 0
        private set

    val hasSession: Boolean get() = session != null
    val openHeader: FeedIncidentHeader? get() = open?.header
    val isCollectingAftermath: Boolean get() = open?.aftermathEndsAt != null

    fun beginSession(context: FeedIncidentSessionContext): FeedIncidentPersistenceJob? {
        val leftover = finalizeOpen(FeedIncidentOutcome.SUPPRESSED, ring.lastOrNull()?.monotonicNow ?: 0.0)
        session = context
        ring.clear()
        breadcrumbs.clear()
        repairs.clear()
        lastSampleAt = null
        healthyExposure = 0.0
        incidentCount = 0
        return leftover
    }

    fun endSession(now: Double): FeedIncidentPersistenceJob? {
        val job = finalizeOpen(FeedIncidentOutcome.SUPPRESSED, now)
        session = null
        ring.clear()
        breadcrumbs.clear()
        repairs.clear()
        lastSampleAt = null
        return job
    }

    fun noteDecoderGeneration(generation: Int) {
        session?.decoderGeneration = generation.coerceAtLeast(0)
        open?.header?.decoderGeneration = generation.coerceAtLeast(0)
    }

    fun noteSocketGeneration(generation: Int) {
        session?.socketGeneration = generation.coerceAtLeast(0)
        open?.header?.socketGeneration = generation.coerceAtLeast(0)
    }

    fun noteTestSource(source: FeedIncidentTestSource) {
        val current = session ?: return
        if (source.rank <= current.testSource.rank) return
        current.testSource = source
    }

    fun noteExhausted(now: Double): FeedIncidentPersistenceJob? {
        val current = open ?: return null
        if (current.header.outcome != FeedIncidentOutcome.OPEN &&
            current.header.outcome != FeedIncidentOutcome.EXHAUSTED
        ) {
            return null
        }
        current.header.outcome = FeedIncidentOutcome.EXHAUSTED
        current.header.endedAtMonotonic = now
        return FeedIncidentPersistenceJob(current.bundle(), FeedIncidentPersistenceJob.Reason.OUTCOME)
    }

    fun recordBreadcrumb(breadcrumb: FeedIncidentBreadcrumb) {
        breadcrumbs.addLast(breadcrumb)
        trim(breadcrumbs, FeedIncidentBounds.BREADCRUMB_RING)
        open?.let { incident ->
            incident.breadcrumbs.add(breadcrumb)
            if (incident.breadcrumbs.size > FeedIncidentBounds.BREADCRUMB_RING) {
                incident.header.evictions += 1
                incident.breadcrumbs.removeAt(0)
            }
        }
    }

    fun recordRepair(repair: FeedRepairRecord): FeedIncidentPersistenceJob? {
        repairs.addLast(repair)
        trim(repairs, FeedIncidentBounds.REPAIR_RING)
        val current = open ?: return null
        current.repairs.add(repair)
        if (current.repairs.size > FeedIncidentBounds.REPAIR_RING) {
            current.header.evictions += 1
            current.repairs.removeAt(0)
        }
        return FeedIncidentPersistenceJob(current.bundle(), FeedIncidentPersistenceJob.Reason.REPAIR)
    }

    fun noteUnexpectedDisconnect(now: Double): FeedIncidentPersistenceJob? {
        if (session == null) return null
        recordBreadcrumb(
            FeedIncidentBreadcrumb(now, FeedIncidentBreadcrumbKind.PATH_CHANGE, "unexpectedDisconnect"),
        )
        if (open != null) {
            return checkpointIfNeeded(ring.lastOrNull() ?: FeedIncidentSnapshot(monotonicNow = now))
        }
        val snapshot =
            ring.lastOrNull()
                ?: FeedIncidentSnapshot(
                    monotonicNow = now,
                    lifecycle = FeedIncidentLifecycle(connected = true, liveEstablished = true),
                )
        return startIncident(
            snapshot,
            FeedIncidentKind.UNEXPECTED_DISCONNECT,
            FeedIncidentFailingStage.PACKET,
        )
    }

    fun recordSnapshot(snapshot: FeedIncidentSnapshot): FeedIncidentPersistenceJob? {
        appendRing(snapshot)
        noteExposure(snapshot)
        if (session == null) return null
        val verdict = FeedIncidentClassifier.classify(snapshot)
        val recovered = FeedIncidentClassifier.isRecovered(snapshot)
        if (open != null) {
            if (recovered) {
                if (open?.aftermathEndsAt != null) return collectAftermath(snapshot)
                return beginAftermath(snapshot.monotonicNow, snapshot)
            }
            if (verdict.suppression == FeedIncidentSuppression.DISCONNECTED ||
                verdict.suppression == FeedIncidentSuppression.PLAYBACK
            ) {
                return finalizeOpen(FeedIncidentOutcome.SUPPRESSED, snapshot.monotonicNow)
            }
            if (verdict.suppression == FeedIncidentSuppression.BACKGROUND) {
                return checkpointIfNeeded(snapshot)
            }
            return continueOpen(snapshot, verdict)
        }
        if (!verdict.shouldRecord) return null
        val kind = verdict.kind ?: return null
        val stage = verdict.failingStage ?: return null
        return startIncident(snapshot, kind, stage)
    }

    fun exportOpen(): FeedIncidentBundle? = open?.bundle()

    private fun startIncident(
        snapshot: FeedIncidentSnapshot,
        kind: FeedIncidentKind,
        stage: FeedIncidentFailingStage,
    ): FeedIncidentPersistenceJob? {
        val session = session ?: return null
        val gap = FeedIncidentPrivacy.gapSeconds(snapshot, stage)
        val header =
            FeedIncidentHeader(
                incidentId = FeedIncidentPrivacy.token(makeIncidentId()),
                sessionId = session.sessionId,
                kind = kind,
                failingStage = stage,
                errorClass = snapshot.decoder.errorClass,
                outcome = FeedIncidentOutcome.OPEN,
                startedAtWallClockMs = snapshot.wallClockMs,
                startedAtMonotonic = snapshot.monotonicNow,
                firstFailureAt = snapshot.monotonicNow,
                worstGapSeconds = gap,
                appVersion = session.appVersion,
                appBuild = session.appBuild,
                sourceRevision = session.sourceRevision,
                osName = session.osName,
                osVersion = session.osVersion,
                hardwareClass = session.hardwareClass,
                cameraFamily = session.cameraFamily,
                cameraFirmware = session.cameraFirmware,
                decoderGeneration =
                    if (snapshot.decoder.generation > 0) snapshot.decoder.generation
                    else session.decoderGeneration,
                socketGeneration = session.socketGeneration,
                assistState = snapshot.lifecycle.assistState,
                healthyExposureSeconds = healthyExposure,
                testSource = session.testSource,
                buildIdentity = session.buildIdentity,
            )
        val incident =
            OpenIncident(header, ring.toMutableList()).also {
                it.breadcrumbs.addAll(breadcrumbs)
                it.repairs.addAll(repairs)
                it.noteError(snapshot.decoder.errorClass)
            }
        open = incident
        incidentCount += 1
        return FeedIncidentPersistenceJob(incident.bundle(), FeedIncidentPersistenceJob.Reason.STARTED)
    }

    private fun continueOpen(
        snapshot: FeedIncidentSnapshot,
        verdict: FeedIncidentVerdict,
    ): FeedIncidentPersistenceJob? {
        val current = open ?: return null
        if (current.aftermathEndsAt != null) {
            current.aftermathEndsAt = null
            current.aftermath.clear()
            current.header.outcome = FeedIncidentOutcome.OPEN
            current.header.endedAtMonotonic = null
        }
        verdict.failingStage?.let { stage ->
            val gap = FeedIncidentPrivacy.gapSeconds(snapshot, stage)
            if (gap > current.header.worstGapSeconds) {
                current.header.worstGapSeconds = gap
                current.header.failingStage = stage
            }
            if (verdict.kind == FeedIncidentKind.DECODER_ERROR && current.header.errorClass == null) {
                current.header.kind = verdict.kind
                current.header.errorClass = snapshot.decoder.errorClass
            }
        }
        current.appendDuring(snapshot)
        current.noteError(snapshot.decoder.errorClass)
        current.header.assistState = snapshot.lifecycle.assistState
        current.snapshotsUntilCheckpoint -= 1
        if (current.snapshotsUntilCheckpoint <= 0) {
            current.snapshotsUntilCheckpoint = 5
            return FeedIncidentPersistenceJob(current.bundle(), FeedIncidentPersistenceJob.Reason.CHECKPOINT)
        }
        return null
    }

    private fun beginAftermath(now: Double, snapshot: FeedIncidentSnapshot?): FeedIncidentPersistenceJob? {
        val current = open ?: return null
        if (current.aftermathEndsAt == null) {
            if (current.header.outcome != FeedIncidentOutcome.EXHAUSTED) {
                current.header.outcome = FeedIncidentOutcome.RECOVERED
            }
            current.header.endedAtMonotonic = now
            current.aftermathEndsAt = now + FeedIncidentBounds.AFTERMATH_SECONDS
        }
        if (snapshot != null) current.appendAftermath(snapshot)
        return FeedIncidentPersistenceJob(current.bundle(), FeedIncidentPersistenceJob.Reason.OUTCOME)
    }

    private fun collectAftermath(snapshot: FeedIncidentSnapshot): FeedIncidentPersistenceJob? {
        val current = open ?: return null
        val end = current.aftermathEndsAt ?: return null
        current.appendAftermath(snapshot)
        if (snapshot.monotonicNow >= end) {
            val job = FeedIncidentPersistenceJob(current.bundle(), FeedIncidentPersistenceJob.Reason.OUTCOME)
            open = null
            return job
        }
        return null
    }

    private fun checkpointIfNeeded(snapshot: FeedIncidentSnapshot): FeedIncidentPersistenceJob? {
        val current = open ?: return null
        current.appendDuring(snapshot)
        current.snapshotsUntilCheckpoint -= 1
        if (current.snapshotsUntilCheckpoint <= 0) {
            current.snapshotsUntilCheckpoint = 5
            return FeedIncidentPersistenceJob(current.bundle(), FeedIncidentPersistenceJob.Reason.CHECKPOINT)
        }
        return null
    }

    private fun finalizeOpen(outcome: FeedIncidentOutcome, now: Double): FeedIncidentPersistenceJob? {
        val current = open ?: return null
        current.header.outcome = outcome
        current.header.endedAtMonotonic = now
        val job = FeedIncidentPersistenceJob(current.bundle(), FeedIncidentPersistenceJob.Reason.OUTCOME)
        open = null
        return job
    }

    private fun appendRing(snapshot: FeedIncidentSnapshot) {
        val last = ring.lastOrNull()
        if (last != null && snapshot.monotonicNow + 0.0001 < last.monotonicNow) return
        if (last != null && snapshot.monotonicNow - last.monotonicNow < 0.9) {
            ring.removeLast()
        }
        ring.addLast(snapshot)
        val cutoff = snapshot.monotonicNow - FeedIncidentBounds.PRELUDE_SECONDS
        while (ring.isNotEmpty() && ring.first().monotonicNow < cutoff) ring.removeFirst()
        while (ring.size > FeedIncidentBounds.RING_COUNT) ring.removeFirst()
    }

    private fun noteExposure(snapshot: FeedIncidentSnapshot) {
        val now = snapshot.monotonicNow
        val last = lastSampleAt
        if (last != null && session != null && FeedIncidentClassifier.isRecovered(snapshot)) {
            healthyExposure += minOf(1.5, maxOf(0.0, now - last))
        }
        lastSampleAt = now
    }

    private fun <T> trim(items: ArrayDeque<T>, keep: Int) {
        while (items.size > keep) items.removeFirst()
    }

    private class OpenIncident(
        val header: FeedIncidentHeader,
        val prelude: MutableList<FeedIncidentSnapshot>,
        val during: MutableList<FeedIncidentSnapshot> = mutableListOf(),
        val aftermath: MutableList<FeedIncidentSnapshot> = mutableListOf(),
        val breadcrumbs: MutableList<FeedIncidentBreadcrumb> = mutableListOf(),
        val repairs: MutableList<FeedRepairRecord> = mutableListOf(),
        val aggregatedErrors: MutableMap<String, Int> = linkedMapOf(),
        var aftermathEndsAt: Double? = null,
        var snapshotsUntilCheckpoint: Int = 5,
    ) {
        fun appendDuring(snapshot: FeedIncidentSnapshot) {
            during.add(snapshot)
            if (during.size > FeedIncidentBounds.DURING_COUNT) {
                header.evictions += during.size - FeedIncidentBounds.DURING_COUNT
                val kept = FeedIncidentSampling.downsample(during, FeedIncidentBounds.DURING_COUNT)
                during.clear()
                during.addAll(kept)
            }
        }

        fun appendAftermath(snapshot: FeedIncidentSnapshot) {
            aftermath.add(snapshot)
            if (aftermath.size > 30) {
                header.evictions += 1
                aftermath.removeAt(0)
            }
        }

        fun noteError(errorClass: String?) {
            if (errorClass.isNullOrEmpty()) return
            aggregatedErrors[errorClass] = (aggregatedErrors[errorClass] ?: 0) + 1
            if (header.errorClass == null) header.errorClass = errorClass
            if (aggregatedErrors.size > FeedIncidentBounds.ERROR_CLASSES) {
                val rare = aggregatedErrors.minByOrNull { it.value }?.key
                if (rare != null) {
                    aggregatedErrors.remove(rare)
                    header.evictions += 1
                }
            }
        }

        fun bundle(): FeedIncidentBundle {
            val errors =
                aggregatedErrors.keys.sorted().map {
                    FeedIncidentErrorCount(it, aggregatedErrors[it] ?: 0)
                }
            return FeedIncidentBundle(
                header = header.copy(),
                prelude = prelude.toList(),
                during = during.toList(),
                aftermath = aftermath.toList(),
                breadcrumbs = breadcrumbs.toList(),
                repairs = repairs.toList(),
                aggregatedErrors = errors,
            )
        }
    }
}
