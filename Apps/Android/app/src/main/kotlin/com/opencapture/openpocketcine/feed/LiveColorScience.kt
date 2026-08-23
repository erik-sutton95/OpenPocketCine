package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.session.CameraCommands
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.log2
import kotlin.math.pow
import kotlin.math.round
import kotlin.math.sqrt

/**
 * Pocket live-tap transfer. Matches core `MonitorTransfer` / `ColorMode`.
 *
 * D-Log M (`0x00`) rides the D-Log curve. WAVE 0 / 100 are paper black and the
 * live-tap EI ceiling; 18% grey stays at paper IRE.
 */
enum class MonitorTransfer {
    REC709,
    HDR,
    DLOG,
    DLOG2,
    ;

    val colorMode: Int
        get() =
            when (this) {
                REC709 -> CameraCommands.COLOR_NORMAL
                HDR -> CameraCommands.COLOR_HDR
                DLOG -> CameraCommands.COLOR_DLOG
                DLOG2 -> CameraCommands.COLOR_DLOG2
            }

    val peakLinear: Double
        get() =
            when (this) {
                REC709 -> 1.0
                HDR -> Hlg.decode(1.0)
                DLOG -> DLog.PEAK_LINEAR
                DLOG2 -> DLog2.PEAK_LINEAR
            }

    val middleGrayEncoded: Double
        get() = LiveColorScience.encode(0.18, this)

    val middleGrayPaperIRE: Double
        get() = LiveColorScience.paperIRE(middleGrayEncoded)

    fun scopeAnchors(iso: Int? = null): ScopeAnchors = ScopeAnchors.make(this, iso)

    companion object {
        fun fromColorMode(code: Int): MonitorTransfer =
            when (code) {
                CameraCommands.COLOR_HDR -> HDR
                CameraCommands.COLOR_DLOG, COLOR_DLOG_M -> DLOG
                CameraCommands.COLOR_DLOG2 -> DLOG2
                else -> REC709
            }

        /** Nano D-Log M (`ColorMode.dLogM`). */
        const val COLOR_DLOG_M = 0x00

        fun inferred(minByte: Int, maxByte: Int, fallback: MonitorTransfer): MonitorTransfer {
            if (fallback != REC709) return fallback
            if (minByte in 12..22 && maxByte in 180..252) return DLOG2
            if (minByte in 20..30 && maxByte in 160..240) return DLOG
            return fallback
        }
    }
}

/** Preview clip model. WAVE 100 / traffic clip sit on this ceiling, not code 255. */
object ScopeExposureCeiling {
    const val REFERENCE_EI = 1600
    const val DLOG_REFERENCE_EI = 400
    const val DLOG2_LIVE_TAP_BYTE_AT_1600 = 247
    const val DLOG2_LIVE_TAP_BYTE_AT_1600_HIGH = 248
    const val DLOG_LIVE_TAP_BYTE_AT_NATIVE = 223
    const val DLOG_LIVE_TAP_BYTE_AT_NATIVE_HIGH = 224

    @Volatile private var iso: Int = REFERENCE_EI
    @Volatile private var refined1600: Int = DLOG2_LIVE_TAP_BYTE_AT_1600
    @Volatile private var refinedDlog: Int = DLOG_LIVE_TAP_BYTE_AT_NATIVE
    private val observedByEI = HashMap<Long, Int>()
    private val lock = Any()

    fun setISO(value: Int) {
        if (value in 50..102_400) iso = value
    }

    fun syncISO(value: Int) {
        if (value > 0) setISO(value)
    }

    fun resolvedISO(): Int = iso

    fun reset() {
        synchronized(lock) {
            iso = REFERENCE_EI
            refined1600 = DLOG2_LIVE_TAP_BYTE_AT_1600
            refinedDlog = DLOG_LIVE_TAP_BYTE_AT_NATIVE
            observedByEI.clear()
        }
    }

    fun clipEncoded(transfer: MonitorTransfer, iso: Int? = null): Double =
        clipByte(transfer, iso) / 255.0

    fun clipByte(transfer: MonitorTransfer, iso: Int? = null): Int {
        synchronized(lock) {
            val ei = iso ?: this.iso
            val table = tableByte(transfer, ei, refined1600, refinedDlog)
            val seen = observedByEI[key(transfer, ei)] ?: 0
            return maxOf(table, seen)
        }
    }

