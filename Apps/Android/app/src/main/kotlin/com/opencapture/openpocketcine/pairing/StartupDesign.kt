package com.opencapture.openpocketcine.pairing

import androidx.compose.foundation.background
import androidx.compose.ui.Modifier
import com.opencapture.opencine.dji.DjiFailures
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.openpocketcine.LiveDesign

/** The app backdrop behind the shell. */
fun Modifier.startupBackdrop(): Modifier = background(LiveDesign.background)

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
