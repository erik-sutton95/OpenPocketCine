package com.opencapture.openpocketcine.media

import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.math.min

sealed class MediaTransferError : Exception() {
    data object BadResponse : MediaTransferError()
    data class HttpStatus(val code: Int) : MediaTransferError()
    data object Timeout : MediaTransferError()
}

/**
 * SoftAP `/v2` GET. Finish at Content-Length — the camera often keeps the socket
 * open after the body, so waiting for EOF hangs at 100%.
 */
object MediaTransfer {
    private val client: OkHttpClient =
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .callTimeout(0, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .build()

    fun getBytes(storage: Int, path: String): ByteArray {
        val (data, _) = performGet(storage, path)
        return data
    }

    fun downloadFile(
        storage: Int,
        path: String,
        dest: File,
        expectedSize: Long = 0,
        onProgress: (Double) -> Unit = {},
    ) {
        var last: MediaTransferError = MediaTransferError.BadResponse
        for (candidate in storageOrder(storage)) {
            try {
                downloadOnce(
                    url = MediaHTTP.pathUrlString(candidate, path),
                    dest = dest,
                    expectedSize = expectedSize,
                    onProgress = onProgress,
                )
                return
            } catch (e: MediaTransferError.HttpStatus) {
                last = e
                if (e.code == 404 || e.code in 400..499) continue
                throw e
            } catch (e: MediaTransferError) {
                last = e
            }
        }
        throw last
    }

    fun fetchBytes(storage: Int, path: String): Pair<ByteArray, Int> = performGet(storage, path)

    private fun performGet(firstStorage: Int, path: String): Pair<ByteArray, Int> {
        var last: MediaTransferError = MediaTransferError.BadResponse
        for (storage in storageOrder(firstStorage)) {
            try {
                val data = getOnce(MediaHTTP.pathUrlString(storage, path))
                if (data.isEmpty()) {
                    last = MediaTransferError.BadResponse
                    continue
                }
                return data to storage
            } catch (e: MediaTransferError.HttpStatus) {
                last = e
                if (e.code == 404 || e.code in 400..499) continue
                throw e
            } catch (e: MediaTransferError) {
                last = e
            }
        }
        throw last
    }

    private fun getOnce(url: String): ByteArray {
        val request =
            Request.Builder()
                .url(url)
                .header("Accept", "*/*")
                .get()
                .build()
        val call = client.newCall(request)
        call.execute().use { response ->
            val code = response.code
            if (code !in 200..299) throw MediaTransferError.HttpStatus(code)
            val body = response.body ?: throw MediaTransferError.BadResponse
            val expected = body.contentLength().takeIf { it > 0 } ?: 0L
            val sink = java.io.ByteArrayOutputStream()
            val written =
                try {
                    readUntilLength(body.byteStream(), sink, expected) { }
                } catch (e: IOException) {
                    if (sink.size() > 0 && expected > 0 && sink.size().toLong() >= expected) {
                        sink.size().toLong()
                    } else {
                        throw e
                    }
                }
            if (written <= 0L) throw MediaTransferError.BadResponse
            if (expected > 0 && written >= expected) call.cancel()
            return sink.toByteArray()
        }
    }

    private fun downloadOnce(
        url: String,
        dest: File,
        expectedSize: Long,
        onProgress: (Double) -> Unit,
    ) {
        dest.parentFile?.mkdirs()
        val tmp = File(dest.parentFile, "${UUID.randomUUID()}.part")
        val request =
            Request.Builder()
                .url(url)
                .header("Accept", "*/*")
                .get()
                .build()
        val call = client.newCall(request)
        try {
            call.execute().use { response ->
                val code = response.code
                if (code !in 200..299) throw MediaTransferError.HttpStatus(code)
                val body = response.body ?: throw MediaTransferError.BadResponse
                val headerLength = body.contentLength()
                val expected = if (headerLength > 0) headerLength else expectedSize
                tmp.outputStream().use { out ->
                    val written =
                        try {
                            readUntilLength(body.byteStream(), out, expected, onProgress)
                        } catch (e: IOException) {
                            val already = tmp.length()
                            if (already > 0 && expected > 0 && already >= expected) {
                                already
                            } else {
                                throw e
                            }
                        }
                    if (written <= 0L) throw MediaTransferError.BadResponse
                    if (expected > 0 && written >= expected) call.cancel()
                }
            }
        } catch (e: IOException) {
            if (tmp.isFile && expectedSize > 0 && tmp.length() >= expectedSize) {
                // Content-Length complete; camera kept the socket open.
            } else {
                tmp.delete()
                throw e
            }
        }
        if (!tmp.isFile || tmp.length() <= 0L) {
            tmp.delete()
            throw MediaTransferError.BadResponse
        }
        if (dest.exists()) dest.delete()
        if (!tmp.renameTo(dest)) {
            tmp.copyTo(dest, overwrite = true)
            tmp.delete()
        }
    }

    /**
     * Copy [expected] bytes (or until EOF when [expected] is 0). Progress is
     * `written / expected` when the length is known.
     */
    fun readUntilLength(
        input: InputStream,
        output: OutputStream,
        expected: Long,
        onProgress: (Double) -> Unit,
    ): Long {
        val buf = ByteArray(64 * 1024)
        var written = 0L
        while (true) {
            val remaining = if (expected > 0) (expected - written).toInt().coerceAtLeast(0) else buf.size
            if (expected > 0 && remaining == 0) break
            val n = input.read(buf, 0, min(buf.size, remaining.coerceAtLeast(1)))
            if (n < 0) break
            output.write(buf, 0, n)
            written += n
            if (expected > 0) onProgress(min(1.0, written.toDouble() / expected.toDouble()))
            if (expected > 0 && written >= expected) break
        }
        output.flush()
        return written
    }

    fun storageOrder(first: Int): List<Int> = if (first == 0) listOf(0, 1) else listOf(1, 0)
}