    fun observeTapMax(byte: Int, transfer: MonitorTransfer): Pair<Int, Boolean> {
        if (transfer != MonitorTransfer.DLOG && transfer != MonitorTransfer.DLOG2) {
            return clipByte(transfer) to false
        }
        if (byte <= 0 || byte >= 255) return clipByte(transfer) to false
        synchronized(lock) {
            if (transfer == MonitorTransfer.DLOG2 && iso == REFERENCE_EI && byte > refined1600 &&
                byte <= DLOG2_LIVE_TAP_BYTE_AT_1600_HIGH
            ) {
                refined1600 = byte
            }
            if (transfer == MonitorTransfer.DLOG &&
                (iso == 0 || iso >= DLOG_REFERENCE_EI) &&
                byte > refinedDlog &&
                byte <= DLOG_LIVE_TAP_BYTE_AT_NATIVE_HIGH
            ) {
                refinedDlog = byte
            }
            val ei = iso
            val table = tableByte(transfer, ei, refined1600, refinedDlog)
            val previous = observedByEI[key(transfer, ei)] ?: 0
            val raised = minOf(maxOf(previous, byte), minOf(254, table + 2))
            if (raised > table) observedByEI[key(transfer, ei)] = raised
            val clip = maxOf(table, observedByEI[key(transfer, ei)] ?: 0)
            return clip to true
        }
    }

    internal fun tableByte(
        transfer: MonitorTransfer,
        iso: Int,
        refined1600: Int = this.refined1600,
        refinedDlog: Int = this.refinedDlog,
    ): Int {
        return when (transfer) {
            MonitorTransfer.REC709, MonitorTransfer.HDR -> 255
            MonitorTransfer.DLOG2 -> {
                val ei = if (iso > 0) iso else REFERENCE_EI
                val refLinear = LiveColorScience.linearize(refined1600 / 255.0, MonitorTransfer.DLOG2)
                val linear = if (ei >= REFERENCE_EI) refLinear else refLinear * ei / REFERENCE_EI
                val encoded = LiveColorScience.encode(linear, MonitorTransfer.DLOG2)
                minOf(254, maxOf(1, round(encoded * 255).toInt()))
            }
            MonitorTransfer.DLOG -> {
                val ei = if (iso > 0) iso else DLOG_REFERENCE_EI
                val refLinear = LiveColorScience.linearize(refinedDlog / 255.0, MonitorTransfer.DLOG)
                val linear = if (ei >= DLOG_REFERENCE_EI) refLinear else refLinear * ei / DLOG_REFERENCE_EI
                val encoded = LiveColorScience.encode(linear, MonitorTransfer.DLOG)
                minOf(254, maxOf(1, round(encoded * 255).toInt()))
            }
        }
    }

    private fun key(transfer: MonitorTransfer, ei: Int): Long =
        (transfer.ordinal.toLong() shl 32) or (ei.toLong() and 0xFFFFFFFFL)
}

/** Per-transfer anchors on the tap's curve-fraction axis (`byte / 255`). */
data class ScopeAnchors(
    val black: Double,
    val mid: Double,
    val clip: Double,
    val midLevel: Double,
    val clipEdgeByte: Int,
    val clipFloorByte: Int,
    val crushFloorByte: Int,
    val crushEdgeByte: Int,
) {
    companion object {
        fun make(transfer: MonitorTransfer, iso: Int? = null): ScopeAnchors {
            val black = LiveColorScience.encode(0.0, transfer)
            val mid = LiveColorScience.encode(0.18, transfer)
            val clip = ScopeExposureCeiling.clipEncoded(transfer, iso)
            val midLevel =
                ScopeDisplayScale.CRUSH_LEVEL +
                    LiveColorScience.paperIRE(mid) / 100.0 *
                        (ScopeDisplayScale.CLIP_LEVEL - ScopeDisplayScale.CRUSH_LEVEL)
            val clipEdge = ScopeExposureCeiling.clipByte(transfer, iso)
            val span = maxOf(0.0, clip - black) * 255
            val crushFloor = floor(black * 255).toInt()
            val crushEdge = ceil(black * 255 + 0.02 * span).toInt()
            val target95 =
                ScopeDisplayScale.CRUSH_LEVEL +
                    0.95 * (ScopeDisplayScale.CLIP_LEVEL - ScopeDisplayScale.CRUSH_LEVEL)
            val encoded95 =
                if (clip <= mid || mid <= black) {
                    black + 0.95 * (clip - black)
                } else if (target95 <= midLevel) {
                    val t =
                        (target95 - ScopeDisplayScale.CRUSH_LEVEL) /
                            maxOf(midLevel - ScopeDisplayScale.CRUSH_LEVEL, 1e-9)
                    black + t * (mid - black)
                } else {
                    val t =
                        (target95 - midLevel) /
                            maxOf(ScopeDisplayScale.CLIP_LEVEL - midLevel, 1e-9)
                    mid + t * (clip - mid)
                }
            val clipFloor = minOf(clipEdge, maxOf(0, floor(encoded95 * 255).toInt()))
            return ScopeAnchors(
                black = black,
                mid = mid,
                clip = clip,
                midLevel = midLevel,
                clipEdgeByte = clipEdge,
                clipFloorByte = clipFloor,
                crushFloorByte = crushFloor,
                crushEdgeByte = crushEdge,
            )
        }
    }
}

