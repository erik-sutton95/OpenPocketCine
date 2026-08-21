package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.round
import kotlin.math.roundToInt
import kotlin.math.sin

data class AssistPoint(val x: Float, val y: Float)

data class AssistSize(val width: Float, val height: Float)

data class AssistRect(val x: Float, val y: Float, val width: Float, val height: Float) {
    val minX: Float
        get() = x
    val minY: Float
        get() = y
    val maxX: Float
        get() = x + width
    val maxY: Float
        get() = y + height
    val midX: Float
        get() = x + width / 2f
    val midY: Float
        get() = y + height / 2f

    fun contains(px: Float, py: Float): Boolean = px in minX..maxX && py in minY..maxY
}

data class GridSegment(val from: AssistPoint, val to: AssistPoint)

data class StoredCenter(val xFraction: Double, val yFraction: Double) {
    constructor(center: AssistPoint, bounds: AssistRect) : this(
        ((center.x - bounds.minX) / maxOf(bounds.width, 1f)).toDouble(),
        ((center.y - bounds.minY) / maxOf(bounds.height, 1f)).toDouble(),
    )

    fun center(bounds: AssistRect): AssistPoint =
        AssistPoint(
            bounds.minX + xFraction.toFloat() * bounds.width,
            bounds.minY + yFraction.toFloat() * bounds.height,
        )
}

data class ScopeGuides(
    val clip: Boolean = true,
    val crush: Boolean = true,
    val middle: Boolean = true,
)

object ScopePanelSize {
    val waveform = AssistSize(250f, 153f)
    val parade = AssistSize(250f, 153f)
    val histogram = AssistSize(250f, 77f)
    val vectorscope = AssistSize(190f, 190f)
    val trafficLights = AssistSize(74f, 168f)
    val audio = AssistSize(28f, 168f)
    val falseColorReference = AssistSize(264f, 52f)
}

object GridAssist {
    val thirdsFractions = floatArrayOf(1f / 3f, 2f / 3f)
    val phiFractions = floatArrayOf(0.382f, 0.618f)
    const val STROKE_OPACITY = 0.22f
    const val STROKE_WIDTH_DP = 1f
    val optionLabels = listOf("Thirds", "Phi Grid", "Diagonal")

    fun segments(
        feed: AssistRect,
        thirds: Boolean,
        phi: Boolean,
        diagonal: Boolean,
    ): List<GridSegment> {
        val lines = ArrayList<GridSegment>(12)
        if (thirds) appendFractions(feed, thirdsFractions, lines)
        if (phi) appendFractions(feed, phiFractions, lines)
        if (diagonal) {
            lines +=
                GridSegment(
                    AssistPoint(feed.minX, feed.minY),
                    AssistPoint(feed.maxX, feed.maxY),
                )
            lines +=
                GridSegment(
                    AssistPoint(feed.maxX, feed.minY),
                    AssistPoint(feed.minX, feed.maxY),
                )
        }
        return lines
    }

    private fun appendFractions(feed: AssistRect, fractions: FloatArray, lines: MutableList<GridSegment>) {
        for (fraction in fractions) {
            val x = feed.minX + feed.width * fraction
            val y = feed.minY + feed.height * fraction
            lines += GridSegment(AssistPoint(x, feed.minY), AssistPoint(x, feed.maxY))
            lines += GridSegment(AssistPoint(feed.minX, y), AssistPoint(feed.maxX, y))
        }
    }
}

object GuidesAssist {
    const val PANEL_WIDTH_DP = 472f

    fun summaryLabel(selected: Set<GuideAspect>): String =
        when (selected.size) {
            0 -> "—"
            1 -> selected.first().label
            else -> "${selected.size} ratios"
        }

