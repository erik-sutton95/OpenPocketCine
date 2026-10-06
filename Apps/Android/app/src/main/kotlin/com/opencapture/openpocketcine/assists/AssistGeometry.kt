package com.opencapture.openpocketcine.assists

import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.fromColorMode

import com.opencapture.openpocketcine.feed.LiveColorScience
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.ScopeDisplayScale
import com.opencapture.openpocketcine.feed.ScopeExposureCeiling
import com.opencapture.openpocketcine.feed.WaveformIre
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.round
import kotlin.math.roundToInt
import kotlin.math.sin

typealias AssistPoint = com.opencapture.monitorui.MonitorScopePoint
typealias AssistSize = com.opencapture.monitorui.MonitorScopeSize
typealias AssistRect = com.opencapture.monitorui.MonitorScopeRect
typealias StoredCenter = com.opencapture.monitorui.MonitorScopeStoredCenter
typealias ScopeGuides = com.opencapture.monitorui.MonitorScopeGuides
typealias ScopePanelSize = com.opencapture.monitorui.MonitorScopePanelSize

typealias CrosshairAssist = com.opencapture.monitorui.MonitorCrosshairGeometry

object MirrorAssist {
    const val EXPLANATION =
        "Flips the monitor for a camera pointed back at you or mounted upside down. " +
            "The recording and the scopes are never mirrored."
    const val HORIZONTAL_HELP = "Left-to-right, for a camera pointed back at you."
    const val VERTICAL_HELP = "Top-to-bottom, for an underslung mount. Both on turns it 180°."

    fun feedScaleX(mirrored: Boolean, squeeze: Float = 1f): Float = if (mirrored) -squeeze else squeeze
}

object AudioAssist {
    const val PANEL_WIDTH_DP = 28f
    const val PANEL_HEIGHT_DP = 168f
    const val HELP = "Meters the camera's audio. Available while live view is up."
    const val FLOOR_DB = -60.0
    const val YELLOW_FROM_DB = -18.0
    const val RED_FROM_DB = -6.0
    val guideMarks = doubleArrayOf(0.0, -6.0, -18.0, -36.0)

    /** Fresh meter: left of the movement well, vertically centered on the canvas. */
    fun defaultCenter(canvas: AssistRect, movement: AssistRect, size: AssistSize): AssistPoint {
        val fallback = AssistPoint(movement.minX + size.width / 2f, canvas.midY)
        return MovablePanelMath.clamp(fallback, size, movement)
    }
}

/**
 * WAVE plot: 0 = paper black, 100 = live-tap EI ceiling, 18% gray at paper IRE.
 * Without a BGRA tap the IRE numbers still place the empty graticule.
 */
object WaveformAxis {
    const val PLOT_INSET = 1f
    const val TITLE_HEIGHT = 26f
    const val BOTTOM_PAD = 2f
    const val SIDE_PAD = 6f
    const val BUFFER_IRE = 5.0
    val crushClipDash = floatArrayOf(3f, 3f)

    /**
     * [width] / [height] are in the same unit as the constants (iOS points /
     * Android dp). Pass [density] (px per dp) when the size is already pixels,
     * so gutters stay 6/26 dp on xxhdpi instead of 6/26 px.
     */
    fun plotRect(width: Float, height: Float, density: Float = 1f): AssistRect {
        val side = SIDE_PAD * density
        val title = TITLE_HEIGHT * density
        val bottom = BOTTOM_PAD * density
        return AssistRect(
            side,
            title,
            width - side * 2f,
            maxOf(1f, height - title - bottom),
        )
    }

    fun plotY(ire: Double, rect: AssistRect, density: Float = 1f): Float {
        val inset = PLOT_INSET * density
        val span = rect.height - 2f * inset
        return rect.maxY - inset - (ire / 100.0).toFloat() * span
    }

    fun plotX(ire: Double, rect: AssistRect, density: Float = 1f): Float {
        val inset = PLOT_INSET * density
        val span = rect.width - 2f * inset
        return rect.minX + inset + (ire / 100.0).toFloat() * span
    }

    /** Paper IRE of 18% grey. Rec.709 ≈ 40.9, D-Log 39.88, D-Log2 30.50, HLG ≈ 37.8. */
    fun middleGrayIRE(colorMode: Int): Double =
        WaveformIre.middleGrayIRE(MonitorTransfer.fromColorMode(colorMode))

