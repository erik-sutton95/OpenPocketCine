package com.opencapture.monitorui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Scale-Y morph from the well the control lives on. Compact and details share it. */
@Composable
fun MonitorCaptureReveal(modifier: Modifier = Modifier, fromTop: Boolean = false,
    content: @Composable BoxScope.() -> Unit) {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val progress by animateFloatAsState(if (shown) 1f else 0f,
        tween(MonitorMotion.PICKER_MORPH_MS, easing = MonitorMotion.EaseOutCubic), label = "capture-reveal")
    Box(modifier.graphicsLayer {
        transformOrigin = TransformOrigin(0.5f, if (fromTop) 0f else 1f)
        scaleY = 0.22f + 0.78f * progress
        alpha = 0.5f + 0.5f * progress
    }, content = content)
}

@Composable
fun MonitorDrawerTabs(tabs: List<String>, selected: Int, onSelect: (Int) -> Unit,
    enabled: Boolean = true) {
    val shape = RoundedCornerShape(13.dp)
    Row(Modifier.clip(shape).background(androidx.compose.ui.graphics.Color(0x8008090A))
        .border(1.dp, ColorWhite08, shape).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        tabs.forEachIndexed { index, label ->
            val active = index == selected
            Box(Modifier.clip(shape)
                .background(if (active) MonitorPalette.accent else androidx.compose.ui.graphics.Color.Transparent)
                .clickable(enabled = enabled, onClick = { onSelect(index) })
                .semantics { role = Role.Tab; contentDescription = label; this.selected = active }
                .padding(horizontal = 11.dp, vertical = 6.dp),
                contentAlignment = Alignment.Center) {
                Text(label,
                    style = MonitorTypography.text(11f, if (active) FontWeight.SemiBold else FontWeight.Medium),
                    color = if (active) androidx.compose.ui.graphics.Color(0xFF08191F) else MonitorPalette.muted,
                    maxLines = 1)
            }
        }
    }
}

private val ColorWhite08 = androidx.compose.ui.graphics.Color.White.copy(alpha = .08f)
