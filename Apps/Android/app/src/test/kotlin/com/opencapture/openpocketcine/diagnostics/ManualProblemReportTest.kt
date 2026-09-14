package com.opencapture.openpocketcine.diagnostics

import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject

class ManualProblemReportTest {
    private lateinit var root: File
    private lateinit var server: MockWebServer

    @BeforeTest
    fun setUp() {
        root = File(System.getProperty("java.io.tmpdir"), "opc-manual-${System.nanoTime()}")
        root.mkdirs()
        server = MockWebServer()
        server.start()
        ReliabilityReportingConsent.resetForTests()
        ReliabilityReportingDSN.buildDsn = null
        ReliabilityReportingDSN.environment = emptyMap()
        ReliabilityReportingGate.resetForTests()
        ReliabilityReportingHostPolicy.requireHttps = false
        ManualProblemReport.resetForTests()
        ManualProblemReport.filesRoot = root
        ManualProblemReport.executeInlineForTests = true
        ManualProblemReport.appInForeground = true
        ManualProblemReport.envelopeUrlOverride = server.url("/api/1/envelope/").toString()
        ManualProblemReport.sentryKeyOverride = "publickey"
        ReliabilityReportingGate.setCameraIPv4PathReadyForTests(false)
        ReliabilityReportingGate.setCameraSessionActive(false)
        ReliabilityReportingGate.setValidInternetForTests(true)
    }

    @AfterTest
    fun tearDown() {
        server.shutdown()
        ManualProblemReport.resetForTests()
        ReliabilityReportingConsent.resetForTests()
        ReliabilityReportingGate.resetForTests()
        ReliabilityReportingHostPolicy.requireHttps = true
        root.deleteRecursively()
    }

    @Test
    fun retryAfterPreservesLongDelayAndHttpDate() {
        assertEquals(7_200_000L, parseRetryAfter("7200", 0))
        assertEquals(86_400_000L, parseRetryAfter("Fri, 02 Jan 1970 00:00:00 GMT", 0))
    }

    @Test
    fun storageFailureDoesNotCrashOrClaimQueued() {
        root.deleteRecursively()
        root.writeText("not a directory")
        assertEquals(ManualSubmitResult.STORAGE_ERROR, ManualProblemReport.submit("A report", "", null))
        assertEquals(0, server.requestCount)
        assertEquals(ManualProblemReportDelivery.IDLE, ManualProblemReport.current().delivery)
    }

    @Test
    fun envelopeKeepsUserMessageAndEmailButRedactsAttachment() {
        val userEmail = "operator.reply@example.com"
        val composed =
            ManualProblemReportEnvelope.compose(
                eventId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                timestampMs = 1_700_000_000_000L,
                release = "com.opencapture.openpocketcine@1.0+1",
                message = "Live view froze. Contact $userEmail",
                contactEmail = userEmail,
                diagnostics =
                    "crash /data/user/0/example/cache/report.txt email=secret.tester@example.com password=hunter2",
            )
        assertEquals("feedback", composed.items[0].header.getString("type"))
        val feedback = JSONObject(String(composed.items[0].payload, Charsets.UTF_8))
        assertEquals("feedback", feedback.getString("type"))
        assertEquals("java", feedback.getString("platform"))
        assertEquals("com.opencapture.openpocketcine@1.0+1", feedback.getString("release"))
        val ctx = feedback.getJSONObject("contexts").getJSONObject("feedback")
        assertEquals("Live view froze. Contact $userEmail", ctx.getString("message"))
        assertEquals(userEmail, ctx.getString("contact_email"))
        assertEquals("custom", ctx.getString("source"))
        assertFalse(feedback.has("user"))
        assertEquals(if (com.opencapture.openpocketcine.BuildConfig.DEBUG) "development" else "production", feedback.getString("environment"))
        assertEquals(com.opencapture.openpocketcine.BuildConfig.VERSION_CODE.toString(), feedback.getString("dist"))
        assertEquals(
            com.opencapture.openpocketcine.BuildConfig.SOURCE_REVISION.take(64),
            feedback.getJSONObject("tags").getString("sourceRevision"),
        )
        val attachment = composed.items[1]
        assertEquals("attachment", attachment.header.getString("type"))
        assertEquals("diagnostics.txt", attachment.header.getString("filename"))
        assertEquals("text/plain", attachment.header.getString("content_type"))
        val body = String(attachment.payload, Charsets.UTF_8)
        assertFalse(body.contains("secret.tester@example.com"))
        assertTrue(body.contains("<email>"))
        assertFalse(body.contains("hunter2"))
        assertTrue(body.contains("password=<redacted>"))
        assertTrue(body.contains(userEmail).not())
        val bytes = ManualProblemReportEnvelope.serialize(composed)
        val parsed = ManualProblemReportEnvelope.parse(bytes)
        assertEquals("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", parsed.header.getString("event_id"))
        assertEquals(2, parsed.items.size)
    }