/**
 * HISTO / PARADE / ZEBRA / FALSE / LIGHTS axis. WAVE drawing uses [WaveformIre]
 * (0 / 100 on the plot edges) instead of the leftover 5% shelf.
 */
object ScopeDisplayScale {
    const val CRUSH_LEVEL = 0.05
    const val CLIP_LEVEL = 0.95

    fun waveformLevel(c: Double, transfer: MonitorTransfer, iso: Int? = null): Double {
        val a = ScopeAnchors.make(transfer, iso)
        val v = minOf(1.0, maxOf(0.0, c))
        if (v < a.black) {
            return if (a.black <= 0) CRUSH_LEVEL else v / a.black * CRUSH_LEVEL
        }
        if (a.clip <= a.mid || a.mid <= a.black) {
            if (v <= a.clip) {
                return CRUSH_LEVEL +
                    (v - a.black) / maxOf(a.clip - a.black, 1e-9) * (CLIP_LEVEL - CRUSH_LEVEL)
            }
            return overshoot(v, a.clip)
        }
        if (v <= a.mid) {
            return CRUSH_LEVEL + (v - a.black) / (a.mid - a.black) * (a.midLevel - CRUSH_LEVEL)
        }
        if (v <= a.clip) {
            return a.midLevel + (v - a.mid) / (a.clip - a.mid) * (CLIP_LEVEL - a.midLevel)
        }
        return overshoot(v, a.clip)
    }

    fun level(scaleIRE: Double): Double = CRUSH_LEVEL + scaleIRE / 100.0 * (CLIP_LEVEL - CRUSH_LEVEL)

    fun monitorPercent(c: Double, transfer: MonitorTransfer, iso: Int? = null): Double {
        val level = waveformLevel(c, transfer, iso)
        return minOf(100.0, maxOf(0.0, (level - CRUSH_LEVEL) / (CLIP_LEVEL - CRUSH_LEVEL) * 100))
    }

    /** Normalized tap code whose [monitorPercent] equals `percent`. iOS `ScopeDisplayScale.signalNative`. */
    fun signalNative(monitorPercent: Double, transfer: MonitorTransfer, iso: Int? = null): Double {
        val a = ScopeAnchors.make(transfer, iso)
        val p = minOf(100.0, maxOf(0.0, monitorPercent))
        if (p <= 0.0) return a.black
        if (p >= 100.0) return a.clip
        val target = CRUSH_LEVEL + p / 100.0 * (CLIP_LEVEL - CRUSH_LEVEL)
        if (a.clip <= a.mid || a.mid <= a.black) {
            return a.black + p / 100.0 * (a.clip - a.black)
        }
        if (target <= a.midLevel) {
            val t = (target - CRUSH_LEVEL) / maxOf(a.midLevel - CRUSH_LEVEL, 1e-9)
            return a.black + t * (a.mid - a.black)
        }
        val t = (target - a.midLevel) / maxOf(CLIP_LEVEL - a.midLevel, 1e-9)
        return a.mid + t * (a.clip - a.mid)
    }

    fun remapHistogram(bins: IntArray, transfer: MonitorTransfer, iso: Int? = null): IntArray {
        val out = IntArray(256)
        val table = levelTable(transfer, iso)
        val limit = minOf(bins.size, 256)
        for (code in 0 until limit) {
            val count = bins[code]
            if (count == 0) continue
            val bucket = round(table[code] * 255.0).toInt().coerceIn(0, 255)
            out[bucket] += count
        }
        return out
    }

