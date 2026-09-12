package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.OpcIcon

/** Pocket supplies its supported tool inventory and existing live/playback actions. */
@Composable
fun MonitorAssistCluster(portrait: Boolean, locked: Boolean, isOn: (LiveAssistTool) -> Boolean,
    onToggle: (LiveAssistTool) -> Unit, onLongPress: (LiveAssistTool) -> Unit,
    modifier: Modifier = Modifier, requestExpand: Boolean = false, onExpansionHandled: () -> Unit = {}) {
    com.opencapture.monitorui.MonitorAssistPalette(
        tools = LiveAssistTool.settingsCases, usageSeed = ASSIST_USAGE_SEED,
        portrait = portrait, locked = locked, isOn = isOn, title = { it.title }, label = { it.chipLabel },
        hasOptions = { it.hasConfiguration }, onToggle = onToggle, onOptions = onLongPress,
        glyph = { tool, tint, iconModifier -> AssistToolGlyph(tool, tint, iconModifier) },
        chevron = { expanded, vertical ->
            val icon = if (vertical) { if (expanded) OpcIcon.CHEVRON_DOWN else OpcIcon.CHEVRON_UP }
                else { if (expanded) OpcIcon.CHEVRON_LEFT else OpcIcon.CHEVRON_RIGHT }
            OpcIcon(icon, null, Modifier.size(14.dp), LiveDesign.muted)
        }, modifier = modifier, requestExpand = requestExpand, onExpansionHandled = onExpansionHandled,
    )
}

/** Approved palette defaults; ties follow the supported catalog's stable order. */
private val ASSIST_USAGE_SEED = mapOf(
    LiveAssistTool.PEAK to 6, LiveAssistTool.FALSE to 5, LiveAssistTool.ZEBRA to 4,
    LiveAssistTool.LUT to 4, LiveAssistTool.WAVE to 3, LiveAssistTool.GUIDES to 2,
    LiveAssistTool.GRID to 2, LiveAssistTool.HISTO to 2, LiveAssistTool.VECTOR to 1,
    LiveAssistTool.PARADE to 1, LiveAssistTool.LIGHTS to 1, LiveAssistTool.CROSS to 1,
    LiveAssistTool.MIRROR to 1, LiveAssistTool.AUDIO to 1,
)
