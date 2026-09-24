package com.opencapture.openpocketcine.assists

import android.graphics.Bitmap
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.opencapture.openpocketcine.feed.PocketScopeSampler
import com.opencapture.openpocketcine.feed.ScopePoint
import com.opencapture.openpocketcine.feed.VectorscopeRaster
import kotlin.math.roundToInt

/**
 * Bake WAVE / PARADE / VECTOR traces at the density-1 plot size (not the
 * panel). Compose fills the 0.72 plate once and Plus-blits this image into
 * the live plot rect so L-scale cannot drift IRE 100.
 */
internal object ScopeTraceRaster {
    val WAVE_W: Int = ScopePanelSize.waveform.width.roundToInt()
    val WAVE_H: Int = ScopePanelSize.waveform.height.roundToInt()
    val VECTOR_W: Int = ScopePanelSize.vectorscope.width.roundToInt()
    val VECTOR_H: Int = ScopePanelSize.vectorscope.height.roundToInt()
    val VECTOR_N: Int = VectorscopeRaster.BINS

    val wavePlot: AssistRect
        get() = WaveformAxis.plotRect(WAVE_W.toFloat(), WAVE_H.toFloat(), 1f)

    val vectorPlot: AssistRect
        get() = VectorscopeGraticule.plotSquare(VECTOR_W.toFloat(), VECTOR_H.toFloat(), 1f)

    val wavePlotW: Int
        get() = wavePlot.width.roundToInt().coerceAtLeast(1)
    val wavePlotH: Int
        get() = wavePlot.height.roundToInt().coerceAtLeast(1)
    val vectorPlotW: Int
        get() = vectorPlot.width.roundToInt().coerceAtLeast(1)
    val vectorPlotH: Int
        get() = vectorPlot.height.roundToInt().coerceAtLeast(1)

    fun vectorscope(
        live: List<ScopePoint>,
        trail: List<ScopePoint>,
        gain: Double,
        intensity: Double,
    ): ImageBitmap? = vectorscopeArgb(live, trail, gain, intensity)?.toImage(vectorPlotW, vectorPlotH)

    fun waveformArgb(
        live: List<ScopePoint>,
        trail: List<ScopePoint>,
        table: FloatArray,
        mode: WaveformMode,
        intensity: Double,
    ): IntArray? = TraceLayers().waveformArgb(live, trail, table, mode, intensity)?.copyOf()

    fun paradeArgb(
        live: List<ScopePoint>,
        trail: List<ScopePoint>,
        table: FloatArray,
        mode: ParadeMode,
        intensity: Double,
    ): IntArray? = TraceLayers().paradeArgb(live, trail, table, mode, intensity)?.copyOf()

    /**
     * One WAVE / PARADE panel's retained build. The trail is the previous bundle's
     * samples and the splat is linear in intensity, so the previous build's live layer
     * times TRAIL_DECAY is the trail: an update splats one sample set into kept buffers
     * instead of two into fresh ones (iOS reuses its previous build the same way).
     */
    class TraceLayers {
        private val w = wavePlotW
        private val h = wavePlotH
        private val plot = AssistRect(0f, 0f, w.toFloat(), h.toFloat())
        private var live = Array(3) { FloatArray(w * h) }
        private var previous = Array(3) { FloatArray(w * h) }
        private var previousPoints: List<ScopePoint>? = null
        private var previousKey: Any? = null
        private val out = IntArray(w * h)

        @Synchronized
        fun waveform(live: List<ScopePoint>, trail: List<ScopePoint>, table: FloatArray, mode: WaveformMode, intensity: Double) =
            waveformArgb(live, trail, table, mode, intensity)?.toImage(w, h)

        @Synchronized
        fun parade(live: List<ScopePoint>, trail: List<ScopePoint>, table: FloatArray, mode: ParadeMode, intensity: Double) =
            paradeArgb(live, trail, table, mode, intensity)?.toImage(w, h)

        /** The returned array is reused by the next build. */
        @Synchronized
        fun waveformArgb(live: List<ScopePoint>, trail: List<ScopePoint>, table: FloatArray, mode: WaveformMode, intensity: Double) =
            build(live, trail, Triple(table, mode, intensity), intensity) { layer, points ->
                splatWave(layer[0], layer[1], layer[2], plot, points, table, mode, intensity, w, h)
            }

