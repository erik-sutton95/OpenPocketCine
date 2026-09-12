package com.opencapture.monitorui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** The renderer supplies an already bounded image; presentation never samples a feed. */
@Composable
fun MonitorImagePreview(image: ImageBitmap?, description: String, modifier: Modifier = Modifier,
    waitingLabel: String = "Waiting for picture") {
    Box(modifier.fillMaxWidth().height(132.dp).clip(RoundedCornerShape(10.dp))
        .background(MonitorPalette.background).semantics { contentDescription = description },
        contentAlignment = Alignment.Center) {
        if (image != null) Image(image, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
        else Text(waitingLabel, style = MonitorTypography.text(10f), color = MonitorPalette.muted)
    }
}
