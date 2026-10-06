package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import com.opencapture.openpocketcine.LiveDesign

private val PanelShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

@Composable
internal fun Modifier.scopePanelChrome(): Modifier =
    monitorMaterial(MonitorMaterial.Scope, PanelShape)