    data class GuideStroke(val ire: Double, val dashed: Boolean, val crushClip: Boolean)

    fun guideStrokes(
        clip: Boolean,
        crush: Boolean,
        middle: Boolean,
        colorMode: Int,
    ): List<GuideStroke> {
        val strokes = ArrayList<GuideStroke>(5)
        strokes += GuideStroke(0.0, dashed = false, crushClip = false)
        strokes += GuideStroke(100.0, dashed = false, crushClip = false)
        if (crush) strokes += GuideStroke(BUFFER_IRE, dashed = true, crushClip = true)
        if (clip) strokes += GuideStroke(100.0 - BUFFER_IRE, dashed = true, crushClip = true)
        if (middle) {
            strokes += GuideStroke(middleGrayIRE(colorMode), dashed = false, crushClip = false)
        }
        return strokes
    }
}

object HistogramAssist {
    const val PANEL_TITLE = "Histo"
    const val CHIP = "RGBL"
    const val CLIP_ZONE_IRE = 95.0
    const val TRAFFIC_LAMP_WIDTH = 7.5f
    const val TRAFFIC_LAMP_HEIGHT = 15f
    const val TRAFFIC_OUTER_PAD = 6f
    const val TRAFFIC_LINE_GAP = 4f
    const val TRAFFIC_LIGHTS_TITLE = "Traffic Lights"
    const val TRAFFIC_LIGHTS_HELP = "Show small RGB edge blocks for crushed and clipped channels. Clip lights from about a third of a stop under the camera's clip, the same point zebra 100% and CineStop use."
    const val COMPENSATION_TITLE = "Crush/Clip Compensation"
    const val COMPENSATION_HELP =
        "Stops of crush/clip tolerance before a traffic light glows. Shared with the goal-post meter."

    val trafficGutter: Float
        get() = TRAFFIC_OUTER_PAD + TRAFFIC_LAMP_WIDTH + TRAFFIC_LINE_GAP

    fun plotRect(width: Float, height: Float, density: Float = 1f): AssistRect {
        val gutter = trafficGutter * density
        val title = WaveformAxis.TITLE_HEIGHT * density
        val bottom = WaveformAxis.BOTTOM_PAD * density
        return AssistRect(
            gutter,
            title,
            maxOf(1f, width - gutter * 2f),
            maxOf(1f, height - title - bottom),
        )
    }

    fun plotX(ire: Double, rect: AssistRect, density: Float = 1f): Float =
        WaveformAxis.plotX(ire, rect, density)

    fun ireX(scaleIRE: Double, rect: AssistRect, density: Float = 1f): Float =
        WaveformAxis.plotX(scaleIRE, rect, density)
}

object WaveformAssist {
    /** OpenZCine `waveformParadeBrightnessMultiplier` - 100% = former 25%. */
    fun intensity(brightness: Int): Double = brightness.coerceIn(0, 200) / 400.0
}

object ParadeAssist {
    fun intensity(brightness: Int): Double = brightness.coerceIn(0, 200) / 100.0

    fun laneWidth(mode: ParadeMode, plot: AssistRect): Float = plot.width / mode.laneCount

    fun laneX(xRatio: Double, lane: Int, mode: ParadeMode, plot: AssistRect): Float {
        val width = laneWidth(mode, plot)
        val originX = plot.minX + lane * width
        return originX + xRatio.toFloat() * (width - 1f)
    }

    fun chip(mode: ParadeMode): String = mode.label.uppercase()
}

typealias MovablePanelMath = com.opencapture.monitorui.MonitorScopePanelMath

object FalseColorBands {
    data class Band(
        val lowerBound: Double,
        val upperBound: Double,
        val red: Double,
        val green: Double,
        val blue: Double,
        val label: String,
    ) {
        fun contains(value: Double): Boolean = value >= lowerBound && value < upperBound
    }

    fun bands(
        scale: FalseColorScale,
        transfer: MonitorTransfer,
        rec709: Boolean = false,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): List<Band> =
        when (scale) {
            FalseColorScale.SCENE_STOPS -> sceneStopBands(clipStops(transfer, rec709, ceiling))
            FalseColorScale.STOPS -> cineStopBands()
            FalseColorScale.IRE -> ireBands()
            FalseColorScale.LIMITS -> limitBands(limitShelfIRE(transfer, rec709, ceiling))
        }

