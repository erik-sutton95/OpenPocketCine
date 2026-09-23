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
 * `FeedLevelView`: OpenZCine two-axis gauge (roll bottom, tilt right) and a
 * bubble near plumb. Stale or missing attitude reads `No level data`, never green.
 */
internal object LiveLevel {
    const val REFRESH_MS = 100L
    const val WORLD_CAPTION = "WORLD"
    const val THRESHOLD = 0.6
    const val MAX_ANGLE = 8.0
    const val AXIS_SPAN = 84f
    const val BUBBLE_SPAN = 10.0
    const val BUBBLE_RADIUS = 64f

    fun visible(feed: ChromeRect, viewport: ChromeRect): ChromeRect {
        val x = maxOf(feed.minX, viewport.minX)
        val y = maxOf(feed.minY, viewport.minY)
        val w = minOf(feed.maxX, viewport.maxX) - x
        val h = minOf(feed.maxY, viewport.maxY) - y
        return if (w <= 0f || h <= 0f) feed else ChromeRect(x, y, w, h)
    }

    data class Seats(val roll: Pair<Float, Float>, val tilt: Pair<Float, Float>)

    /** OpenZCine #47: seat against the on-screen part of the feed (dp). */
    fun seats(feed: ChromeRect, viewport: ChromeRect, portrait: Boolean): Seats {
        val v = visible(feed, viewport)
        return Seats(v.midX to v.maxY - if (portrait) 30f else 104f, v.maxX - 44f to v.midY)
    }

    fun accessibilityLabel(mode: LevelMode): String = when (mode) {
        LevelMode.Unavailable -> "Level, ${WorldLevelSnap.NO_LEVEL_DATA}"
        is LevelMode.Gauges -> String.format(Locale.ROOT, "Level, roll %+.1f°, tilt %+.1f°", mode.rollDeg, mode.tiltDeg)
        is LevelMode.Bubble -> String.format(Locale.ROOT, "Level, off plumb %+.1f° / %+.1f°", mode.xDeg, mode.yDeg)
    }

    fun format(value: Double): String = String.format(Locale.ROOT, "%+.1f°", if (abs(value) < 0.05) 0.0 else value)
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
    Canvas(modifier.fillMaxSize().semantics { contentDescription = LiveLevel.accessibilityLabel(mode) }) {
        val seats = LiveLevel.seats(feed, viewport, portrait)
        fun at(p: Pair<Float, Float>) = Offset(p.first.dp.toPx(), p.second.dp.toPx())
        when (val m = mode) {
            is LevelMode.Bubble -> {
                val v = LiveLevel.visible(feed, viewport)
                val centre = Offset(v.midX.dp.toPx(), v.midY.dp.toPx())
                drawBubble(centre, m.xDeg, m.yDeg, measurer)
                caption(measurer, LiveLevel.WORLD_CAPTION, Offset(centre.x, centre.y + (LiveLevel.BUBBLE_RADIUS + 30f).dp.toPx()))
            }
            is LevelMode.Gauges -> {
                drawAxis(at(seats.roll), horizontal = true, m.rollDeg, measurer)
                drawAxis(at(seats.tilt), horizontal = false, m.tiltDeg, measurer)
                caption(measurer, LiveLevel.WORLD_CAPTION, at(seats.roll) + Offset(0f, 20f.dp.toPx()))
            }
            LevelMode.Unavailable -> {
                drawAxis(at(seats.roll), horizontal = true, null, measurer)
                drawAxis(at(seats.tilt), horizontal = false, null, measurer)
                caption(measurer, WorldLevelSnap.NO_LEVEL_DATA, at(seats.roll) + Offset(0f, 20f.dp.toPx()))
            }
        }
    }
}

private fun DrawScope.readout(measurer: TextMeasurer, text: String, centre: Offset, color: Color, size: Float = 11f) {
    val style = TextStyle(color = color, fontSize = size.sp, fontFamily = OpcFonts.sora, fontWeight = FontWeight.SemiBold)
    val layout = measurer.measure(text, style)
    drawText(layout, topLeft = Offset(centre.x - layout.size.width / 2f, centre.y - layout.size.height / 2f))
}

private fun DrawScope.caption(measurer: TextMeasurer, text: String, centre: Offset) =
    readout(measurer, text, centre, LiveDesign.muted, 9f)

