package com.opencapture.openpocketcine.feed

import com.opencapture.opencine.media.ScopeClipCalibration
import com.opencapture.opencine.media.ScopeClipProfile

/** Measured preview calibration belongs to the source adapter, independent of common curve math. */
class ScopeExposureCeiling : com.opencapture.opencine.media.ScopeExposureCeiling(PROFILE) {
    companion object {
        const val REFERENCE_EI = 1600
        const val DLOG_REFERENCE_EI = 400
        const val DLOG2_LIVE_TAP_BYTE_AT_1600 = 247
        const val DLOG2_LIVE_TAP_BYTE_AT_1600_HIGH = 248
        const val DLOG_LIVE_TAP_BYTE_AT_NATIVE = 223
        const val DLOG_LIVE_TAP_BYTE_AT_NATIVE_HIGH = 224
        const val CLIP_SHELF_CODES = 7
        val PROFILE = ScopeClipProfile(mapOf(
            MonitorTransfer.DLOG2 to ScopeClipCalibration(REFERENCE_EI,
                DLOG2_LIVE_TAP_BYTE_AT_1600, DLOG2_LIVE_TAP_BYTE_AT_1600_HIGH),
            MonitorTransfer.DLOG to ScopeClipCalibration(DLOG_REFERENCE_EI,
                DLOG_LIVE_TAP_BYTE_AT_NATIVE, DLOG_LIVE_TAP_BYTE_AT_NATIVE_HIGH, refinementAtOrAboveReference = true),
        ), defaultIso = REFERENCE_EI)
        val UNOBSERVED get() = ScopeExposureCeiling()
    }
}
