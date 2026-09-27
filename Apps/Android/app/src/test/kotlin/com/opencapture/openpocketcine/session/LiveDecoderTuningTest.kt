package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals

class LiveDecoderTuningTest {
    @Test fun lowLatencyIsAskedForFromTheApiThatDefinesIt() {
        // Measured on a Galaxy S23: the chosen c2.qti.avc.decoder does not carry
        // the low-latency feature (Qualcomm ships that as a separate
        // c2.qti.avc.decoder.low_latency component), yet the key has always
        // worked there. Gating on the advertisement would drop the tuning across
        // Qualcomm to fix one Exynos, so the request stays unconditional.
        for ((sdk, asked) in listOf(29 to false, 30 to true, 34 to true)) {
            assertEquals(asked, LiveDecoderTuning.lowLatencyRequested(sdkInt = sdk), "sdk $sdk")
        }
    }

    @Test fun onlyARefusedLowLatencyConfigureIsRetriedWithoutIt() {
        val cases = listOf(
            Triple(true, LiveDecoderTuning.ERROR_UNSUPPORTED, true),
            // Nothing was asked for that could be given up, so a second identical
            // attempt would only report the same fault twice.
            Triple(false, LiveDecoderTuning.ERROR_UNSUPPORTED, false),
            // A reclaimed or resource-starved codec is a different fault; dropping
            // low latency does not answer it, and retrying would hide it.
            Triple(true, 1101, false),
            Triple(true, 1100, false),
            // Not a CodecException at all: no code to read.
            Triple(true, null, false),
        )
        for ((carried, code, retry) in cases) {
            assertEquals(
                retry,
                LiveDecoderTuning.retryWithoutLowLatency(carriedLowLatency = carried, errorCode = code),
                "carriedLowLatency=$carried errorCode=$code",
            )
        }
    }
}
