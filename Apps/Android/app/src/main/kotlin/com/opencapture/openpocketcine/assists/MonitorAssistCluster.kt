package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorToolUsageState
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.OperatorPrefs

/**
 * Pocket supplies its supported tool inventory and existing live/playback actions.
 *
 * [inspectorOpen] hides the cluster so the palette Popup cannot cover inspector
 * controls (iOS collapses the palette while `configureTool` is set). Landscape
 * and portrait chrome should pass `assist.configureTool != null`.
 */
@Composable
fun MonitorAssistCluster(portrait: Boolean, locked: Boolean, isOn: (LiveAssistTool) -> Boolean,
    onToggle: (LiveAssistTool) -> Unit, onLongPress: (LiveAssistTool) -> Unit,
    modifier: Modifier = Modifier, requestExpand: Boolean = false, onExpansionHandled: () -> Unit = {},
    showsAudio: Boolean = true, inspectorOpen: Boolean = false) {
    if (inspectorOpen) return
    val context = LocalContext.current
    var usage by remember { mutableStateOf(OperatorPrefs.assistToolUsage(context)) }
    val tools = if (showsAudio) LiveAssistTool.settingsCases else LiveAssistTool.toolbarCases
    com.opencapture.monitorui.MonitorAssistPalette(
        tools = tools, usageSeed = ASSIST_USAGE_SEED,
        portrait = portrait, locked = locked, isOn = isOn, title = { it.title }, label = { it.chipLabel },
        hasOptions = { it.hasConfiguration }, onToggle = onToggle, onOptions = onLongPress,
        glyph = { tool, tint, iconModifier -> AssistToolGlyph(tool, tint, iconModifier) },
        chevron = { expanded, vertical ->
            val icon = if (vertical) { if (expanded) OpcIcon.CHEVRON_DOWN else OpcIcon.CHEVRON_UP }
                else { if (expanded) OpcIcon.CHEVRON_LEFT else OpcIcon.CHEVRON_RIGHT }
            OpcIcon(icon, null, Modifier.size(14.dp), LiveDesign.muted)
        }, modifier = modifier, requestExpand = requestExpand, onExpansionHandled = onExpansionHandled,
        idOf = { it.name }, usage = usage,
        onUsageChange = { next: MonitorToolUsageState ->
            usage = next
            OperatorPrefs.setAssistToolUsage(context, next)
        },
    )
}

/** Approved palette defaults; ties follow the supported catalog's stable order. */
private val ASSIST_USAGE_SEED = mapOf(
    "PEAK" to 6, "FALSE" to 5, "ZEBRA" to 4,
    "LUT" to 4, "WAVE" to 3, "GUIDES" to 2,
    "GRID" to 2, "HISTO" to 2, "VECTOR" to 1,
    "PARADE" to 1, "LIGHTS" to 1, "CROSS" to 1,
    "MIRROR" to 1, "AUDIO" to 1,
)
