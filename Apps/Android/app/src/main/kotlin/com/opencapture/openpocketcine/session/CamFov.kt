package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.math.round
import kotlin.math.roundToInt

/**
 * iOS `CamFov`. Operator 1×…12× from `cam_fov` `@0` + lens `@14`.
 *
 * `cam_fov / 1024` runs backwards and jumps at the 3× hop — never show that
 * as the chip number. Writes are slider `0A 4E` + lens (217 / 651 / 1302 / 2604).
 */
object CamFov {
    const val MIN_FACTOR = 1.0
    const val MAX_FACTOR = 12.0
    val JUMPS: List<Double> = listOf(1.0, 3.0, 6.0, 12.0)

    const val RAW_AT_1X = 12_287
    const val RAW_AT_3X = 9_368
    const val RAW_AT_12X = 2_341

    const val LENS_1X = 217
    const val LENS_3X = 651
    const val LENS_6X = 1_302
    const val LENS_12X = 2_604

    const val SLEW_TELE = 100
    const val SLEW_WIDE = 300
    const val TELE_ENGAGE = 3.0
    /** iOS `CameraSetMailbox.zoomCoalesceHold` — Mimo pinch is 20 Hz. */
    const val SLIDER_COALESCE_MS = 50L

    fun rawAt0(value: ByteArray): Int? {
        if (value.size < 4) return null
        return (value[0].toInt() and 0xFF) or
            ((value[1].toInt() and 0xFF) shl 8) or
            ((value[2].toInt() and 0xFF) shl 16) or
            ((value[3].toInt() and 0xFF) shl 24)
    }

    fun lensAt14(value: ByteArray): Int? {
        if (value.size < 16) return null
        val lens = (value[14].toInt() and 0xFF) or ((value[15].toInt() and 0xFF) shl 8)
        return lens.takeIf { it in 100..3_000 }
    }

    fun factor(raw: Int): Double {
        if (raw == 0) return MIN_FACTOR
        if (raw >= RAW_AT_1X) return MIN_FACTOR
        if (raw <= RAW_AT_12X) return MAX_FACTOR
        if (raw >= RAW_AT_3X) {
            val t = (RAW_AT_1X - raw).toDouble() / (RAW_AT_1X - RAW_AT_3X).toDouble()
            return clamp(MIN_FACTOR + t * 2)
        }
        val t = (RAW_AT_3X - raw).toDouble() / (RAW_AT_3X - RAW_AT_12X).toDouble()
        return clamp(3 + t * 9)
    }

    fun factorFromValue(value: ByteArray): Double? = rawAt0(value)?.let { factor(it) }

    fun factorFromLens(lens: Int): Double? {
        if (lens <= 0) return null
        if (lens <= LENS_1X) return MIN_FACTOR
        if (lens >= LENS_12X) return MAX_FACTOR
        if (lens <= LENS_3X) {
            val t = (lens - LENS_1X).toDouble() / (LENS_3X - LENS_1X).toDouble()
            return clamp(MIN_FACTOR + t * 2)
        }
        val t = (lens - LENS_3X).toDouble() / (LENS_12X - LENS_3X).toDouble()
        return clamp(3 + t * 9)
    }

    fun clamp(factor: Double, max: Double = MAX_FACTOR): Double =
        factor.coerceIn(MIN_FACTOR, max)

    fun lensPosition(factor: Double): Int {
        val f = clamp(factor)
        if (abs(f - MIN_FACTOR) < 0.001) return LENS_1X
        if (abs(f - MAX_FACTOR) < 0.001) return LENS_12X
        if (f <= 3) return lerpLens(LENS_1X, LENS_3X, (f - MIN_FACTOR) / 2)
        return lerpLens(LENS_3X, LENS_12X, (f - 3) / 9)
    }

    fun displayLabel(raw: Int): String = displayLabel(factor(raw))