    fun levelTable(transfer: MonitorTransfer, iso: Int? = null): FloatArray {
        val ei = iso ?: ScopeExposureCeiling.resolvedISO()
        val clip = ScopeExposureCeiling.clipByte(transfer, ei)
        val key = transfer.ordinal.toLong() shl 32 or clip.toLong()
        return tables.getOrPut(key) {
            FloatArray(256) { waveformLevel(it / 255.0, transfer, ei).toFloat() }
        }
    }

    private fun overshoot(v: Double, clip: Double): Double {
        val headroom = 1.0 - clip
        if (headroom <= 0) return CLIP_LEVEL
        return CLIP_LEVEL + (v - clip) / headroom * (1.0 - CLIP_LEVEL)
    }

    private val tables = ConcurrentHashMap<Long, FloatArray>()
}

/**
 * WAVE plot IRE: 0 = paper black, 100 = live-tap clip, 18% grey = paper IRE.
 * Native-code histogram remap lands paper black on bucket 0 and clip on 255.
 */
object WaveformIre {
    fun ire(encoded: Double, transfer: MonitorTransfer, iso: Int? = null): Double {
        val a = ScopeAnchors.make(transfer, iso)
        val blackByte = round(a.black * 255)
        if (!encoded.isFinite() || encoded * 255 <= blackByte) return 0.0
        if (encoded >= a.clip) return 100.0
        val midIRE = LiveColorScience.paperIRE(a.mid)
        if (a.mid <= a.black || a.clip <= a.mid) {
            return (encoded - a.black) / maxOf(a.clip - a.black, 1e-9) * 100
        }
        if (encoded <= a.mid) {
            return (encoded - a.black) / (a.mid - a.black) * midIRE
        }
        return midIRE + (encoded - a.mid) / (a.clip - a.mid) * (100 - midIRE)
    }

    fun remapHistogram(bins: IntArray, transfer: MonitorTransfer, iso: Int? = null): IntArray {
        val out = IntArray(256)
        val table = levelTable(transfer, iso)
        val limit = minOf(bins.size, 256)
        for (code in 0 until limit) {
            val count = bins[code]
            if (count == 0) continue
            val bucket = round(table[code] / 100.0 * 255).toInt().coerceIn(0, 255)
            out[bucket] += count
        }
        return out
    }

    fun levelTable(transfer: MonitorTransfer, iso: Int? = null): FloatArray {
        val ei = iso ?: ScopeExposureCeiling.resolvedISO()
        return FloatArray(256) { ire(it / 255.0, transfer, ei).toFloat() }
    }

    fun middleGrayIRE(transfer: MonitorTransfer): Double = transfer.middleGrayPaperIRE
}

data class ScopeChannelLight(
    val clip: Boolean,
    val crush: Boolean,
    val level: Double,
) {
    val isNeutral: Boolean
        get() = abs(level - 0.5) <= 0.03
}

data class ScopeTrafficLightsReading(
    val red: ScopeChannelLight,
    val green: ScopeChannelLight,
    val blue: ScopeChannelLight,
) {
    val anyClip: Boolean
        get() = red.clip || green.clip || blue.clip
    val anyCrush: Boolean
        get() = red.crush || green.crush || blue.crush

    companion object {
        val NONE =
            ScopeTrafficLightsReading(
                ScopeChannelLight(clip = false, crush = false, level = 0.5),
                ScopeChannelLight(clip = false, crush = false, level = 0.5),
                ScopeChannelLight(clip = false, crush = false, level = 0.5),
            )
    }
}

object ScopeTrafficLights {
    const val DEFAULT_THRESHOLD = 0.0
    const val HOLD_RATIO = 0.5