private fun DrawScope.drawBead(centre: Offset, tint: Color) {
    drawCircle(Color.Black.copy(alpha = 0.5f), radius = 8f.dp.toPx(), center = centre)
    drawCircle(tint, radius = 6.5f.dp.toPx(), center = centre)
    drawCircle(Color.Black.copy(alpha = 0.45f), radius = 6.5f.dp.toPx(), center = centre, style = Stroke(2f.dp.toPx()))
}

/** OpenZCine `drawGaugeAxis`; `value == null` draws the bare track with `--`. */
private fun DrawScope.drawAxis(seat: Offset, horizontal: Boolean, value: Double?, measurer: TextMeasurer) {
    val span = LiveLevel.AXIS_SPAN.dp.toPx()
    fun along(t: Float) = if (horizontal) Offset(seat.x + t, seat.y) else Offset(seat.x, seat.y - t)
    drawLine(Color.White.copy(alpha = 0.22f), along(-span), along(span), 2f.dp.toPx())
    var deg = -LiveLevel.MAX_ANGLE
    while (deg <= LiveLevel.MAX_ANGLE + 0.001) {
        val c = along((deg / LiveLevel.MAX_ANGLE).toFloat() * span)
        val centre = abs(deg) < 0.001
        val half = (if (centre) 9f else 5f).dp.toPx()
        val a = if (horizontal) Offset(c.x, c.y - half) else Offset(c.x - half, c.y)
        val b = if (horizontal) Offset(c.x, c.y + half) else Offset(c.x + half, c.y)
        drawLine(Color.White.copy(alpha = if (centre) 0.75f else 0.34f), a, b, (if (centre) 2f else 1f).dp.toPx())
        deg += 2.0
    }
    val readoutAt = if (horizontal) Offset(seat.x, seat.y - 24f.dp.toPx()) else Offset(seat.x - 42f.dp.toPx(), seat.y)
    if (value == null) {
        readout(measurer, "--", readoutAt, LiveDesign.muted)
        return
    }
    val isLevel = abs(value) < LiveLevel.THRESHOLD
    val tint = if (isLevel) LiveDesign.good else LiveDesign.amber
    val bead = along((value / LiveLevel.MAX_ANGLE).coerceIn(-1.0, 1.0).toFloat() * span)
    drawBead(bead, tint)
    if (!isLevel) {
        val sign = if (value > 0) 1f else -1f
        val urgency = when (abs(value)) {
            in 0.0..<LiveLevel.MAX_ANGLE / 3 -> 1
            in LiveLevel.MAX_ANGLE / 3..<LiveLevel.MAX_ANGLE * 2 / 3 -> 2
            else -> 3
        }
        val half = 3f.dp.toPx()
        repeat(urgency) { i ->
            val t = -sign * (16f + 8f * i).dp.toPx()
            val c = if (horizontal) Offset(bead.x + t, bead.y) else Offset(bead.x, bead.y - t)
            val color = LiveDesign.amber.copy(alpha = 1f - i * 0.22f)
            // Chevron points back toward level (toward the centre tick).
            val tip = if (horizontal) Offset(c.x - sign * half, c.y) else Offset(c.x, c.y + sign * half)
            val w1 = if (horizontal) Offset(c.x + sign * half, c.y - half) else Offset(c.x - half, c.y - sign * half)
            val w2 = if (horizontal) Offset(c.x + sign * half, c.y + half) else Offset(c.x + half, c.y - sign * half)
            drawLine(color, w1, tip, 1.5f.dp.toPx())
            drawLine(color, tip, w2, 1.5f.dp.toPx())
        }
    }
    readout(measurer, LiveLevel.format(value), readoutAt, if (isLevel) LiveDesign.good else LiveDesign.text.copy(alpha = 0.85f))
}

/** Lens offset from plumb: ±10° ring, 5° inner ring, bead toward the high side. */
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
    drawBead(bead, if (isLevel) LiveDesign.good else LiveDesign.amber)
    readout(measurer, "${LiveLevel.format(x)} / ${LiveLevel.format(y)}", Offset(centre.x, centre.y + r + 14f.dp.toPx()),
        if (isLevel) LiveDesign.good else LiveDesign.text.copy(alpha = 0.85f))
}
