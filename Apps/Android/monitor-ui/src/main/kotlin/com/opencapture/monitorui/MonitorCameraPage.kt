package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Immutable
data class MonitorCameraSection<T>(
    val title: String,
    val cameras: List<T>,
    val note: String = "",
)

/** The shell supplies identities, availability and actions; this page owns only layout. */
@Composable
fun <T> MonitorCameraPage(
    brand: String,
    sections: List<MonitorCameraSection<T>>,
    key: (T) -> Any,
    emptyMessage: String,
    modifier: Modifier = Modifier,
    title: String = "Your cameras",
    emptyTitle: String = "No cameras saved yet",
    scanning: Boolean = false,
    actions: @Composable RowScope.() -> Unit,
    camera: @Composable (T) -> Unit,
    footer: @Composable () -> Unit,
) {
    val config = LocalConfiguration.current
    val tablet = minOf(config.screenWidthDp, config.screenHeightDp) >= 600
    val landscape = config.screenWidthDp > config.screenHeightDp
    val fullLabels = landscape || tablet
    Column(modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(if (fullLabels) 12.dp else 8.dp),
        ) {
            Column(
                Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    brand,
                    color = MonitorPalette.accent,
                    style = MonitorTypography.text(8.5f, FontWeight.Bold).copy(letterSpacing = 1.7.sp),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        title,
                        color = MonitorPalette.text,
                        style = MonitorTypography.text(
                            MonitorLayoutPolicy.cameraPageTitleSize(tablet),
                            FontWeight.SemiBold,
                        ).copy(letterSpacing = (-0.2).sp),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    if (scanning) MonitorCameraScanStatus(fullLabels = fullLabels)
                }
            }
            actions()
        }
        val gridState = rememberLazyGridState()
        LazyVerticalGrid(
            columns = GridCells.Fixed(if (tablet) 2 else 1),
            modifier = Modifier.weight(1f).monitorScrollFade(gridState),
            state = gridState,
            contentPadding = PaddingValues(bottom = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val visible = sections.filter { it.cameras.isNotEmpty() }
            visible.forEachIndexed { index, section ->
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Row(
                        Modifier.fillMaxWidth().padding(top = if (index == 0) 0.dp else 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(9.dp),
                    ) {
                        Text(
                            section.title,
                            color = MonitorPalette.faint,
                            style = MonitorTypography.text(8.5f, FontWeight.Bold)
                                .copy(letterSpacing = 1.7.sp),
                            maxLines = 1,
                        )
                        if (section.note.isNotEmpty()) {
                            Text(
                                section.note,
                                color = MonitorPalette.faint,
                                style = MonitorTypography.text(9f).copy(letterSpacing = 0.9.sp),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f, fill = false),
                            )
                        }
                    }
                }
                items(section.cameras.size, key = { key(section.cameras[it]) }) {
                    Box(Modifier.fillMaxWidth()) { camera(section.cameras[it]) }
                }
            }
            if (visible.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                Column(
                    Modifier.fillMaxWidth()
                        .clip(RoundedCornerShape(MonitorLayoutPolicy.CAMERA_CARD_CORNER.dp))
                        .background(MonitorPalette.surface)
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        emptyTitle,
                        color = MonitorPalette.text,
                        style = MonitorTypography.text(15f, FontWeight.SemiBold),
                    )
                    Text(
                        emptyMessage,
                        color = MonitorPalette.muted,
                        style = MonitorTypography.text(12f),
                    )
                }
            }
        }
        footer()
    }
}

