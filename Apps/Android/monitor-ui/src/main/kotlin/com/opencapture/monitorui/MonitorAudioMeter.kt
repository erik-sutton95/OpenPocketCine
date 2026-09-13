package com.opencapture.monitorui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
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

/** Mockup `SCOPE_SIZE.AUDIO` 28×168. dB overlays the bars; the plate does not grow. */
object MonitorAudioMetrics {
    const val CROSS_AXIS = 28f
    const val LONG_AXIS = 168f
    const val GAP = 2f
    const val INSET = 1f
    const val LABEL_RESERVE = 12f
    const val BARS_TOP = 2f

    fun panelWidth(orientation: MonitorAudioOrientation): Float =
        if (orientation == MonitorAudioOrientation.VERTICAL) CROSS_AXIS else LONG_AXIS

    fun panelHeight(orientation: MonitorAudioOrientation): Float =
        if (orientation == MonitorAudioOrientation.VERTICAL) LONG_AXIS else CROSS_AXIS
}

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
        val green = Color(0xFF56EB84)
        val yellow = Color(0xFFF5D052)
        val red = Color(0xFFFF5C52)
        val ink = Color.White
        fun zone(db: Double): Color = when {
            db >= -6.0 -> red.copy(alpha = .95f)
            db >= -18.0 -> yellow.copy(alpha = .95f)
            else -> green.copy(alpha = .9f)
        }
        fun text(label: String, at: Offset, center: Boolean = false) {
            val layout = measurer.measure(label, MonitorTypography.readout(7.5f, FontWeight.Bold), maxLines = 1)
            drawText(layout, color = ink.copy(alpha = .58f),
                topLeft = Offset(at.x - if (center) layout.size.width / 2f else 0f,
                    at.y - layout.size.height / 2f))
        }
        val channels = listOf(Triple("L", left, leftPeak), Triple("R", right, rightPeak))
        if (horizontal) {
            val barsL = MonitorAudioMetrics.LABEL_RESERVE.dp.toPx()
            val gap = MonitorAudioMetrics.GAP.dp.toPx()
            val inset = MonitorAudioMetrics.INSET.dp.toPx()
            val trackH = (size.height - gap - inset * 2f) / 2f
            val trackW = (size.width - barsL - inset).coerceAtLeast(1f)
            channels.forEachIndexed { index, channel ->
                val y = inset + index * (trackH + gap)
                val origin = Offset(barsL, y)
                val track = Size(trackW, trackH)
                drawRoundRect(ink.copy(alpha = .08f), origin, track, CornerRadius(2.dp.toPx()))
                val value = MonitorAudioReadout.fraction(channel.second)
                if (value > 0f) {
                    val filled = trackW * value
                    drawRoundRect(zone(channel.second), origin, Size(filled, trackH), CornerRadius(2.dp.toPx()))
                }
                val peak = MonitorAudioReadout.fraction(channel.third)
                if (peak > 0f) {
                    val px = origin.x + trackW * peak
                    drawLine(zone(channel.third), Offset(px, origin.y), Offset(px, origin.y + trackH), 1.5.dp.toPx())
                }
                text(channel.first, Offset(barsL / 2f, origin.y + trackH / 2f), center = true)
                if (showDB) text(MonitorAudioReadout.label(channel.second),
                    Offset(origin.x + trackW - 10.dp.toPx(), origin.y + trackH / 2f), center = true)
            }
        } else {
            val gap = MonitorAudioMetrics.GAP.dp.toPx()
            val inset = MonitorAudioMetrics.INSET.dp.toPx()
            val barsT = MonitorAudioMetrics.BARS_TOP.dp.toPx()
            val barsH = (size.height - MonitorAudioMetrics.LABEL_RESERVE.dp.toPx()).coerceAtLeast(1f)
            val bw = (size.width - gap - inset * 2f) / 2f
            listOf(0.0, -6.0, -18.0, -36.0).forEach { mark ->
                val gy = barsT + barsH * (1f - MonitorAudioReadout.fraction(mark))
                drawLine(ink.copy(alpha = .10f), Offset(0f, gy), Offset(size.width, gy), 1.dp.toPx())
            }
            channels.forEachIndexed { index, channel ->
                val x = inset + index * (bw + gap)
                val origin = Offset(x, barsT)
                val track = Size(bw, barsH)
                drawRoundRect(ink.copy(alpha = .08f), origin, track, CornerRadius(2.dp.toPx()))
                val value = MonitorAudioReadout.fraction(channel.second)
                if (value > 0f) {
                    val filled = barsH * value
                    drawRoundRect(zone(channel.second), Offset(x, barsT + barsH - filled), Size(bw, filled),
                        CornerRadius(2.dp.toPx()))
                }
                val peak = MonitorAudioReadout.fraction(channel.third)
                if (peak > 0f) {
                    val py = barsT + barsH * (1f - peak)
                    drawLine(zone(channel.third), Offset(x, py), Offset(x + bw, py), 1.5.dp.toPx())
                }
                text(channel.first, Offset(x + bw / 2f, size.height - 5.dp.toPx()), center = true)
                if (showDB) text(MonitorAudioReadout.label(channel.second),
                    Offset(x + bw / 2f, barsT + 8.dp.toPx()), center = true)
            }
        }
    }
}
