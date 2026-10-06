package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.OpcIcon

/** Cyan edge chevron hinting at off-screen tools (OpenZCine `ScrollChevron`). */
@Composable
internal fun AssistScrollChevron(leading: Boolean, visible: Boolean, modifier: Modifier = Modifier) {
    OpcIcon(
        icon = if (leading) OpcIcon.CHEVRON_LEFT else OpcIcon.CHEVRON_RIGHT,
        contentDescription = null,
        tint = LiveDesign.accent,
        modifier =
            modifier
                .padding(horizontal = 5.dp)
                .size(12.dp)
                .alpha(if (visible) 1f else 0f),
    )
}
