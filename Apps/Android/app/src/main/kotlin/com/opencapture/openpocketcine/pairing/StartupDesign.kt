package com.opencapture.openpocketcine.pairing

import androidx.compose.foundation.background
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.opencapture.opencine.dji.DjiFailures
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.openpocketcine.LiveDesign

/** Pairing chrome — DJI Sky Blue `#00A3E0` on Black, no Nikon gold. */
object StartupColors {
    val surface: Color = LiveDesign.surface
    val tile: Color = LiveDesign.tile
    val control: Color = LiveDesign.tile
    val ink: Color = Color.White
    val muted: Color = LiveDesign.muted
    val dim: Color = Color(94 / 255f, 98 / 255f, 98 / 255f)
    val border: Color = Color.White
    val card: Color = LiveDesign.surface
    val accent: Color = LiveDesign.accent
    val ready: Color = Color(0.247f, 0.710f, 0.416f)
    val destructive: Color = Color(0.930f, 0.267f, 0.267f)
    val darkText: Color = Color(20 / 255f, 20 / 255f, 20 / 255f)
    val backdropBase: Color = LiveDesign.background
    /**
     * Operator Setup wash. iOS uses Sky Blue at 10% / 760 pt; Android is 20%
     * quieter and tighter on top of the OLED dim (6% / 608 pt).
     */
    val backdropGlow: Color = Color(0f, 163 / 255f, 230 / 255f, 0.06f)
}

fun Modifier.startupBackdrop(): Modifier = background(StartupColors.backdropBase)

fun ConnectionPhase.isBusy(): Boolean =
    when (this) {
        ConnectionPhase.IDLE,
        ConnectionPhase.SCANNING,
        ConnectionPhase.FAILED,
        ConnectionPhase.LIVE,
        -> false
        else -> true
    }

object StartupConnectionCopy {
    // Frame Tap blocks pairing and connecting; DJI Mimo on any nearby phone holds the camera.
    // Same wording as iOS. Failure cards add `DjiFailures.DJI_APPS_TIP` themselves.
    const val PAIRING_PRECHECK = "Before pairing, turn off DJI Frame Tap and force quit DJI Mimo."
    const val STILL_LOOKING = "${DjiFailures.DJI_APPS_TIP} Make sure the camera is on and activated, then move closer."
}
