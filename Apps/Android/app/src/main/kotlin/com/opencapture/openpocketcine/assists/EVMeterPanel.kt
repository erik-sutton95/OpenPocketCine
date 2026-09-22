package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.OpcFonts
import com.opencapture.openpocketcine.feed.ScopeAssistBundle

@Composable
internal fun EVMeterPanel(
    state: LiveAssistState,
    modifier: Modifier = Modifier,
    previewBundle: ScopeAssistBundle? = null,
) {
    val reading = EVMeterReading.from(previewBundle ?: state.scopeBundle)
    val measurer = rememberTextMeasurer()
    Canvas(modifier.fillMaxSize().semantics { contentDescription = reading.accessibilityLabel }) {
        val scale = minOf(size.width / ScopePanelSize.evMeter.width, size.height / ScopePanelSize.evMeter.height)
        val pad = 12f * scale
        val left = pad
        val right = size.width - pad
        val baseline = 38f * scale
        val textStyle = TextStyle(
            color = LiveDesign.text,
            fontSize = (10f * scale / density).sp,
            fontFamily = OpcFonts.sora,
            fontWeight = FontWeight.SemiBold,
        )
        drawText(measurer, reading.title, Offset(pad, 5f * scale), textStyle)
        val value = measurer.measure(reading.label, textStyle.copy(fontSize = (15f * scale / density).sp))
        drawText(value, topLeft = Offset(right - value.size.width, 5f * scale))
        val tickColor = LiveDesign.text.copy(alpha = 0.55f)
        drawLine(tickColor, Offset(left, baseline), Offset(right, baseline), scale)
        for (tick in -9..9) {
            val x = left + (right - left) * (tick + 9) / 18f
            val height = if (tick % 3 == 0) 8f else 4f
            drawLine(tickColor, Offset(x, baseline - height * scale), Offset(x, baseline), scale)
        }
        val labelStyle = textStyle.copy(fontSize = (9f * scale / density).sp, color = tickColor)
        listOf("−3" to left, "0" to (left + right) / 2, "+3" to right).forEach { (label, x) ->
            val layout = measurer.measure(label, labelStyle)
            drawText(layout, topLeft = Offset(x - layout.size.width / 2f, 43f * scale))
        }
        reading.needleFraction?.let { fraction ->
            val x = left + (right - left) * fraction
            drawLine(LiveDesign.accent, Offset(x, 24f * scale), Offset(x, 40f * scale),
                2f * scale, StrokeCap.Round)
        }
    }
}