    /** iOS `LiveColorScience.cineStopBands`: the Video scale, Video Mode IRE with grayscale gaps. */
    fun cineStopBands(): List<Band> =
        listOf(
            Band(0.0, 5.0, 0.44, 0.22, 0.76, "0–4"),
            Band(5.0, 6.0, 0.28, 0.37, 0.85, "5"),
            Band(10.0, 13.0, 0.18, 0.58, 0.64, "10–12"),
            Band(41.0, 49.0, 0.38, 0.63, 0.35, "41–48"),
            Band(61.0, 71.0, 0.83, 0.53, 0.71, "61–70"),
            Band(92.0, 94.0, 0.83, 0.77, 0.45, "92–93"),
            Band(94.0, 96.0, 0.89, 0.72, 0.29, "94–95"),
            Band(96.0, 99.0, 0.85, 0.55, 0.22, "96–98"),
            Band(99.0, Double.POSITIVE_INFINITY, 0.78, 0.28, 0.18, "99–100"),
        )

    fun ireBands(): List<Band> =
        listOf(
            Band(0.0, 2.5, 115 / 255.0, 33 / 255.0, 120 / 255.0, "BDL"),
            Band(2.5, 10.0, 29 / 255.0, 2 / 255.0, 221 / 255.0, "NBDL"),
            Band(38.0, 42.0, 123 / 255.0, 207 / 255.0, 87 / 255.0, "18%MG"),
            Band(52.0, 56.0, 241 / 255.0, 190 / 255.0, 198 / 255.0, "MG+1"),
            Band(80.0, 95.0, 255 / 255.0, 255 / 255.0, 88 / 255.0, "80%WC"),
            Band(95.0, Double.POSITIVE_INFINITY, 220 / 255.0, 51 / 255.0, 33 / 255.0, "95%WC"),
        )

    /** iOS `LiveColorScience.limitBands(shelfIRE:)`: clip starts on the clip shelf, never above 99 IRE. */
    fun limitBands(shelfIRE: Double? = null): List<Band> {
        val bands =
            listOf(
                Band(0.0, 5.0, 0.44, 0.22, 0.76, "0–4"),
                Band(5.0, 10.0, 0.28, 0.37, 0.85, "5–9"),
                Band(94.0, 99.0, 0.89, 0.72, 0.29, "94–98"),
                Band(99.0, Double.POSITIVE_INFINITY, 0.78, 0.28, 0.18, "99–100"),
            )
        if (shelfIRE == null || shelfIRE >= 99 || shelfIRE <= bands[2].lowerBound) return bands
        return bands.mapIndexed { index, band ->
            when (index) {
                2 -> band.copy(upperBound = shelfIRE)
                3 -> band.copy(lowerBound = shelfIRE)
                else -> band
            }
        }
    }

    /** iOS `falseColorClip` for Limits: the clip shelf in WAVE IRE, on Rec.709 when 709 reads the look. */
    fun limitShelfIRE(transfer: MonitorTransfer, rec709: Boolean = false, ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED): Double {
        val t = if (readsThroughLook(transfer, rec709)) MonitorTransfer.REC709 else transfer
        val shelf = maxOf(0.0, ceiling.clipEncoded(t) - ScopeExposureCeiling.CLIP_SHELF_CODES / 255.0)
        return ScopeDisplayScale.monitorPercent(shelf, t, ceiling = ceiling)
    }

    /** iOS `LiveColorScience.sceneStopDefaultClip`: clip starts at +11 when the ceiling is unknown. */
    const val SCENE_STOP_DEFAULT_CLIP = 10.5

    /**
     * iOS `LiveColorScience.falseColorClip(.sceneStops, rec709: true)`: encoded code where each
     * official Rec.709 look first saturates (33-point gray axis). Pinned by the Swift test
     * `cineStopAt709ClipMatchesTheAndroidMirror`.
     */
    private val LOOK_SATURATION =
        mapOf(MonitorTransfer.DLOG2 to 30 / 32.0, MonitorTransfer.DLOG to 1.0, MonitorTransfer.DLOGM to 1.0)

    /** True when 709 applies: the operator picked 709 and this curve has an official look. */
    fun readsThroughLook(transfer: MonitorTransfer, rec709: Boolean): Boolean =
        rec709 && transfer in LOOK_SATURATION

