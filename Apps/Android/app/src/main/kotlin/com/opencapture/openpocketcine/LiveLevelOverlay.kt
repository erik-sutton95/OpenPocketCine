package com.opencapture.openpocketcine

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.monitorui.monitorReadoutShadow
import com.opencapture.openpocketcine.session.LevelMode
import com.opencapture.openpocketcine.session.LevelReading
import com.opencapture.openpocketcine.session.WorldLevelSnap
import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt
import kotlinx.coroutines.delay

/**
 * LEVEL: camera world attitude ([LevelReading]), not this phone. Mirrors iOS
 * `MonitorLevelGauge`: the EV meter's language (slim white line, glow, number at
 * the start, ±8 ends) with a bubble ring that turns green when level. Tilt takes
 * the EV meter's left-edge slot, one strip over when EV is on; roll runs along the
 * bottom; a bubble replaces both near plumb. No data reads `No level data`.
 */
internal object LiveLevel {
    const val REFRESH_MS = 100L
    const val THICKNESS = 28f
    const val MAX_LENGTH = 180f
    const val SPAN = 8.0
    const val THRESHOLD = 0.6
    const val BUBBLE_SPAN = 10.0
    const val BUBBLE_RADIUS = 44f
    val good = Color(0.18f, 0.78f, 0.42f)

    fun visible(feed: ChromeRect, viewport: ChromeRect): ChromeRect {
        val x = maxOf(feed.minX, viewport.minX)
        val y = maxOf(feed.minY, viewport.minY)
        val w = minOf(feed.maxX, viewport.maxX) - x
        val h = minOf(feed.maxY, viewport.maxY) - y
        return if (w <= 0f || h <= 0f) feed else ChromeRect(x, y, w, h)
    }

    data class Frames(val roll: ChromeRect, val tilt: ChromeRect?)

    /** Strips in dp against the on-screen part of the feed (OpenZCine #47). */
    fun frames(
        feed: ChromeRect, viewport: ChromeRect, portrait: Boolean,
        avoid: ChromeRect? = null, evVisible: Boolean = false,
    ): Frames {
        val v = visible(feed, viewport)
        val tilt = CameraExposureMeter.frame(v, PocketDispMode.LIVE, avoid)
            ?.let { if (evVisible) ChromeRect(it.x + THICKNESS + 6f, it.y, it.width, it.height) else it }
        val rollWidth = minOf(MAX_LENGTH, v.width - 24f).coerceAtLeast(0f)
        val rollMidY = v.maxY - if (portrait) 30f else 104f
        return Frames(ChromeRect(v.midX - rollWidth / 2f, rollMidY - THICKNESS / 2f, rollWidth, THICKNESS), tilt)
    }

    fun label(value: Double?): String =
        if (value == null) "—" else String.format(Locale.ROOT, "%+.1f°", if (abs(value) < 0.05) 0.0 else value)

    fun accessibilityLabel(mode: LevelMode): String = when (mode) {
        LevelMode.Unavailable -> "Level, ${WorldLevelSnap.NO_LEVEL_DATA}"
        is LevelMode.Gauges -> String.format(Locale.ROOT, "Level, roll %+.1f°, tilt %+.1f°", mode.rollDeg, mode.tiltDeg)
        is LevelMode.Bubble -> String.format(Locale.ROOT, "Level, off plumb %+.1f° / %+.1f°", mode.xDeg, mode.yDeg)
    }
}

@Composable
internal fun LiveLevelOverlay(
    reading: LevelReading,
    viewFlip: Boolean,
    feed: ChromeRect,
    viewport: ChromeRect,
    portrait: Boolean,
    modifier: Modifier = Modifier,
    avoid: ChromeRect? = null,
    evVisible: Boolean = false,
) {
    var mode by remember { mutableStateOf<LevelMode>(LevelMode.Unavailable) }
    LaunchedEffect(reading, viewFlip) {
        while (true) {
            mode = reading.mode(android.os.SystemClock.elapsedRealtimeNanos() / 1e9, viewFlip)
            delay(LiveLevel.REFRESH_MS)
        }
    }
    val measurer = rememberTextMeasurer()
    Canvas(
        modifier.fillMaxSize().monitorReadoutShadow()
            .semantics { contentDescription = LiveLevel.accessibilityLabel(mode) },
    ) {
        val frames = LiveLevel.frames(feed, viewport, portrait, avoid, evVisible)
        when (val m = mode) {
            is LevelMode.Bubble -> {
                val v = LiveLevel.visible(feed, viewport)
                drawBubble(Offset(v.midX.dp.toPx(), v.midY.dp.toPx()), m.xDeg, m.yDeg, measurer)
            }
            is LevelMode.Gauges -> {
                drawStrip(frames.roll, vertical = false, m.rollDeg, measurer)
                frames.tilt?.let { drawStrip(it, vertical = true, m.tiltDeg, measurer) }
            }
            LevelMode.Unavailable -> {
                drawStrip(frames.roll, vertical = false, null, measurer)
                frames.tilt?.let { drawStrip(it, vertical = true, null, measurer) }
                text(measurer, WorldLevelSnap.NO_LEVEL_DATA,
                    Offset(frames.roll.midX.dp.toPx(), (frames.roll.maxY + 6f).dp.toPx()), LiveDesign.muted, 8f)
            }
        }
    }
}

