package com.opencapture.openpocketcine

import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

typealias OpcIcon = com.opencapture.monitorui.MonitorIcon

@Composable
fun OpcIcon(icon: OpcIcon, contentDescription: String?, modifier: Modifier = Modifier,
    tint: Color = LocalContentColor.current, filled: Boolean = false) =
    com.opencapture.monitorui.MonitorIcon(icon, contentDescription, modifier, tint, filled)