    fun reading(
        red: IntArray,
        green: IntArray,
        blue: IntArray,
        transfer: MonitorTransfer,
        threshold: Double = DEFAULT_THRESHOLD,
        previous: ScopeTrafficLightsReading? = null,
        luma: IntArray? = null,
    ): ScopeTrafficLightsReading {
        val a = transfer.scopeAnchors()
        val redClip = edgeEnergy(red, a.clipFloorByte, 255)
        val greenClip = edgeEnergy(green, a.clipFloorByte, 255)
        val blueClip = edgeEnergy(blue, a.clipFloorByte, 255)
        val lumaClip = luma?.let { edgeEnergy(it, a.clipFloorByte, 255) } ?: 0.0
        val pictureClip =
            lumaClip > threshold || redClip > threshold || greenClip > threshold || blueClip > threshold
        val pictureEnergy = maxOf(lumaClip, redClip, greenClip, blueClip)
        return ScopeTrafficLightsReading(
            channel(red, transfer, threshold, redClip, pictureEnergy, pictureClip, previous?.red),
            channel(green, transfer, threshold, greenClip, pictureEnergy, pictureClip, previous?.green),
            channel(blue, transfer, threshold, blueClip, pictureEnergy, pictureClip, previous?.blue),
        )
    }

    private fun channel(
        bins: IntArray,
        transfer: MonitorTransfer,
        threshold: Double,
        ownClipEnergy: Double,
        pictureEnergy: Double,
        pictureClip: Boolean,
        previous: ScopeChannelLight?,
    ): ScopeChannelLight {
        val a = transfer.scopeAnchors()
        if (bins.size < 256) return ScopeChannelLight(false, false, 0.5)
        var total = 0
        for (count in bins) total += count
        if (total <= 0) return ScopeChannelLight(false, false, 0.5)
        var crushed = 0
        for (code in a.crushFloorByte..a.crushEdgeByte) {
            if (code in 0..255) crushed += bins[code]
        }
        val crushEnergy = crushed.toDouble() / total
        var seen = 0
        var median = 0
        val half = (total + 1) / 2
        for (code in 0 until 256) {
            seen += bins[code]
            if (seen >= half) {
                median = code
                break
            }
        }
        val rawClip = ownClipEnergy > threshold || pictureClip
        val clip =
            latched(rawClip, previous?.clip == true, maxOf(ownClipEnergy, pictureEnergy), threshold)
        val crush = latched(crushEnergy > threshold, previous?.crush == true, crushEnergy, threshold)
        val level =
            balance(
                ScopeDisplayScale.waveformLevel(median / 255.0, transfer),
                a.midLevel,
            )
        return ScopeChannelLight(clip, crush, level)
    }

    fun edgeEnergy(bins: IntArray, from: Int, to: Int): Double {
        if (bins.size < 256 || from > to || from < 0 || to > 255) return 0.0
        var total = 0
        var band = 0
        for (code in 0 until 256) {
            total += bins[code]
            if (code in from..to) band += bins[code]
        }
        if (total <= 0) return 0.0
        return band.toDouble() / total
    }

    fun latched(now: Boolean, was: Boolean, energy: Double, threshold: Double): Boolean {
        if (now) return true
        if (!was) return false
        return energy > threshold * HOLD_RATIO
    }

    fun balance(level: Double, midLevel: Double): Double {
        if (level <= midLevel) {
            if (midLevel <= 0) return 0.5
            return 0.5 * level / midLevel
        }
        val span = 1.0 - midLevel
        if (span <= 0) return 0.5
        return 0.5 + 0.5 * (level - midLevel) / span
    }
}

object LiveColorScience {
    fun linearize(encoded: Double, transfer: MonitorTransfer): Double {
        val linear = decode(clamp01(encoded), transfer)
        if (!linear.isFinite()) return 0.0
        return maxOf(0.0, linear)
    }

    fun encode(linear: Double, transfer: MonitorTransfer): Double {
        val encoded = encodeRaw(maxOf(0.0, linear), transfer)
        if (!encoded.isFinite()) return 0.0
        return clamp01(encoded)
    }

    fun paperIRE(encoded: Double): Double = encoded * 100

    /** Stops relative to 18% grey. Zero light is −∞, never NaN. */
    fun stops(linear: Double): Double {
        val y = maxOf(0.0, linear)
        if (y <= 0.0 || !y.isFinite()) return Double.NEGATIVE_INFINITY
        return log2(y / 0.18)
    }

    fun stops(encoded: Double, transfer: MonitorTransfer): Double = stops(linearize(encoded, transfer))

    fun lumaWeights(transfer: MonitorTransfer): Triple<Double, Double, Double> =
        when (transfer) {
            MonitorTransfer.REC709, MonitorTransfer.DLOG -> Triple(0.2126, 0.7152, 0.0722)
            MonitorTransfer.HDR, MonitorTransfer.DLOG2 -> Triple(0.2627, 0.6780, 0.0593)
        }

