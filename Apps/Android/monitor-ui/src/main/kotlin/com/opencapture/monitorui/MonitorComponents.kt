package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Immutable
data class MonitorValue(val id: String, val label: String, val value: String,
    val selected: Boolean = false, val annotation: String? = null)

/** Camera values are ready-to-display data; adapters retain interpretation and writes. */
@Composable
fun MonitorCameraValues(values: List<MonitorValue>, enabled: Boolean, portrait: Boolean,
    modifier: Modifier = Modifier, itemModifier: (String) -> Modifier = { Modifier },
    quickControl: (String) -> MonitorQuickControl? = { null }, onQuickCommit: (String, String) -> Unit = { _, _ -> },
    onQuickActiveChange: (Boolean) -> Unit = {},
    quickBottomClearanceDp: Float = 0f,
    onOpen: (String) -> Unit) {
    val gestureOwner = remember { MonitorQuickGestureOwner() }
    val notifyQuickActive by rememberUpdatedState(onQuickActiveChange)
    LaunchedEffect(gestureOwner.active) { notifyQuickActive(gestureOwner.active != null) }
    DisposableEffect(Unit) { onDispose { notifyQuickActive(false) } }
    val density = LocalDensity.current
    val configuration = LocalConfiguration.current
    val tablet = minOf(configuration.screenWidthDp, configuration.screenHeightDp) >= 600
    val measurer = rememberTextMeasurer()
    val valueStyle = MonitorTypography.readout(if (tablet) 18f else 16f, FontWeight.Medium).copy(lineHeight = (if (tablet) 18 else 16).sp)
    val labelStyle = MonitorTypography.text(8f, FontWeight.SemiBold).copy(lineHeight = 10.sp, letterSpacing = 1.12.sp)
    val intrinsic = values.map { item ->
        val valueWidth = measurer.measure(item.value, valueStyle, maxLines = 1).size.width
        val labelWidth = measurer.measure(item.label + item.annotation?.let { "  $it" }.orEmpty(), labelStyle, maxLines = 1).size.width
        with(density) { maxOf(valueWidth, labelWidth).toDp().value } + 8f
    }
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val rowWidth = maxWidth
        val columns = MonitorLayoutPolicy.valueColumns(maxWidth.value, portrait, values.size)
        val grid = portrait && !tablet
        val gap = if (grid) 12f else ((maxWidth.value - intrinsic.sum()) / (values.size - 1).coerceAtLeast(1)).coerceIn(14f, 32f)
        Column(verticalArrangement = Arrangement.spacedBy(if (grid) 10.dp else 8.dp)) {
            values.chunked(columns).forEachIndexed { rowIndex, row ->
                Row(Modifier.then(if (grid) Modifier.fillMaxWidth() else Modifier.horizontalScroll(rememberScrollState()).widthIn(min = rowWidth)),
                    horizontalArrangement = Arrangement.spacedBy(gap.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.Bottom) {
                    row.forEachIndexed { column, item ->
                        Column(Modifier.then(if (grid) Modifier.weight(1f) else Modifier.width(intrinsic[rowIndex * columns + column].dp))
                            .heightIn(min = if (grid) 32.dp else 44.dp)
                            .then(itemModifier(item.id)).clip(RoundedCornerShape(8.dp))
                            .background(if (item.selected) MonitorPalette.accent.copy(alpha = .14f) else Color.Transparent)
                            .monitorReadoutGesture(quickControl(item.id), enabled && (gestureOwner.owner == null || gestureOwner.owner == item.id),
                                { onOpen(item.id) }, { onQuickCommit(item.id, it) },
                                quickBottomClearanceDp, gestureOwner, item.id)
                            .semantics { contentDescription = "${item.label} ${item.value}${item.annotation?.let { ", $it" }.orEmpty()}" }
                            .padding(horizontal = 4.dp, vertical = 2.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
                            Text(item.value, color = if (item.selected) MonitorPalette.accent else MonitorPalette.text,
                                style = valueStyle, maxLines = 1, softWrap = false)
                            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Bottom) {
                                Text(item.label, color = if (item.selected) MonitorPalette.accent else MonitorPalette.muted,
                                    style = labelStyle, maxLines = 1)
                                item.annotation?.let { Text(it, style = MonitorTypography.readout(7.5f), color = MonitorPalette.muted, maxLines = 1) }
                            }
                        }
                    }
                    if (grid) repeat(columns - row.size) { Box(Modifier.weight(1f)) }
                }
            }
        }
    }
}

