package com.opencapture.openpocketcine.session

/**
 * Whether a live decoder may be asked for low latency, and what to do when it says no.
 *
 * `KEY_LOW_LATENCY` is not a hint. The framework turns it into
 * `setConfig(OMX_IndexConfigLowLatency)` on a legacy OMX component, and a
 * component without that index answers `OMX_ErrorUnsupportedIndex`; `ACodec`
 * returns that error straight out of `configureCodec`, so `configure` throws and
 * the whole decoder is refused over one optional key. The neighbouring keys do
 * not behave this way — `max-input-size`, `priority` and `operating-rate` are
 * each followed by `err = OK; // ignore error` — which is why this is the only
 * tuning worth a decision.
 *
 * A 2017 Exynos part does exactly that: black live view, `codec:-1010`, and not
 * one picture ever submitted to decode, on a phone whose HEVC decoder is fine.
 *
 * The obvious guard — ask only where `FEATURE_LowLatency` is advertised — was
 * tried and refuted on a Galaxy S23. Qualcomm ships low latency as a *separate
 * component*: `c2.qti.avc.decoder` carries no such feature, while a sibling
 * `c2.qti.avc.decoder.low_latency` declares it. So the codec we pick answers no
 * on a phone where the key has always worked, and honouring that answer would
 * quietly drop the tuning across every Qualcomm device to fix one Exynos. An
 * advertisement is about a component, not about whether the key is safe to send,
 * so it cannot be read as a veto. Ask everywhere the API exists, as before, and
 * pay for the refusal only on the phone that actually refuses.
 */
internal object LiveDecoderTuning {
    /**
     * `MediaCodec` reports the component's refusal as ERROR_UNSUPPORTED.
     *
     * The constant is not public API, so it is spelled out here: it is
     * `MEDIA_ERROR_BASE - 10` in `MediaErrors.h`, which both
     * `OMX_ErrorUnsupportedIndex` and `OMX_ErrorUnsupportedSetting` map to.
     */
    const val ERROR_UNSUPPORTED = -1010

    /** `KEY_LOW_LATENCY` is first defined on API 30; below that there is nothing to ask. */
    const val FIRST_SDK = 30

    /**
     * Ask for low latency wherever the key exists — the pre-existing behaviour.
     *
     * Deliberately not narrowed by what the codec advertises: see the note on
     * this object for the Galaxy S23 measurement that ruled that out.
     */
    fun lowLatencyRequested(sdkInt: Int): Boolean = sdkInt >= FIRST_SDK

    /**
     * Retry a refused configure once without the low-latency key.
     *
     * Only for the attempt that carried it and only for the refusal it causes: a
     * codec that fails plain configure is broken in a way a second identical try
     * cannot fix, and reporting that failure twice would read as two faults.
     *
     * This is the whole fix. A phone that accepts the key never reaches here and
     * is untouched; a phone that refuses it pays one extra configure, once, and
     * gets a picture instead of a black well.
     */
    fun retryWithoutLowLatency(carriedLowLatency: Boolean, errorCode: Int?): Boolean =
        carriedLowLatency && errorCode == ERROR_UNSUPPORTED
}
