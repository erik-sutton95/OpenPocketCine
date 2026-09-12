package com.opencapture.monitorui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

enum class MonitorAudioOrientation(val label: String) { VERTICAL("Vertical"), HORIZONTAL("Horizontal") }

object MonitorAudioReadout {
    fun fraction(db: Double): Float = if (db.isFinite()) ((db + 60.0) / 60.0).coerceIn(0.0, 1.0).toFloat() else 0f
    fun label(db: Double): String = when {
        !db.isFinite() -> "—"
        db <= -60.0 -> "−∞"
        else -> db.coerceAtMost(0.0).roundToInt().toString().replace('-', '−')
    }
}

/** Presentation only: the caller supplies its authoritative channel levels and held peaks. */
@Composable
fun MonitorAudioMeter(left: Double, leftPeak: Double, right: Double, rightPeak: Double,
    orientation: MonitorAudioOrientation, showDB: Boolean, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.semantics {
        contentDescription = "Audio, left ${MonitorAudioReadout.label(left)} dBFS, right ${MonitorAudioReadout.label(right)} dBFS"
    }) {
        val horizontal = orientation == MonitorAudioOrientation.HORIZONTAL
        val pad = 9.dp.toPx()
        val labelH = 14.dp.toPx()
        val numberH = if (showDB) 14.dp.toPx() else 0f
        val green = Color(0xFF56EB84)
        val yellow = Color(0xFFF5D052)
        val red = Color(0xFFFF5C52)
        fun text(label: String, at: Offset, center: Boolean = false, muted: Boolean = false) {
            val layout = measurer.measure(label, MonitorTypography.readout(8f, FontWeight.Medium), maxLines = 1)
            drawText(layout, color = if (muted) MonitorPalette.muted else MonitorPalette.text,
                topLeft = Offset(at.x - if (center) layout.size.width / 2f else 0f, at.y))
        }
        text("AUDIO", Offset(pad, 6.dp.toPx()), muted = true)
        if (showDB) text("dBFS", Offset(size.width - 33.dp.toPx(), 6.dp.toPx()), muted = true)
        listOf(Triple("L", left, leftPeak), Triple("R", right, rightPeak)).forEachIndexed { index, channel ->
            val origin: Offset
            val track: Size
            if (horizontal) {
                origin = Offset(pad + 15.dp.toPx(), 27.dp.toPx() + index * 23.dp.toPx())
                track = Size((size.width - origin.x - pad - if (showDB) 31.dp.toPx() else 0f).coerceAtLeast(1f), 10.dp.toPx())
                text(channel.first, Offset(pad, origin.y - 2.dp.toPx()), muted = true)
                if (showDB) text(MonitorAudioReadout.label(channel.second), Offset(origin.x + track.width + 6.dp.toPx(), origin.y - 2.dp.toPx()))
            } else {
                val column = (size.width - pad * 2f) / 2f
                val centerX = pad + column * (index + .5f)
                origin = Offset(centerX - 8.dp.toPx(), 26.dp.toPx())
                track = Size(16.dp.toPx(), (size.height - origin.y - pad - labelH - numberH).coerceAtLeast(1f))
                text(channel.first, Offset(centerX, origin.y + track.height + 3.dp.toPx()), center = true, muted = true)
                if (showDB) text(MonitorAudioReadout.label(channel.second), Offset(centerX, origin.y + track.height + labelH), center = true)
            }
            drawRect(Color.White.copy(alpha = .07f), origin, track)
            val value = MonitorAudioReadout.fraction(channel.second)
            listOf(Triple(0f, .7f, green), Triple(.7f, .9f, yellow), Triple(.9f, 1f, red)).forEach { (low, high, color) ->
                val end = minOf(value, high)
                if (end > low) {
                    val at = if (horizontal) Offset(origin.x + track.width * low, origin.y)
                        else Offset(origin.x, origin.y + track.height * (1f - end))
                    val segment = if (horizontal) Size(track.width * (end - low), track.height)
                        else Size(track.width, track.height * (end - low))
                    drawRect(color, at, segment)
                }
            }
            val peak = MonitorAudioReadout.fraction(channel.third)
            if (peak > 0f) {
                val color = if (peak >= .9f) red else if (peak >= .7f) yellow else green
                if (horizontal) drawLine(color, Offset(origin.x + track.width * peak, origin.y),
                    Offset(origin.x + track.width * peak, origin.y + track.height), 1.5.dp.toPx())
                else drawLine(color, Offset(origin.x, origin.y + track.height * (1f - peak)),
                    Offset(origin.x + track.width, origin.y + track.height * (1f - peak)), 1.5.dp.toPx())
            }
        }
    }
}