    /** Letterbox when the guide is wider than the feed, pillarbox when narrower. */
    fun rectForRatio(feed: AssistRect, ratio: Float): AssistRect {
        val width: Float
        val height: Float
        if (feed.height <= 0f || ratio <= 0f) return feed
        if (feed.width / feed.height > ratio) {
            height = feed.height
            width = feed.height * ratio
        } else {
            width = feed.width
            height = feed.width / ratio
        }
        return AssistRect(
            feed.minX + (feed.width - width) / 2f,
            feed.minY + (feed.height - height) / 2f,
            width,
            height,
        )
    }
}

object CrosshairAssist {
    const val ARM_LENGTH_DP = 40f
    const val STROKE_WIDTH_DP = 1.4f
    const val OPACITY = 0.65f
    const val HELP = "Tap the toolbar button to show or hide the centre crosshair."
}

object MirrorAssist {
    const val EXPLANATION =
        "Flips the monitor left-to-right, for a camera pointed back at you. " +
            "The recording and the scopes are never mirrored."

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

    fun displayedSensitivity(value: String?): String {
        val trimmed = value?.trim().orEmpty()
        return if (trimmed.isEmpty()) "—" else trimmed.uppercase()
    }

    fun y(db: Double, barTop: Float, barBottom: Float): Float {
        val fraction = ((db - FLOOR_DB) / -FLOOR_DB).coerceIn(0.0, 1.0)
        return (barBottom - fraction * (barBottom - barTop)).toFloat()
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
    const val OPTIONS_DRAG_SLOP = 8f
    val crushClipDash = floatArrayOf(3f, 3f)

    fun plotRect(width: Float, height: Float): AssistRect =
        AssistRect(
            SIDE_PAD,
            TITLE_HEIGHT,
            width - SIDE_PAD * 2f,
            maxOf(1f, height - TITLE_HEIGHT - BOTTOM_PAD),
        )

    fun plotY(ire: Double, rect: AssistRect): Float {
        val span = rect.height - 2f * PLOT_INSET
        return rect.maxY - PLOT_INSET - (ire / 100.0).toFloat() * span
    }

    fun plotX(ire: Double, rect: AssistRect): Float {
        val span = rect.width - 2f * PLOT_INSET
        return rect.minX + PLOT_INSET + (ire / 100.0).toFloat() * span
    }

    /**
     * Paper IRE of 18% grey. Rec.709 ≈ 40.9, D-Log 39.88, D-Log2 30.50.
     * JNI LiveColorScience will replace this once a tap exists.
     */
    fun middleGrayIRE(colorMode: Int): Double =
        when (colorMode) {
            CameraCommands.COLOR_DLOG2 -> 30.50
            CameraCommands.COLOR_DLOG -> 39.88
            CameraCommands.COLOR_HDR -> 47.0
            else -> 40.9
        }

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

    fun shouldPresentOptions(dx: Float, dy: Float): Boolean = hypot(dx, dy) <= OPTIONS_DRAG_SLOP
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
    const val TRAFFIC_LIGHTS_HELP = "Show small RGB edge blocks for crushed and clipped channels."
    const val COMPENSATION_TITLE = "Crush/Clip Compensation"
    const val COMPENSATION_HELP =
        "Stops of crush/clip tolerance before a traffic light glows. Shared with the goal-post meter."

    val trafficGutter: Float
        get() = TRAFFIC_OUTER_PAD + TRAFFIC_LAMP_WIDTH + TRAFFIC_LINE_GAP

    fun plotRect(width: Float, height: Float): AssistRect =
        AssistRect(
            trafficGutter,
            WaveformAxis.TITLE_HEIGHT,
            maxOf(1f, width - trafficGutter * 2f),
            maxOf(1f, height - WaveformAxis.TITLE_HEIGHT - WaveformAxis.BOTTOM_PAD),
        )

    fun plotX(ire: Double, rect: AssistRect): Float = WaveformAxis.plotX(ire, rect)

    fun ireX(scaleIRE: Double, rect: AssistRect): Float = WaveformAxis.plotX(scaleIRE, rect)
}

object ParadeAssist {
    fun laneWidth(mode: ParadeMode, plot: AssistRect): Float = plot.width / mode.laneCount

