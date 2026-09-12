package com.opencapture.openpocketcine.monitor

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon

/** Responsive shell shared by Settings, media and future monitor destinations. */
@Composable
fun MonitorPageScaffold(
    modifier: Modifier = Modifier,
    navigation: @Composable (portrait: Boolean) -> Unit,
    content: @Composable () -> Unit,
) {
    com.opencapture.monitorui.MonitorPageScaffold(modifier, navigation, content)
}

@Composable
fun MonitorPageHeader(title: String, kicker: String, onClose: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
        MonitorIconButton(OpcIcon.CHEVRON_LEFT, "Back", onClick = onClose)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(kicker, color = LiveDesign.accent,
                style = LiveType.ui(8f, FontWeight.Bold).copy(letterSpacing = 1.2.sp), maxLines = 1)
            Text(title, style = LiveType.ui(13f, FontWeight.SemiBold), maxLines = 1)
        }
    }
}
