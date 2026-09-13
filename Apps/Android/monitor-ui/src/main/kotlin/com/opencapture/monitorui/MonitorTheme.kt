package com.opencapture.monitorui

import androidx.compose.runtime.Immutable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
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
    /** Mockup panel RGB (20,22,24). Alphas follow compact / expanded / share plates. */
    val panel = Color(20, 22, 24)
    val compactGlass = panel.copy(alpha = .52f)
    val expandedGlass = panel.copy(alpha = .62f)
    /** Share / dense info plates. Capture drawers use [expandedGlass]. */
    val overlayPanel = panel.copy(alpha = .86f)
    val zoomGlass = Color(18, 20, 22).copy(alpha = .72f)
    val recHousing = Color.White.copy(alpha = .08f)
    val accent = Color(0xFF00A3E0)
    val text = Color.White
    val muted = Color(0xFF8D9293)
    val faint = Color(0xFF5E6262)
    val recording = Color(0xFFD13034)
}

/** Darker, tighter readout halo than the mockup's 5+12 bloom. */
fun TextStyle.monitorReadoutGlow(): TextStyle = copy(
    shadow = Shadow(Color.Black.copy(alpha = .92f), Offset(0f, 1f), blurRadius = 6f),
)

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
