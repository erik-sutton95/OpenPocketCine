package com.opencapture.openpocketcine

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.session.SessionRecoveryCopy
import com.opencapture.openpocketcine.session.SessionRecoveryUi

@Composable
fun MonitorRecoveryOverlay(
    state: SessionRecoveryUi,
    deviceName: String,
    onRetry: () -> Unit,
    onOperatorMenu: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (!state.isRecovering) return
    Box(
        modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.34f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .widthIn(max = 460.dp)
                .padding(horizontal = 24.dp)
                .clip(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))
                .background(LiveDesign.glassOpaque)
                .padding(horizontal = 18.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(22.dp),
                    color = LiveDesign.accent,
                    strokeWidth = 2.dp,
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        SessionRecoveryCopy.title(state),
                        color = LiveDesign.text,
                        style = LiveType.ui(16f, FontWeight.SemiBold),
                    )
                    Text(
                        SessionRecoveryCopy.detail(state, deviceName),
                        color = LiveDesign.muted,
                        style = LiveType.ui(12f, FontWeight.Medium),
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                RecoveryAction(SessionRecoveryCopy.RETRY_CONNECTION, accent = true, modifier = Modifier.weight(1f), onClick = onRetry)
                RecoveryAction(SessionRecoveryCopy.OPERATOR_MENU, accent = false, modifier = Modifier.weight(1f), onClick = onOperatorMenu)
            }
        }
    }
}

@Composable
private fun RecoveryAction(
    title: String,
    accent: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .clip(RoundedCornerShape(50))
            .background(if (accent) LiveDesign.accent else LiveDesign.glass)
            .chromeClickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            color = if (accent) LiveDesign.background else LiveDesign.text,
            style = LiveType.ui(13f, FontWeight.SemiBold),
            maxLines = 1,
        )
    }
}
