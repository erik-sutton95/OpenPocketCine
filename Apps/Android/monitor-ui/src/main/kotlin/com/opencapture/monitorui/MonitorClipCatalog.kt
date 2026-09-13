@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
package com.opencapture.monitorui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Immutable
data class MonitorClipValue(val id: String, val title: String, val detail: String,
    val duration: String?, val source: String, val favorite: Boolean,
    val progress: Float? = null)

/** Grid and list share one presentation value and one thumbnail-loader slot. */
@Composable
fun MonitorClipCard(clip: MonitorClipValue, list: Boolean, selecting: Boolean, selected: Boolean,
    onOpen: () -> Unit, onSelect: () -> Unit, onFavorite: (() -> Unit)? = null,
    modifier: Modifier = Modifier, clicks: Boolean = true, thumbnail: @Composable BoxScope.() -> Unit) {
    val shape = RoundedCornerShape(11.dp)
    val surface = modifier.fillMaxWidth().clip(shape)
        .background(if (selected) MonitorPalette.accent.copy(alpha = .12f) else MonitorPalette.surface)
        .border(if (selected) 2.dp else 1.dp,
            if (selected) MonitorPalette.accent else Color.White.copy(alpha = .06f), shape)
        .then(
            if (clicks) Modifier.combinedClickable(
                role = Role.Button,
                onClick = { if (selecting) onSelect() else onOpen() },
                onLongClick = onSelect,
            ).semantics { contentDescription = clip.title }
            else Modifier.semantics {
                role = Role.Button
                contentDescription = clip.title
                onClick(label = if (selecting) "Toggle selection" else "Open") {
                    if (selecting) onSelect() else onOpen()
                    true
                }
                onLongClick(label = if (selecting) "Toggle selection" else "Select clip") {
                    onSelect()
                    true
                }
            },
        )
    val favoriteAction = onFavorite
    val image: @Composable BoxScope.() -> Unit = {
        thumbnail()
        clip.progress?.let { progress ->
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .45f)), contentAlignment = Alignment.Center) {
                Text("${(progress * 100).toInt()}%", style = MonitorTypography.readout(11f, FontWeight.SemiBold))
            }
        }
    }
    if (list) Row(surface.padding(start = 4.dp, end = 5.dp, top = 5.dp, bottom = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (selecting) MonitorClipSelection(selected, if (clicks) onSelect else null)
        Box(Modifier.width(64.dp).height(40.dp).clip(RoundedCornerShape(6.dp)).background(MonitorPalette.backgroundDeep), content = image)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(clip.title, style = MonitorTypography.text(10.5f, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(clip.detail, color = MonitorPalette.muted, style = MonitorTypography.text(9f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(clip.duration.orEmpty(), style = MonitorTypography.readout(9.5f))
            Text(clip.source, color = MonitorPalette.muted, style = MonitorTypography.text(7.5f, FontWeight.SemiBold))
        }
        if (favoriteAction != null) {
            MonitorClipFavorite(clip.favorite, favoriteAction)
        }
    } else Column(surface, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(shape).background(MonitorPalette.backgroundDeep)) {
            image()
            if (selecting) {
                Box(Modifier.align(Alignment.TopStart)) {
                    MonitorClipSelection(selected, if (clicks) onSelect else null)
                }
            }
            if (favoriteAction != null) {
                Box(Modifier.align(Alignment.TopEnd)) {
                    MonitorClipFavorite(clip.favorite, favoriteAction)
                }
            }
            ClipBadge(clip.source, Modifier.align(Alignment.BottomStart).padding(6.dp))
            clip.duration?.let { ClipBadge(it, Modifier.align(Alignment.BottomEnd).padding(6.dp)) }
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = 9.dp, vertical = 7.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(clip.title, style = MonitorTypography.text(10.5f, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(clip.detail, color = MonitorPalette.faint, style = MonitorTypography.text(9f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun MonitorClipFavorite(favorite: Boolean, onClick: () -> Unit,
    label: String = if (favorite) "Remove from favorites" else "Add to favorites") {
    Box(Modifier.size(44.dp).combinedClickable(role = Role.Button, onClick = onClick), contentAlignment = Alignment.Center) {
        MonitorIcon(MonitorIcon.STAR, label,
            Modifier.size(13.dp), if (favorite) Color(0xFFE9C35A) else MonitorPalette.muted, favorite)
    }
}

@Composable
fun MonitorClipSelection(selected: Boolean, onClick: (() -> Unit)? = null) {
    Box(Modifier.size(44.dp).then(
        if (onClick != null) Modifier.combinedClickable(role = Role.Checkbox, onClick = onClick) else Modifier,
    ).semantics { contentDescription = if (selected) "Deselect clip" else "Select clip" }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(20.dp).background(if (selected) MonitorPalette.accent else Color.Black.copy(alpha = .56f), CircleShape),
            contentAlignment = Alignment.Center) {
            MonitorIcon(if (selected) MonitorIcon.CHECK else MonitorIcon.CIRCLE, null, Modifier.size(13.dp),
                if (selected) MonitorPalette.backgroundDeep else MonitorPalette.text)
        }
    }
}

@Composable
private fun ClipBadge(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.background(Color.Black.copy(alpha = .55f), RoundedCornerShape(5.dp)).padding(5.dp, 3.dp),
        color = MonitorPalette.text, style = MonitorTypography.text(7.5f, FontWeight.SemiBold), maxLines = 1)
}

/** Mockup: 3+32+2+32+3 and 3+28×3+2×2+3 capsules, 6 dp apart. */
@Composable
fun MonitorCatalogDisplayControls(
    list: Boolean,
    thumbnailSize: MonitorThumbnailSize,
    onList: (Boolean) -> Unit,
    onThumbnailSize: (MonitorThumbnailSize) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            Modifier.clip(RoundedCornerShape(9.dp)).background(Color.Black.copy(alpha = .35f)).padding(3.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            CatalogLayoutCell(
                MonitorIcon.LAYOUT_GRID, "Grid view", selected = !list, onClick = { onList(false) })
            CatalogLayoutCell(
                MonitorIcon.MENU, "List view", selected = list, onClick = { onList(true) })
        }
        Row(
            Modifier.clip(RoundedCornerShape(9.dp)).background(Color.Black.copy(alpha = .35f)).padding(3.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            MonitorThumbnailSize.entries.forEach { size ->
                val selected = size == thumbnailSize
                Box(Modifier.size(28.dp).clip(RoundedCornerShape(7.dp))
                    .background(if (selected) Color.White.copy(alpha = .14f) else Color.Transparent)
                    .combinedClickable(role = Role.Button, onClick = { onThumbnailSize(size) })
                    .semantics {
                        contentDescription = "${size.name.lowercase().replaceFirstChar { it.uppercase() }} thumbnails"
                        this.selected = selected
                    },
                    contentAlignment = Alignment.Center) {
                    Box(Modifier.size((7 + size.ordinal * 3).dp).clip(RoundedCornerShape(3.dp))
                        .background(if (selected) Color.White else MonitorPalette.faint))
                }
            }
        }
    }
}

@Composable
private fun CatalogLayoutCell(icon: MonitorIcon, label: String, selected: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(32.dp, 28.dp).clip(RoundedCornerShape(7.dp))
        .background(if (selected) Color.White.copy(alpha = .14f) else Color.Transparent)
        .combinedClickable(role = Role.Button, onClick = onClick)
        .semantics {
            contentDescription = label
            this.selected = selected
        },
        contentAlignment = Alignment.Center) {
        MonitorIcon(icon, null, Modifier.size(13.dp), if (selected) Color.White else MonitorPalette.muted)
    }
}

@Composable
fun MonitorCatalogHeader(title: String, subtitle: String, compact: Boolean, sort: String,
    filterActive: Boolean, onSort: () -> Unit, onFilter: () -> Unit, modifier: Modifier = Modifier,
    filterCount: Int = 0) {
    val identity: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MonitorTypography.text(10.5f, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = MonitorTypography.text(9f), color = MonitorPalette.faint, maxLines = 1)
        }
    }
    val controls: @Composable () -> Unit = {
        Row(Modifier.horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.height(34.dp).clip(RoundedCornerShape(8.dp)).background(MonitorPalette.tile)
                .combinedClickable(role = Role.Button, onClick = onSort).padding(horizontal = 9.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                MonitorIcon(MonitorIcon.ARROW_UP_DOWN, "Sort clips", Modifier.size(12.dp), MonitorPalette.muted)
                Text(sort, style = MonitorTypography.text(10.5f, FontWeight.Medium), color = MonitorPalette.muted)
            }
            Row(
                Modifier.height(34.dp).clip(RoundedCornerShape(8.dp))
                    .background(
                        if (filterActive) MonitorPalette.accent.copy(alpha = .18f)
                        else MonitorPalette.tile,
                    )
                    .combinedClickable(role = Role.Button, onClick = onFilter)
                    .semantics {
                        contentDescription = "Filter library"
                        selected = filterActive
                    }
                    .padding(horizontal = 9.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                MonitorIcon(
                    MonitorIcon.LIST_FILTER, null, Modifier.size(12.dp),
                    if (filterActive) MonitorPalette.text else MonitorPalette.muted,
                )
                Text(
                    "Filter",
                    style = MonitorTypography.text(10.5f, FontWeight.Medium),
                    color = if (filterActive) MonitorPalette.text else MonitorPalette.muted,
                )
                if (filterCount > 0) {
                    Text(
                        "$filterCount",
                        style = MonitorTypography.text(10.5f, FontWeight.Medium),
                        color = MonitorPalette.text,
                    )
                }
            }
        }
    }
    if (compact) Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) { identity(); controls() }
    else Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.weight(1f)) { identity() }; controls()
    }
}
