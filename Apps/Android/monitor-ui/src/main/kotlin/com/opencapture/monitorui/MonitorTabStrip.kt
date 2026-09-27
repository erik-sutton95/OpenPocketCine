package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** One outline for a contiguous navigation strip; hosts retain scrolling and selection. */
fun Modifier.monitorTabStrip(): Modifier {
    val shape = RoundedCornerShape(7.dp)
    return clip(shape).background(Color.White.copy(alpha = .035f))
        .border(1.dp, MonitorPalette.border, shape)
}

/** Shared edges stay still on press. Each native tab retains a full 44dp target. */
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
            .background(if (selected) MonitorPalette.accent.copy(alpha = .10f) else Color.Transparent)
            .drawBehind {
                val edge = 1.dp.toPx()
                if (separator) {
                    val end = if (vertical) Offset(size.width, 0f) else Offset(0f, size.height)
                    drawLine(MonitorPalette.border, Offset.Zero, end, edge)
                }
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
