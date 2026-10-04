package com.opencapture.openpocketcine

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.session.CamFov
import com.opencapture.openpocketcine.session.PocketCameraSession

/**
 * Pocket 3 Med-Tele (MT): the second, 2× lens, beside the zoom chip. Its own button
 * rather than a zoom stop, because the body decides where the zoom lands after the swap.
 *
 * Reads the session itself, so a swap redraws this button and nothing around it. Dimmed
 * while a swap runs, when it takes no taps, and in the states [CamFov.medTeleRefusal]
 * names, where it stays tappable so the note can say why.
 */
@Composable
fun LiveMedTeleButton(session: PocketCameraSession, locked: Boolean, frame: ChromeRect) {
    val status by session.status.collectAsState()
    val swap by session.medTeleSwap.collectAsState()
    val on = swap ?: (status.zoomLensMin >= 0 && CamFov.isMedTele(status.zoomLensMin))
    val refused = CamFov.medTeleRefusal(status.colorMode, status.isRecording, status.shootingMode) != null
    val enabled = !locked && swap == null
    Box(
        Modifier
            .liveModuleFrame(frame)
            .alpha(if (enabled && !refused) 1f else 0.4f)
            .size(GimbalCluster.MED_TELE.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.55f))
            .border(1.dp, if (on) LiveDesign.accent else LiveDesign.hairline, CircleShape)
            .chromeClickable(enabled = enabled, onClick = session::toggleMedTele)
            .semantics { contentDescription = if (on) "Turn Med-Tele off" else "Turn Med-Tele on" },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "MT",
            color = if (on) LiveDesign.accent else LiveDesign.text,
            style = LiveType.ui(9f, FontWeight.Bold),
            maxLines = 1,
        )
    }
}

/**
 * Black over the picture while an MT swap runs, so the body's lens change never shows.
 * The state is read here and the fade only in the draw layer, so a swap does not
 * recompose the live view around it.
 */
@Composable
fun LiveMedTeleFade(session: PocketCameraSession, modifier: Modifier) {
    val swapping = session.medTeleSwap.collectAsState().value != null
    val fade by animateFloatAsState(
        if (swapping) 1f else 0f,
        tween(if (swapping) CamFov.MED_TELE_FADE_MS.toInt() else MED_TELE_FADE_IN_MS),
        label = "medTeleFade",
    )
    Box(modifier.graphicsLayer { alpha = fade }.background(Color.Black))
}

/** The picture comes back a little slower than it goes. */
private const val MED_TELE_FADE_IN_MS = 160
