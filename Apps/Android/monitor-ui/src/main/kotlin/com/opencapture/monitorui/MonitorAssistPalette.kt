@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
package com.opencapture.monitorui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
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
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.window.PopupPositionProvider
import kotlinx.coroutines.delay
import androidx.compose.ui.unit.sp
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
    var fullMounted by remember { mutableStateOf(false) }
    var revealed by remember { mutableStateOf(false) }
    var usage by remember(tools, usageSeed) { mutableStateOf(usageSeed) }
    val ranked = remember(tools, usage) { MonitorAssistUsage.ranked(tools, usage) }
    fun used(tool: T) { usage = MonitorAssistUsage.recording(tool, usage) }
    val config = LocalConfiguration.current
    val tablet = minOf(config.screenWidthDp, config.screenHeightDp) >= 600
    val buttonSize = MonitorLayoutPolicy.assistButtonSize(tablet).dp
    val iconSize = MonitorLayoutPolicy.assistIconSize(tablet).dp
    val cellW = MonitorLayoutPolicy.assistCellWidth(config.screenWidthDp.toFloat(), portrait, tablet).dp
    val expand by animateFloatAsState(if (revealed) 1f else 0f,
        tween(MonitorMotion.PALETTE_MS, easing = MonitorMotion.EaseOutCubic), label = "assist-palette")
    LaunchedEffect(requestExpand) { if (requestExpand) { expanded = true; onExpansionHandled() } }
    LaunchedEffect(locked) { if (locked) expanded = false }
    LaunchedEffect(expanded) {
        if (expanded) {
            fullMounted = true
            androidx.compose.runtime.withFrameNanos { }
            revealed = true
        } else {
            revealed = false
            delay(MonitorMotion.PALETTE_SETTLE_MS.toLong())
            fullMounted = false
        }
    }
    val compactW = buttonSize + if (portrait) 8.dp else 26.dp
    val compactH = if (portrait) buttonSize + 35.dp else buttonSize * 2 + 11.dp
    val fullW = if (portrait) cellW + 8.dp else
        MonitorLayoutPolicy.assistAvailableWidth(config.screenWidthDp.toFloat(), portrait, tablet).dp
    val fullH = if (portrait) minOf((config.screenHeightDp * .62f).dp,
        buttonSize * tools.size + (maxOf(0, tools.size - 1) * 3 + 35).dp) else buttonSize * 2 + 11.dp
    val columns = maxOf(1, (tools.size + 1) / 2)
    val scrollState = rememberScrollState()
    val popupPosition = remember { object : PopupPositionProvider {
        override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize,
            layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset =
            IntOffset(anchorBounds.left.coerceIn(0, maxOf(0, windowSize.width - popupContentSize.width)),
                (anchorBounds.bottom - popupContentSize.height).coerceAtLeast(0))
    } }
    val key: @Composable (T, Boolean, androidx.compose.ui.unit.Dp) -> Unit = { tool, withLabel, cellWidth ->
        val active = isOn(tool)
        val tint = if (active) MonitorPalette.accent else MonitorPalette.text
        Column(Modifier.size(cellWidth, buttonSize)
            .clip(RoundedCornerShape(9.dp)).background(if (active) MonitorPalette.accent.copy(alpha = .13f) else Color.Transparent)
            .combinedClickable(enabled = !locked && (!fullMounted || expanded), onClick = { used(tool); onToggle(tool) },
                onLongClick = if (hasOptions(tool)) { { used(tool); onOptions(tool); expanded = false } } else null)
            .semantics { contentDescription = "${title(tool)}, ${if (active) "on" else "off"}" },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)) {
            glyph(tool, tint, Modifier.size(iconSize))
            if (withLabel) Text(label(tool), color = tint,
                style = MonitorTypography.text(7.5f, FontWeight.SemiBold).copy(letterSpacing = .75.sp), maxLines = 1)
        }
    }
    val expandHit: @Composable (Boolean) -> Unit = { open ->
        Box(Modifier.size(if (portrait) buttonSize else 15.dp, if (portrait) 24.dp else buttonSize * 2 + 3.dp)
            .combinedClickable(enabled = !locked && (!fullMounted || expanded), onClick = { expanded = !open })
            .semantics { contentDescription = if (open) "Collapse view assists" else "Show view assists" },
            contentAlignment = Alignment.Center) {
            chevron(open, portrait)
        }
    }
    Box(modifier, contentAlignment = Alignment.BottomStart) {
        Row(Modifier.graphicsLayer { alpha = if (fullMounted) 0f else 1f }
            .then(if (fullMounted) Modifier.clearAndSetSemantics { } else Modifier)
            .clip(RoundedCornerShape(14.dp)).monitorMaterial(MonitorMaterial.Compact).padding(4.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                if (portrait) expandHit(false)
                ranked.take(if (portrait) 1 else 2).forEach { key(it, false, buttonSize) }
            }
            if (!portrait) expandHit(false)
        }
        if (fullMounted) Popup(popupPositionProvider = popupPosition,
            onDismissRequest = { expanded = false }, properties = PopupProperties(focusable = true)) {
            // The full-size cells never reflow during the animated, bottom-leading
            // clip. The popup merely escapes a shell's collapsed rail hit bounds.
            Box(Modifier.requiredSize(fullW, fullH).graphicsLayer {
                val visibleW = (compactW + (fullW - compactW) * expand).toPx()
                val visibleH = (compactH + (fullH - compactH) * expand).toPx()
                shape = GenericShape { size, _ ->
                    addRoundRect(RoundRect(0f, size.height - visibleH, visibleW, size.height,
                        CornerRadius(14.dp.toPx())))
                }
                clip = true
            }.monitorMaterial(MonitorMaterial.Expanded).padding(4.dp)) {
                if (portrait) Column(horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    expandHit(true)
                    Column(Modifier.width(cellW).height(fullH - 35.dp).verticalScroll(scrollState),
                        verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        tools.forEach { key(it, true, cellW) }
                    }
                } else Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(Modifier.width(fullW - 26.dp).height(fullH - 8.dp).horizontalScroll(scrollState),
                        horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        repeat(columns) { column ->
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                repeat(2) { row ->
                                    val index = row * columns + column
                                    if (index < tools.size) key(tools[index], true, cellW)
                                    else Box(Modifier.size(cellW, buttonSize))
                                }
                            }
                        }
                    }
                    expandHit(true)
                }
            }
        }
    }
}