    fun laneX(xRatio: Double, lane: Int, mode: ParadeMode, plot: AssistRect): Float {
        val width = laneWidth(mode, plot)
        val originX = plot.minX + lane * width
        return originX + xRatio.toFloat() * (width - 1f)
    }

    fun chip(mode: ParadeMode): String = mode.label.uppercase()

    fun accessibilityLabel(mode: ParadeMode): String =
        if (mode == ParadeMode.YRGB) "YRGB parade" else "RGB parade"
}

object VectorscopeAssist {
    fun chip(zoom: VectorscopeZoom): String = "MON · ${zoom.label.uppercase()}"
}

object VectorscopeGraticule {
    const val SKIN_ANGLE_DEGREES = 123.0
    const val SKIN_LENGTH = 0.92
    const val BOX_SIDE = 7f
    const val LABEL_PUSH = 10f
    const val CROSS_ARM = 8f
    data class Target(val label: String, val red: Int, val green: Int, val blue: Int)

    val targets =
        listOf(
            Target("R", 191, 0, 0),
            Target("Mg", 191, 0, 191),
            Target("B", 0, 0, 191),
            Target("Cy", 0, 191, 191),
            Target("G", 0, 191, 0),
            Target("Yl", 191, 191, 0),
        )

    fun plotSquare(width: Float, height: Float): AssistRect {
        val plot =
            AssistRect(
                6f,
                26f,
                width - 12f,
                maxOf(1f, height - 26f - 8f),
            )
        val side = minOf(plot.width, plot.height)
        return AssistRect(plot.midX - side / 2f, plot.midY - side / 2f, side, side)
    }

    fun skinEnd(rect: AssistRect): AssistPoint {
        val radius = rect.width / 2f
        val angle = Math.toRadians(SKIN_ANGLE_DEGREES)
        return AssistPoint(
            rect.midX + (cos(angle) * radius * SKIN_LENGTH).toFloat(),
            rect.midY - (sin(angle) * radius * SKIN_LENGTH).toFloat(),
        )
    }

    fun rec709Chroma(red: Double, green: Double, blue: Double): Pair<Double, Double> {
        val y = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return (blue - y) / 1.8556 to (red - y) / 1.5748
    }

    fun targetCenter(red: Int, green: Int, blue: Int, rect: AssistRect): AssistPoint {
        val chroma = rec709Chroma(red / 255.0, green / 255.0, blue / 255.0)
        return AssistPoint(
            rect.midX + chroma.first.toFloat() * rect.width,
            rect.midY - chroma.second.toFloat() * rect.height,
        )
    }
}

object TrafficLightsAssist {
    const val METER_TITLE = "TL"
    const val TITLE_SIZE = 8.5f
    const val TITLE_SPACING = 6f
    const val COLUMN_SPACING = 6f
    const val POST_SPACING = 4f
    const val PANEL_PAD = 8f
    const val TRACK_WIDTH = 11f
    const val COLUMN_HEIGHT = 108f
    const val INDICATOR_SIZE = 8f
    const val TRACK_CORNER = 2f
    const val MIN_BAR_HEIGHT = 1.5f
    const val CENTER_LINE_FACTOR = 0.85f
    const val BALANCE_CENTER = 0.5
    const val BALANCE_DEAD_ZONE = 0.03
    val meterRedRGB = Triple(255.0, 92.0, 82.0)
    val meterGreenRGB = Triple(86.0, 235.0, 132.0)
    val meterBlueRGB = Triple(96.0, 158.0, 255.0)

    enum class BarSide {
        NEUTRAL,
        OVER,
        UNDER,
    }

