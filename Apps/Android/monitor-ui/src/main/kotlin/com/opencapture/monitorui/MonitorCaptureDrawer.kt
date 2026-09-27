package com.opencapture.monitorui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight

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

/** Horizontal strips keep the bottom baseline; vertical rails keep it on their left edge. */
@Composable
fun MonitorDrawerTabs(tabs: List<String>, selected: Int, onSelect: (Int) -> Unit,
    enabled: Boolean = true, vertical: Boolean = false, modifier: Modifier = Modifier) {
    val items: @Composable (Modifier) -> Unit = { tabModifier ->
        tabs.forEachIndexed { index, label ->
            val active = index == selected
            MonitorTab(active, { onSelect(index) }, tabModifier, enabled = enabled, vertical = vertical,
                separator = index > 0, accessibilityLabel = label) {
                Text(label,
                    style = MonitorTypography.text(11f, if (active) FontWeight.SemiBold else FontWeight.Medium),
                    color = if (active) MonitorPalette.accent else MonitorPalette.muted,
                    maxLines = 1)
            }
        }
    }
    if (vertical) {
        Column(modifier.width(IntrinsicSize.Max).monitorTabStrip(vertical = true)) { items(Modifier.fillMaxWidth()) }
    } else {
        Row(modifier.monitorTabStrip()) { items(Modifier) }
    }
}
