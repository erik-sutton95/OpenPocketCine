package com.opencapture.openpocketcine.diagnostics

import io.sentry.Hint
import io.sentry.RequestDetails
import io.sentry.SentryEnvelope
import io.sentry.SentryEvent
import io.sentry.SentryOptions
import io.sentry.cache.IEnvelopeCache
import io.sentry.protocol.SentryId
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

/** SIMULATED malformed SDK cache; exercises the real transport drain and HTTP receipt. */
class ReliabilityTransportCacheFailureTest {
    private class RefusingCache : IEnvelopeCache {
        val entries = ConcurrentHashMap<String, SentryEnvelope>()
        val reads = AtomicInteger()

        override fun store(envelope: SentryEnvelope, hint: Hint) {
            entries[envelope.header.eventId.toString()] = envelope
        }

        override fun discard(envelope: SentryEnvelope) {
            entries.remove(envelope.header.eventId.toString())
        }

        override fun iterator(): MutableIterator<SentryEnvelope> {
            reads.incrementAndGet()
            throw IllegalArgumentException("SIMULATED malformed cached envelope")
        }
    }

    private class DeliveryHint : io.sentry.hints.DiskFlushNotification,
        io.sentry.hints.Retryable, io.sentry.hints.SubmissionResult {
        var flushed = false
        private var retry = false
        private var success = false
        override fun markFlushed() { flushed = true }
        override fun isFlushable(id: SentryId?) = true
        override fun setFlushable(id: SentryId) = Unit
        override fun isRetry() = retry
        override fun setRetry(value: Boolean) { retry = value }
        override fun isSuccess() = success
        override fun setResult(value: Boolean) { success = value }
    }

    @Test
    fun unreadableCacheRetainsDurableReportsAndAllowsPendingThenLaterDelivery() {
        val server = MockWebServer()
        server.start()
        val cache = RefusingCache()
        val options = SentryOptions().apply { setEnvelopeDiskCache(cache) }
        val details = RequestDetails(server.url("/envelope/").toString(), emptyMap())
        val previousHost = AppDiagnostics.reporting.dsnHost
        AppDiagnostics.consent.setOptedIn(true)
        AppDiagnostics.gate.resetForTests()
        AppDiagnostics.gate.hostPolicy.requireHttps = false
        AppDiagnostics.reporting.dsnHost = server.hostName
        val transport = ReliabilityReportingTransport(AppDiagnostics.reporting, options, details)
        fun envelope(id: String): SentryEnvelope {
            val event = SentryEvent().apply { eventId = SentryId(id) }
            return SentryEnvelope.from(options.serializer, event, null)
        }
        val retained = envelope("96969696969696969696969696969696")
        cache.store(retained, Hint())
        try {
            AppDiagnostics.gate.setCameraSessionActive(true)
            val first = envelope("95959595959595959595959595959595")
            val firstHint = DeliveryHint()
            transport.send(first, io.sentry.util.HintUtils.createWithTypeCheckHint(firstHint))
            assertTrue(firstHint.flushed)
            assertTrue(firstHint.isRetry)
            assertFalse(firstHint.isSuccess)
            assertEquals(2, cache.entries.size)
            assertNull(server.takeRequest(100, TimeUnit.MILLISECONDS))
            assertEquals(0, cache.reads.get())

            server.enqueue(MockResponse().setResponseCode(200))
            AppDiagnostics.gate.setCameraSessionActive(false)
            transport.flush(2000)
            assertNotNull(server.takeRequest(1, TimeUnit.SECONDS))
            assertTrue(cache.reads.get() > 0)
            assertTrue(firstHint.isSuccess)
            assertFalse(firstHint.isRetry)
            assertEquals(setOf(retained.header.eventId.toString()), cache.entries.keys)

            server.enqueue(MockResponse().setResponseCode(200))
            val secondHint = DeliveryHint()
            val second = envelope("94949494949494949494949494949494")
            transport.send(second, io.sentry.util.HintUtils.createWithTypeCheckHint(secondHint))
            transport.flush(2000)
            assertNotNull(server.takeRequest(1, TimeUnit.SECONDS))
            assertTrue(secondHint.isSuccess)
            assertFalse(secondHint.isRetry)
            assertEquals(2, server.requestCount)
            assertEquals(setOf(retained.header.eventId.toString()), cache.entries.keys)
        } finally {
            transport.close()
            server.shutdown()
            AppDiagnostics.consent.resetForTests()
            AppDiagnostics.gate.resetForTests()
            AppDiagnostics.reporting.dsnHost = previousHost
        }
    }
}
