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
import com.opencapture.openpocketcine.session.LevelMode
import com.opencapture.openpocketcine.session.LevelReading
import com.opencapture.openpocketcine.session.WorldLevelSnap
import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt
import kotlinx.coroutines.delay

/**
 * LEVEL: camera world attitude ([LevelReading]), not this phone. Mirrors iOS
 * `MonitorLevelGauge`: the EV meter's language in a Nikon Z virtual-horizon layout
 * (opaque dark band, centreline, cross-bar marker, number at the start, no glow),
 * green when level.
 * Roll runs along the bottom; tilt centres vertically, right of centre by the same
 * distance roll sits below centre. A bubble replaces both near plumb. No data reads
 * `No level data`.
 */
internal object LiveLevel {
    const val REFRESH_MS = 100L
    const val THICKNESS = 28f
    const val MAX_LENGTH = 180f
    const val SPAN = 8.0
    const val THRESHOLD = 0.6
    const val BUBBLE_SPAN = 10.0
    const val BUBBLE_RADIUS = 64f
    const val BAND = 8f
    /** Roll strip centre above the visible picture's bottom edge; tilt mirrors the offset. */
    const val ROLL_LIFT_LANDSCAPE = 84f
    const val ROLL_LIFT_PORTRAIT = 22f
    val good = Color(0.18f, 0.78f, 0.42f)

    fun visible(feed: ChromeRect, viewport: ChromeRect): ChromeRect {
        val x = maxOf(feed.minX, viewport.minX)
        val y = maxOf(feed.minY, viewport.minY)
        val w = minOf(feed.maxX, viewport.maxX) - x
        val h = minOf(feed.maxY, viewport.maxY) - y
        return if (w <= 0f || h <= 0f) feed else ChromeRect(x, y, w, h)
    }

    data class Frames(val roll: ChromeRect, val tilt: ChromeRect)

    /** Strips in dp against the on-screen part of the feed (OpenZCine #47). */
    fun frames(feed: ChromeRect, viewport: ChromeRect, portrait: Boolean): Frames {
        val v = visible(feed, viewport)
        val rollWidth = minOf(MAX_LENGTH, v.width - 24f).coerceAtLeast(0f)
        val rollMidY = v.maxY - if (portrait) ROLL_LIFT_PORTRAIT else ROLL_LIFT_LANDSCAPE
        val tiltHeight = minOf(MAX_LENGTH, v.height - 12f).coerceAtLeast(0f)
        // Same offset from centre as roll, kept 6 dp inside the picture (portrait fill).
        val tiltMidX = minOf(v.midX + (rollMidY - v.midY), v.maxX - 6f - THICKNESS / 2f)
        return Frames(
            ChromeRect(v.midX - rollWidth / 2f, rollMidY - THICKNESS / 2f, rollWidth, THICKNESS),
            ChromeRect(tiltMidX - THICKNESS / 2f, v.midY - tiltHeight / 2f, THICKNESS, tiltHeight),
        )
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
        modifier.fillMaxSize()
            .semantics { contentDescription = LiveLevel.accessibilityLabel(mode) },
    ) {
        val frames = LiveLevel.frames(feed, viewport, portrait)
        when (val m = mode) {
            is LevelMode.Bubble -> {
                val v = LiveLevel.visible(feed, viewport)
                drawBubble(Offset(v.midX.dp.toPx(), v.midY.dp.toPx()), m.xDeg, m.yDeg, measurer)
            }
            is LevelMode.Gauges -> {
                drawStrip(frames.roll, vertical = false, m.rollDeg, measurer)
                drawStrip(frames.tilt, vertical = true, m.tiltDeg, measurer)
            }
            LevelMode.Unavailable -> {
                drawStrip(frames.roll, vertical = false, null, measurer)
                drawStrip(frames.tilt, vertical = true, null, measurer)
                text(measurer, WorldLevelSnap.NO_LEVEL_DATA,
                    Offset(frames.roll.midX.dp.toPx(), (frames.roll.maxY + 6f).dp.toPx()), LiveDesign.muted, 8f)
            }
        }
    }
}

private fun DrawScope.text(
    measurer: TextMeasurer, s: String, centre: Offset, color: Color, size: Float,
    bold: Boolean = false, shadow: Boolean = true,
) {
    // Faint text-only shadow (iOS `drawReadout`); the band carries no glow.
    val style = TextStyle(color = color, fontSize = size.sp, fontFamily = OpcFonts.sora,
        fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Medium,
        shadow = if (shadow) androidx.compose.ui.graphics.Shadow(Color.Black.copy(alpha = 0.6f), blurRadius = 1.5f.dp.toPx()) else null)
    val layout = measurer.measure(s, style)
    drawText(layout, topLeft = Offset(centre.x - layout.size.width / 2f, centre.y - layout.size.height / 2f))
}

private val bandFill = Color.Black.copy(alpha = 0.32f)