        /** The returned array is reused by the next build. */
        @Synchronized
        fun paradeArgb(live: List<ScopePoint>, trail: List<ScopePoint>, table: FloatArray, mode: ParadeMode, intensity: Double) =
            build(live, trail, Triple(table, mode, intensity), intensity) { layer, points ->
                splatParade(layer[0], layer[1], layer[2], plot, points, table, mode, intensity, w, h)
            }

        private fun build(
            livePoints: List<ScopePoint>,
            trailPoints: List<ScopePoint>,
            key: Any,
            intensity: Double,
            splat: (Array<FloatArray>, List<ScopePoint>) -> Unit,
        ): IntArray? {
            if (livePoints.isEmpty() && trailPoints.isEmpty() || intensity <= 0) return null
            if (trailPoints !== previousPoints || key != previousKey) {
                previous.forEach { it.fill(0f) }
                splat(previous, trailPoints)
            }
            live.forEach { it.fill(0f) }
            splat(live, livePoints)
            val any = packTraces(live[0], live[1], live[2], out, previous, PocketScopeSampler.TRAIL_DECAY.toFloat())
            // This build's live layer is the next build's trail.
            previous = live.also { live = previous }
            previousPoints = livePoints
            previousKey = key
            return if (any != null) out else null
        }
    }

    fun vectorscopeArgb(
        live: List<ScopePoint>,
        trail: List<ScopePoint>,
        gain: Double,
        intensity: Double,
    ): IntArray? {
        if (live.isEmpty() && trail.isEmpty()) return null
        if (intensity <= 0) return null
        val w = vectorPlotW
        val h = vectorPlotH
        val plot = AssistRect(0f, 0f, w.toFloat(), h.toFloat())
        val n = w * h
        val red = FloatArray(n)
        val green = FloatArray(n)
        val blue = FloatArray(n)
        if (trail.isNotEmpty()) {
            stampVector(red, green, blue, plot, trail, gain, intensity * PocketScopeSampler.TRAIL_DECAY, w, h)
        }
        stampVector(red, green, blue, plot, live, gain, intensity, w, h)
        return packTraces(red, green, blue)
    }

    private fun splatWave(
        red: FloatArray,
        green: FloatArray,
        blue: FloatArray,
        plot: AssistRect,
        points: List<ScopePoint>,
        table: FloatArray,
        mode: WaveformMode,
        intensity: Double,
        width: Int,
        height: Int,
    ) {
        if (points.isEmpty() || intensity <= 0) return
        val gain = intensity.toFloat()
        when (mode) {
            WaveformMode.LUMA -> {
                val ghost = gain * 0.25f
                points.forEachIndexed { index, point ->
                    val x = xFor(point.xRatio, plot)
                    val y = yFor(table, point.luma, plot)
                    add(red, green, blue, x, y, width, height, 182 / 255f * ghost, 190 / 255f * ghost, 186 / 255f * ghost)
                    add(red, green, blue, x, y, width, height, 222 / 255f * gain, 230 / 255f * gain, 224 / 255f * gain)
                    if (index and 3 == 0) {
                        add(red, green, blue, x, y, width, height, gain, gain, gain)
                    }
                }
            }
            WaveformMode.RGB -> {
                val channel = gain * 0.55f
                for (point in points) {
                    val x = xFor(point.xRatio, plot)
                    add(
                        red, green, blue, x, yFor(table, point.red, plot), width, height,
                        channel, 64 / 255f * channel, 54 / 255f * channel,
                    )
                    add(
                        red, green, blue, x, yFor(table, point.green, plot), width, height,
                        70 / 255f * channel, channel, 110 / 255f * channel,
                    )
                    add(
                        red, green, blue, x, yFor(table, point.blue, plot), width, height,
                        72 / 255f * channel, 148 / 255f * channel, channel,
                    )
                }
            }
        }
    }