    /** Scene stops at this curve's clip shelf; the CineStop clip band starts here. At 709 the look's clip. */
    fun clipStops(transfer: MonitorTransfer, rec709: Boolean = false, ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED): Double {
        val ceiling =
            if (readsThroughLook(transfer, rec709)) LOOK_SATURATION.getValue(transfer)
            else ceiling.clipEncoded(transfer)
        val shelf = ceiling - ScopeExposureCeiling.CLIP_SHELF_CODES / 255.0
        val stops = LiveColorScience.stops(maxOf(0.0, shelf), transfer)
        return if (stops.isFinite()) stops else SCENE_STOP_DEFAULT_CLIP
    }

    /**
     * iOS `LiveColorScience.sceneStopBands`: CineStop, five whole-stop zones around 18% gray,
     * violet crush, red clip at the camera's ceiling, flat dark gray below and light gray above.
     */
    fun sceneStopBands(clipStops: Double = SCENE_STOP_DEFAULT_CLIP): List<Band> {
        val clip = if (clipStops.isFinite()) clipStops else SCENE_STOP_DEFAULT_CLIP
        return buildList {
            add(rgb(Double.NEGATIVE_INFINITY, -6.5, 75, 8, 165, "crush"))
            add(rgb(-6.5, -2.5, 102, 102, 102, "shadows"))
            SCENE_STOP_ZONES.filter { it.lowerBound < clip }
                .forEach { add(it.copy(upperBound = minOf(it.upperBound, clip))) }
            if (clip > 2.5) add(rgb(2.5, clip, 179, 178, 178, "highlights"))
            add(rgb(clip, Double.POSITIVE_INFINITY, 245, 39, 0, "clip"))
        }
    }

    private val SCENE_STOP_ZONES =
        listOf(
            rgb(-2.5, -1.5, 39, 76, 0, "−2"),
            rgb(-1.5, -0.5, 155, 196, 56, "−1"),
            rgb(-0.5, 0.5, 127, 127, 127, "18%"),
            rgb(0.5, 1.5, 221, 174, 180, "+1"),
            rgb(1.5, 2.5, 252, 232, 96, "+2"),
        )

    private fun rgb(lo: Double, hi: Double, r: Int, g: Int, b: Int, label: String) =
        Band(lo, hi, r / 255.0, g / 255.0, b / 255.0, label)
}

typealias AssistLongPress = com.opencapture.monitorui.MonitorAssistPanelMetrics

/** iOS `ZebraAssist.Options.displayValue` / `ire(fromDisplay:)`. Thresholds stay 0–100 IRE. */
object ZebraEditor {
    fun displayValue(ire: Double, unit: ZebraUnit, transfer: MonitorTransfer, ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED): Int =
        when (unit) {
            ZebraUnit.IRE -> ire.roundToInt()
            ZebraUnit.NATIVE ->
                (ScopeDisplayScale.signalNative(ire, transfer, ceiling = ceiling) * 255.0).roundToInt()
        }

    fun ireFromDisplay(value: Int, unit: ZebraUnit, transfer: MonitorTransfer, ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED): Double =
        when (unit) {
            ZebraUnit.IRE -> value.toDouble().coerceIn(0.0, 100.0)
            ZebraUnit.NATIVE ->
                ScopeDisplayScale.monitorPercent(value.coerceIn(0, 255) / 255.0, transfer, ceiling = ceiling)
        }

    fun editorMaximum(unit: ZebraUnit): Int = if (unit == ZebraUnit.NATIVE) 255 else 100
}

/** iOS `FalseColorReference` - 264×52 glass ruler with proportional zone chips. */
object FalseColorReference {
    data class Segment(
        val lowerFraction: Double,
        val upperFraction: Double,
        val band: FalseColorBands.Band,
    )

    data class AxisMarker(val label: String, val fraction: Double)

    /** iOS `FalseColorReference.sceneStopDomain`: crush to one stop past this curve's clip. */
    private fun sceneStopDomain(
        transfer: MonitorTransfer,
        rec709: Boolean,
        ceiling: com.opencapture.opencine.media.ScopeClipSource,
    ): ClosedRange<Double> = -8.5..(maxOf(2.5, FalseColorBands.clipStops(transfer, rec709, ceiling)) + 1)

