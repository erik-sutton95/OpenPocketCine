package com.opencapture.openpocketcine

import com.opencapture.opencine.media.MonitorNDFilterRecommendation
import com.opencapture.openpocketcine.feed.MonitorTransfer

typealias NDFilterNotation = com.opencapture.opencine.media.MonitorNDFilterNotation
typealias NDFilterSuggestion = com.opencapture.opencine.media.MonitorNDFilterSuggestion

/** Existing app-facing labels/factory; measured histogram absence stays optional. */
object NDFilterRecommendation {
    const val MIN_STOPS = MonitorNDFilterRecommendation.MIN_STOPS
    const val MAX_STOPS = MonitorNDFilterRecommendation.MAX_STOPS
    val opticalFactors = MonitorNDFilterRecommendation.opticalFactors
    const val NONE_LABEL = "\u2014"
    const val DENSITY_PER_STOP = MonitorNDFilterRecommendation.DENSITY_PER_STOP

    fun opticalFactor(stops: Int): Int = MonitorNDFilterRecommendation.opticalFactor(stops)
    fun ndLabel(stops: Int): String = MonitorNDFilterRecommendation.ndLabel(stops, NONE_LABEL)
    fun stopsLabel(stops: Double): String = MonitorNDFilterRecommendation.stopsLabel(stops, NONE_LABEL)
    fun densityLabel(stops: Double): String = MonitorNDFilterRecommendation.densityLabel(stops, NONE_LABEL)
    fun pictureStops(lumaHistogram: IntArray, transfer: MonitorTransfer): Double? =
        MonitorNDFilterRecommendation.pictureStops(lumaHistogram, transfer)
    fun suggestion(pictureStops: Double): NDFilterSuggestion =
        MonitorNDFilterRecommendation.suggestion(pictureStops, NONE_LABEL)
            ?: NDFilterSuggestion(0.0, 0, 1, NONE_LABEL, "0.0")
    fun reading(lumaHistogram: IntArray, transfer: MonitorTransfer): NDFilterSuggestion? =
        MonitorNDFilterRecommendation.reading(lumaHistogram, transfer, NONE_LABEL)
}
