package com.opencapture.openpocketcine.pairing

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.opencapture.openpocketcine.OpcIcon

/**
 * Pairing chrome glyphs. Names keep the old Canvas kinds so [StartupDesign] call
 * sites stay put; each maps to the shared Lucide catalog.
 */
enum class StartupGlyphKind {
    ANTENNA,
    PHONE_WAVES,
    CABLE,
    CAMERA,
    WIFI,
    SHIELD,
    APERTURE,
    PHONE,
    CHEVRON_LEFT,
    ;

    val opcIcon: OpcIcon
        get() =
            when (this) {
                ANTENNA -> OpcIcon.RADIO
                PHONE_WAVES -> OpcIcon.SIGNAL
                CABLE -> OpcIcon.UNPLUG
                CAMERA -> OpcIcon.CAMERA
                WIFI -> OpcIcon.WIFI
                SHIELD -> OpcIcon.LOCK
                APERTURE -> OpcIcon.APERTURE
                PHONE -> OpcIcon.SMARTPHONE
                CHEVRON_LEFT -> OpcIcon.CHEVRON_LEFT
            }
}

@Composable
fun StartupGlyph(
    kind: StartupGlyphKind,
    tint: Color,
    modifier: Modifier = Modifier,
) {
    OpcIcon(
        icon = kind.opcIcon,
        contentDescription = null,
        tint = tint,
        modifier = modifier,
    )
}