/** Native icon artwork is an adapter slot, so the engine has no brand/icon dependency. */
@Composable
fun MonitorActionButton(label: String, modifier: Modifier = Modifier, selected: Boolean = false,
    enabled: Boolean = true, onClick: () -> Unit, glyph: @Composable (Color) -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    val tint = if (selected) MonitorPalette.accent else MonitorPalette.text
    Box(modifier.size(44.dp).clip(shape)
        .background(if (selected) MonitorPalette.accent.copy(alpha = .14f) else MonitorPalette.tile)
        .border(1.dp, if (selected) MonitorPalette.accent.copy(alpha = .3f) else Color.Transparent, shape)
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
        .semantics { contentDescription = label }, contentAlignment = Alignment.Center) { glyph(tint) }
}

@Composable
fun MonitorPageScaffold(modifier: Modifier = Modifier,
    navigation: @Composable (portrait: Boolean) -> Unit, content: @Composable () -> Unit) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        if (maxHeight > maxWidth) {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.fillMaxWidth().background(MonitorPalette.surface, RoundedCornerShape(12.dp)).padding(10.dp)) {
                    navigation(true)
                }
                Box(Modifier.weight(1f).fillMaxWidth()) { content() }
            }
        } else {
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.width(170.dp).fillMaxHeight().background(MonitorPalette.surface,
                    RoundedCornerShape(12.dp)).padding(10.dp)) { navigation(false) }
                Box(Modifier.weight(1f).fillMaxHeight()) { content() }
            }
        }
    }
}

/** Catalog mechanics are common; item identity, cache state and actions stay in the adapter. */
@Composable
fun <T> MonitorCatalogGrid(items: List<T>, columns: Int, key: (T) -> Any,
    modifier: Modifier = Modifier, cell: @Composable (T) -> Unit) {
    LazyVerticalGrid(columns = GridCells.Fixed(columns.coerceAtLeast(1)), modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)) {
        items(items, key = key) { cell(it) }
    }
}

enum class MonitorThumbnailSize { SMALL, MEDIUM, LARGE }

fun monitorCatalogColumns(size: MonitorThumbnailSize, tablet: Boolean): Int = when (size) {
    MonitorThumbnailSize.SMALL -> if (tablet) 5 else 3
    MonitorThumbnailSize.MEDIUM -> if (tablet) 4 else 2
    MonitorThumbnailSize.LARGE -> if (tablet) 2 else 1
}

@Composable
fun MonitorSettingsCard(title: String? = null, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MonitorPalette.surface)
        .padding(horizontal = 13.dp, vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (!title.isNullOrBlank()) Text(title.uppercase(), color = MonitorPalette.muted,
            style = MonitorTypography.text(9f, FontWeight.SemiBold).copy(letterSpacing = 1.2.sp))
        content()
    }
}

/** Bulk catalog actions are supplied by the adapter and remain capability gated. */
@Composable
fun MonitorSelectionTray(count: Int, modifier: Modifier = Modifier,
    actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    Row(modifier.fillMaxWidth().clip(RoundedCornerShape(11.dp))
        .background(MonitorPalette.accent.copy(alpha = .14f))
        .border(1.dp, MonitorPalette.accent.copy(alpha = .3f), RoundedCornerShape(11.dp))
        .padding(horizontal = 9.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("$count selected", modifier = Modifier.weight(1f),
            style = MonitorTypography.text(10.5f, FontWeight.SemiBold), maxLines = 1,
            overflow = TextOverflow.Ellipsis)
        actions()
    }
}

/** Inspector control group over the picture, independent of a tool taxonomy. */
@Composable
fun MonitorOptionGroup(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
        .background(Color.White.copy(alpha = .035f))
        .border(1.dp, Color.White.copy(alpha = .06f), RoundedCornerShape(10.dp))
        .padding(horizontal = 12.dp)) { content() }
}

/** Quiet bottom handle shared by capture card presentations. */
@Composable
fun MonitorPanelGrabber() {
    Box(Modifier.fillMaxWidth().padding(top = 4.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size(36.dp, 4.dp).background(Color.White.copy(alpha = .18f), RoundedCornerShape(2.dp)))
    }
}