    data class ChannelDisplay(val side: BarSide, val barFill: Double) {
        companion object {
            val neutral = ChannelDisplay(BarSide.NEUTRAL, 0.0)
        }
    }

    fun channelDisplay(
        level: Double,
        center: Double = BALANCE_CENTER,
        deadZone: Double = BALANCE_DEAD_ZONE,
    ): ChannelDisplay {
        val deviation = level - center
        if (abs(deviation) <= deadZone) return ChannelDisplay.neutral
        return if (deviation > 0) {
            val span = maxOf(1 - center, Double.MIN_VALUE)
            ChannelDisplay(BarSide.OVER, minOf(1.0, deviation / span))
        } else {
            val span = maxOf(center, Double.MIN_VALUE)
            ChannelDisplay(BarSide.UNDER, minOf(1.0, abs(deviation) / span))
        }
    }
}

object MovablePanelMath {
    const val HOLD_SECONDS = 0.3
    const val POSITION_GRID = 4f
    const val HAPTIC_GRID = 22f
    const val SCALE_MIN = 0.6
    const val SCALE_MAX = 1.6
    const val GAP = 10f

    fun clampedScale(value: Double): Double = value.coerceIn(SCALE_MIN, SCALE_MAX)

    fun panelSize(base: AssistSize, scale: Double): AssistSize {
        val clamped = clampedScale(scale)
        return AssistSize(round(base.width * clamped.toFloat()), round(base.height * clamped.toFloat()))
    }

    fun clamp(point: AssistPoint, size: AssistSize, bounds: AssistRect): AssistPoint {
        val halfW = size.width / 2f
        val halfH = size.height / 2f
        return AssistPoint(
            point.x.coerceIn(bounds.minX + halfW, bounds.maxX - halfW),
            point.y.coerceIn(bounds.minY + halfH, bounds.maxY - halfH),
        )
    }

    fun snap(point: AssistPoint, grid: Float = POSITION_GRID): AssistPoint =
        AssistPoint(round(point.x / grid) * grid, round(point.y / grid) * grid)

    fun hapticCell(point: AssistPoint, grid: Float = HAPTIC_GRID): Int =
        round(point.x / grid).toInt() * 100_000 + round(point.y / grid).toInt()

    fun resolvedCenter(
        session: AssistPoint?,
        stored: StoredCenter?,
        defaultCenter: AssistPoint,
        size: AssistSize,
        bounds: AssistRect,
    ): AssistPoint {
        if (session != null) return clamp(session, size, bounds)
        if (stored != null) return clamp(stored.center(bounds), size, bounds)
        return clamp(defaultCenter, size, bounds)
    }

    fun defaultCenterTopLeading(
        feed: AssistRect,
        size: AssistSize,
        bounds: AssistRect,
        topClearance: Float = 0f,
    ): AssistPoint {
        val halfW = size.width / 2f
        val halfH = size.height / 2f
        val x = feed.minX + halfW
        val outside = feed.minY - GAP - halfH
        val y =
            if (outside - halfH >= bounds.minY) {
                outside
            } else {
                maxOf(feed.minY, bounds.minY + topClearance) + GAP + halfH
            }
        return clamp(AssistPoint(x, y), size, bounds)
    }

    fun defaultCenterTopTrailing(
        feed: AssistRect,
        size: AssistSize,
        bounds: AssistRect,
        topClearance: Float = 0f,
    ): AssistPoint {
        val halfW = size.width / 2f
        val halfH = size.height / 2f
        val x = feed.maxX - halfW
        val outside = feed.minY - GAP - halfH
        val y =
            if (outside - halfH >= bounds.minY) {
                outside
            } else {
                maxOf(feed.minY, bounds.minY + topClearance) + GAP + halfH
            }
        return clamp(AssistPoint(x, y), size, bounds)
    }