    private fun splatParade(
        red: FloatArray,
        green: FloatArray,
        blue: FloatArray,
        plot: AssistRect,
        points: List<ScopePoint>,
        table: FloatArray,
        mode: ParadeMode,
        intensity: Double,
        width: Int,
        height: Int,
    ) {
        if (points.isEmpty() || intensity <= 0) return
        val gain = intensity.toFloat()
        val lanes =
            buildList {
                if (mode == ParadeMode.YRGB) {
                    add(Triple(222 / 255f, 230 / 255f, 224 / 255f) to { p: ScopePoint -> p.luma })
                }
                add(Triple(1f, 86 / 255f, 78 / 255f) to { p: ScopePoint -> p.red })
                add(Triple(102 / 255f, 232 / 255f, 132 / 255f) to { p: ScopePoint -> p.green })
                add(Triple(92 / 255f, 156 / 255f, 255 / 255f) to { p: ScopePoint -> p.blue })
            }
        for ((index, lane) in lanes.withIndex()) {
            val (cr, cg, cb) = lane.first
            val pick = lane.second
            for (point in points) {
                val x = ParadeAssist.laneX(point.xRatio, index, mode, plot).roundToInt()
                val y = yFor(table, pick(point), plot)
                add(red, green, blue, x, y, width, height, cr * gain, cg * gain, cb * gain)
            }
        }
    }

    private fun stampVector(
        red: FloatArray,
        green: FloatArray,
        blue: FloatArray,
        plot: AssistRect,
        points: List<ScopePoint>,
        gain: Double,
        intensity: Double,
        width: Int,
        height: Int,
    ) {
        val src = VectorscopeRaster.pixels(points, gain, intensity) ?: return
        val n = VECTOR_N
        var p = 0
        for (sy in 0 until n) {
            for (sx in 0 until n) {
                val sr = (src[p].toInt() and 0xFF) / 255f
                val sg = (src[p + 1].toInt() and 0xFF) / 255f
                val sb = (src[p + 2].toInt() and 0xFF) / 255f
                p += 4
                if (sr <= 0f && sg <= 0f && sb <= 0f) continue
                val x = (plot.minX + (sx + 0.5f) / n * plot.width).roundToInt()
                val y = (plot.minY + (sy + 0.5f) / n * plot.height).roundToInt()
                add(red, green, blue, x, y, width, height, sr, sg, sb)
            }
        }
    }

    private fun xFor(xRatio: Double, plot: AssistRect): Int =
        (plot.minX + xRatio.toFloat() * plot.width).roundToInt()

    private fun yFor(table: FloatArray, byte: Int, plot: AssistRect): Int {
        val ire = table[byte.coerceIn(0, table.lastIndex)].toDouble()
        return WaveformAxis.plotY(ire, plot, 1f).roundToInt()
    }

    private fun add(
        red: FloatArray,
        green: FloatArray,
        blue: FloatArray,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        r: Float,
        g: Float,
        b: Float,
    ) {
        if (x !in 0 until width || y !in 0 until height) return
        val i = y * width + x
        red[i] += r
        green[i] += g
        blue[i] += b
    }

    /** Transparent where nothing landed; Compose Plus-blits onto one plate fill. [trail] adds at [decay]. */
    private fun packTraces(
        red: FloatArray,
        green: FloatArray,
        blue: FloatArray,
        out: IntArray = IntArray(red.size),
        trail: Array<FloatArray>? = null,
        decay: Float = 0f,
    ): IntArray? {
        var any = false
        for (i in red.indices) {
            val rr = if (trail == null) red[i] else red[i] + decay * trail[0][i]
            val gg = if (trail == null) green[i] else green[i] + decay * trail[1][i]
            val bb = if (trail == null) blue[i] else blue[i] + decay * trail[2][i]
            out[i] = 0
            if (rr <= 0f && gg <= 0f && bb <= 0f) continue
            val r = (rr.coerceAtMost(1f) * 255f).roundToInt()
            val g = (gg.coerceAtMost(1f) * 255f).roundToInt()
            val b = (bb.coerceAtMost(1f) * 255f).roundToInt()
            val a = maxOf(r, g, b)
            if (a <= 0) continue
            out[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
            any = true
        }
        return if (any) out else null
    }

    private fun IntArray.toImage(width: Int, height: Int): ImageBitmap =
        Bitmap.createBitmap(this, width, height, Bitmap.Config.ARGB_8888).asImageBitmap()
}
