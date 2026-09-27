package com.opencapture.openpocketcine.monitor

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorLinkHealth
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.monitorGlass

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
    val bars = signalBars.coerceIn(0, 4)
    val linkColor = MonitorLinkHealth.color(MonitorLinkHealth.score(bars))
    val gauges: @Composable () -> Unit = {
        TelemetryGauge(OpcIcon.SIGNAL, linkColor, bars / 4f, "Live link $signalBars of 4 delivery bars", horizontal)
        // Whole frames with a unit; RECOV / LINK / — pass through.
        TelemetryGauge(OpcIcon.VIDEO, linkColor, 0f, "Feed $fps frames per second", horizontal,
            fps.toDoubleOrNull()?.let { "${Math.round(it)} fps" } ?: fps)
        TelemetryGauge(OpcIcon.SMARTPHONE, batteryTint(phonePercent), phonePercent / 100f,
            if (phonePercent >= 0) "Phone battery $phonePercent percent" else "Phone battery unavailable",
            horizontal, phonePercent.takeIf { it in 0..100 }?.let { "$it%" } ?: "—")
        MonitorCameraBatteryGauge(cameraPercent, stacked = horizontal)
    }
    if (horizontal) Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) { gauges() }
    else Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) { gauges() }
}

/** Phone and camera batteries share one scale (matches iOS). */
private fun batteryTint(percent: Int): Color = when {
    percent !in 0..100 -> LiveDesign.text
    percent <= 20 -> LiveDesign.rec
    percent <= 40 -> LiveDesign.amber
    else -> LiveDesign.good
}

/** Live View and Multiview share the camera glyph and percentage. */
@Composable
fun MonitorCameraBatteryGauge(percent: Int, stacked: Boolean = false) {
    TelemetryGauge(OpcIcon.CAMERA, batteryTint(percent), if (percent in 0..100) percent / 100f else 0f,
        if (percent in 0..100) "Camera battery $percent percent" else "Camera battery unavailable",
        stacked, percent.takeIf { it in 0..100 }?.let { "$it%" } ?: "—")
}

/**
 * One glass pill per gauge, styled like the Live View buttons: white icon beside
 * the value, status color on the value only. One width fits the widest value.
 */
@Composable
private fun TelemetryGauge(
    icon: OpcIcon, tint: Color, fraction: Float, label: String,
    stacked: Boolean, value: String? = null,
) {
    Row(
        Modifier
            .size(54.dp, 17.dp)
            .monitorGlass(RoundedCornerShape(7.dp))
            .padding(horizontal = 6.dp)
            .semantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        OpcIcon(icon, contentDescription = null, tint = LiveDesign.text, modifier = Modifier.size(10.dp))
        if (value != null) {
            Text(value, color = tint, style = LiveType.mono(9f, FontWeight.Bold), maxLines = 1)
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(1.5.dp)) {
                repeat(4) { index ->
                    Box(
                        Modifier.size(3.dp, 8.dp).background(
                            tint.copy(alpha = if (fraction >= (index + 1) / 4f) 1f else .2f),
                            RoundedCornerShape(.75.dp),
                        ),
                    )
                }
            }
        }
    }
}