    fun defaultCenterBottomTrailing(
        feed: AssistRect,
        size: AssistSize,
        bounds: AssistRect,
        bottomClearance: Float = 0f,
    ): AssistPoint {
        val halfW = size.width / 2f
        val halfH = size.height / 2f
        val x = feed.maxX - halfW
        val outside = feed.maxY + GAP + halfH
        val y =
            if (outside + halfH <= bounds.maxY) {
                outside
            } else {
                minOf(feed.maxY, bounds.maxY - bottomClearance) - GAP - halfH
            }
        return clamp(AssistPoint(x, y), size, bounds)
    }

    fun defaultCenterBottomLeading(
        feed: AssistRect,
        size: AssistSize,
        bounds: AssistRect,
        bottomClearance: Float = 0f,
    ): AssistPoint {
        val halfW = size.width / 2f
        val halfH = size.height / 2f
        val x = feed.minX + halfW
        val outside = feed.maxY + GAP + halfH
        val y =
            if (outside + halfH <= bounds.maxY) {
                outside
            } else {
                minOf(feed.maxY, bounds.maxY - bottomClearance) - GAP - halfH
            }
        return clamp(AssistPoint(x, y), size, bounds)
    }
}

object LiveLumaHistogram {
    const val BINS = 256

    /** Rec.709 luma over packed ARGB. Empty input yields 256 zeros. */
    fun fromArgb(pixels: IntArray): IntArray {
        val bins = IntArray(BINS)
        for (px in pixels) {
            val r = (px ushr 16) and 0xFF
            val g = (px ushr 8) and 0xFF
            val b = px and 0xFF
            val y = (0.2126 * r + 0.7152 * g + 0.0722 * b).roundToInt().coerceIn(0, 255)
            bins[y]++
        }
        return bins
    }

    fun empty(): IntArray = IntArray(BINS)
}

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

    fun legendLabels(scale: FalseColorScale): List<String> =
        when (scale) {
            FalseColorScale.STOPS ->
                listOf("Minimum", "−3", "18%", "Skin +1", "+2", "⅔ below max", "⅓ below max", "Maximum")
            FalseColorScale.IRE ->
                listOf("0–4", "5", "10–12", "18%", "55–61", "92–93", "94–95", "96–98", "99–100")
            FalseColorScale.LIMITS -> listOf("0–4", "5–9", "94–98", "99–100")
        }

    fun ireBands(): List<Band> =
        listOf(
            Band(0.0, 5.0, 0.44, 0.22, 0.76, "0–4"),
            Band(5.0, 6.0, 0.28, 0.37, 0.85, "5"),
            Band(10.0, 13.0, 0.18, 0.58, 0.64, "10–12"),
            Band(28.0, 34.0, 0.38, 0.63, 0.35, "18%"),
            Band(52.0, 62.0, 0.83, 0.53, 0.71, "55–61"),
            Band(92.0, 94.0, 0.83, 0.77, 0.45, "92–93"),
            Band(94.0, 96.0, 0.89, 0.72, 0.29, "94–95"),
            Band(96.0, 99.0, 0.85, 0.55, 0.22, "96–98"),
            Band(99.0, Double.POSITIVE_INFINITY, 0.78, 0.28, 0.18, "99–100"),
        )

    fun limitBands(): List<Band> =
        listOf(
            Band(0.0, 5.0, 0.44, 0.22, 0.76, "0–4"),
            Band(5.0, 10.0, 0.28, 0.37, 0.85, "5–9"),
            Band(94.0, 99.0, 0.89, 0.72, 0.29, "94–98"),
            Band(99.0, Double.POSITIVE_INFINITY, 0.78, 0.28, 0.18, "99–100"),
        )
}

object AssistLongPress {
    const val CHIP_MS = 250L
    const val PANEL_MS = 300L
    const val GAP_DP = 10f
    const val MARGIN_DP = 12f

    fun preferredWidthDp(tool: LiveAssistTool): Float =
        if (tool == LiveAssistTool.GUIDES) 472f else 400f
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
