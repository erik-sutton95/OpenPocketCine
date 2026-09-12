package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Immutable
data class MonitorCameraSection<T>(val title: String, val cameras: List<T>)

/** The shell supplies identities, availability and actions; this page owns only layout. */
@Composable
fun <T> MonitorCameraPage(brand: String, sections: List<MonitorCameraSection<T>>, key: (T) -> Any,
    emptyMessage: String, modifier: Modifier = Modifier, title: String = "Your cameras",
    actions: @Composable RowScope.() -> Unit, camera: @Composable (T) -> Unit,
    footer: @Composable () -> Unit) {
    val config = LocalConfiguration.current
    val tablet = minOf(config.screenWidthDp, config.screenHeightDp) >= 600
    Column(modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(brand, color = MonitorPalette.accent,
                    style = MonitorTypography.text(8.5f, FontWeight.Bold).copy(letterSpacing = 1.5.sp))
                Text(title, color = MonitorPalette.text,
                    style = MonitorTypography.text(if (config.screenWidthDp < 400) 22f else 26f, FontWeight.SemiBold), maxLines = 1)
            }
            actions()
        }
        LazyVerticalGrid(columns = GridCells.Fixed(if (tablet) 2 else 1), modifier = Modifier.weight(1f),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            sections.filter { it.cameras.isNotEmpty() }.forEach { section ->
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Text(section.title, color = MonitorPalette.faint,
                        style = MonitorTypography.text(8.5f, FontWeight.Bold).copy(letterSpacing = 1.5.sp),
                        modifier = Modifier.padding(top = 5.dp, bottom = 2.dp))
                }
                items(section.cameras.size, key = { key(section.cameras[it]) }) { camera(section.cameras[it]) }
            }
            if (sections.all { it.cameras.isEmpty() }) item(span = { GridItemSpan(maxLineSpan) }) {
                Text(emptyMessage, color = MonitorPalette.muted,
                    style = MonitorTypography.text(13f), modifier = Modifier.padding(vertical = 20.dp))
            }
        }
        footer()
    }
}

@Composable
fun MonitorCameraCard(title: String, detail: String, enabled: Boolean, onOpen: () -> Unit,
    modifier: Modifier = Modifier, glyph: @Composable () -> Unit,
    options: @Composable () -> Unit, status: @Composable RowScope.() -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MonitorPalette.surface)
        .padding(horizontal = 14.dp, vertical = 13.dp)) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(MonitorPalette.tile),
                contentAlignment = Alignment.Center) { glyph() }
            Column(Modifier.weight(1f).clickable(enabled = enabled, onClick = onOpen),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(title, color = MonitorPalette.text, style = MonitorTypography.text(14.5f, FontWeight.SemiBold),
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(detail, color = MonitorPalette.muted, style = MonitorTypography.text(9.5f),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            options()
        }
        Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp), content = status)
    }
}
