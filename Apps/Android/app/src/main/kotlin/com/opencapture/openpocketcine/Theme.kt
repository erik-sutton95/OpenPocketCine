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
    val accent: Color = Color(0xFF00A3E0)
    val accentSoft: Color = Color(0f, 163 / 255f, 230 / 255f, 0.18f)
    val background: Color = Color(20 / 255f, 20 / 255f, 20 / 255f)
    val backgroundDeep: Color = Color(14 / 255f, 14 / 255f, 14 / 255f)
    val surface: Color = Color(28 / 255f, 28 / 255f, 28 / 255f)
    val tile: Color = Color(36 / 255f, 36 / 255f, 36 / 255f)
    val ink: Color = Color.White
    val darkText: Color = Color(20 / 255f, 20 / 255f, 20 / 255f)
    val muted: Color = Color(160 / 255f, 165 / 255f, 165 / 255f)
    val titan: Color = Color(94 / 255f, 98 / 255f, 98 / 255f)
}

object OpcFonts {
    val sora =
        FontFamily(
            Font(R.font.sora_medium, FontWeight.Medium),
            Font(R.font.sora_semibold, FontWeight.SemiBold),
            Font(R.font.sora_bold, FontWeight.Bold),
        )
    val plex =
        FontFamily(
            Font(R.font.ibm_plex_sans_regular, FontWeight.Normal),
            Font(R.font.ibm_plex_sans_medium, FontWeight.Medium),
            Font(R.font.ibm_plex_sans_semibold, FontWeight.SemiBold),
            Font(R.font.ibm_plex_sans_bold, FontWeight.Bold),
        )
    val mono = FontFamily.Monospace
}

/** iOS `LiveType.ui(design:)`. Rounded is the startup/home face. */
enum class LiveTypeDesign {
    Default,
    Rounded,
    Monospaced,
}

/**
 * Landing-page type, same as iOS `LiveType`: Sora for titles, IBM Plex Sans
 * for body / chrome. Camera readouts stay platform mono (`LiveType.mono`),
 * matching iOS SF Mono via `.system(..., design: .monospaced)`.
 */
object LiveType {
    fun display(size: Float, weight: FontWeight = FontWeight.SemiBold) =
        TextStyle(fontFamily = OpcFonts.sora, fontWeight = weight, fontSize = size.sp, color = LiveDesign.text)

    fun title(size: Float, weight: FontWeight = FontWeight.SemiBold) = display(size, weight)

    fun text(size: Float, weight: FontWeight = FontWeight.Normal) =
        TextStyle(fontFamily = OpcFonts.plex, fontWeight = weight, fontSize = size.sp, color = LiveDesign.text)

    fun ui(
        size: Float,
        weight: FontWeight = FontWeight.Normal,
        design: LiveTypeDesign = LiveTypeDesign.Default,
    ): TextStyle {
        if (design == LiveTypeDesign.Monospaced) return mono(size, weight)
        val titleWeight = weight >= FontWeight.SemiBold
        val useSora =
            when (design) {
                LiveTypeDesign.Rounded -> titleWeight || size >= 16f
                LiveTypeDesign.Default -> titleWeight && size >= 17f
                LiveTypeDesign.Monospaced -> false
            }
        return if (useSora) display(size, weight) else text(size, weight)
    }

    fun mono(size: Float, weight: FontWeight = FontWeight.Medium) =
        TextStyle(fontFamily = OpcFonts.mono, fontWeight = weight, fontSize = size.sp, color = LiveDesign.text)
}

