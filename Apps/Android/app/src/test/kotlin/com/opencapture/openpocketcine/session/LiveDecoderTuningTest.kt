package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LiveDecoderTuningTest {
    @Test fun lowLatencyIsAskedForWhereverTheKeyExists() {
        // Measured on a Galaxy S23: the chosen c2.qti.avc.decoder does not carry
        // the low-latency feature (Qualcomm ships that as a separate
        // c2.qti.avc.decoder.low_latency component), yet the key has always
        // worked there. Gating on the advertisement would drop the tuning across
        // Qualcomm to fix one Exynos, so the request stays unconditional.
        assertTrue(LiveDecoderTuning.lowLatencyRequested(sdkInt = 34))
    }

    @Test fun lowLatencyIsNotAskedForBeforeTheApiThatDefinesIt() {
        assertFalse(LiveDecoderTuning.lowLatencyRequested(sdkInt = 29))
        assertTrue(LiveDecoderTuning.lowLatencyRequested(sdkInt = 30))
    }

    @Test fun aRefusedLowLatencyConfigureIsRetriedWithoutIt() {
        assertTrue(
            LiveDecoderTuning.retryWithoutLowLatency(
                carriedLowLatency = true,
                errorCode = LiveDecoderTuning.ERROR_UNSUPPORTED,
            ),
        )
    }

    @Test fun aPlainConfigureFailureIsReportedRatherThanRetried() {
        // Nothing was asked for that could be given up, so a second identical
        // attempt would only report the same fault twice.
        assertFalse(
            LiveDecoderTuning.retryWithoutLowLatency(
                carriedLowLatency = false,
                errorCode = LiveDecoderTuning.ERROR_UNSUPPORTED,
            ),
        )
    }

    @Test fun onlyTheRefusalThatLowLatencyCausesIsRetried() {
        // A reclaimed or resource-starved codec is a different fault; dropping
        // low latency does not answer it, and retrying would hide it.
        assertFalse(LiveDecoderTuning.retryWithoutLowLatency(carriedLowLatency = true, errorCode = 1101))
        assertFalse(LiveDecoderTuning.retryWithoutLowLatency(carriedLowLatency = true, errorCode = 1100))
        // Not a CodecException at all: no code to read.
        assertFalse(LiveDecoderTuning.retryWithoutLowLatency(carriedLowLatency = true, errorCode = null))
    }
}
