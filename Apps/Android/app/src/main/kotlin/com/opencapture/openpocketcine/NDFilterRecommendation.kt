package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.feed.LiveColorScience
import com.opencapture.openpocketcine.feed.MonitorTransfer
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log2

/** Screw-on ND stop so 180° shutter holds. Recommendation only — not a SET. */
data class NDFilterSuggestion(
    val stops: Int,
    val opticalFactor: Int,
    val label: String,
    val line: String,
)

/**
 * How many ND stops would keep 180° (and native ISO, when the curve has one)
 * given the live shutter, ISO, and an optional picture meter.
 *
 * Lockstep of core `NDFilterRecommendation`.
 */
object NDFilterRecommendation {
    const val MIN_STOPS = 1
    const val MAX_STOPS = 10
    val opticalFactors = listOf(2, 4, 8, 16, 32, 64, 128, 256, 512, 1_000)
    const val PICTURE_DEADBAND_STOPS = 1.0 / 3.0

    fun opticalFactor(stops: Int): Int {
        val idx = stops.coerceIn(MIN_STOPS, MAX_STOPS) - 1
        return opticalFactors[idx]
    }

    fun label(stops: Int): String = "ND${opticalFactor(stops)}"

    /** Native base ISO for the live transfer. Rec.709 / HLG have none. */
    fun baseISO(transfer: MonitorTransfer?): Int? =
        when (transfer) {
            MonitorTransfer.DLOG -> 400
            MonitorTransfer.DLOG2 -> 1600
            else -> null
        }

    /** Median luma vs 18% grey, in stops. Null when the histogram is empty. */
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

    /** Manual expo only. Null when already within half a stop of 180° / native. */
    fun suggest(
        expoIsManual: Boolean,
        shutterDenom: Int,
        fps: Int,
        iso: Int,
        isoIsAuto: Boolean,
        transfer: MonitorTransfer?,
        pictureStops: Double? = null,
    ): NDFilterSuggestion? {
        if (!expoIsManual) return null
        if (shutterDenom <= 0 || fps !in 8..240) return null
        val targetDenom = ShutterAngle.denom(ShutterAngle.DEFAULT_DEGREES, fps)
        if (targetDenom <= 0) return null
        val shutterStops = log2(shutterDenom.toDouble() / targetDenom.toDouble())
        var isoStops = 0.0
        val native = if (!isoIsAuto && iso > 0) baseISO(transfer) else null
        if (native != null) {
            isoStops = log2(iso.toDouble() / native.toDouble())
        }
        val picture =
            if (pictureStops != null && pictureStops.isFinite() &&
                abs(pictureStops) >= PICTURE_DEADBAND_STOPS
            ) {
                pictureStops
            } else {
                0.0
            }
        val needed = shutterStops + isoStops + picture
        if (!needed.isFinite() || needed < 0.5) return null
        val stops = floor(needed + 0.5).toInt().coerceIn(MIN_STOPS, MAX_STOPS)
        val factor = opticalFactor(stops)
        val name = label(stops)
        val angle = ShutterAngle.label(ShutterAngle.DEFAULT_DEGREES)
        return NDFilterSuggestion(
            stops = stops,
            opticalFactor = factor,
            label = name,
            line = "Try $name so $angle holds",
        )
    }
}