object LiveDesign {
    val background = Color(20 / 255f, 20 / 255f, 20 / 255f)
    val backgroundDeep = Color(14 / 255f, 14 / 255f, 14 / 255f)
    /**
     * Scope plate — DJI black at 72%. Compose frame and Vulkan plot fill
     * use this exact RGBA so WAVE / PARADE / VECTOR don't read as a cutout.
     */
    val scopePlate = Color(20 / 255f, 20 / 255f, 20 / 255f, 0.72f)
    val surface = Color(28 / 255f, 28 / 255f, 28 / 255f)
    val tile = Color(36 / 255f, 36 / 255f, 36 / 255f)
    val glass = Color(0f, 0f, 0f, 0.24f)
    val glassOpaque = Color(0f, 0f, 0f, 0.38f)
    val chromePlate = Color(0f, 0f, 0f, 0.34f)
    val chromeTint = Color(0f, 0f, 0f, 0.42f)
    /** Playback transport plate — dense DJI black so type reads over the clip. */
    val playbackPanel = Color(0f, 0f, 0f, 0.82f)
    /** Playback transport bar — 50% of HUD ND so the clip reads through. */
    val playbackBarPlate = Color(0f, 0f, 0f, 0.17f)
    val playbackBarTint = Color(0f, 0f, 0f, 0.21f)
    /** FLAT playback fallback — darkened bars so chrome reads over a bright clip. */
    val playbackScrim = Color(0f, 0f, 0f, 0.72f)
    /** Extra ND on picker / assist cards — a tad denser than HUD bars. */
    val pickerNd = Color(0f, 0f, 0f, 0.20f)
    /** Share / confirm sheets — DJI black, nearly opaque so type reads over a clip. */
    val sheetPlate = Color(20 / 255f, 20 / 255f, 20 / 255f, 0.94f)
    val sheetScrim = Color(0f, 0f, 0f, 0.48f)
    val glassBright = Color(94 / 255f, 98 / 255f, 98 / 255f, 0.18f)
    val text = Color.White
    val muted = Color(160 / 255f, 165 / 255f, 165 / 255f)
    val faint = Color(94 / 255f, 98 / 255f, 98 / 255f)
    val accent = Color(0f, 163 / 255f, 230 / 255f)
    val good = Color(0.18f, 0.78f, 0.42f)
    val rec = Color(0.82f, 0.20f, 0.23f)
    val info = Color(0.10f, 0.58f, 0.98f)
    val amber = Color(0.914f, 0.674f, 0.208f)
    val accentDim = Color(0f, 163 / 255f, 230 / 255f, 0.16f)
    val hairlineStrong = Color(94 / 255f, 98 / 255f, 98 / 255f, 0.70f)
    val hairline = Color(94 / 255f, 98 / 255f, 98 / 255f, 0.45f)
    val recordWell = Color(44 / 255f, 43 / 255f, 43 / 255f)
    val pocketRing = Color(227 / 255f, 83 / 255f, 70 / 255f)
    val feedWell = Color.Black

    const val CORNER_RADIUS_DP = 16f
    const val CONTROL_HEIGHT_DP = 58f
    const val LOCK_SIZE_DP = 40f
    const val RECORD_SIZE_DP = 82.8f
    const val AUX_SIZE_DP = 63.25f
    const val DISP_WIDTH_DP = 73.6f
    const val DISP_HEIGHT_DP = 43.7f
    const val RAIL_WIDTH_DP = 82.8f
    const val ZOOM_CHIP_DP = 44f
    const val GIMBAL_STICK_DP = 88f
    const val GIMBAL_KNOB_DP = 36f
    const val TOP_DECK_HEIGHT_DP = 46f
    const val FOCUS_RESET_DP = 40f
    const val TOP_PICKER_WIDTH_DP = 340f
    const val CAPTURE_PICKER_WIDTH_DP = 420f
}

private val OpcTypography =
    Typography(
        headlineLarge = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.Bold, fontSize = 28.sp),
        headlineMedium = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.SemiBold, fontSize = 22.sp),
        titleLarge = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.SemiBold, fontSize = 18.sp),
        titleMedium = TextStyle(fontFamily = OpcFonts.sora, fontWeight = FontWeight.Medium, fontSize = 16.sp),
        bodyLarge = TextStyle(fontFamily = OpcFonts.plex, fontWeight = FontWeight.Normal, fontSize = 16.sp),
        bodyMedium = TextStyle(fontFamily = OpcFonts.plex, fontWeight = FontWeight.Normal, fontSize = 14.sp),
        labelLarge = TextStyle(fontFamily = OpcFonts.plex, fontWeight = FontWeight.SemiBold, fontSize = 13.sp),
        labelMedium = TextStyle(fontFamily = OpcFonts.plex, fontWeight = FontWeight.Medium, fontSize = 12.sp),
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