    fun curveKeyLabel(colorMode: Int, rec709: Boolean = false): String =
        if (FalseColorBands.readsThroughLook(MonitorTransfer.fromColorMode(colorMode), rec709)) "709"
        else when (colorMode) {
            com.opencapture.opencine.vocabulary.CameraCommands.COLOR_HDR -> "HLG"
            com.opencapture.opencine.vocabulary.CameraCommands.COLOR_DLOG -> "D-Log"
            com.opencapture.opencine.vocabulary.CameraCommands.COLOR_DLOG_M -> "DLM ≈"
            com.opencapture.opencine.vocabulary.CameraCommands.COLOR_DLOG2 -> "D-Log2"
            else -> "709"
        }

    fun axisLabels(scale: FalseColorScale): List<String> =
        when (scale) {
            FalseColorScale.SCENE_STOPS -> emptyList()
            FalseColorScale.STOPS, FalseColorScale.IRE -> listOf("crush", "18%", "skin", "clip")
            FalseColorScale.LIMITS -> listOf("crushed", "midtones untouched", "clipped")
        }

    fun segments(
        scale: FalseColorScale,
        transfer: MonitorTransfer,
        rec709: Boolean = false,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): List<Segment> =
        FalseColorBands.bands(scale, transfer, rec709, ceiling).map { band ->
            Segment(
                lowerFraction = fraction(band.lowerBound, scale, transfer, rec709, ceiling, infiniteFallback = 0.0),
                upperFraction = fraction(band.upperBound, scale, transfer, rec709, ceiling, infiniteFallback = 1.0),
                band = band,
            )
        }

    /** iOS `FalseColorReference.sceneStopMarkers`: every second stop, 1½ stops clear of clip. */
    fun sceneStopMarkers(
        transfer: MonitorTransfer,
        rec709: Boolean = false,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): List<AxisMarker> {
        val clip = FalseColorBands.clipStops(transfer, rec709, ceiling)
        val marks =
            generateSequence(-6) { it + 2 }.takeWhile { it < clip - 1.5 }
                .map { stop ->
                    val label = if (stop == 0) "18%" else if (stop < 0) "−${-stop}" else "+$stop"
                    label to stop.toDouble()
                }.toList() + ("clip" to clip)
        return marks.map { (label, stop) ->
            AxisMarker(label, fraction(stop, FalseColorScale.SCENE_STOPS, transfer, rec709, ceiling, infiniteFallback = 1.0))
        }
    }

    private fun fraction(
        value: Double,
        scale: FalseColorScale,
        transfer: MonitorTransfer,
        rec709: Boolean,
        ceiling: com.opencapture.opencine.media.ScopeClipSource,
        infiniteFallback: Double,
    ): Double {
        if (!value.isFinite()) return infiniteFallback
        if (!scale.usesSceneStops) return (value / 100.0).coerceIn(0.0, 1.0)
        val domain = sceneStopDomain(transfer, rec709, ceiling)
        return ((value - domain.start) / (domain.endInclusive - domain.start)).coerceIn(0.0, 1.0)
    }
}

/**
 * Stereo meters from [CameraStatus] when `audioMetersLeft` / `audioMetersRight`
 * exist on the JSON blob or as fields. Session has not published them yet.
 */
fun CameraStatus.audioMetersLeftRight(): Pair<Double, Double>? {
    val left = audioMetersLeft
    val right = audioMetersRight
    if (left <= -60.0 && right <= -60.0) return null
    return left to right
}

fun Pair<Double, Double>.asMeterChannels(): Pair<AudioMeterReading, AudioMeterReading> {
    fun channel(raw: Double): AudioMeterReading {
        val db =
            when {
                raw in AudioAssist.FLOOR_DB..0.0 -> raw
                raw in 0.0..1.0 -> AudioAssist.FLOOR_DB * (1.0 - raw)
                raw in 0.0..100.0 -> AudioAssist.FLOOR_DB * (1.0 - raw / 100.0)
                else -> raw.coerceIn(AudioAssist.FLOOR_DB, 0.0)
            }
        return AudioMeterReading(levelDB = db, peakDB = db)
    }
    return channel(first) to channel(second)
}

data class AudioMeterReading(val levelDB: Double, val peakDB: Double)

fun AssistSize.scaled(scale: Double): AssistSize = MovablePanelMath.panelSize(this, scale)
