package com.opencapture.openpocketcine.diagnostics

import com.opencapture.opencine.appkit.diagnostics.ManualReportCall
import com.opencapture.opencine.appkit.diagnostics.ManualReportResponse
import com.opencapture.opencine.appkit.diagnostics.ManualReportUpload
import java.util.concurrent.TimeUnit
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** OkHttp for OpenCine's manual problem report: no redirects or silent retries, bounded waits. */
internal object OkHttpManualReportUpload : ManualReportUpload {
    override fun call(url: String, contentType: String, body: ByteArray, headers: Map<String, String>): ManualReportCall {
        val client =
            OkHttpClient.Builder()
                .followRedirects(false)
                .followSslRedirects(false)
                .retryOnConnectionFailure(false)
                .connectTimeout(20, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .callTimeout(120, TimeUnit.SECONDS)
                .build()
        val request = Request.Builder().url(url).post(body.toRequestBody(contentType.toMediaType()))
        for ((name, value) in headers) request.header(name, value)
        val call = client.newCall(request.build())
        return object : ManualReportCall {
            override fun execute(): ManualReportResponse =
                call.execute().use { response -> ManualReportResponse(response.code, response.header("Retry-After")) }

            override fun cancel() {
                call.cancel()
            }

            override val isCanceled: Boolean
                get() = call.isCanceled()
        }
    }
}
