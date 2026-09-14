package com.opencapture.openpocketcine.diagnostics

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FeedIncidentStoreTest {
    @Test
    fun persistIsAtomicAndSurvivesRereadWithoutCredentialsOrFrames() {
        val dir = File.createTempFile("opc-incidents", "").apply { delete(); mkdirs() }
        try {
            val store = FeedIncidentStore(dir)
            val bundle = sampleBundle("inc-a")
            store.persist(
                FeedIncidentPersistenceJob(bundle, FeedIncidentPersistenceJob.Reason.STARTED),
                nowMs = bundle.header.startedAtWallClockMs,
            )
            val loaded = store.loadAll().single()
            assertEquals("inc-a", loaded.header.incidentId)
            assertEquals(FeedIncidentKind.FRESH_INPUT_STALE_OUTPUT, loaded.header.kind)
            val json = String(File(dir, "incident-inc-a.json").readBytes())
            assertTrue(json.contains("\"incidentID\":\"inc-a\""))
            assertTrue(json.contains("sourceRevision"))
            assertFalse(json.contains("password"))
            assertFalse(json.contains("192.168.1."))
            assertFalse(json.contains("00 00 00 01"))
            dir.listFiles()?.none { it.name.endsWith(".tmp") }?.let { assertTrue(it) }
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun leftoverOpenIncidentsAreInterruptedNotCrashes() {
        val dir = File.createTempFile("opc-incidents", "").apply { delete(); mkdirs() }
        try {
            val store = FeedIncidentStore(dir)
            store.persist(
                FeedIncidentPersistenceJob(sampleBundle("inc-open"), FeedIncidentPersistenceJob.Reason.STARTED),
                nowMs = 1_000,
            )
            val changed = store.markInterrupted(nowMs = 1_000)
            assertEquals(listOf("inc-open"), changed)
            assertEquals(FeedIncidentOutcome.INTERRUPTED, store.loadAll().single().header.outcome)
            assertTrue(store.loadAll().single().header.processInterrupted)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun retentionDropsOldestWhenCountCapIsReached() {
        val dir = File.createTempFile("opc-incidents", "").apply { delete(); mkdirs() }
        try {
            val store = FeedIncidentStore(dir, FeedIncidentLimits(maxBundles = 2, ttlMs = 86_400_000))
            store.persist(job("id-0", started = 1_000), nowMs = 3_000)
            store.persist(job("id-1", started = 2_000), nowMs = 3_000)
            store.persist(job("id-2", started = 3_000), nowMs = 3_000)
            val ids = store.loadAll().map { it.header.incidentId }
            assertEquals(2, ids.size)
            assertFalse(ids.contains("id-0"))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun ttlEvictsExpiredBundlesAndCorruptFilesAreIgnored() {
        val dir = File.createTempFile("opc-incidents", "").apply { delete(); mkdirs() }
        try {
            val store = FeedIncidentStore(dir, FeedIncidentLimits(ttlMs = 1_000))
            store.persist(job("old", started = 1_000), nowMs = 1_000)
            File(dir, "incident-bad.json").writeText("{not-json")
            store.applyRetention(nowMs = 10_000)
            assertTrue(store.loadAll().isEmpty())
            assertTrue(File(dir, "incident-bad.json").exists())
            assertTrue(store.loadAll().none { it.header.incidentId == "bad" })
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun exportExtrasIncludesTypedJsonNotOnlyAHeaderListing() {
        val dir = File.createTempFile("opc-incidents", "").apply { delete(); mkdirs() }
        try {
            val store = FeedIncidentStore(dir)
            store.persist(
                FeedIncidentPersistenceJob(sampleBundle("inc-json"), FeedIncidentPersistenceJob.Reason.STARTED),
                nowMs = 1_000,
            )
            val extras = store.exportExtras()
            val names = extras.map { it.first }
            assertTrue(names.contains("incidents.txt"))
            assertTrue(names.contains("incident-inc-json.json"))
            val listing = extras.first { it.first == "incidents.txt" }.second
            assertTrue(listing.contains("decoderGen="))
            assertTrue(listing.contains("breadcrumbs="))
            val json = extras.first { it.first.endsWith(".json") }.second
            assertTrue(json.contains("\"prelude\""))
            assertTrue(json.contains("\"during\""))
            assertTrue(json.contains("decodedOutputAge"))
            assertTrue(json.contains("outputObservable"))
            assertTrue(json.contains("presentationExpected"))
            assertFalse(json.contains("password"))
            assertFalse(json.contains("00 00 00 01"))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun exportExtrasRedactsIdentifiersAndOmitsAnnexB() {
        val dir = File.createTempFile("opc-incidents", "").apply { delete(); mkdirs() }
        try {
            val store = FeedIncidentStore(dir)
            val dirty =
                sampleBundle("inc-redact").copy(
                    breadcrumbs =
                        listOf(
                            FeedIncidentBreadcrumb(
                                1.0,
                                FeedIncidentBreadcrumbKind.SETTINGS_ENTER,
                                "password=hunter2 ssid=CafeWiFi aa:bb:cc:dd:ee:ff",
                            ),
                        ),
                )
            store.persist(
                FeedIncidentPersistenceJob(dirty, FeedIncidentPersistenceJob.Reason.STARTED),
                nowMs = 1_000,
            )
            val extras = store.exportExtras()
            val joined = extras.joinToString("\n") { it.second }
            assertFalse(joined.contains("hunter2"))
            assertTrue(joined.contains("password=<redacted>"))
            assertTrue(joined.contains("ssid=<redacted>"))
            assertTrue(joined.contains("<mac>"))
            assertFalse(joined.contains("00 00 00 01"))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun exportExtrasStopsBeforeTheTotalByteCap() {
        val dir = File.createTempFile("opc-incidents", "").apply { delete(); mkdirs() }
        try {
            val store = FeedIncidentStore(dir)
            store.persist(job("id-0", started = 1_000), nowMs = 3_000)
            store.persist(job("id-1", started = 2_000), nowMs = 3_000)
            val unlimited = store.exportExtras(maxTotalBytes = Int.MAX_VALUE)
            val listing = unlimited.first { it.first == "incidents.txt" }.second
            val firstJson = unlimited.first { it.first.endsWith(".json") }.second
            val capped = store.exportExtras(maxTotalBytes = listing.length + firstJson.length + 1)
            assertTrue(capped.any { it.first == "incidents.txt" })
            assertEquals(1, capped.count { it.first.endsWith(".json") })
            assertTrue(capped.sumOf { it.second.length } <= listing.length + firstJson.length + 1)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun enforceSizeEvictsSnapshotsToStayUnderTheByteCap() {
        val huge =
            sampleBundle("inc-size").copy(
                prelude = List(80) { sampleSnapshot(it.toDouble()) },
                during = List(80) { sampleSnapshot(100.0 + it) },
            )
        val limited = FeedIncidentStore.enforceSize(huge, maxBytes = 8_192)
        assertTrue(FeedIncidentJson.encodedSize(limited) <= 8_192)
        assertTrue(limited.header.evictions > 0)
        assertTrue(limited.prelude.size + limited.during.size < huge.prelude.size + huge.during.size)
    }

    private fun job(id: String, started: Long) =
        FeedIncidentPersistenceJob(
            sampleBundle(id).copy(header = sampleBundle(id).header.copy(incidentId = id, startedAtWallClockMs = started)),
            FeedIncidentPersistenceJob.Reason.STARTED,
        )

    private fun sampleBundle(id: String) =
        FeedIncidentBundle(
            header =
                FeedIncidentHeader(
                    incidentId = id,
                    sessionId = "session-1",
                    kind = FeedIncidentKind.FRESH_INPUT_STALE_OUTPUT,
                    failingStage = FeedIncidentFailingStage.DECODED_OUTPUT,
                    startedAtWallClockMs = 1_000,
                    startedAtMonotonic = 1.0,
                    firstFailureAt = 1.0,
                    worstGapSeconds = 5.0,
                    appVersion = "0.1.0",
                    appBuild = "2",
                    sourceRevision = "abc1234+",
                    osName = "Android",
                    osVersion = "16",
                    hardwareClass = "Pixel",
                    cameraFamily = "pocket",
                ),
            prelude = listOf(sampleSnapshot(0.0)),
        )

    private fun sampleSnapshot(monotonic: Double) =
        FeedIncidentSnapshot(
            monotonicNow = monotonic,
            wallClockMs = 1_000,
            rates = FeedIncidentRates(packetHz = 25.0, decodedOutputHz = 0.0),
            ages = FeedIncidentAges(packetAge = 0.04, decodedOutputAge = 5.0),
            lifecycle = FeedIncidentLifecycle(connected = true, liveEstablished = true),
        )
}