    @Test
    fun limitsTruncateMessageEmailAndAttachment() {
        val message = "x".repeat(ManualProblemReport.MESSAGE_MAX + 50)
        val huge = "email=keep-this-out@example.com\n" + "n".repeat(ManualProblemReport.ATTACHMENT_MAX_CHARS + 8_000)
        val composed =
            ManualProblemReportEnvelope.compose(
                eventId = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                timestampMs = 1L,
                release = "com.opencapture.openpocketcine@1.0+1",
                message = ManualProblemReportEnvelope.sanitizeMessage(message),
                contactEmail = "operator.reply@example.com",
                diagnostics = huge,
            )
        val feedback = JSONObject(String(composed.items[0].payload, Charsets.UTF_8))
        val ctx = feedback.getJSONObject("contexts").getJSONObject("feedback")
        assertEquals(ManualProblemReport.MESSAGE_MAX, ctx.getString("message").length)
        assertTrue(composed.items[1].payload.size <= ManualProblemReport.ATTACHMENT_MAX_BYTES)
        val attachmentText = String(composed.items[1].payload, Charsets.UTF_8)
        assertTrue(attachmentText.length <= ManualProblemReport.ATTACHMENT_MAX_CHARS)
        assertNull(ManualProblemReportEnvelope.sanitizeEmail("  "))
        assertNull(ManualProblemReportEnvelope.sanitizeEmail("not-an-email"))
        assertNull(ManualProblemReportEnvelope.sanitizeEmail("a".repeat(ManualProblemReport.EMAIL_MAX + 1)))
        assertEquals("", ManualProblemReportEnvelope.sanitizeMessage("   "))
        val snowflake = "é".repeat(80)
        val clipped = ManualProblemReportEnvelope.utf8Prefix(snowflake, 10)
        assertTrue(clipped.toByteArray(Charsets.UTF_8).size <= 10)
    }

    @Test
    fun dsnEndpointIsHttpsEnvelopeOnDsnHost() {
        ReliabilityReportingHostPolicy.requireHttps = true
        val endpoint =
            ManualReportEndpoint.fromDsn("https://publickey@o0.ingest.sentry.io/123")
        assertNotNull(endpoint)
        assertEquals("https://o0.ingest.sentry.io/api/123/envelope/", endpoint.url)
        assertEquals("o0.ingest.sentry.io", endpoint.host)
        assertEquals("publickey", endpoint.sentryKey)
        assertNull(ManualReportEndpoint.fromDsn("http://publickey@o0.ingest.sentry.io/123"))
    }

    @Test
    fun submitDoesNotEnableAutomaticConsentOrStartWithoutExplicitSend() {
        assertFalse(ReliabilityReportingConsent.isOptedIn)
        assertEquals(0, root.listFiles()?.size ?: 0)
        val composed =
            ManualProblemReportEnvelope.compose(
                eventId = "cccccccccccccccccccccccccccccccc",
                timestampMs = 1L,
                release = "rel",
                message = "opened the form",
                contactEmail = null,
                diagnostics = null,
            )
        assertEquals(1, composed.items.size)
        assertEquals(0, root.listFiles()?.size ?: 0)
        assertFalse(ReliabilityReportingConsent.isOptedIn)
        server.enqueue(MockResponse().setResponseCode(200))
        val result =
            ManualProblemReport.submit(
                message = "Feed froze after LUT",
                replyEmail = "operator.reply@example.com",
                diagnostics = null,
            )
        assertEquals(ManualSubmitResult.QUEUED, result)
        assertFalse(ReliabilityReportingConsent.isOptedIn)
        assertEquals(ManualProblemReportDelivery.SENT, ManualProblemReport.current().delivery)
        val recorded = server.takeRequest(1, TimeUnit.SECONDS)
        assertNotNull(recorded)
        assertEquals("/api/1/envelope/", recorded.path)
        assertTrue(recorded.getHeader("X-Sentry-Auth")!!.contains("sentry_key=publickey"))
        assertEquals("application/x-sentry-envelope", recorded.getHeader("Content-Type"))
        val parsed = ManualProblemReportEnvelope.parse(recorded.body.readByteArray())
        val feedback = JSONObject(String(parsed.items[0].payload, Charsets.UTF_8))
        val ctx = feedback.getJSONObject("contexts").getJSONObject("feedback")
        assertEquals("Feed froze after LUT", ctx.getString("message"))
        assertEquals("operator.reply@example.com", ctx.getString("contact_email"))
        assertEquals("custom", ctx.getString("source"))
        assertEquals(1, parsed.items.size)
        assertEquals(ManualSubmitResult.INVALID, ManualProblemReport.submit("still broken", "not-an-email", null))
    }

