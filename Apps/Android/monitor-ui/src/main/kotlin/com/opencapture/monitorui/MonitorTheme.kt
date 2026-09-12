package com.opencapture.monitorui

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Shared monitor engine tokens. Brand shells supply identity separately. */
object MonitorPalette {
    val background = Color(0xFF111213)
    val backgroundDeep = Color(0xFF08090A)
    val surface = Color(0xFF1A1B1C)
    val tile = Color(0xFF232527)
    /** Dense modal tint suppresses underlying text without sampling a blurred frame. */
    val overlayPanel = Color(0xFF141618).copy(alpha = .96f)
    val accent = Color(0xFF00A3E0)
    val text = Color.White
    val muted = Color(0xFF8D9293)
    val faint = Color(0xFF5E6262)
    val recording = Color(0xFFD13034)
}

object MonitorTypography {
    val fontFamily = FontFamily(
        Font(R.font.sora_regular, FontWeight.Normal),
        Font(R.font.sora_medium, FontWeight.Medium),
        Font(R.font.sora_semibold, FontWeight.SemiBold),
        Font(R.font.sora_bold, FontWeight.Bold),
    )

    fun text(size: Float, weight: FontWeight = FontWeight.Normal): TextStyle =
        TextStyle(fontFamily = fontFamily, fontWeight = weight, fontSize = size.sp, color = MonitorPalette.text)

    fun readout(size: Float, weight: FontWeight = FontWeight.Medium): TextStyle =
        text(size, weight).copy(fontFeatureSettings = "tnum")
}

/** Additive capabilities are supplied by an adapter, never inferred from a brand here. */
@Immutable
data class MonitorCapabilities(
    val gimbal: Boolean = false,
    val zoom: Boolean = false,
    val focus: Boolean = false,
    val timecode: Boolean = false,
    val clipDelete: Boolean = false,
    val clipStar: Boolean = false,
)
