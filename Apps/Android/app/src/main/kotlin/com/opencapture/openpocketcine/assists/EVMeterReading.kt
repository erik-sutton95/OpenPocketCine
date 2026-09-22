package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.NDFilterRecommendation
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.ScopeAssistBundle

/** A picture measurement; independent of camera exposure mode and compensation. */
internal class EVMeterReading(pictureStops: Double?, val estimated: Boolean = false) {
    val stops: Double? = pictureStops?.takeIf { it.isFinite() }
    val label: String = stops?.let(NDFilterRecommendation::stopsLabel) ?: "—"
    val title: String = if (estimated) "EV ≈" else "EV"
    val needleFraction: Float? = stops?.let { ((it.coerceIn(-3.0, 3.0) + 3.0) / 6.0).toFloat() }
    val accessibilityLabel: String
        get() = when {
            stops == null -> "Exposure meter, unavailable"
            estimated -> "Exposure meter, approximately $label stops relative to middle gray"
            else -> "Exposure meter, $label stops relative to middle gray"
        }

    companion object {
        const val HELP = "Measures median picture brightness in stops relative to middle gray. " +
            "Positive is brighter; negative is darker. Works in Auto and Manual without changing camera settings. " +
            "D-Log M is an estimate."

        fun from(bundle: ScopeAssistBundle): EVMeterReading = EVMeterReading(
            NDFilterRecommendation.pictureStops(bundle.samples.histogramLuma, bundle.transfer),
            estimated = bundle.transfer == MonitorTransfer.DLOGM,
        )
    }
}
