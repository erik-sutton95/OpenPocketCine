package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorInspector
import com.opencapture.monitorui.MonitorInspectorPolicy
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.chromeClickable

/** Assist options ride the shared inspector frame; preview work stays in AssistOptionsPopup. */
@Composable
@Suppress("UNUSED_PARAMETER")
fun MonitorAssistInspector(
    tool: LiveAssistTool, state: LiveAssistState, model: AppModel?, colorMode: Int,
    viewportWidth: Float, viewportHeight: Float, safeLeading: Float,
    safeTop: Float, safeBottom: Float, controlsFloor: Float,
    onDismiss: () -> Unit,
    playback: Boolean = false,
    safeTrailing: Float = 0f,
) {
    MonitorInspector(
        title = tool.title.uppercase(),
        viewportWidth = viewportWidth,
        viewportHeight = viewportHeight,
        onDismiss = onDismiss,
        trailing = false,
        safeLeading = safeLeading,
        safeTrailing = safeTrailing,
        safeTop = safeTop,
        safeBottom = safeBottom,
        navigation = { portrait ->
            if (portrait) {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    LiveAssistTool.settingsCases.forEach { InspectorTab(it, tool, state, true) }
                }
            } else {
                Column(Modifier.fillMaxHeight().verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    LiveAssistTool.settingsCases.forEach { InspectorTab(it, tool, state, false) }
                }
            }
        },
    ) {
        androidx.compose.runtime.key(tool, playback) {
            val frame = MonitorInspectorPolicy.frame(viewportWidth, viewportHeight, trailing = false)
            AssistOptionsPopup(
                tool, state, onDismiss, model = model,
                maxHeightDp = (frame.height - 120f).coerceAtLeast(100f),
                colorMode = colorMode, embedded = true, playback = playback,
            )
        }
    }
}

@Composable
private fun InspectorTab(tool: LiveAssistTool, selected: LiveAssistTool, state: LiveAssistState, portrait: Boolean) {
    val active = tool == selected
    val tint = if (active) LiveDesign.accent else LiveDesign.muted
    Row(
        Modifier.then(if (portrait) Modifier.width(94.dp) else Modifier.fillMaxWidth()).height(44.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (active) LiveDesign.accentDim else androidx.compose.ui.graphics.Color.Transparent)
            .chromeClickable { state.configureTool = tool }.padding(horizontal = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        AssistToolGlyph(tool, tint, Modifier.size(15.dp))
        Text(tool.chipLabel, color = tint, style = LiveType.ui(9f, FontWeight.SemiBold), maxLines = 1)
    }
}
