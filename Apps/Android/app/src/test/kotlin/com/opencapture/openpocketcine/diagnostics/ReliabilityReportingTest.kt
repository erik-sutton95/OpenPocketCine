package com.opencapture.openpocketcine.diagnostics

import com.opencapture.opencine.appkit.diagnostics.ReliabilityEvent
import com.opencapture.opencine.appkit.diagnostics.ReliabilityEventLevel
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingReceipts
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingReceipt
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingReceiptState
import com.opencapture.opencine.media.FeedIncidentTestSource
import io.sentry.Breadcrumb
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.protocol.Request
import io.sentry.protocol.SentryException
import io.sentry.protocol.User
import java.io.File
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReliabilityReportingTest {
    private val consent = AppDiagnostics.consent
    private val dsn = AppDiagnostics.dsn
    private val gate = AppDiagnostics.gate
    private val origin = AppDiagnostics.origin
    private val reporting = AppDiagnostics.reporting
    private lateinit var cacheRoot: File

    companion object {
        private const val CONFIGURED_DSN = "https://publickey@o0.ingest.sentry.io/0"
    }

    @BeforeTest
    fun setUp() {
        cacheRoot = File(System.getProperty("java.io.tmpdir"), "opc-rel-${System.nanoTime()}")
        cacheRoot.mkdirs()
        reporting.sdkCacheRoot = cacheRoot
        consent.resetForTests()
        dsn.buildDsn = null
        dsn.environment = emptyMap()
        reporting.setCaptureHandlerForTests(null)
        gate.resetForTests()
        reporting.dsnHost = "o0.ingest.sentry.io"
    }

    @AfterTest
    fun tearDown() {
        reporting.setCaptureHandlerForTests(null)
        consent.resetForTests()
        gate.resetForTests()
        origin.resetForTests()
        cacheRoot.deleteRecursively()
    }

    @Test
    fun unknownBreadcrumbTokensAreRejected() {
        val event = SentryEvent()
        val scene = Breadcrumb()
        scene.category = "feed"
        scene.message = "sceneActivity"
        scene.setData("sceneState", "Erik")
        scene.setData("assistState", "private_project")
        event.breadcrumbs = mutableListOf(scene)
        reporting.privacy.scrub(event)
        assertEquals(1, event.breadcrumbs?.size)
        assertNull(event.breadcrumbs?.first()?.data?.get("sceneState"))
        assertNull(event.breadcrumbs?.first()?.data?.get("assistState"))
    }

    @Test
    fun scrubDoesNotStampCurrentOriginOntoLegacyEvents() {
        origin.overrideTestSourceForTests = FeedIncidentTestSource.VERIFICATION
        val event = SentryEvent()
        event.level = SentryLevel.FATAL
        event.setTag("failingStage", "decodedOutput")
        reporting.privacy.scrub(event)
        assertNull(event.tags?.get("testSource"))
        event.setTag("testSource", "manual")
        event.setTag("buildIdentity", "android-priorrun0123456789abcdef")
        reporting.privacy.scrub(event)
        assertEquals("manual", event.tags?.get("testSource"))
        assertEquals("android-priorrun0123456789abcdef", event.tags?.get("buildIdentity"))
    }

    @Test
    fun onlyTypedFeedBreadcrumbsSurviveScrubbing() {
        val event = SentryEvent()
        val typed = Breadcrumb()
        typed.category = "feed"
        typed.message = "settingsEnter"
        typed.setData("password", "must-not-leave-phone")
        val scene = Breadcrumb()
        scene.category = "feed"
        scene.message = "sceneActivity"
        scene.setData("sceneState", "inactive")
        scene.setData("password", "must-not-leave-phone")
        val repair = Breadcrumb()
        repair.category = "feed"
        repair.message = "repair"
        repair.setData("repairAction", "decoder")
        repair.setData("repairPhase", "requested")
        val arbitrary = Breadcrumb()
        arbitrary.category = "feed"
        arbitrary.message = "arbitrary operator text"
        event.breadcrumbs = mutableListOf(typed, scene, repair, arbitrary, Breadcrumb())
        reporting.privacy.scrub(event)
        assertEquals(3, event.breadcrumbs?.size)
        assertEquals("settingsEnter", event.breadcrumbs?.get(0)?.message)
        assertTrue(event.breadcrumbs?.get(0)?.data.isNullOrEmpty())
        assertEquals("sceneActivity", event.breadcrumbs?.get(1)?.message)
        assertEquals("inactive", event.breadcrumbs?.get(1)?.data?.get("sceneState"))
        assertNull(event.breadcrumbs?.get(1)?.data?.get("password"))
        assertEquals("repair", event.breadcrumbs?.get(2)?.message)
        assertEquals("decoder", event.breadcrumbs?.get(2)?.data?.get("repairAction"))
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
        event.setTag("testSource", "automation")
        event.setTag("buildIdentity", "android-0123456789abcdef0123456789ab")
        event.setExtra("password", "hunter2")
        event.setExtra("failingStage", "decodedOutput")
        event.contexts["device"] = mapOf("name" to "Example Phone", "model" to "Pixel 9")
        event.contexts["feed"] = mapOf("failingStage" to "decodedOutput", "serial" to "ABC")
        val exception = SentryException()
        exception.value = "/" + "Users/example/Library/crash"
        exception.type = "RuntimeException"
        event.exceptions = mutableListOf(exception)
        reporting.privacy.scrub(event)
        assertNull(event.user)
        assertNull(event.request)
        assertTrue(event.breadcrumbs.isNullOrEmpty())
        assertNull(event.tags?.get("email"))
        assertEquals("decodedOutput", event.tags?.get("failingStage"))
        assertEquals("automation", event.tags?.get("testSource"))
        assertEquals("android-0123456789abcdef0123456789ab", event.tags?.get("buildIdentity"))
        assertNull(event.extras?.get("password"))
        assertEquals("decodedOutput", event.extras?.get("failingStage"))
        val device = event.contexts["device"] as? Map<*, *>
        assertNull(device?.get("name"))
        assertEquals("Pixel 9", device?.get("model"))
        val feed = event.contexts["feed"] as? Map<*, *>
        assertNull(feed?.get("serial"))
        assertFalse(event.exceptions?.first()?.value?.contains("example/Library") == true)
        event.setTag("sourceRevision", "a".repeat(40))
        reporting.privacy.scrub(event)
        assertEquals("a".repeat(40), event.tags?.get("sourceRevision"))
    }

    @Test
    fun optionsDisableScreenshotsReplayProfilingAndPii() {
        val options =
            makeOptions("https://publickey@o0.ingest.sentry.io/0", reporting)
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
        assertEquals(com.opencapture.openpocketcine.BuildConfig.VERSION_CODE.toString(), options.dist)
        assertEquals("development", options.environment)
    }

    @Test
    fun httpSuccessConfirmsQueuedReceiptAndCameraCancelKeepsItQueued() {
        val server = okhttp3.mockwebserver.MockWebServer()
        server.start()
        try {
            consent.setOptedIn(true)
            gate.hostPolicy.requireHttps = false
            reporting.dsnHost = server.hostName
            gate.setCameraSessionActive(false)
            gate.setCameraIPv4PathReadyForTests(false)
            gate.setValidInternetForTests(true)
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
            val transport = ReliabilityReportingTransport(reporting, options, details)
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
            val slow = ReliabilityReportingTransport(reporting, options, details)
            slow.send(envelopeWithId(options, blockedId), io.sentry.Hint())
            Thread.sleep(80)
            reporting.setCameraSessionActive(true)
            Thread.sleep(400)
            assertEquals(
                ReliabilityReportingReceiptState.QUEUED,
                ReliabilityReportingReceipts.load(blockedId, cacheRoot)?.state,
            )
            slow.close()
        } finally {
            server.shutdown()
            gate.hostPolicy.requireHttps = true
        }
    }

    private fun envelopeWithId(options: io.sentry.SentryOptions, hex: String): io.sentry.SentryEnvelope {
        val event = SentryEvent()
        event.eventId = io.sentry.protocol.SentryId(hex)
        return io.sentry.SentryEnvelope.from(options.serializer, event, null)
    }

    // Returns as soon as the predicate holds; the ceiling only matters on a loaded CI runner.
    private fun waitUntil(timeoutMs: Long = 10_000, predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (predicate()) return
            Thread.sleep(20)
        }
    }

    @Test
    fun typedEventKeepsItsPayloadAsASentryEvent() {
        val event =
            ReliabilityEvent(
                eventId = "12c2d058d58442709aa2eca08bf20986",
                level = ReliabilityEventLevel.WARNING,
                timestampMs = 1_780_000_000_000L,
                release = AppDiagnostics.host.release("0.1.0", "107"),
                dist = "107",
                message = "feed incident decodedOutput",
                fingerprints = listOf("feed-incident", "schema:1", "kind:transportStall"),
                tags = mapOf("failingStage" to "decodedOutput", "testSource" to "faultInjection"),
                extras = mapOf("schemaVersion" to 1, "worstGapSeconds" to 2.5),
                contexts = mapOf("feed" to mapOf("kind" to "transportStall", "schemaVersion" to 1)),
            )
        val sentry = event.toSentryEvent()
        assertEquals(SentryLevel.WARNING, sentry.level)
        assertEquals("12c2d058d58442709aa2eca08bf20986", sentry.eventId.toString())
        assertEquals(java.util.Date(1_780_000_000_000L), sentry.timestamp)
        assertEquals("com.opencapture.openpocketcine@0.1.0+107", sentry.release)
        assertEquals("107", sentry.dist)
        assertEquals("feed incident decodedOutput", sentry.message?.formatted)
        assertEquals(event.fingerprints, sentry.fingerprints)
        assertEquals(event.tags, sentry.tags)
        assertEquals(event.extras, sentry.extras)
        assertEquals(event.contexts["feed"], sentry.contexts["feed"])
        assertNull(sentry.user)
        assertNull(sentry.request)
        assertTrue(sentry.breadcrumbs.isNullOrEmpty())
        // The SDK's beforeSend scrub keeps an event the shared rules already scrubbed.
        reporting.privacy.scrub(sentry)
        assertEquals("feed incident decodedOutput", sentry.message?.formatted)
        assertEquals(event.tags, sentry.tags)
        assertEquals(event.extras, sentry.extras)
        assertEquals(event.contexts["feed"], sentry.contexts["feed"])
    }
}