/**
 * iOS `MonitorLevelGauge`, laid out like a Nikon Z virtual horizon: opaque dark band,
 * white centreline, cross-bar marker, zero notches, number at the start. Layout in
 * dp inside [rect]; positive reads up / right. Green when level.
 */
private fun DrawScope.drawStrip(rect: ChromeRect, vertical: Boolean, value: Double?, measurer: TextMeasurer) {
    if (rect.isEmpty) return
    val white = LiveDesign.text
    val isLevel = value != null && abs(value) < LiveLevel.THRESHOLD
    val tint = if (isLevel) LiveLevel.good else white
    val length = if (vertical) rect.height else rect.width
    val start = if (vertical) 18f else 4f
    val end = maxOf(start, length - 4f)
    val across = if (vertical) rect.width / 2f else rect.height - 8f
    val h = LiveLevel.BAND / 2f
    fun p(t: Float, off: Float = 0f) = if (vertical) Offset((rect.x + across + off).dp.toPx(), (rect.y + t).dp.toPx())
        else Offset((rect.x + t).dp.toPx(), (rect.y + across + off).dp.toPx())
    fun position(deg: Double): Float {
        val f = ((deg.coerceIn(-LiveLevel.SPAN, LiveLevel.SPAN) + LiveLevel.SPAN) / (2 * LiveLevel.SPAN)).toFloat()
        return if (vertical) end - h - (end - start - 2 * h) * f else start + h + (end - start - 2 * h) * f
    }
    text(measurer, LiveLevel.label(value), Offset((rect.x + rect.width / 2f).dp.toPx(), (rect.y + 6f).dp.toPx()), tint, 10f, bold = true)
    val bandSize = if (vertical) androidx.compose.ui.geometry.Size(LiveLevel.BAND.dp.toPx(), (end - start).dp.toPx())
        else androidx.compose.ui.geometry.Size((end - start).dp.toPx(), LiveLevel.BAND.dp.toPx())
    drawRoundRect(bandFill, p(start, -h), bandSize, androidx.compose.ui.geometry.CornerRadius(h.dp.toPx()))
    val stroke = 1f.dp.toPx()
    drawLine(if (isLevel) tint else tint.copy(alpha = 0.8f), p(start + h), p(end - h), stroke)
    val zero = position(0.0)
    for (side in listOf(-1f, 1f)) {
        drawLine(white.copy(alpha = 0.8f), p(zero, side * (h + 1f)), p(zero, side * (h + 4f)), stroke)
    }
    if (value != null) {
        val m = position(value)
        drawLine(tint, p(m, -(h + 2f)), p(m, h + 2f), 2f.dp.toPx(), androidx.compose.ui.graphics.StrokeCap.Round)
    }
}

/** iOS `MonitorLevelBubble`: ±10° ring, 5° inner ring, centre cross, solid bead (amber / green). */
private fun DrawScope.drawBubble(centre: Offset, x: Double, y: Double, measurer: TextMeasurer) {
    val r = LiveLevel.BUBBLE_RADIUS.dp.toPx()
    drawCircle(Color.White.copy(alpha = 0.22f), radius = r, center = centre, style = Stroke(2f.dp.toPx()))
    drawCircle(Color.White.copy(alpha = 0.34f), radius = r / 2, center = centre, style = Stroke(1f.dp.toPx()))
    val arm = 9f.dp.toPx()
    drawLine(Color.White.copy(alpha = 0.75f), Offset(centre.x - arm, centre.y), Offset(centre.x + arm, centre.y), 2f.dp.toPx())
    drawLine(Color.White.copy(alpha = 0.75f), Offset(centre.x, centre.y - arm), Offset(centre.x, centre.y + arm), 2f.dp.toPx())
    val distance = sqrt(x * x + y * y)
    val isLevel = distance < LiveLevel.THRESHOLD
    val clamp = if (distance > LiveLevel.BUBBLE_SPAN) LiveLevel.BUBBLE_SPAN / distance else 1.0
    val bead = Offset(
        centre.x + (x * clamp / LiveLevel.BUBBLE_SPAN).toFloat() * r,
        centre.y - (y * clamp / LiveLevel.BUBBLE_SPAN).toFloat() * r,
    )
    drawCircle(Color.Black.copy(alpha = 0.5f), radius = 8f.dp.toPx(), center = bead)
    drawCircle(if (isLevel) LiveLevel.good else LiveDesign.amber, radius = 6.5f.dp.toPx(), center = bead)
    drawCircle(Color.Black.copy(alpha = 0.45f), radius = 6.5f.dp.toPx(), center = bead, style = Stroke(2f.dp.toPx()))
    text(measurer, "${LiveLevel.label(x)} / ${LiveLevel.label(y)}", Offset(centre.x, centre.y + r + 14f.dp.toPx()),
        if (isLevel) LiveLevel.good else LiveDesign.text.copy(alpha = 0.85f), 11f, bold = true, shadow = false)
}
