package com.opencapture.openpocketcine.monitor

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon

/** Draw-only readouts. The adapter supplies its existing delivery-health mapping. */
@Composable
fun MonitorTelemetry(
    signalBars: Int,
    fps: String,
    phonePercent: Int,
    cameraPercent: Int,
    horizontal: Boolean,
    modifier: Modifier = Modifier,
) {
    val gauges: @Composable () -> Unit = {
        TelemetryGauge(OpcIcon.SIGNAL, LiveDesign.accent, signalBars.coerceIn(0, 4) / 4f,
            "Live view $fps frames per second, $signalBars of 4 delivery bars", horizontal)
        TelemetryGauge(OpcIcon.SMARTPHONE, Color(0xFF3FE0C7), phonePercent / 100f,
            if (phonePercent >= 0) "Phone battery $phonePercent percent" else "Phone battery unavailable",
            horizontal, phonePercent.takeIf { it in 0..100 }?.toString())
        TelemetryGauge(OpcIcon.CAMERA, LiveDesign.amber, cameraPercent / 100f,
            if (cameraPercent >= 0) "Camera battery $cameraPercent percent" else "Camera battery unavailable", horizontal)
    }
    if (horizontal) Row(modifier, horizontalArrangement = Arrangement.spacedBy(10.dp)) { gauges() }
    else Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) { gauges() }
}

@Composable
private fun TelemetryGauge(
    icon: OpcIcon, tint: Color, fraction: Float, label: String,
    stacked: Boolean, value: String? = null,
) {
    val content: @Composable () -> Unit = {
        OpcIcon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(9.dp))
        Box(Modifier.size(28.dp, 14.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.matchParentSize()) {
                val line = 1.dp.toPx()
                drawRoundRect(tint, cornerRadius = CornerRadius(2.dp.toPx()), style = Stroke(line))
                if (value == null) {
                    val inset = 3.dp.toPx()
                    val gap = 1.5.dp.toPx()
                    val width = (size.width - 2 * inset - 4 * gap) / 5
                    repeat(5) { index ->
                        drawRoundRect(tint.copy(alpha = if (fraction >= (index + 1) / 5f) 1f else .15f),
                            topLeft = Offset(inset + index * (width + gap), inset),
                            size = Size(width, size.height - 2 * inset), cornerRadius = CornerRadius(.7.dp.toPx()))
                    }
                }
            }
            if (value != null) Text(value, color = tint, style = LiveType.mono(8f, FontWeight.Bold), maxLines = 1)
        }
    }
    if (stacked) Column(Modifier.semantics { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) { content() }
    else Row(Modifier.semantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) { content() }
}
