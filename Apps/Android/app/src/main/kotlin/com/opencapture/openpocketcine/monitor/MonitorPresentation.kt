package com.opencapture.openpocketcine.monitor

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.size
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.opencapture.opencine.cameracontrols.reportChromeFrame
import com.opencapture.monitorui.MonitorRect
import com.opencapture.monitorui.MonitorIcon
import com.opencapture.monitorui.MonitorValue


/** Adapter boundary for canvas frame reporting; shared rendering owns the layout. */
@Composable
fun MonitorCameraValues(values: List<MonitorValue>, enabled: Boolean, portrait: Boolean,
    modifier: Modifier = Modifier,
    quickControl: (String) -> com.opencapture.monitorui.MonitorQuickControl? = { null },
    onQuickCommit: (String, com.opencapture.monitorui.MonitorQuickControl, String) -> Unit = { _, _, _ -> },
    quickPreview: (@Composable (String, com.opencapture.monitorui.MonitorQuickPreview, Float) -> Unit)? = null,
    onQuickActiveChange: (Boolean) -> Unit = {},
    quickBottomClearanceDp: Float = 0f,
    onOpen: (String) -> Unit, onFrame: (String, MonitorRect) -> Unit) {
    com.opencapture.monitorui.MonitorCameraValues(values, enabled, portrait, modifier,
        itemModifier = { id -> Modifier.reportChromeFrame { onFrame(id, it) } },
        quickControl = quickControl, onQuickCommit = onQuickCommit, quickPreview = quickPreview,
        onQuickActiveChange = onQuickActiveChange, quickBottomClearanceDp = quickBottomClearanceDp, onOpen = onOpen)
}
