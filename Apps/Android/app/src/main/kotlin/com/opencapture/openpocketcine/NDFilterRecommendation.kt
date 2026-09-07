package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.feed.LiveColorScience
import com.opencapture.openpocketcine.feed.MonitorTransfer
import kotlin.math.abs
import kotlin.math.floor

/** Live-picture ND reading. Suggestion only — not a SET. */
data class NDFilterSuggestion(
    val pictureStops: Double,
    val ndStops: Int,
    val opticalFactor: Int,
    val ndLabel: String,
    val stopsLabel: String,
) {
    val needsGlass: Boolean
        get() = ndStops >= 1
}

/**
 * Meters the live luma histogram against middle gray and names a screw-on ND
 * that would balance the picture. Lockstep of core `NDFilterRecommendation`.
 */
object NDFilterRecommendation {
    const val MIN_STOPS = 1
    const val MAX_STOPS = 10
    val opticalFactors = listOf(2, 4, 8, 16, 32, 64, 128, 256, 512, 1_000)
    const val NONE_LABEL = "—"

    fun opticalFactor(stops: Int): Int {
        if (stops < MIN_STOPS) return 1
        val idx = stops.coerceIn(MIN_STOPS, MAX_STOPS) - 1
        return opticalFactors[idx]
    }

    fun ndLabel(stops: Int): String {
        if (stops < MIN_STOPS) return NONE_LABEL
        return "ND${opticalFactor(stops)}"
    }

    fun stopsLabel(stops: Double): String {
        if (!stops.isFinite()) return "—"
        if (abs(stops) < 0.05) return "0.0"
        val sign = if (stops > 0) "+" else "−"
        return sign + String.format("%.1f", abs(stops))
    }

    fun pictureStops(lumaHistogram: IntArray, transfer: MonitorTransfer): Double? {
        if (lumaHistogram.size < 2) return null
        var total = 0
        for (count in lumaHistogram) total += count
        if (total <= 0) return null
        var seen = 0
        val half = (total + 1) / 2
        val last = minOf(lumaHistogram.size, 256)
        for (code in 0 until last) {
            seen += lumaHistogram[code]
            if (seen >= half) {
                val encoded = code / 255.0
                val stops = LiveColorScience.stops(encoded, transfer)
                return if (stops.isFinite()) stops else null
            }
        }
        return null
    }

    fun suggestion(pictureStops: Double): NDFilterSuggestion {
        val picture = if (pictureStops.isFinite()) pictureStops else 0.0
        val ndStops =
            if (picture >= 0.5) {
                floor(picture + 0.5).toInt().coerceIn(MIN_STOPS, MAX_STOPS)
            } else {
                0
            }
        return NDFilterSuggestion(
            pictureStops = picture,
            ndStops = ndStops,
            opticalFactor = opticalFactor(ndStops),
            ndLabel = ndLabel(ndStops),
            stopsLabel = stopsLabel(picture),
        )
    }

    fun reading(lumaHistogram: IntArray, transfer: MonitorTransfer): NDFilterSuggestion? {
        val picture = pictureStops(lumaHistogram, transfer) ?: return null
        return suggestion(picture)
    }
}