    fun monitorIRE(encoded: Double, transfer: MonitorTransfer, iso: Int? = null): Double {
        val ire = ScopeDisplayScale.monitorPercent(encoded, transfer, iso)
        if (!ire.isFinite()) return 0.0
        return ire.coerceIn(0.0, 100.0)
    }

    private fun decode(encoded: Double, transfer: MonitorTransfer): Double =
        when (transfer) {
            MonitorTransfer.REC709 -> Rec709.decode(encoded)
            MonitorTransfer.HDR -> Hlg.decode(encoded)
            MonitorTransfer.DLOG -> DLog.decode(encoded)
            MonitorTransfer.DLOG2 -> DLog2.decode(encoded)
        }

    private fun encodeRaw(linear: Double, transfer: MonitorTransfer): Double =
        when (transfer) {
            MonitorTransfer.REC709 -> Rec709.encode(linear)
            MonitorTransfer.HDR -> Hlg.encode(linear)
            MonitorTransfer.DLOG -> DLog.encode(linear)
            MonitorTransfer.DLOG2 -> DLog2.encode(linear)
        }

    private fun clamp01(x: Double): Double = x.coerceIn(0.0, 1.0)
}

private object Rec709 {
    fun decode(encoded: Double): Double {
        val e = encoded
        return if (e < 0.081) e / 4.5 else ((e + 0.099) / 1.099).pow(1 / 0.45)
    }

    fun encode(linear: Double): Double {
        val l = minOf(1.0, linear)
        return if (l < 0.018) 4.5 * l else 1.099 * l.pow(0.45) - 0.099
    }
}

internal object Hlg {
    private const val A = 0.178_832_77
    private const val B = 0.284_668_92
    private const val C = 0.559_910_73
    private val diffuseWhite = inverseOETF(0.75)

    fun decode(encoded: Double): Double = inverseOETF(encoded.coerceIn(0.0, 1.0)) / diffuseWhite

    fun encode(linear: Double): Double = oetf((linear * diffuseWhite).coerceIn(0.0, 1.0))

    private fun oetf(scene: Double): Double =
        if (scene <= 1.0 / 12.0) sqrt(3 * scene) else A * ln(12 * scene - B) + C

    private fun inverseOETF(e: Double): Double =
        if (e <= 0.5) e * e / 3 else (exp((e - C) / A) + B) / 12
}

internal object DLog {
    const val PEAK_LINEAR = 42.0

    fun decode(encoded: Double): Double =
        if (encoded <= 0.14) {
            (encoded - 0.0929) / 6.025
        } else {
            (10.0.pow(3.89616 * encoded - 2.27752) - 0.0108) / 0.9892
        }

    fun encode(linear: Double): Double =
        if (linear <= 0.0078) {
            6.025 * linear + 0.0929
        } else {
            log10(linear * 0.9892 + 0.0108) * 0.256663 + 0.584555
        }
}

internal object DLog2 {
    const val PEAK_LINEAR = 475.0
    private const val A = 16.285_770_761_945_304
    private const val K1 = 0.059_439_938_321_493
    private const val B1 = 0.304_985_337_243_402
    private const val K2 = 2.960_935_245_492_250
    private const val B2 = 0.148_314_799_066_323
    private const val IN_LIMIT_1 = 0.18
    private const val IN_LIMIT_2 = 0.028_961_695_254_132

    fun decode(encoded: Double): Double =
        if (encoded >= B1) {
            (PEAK_LINEAR / (2.0.pow(A) - 1)) * (2.0.pow(A * encoded) - 1)
        } else if (encoded >= B2) {
            2.0.pow((encoded - B1) / K1 + log2(IN_LIMIT_1))
        } else {
            (encoded - B2) / K2 + IN_LIMIT_2
        }

    fun encode(linear: Double): Double =
        if (linear >= IN_LIMIT_1) {
            (1 / A) * log2(linear * (2.0.pow(A) - 1) / PEAK_LINEAR + 1)
        } else if (linear >= IN_LIMIT_2) {
            K1 * (log2(maxOf(linear, 1e-15)) - log2(IN_LIMIT_1)) + B1
        } else {
            K2 * (linear - IN_LIMIT_2) + B2
        }
}