    fun displayLabel(factor: Double): String {
        val shown = displayTenths(factor)
        if (abs(shown - MAX_FACTOR) < 0.05) return "12×"
        val nearest = shown.roundToInt()
        if (abs(shown - nearest) < 0.05 && nearest in 1..12) return "${nearest}×"
        return String.format("%.1f×", shown)
    }

    fun nextJump(from: Double, stops: List<Double> = JUMPS): Double {
        val cycle = if (stops.isEmpty()) JUMPS else stops
        for (stop in cycle) {
            if (from < stop - 0.05) return stop
        }
        return cycle[0]
    }

    fun isJumpStop(factor: Double, stops: List<Double> = JUMPS): Boolean {
        val shown = displayTenths(factor)
        val cycle = if (stops.isEmpty()) JUMPS else stops
        return cycle.any { abs(shown - it) < 0.05 }
    }

    sealed class ChipWrite {
        data class Lens(val position: Int) : ChipWrite()
        data class Slew(val value: Int) : ChipWrite()
    }

    fun chipWrite(forJump: Double): ChipWrite? =
        when {
            abs(forJump - 1) < 0.1 -> ChipWrite.Lens(LENS_1X)
            abs(forJump - 2) < 0.1 -> ChipWrite.Lens(lensPosition(2.0))
            abs(forJump - 3) < 0.1 -> ChipWrite.Lens(LENS_3X)
            abs(forJump - 4) < 0.1 -> ChipWrite.Lens(lensPosition(4.0))
            abs(forJump - 6) < 0.1 -> ChipWrite.Lens(LENS_6X)
            abs(forJump - MAX_FACTOR) < 0.1 -> ChipWrite.Lens(LENS_12X)
            else -> null
        }

    fun displayTenths(factor: Double): Double = round(clamp(factor) * 10.0) / 10.0

    fun pinchFactor(anchor: Double, magnification: Double, max: Double = MAX_FACTOR): Double =
        clamp(anchor * magnification, max)

    fun pinchPreview(anchor: Double, magnification: Double): Double =
        displayTenths(pinchFactor(anchor, magnification))

    fun pinchLens(factor: Double): Int = lensPosition(factor)

    fun readout(
        live: Double?,
        preview: Double?,
        fallback: Double,
        optimistic: Double? = null,
    ): Double {
        if (preview != null) return displayTenths(preview)
        if (optimistic != null) return displayTenths(optimistic)
        if (live != null) return displayTenths(live)
        return displayTenths(fallback)
    }

    fun hybridFactor(raw: Int, lens: Int?): Double? {
        if (lens != null) factorFromLens(lens)?.let { return it }
        return if (raw == 0) null else factor(raw)
    }

    fun matches(live: Double, target: Double): Boolean =
        abs(displayTenths(live) - displayTenths(target)) < 0.15

    fun usesTelephoto(factor: Double): Boolean = displayTenths(factor) >= TELE_ENGAGE

    fun colorModeForZoom(factor: Double, current: Int): Int? {
        if (current != CameraCommands.COLOR_DLOG2) return null
        return if (displayTenths(factor) > 1.05) CameraCommands.COLOR_DLOG else null
    }

    /** Body will not change color while rolling, so D-Log2 cannot leave 1×. */
    fun zoomNeedsColorHopWhileRecording(
        factor: Double,
        current: Int,
        isRecording: Boolean,
    ): Boolean = isRecording && colorModeForZoom(factor, current) != null

    fun shouldRestoreDLog2(factor: Double): Boolean = displayTenths(factor) <= 1.05

    fun absorb(status: CameraStatus): CameraStatus {
        val factor = hybridFactor(status.zoomFactorRaw, status.zoomLens.takeIf { it >= 0 })
        return if (factor == status.zoomFactor) status else status.copy(zoomFactor = factor)
    }

    private fun lerpLens(a: Int, b: Int, t: Double): Int {
        val u = t.coerceIn(0.0, 1.0)
        return (a + u * (b - a)).roundToInt()
    }
}
