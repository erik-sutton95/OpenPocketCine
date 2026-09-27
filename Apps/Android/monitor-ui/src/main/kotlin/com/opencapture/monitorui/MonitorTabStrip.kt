package com.opencapture.monitorui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** A single baseline; tab content remains on the surrounding page surface. */
fun Modifier.monitorTabStrip(vertical: Boolean = false): Modifier = drawBehind {
    val edge = 1.dp.toPx()
    val start = if (vertical) Offset(edge / 2, 0f) else Offset(0f, size.height - edge / 2)
    val end = if (vertical) Offset(edge / 2, size.height) else Offset(size.width, size.height - edge / 2)
    drawLine(MonitorPalette.border, start, end, edge)
}

/** Shared edges stay still on press. Each native tab retains a full 44dp target. */
@Suppress("UNUSED_PARAMETER") // Keep separator source-compatible; tabs now share only one edge line.
@Composable
fun MonitorTab(
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    vertical: Boolean = false,
    separator: Boolean = true,
    accessibilityLabel: String? = null,
    horizontalPadding: Dp = 12.dp,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier.widthIn(min = 44.dp).heightIn(min = 44.dp)
            .drawBehind {
                val edge = 1.dp.toPx()
                if (selected) {
                    val start = if (vertical) Offset(edge, 0f) else Offset(0f, size.height - edge)
                    val end = if (vertical) Offset(edge, size.height) else Offset(size.width, size.height - edge)
                    drawLine(MonitorPalette.accent, start, end, 2.dp.toPx())
                }
            }
            .selectable(selected = selected, enabled = enabled, role = Role.Tab, onClick = onClick)
            .semantics { accessibilityLabel?.let { contentDescription = it } }
            .padding(horizontal = horizontalPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        content = content,
    )
}
