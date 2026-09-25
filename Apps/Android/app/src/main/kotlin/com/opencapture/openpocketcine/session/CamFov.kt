package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.round
import kotlin.math.roundToInt
import java.util.Locale

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
    /** Camera can pause HEVC while the lens slews. Same 4 s as AF-C. */
    const val VIDEO_GRACE_SEC = 4.0

    /**
     * How long to wait for a Med-Tele swap to show up in the reported floor before telling
     * the operator it did not happen.
     *
     * Measured under 1 s in both directions over many runs; this is that with room, not a
     * guess. It has to exist at all because the refusals are silent — no movement and no
     * NACK — so without a deadline a swap the body ignored would look like a slow one.
     */
    const val MED_TELE_SWAP_TIMEOUT_MS = 2_000L

    fun shouldHoldWatchdog(secondsSinceSet: Double?, pinchActive: Boolean = false): Boolean {
        if (pinchActive) return true
        val s = secondsSinceSet ?: return false
        return s >= 0.0 && s < VIDEO_GRACE_SEC
    }

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

    /** `cam_lens_state` u16-LE `@10` — the widest lens the body will accept right now. */
    fun lensMinAt10(value: ByteArray): Int? = lensLimit(value, 10)

    /** `cam_lens_state` u16-LE `@12` — the longest lens the body will accept right now. */
    fun lensMaxAt12(value: ByteArray): Int? = lensLimit(value, 12)

    private fun lensLimit(value: ByteArray, at: Int): Int? {
        if (value.size < at + 2) return null
        val lens = (value[at].toInt() and 0xFF) or ((value[at + 1].toInt() and 0xFF) shl 8)
        return lens.takeIf { it in 100..3_000 }
    }

    /**
     * Med-Tele (Pocket 3, 2× / 40 mm) is on when the body lifts its own wide limit off
     * [LENS_1X]. Measured on a Pocket 3: the floor is `217` normally and `434` under
     * Med-Tele, in every FORMAT. Only the floor is tested — with Med-Tele off the tele
     * limit is the FORMAT's own digital ceiling (868 at 1080P, 651 at 2.7K, 434 at 4K),
     * so it says nothing about which lens is in front of the sensor.
     *
     * The camera announces the mode nowhere — no `camcap_*` key carries it and `0x02/0x80`
     * `@57` never moves — so the raised floor is the only honest signal. It is also the one
     * that matters: the body clamps an ask to these limits instead of refusing it, so asking
     * below the floor silently parks the lens on the floor.
     */
    fun isMedTele(lensMin: Int): Boolean = lensMin > LENS_1X

    /**
     * The chip cycle while Med-Tele holds the floor up: whole factors from the body's own
     * floor to its own ceiling, which is 2×…4× on a Pocket 3.
     *
     * 1× is deliberately absent, because a *zoom* cannot reach it: the camera clamps a
     * wider ask back to the floor, so the tap would go nowhere. Getting back to 1× is the
     * MT button's job — taking the lens off — not a stop. Null when Med-Tele is off or the
     * body has not reported its limits yet, and the caller keeps the per-FORMAT table.
     */
    fun medTeleStops(lensMin: Int, lensMax: Int): List<Double>? {
        if (!isMedTele(lensMin)) return null
        val low = factorFromLens(lensMin) ?: return null
        val high = factorFromLens(lensMax) ?: return null
        val first = ceil(low - 0.05).toInt()
        val last = floor(high + 0.05).toInt()
        if (last < first) return listOf(displayTenths(low))
        return (first..last).map { it.toDouble() }
    }

    /**
     * Whether the MT button may take the Pocket 3's Med-Tele lens on or off right now.
     *
     * These are the states where the swap was measured not to work, each a *silent*
     * refusal — the body neither moves nor NACKs — so the button is dimmed there instead
     * of spending a tap on nothing:
     * - colour must be Normal; in D-Log M the SET was ignored for 4 s. (On a Pocket 3
     *   `parseColorMode` only ever yields Normal or D-Log M for the 8/10-bit pair, so
     *   this one constant covers both.)
     * - not while recording; mid-take the SET was ignored for 4 s with the link healthy,
     *   and the identical command landed in under 1 s once REC stopped.
     * - video only. SlowMo / TimeLapse / SuperNight were never probed, and an unmeasured
     *   yes is how the inert 1× got shipped the first time. Lifting this needs one run,
     *   not an argument.
     *
     * ActiveTrack is deliberately *not* here. The swap works with a track running — it is
     * the subject that does not survive it — so the caller clears tracking itself rather
     * than dimming a button the body would honour.
     */
    fun medTeleToggleable(colorMode: Int, isRecording: Boolean, shootingMode: Int): Boolean =
        colorMode == CameraCommands.COLOR_NORMAL &&
            !isRecording &&
            shootingMode == CameraCommands.SHOOT_VIDEO

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

    /**
     * The remembered chip stop, kept inside what the current FORMAT allows.
     *
     * A FORMAT change can drop the ceiling under a stop the operator already picked — 2.7K offers
     * 3×, 4K stops at 2×. The stop is only the readout's last resort, before any `cam_fov` lands,
     * but even then it must not advertise a factor this FORMAT would refuse. Med-Tele does the
     * same from below, so the floor holds too.
     */
    fun stopWithinCycle(stop: Double, stops: List<Double>): Double =
        clamp(stop, stops.lastOrNull() ?: MIN_FACTOR)
            .coerceAtLeast(stops.firstOrNull() ?: MIN_FACTOR)

    /**
     * The line to show when a new FORMAT pulls the zoom ceiling out from under the factor the
     * operator is already holding.
     *
     * The body does not refuse: it walks the lens back to whatever the new capture size allows, so
     * without a word the chip just falls to 1x and nothing on screen says why. [size] is
     * [VideoResolution.sizeTitle]. Null while the held factor still fits, which is the usual case.
     */
    fun ceilingNote(size: String, held: Double, stops: List<Double>): String? {
        val ceiling = stops.lastOrNull() ?: return null
        if (displayTenths(held) <= ceiling + 0.05) return null
        return "$size caps zoom at ${displayLabel(ceiling)}"
    }

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
        return String.format(Locale.US, "%.1f×", shown)
    }

    fun nextJump(from: Double, stops: List<Double> = JUMPS): Double {
        val cycle = if (stops.isEmpty()) JUMPS else stops
        for (stop in cycle) {
            if (from < stop - 0.05) return stop
        }
        return cycle[0]
    }

    /** Next lower chip stop. Stays on the wide end — does not wrap to tele. */
    fun previousJump(from: Double, stops: List<Double> = JUMPS): Double {
        val cycle = if (stops.isEmpty()) JUMPS else stops
        for (stop in cycle.asReversed()) {
            if (from > stop + 0.05) return stop
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

    /**
     * [min] is the body's own wide limit, above [MIN_FACTOR] only while a second lens holds
     * the floor up (Med-Tele). Spreading past it would otherwise preview a factor the camera
     * clamps straight back, so the pinch stops where the optics do.
     */
    fun pinchFactor(
        anchor: Double,
        magnification: Double,
        max: Double = MAX_FACTOR,
        min: Double = MIN_FACTOR,
    ): Double = clamp(anchor * magnification, max).coerceAtLeast(clamp(min, max))

    /** Right trigger minus left trigger onto −1…1 (positive = zoom in). */
    fun triggerZoomAxis(left: Double, right: Double): Double {
        val l = left.coerceIn(0.0, 1.0)
        val r = right.coerceIn(0.0, 1.0)
        return r - l
    }

    /** Full R2/L2: this many operator × per second. Light press crawls. */
    const val ZOOM_RATE_PER_SECOND = 3.0
    const val ZOOM_STEP_INTERVAL_MS = 50L

    /**
     * Hold-to-zoom: `y` is R2−L2 (−1…1). Integrate `dt` seconds of analog rate, between the
     * body's own limits — see [pinchFactor] for why [min] is not always 1×.
     */
    fun zoomStep(
        current: Double,
        y: Double,
        dt: Double,
        max: Double = MAX_FACTOR,
        min: Double = MIN_FACTOR,
    ): Double {
        val floor = clamp(min, max)
        if (dt <= 0.0) return clamp(current, max).coerceAtLeast(floor)
        val t = CameraCommands.gimbalLinearThrow(y.toFloat()).toDouble()
        return clamp(current + t * ZOOM_RATE_PER_SECOND * dt, max).coerceAtLeast(floor)
    }

    fun pinchPreview(anchor: Double, magnification: Double): Double =
        displayTenths(pinchFactor(anchor, magnification))

    fun pinchLens(factor: Double): Int = lensPosition(factor)

    fun readout(
        live: Double?,
        preview: Double?,
        fallback: Double,
        optimistic: Double? = null,
    ): Double = displayTenths(continuousReadout(live, preview, fallback, optimistic))

    /** Unrounded lens factor for the zoom disc. The chip still uses [readout]. */
    fun continuousReadout(
        live: Double?,
        preview: Double?,
        fallback: Double,
        optimistic: Double? = null,
    ): Double {
        if (preview != null) return clamp(preview)
        if (optimistic != null) return clamp(optimistic)
        if (live != null) return clamp(live)
        return clamp(fallback)
    }

    fun hybridFactor(raw: Int, lens: Int?): Double? {
        if (lens != null) factorFromLens(lens)?.let { return it }
        return if (raw == 0) null else factor(raw)
    }

    /**
     * Confirmation test for the chip pin ([CameraValuePin]): the live factor comes back off a lens
     * position and lands a hair off what was asked, so exact equality would never release the pin.
     */
    fun matches(live: Double, target: Double): Boolean =
        abs(displayTenths(live) - displayTenths(target)) < 0.15

    fun usesTelephoto(factor: Double): Boolean = displayTenths(factor) >= TELE_ENGAGE

    /**
     * D-Log2 rejects every zoom SET. Hop on the first step off 1×.
     * `current` is unpinned live color, not an optimistic HUD pin.
     */
    fun colorModeForZoom(factor: Double, current: Int): Int? {
        if (current != CameraCommands.COLOR_DLOG2) return null
        return if (factor > MIN_FACTOR) CameraCommands.COLOR_DLOG else null
    }

    /** Hold 0xB8 until D-Log2→D-Log is on the body, not only until the color ACK. */
    fun holdZoomWrite(factor: Double, current: Int, hopPending: Boolean): Boolean {
        if (hopPending) return true
        return colorModeForZoom(factor, current) != null
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
