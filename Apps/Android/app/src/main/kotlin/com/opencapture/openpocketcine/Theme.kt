package com.opencapture.openpocketcine

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

object BrandColors {
    val accent: Color = com.opencapture.monitorui.MonitorPalette.accent
    val accentSoft: Color = Color(0x2E00A3E0)
    val background: Color = com.opencapture.monitorui.MonitorPalette.background
    val backgroundDeep: Color = com.opencapture.monitorui.MonitorPalette.backgroundDeep
    val surface: Color = com.opencapture.monitorui.MonitorPalette.surface
    val tile: Color = com.opencapture.monitorui.MonitorPalette.tile
    val ink: Color = Color.White
    val darkText: Color = com.opencapture.monitorui.MonitorPalette.background
    val muted: Color = com.opencapture.monitorui.MonitorPalette.muted
    val titan: Color = Color(94 / 255f, 98 / 255f, 98 / 255f)
}

object OpcFonts {
    val sora = com.opencapture.monitorui.MonitorTypography.fontFamily
    val plex =
        FontFamily(
            Font(R.font.ibm_plex_sans_regular, FontWeight.Normal),
            Font(R.font.ibm_plex_sans_medium, FontWeight.Medium),
            Font(R.font.ibm_plex_sans_semibold, FontWeight.SemiBold),
            Font(R.font.ibm_plex_sans_bold, FontWeight.Bold),
        )
    val mono = sora
}

/** Compatibility names for existing consumers; UI 2.0 uses Sora throughout. */
enum class LiveTypeDesign { Default, Rounded, Monospaced }

/** One optical family for every surface. Numeric readouts use tabular Sora figures. */
object LiveType {
    fun display(size: Float, weight: FontWeight = FontWeight.SemiBold) =
        com.opencapture.monitorui.MonitorTypography.text(size, weight)

    fun title(size: Float, weight: FontWeight = FontWeight.SemiBold) = display(size, weight)

    fun text(size: Float, weight: FontWeight = FontWeight.Normal) = display(size, weight)

    fun ui(size: Float, weight: FontWeight = FontWeight.Normal, design: LiveTypeDesign = LiveTypeDesign.Default): TextStyle =
        if (design == LiveTypeDesign.Monospaced) mono(size, weight) else display(size, weight)

    fun mono(size: Float, weight: FontWeight = FontWeight.Medium) =
        display(size, weight).copy(fontFeatureSettings = "tnum")
}

object LiveDesign {
    val background = com.opencapture.monitorui.MonitorPalette.background
    val backgroundDeep = com.opencapture.monitorui.MonitorPalette.backgroundDeep
    /**
     * Scope plate — DJI black at 72%. Compose frame and Vulkan plot fill
     * use this exact RGBA so WAVE / PARADE / VECTOR don't read as a cutout.
     */
    val scopePlate = Color(20 / 255f, 20 / 255f, 20 / 255f, 0.72f)
    val surface = com.opencapture.monitorui.MonitorPalette.surface
    val tile = com.opencapture.monitorui.MonitorPalette.tile
    val glass = surface
    val glassOpaque = surface
    val chromePlate = surface
    val chromeTint = surface
    /** Playback transport plate — dense DJI black so type reads over the clip. */
    val playbackPanel = surface
    /** Playback transport bar — 50% of HUD ND so the clip reads through. */
    val playbackBarPlate = surface
    val playbackBarTint = surface
    /** FLAT playback fallback — darkened bars so chrome reads over a bright clip. */
    val playbackScrim = Color(0f, 0f, 0f, 0.72f)
    /** Extra ND on picker / assist cards — a tad denser than HUD bars. */
    val pickerNd = Color(0f, 0f, 0f, 0.20f)
    /** Share / confirm sheets — DJI black, nearly opaque so type reads over a clip. */
    val sheetPlate = surface
    val sheetScrim = Color(0f, 0f, 0f, 0.48f)
    val glassBright = Color(94 / 255f, 98 / 255f, 98 / 255f, 0.18f)
    val text = Color.White
    val muted = com.opencapture.monitorui.MonitorPalette.muted
    val faint = Color(94 / 255f, 98 / 255f, 98 / 255f)
    val accent = com.opencapture.monitorui.MonitorPalette.accent
    val good = Color(0.18f, 0.78f, 0.42f)
    val rec = com.opencapture.monitorui.MonitorPalette.recording
    val info = accent
    val amber = Color(0.914f, 0.674f, 0.208f)
    val accentDim = Color(0x2900A3E0)
    val hairlineStrong = Color.White.copy(alpha = 0.10f)
    val hairline = Color.White.copy(alpha = 0.06f)
    val recordWell = Color(44 / 255f, 43 / 255f, 43 / 255f)
    val pocketRing = Color(227 / 255f, 83 / 255f, 70 / 255f)
    val feedWell = Color.Black

    const val CORNER_RADIUS_DP = 12f
    const val CONTROL_HEIGHT_DP = 44f
    const val LOCK_SIZE_DP = 54f
    const val RECORD_SIZE_DP = 70f
    const val AUX_SIZE_DP = 54f
    const val DISP_WIDTH_DP = 54f
    const val DISP_HEIGHT_DP = 54f
    const val RAIL_WIDTH_DP = 70f
    const val ZOOM_CHIP_DP = 44f
    const val GIMBAL_STICK_DP = 88f
    const val GIMBAL_KNOB_DP = 36f
    const val TOP_DECK_HEIGHT_DP = 35f
    const val FOCUS_RESET_DP = 40f
    const val TOP_PICKER_WIDTH_DP = 480f
    const val CAPTURE_PICKER_WIDTH_DP = 480f
}

private val OpcTypography =
    Typography(
        headlineLarge = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.Bold, fontSize = 28.sp),
        headlineMedium = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.SemiBold, fontSize = 22.sp),
        titleLarge = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.SemiBold, fontSize = 18.sp),
        titleMedium = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.Medium, fontSize = 16.sp),
        bodyLarge = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.Normal, fontSize = 16.sp),
        bodyMedium = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.Normal, fontSize = 14.sp),
        labelLarge = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.SemiBold, fontSize = 13.sp),
        labelMedium = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.Medium, fontSize = 12.sp),
    )

@Composable
fun OpenPocketCineTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme =
            darkColorScheme(
                primary = BrandColors.accent,
                background = BrandColors.background,
                surface = BrandColors.surface,
                onBackground = BrandColors.ink,
                onSurface = BrandColors.ink,
                onPrimary = BrandColors.darkText,
            ),
        typography = OpcTypography,
    ) {
        ProvideTextStyle(LiveType.text(16f), content)
    }
}
