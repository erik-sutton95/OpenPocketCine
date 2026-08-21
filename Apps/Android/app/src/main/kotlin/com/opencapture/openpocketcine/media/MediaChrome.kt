package com.opencapture.openpocketcine.media

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.LiveDesign

fun Modifier.mediaGlass(shape: Shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)): Modifier =
    clip(shape)
        .background(LiveDesign.glassOpaque)
        .border(1.dp, LiveDesign.hairlineStrong, shape)

@Composable
fun MediaCloseButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 37.dp,
) {
    Box(
        modifier
            .size(size)
            .mediaGlass(CircleShape)
            .clickable(onClick = onClick)
            .semantics { contentDescription = "Close" },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Filled.Close,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(size * 0.38f),
        )
    }
}
