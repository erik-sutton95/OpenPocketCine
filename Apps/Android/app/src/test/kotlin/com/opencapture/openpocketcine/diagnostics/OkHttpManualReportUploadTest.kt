package com.opencapture.openpocketcine.diagnostics

import com.opencapture.opencine.appkit.diagnostics.ManualProblemReportDelivery
import com.opencapture.opencine.appkit.diagnostics.ManualProblemReportEnvelope
import com.opencapture.opencine.appkit.diagnostics.ManualSubmitResult
import com.opencapture.openpocketcine.BuildConfig
import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject

/** The holder's manual report over the OkHttp adapter, against a real HTTP server. */
class OkHttpManualReportUploadTest {
    private val report = AppDiagnostics.manualReport
    private val gate = AppDiagnostics.gate
    private lateinit var root: File
    private lateinit var server: MockWebServer

    @BeforeTest
    fun setUp() {
        root = File(System.getProperty("java.io.tmpdir"), "opc-manual-${System.nanoTime()}")
        root.mkdirs()
        server = MockWebServer()
        server.start()
        AppDiagnostics.consent.resetForTests()
        AppDiagnostics.dsn.buildDsn = null
        AppDiagnostics.dsn.environment = emptyMap()
        gate.resetForTests()
        gate.hostPolicy.requireHttps = false
        report.resetForTests()
        report.filesRoot = root
        report.executeInlineForTests = true
        report.appInForeground = true
        report.envelopeUrlOverride = server.url("/api/1/envelope/").toString()
        report.sentryKeyOverride = "publickey"
        gate.setCameraIPv4PathReadyForTests(false)
        gate.setCameraSessionActive(false)
        gate.setValidInternetForTests(true)
    }

    @AfterTest
    fun tearDown() {
        server.shutdown()
        report.resetForTests()
        AppDiagnostics.consent.resetForTests()
        gate.resetForTests()
        gate.hostPolicy.requireHttps = true
        root.deleteRecursively()
    }

    @Test
    fun postsTheEnvelopeAsThisAppAndReadsRetryAfterAndRefusals() {
        server.enqueue(MockResponse().setResponseCode(200))
        assertEquals(ManualSubmitResult.QUEUED, report.submit("Feed froze after LUT", "operator.reply@example.com", null))
        assertEquals(ManualProblemReportDelivery.SENT, report.current().delivery)
        assertEquals("Report sent. Thank you for helping improve OpenPocketCine.", report.current().detail)
        val recorded = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(recorded)
        assertEquals("POST", recorded.method)
        assertEquals("/api/1/envelope/", recorded.path)
        assertEquals("application/x-sentry-envelope", recorded.getHeader("Content-Type"))
        assertEquals("application/json", recorded.getHeader("Accept"))
        assertEquals(
            "Sentry sentry_version=7, sentry_client=openpocketcine-android/${BuildConfig.VERSION_NAME}, sentry_key=publickey",
            recorded.getHeader("X-Sentry-Auth"),
        )
        val parsed = ManualProblemReportEnvelope.parse(recorded.body.readByteArray())
        val feedback = JSONObject(String(parsed.items[0].payload, Charsets.UTF_8))
        assertEquals(
            "com.opencapture.openpocketcine@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}",
            feedback.getString("release"),
        )
        assertEquals(if (BuildConfig.DEBUG) "development" else "production", feedback.getString("environment"))
        assertEquals(BuildConfig.VERSION_CODE.toString(), feedback.getString("dist"))
        assertEquals(BuildConfig.SOURCE_REVISION.take(64), feedback.getJSONObject("tags").getString("sourceRevision"))

        report.discard()
        server.enqueue(MockResponse().setResponseCode(429).setHeader("Retry-After", "60"))
        report.submit("rate limited", "", null)
        assertEquals(ManualProblemReportDelivery.WAITING, report.current().delivery)
        assertNotNull(server.takeRequest(1, TimeUnit.SECONDS))
        val meta = JSONObject(File(root, "pending.json").readText())
        assertTrue(meta.getLong("nextAttemptAtMs") >= System.currentTimeMillis() + 50_000)

        report.discard()
        server.enqueue(MockResponse().setResponseCode(400))
        report.submit("bad request", "", null)
        assertEquals(ManualProblemReportDelivery.FAILED, report.current().delivery)
        assertEquals(
            "Report couldn't be sent. Remove it and try again, or contact support@openpocketcine.app.",
            report.current().detail,
        )
    }
}
