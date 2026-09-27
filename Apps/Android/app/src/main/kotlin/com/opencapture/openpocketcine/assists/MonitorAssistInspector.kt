package com.opencapture.openpocketcine.assists

import com.opencapture.monitorui.MonitorTab
import com.opencapture.monitorui.monitorTabStrip
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.opencapture.monitorui.LocalMonitorInspectorHelp
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorInspector
import com.opencapture.monitorui.monitorScrollFade
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LocalOperatorHaptics
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType

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
    var helpVisible by remember { mutableStateOf(false) }
    MonitorInspector(
        title = tool.title,
        helpVisible = helpVisible,
        onToggleHelp = { helpVisible = !helpVisible },
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
                val tabScroll = rememberScrollState()
                Row(Modifier.fillMaxWidth().monitorScrollFade(tabScroll, vertical = false).horizontalScroll(tabScroll).monitorTabStrip()) {
                    LiveAssistTool.settingsCases.forEach { InspectorTab(it, tool, state, true) }
                }
            } else {
                val tabScroll = rememberScrollState()
                Column(Modifier.fillMaxHeight().monitorScrollFade(tabScroll).verticalScroll(tabScroll).monitorTabStrip()) {
                    LiveAssistTool.settingsCases.forEach { InspectorTab(it, tool, state, false) }
                }
            }
        },
    ) {
        androidx.compose.runtime.key(tool, playback) {
            BoxWithConstraints(Modifier.fillMaxWidth().fillMaxHeight()) {
                CompositionLocalProvider(LocalMonitorInspectorHelp provides helpVisible) {
                    AssistOptionsPopup(
                        tool, state, onDismiss, model = model,
                        maxHeightDp = maxHeight.value,
                        colorMode = colorMode, embedded = true, playback = playback, isPhoto = isPhoto,
                    )
                }
            }
        }
    }
}

@Composable
private fun InspectorTab(tool: LiveAssistTool, selected: LiveAssistTool, state: LiveAssistState, portrait: Boolean) {
    val active = tool == selected
    val haptics = LocalOperatorHaptics.current
    val tint = if (active) LiveDesign.accent else LiveDesign.muted
    MonitorTab(active, { haptics.selection(); state.configureTool = tool },
        Modifier.then(if (portrait) Modifier.width(94.dp) else Modifier.fillMaxWidth()).height(44.dp),
        vertical = !portrait, separator = tool != LiveAssistTool.settingsCases.first(),
        accessibilityLabel = tool.chipLabel) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            AssistToolGlyph(tool, tint, Modifier.size(15.dp))
            Text(tool.chipLabel, color = tint, style = LiveType.ui(9f, FontWeight.SemiBold), maxLines = 1)
        }
    }
}
