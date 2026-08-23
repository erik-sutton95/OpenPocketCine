package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.EvComp
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round

/**
 * Auto-expo face meter. Matches core `FacePriorityExposure`.
 * The body still takes EV thirds (`setEv`); we pick the stop from face boxes
 * on the encoded live tap. Target is 18% gray.
 */
object FacePriorityExposure {
    const val MIN_SAMPLES = 8
    const val SAMPLE_STRIDE = 2
    const val DEADBAND_STOPS = 2.0 / 3.0
    const val MAX_STEP_THIRDS = 1
    const val ACQUIRE_DURATION = 2.5
    const val ACQUIRE_INTERVAL = 0.4
    const val SETTLE_INTERVAL = 1.0

    data class Box(val x: Double, val y: Double, val width: Double, val height: Double) {
        val minX: Double get() = x
        val minY: Double get() = y
        val maxX: Double get() = x + width
        val maxY: Double get() = y + height
    }

    /** Fast for the first 2.5 s a face is in frame, then 1 s. Seconds, like iOS. */
    fun interval(sinceAcquireSec: Double?, elapsedSec: Double): Double {
        if (sinceAcquireSec == null) return ACQUIRE_INTERVAL
        return if (elapsedSec < ACQUIRE_DURATION) ACQUIRE_INTERVAL else SETTLE_INTERVAL
    }

    fun intervalSince(sinceAcquireMs: Long?, nowMs: Long): Double {
        if (sinceAcquireMs == null) return ACQUIRE_INTERVAL
        return interval(0.0, (nowMs - sinceAcquireMs) / 1000.0)
    }

    fun medianEncoded(
        bytes: ByteArray,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        boxes: List<Box>,
        transfer: MonitorTransfer,
    ): Double? {
        val (redW, greenW, blueW) = LiveColorScience.lumaWeights(transfer)
        val faceMedians = ArrayList<Double>(boxes.size)
        for (box in boxes) {
            val samples = ArrayList<Double>()
            val x0 = max(0, floor(box.minX * width).toInt())
            val y0 = max(0, floor(box.minY * height).toInt())
            val x1 = min(width, ceil(box.maxX * width).toInt())
            val y1 = min(height, ceil(box.maxY * height).toInt())
            if (x1 <= x0 || y1 <= y0) continue
            var y = y0
            while (y < y1) {
                val rowStart = y * bytesPerRow
                var x = x0
                while (x < x1) {
                    val i = rowStart + x * 4
                    if (i + 2 < bytes.size) {
                        val b = (bytes[i].toInt() and 0xFF).toDouble()
                        val g = (bytes[i + 1].toInt() and 0xFF).toDouble()
                        val r = (bytes[i + 2].toInt() and 0xFF).toDouble()
                        val luma = redW * r + greenW * g + blueW * b
                        samples.add(min(1.0, max(0.0, luma / 255.0)))
                    }
                    x += SAMPLE_STRIDE
                }
                y += SAMPLE_STRIDE
            }
            if (samples.size >= MIN_SAMPLES) {
                median(samples)?.let { faceMedians.add(it) }
            }
        }
        return median(faceMedians)
    }

    fun nextEV(current: EvComp, encoded: Double, transfer: MonitorTransfer): EvComp? {
        val stops = LiveColorScience.stops(encoded, transfer)
        if (!stops.isFinite()) return null
        if (abs(stops) < DEADBAND_STOPS) return null
        var deltaThirds = round(-stops * 3.0).toInt()
        if (deltaThirds == 0) return null
        deltaThirds = deltaThirds.coerceIn(-MAX_STEP_THIRDS, MAX_STEP_THIRDS)
        val next = EvComp.fromThirds(current.thirds + deltaThirds)
        return if (next == current) null else next
    }

    fun restoreEV(saved: EvComp?): EvComp = saved ?: EvComp.ZERO

    /** Write on disable, or null when already there / not Auto. */
    fun restoreWrite(saved: EvComp?, expoIsAuto: Boolean, current: EvComp?): EvComp? {
        if (!expoIsAuto) return null
        val restore = restoreEV(saved)
        return restore.takeIf { it != current }
    }

    fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val mid = sorted.size / 2
        return if (sorted.size % 2 == 0) {
            (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            sorted[mid]
        }
    }
}
