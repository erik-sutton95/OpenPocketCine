package com.opencapture.openpocketcine

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial

/** Camera telemetry only; this never reads the configured compensation or sampled picture. */
internal class CameraExposureMeter(raw: Int, available: Boolean = true) {
    private val value = EvComp.fromRaw(raw).takeIf { available }
    val stops: Double? = value?.thirds?.div(3.0)
    val label: String = value?.label ?: "—"
    /** Top is +3, bottom is −3. */
    val needleFraction: Float? = value?.thirds?.let { (9 - it) / 18f }
    val accessibilityLabel: String =
        if (value == null) "Camera exposure meter, unavailable" else "Camera exposure meter, $label EV"

    companion object {
        fun frame(feed: ChromeRect, mode: PocketDispMode, avoid: ChromeRect? = null): ChromeRect? {
            if (mode != PocketDispMode.LIVE || feed.width < 48f || feed.height < 60f) return null
            val x = feed.minX + 6f
            var height = minOf(156f, feed.height - 12f)
            if (avoid != null && avoid.minX < x + 36f && avoid.maxX > x && avoid.minY > feed.midY) {
                val clearanceHeight = 2f * (avoid.minY - feed.midY - 8f)
                height = minOf(height, maxOf(minOf(60f, feed.height - 12f), clearanceHeight))
            }
            return ChromeRect(x, feed.midY - height / 2, 36f, height)
        }
    }
}

/** Fixed to the visible feed's left edge in DISP 1; it has no pointer handlers or saved placement. */
@Composable
internal fun LiveCameraExposureMeter(
    raw: Int,
    available: Boolean,
    feed: ChromeRect,
    mode: PocketDispMode,
    modifier: Modifier = Modifier,
    avoid: ChromeRect? = null,
) {
    val frame = CameraExposureMeter.frame(feed, mode, avoid) ?: return
    val reading = CameraExposureMeter(raw, available)
    val measurer = rememberTextMeasurer()
    Canvas(
        modifier.offset(frame.x.dp, frame.y.dp).size(frame.width.dp, frame.height.dp)
            .monitorMaterial(MonitorMaterial.Scope, RoundedCornerShape(6.dp))
            .semantics { contentDescription = reading.accessibilityLabel },
    ) {
        // Short landscape plates keep legible text; only the tick span compresses.
        val scale = size.width / 36f
        val style = TextStyle(
            color = LiveDesign.text,
            fontSize = (11f * scale / density).sp,
            fontFamily = OpcFonts.sora,
            fontWeight = FontWeight.SemiBold,
        )
        val number = measurer.measure(reading.label, style)
        drawText(number, topLeft = Offset((size.width - number.size.width) / 2, 5f * scale))
        val captionStyle = style.copy(fontSize = (8f * scale / density).sp, color = LiveDesign.muted)
        val caption = measurer.measure("EV", captionStyle)
        drawText(caption, topLeft = Offset((size.width - caption.size.width) / 2, 21f * scale))
        val bottom = size.height - 12f * scale
        val top = minOf(42f * scale, bottom)
        val span = bottom - top
        val axisX = 8f * scale
        val axisColor = LiveDesign.text.copy(alpha = .55f)
        drawLine(axisColor, Offset(axisX, top), Offset(axisX, bottom), scale)
        val tickStep = if (span < 60f * scale) 3 else 1
        for (tick in 0..18 step tickStep) {
            val y = top + span * tick / 18f
            val length = if (tick % 3 == 0) 7f else 4f
            drawLine(axisColor, Offset(axisX, y), Offset(axisX + length * scale, y), scale)
        }
        listOf("+3" to top, "0" to (top + bottom) / 2, "−3" to bottom).forEach { (label, y) ->
            val layout = measurer.measure(label, captionStyle)
            drawText(layout, topLeft = Offset(19f * scale, y - layout.size.height / 2))
        }
        reading.needleFraction?.let { fraction ->
            val y = top + span * fraction
            drawLine(LiveDesign.accent, Offset(4f * scale, y), Offset(17f * scale, y),
                2f * scale, StrokeCap.Round)
        }
    }
}