    @Test
    fun missingDsnIsUnavailableAndDoesNotFakeSuccess() {
        ManualProblemReport.envelopeUrlOverride = null
        ManualProblemReport.sentryKeyOverride = null
        ReliabilityReportingDSN.buildDsn = null
        val result = ManualProblemReport.submit("something broke", "", null)
        assertEquals(ManualSubmitResult.UNAVAILABLE, result)
        assertEquals(ManualProblemReportDelivery.IDLE, ManualProblemReport.current().delivery)
        assertTrue(root.listFiles().isNullOrEmpty() || root.listFiles()!!.none { it.length() > 0 && it.extension == "envelope" })
        assertEquals(0, server.requestCount)
    }

    @Test
    fun cameraPathQueuesThenSendsOnceAndRejectsDuplicateSubmit() {
        server.enqueue(MockResponse().setResponseCode(200))
        ReliabilityReportingGate.setCameraSessionActive(true)
        val first =
            ManualProblemReport.submit("Queued on camera Wi-Fi", "", "phase=live email=hidden@example.com")
        assertEquals(ManualSubmitResult.QUEUED, first)
        assertEquals(ManualProblemReportDelivery.WAITING, ManualProblemReport.current().delivery)
        assertNull(server.takeRequest(100, TimeUnit.MILLISECONDS))
        val queuedId = ManualProblemReport.current().eventId
        val duplicate = ManualProblemReport.submit("second", "", null)
        assertEquals(ManualSubmitResult.PENDING_EXISTS, duplicate)
        assertEquals(queuedId, ManualProblemReport.current().eventId)
        ReliabilityReportingGate.setCameraSessionActive(false)
        ManualProblemReport.noteCameraPathClear()
        assertEquals(ManualProblemReportDelivery.SENT, ManualProblemReport.current().delivery)
        assertNotNull(server.takeRequest(1, TimeUnit.SECONDS))
        assertEquals(1, server.requestCount)
        val id = ManualProblemReport.current().eventId
        assertNotNull(id)
        assertEquals(32, id!!.length)
    }

    @Test
    fun retryAfterAndNonretryableFourHundred() {
        server.enqueue(MockResponse().setResponseCode(429).setHeader("Retry-After", "60"))
        ManualProblemReport.submit("rate limited", "", null)
        assertEquals(ManualProblemReportDelivery.WAITING, ManualProblemReport.current().delivery)
        assertNotNull(server.takeRequest(1, TimeUnit.SECONDS))
        ManualProblemReport.flush()
        assertEquals(1, server.requestCount)
        ManualProblemReport.discard()
        server.enqueue(MockResponse().setResponseCode(400))
        ManualProblemReport.submit("bad request", "", null)
        assertEquals(ManualProblemReportDelivery.FAILED, ManualProblemReport.current().delivery)
        assertTrue(ManualProblemReport.current().allowsDiscard)
        val failedId = ManualProblemReport.current().eventId
        assertNotNull(failedId)
        ManualProblemReport.discard()
        assertEquals(ManualProblemReportDelivery.IDLE, ManualProblemReport.current().delivery)
        assertNull(ManualProblemReport.current().eventId)
    }