@Composable
fun MonitorCameraCard(
    title: String,
    detail: String,
    status: String,
    actionTitle: String,
    enabled: Boolean,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
    badge: String = "",
    primary: Boolean = false,
    busy: Boolean = false,
    available: Boolean = true,
    onCancel: (() -> Unit)? = null,
    glyph: @Composable () -> Unit,
    options: @Composable () -> Unit = {},
    /** Saved-camera setups (#406); empty hides the chip row. */
    setups: List<MonitorSetupChip> = emptyList(),
    canAddSetup: Boolean = false,
    /** False while any camera is connecting (iOS disables the chips while busy). */
    setupsEnabled: Boolean = true,
    onSetup: ((MonitorSetupChip) -> Unit)? = null,
    onAddSetup: (() -> Unit)? = null,
    onForgetSetup: ((MonitorSetupChip) -> Unit)? = null,
    /** Connection progress while [busy]; empty keeps the one-line status. */
    steps: List<MonitorConnectStep> = emptyList(),
    failure: MonitorConnectFailure? = null,
    onFailureAction: ((String) -> Unit)? = null,
) {
    val shape = RoundedCornerShape(MonitorLayoutPolicy.CAMERA_CARD_CORNER.dp)
    val fill = if (primary) CameraCardPrimaryFill else CameraCardFill
    val stroke = if (primary) MonitorPalette.accent.copy(alpha = 0.26f) else Color.White.copy(alpha = 0.06f)
    Column(
        modifier.fillMaxWidth()
            .clip(shape)
            .background(fill)
            .border(1.dp, stroke, shape)
            .padding(horizontal = 14.dp, vertical = 13.dp),
        verticalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(11.dp),
        ) {
            Box(
                Modifier.size(40.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(
                        if (primary) MonitorPalette.accent.copy(alpha = 0.14f)
                        else Color.White.copy(alpha = 0.05f),
                    ),
                contentAlignment = Alignment.Center,
            ) { glyph() }
            Column(
                Modifier.weight(1f)
                    .heightIn(min = 44.dp)
                    .clickable(enabled = enabled, onClick = onOpen),
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Text(
                    title,
                    color = MonitorPalette.text,
                    style = MonitorTypography.text(14.5f, FontWeight.SemiBold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    detail,
                    color = MonitorPalette.muted,
                    style = MonitorTypography.text(9.5f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (badge.isNotEmpty()) {
                Text(
                    badge,
                    color = if (primary) MonitorPalette.accent else MonitorPalette.muted,
                    style = MonitorTypography.text(8f, FontWeight.Bold).copy(letterSpacing = 1.1.sp),
                    maxLines = 1,
                    softWrap = false,
                    modifier = Modifier
                        .background(
                            if (primary) MonitorPalette.accent.copy(alpha = 0.16f)
                            else Color.White.copy(alpha = 0.06f),
                            RoundedCornerShape(5.dp),
                        )
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                )
            }
        }
        if (setups.isNotEmpty() && onSetup != null) {
            MonitorSetupChips(title, setups, canAddSetup, setupsEnabled, onSetup, onAddSetup, onForgetSetup)
        }
        if (busy && steps.isNotEmpty()) MonitorConnectProgressBar(steps)
        if (failure != null && !busy) MonitorConnectFailureBanner(failure, enabled, onFailureAction)
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            if (busy && steps.isNotEmpty()) {
                Text(
                    MonitorConnectProgress.caption(steps),
                    color = MonitorPalette.muted,
                    style = MonitorTypography.text(10.5f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
            } else if (failure != null && !busy) {
                Spacer(Modifier.weight(1f))
            } else if (busy) {
                Row(
                    Modifier.weight(1f),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    val pulse = monitorPulsePhase(1400)
                    Box(
                        Modifier.size(6.dp).background(
                            MonitorPalette.accent.copy(alpha = 1f - 0.75f * pulse),
                            CircleShape,
                        ),
                    )
                    Text(
                        status,
                        color = MonitorPalette.accent,
                        style = MonitorTypography.text(10f, FontWeight.SemiBold),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            } else {
                Text(
                    status,
                    color = if (available) MonitorPalette.muted else MonitorPalette.faint,
                    style = MonitorTypography.text(9.5f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
            }
            options()
            if (failure != null && !busy && onFailureAction != null) {
                failure.actions.forEach { action ->
                    MonitorCameraAction(
                        text = action.title,
                        primary = action.primary,
                        enabled = enabled,
                        contentDescription = "${action.title} ${title}",
                        onClick = { onFailureAction(action.id) },
                    )
                }
            } else {
                MonitorCameraAction(
                    text = if (busy) "Cancel" else actionTitle,
                    primary = primary && !busy,
                    enabled = if (busy) onCancel != null else enabled,
                    contentDescription = if (busy) "Cancel connecting to $title" else "$actionTitle $title",
                    onClick = { if (busy) onCancel?.invoke() else onOpen() },
                )
            }
        }
    }
}

/** A status beside the title, not a button: no plate or frame. */
@Composable
private fun MonitorCameraScanStatus(fullLabels: Boolean) {
    val phase = monitorPulsePhase(1400)
    Row(
        Modifier.semantics(mergeDescendants = true) { contentDescription = "Scanning for cameras" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier.size(6.dp).background(
                MonitorPalette.accent.copy(alpha = 1f - 0.75f * phase),
                CircleShape,
            ),
        )
        if (fullLabels) {
            Text(
                "SCANNING",
                color = MonitorPalette.accent,
                style = MonitorTypography.text(9.5f, FontWeight.Bold).copy(letterSpacing = 1.1.sp),
                maxLines = 1,
            )
        }
    }
}

/** The app's standard action button. Destructive uses the record red. */
@Composable
fun MonitorCameraAction(
    text: String,
    primary: Boolean,
    enabled: Boolean,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    destructive: Boolean = false,
    icon: (@Composable (Color) -> Unit)? = null,
) {
    val shape = RoundedCornerShape(11.dp)
    val ink = when {
        primary -> CameraCardPrimaryInk
        destructive -> MonitorPalette.recording
        else -> MonitorPalette.secondary
    }
    Row(
        modifier.alpha(if (enabled) 1f else 0.38f)
            .heightIn(min = 42.dp)
            .clip(shape)
            .background(
                when {
                    primary -> MonitorPalette.accent
                    destructive -> MonitorPalette.recording.copy(alpha = 0.12f)
                    else -> Color.White.copy(alpha = 0.06f)
                },
            )
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { this.contentDescription = contentDescription }
            .padding(horizontal = 17.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally),
    ) {
        icon?.invoke(ink)
        Text(
            text,
            color = ink,
            style = MonitorTypography.text(13f, FontWeight.SemiBold),
            maxLines = 1,
        )
    }
}

private val CameraCardFill = Color(23, 24, 25)
private val CameraCardPrimaryFill = Color(28, 30, 31)
private val CameraCardPrimaryInk = Color(8, 25, 31)
