package com.opencapture.openpocketcine.monitor

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.size
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.ChromeRect
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.reportChromeFrame

typealias MonitorValue = com.opencapture.monitorui.MonitorValue

/** Adapter boundary for canvas frame reporting; shared rendering owns the layout. */
@Composable
fun MonitorCameraValues(values: List<MonitorValue>, enabled: Boolean, portrait: Boolean,
    modifier: Modifier = Modifier,
    quickControl: (String) -> com.opencapture.monitorui.MonitorQuickControl? = { null },
    onQuickCommit: (String, String) -> Unit = { _, _ -> },
    onOpen: (String) -> Unit, onFrame: (String, ChromeRect) -> Unit) {
    com.opencapture.monitorui.MonitorCameraValues(values, enabled, portrait, modifier,
        itemModifier = { id -> Modifier.reportChromeFrame { onFrame(id, it) } },
        quickControl = quickControl, onQuickCommit = onQuickCommit, onOpen = onOpen)
}

@Composable
fun MonitorIconButton(icon: OpcIcon, label: String, modifier: Modifier = Modifier,
    selected: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    com.opencapture.monitorui.MonitorActionButton(label, modifier, selected, enabled, onClick) { tint ->
        OpcIcon(icon, null, Modifier.size(20.dp), tint)
    }
}