    @Test
    fun expiredWaitingReportDropsEnvelopeKeepsMetadata() {
        server.enqueue(MockResponse().setResponseCode(200))
        var now = 1_000L
        ManualProblemReport.nowMs = { now }
        ReliabilityReportingGate.setValidInternetForTests(false)
        ManualProblemReport.submit("offline then expired", "operator.reply@example.com", "secret.tester@example.com")
        assertEquals(ManualProblemReportDelivery.WAITING, ManualProblemReport.current().delivery)
        assertTrue(File(root, "pending.envelope").isFile)
        now += ManualProblemReport.TTL_MS + 1
        ReliabilityReportingGate.setValidInternetForTests(true)
        ManualProblemReport.flush()
        assertEquals(ManualProblemReportDelivery.FAILED, ManualProblemReport.current().delivery)
        assertTrue(ManualProblemReport.current().detail!!.contains("expired"))
        assertTrue(ManualProblemReport.current().expiredMetadataOnly)
        assertFalse(File(root, "pending.envelope").exists())
        assertTrue(File(root, "pending.json").isFile)
        val meta = File(root, "pending.json").readText()
        assertFalse(meta.contains("operator.reply@example.com"))
        assertEquals(0, server.requestCount)
    }

    @Test
    fun discardInvalidatesInFlightResponseAndPreservesNewReport() {
        ReliabilityReportingGate.setValidInternetForTests(false)
        ManualProblemReport.submit("first report", "", null)
        val firstId = ManualProblemReport.current().eventId!!
        val firstGen = ManualProblemReport.currentGeneration()
        ManualProblemReport.discard()
        ManualProblemReport.submit("second report", "", null)
        val secondId = ManualProblemReport.current().eventId!!
        val secondGen = ManualProblemReport.currentGeneration()
        assertTrue(secondGen > firstGen)
        assertTrue(secondId != firstId)
        ManualProblemReport.finishForTests(firstId, firstGen, 200)
        assertEquals(secondId, ManualProblemReport.current().eventId)
        assertEquals(ManualProblemReportDelivery.WAITING, ManualProblemReport.current().delivery)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun cameraClearPreservesRetryAfterBackoff() {
        server.enqueue(MockResponse().setResponseCode(429).setHeader("Retry-After", "120"))
        ManualProblemReport.submit("rate limited then camera", "", null)
        assertEquals(ManualProblemReportDelivery.WAITING, ManualProblemReport.current().delivery)
        assertNotNull(server.takeRequest(1, TimeUnit.SECONDS))
        val after429 = File(root, "pending.json").readText()
        val nextAttempt = JSONObject(after429).getLong("nextAttemptAtMs")
        assertTrue(nextAttempt > ManualProblemReport.nowMs())
        ReliabilityReportingGate.setCameraSessionActive(true)
        ReliabilityReportingGate.setCameraSessionActive(false)
        ManualProblemReport.noteCameraPathClear()
        assertEquals(1, server.requestCount)
        val afterClear = JSONObject(File(root, "pending.json").readText())
        assertEquals(nextAttempt, afterClear.getLong("nextAttemptAtMs"))
    }

    @Test
    fun dsnChangeDoesNotSendOldEnvelopeToNewProject() {
        ReliabilityReportingGate.setValidInternetForTests(false)
        ManualProblemReport.submit("queued against original DSN", "", null)
        assertEquals(ManualProblemReportDelivery.WAITING, ManualProblemReport.current().delivery)
        ManualProblemReport.envelopeUrlOverride = null
        ReliabilityReportingDSN.buildDsn = "https://otherkey@o1.ingest.sentry.io/99"
        ReliabilityReportingGate.setValidInternetForTests(true)
        ManualProblemReport.flush()
        assertEquals(ManualProblemReportDelivery.FAILED, ManualProblemReport.current().delivery)
        assertTrue(ManualProblemReport.current().detail!!.contains("destination changed"))
        assertEquals(0, server.requestCount)
        assertFalse(File(root, "pending.envelope").exists())
    }

    @Test
    fun backgroundDoesNotTransmitUntilForeground() {
        server.enqueue(MockResponse().setResponseCode(200))
        ManualProblemReport.appInForeground = false
        ManualProblemReport.submit("typed while backgrounded", "", null)
        assertEquals(ManualProblemReportDelivery.WAITING, ManualProblemReport.current().delivery)
        assertNull(server.takeRequest(100, TimeUnit.MILLISECONDS))
        ManualProblemReport.setForeground(true)
        assertEquals(ManualProblemReportDelivery.SENT, ManualProblemReport.current().delivery)
        assertNotNull(server.takeRequest(1, TimeUnit.SECONDS))
    }

    @Test
    fun imageAttachmentsUseGeneratedJpegNamesWithoutExifOrOriginalFilename() {
        val jpeg = jpegFixture(256)
        val composed =
            ManualProblemReportEnvelope.compose(
                eventId = "dddddddddddddddddddddddddddddddd",
                timestampMs = 1L,
                release = "com.opencapture.openpocketcine@1.0+1",
                message = "black live view",
                contactEmail = null,
                diagnostics = null,
                images = listOf(jpeg),
            )
        assertEquals(2, composed.items.size)
        val image = composed.items[1]
        assertEquals("attachment", image.header.getString("type"))
        assertEquals("image-1.jpg", image.header.getString("filename"))
        assertEquals("image/jpeg", image.header.getString("content_type"))
        assertTrue(image.payload.contentEquals(jpeg))
        assertFalse(image.header.toString().contains("DSC_"))
        assertFalse(ManualReportImages.containsExif(image.payload))
        assertNull(ManualReportImages.accept(listOf(jpegFixture(64, exif = true))))
        assertNull(ManualReportImages.accept(listOf("not-an-image".toByteArray())))
        assertNull(ManualReportImages.accept(List(4) { jpegFixture(64) }))
        assertNull(ManualReportImages.accept(listOf(jpegFixture(ManualReportImages.MAX_EACH_BYTES + 1))))
        val almost = jpegFixture(ManualReportImages.MAX_EACH_BYTES)
        assertEquals(3, ManualReportImages.accept(listOf(almost, almost, almost))!!.size)
    }

    @Test
    fun queuedEnvelopeRoundtripsImageBytesAndRejectsInvalidCountWithoutWriting() {
        ReliabilityReportingGate.setValidInternetForTests(false)
        val jpeg = jpegFixture(512)
        val result =
            ManualProblemReport.submit(
                message = "with photo",
                replyEmail = "",
                diagnostics = "phase=live",
                images = listOf(jpeg, jpegFixture(128)),
            )
        assertEquals(ManualSubmitResult.QUEUED, result)
        assertEquals(ManualProblemReportDelivery.WAITING, ManualProblemReport.current().delivery)
        val envelopeBytes = File(root, "pending.envelope").readBytes()
        val parsed = ManualProblemReportEnvelope.parse(envelopeBytes)
        assertEquals(4, parsed.items.size)
        assertEquals("diagnostics.txt", parsed.items[1].header.getString("filename"))
        assertEquals("image-1.jpg", parsed.items[2].header.getString("filename"))
        assertEquals("image/jpeg", parsed.items[2].header.getString("content_type"))
        assertEquals("image-2.jpg", parsed.items[3].header.getString("filename"))
        assertTrue(parsed.items[2].payload.contentEquals(jpeg))
        val restored = ManualProblemReportEnvelope.parse(File(root, "pending.envelope").readBytes())
        assertEquals(parsed.items.size, restored.items.size)
        assertTrue(restored.items[2].payload.contentEquals(jpeg))
        ManualProblemReport.discard()
        assertEquals(
            ManualSubmitResult.INVALID,
            ManualProblemReport.submit("too many", "", null, List(4) { jpegFixture(64) }),
        )
        assertEquals(ManualProblemReportDelivery.IDLE, ManualProblemReport.current().delivery)
        assertFalse(File(root, "pending.envelope").exists())
        assertFalse(ReliabilityReportingConsent.isOptedIn)
    }

    private fun jpegFixture(size: Int, exif: Boolean = false): ByteArray {
        val bytes = ByteArray(size.coerceAtLeast(24))
        bytes[0] = 0xFF.toByte()
        bytes[1] = 0xD8.toByte()
        bytes[2] = 0xFF.toByte()
        if (exif) {
            bytes[3] = 0xE1.toByte()
            bytes[4] = 0x00
            bytes[5] = 0x10
            byteArrayOf(0x45, 0x78, 0x69, 0x66, 0x00, 0x00).copyInto(bytes, 6)
        } else {
            bytes[3] = 0xE0.toByte()
            bytes[4] = 0x00
            bytes[5] = 0x10
            byteArrayOf(0x4A, 0x46, 0x49, 0x46, 0x00).copyInto(bytes, 6)
        }
        bytes[bytes.lastIndex - 1] = 0xFF.toByte()
        bytes[bytes.lastIndex] = 0xD9.toByte()
        return bytes
    }
}
