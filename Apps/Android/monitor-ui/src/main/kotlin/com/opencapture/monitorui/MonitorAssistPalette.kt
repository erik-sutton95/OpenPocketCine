@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties

/** One palette for live, playback and multi-view, without any camera or tool taxonomy. */
@Composable
fun <T> MonitorAssistPalette(tools: List<T>, portrait: Boolean, locked: Boolean,
    isOn: (T) -> Boolean, title: (T) -> String, label: (T) -> String, hasOptions: (T) -> Boolean,
    onToggle: (T) -> Unit, onOptions: (T) -> Unit,
    glyph: @Composable (T, Color, Modifier) -> Unit,
    chevron: @Composable (expanded: Boolean, portrait: Boolean) -> Unit,
    modifier: Modifier = Modifier, requestExpand: Boolean = false, onExpansionHandled: () -> Unit = {},
    usageSeed: Map<T, Int> = emptyMap()) {
    var expanded by remember { mutableStateOf(false) }
    var usage by remember(tools, usageSeed) { mutableStateOf(usageSeed) }
    val ranked = remember(tools, usage) { MonitorAssistUsage.ranked(tools, usage) }
    fun used(tool: T) { usage = MonitorAssistUsage.recording(tool, usage) }
    val config = LocalConfiguration.current
    val tablet = minOf(config.screenWidthDp, config.screenHeightDp) >= 600
    val buttonSize = if (tablet) 52.dp else 44.dp
    LaunchedEffect(requestExpand) { if (requestExpand) { expanded = true; onExpansionHandled() } }
    LaunchedEffect(locked) { if (locked) expanded = false }
    val key: @Composable (T, Boolean) -> Unit = { tool, withLabel ->
        val active = isOn(tool)
        val tint = if (active) MonitorPalette.accent else MonitorPalette.text
        Column(Modifier.size(if (withLabel) buttonSize + 8.dp else buttonSize, buttonSize)
            .clip(RoundedCornerShape(9.dp)).background(if (active) MonitorPalette.accent.copy(alpha = .14f) else Color.Transparent)
            .combinedClickable(enabled = !locked, onClick = { used(tool); onToggle(tool) },
                onLongClick = if (hasOptions(tool)) { { used(tool); onOptions(tool); expanded = false } } else null)
            .semantics { contentDescription = "${title(tool)}, ${if (active) "on" else "off"}" },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)) {
            glyph(tool, tint, Modifier.size(if (tablet) 24.dp else 20.dp))
            if (withLabel) Text(label(tool), color = tint, style = MonitorTypography.text(7.5f, FontWeight.SemiBold), maxLines = 1)
        }
    }
    val expand: @Composable (Boolean) -> Unit = { open ->
        Box(Modifier.size(if (portrait) buttonSize else 18.dp, if (portrait) 24.dp else buttonSize)
            .combinedClickable(enabled = !locked, onClick = { expanded = !open })
            .semantics { contentDescription = if (open) "Collapse view assists" else "Show view assists" }, contentAlignment = Alignment.Center) {
            chevron(open, portrait)
        }
    }
    Box(modifier, contentAlignment = Alignment.BottomStart) {
        Row(Modifier.clip(RoundedCornerShape(14.dp)).background(Color(0xFF141618).copy(alpha = .52f)).padding(4.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                if (portrait) expand(false)
                val smart = ranked.take(if (portrait) 1 else 2)
                smart.forEach { key(it, false) }
            }
            if (!portrait) expand(false)
        }
        if (expanded && !locked) Popup(alignment = Alignment.BottomStart, onDismissRequest = { expanded = false },
            properties = PopupProperties(focusable = true)) {
            if (portrait) Column(Modifier.clip(RoundedCornerShape(14.dp)).background(Color(0xFF141618).copy(alpha = .62f))
                .padding(4.dp).heightIn(max = (config.screenHeightDp * .62f).dp), horizontalAlignment = Alignment.CenterHorizontally) {
                expand(true)
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    tools.forEach { key(it, true) }
                }
            } else Row(Modifier.clip(RoundedCornerShape(14.dp)).background(Color(0xFF141618).copy(alpha = .62f))
                .padding(4.dp).horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    tools.chunked((tools.size + 1) / 2).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) { row.forEach { key(it, true) } }
                    }
                }
                expand(true)
            }
        }
    }
}
