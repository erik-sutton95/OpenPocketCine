package com.opencapture.openpocketcine.media

import com.opencapture.opencine.dji.DJIMediaHTTPError
import com.opencapture.opencine.media.MediaByteSink
import com.opencapture.opencine.media.MediaTransferReceipt
import com.opencapture.opencine.runtime.MonitorMediaReadSource
import com.opencapture.opencine.runtime.MonitorMediaReadStream
import com.opencapture.opencine.runtime.MonitorMediaStreamException
import com.opencapture.opencine.runtime.MonitorMediaStreamPump
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response

/** Actual HTTP socket construction. The native runtime owns bounded copying, cancellation and
 * completion at an observed length; the integration owns storage candidates and retry. */
object MediaTransfer {
    const val MAX_RAM_BYTES: Long = 8L * 1024 * 1024
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS).callTimeout(0, TimeUnit.SECONDS)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
    private val pump = MonitorMediaStreamPump()

    suspend fun stream(url: String, expected: Long?, sink: MediaByteSink): MediaTransferReceipt =
        transfer(HTTPSource(url), expected, sink, Long.MAX_VALUE)

    suspend fun bytes(url: String): ByteArray {
        val sink = MemorySink()
        transfer(HTTPSource(url), null, sink, MAX_RAM_BYTES)
        return sink.bytes()
    }

    /** A genuine Range response may end early with useful tail bytes. A server ignoring Range
     * cannot materialize the full original, and the native worker still owns each read/cancel. */
    suspend fun range(url: String, range: String, maximum: Int): ByteArray {
        if (maximum <= 0) throw DJIMediaHTTPError.BadResponse
        val sink = MemorySink()
        try { transfer(HTTPSource(url, range, maximum.toLong()), null, sink, maximum.toLong()) }
        catch (error: IOException) {
            if (error is DJIMediaHTTPError || sink.size == 0) throw error
        }
        return sink.bytes()
    }

    private suspend fun transfer(source: MonitorMediaReadSource, expected: Long?, sink: MediaByteSink,
        maximum: Long): MediaTransferReceipt {
        try { return pump.transfer(source, expected, sink, maximum) }
        catch (error: MonitorMediaStreamException.Status) { throw DJIMediaHTTPError.HttpStatus(error.status) }
        catch (_: MonitorMediaStreamException.Empty) { throw DJIMediaHTTPError.BadResponse }
        catch (_: MonitorMediaStreamException.Limit) { throw DJIMediaHTTPError.BadResponse }
    }
    private class MemorySink : MediaByteSink {
        private val output = ByteArrayOutputStream()
        val size: Int get() = output.size()
        override suspend fun write(chunk: ByteArray) { output.write(chunk) }
        fun bytes(): ByteArray = output.toByteArray()
    }
    private class HTTPSource(url: String, private val range: String? = null,
        private val maximum: Long? = null) : MonitorMediaReadSource {
        private val call = client.newCall(Request.Builder().url(url).header("Accept", "*/*")
            .apply { range?.let { header("Range", it) } }.get().build())
        override fun cancel() { call.cancel() }
        override fun open(): MonitorMediaReadStream {
            val response = call.execute()
            try {
                if (response.code !in 200..299) throw DJIMediaHTTPError.HttpStatus(response.code)
                val body = response.body ?: throw DJIMediaHTTPError.BadResponse
                val header = body.contentLength().takeIf { it > 0 }
                if (range != null && response.code == 200 && header != null && header > checkNotNull(maximum)) {
                    throw DJIMediaHTTPError.BadResponse
                }
                // The requested tail, not the original movie length, bounds a Range read.
                val length = if (range == null) header else header?.coerceAtMost(checkNotNull(maximum)) ?: maximum
                return HTTPStream(response, length, body.byteStream())
            } catch (error: Throwable) { response.close(); throw error }
        }
    }
    private class HTTPStream(private val response: Response,
        override val contentLength: Long?, override val input: InputStream) : MonitorMediaReadStream {
        override val status: Int get() = response.code
        override fun close() { response.close() }
    }
}