private fun DrawScope.text(measurer: TextMeasurer, s: String, centre: Offset, color: Color, size: Float, bold: Boolean = false) {
    val style = TextStyle(color = color, fontSize = size.sp, fontFamily = OpcFonts.sora,
        fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Medium)
    val layout = measurer.measure(s, style)
    drawText(layout, topLeft = Offset(centre.x - layout.size.width / 2f, centre.y - layout.size.height / 2f))
}

private fun DrawScope.marker(c: Offset, tint: Color, level: Boolean) {
    drawCircle(tint, radius = 4.5f.dp.toPx(), center = c, style = Stroke(1.2f.dp.toPx()))
    if (level) drawCircle(tint, radius = 2f.dp.toPx(), center = c)
}

/** iOS `MonitorLevelGauge`: layout in dp inside [rect]; positive reads up / right. */
private fun DrawScope.drawStrip(rect: ChromeRect, vertical: Boolean, value: Double?, measurer: TextMeasurer) {
    if (rect.isEmpty) return
    val white = LiveDesign.text
    val line = white.copy(alpha = 0.8f)
    val isLevel = value != null && abs(value) < LiveLevel.THRESHOLD
    val tint = if (isLevel) LiveLevel.good else white
    val length = if (vertical) rect.height else rect.width
    val start = if (vertical) 34f else 22f
    val end = maxOf(start, length - if (vertical) 18f else 22f)
    val across = if (vertical) rect.width / 2f else rect.height - 8f
    fun p(t: Float) = if (vertical) Offset((rect.x + across).dp.toPx(), (rect.y + t).dp.toPx())
        else Offset((rect.x + t).dp.toPx(), (rect.y + across).dp.toPx())
    fun position(deg: Double): Float {
        val f = ((deg.coerceIn(-LiveLevel.SPAN, LiveLevel.SPAN) + LiveLevel.SPAN) / (2 * LiveLevel.SPAN)).toFloat()
        return if (vertical) end - (end - start) * f else start + (end - start) * f
    }
    text(measurer, LiveLevel.label(value), Offset((rect.x + rect.width / 2f).dp.toPx(), (rect.y + 6f).dp.toPx()), tint, 10f, bold = true)
    val ends = if (vertical) listOf("+8" to Offset(rect.width / 2f, 23f), "−8" to Offset(rect.width / 2f, rect.height - 5f))
        else listOf("−8" to Offset(9f, across), "+8" to Offset(rect.width - 9f, across))
    for ((label, at) in ends) text(measurer, label, Offset((rect.x + at.x).dp.toPx(), (rect.y + at.y).dp.toPx()), white, 8f)
    val stroke = 1f.dp.toPx()
    val m = value?.let { position(it) }
    if (m == null) {
        drawLine(line, p(start), p(end), stroke)
    } else {
        if (minOf(m - 9f, end) > start) drawLine(line, p(start), p(minOf(m - 9f, end)), stroke)
        if (end > maxOf(m + 9f, start)) drawLine(line, p(maxOf(m + 9f, start)), p(end), stroke)
    }
    val z = p(position(0.0))
    val half = 5f.dp.toPx()
    if (vertical) drawLine(line, Offset(z.x - half, z.y), Offset(z.x + half, z.y), stroke)
    else drawLine(line, Offset(z.x, z.y - half), Offset(z.x, z.y + half), stroke)
    if (m != null) marker(p(m), tint, isLevel)
}

/** iOS `MonitorLevelBubble`: thin ±10° ring, centre cross, bubble ring toward the high side. */
private fun DrawScope.drawBubble(centre: Offset, x: Double, y: Double, measurer: TextMeasurer) {
    val white = LiveDesign.text
    val line = white.copy(alpha = 0.8f)
    val r = LiveLevel.BUBBLE_RADIUS.dp.toPx()
    val mid = Offset(centre.x, centre.y + 8f.dp.toPx())
    val distance = sqrt(x * x + y * y)
    val isLevel = distance < LiveLevel.THRESHOLD
    val tint = if (isLevel) LiveLevel.good else white
    text(measurer, "${LiveLevel.label(x)} / ${LiveLevel.label(y)}", Offset(mid.x, mid.y - r - 18f.dp.toPx()), tint, 10f, bold = true)
    val stroke = 1f.dp.toPx()
    drawCircle(line, radius = r, center = mid, style = Stroke(stroke))
    val arm = 5f.dp.toPx()
    drawLine(line, Offset(mid.x - arm, mid.y), Offset(mid.x + arm, mid.y), stroke)
    drawLine(line, Offset(mid.x, mid.y - arm), Offset(mid.x, mid.y + arm), stroke)
    val clamp = if (distance > LiveLevel.BUBBLE_SPAN) LiveLevel.BUBBLE_SPAN / distance else 1.0
    marker(
        Offset(mid.x + (x * clamp / LiveLevel.BUBBLE_SPAN).toFloat() * r, mid.y - (y * clamp / LiveLevel.BUBBLE_SPAN).toFloat() * r),
        tint, isLevel,
    )
}
