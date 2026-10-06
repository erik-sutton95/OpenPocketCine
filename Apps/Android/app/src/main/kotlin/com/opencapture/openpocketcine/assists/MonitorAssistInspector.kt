package com.opencapture.openpocketcine.assists

import androidx.compose.runtime.Composable
import com.opencapture.opencine.cameracontrols.AssistInspectorFrame
import com.opencapture.openpocketcine.AppModel

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
    isPhoto: Boolean = false,
) {
    AssistInspectorFrame(tool, state, viewportWidth, viewportHeight, safeLeading, safeTop, safeBottom, onDismiss,
        playback = playback, safeTrailing = safeTrailing,) { maxHeightDp ->
        AssistOptionsPopup(
            tool, state, onDismiss, model = model,
            maxHeightDp = maxHeightDp,
            colorMode = colorMode, embedded = true, playback = playback, isPhoto = isPhoto,
        )
    }
}
