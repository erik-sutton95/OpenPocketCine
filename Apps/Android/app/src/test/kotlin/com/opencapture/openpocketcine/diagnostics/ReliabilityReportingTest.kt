package com.opencapture.openpocketcine.diagnostics

import io.sentry.Breadcrumb
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.protocol.Request
import io.sentry.protocol.SentryException
import io.sentry.protocol.User
import java.io.File
import java.net.URL
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReliabilityReportingTest {
    private lateinit var cacheRoot: File

    @BeforeTest
    fun setUp() {
        cacheRoot = File(System.getProperty("java.io.tmpdir"), "opc-rel-${System.nanoTime()}")
        cacheRoot.mkdirs()
        ReliabilityReporting.sdkCacheRoot = cacheRoot
        ReliabilityReportingConsent.resetForTests()
        ReliabilityReportingDSN.buildDsn = null
        ReliabilityReportingDSN.environment = emptyMap()
        ReliabilityReporting.setCaptureHandlerForTests(null)
        ReliabilityReportingGate.resetForTests()
        ReliabilityReporting.dsnHost = "o0.ingest.sentry.io"
    }

    @AfterTest
    fun tearDown() {
        ReliabilityReporting.setCaptureHandlerForTests(null)
        ReliabilityReportingConsent.resetForTests()
        ReliabilityReportingGate.resetForTests()
        cacheRoot.deleteRecursively()
    }

    @Test
    fun consentDefaultsOffAndRevokePurgesOnlySdkOwnedSpool() {
        assertFalse(ReliabilityReportingConsent.isOptedIn)
        assertFalse(ReliabilityReporting.isOptedIn)
        ReliabilityReportingConsent.setOptedIn(true)
        assertTrue(ReliabilityReporting.isOptedIn)
        val localDir = File(System.getProperty("java.io.tmpdir"), "opc-local-${System.nanoTime()}")
        localDir.mkdirs()
        val local = File(localDir, "incident-keep.json")
        local.writeText("keep")
        ReliabilityReportingReceipts.store(
            ReliabilityReportingReceipt(
                incidentID = "inc-1",
                eventID = "abc",
                state = ReliabilityReportingReceiptState.QUEUED,
                updatedAt = System.currentTimeMillis(),
            ),
            cacheRoot,
        )
        assertNotNull(ReliabilityReportingReceipts.load("inc-1", cacheRoot))
        ReliabilityReporting.setConsent(false)
        assertFalse(ReliabilityReporting.isOptedIn)
        waitUntil { ReliabilityReportingReceipts.load("inc-1", cacheRoot) == null }
        assertNull(ReliabilityReportingReceipts.load("inc-1", cacheRoot))
        assertTrue(local.isFile)
        localDir.deleteRecursively()
    }

    @Test
    fun dsnRequiresHttpsSentryShape() {
        assertNull(ReliabilityReportingDSN.validated(""))
        assertNull(ReliabilityReportingDSN.validated("http://key@host/1"))
        assertNull(ReliabilityReportingDSN.validated("https://ingest.sentry.io/1"))
        assertNull(ReliabilityReportingDSN.validated("https://key:secret@ingest.sentry.io/1"))
        assertNull(ReliabilityReportingDSN.validated("https://key@ingest.sentry.io/1?token=value"))
        assertNull(ReliabilityReportingDSN.validated("https://key@ingest.sentry.io/1#frag"))
        assertNull(ReliabilityReportingDSN.validated("https://key@ingest.sentry.io/not-a-project"))
        assertNotNull(ReliabilityReportingDSN.validated("https://publickey@o0.ingest.sentry.io/0"))
        ReliabilityReportingDSN.buildDsn = ""
        assertFalse(ReliabilityReportingDSN.isAvailable)
        ReliabilityReportingDSN.buildDsn = "https://publickey@o0.ingest.sentry.io/0"
        assertTrue(ReliabilityReportingDSN.isAvailable)
    }

    @Test
    fun cameraGateBlocksEvenWithInternetAndCancelsPending() {
        val fake = FakeTask()
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingGate.setValidInternetForTests(true)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
        ReliabilityReportingGate.setCameraSessionActive(false)
        ReliabilityReportingGate.register(fake)
        assertFalse(ReliabilityReportingGate.shouldBlockUpload)
        assertTrue(ReliabilityReportingGate.isConnected)
        ReliabilityReportingGate.setCameraSessionActive(true)
        assertTrue(ReliabilityReportingGate.shouldBlockUpload)
        assertFalse(ReliabilityReportingGate.isConnected)
        assertTrue(fake.cancelled)
        ReliabilityReportingGate.setCameraSessionActive(false)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(true)
        assertTrue(ReliabilityReportingGate.shouldBlockUpload)
        assertFalse(ReliabilityReportingGate.isConnected)
    }

    @Test
    fun manualRegisterSurvivesMissingConsentAndConsentRevoke() {
        val fake = object : ReliabilityReportingCancellable {
            var cancelled = false
            override val independentOfAutomaticConsent = true
            override fun cancel() {
                cancelled = true
            }
        }
        ReliabilityReportingConsent.setOptedIn(false)
        ReliabilityReportingGate.setValidInternetForTests(true)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
        ReliabilityReportingGate.setCameraSessionActive(false)
        ReliabilityReportingGate.register(fake)
        assertFalse(fake.cancelled)
        ReliabilityReportingGate.cancelPending(includeIndependent = false)
        assertFalse(fake.cancelled)
        ReliabilityReportingGate.setCameraSessionActive(true)
        assertTrue(fake.cancelled)
    }

    @Test
    fun automaticPromptIsOffUntilConfiguredAndUndecided() {
        ReliabilityReportingDSN.buildDsn = null
        assertFalse(ReliabilityReportingConsent.shouldOfferAutomaticPrompt())
        ReliabilityReportingDSN.buildDsn = "https://publickey@o0.ingest.sentry.io/0"
        assertTrue(ReliabilityReportingConsent.shouldOfferAutomaticPrompt())
        ReliabilityReportingConsent.setOptedIn(true)
        assertFalse(ReliabilityReportingConsent.shouldOfferAutomaticPrompt())
        ReliabilityReportingConsent.resetForTests()
        ReliabilityReportingDSN.buildDsn = "https://publickey@o0.ingest.sentry.io/0"
        ReliabilityReportingConsent.setOptedIn(false)
        assertFalse(ReliabilityReportingConsent.shouldOfferAutomaticPrompt())
        assertFalse(ReliabilityReportingConsent.isOptedIn)
        assertTrue(ReliabilityReportingConsent.hasDecision)
    }

    @Test
    fun hostIsolationRejectsNonDsnHosts() {
        val dsnHost = "o0.ingest.sentry.io"
        val allowed = URL("https://o0.ingest.sentry.io/api/0/envelope/")
        val other = URL("https://example.com/ingest")
        assertTrue(ReliabilityReportingHostPolicy.allows(allowed, dsnHost))
        assertFalse(ReliabilityReportingHostPolicy.allows(other, dsnHost))
        assertEquals(
            ReliabilityReportingLoadDecision.REJECT_HOST,
            ReliabilityReportingNetwork.decision(other, dsnHost),
        )
        ReliabilityReportingGate.setCameraSessionActive(true)
        assertEquals(
            ReliabilityReportingLoadDecision.BLOCK_CAMERA_PATH,
            ReliabilityReportingNetwork.decision(allowed, dsnHost),
        )
    }

    @Test
    fun revokedConsentDisconnectsTransportGate() {
        ReliabilityReportingConsent.setOptedIn(false)
        ReliabilityReportingGate.setCameraSessionActive(false)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
        ReliabilityReportingGate.setValidInternetForTests(true)
        assertFalse(ReliabilityReportingGate.isConnected)
        ReliabilityReportingConsent.setOptedIn(true)
        assertTrue(ReliabilityReportingGate.isConnected)
    }

    @Test
    fun eventIdAndFingerprintAreStable() {
        val id = "12c2d058-d584-4270-9aa2-eca08bf20986"
        val first = ReliabilityReportingPrivacy.eventId(id)
        val second = ReliabilityReportingPrivacy.eventId(id)
        assertEquals(first.toString(), second.toString())
        assertEquals("12c2d058d58442709aa2eca08bf20986", first.toString())
        val prints =
            ReliabilityReportingPrivacy.fingerprint(
                schema = 1,
                stage = "decodedOutput",
                errorClass = "invalidSession",
            )
        assertEquals(
            listOf("feed-incident", "schema:1", "stage:decodedOutput", "errorClass:invalidSession"),
            prints,
        )
    }

    @Test
    fun scrubRemovesUserRequestBreadcrumbsAndPaths() {
        val event = SentryEvent()
        event.level = SentryLevel.ERROR
        val user = User()
        user.email = "tester@example.com"
        user.username = "example-user"
        event.user = user
        event.request = Request()
        event.breadcrumbs = mutableListOf(Breadcrumb())
        event.setTag("failingStage", "decodedOutput")
        event.setTag("email", "tester@example.com")
        event.setExtra("password", "hunter2")
        event.setExtra("failingStage", "decodedOutput")
        event.contexts["device"] = mapOf("name" to "Example Phone", "model" to "Pixel 9")
        event.contexts["feed"] = mapOf("failingStage" to "decodedOutput", "serial" to "ABC")
        val exception = SentryException()
        exception.value = "/" + "Users/example/Library/crash"
        exception.type = "RuntimeException"
        event.exceptions = mutableListOf(exception)
        ReliabilityReportingPrivacy.scrub(event)
        assertNull(event.user)
        assertNull(event.request)
        assertTrue(event.breadcrumbs.isNullOrEmpty())
        assertNull(event.tags?.get("email"))
        assertEquals("decodedOutput", event.tags?.get("failingStage"))
        assertNull(event.extras?.get("password"))
        assertEquals("decodedOutput", event.extras?.get("failingStage"))
        val device = event.contexts["device"] as? Map<*, *>
        assertNull(device?.get("name"))
        assertEquals("Pixel 9", device?.get("model"))
        val feed = event.contexts["feed"] as? Map<*, *>
        assertNull(feed?.get("serial"))
        assertFalse(event.exceptions?.first()?.value?.contains("example/Library") == true)
        event.setTag("sourceRevision", "a".repeat(40))
        ReliabilityReportingPrivacy.scrub(event)
        assertEquals("a".repeat(40), event.tags?.get("sourceRevision"))
    }

    @Test
    fun queuedIncidentKeepsOriginalReleaseAndOccurrenceTime() {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
        ReliabilityReportingGate.setCameraSessionActive(false)
        val bundle = stallBundle("12121212121212121212121212121212")
        bundle.header.appVersion = "0.1.0"
        bundle.header.appBuild = "107"
        bundle.header.sourceRevision = "a".repeat(40)
        bundle.header.startedAtWallClockMs = 1_780_000_000_000L
        var captured = false
        ReliabilityReporting.setCaptureHandlerForTests { event, _ ->
            captured = true
            assertEquals("com.opencapture.openpocketcine@0.1.0+107", event.release)
            assertEquals("107", event.dist)
            assertEquals(java.util.Date(1_780_000_000_000L), event.timestamp)
            assertEquals("a".repeat(40), event.tags?.get("sourceRevision"))
        }
        ReliabilityReporting.enqueueFinalized(bundle)
        waitUntil { captured }
        assertTrue(captured)
    }

    @Test
    fun queuedReceiptOlderThanFiveMinutesCanRetry() {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
        ReliabilityReportingGate.setCameraSessionActive(false)
        val id = "13131313131313131313131313131313"
        ReliabilityReportingReceipts.store(
            ReliabilityReportingReceipt(
                incidentID = id,
                eventID = id,
                state = ReliabilityReportingReceiptState.QUEUED,
                updatedAt = System.currentTimeMillis() - 301_000L,
            ),
            cacheRoot,
        )
        var captured = 0
        ReliabilityReporting.setCaptureHandlerForTests { _, _ -> captured += 1 }
        ReliabilityReporting.enqueueFinalized(stallBundle(id))
        waitUntil { captured == 1 }
        assertEquals(1, captured)
    }

    @Test
    fun captureEnqueueIsQueuedNotDeliveredAndDedupsConfirmed() {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
        ReliabilityReportingGate.setCameraSessionActive(false)
        val bundle = stallBundle("12c2d058d58442709aa2eca08bf20986")
        var captured = 0
        ReliabilityReporting.setCaptureHandlerForTests { event, data ->
            captured += 1
            assertEquals("12c2d058d58442709aa2eca08bf20986", event.eventId.toString())
            assertEquals("feed-incident", event.fingerprints?.first())
            assertNull(event.user)
            val text = String(data, Charsets.UTF_8)
            assertTrue(text.contains("prelude"))
            assertFalse(text.contains("control-live.log"))
        }
        ReliabilityReporting.enqueueFinalized(bundle)
        waitForReceipt("12c2d058d58442709aa2eca08bf20986", ReliabilityReportingReceiptState.QUEUED)
        assertEquals(1, captured)
        ReliabilityReporting.noteTransportSuccess("12c2d058d58442709aa2eca08bf20986")
        waitForReceipt("12c2d058d58442709aa2eca08bf20986", ReliabilityReportingReceiptState.CONFIRMED)
        ReliabilityReporting.setCaptureHandlerForTests { _, _ -> captured += 1 }
        ReliabilityReporting.enqueueFinalized(bundle)
        Thread.sleep(300)
        assertEquals(1, captured)
    }

    @Test
    fun openCheckpointDoesNotEnqueue() {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
        val open = stallBundle("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", outcome = FeedIncidentOutcome.OPEN)
        assertFalse(ReliabilityReporting.isFinalized(open))
        var captured = false
        ReliabilityReporting.setCaptureHandlerForTests { _, _ -> captured = true }
        ReliabilityReporting.enqueueFinalized(open)
        Thread.sleep(400)
        assertFalse(captured)
        assertNull(ReliabilityReporting.receipt("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    }

    @Test
    fun cameraPathDoesNotEnqueueWhileBlocked() {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingGate.setCameraSessionActive(true)
        val bundle = stallBundle("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        var captured = false
        ReliabilityReporting.setCaptureHandlerForTests { _, _ -> captured = true }
        ReliabilityReporting.enqueueFinalized(bundle)
        Thread.sleep(400)
        assertFalse(captured)
        assertNull(ReliabilityReporting.receipt("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"))
    }

    @Test
    fun vendorEnvelopeMapsStageAndErrorClass() {
        val bundle = stallBundle("cccccccccccccccccccccccccccccccc")
        bundle.header.failingStage = FeedIncidentFailingStage.DECODED_OUTPUT
        bundle.header.errorClass = "invalidSession"
        val envelope = ReliabilityReportingPrivacy.validatedEnvelope(bundle)
        assertNotNull(envelope)
        assertEquals("feed.incident", envelope.eventName)
        assertEquals(1, envelope.schemaVersion)
        assertEquals("decodedOutput", envelope.grouping.failingStage)
        assertEquals("invalidSession", envelope.grouping.errorClass)
        assertEquals(
            listOf("feed-incident", "schema:1", "stage:decodedOutput", "errorClass:invalidSession"),
            ReliabilityReportingPrivacy.fingerprint(
                envelope.schemaVersion,
                envelope.grouping.failingStage,
                envelope.grouping.errorClass,
            ),
        )
        val json = ReliabilityReportingPrivacy.typedJson(bundle)
        assertNotNull(json)
        assertTrue(json.size <= 262_144)
    }

    @Test
    fun unknownStageIsRejected() {
        val bundle = stallBundle("dddddddddddddddddddddddddddddddd")
        bundle.header.failingStage = FeedIncidentFailingStage.PACKET
        val envelope = FeedIncidentExport.envelope(bundle)
        assertTrue(FeedIncidentFailingStage.isKnown(envelope.grouping.failingStage))
        assertFalse(FeedIncidentFailingStage.isKnown("not-a-stage"))
        assertNull(
            ReliabilityReportingPrivacy.validatedEnvelope(
                bundle.copy(
                    header = bundle.header.copy(incidentId = "unknown"),
                ),
            ),
        )
    }

    @Test
    fun optionsDisableScreenshotsReplayProfilingAndPii() {
        val options =
            ReliabilityReporting.makeOptions("https://publickey@o0.ingest.sentry.io/0")
        assertFalse(options.isSendDefaultPii)
        assertFalse(options.isAttachScreenshot)
        assertFalse(options.isAttachViewHierarchy)
        assertFalse(options.isAttachStacktrace)
        assertFalse(options.isEnableAutoSessionTracking)
        assertFalse(options.isEnableUserInteractionTracing)
        assertEquals(0.0, options.sessionReplay.sessionSampleRate)
        assertEquals(0.0, options.sessionReplay.onErrorSampleRate)
        assertEquals(0.0, options.tracesSampleRate)
        assertTrue(options.isAnrEnabled)
        assertTrue(options.isEnableUncaughtExceptionHandler)
        assertEquals(30, options.maxCacheItems)
        assertEquals(256 * 1_024L, options.maxAttachmentSize)
        assertEquals(0, options.shutdownTimeoutMillis)
        assertTrue(options.release.orEmpty().startsWith("com.opencapture.openpocketcine@"))
        assertEquals("2", options.dist)
        assertEquals("development", options.environment)
    }

    @Test
    fun sdkStartsWithConsentEvenOnCameraPath() {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingDSN.buildDsn = "https://publickey@o0.ingest.sentry.io/0"
        ReliabilityReportingGate.setCameraSessionActive(true)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(true)
        assertTrue(ReliabilityReporting.shouldStartSdk())
        assertTrue(ReliabilityReportingGate.shouldBlockUpload)
        assertFalse(ReliabilityReportingGate.isConnected)
    }

    @Test
    fun sessionSummaryDoesNotClaimHealthyAtZeroExposure() {
        assertEquals("healthy", FeedIncidentRuntime.summaryOutcome(0, 12.0))
        assertEquals("no-exposure", FeedIncidentRuntime.summaryOutcome(0, 0.0))
        assertEquals("ended", FeedIncidentRuntime.summaryOutcome(2, 40.0))
    }

    @Test
    fun httpSuccessConfirmsQueuedReceiptAndCameraCancelKeepsItQueued() {
        val server = okhttp3.mockwebserver.MockWebServer()
        server.start()
        try {
            ReliabilityReportingConsent.setOptedIn(true)
            ReliabilityReportingHostPolicy.requireHttps = false
            ReliabilityReporting.dsnHost = server.hostName
            ReliabilityReportingGate.setCameraSessionActive(false)
            ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
            ReliabilityReportingGate.setValidInternetForTests(true)
            val options = io.sentry.SentryOptions()
            options.dsn = "http://key@${server.hostName}/1"
            val details =
                io.sentry.RequestDetails(
                    server.url("/api/0/envelope/").toString(),
                    mapOf("X-Sentry-Auth" to "Sentry sentry_key=key"),
                )
            val eventId = "ffffffffffffffffffffffffffffffff"
            ReliabilityReportingReceipts.store(
                ReliabilityReportingReceipt(
                    incidentID = eventId,
                    eventID = eventId,
                    state = ReliabilityReportingReceiptState.QUEUED,
                    updatedAt = System.currentTimeMillis(),
                ),
                cacheRoot,
            )
            server.enqueue(okhttp3.mockwebserver.MockResponse().setResponseCode(200).setBody("{}"))
            val transport = ReliabilityReportingTransport(options, details)
            transport.send(envelopeWithId(options, eventId), io.sentry.Hint())
            val recorded = server.takeRequest(3, java.util.concurrent.TimeUnit.SECONDS)
            assertNotNull(recorded)
            waitUntil { ReliabilityReportingReceipts.load(eventId, cacheRoot)?.state == ReliabilityReportingReceiptState.CONFIRMED }
            assertEquals(
                ReliabilityReportingReceiptState.CONFIRMED,
                ReliabilityReportingReceipts.load(eventId, cacheRoot)?.state,
            )
            transport.close()

            val blockedId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ReliabilityReportingReceipts.store(
                ReliabilityReportingReceipt(
                    incidentID = blockedId,
                    eventID = blockedId,
                    state = ReliabilityReportingReceiptState.QUEUED,
                    updatedAt = System.currentTimeMillis(),
                ),
                cacheRoot,
            )
            server.dispatcher =
                object : okhttp3.mockwebserver.Dispatcher() {
                    override fun dispatch(request: okhttp3.mockwebserver.RecordedRequest): okhttp3.mockwebserver.MockResponse {
                        Thread.sleep(1_500)
                        return okhttp3.mockwebserver.MockResponse().setResponseCode(200).setBody("{}")
                    }
                }
            val slow = ReliabilityReportingTransport(options, details)
            slow.send(envelopeWithId(options, blockedId), io.sentry.Hint())
            Thread.sleep(80)
            ReliabilityReporting.setCameraSessionActive(true)
            Thread.sleep(400)
            assertEquals(
                ReliabilityReportingReceiptState.QUEUED,
                ReliabilityReportingReceipts.load(blockedId, cacheRoot)?.state,
            )
            slow.close()
        } finally {
            server.shutdown()
            ReliabilityReportingHostPolicy.requireHttps = true
        }
    }

    private fun envelopeWithId(options: io.sentry.SentryOptions, hex: String): io.sentry.SentryEnvelope {
        val event = SentryEvent()
        event.eventId = io.sentry.protocol.SentryId(hex)
        return io.sentry.SentryEnvelope.from(options.serializer, event, null)
    }

    @Test
    fun backoffGrowsWithJitterBound() {
        val first = ReliabilityReportingBackoff.delaySeconds(0, 0.0)
        val later = ReliabilityReportingBackoff.delaySeconds(5, 1.0)
        assertTrue(later > first)
        assertTrue(later <= 30.0)
    }

    @Test
    fun immediateConfirmationIsNotOverwrittenByQueuedReceipt() {
        ReliabilityReportingConsent.setOptedIn(true)
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
        val id = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        ReliabilityReporting.setCaptureHandlerForTests { event, _ ->
            ReliabilityReporting.noteTransportSuccess(event.eventId.toString())
        }
        ReliabilityReporting.enqueueFinalized(stallBundle(id))
        waitForReceipt(id, ReliabilityReportingReceiptState.CONFIRMED)
    }

    private fun waitForReceipt(id: String, state: ReliabilityReportingReceiptState) {
        waitUntil { ReliabilityReporting.receipt(id)?.state == state }
        assertEquals(state, ReliabilityReporting.receipt(id)?.state)
    }

    private fun waitUntil(timeoutMs: Long = 2_000, predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (predicate()) return
            Thread.sleep(20)
        }
    }

    private fun stallBundle(
        id: String,
        outcome: FeedIncidentOutcome = FeedIncidentOutcome.RECOVERED,
    ): FeedIncidentBundle {
        val recorder = FeedIncidentRecorder { id }
        recorder.beginSession(
            FeedIncidentSessionContext(
                sessionId = "session-1",
                appVersion = "0.1.0",
                appBuild = "2",
                sourceRevision = "test",
                osName = "Android",
                osVersion = "16",
                hardwareClass = "Pixel",
                cameraFamily = "pocket",
            ),
        )
        recorder.recordSnapshot(healthy(1.0))
        recorder.recordSnapshot(staleOutput(3.0))
        val recovered = recorder.recordSnapshot(healthy(4.0))
        val bundle = recovered?.bundle ?: error("expected recovered bundle")
        bundle.header.outcome = outcome
        return bundle
    }

    private fun healthy(monotonic: Double) =
        FeedIncidentSnapshot(
            monotonicNow = monotonic,
            wallClockMs = 1_000L + (monotonic * 1000).toLong(),
            rates =
                FeedIncidentRates(
                    packetHz = 25.0,
                    accessUnitHz = 25.0,
                    decodedOutputHz = 25.0,
                    presentHz = 25.0,
                ),
            ages =
                FeedIncidentAges(
                    packetAge = 0.04,
                    accessUnitAge = 0.04,
                    decodedOutputAge = 0.04,
                    presentAge = 0.04,
                ),
            lifecycle = FeedIncidentLifecycle(connected = true, liveEstablished = true),
        )

    private fun staleOutput(monotonic: Double) =
        healthy(monotonic).copy(
            rates =
                FeedIncidentRates(
                    packetHz = 25.0,
                    accessUnitHz = 25.0,
                    decodeSubmitHz = 25.0,
                    decodedOutputHz = 0.0,
                ),
            ages =
                FeedIncidentAges(
                    packetAge = 0.04,
                    accessUnitAge = 0.04,
                    decodedOutputAge = 5.0,
                    presentAge = 5.0,
                ),
        )

    private class FakeTask : ReliabilityReportingCancellable {
        var cancelled = false
        override fun cancel() {
            cancelled = true
        }
    }
}
