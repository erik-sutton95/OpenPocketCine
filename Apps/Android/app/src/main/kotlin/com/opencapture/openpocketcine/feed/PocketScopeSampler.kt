package com.opencapture.openpocketcine.feed

import kotlin.math.ln
import kotlin.math.round
import kotlin.math.roundToInt

/** One sampled pixel for WAVE / PARADE / VECTOR. Bytes are native curve codes. */
data class ScopePoint(
    val xRatio: Double,
    val yRatio: Double,
    val red: Int,
    val green: Int,
    val blue: Int,
    val luma: Int,
)

/** Shared tap product. Histograms are 256-bin native-code counts. */
data class ScopeSamples(
    val histogramLuma: IntArray,
    val histogramRed: IntArray,
    val histogramGreen: IntArray,
    val histogramBlue: IntArray,
    val points: List<ScopePoint>,
) {
    companion object {
        val EMPTY =
            ScopeSamples(
                IntArray(256),
                IntArray(256),
                IntArray(256),
                IntArray(256),
                emptyList(),
            )
    }
}

/** Remapped / blended / smoothed HISTO curves on the WAVE IRE axis. */
data class ScopeHistogramDisplay(
    val luma: FloatArray,
    val red: FloatArray,
    val green: FloatArray,
    val blue: FloatArray,
) {
    companion object {
        val EMPTY =
            ScopeHistogramDisplay(
                FloatArray(256),
                FloatArray(256),
                FloatArray(256),
                FloatArray(256),
            )
    }
}

/** One published tick for every scope surface. */
data class ScopeAssistBundle(
    val revision: Long = 0,
    val samples: ScopeSamples = ScopeSamples.EMPTY,
    val vectorscopePoints: List<ScopePoint> = emptyList(),
    val trailSamples: ScopeSamples = ScopeSamples.EMPTY,
    val trailVectorscopePoints: List<ScopePoint> = emptyList(),
    val traffic: ScopeTrafficLightsReading = ScopeTrafficLightsReading.NONE,
    val histogramDisplay: ScopeHistogramDisplay = ScopeHistogramDisplay.EMPTY,
    val transfer: MonitorTransfer = MonitorTransfer.REC709,
    val iso: Int = ScopeExposureCeiling.REFERENCE_EI,
) {
    val isEmpty: Boolean
        get() = revision == 0L && samples.points.isEmpty() && samples.histogramLuma.all { it == 0 }

    companion object {
        val EMPTY = ScopeAssistBundle()
    }
}

/**
 * OpenZCine `ScopeSampler` on the GLES tap. WAVE / PARADE / HISTO / LIGHTS
 * meter encoded camera codes; VECTOR maps the same walk through the display look.
 */
object PocketScopeSampler {
    const val MAX_WIDTH = 200
    const val POINT_STRIDE = 2
    const val BASE_MIN_INTERVAL_NS = 1_000_000_000L / 15
    const val DENSE_MIN_INTERVAL_NS = 1_000_000_000L / 10
    const val DENSE_ASSIST_THRESHOLD = 2
    const val TRAIL_DECAY = 0.35

    fun tapSize(srcW: Int, srcH: Int, maxWidth: Int = MAX_WIDTH): Pair<Int, Int> {
        val step = maxOf(1, srcW / maxOf(8, maxWidth))
        return maxOf(8, srcW / step) to maxOf(8, srcH / step)
    }

    fun minIntervalNs(activeScopeCount: Int, thermalMultiplier: Double = 1.0): Long {
        val base =
            if (activeScopeCount > DENSE_ASSIST_THRESHOLD) DENSE_MIN_INTERVAL_NS else BASE_MIN_INTERVAL_NS
        return (base * thermalMultiplier).toLong().coerceAtLeast(BASE_MIN_INTERVAL_NS)
    }

    fun thermalMultiplier(androidThermalStatus: Int): Double =
        when (androidThermalStatus) {
            // PowerManager.THERMAL_STATUS_SEVERE
            3 -> 3.0
            // CRITICAL / EMERGENCY / SHUTDOWN
            4, 5, 6 -> 5.0
            else -> 1.0
        }

    fun minMaxRGB(bytes: ByteArray): Pair<Int, Int> {
        var minC = 255
        var maxC = 0
        var i = 0
        while (i + 2 < bytes.size) {
            val r = bytes[i].toInt() and 0xFF
            val g = bytes[i + 1].toInt() and 0xFF
            val b = bytes[i + 2].toInt() and 0xFF
            val lo = minOf(r, g, b)
            val hi = maxOf(r, g, b)
            if (lo < minC) minC = lo
            if (hi > maxC) maxC = hi
            i += 4
        }
        return minC to maxC
    }

    fun sample(
        bytes: ByteArray,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        transfer: MonitorTransfer,
        includePoints: Boolean,
        includeVectorPoints: Boolean = false,
        look: FeedEffectsCube? = null,
        trafficThreshold: Double = ScopeTrafficLights.DEFAULT_THRESHOLD,
        previous: ScopeAssistBundle = ScopeAssistBundle.EMPTY,
        iso: Int = ScopeExposureCeiling.resolvedISO(),
    ): ScopeAssistBundle {
        val histY = IntArray(256)
        val histR = IntArray(256)
        val histG = IntArray(256)
        val histB = IntArray(256)
        val needsPoints = includePoints || includeVectorPoints
        val points =
            if (needsPoints) {
                val columns = (width + POINT_STRIDE - 1) / POINT_STRIDE
                val rows = (height + POINT_STRIDE - 1) / POINT_STRIDE
                ArrayList<ScopePoint>(maxOf(0, columns * rows))
            } else {
                ArrayList()
            }
        val widthDivisor = maxOf(width, 1).toDouble()
        val heightDivisor = maxOf(height, 1).toDouble()
        val lumaW = LiveColorScience.lumaWeights(transfer)
        var y = 0
        while (y < height) {
            val rowStart = y * bytesPerRow
            var x = 0
            while (x < width) {
                val i = rowStart + x * 4
                if (i + 2 >= bytes.size) break
                val r = bytes[i].toInt() and 0xFF
                val g = bytes[i + 1].toInt() and 0xFF
                val b = bytes[i + 2].toInt() and 0xFF
                val lumaValue = lumaW.first * r + lumaW.second * g + lumaW.third * b
                val luma = lumaValue.roundToInt().coerceIn(0, 255)
                histY[luma] += 1
                histR[r] += 1
                histG[g] += 1
                histB[b] += 1
                if (needsPoints) {
                    points.add(
                        ScopePoint(
                            xRatio = x / widthDivisor,
                            yRatio = y / heightDivisor,
                            red = r,
                            green = g,
                            blue = b,
                            luma = luma,
                        ),
                    )
                }
                x += POINT_STRIDE
            }
            y += POINT_STRIDE
        }
        val samples =
            ScopeSamples(
                histogramLuma = histY,
                histogramRed = histR,
                histogramGreen = histG,
                histogramBlue = histB,
                points = if (includePoints) points else emptyList(),
            )
        val vectorPoints = if (includeVectorPoints) monitorPoints(points, look) else emptyList()
        return ScopeAssistBundle(
            revision = previous.revision + 1,
            samples = samples,
            vectorscopePoints = vectorPoints,
            trailSamples = previous.samples,
            trailVectorscopePoints = previous.vectorscopePoints,
            traffic =
                ScopeTrafficLights.reading(
                    red = histR,
                    green = histG,
                    blue = histB,
                    transfer = transfer,
                    threshold = trafficThreshold,
                    previous = previous.traffic,
                    luma = histY,
                ),
            histogramDisplay = histogramDisplay(samples, previous.histogramDisplay, transfer, iso),
            transfer = transfer,
            iso = iso,
        )
    }

    fun monitorPoints(points: List<ScopePoint>, look: FeedEffectsCube?): List<ScopePoint> {
        if (look == null) return points
        return points.map { point ->
            val mapped =
                look.map(
                    red = point.red / 255f,
                    green = point.green / 255f,
                    blue = point.blue / 255f,
                )
            val red = mapped.first.toDouble()
            val green = mapped.second.toDouble()
            val blue = mapped.third.toDouble()
            val luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            ScopePoint(
                xRatio = point.xRatio,
                yRatio = point.yRatio,
                red = displayByte(red),
                green = displayByte(green),
                blue = displayByte(blue),
                luma = displayByte(luma),
            )
        }
    }

    fun histogramDisplay(
        samples: ScopeSamples,
        previous: ScopeHistogramDisplay,
        transfer: MonitorTransfer,
        iso: Int? = null,
    ): ScopeHistogramDisplay =
        ScopeHistogramDisplay(
            luma = displayChannel(samples.histogramLuma, previous.luma, transfer, iso),
            red = displayChannel(samples.histogramRed, previous.red, transfer, iso),
            green = displayChannel(samples.histogramGreen, previous.green, transfer, iso),
            blue = displayChannel(samples.histogramBlue, previous.blue, transfer, iso),
        )

    fun displayChannel(
        native: IntArray,
        previous: FloatArray,
        transfer: MonitorTransfer,
        iso: Int? = null,
    ): FloatArray {
        val remapped = WaveformIre.remapHistogram(native, transfer, iso)
        val blended = FloatArray(256)
        val hasPrevious = previous.size == 256
        for (i in 0 until 256) {
            val current = remapped[i].toFloat()
            blended[i] = if (hasPrevious) 0.65f * current + 0.35f * previous[i] else current
        }
        return boxBlur(blended, radius = 2)
    }

    fun boxBlur(values: FloatArray, radius: Int): FloatArray {
        if (radius <= 0 || values.size <= 1) return values
        val out = FloatArray(values.size)
        for (i in values.indices) {
            val lo = maxOf(0, i - radius)
            val hi = minOf(values.lastIndex, i + radius)
            var sum = 0f
            for (j in lo..hi) sum += values[j]
            out[i] = sum / (hi - lo + 1)
        }
        return out
    }

    private fun displayByte(value: Double): Int = (value * 255).roundToInt().coerceIn(0, 255)
}

/** BT.709 chroma used by both VECTOR binning and the 75% graticule targets. */
object ScopeChroma {
    fun rec709(red: Double, green: Double, blue: Double): Pair<Double, Double> {
        val y = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return (blue - y) / 1.8556 to (red - y) / 1.5748
    }

    fun rec709(red: Int, green: Int, blue: Int): Pair<Double, Double> =
        rec709(red / 255.0, green / 255.0, blue / 255.0)

    fun traceTint(red: Double, green: Double, blue: Double): Triple<Double, Double, Double> {
        val low = minOf(red, green, blue)
        val high = maxOf(red, green, blue)
        val span = high - low
        if (high <= 0.000_001 || span <= 0.000_001) return Triple(1.0, 1.0, 1.0)
        val saturation = (span / high).coerceIn(0.0, 1.0)
        fun tint(component: Double): Double {
            val pure = (component - low) / span
            return (1 - saturation) + pure * saturation
        }
        return Triple(tint(red), tint(green), tint(blue))
    }
}

/** OpenZCine 128-bin CbCr density raster. */
object VectorscopeRaster {
    const val BINS = 128

    fun binIndex(red: Int, green: Int, blue: Int, gain: Double = 1.0): Pair<Int, Int>? {
        val chroma = ScopeChroma.rec709(red, green, blue)
        val x = chroma.first * gain + 0.5
        val y = chroma.second * gain + 0.5
        if (x < 0 || x > 1 || y < 0 || y > 1) return null
        val scale = (BINS - 1).toDouble()
        return round(x * scale).toInt() to round(y * scale).toInt()
    }

    /** Premultiplied RGBA8, +Cr flipped up. Null when nothing lands. */
    fun pixels(points: List<ScopePoint>, gain: Double, intensity: Double): ByteArray? {
        if (points.isEmpty()) return null
        val n = BINS
        val counts = IntArray(n * n)
        val sumRed = LongArray(n * n)
        val sumGreen = LongArray(n * n)
        val sumBlue = LongArray(n * n)
        for (point in points) {
            val bin = binIndex(point.red, point.green, point.blue, gain) ?: continue
            val idx = bin.second * n + bin.first
            counts[idx] += 1
            sumRed[idx] += point.red.toLong()
            sumGreen[idx] += point.green.toLong()
            sumBlue[idx] += point.blue.toLong()
        }
        var peak = 0
        for (c in counts) if (c > peak) peak = c
        if (peak <= 0) return null
        val logPeak = ln(1.0 + peak)
        val pixels = ByteArray(n * n * 4)
        for (index in 0 until n * n) {
            val count = counts[index]
            if (count <= 0) continue
            val density = ln(1.0 + count) / logPeak
            val alpha = ((0.4 + 0.6 * density) * intensity).coerceIn(0.0, 1.0)
            val tint =
                ScopeChroma.traceTint(
                    sumRed[index].toDouble() / (count * 255.0),
                    sumGreen[index].toDouble() / (count * 255.0),
                    sumBlue[index].toDouble() / (count * 255.0),
                )
            val row = n - 1 - index / n
            val column = index % n
            val offset = (row * n + column) * 4
            pixels[offset] = (255 * tint.first * alpha).roundToInt().toByte()
            pixels[offset + 1] = (255 * tint.second * alpha).roundToInt().toByte()
            pixels[offset + 2] = (255 * tint.third * alpha).roundToInt().toByte()
            pixels[offset + 3] = (255 * alpha).roundToInt().toByte()
        }
        return pixels
    }
}
