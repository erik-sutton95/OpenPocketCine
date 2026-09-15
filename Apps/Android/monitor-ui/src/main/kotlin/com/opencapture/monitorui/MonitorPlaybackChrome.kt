package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.max
import kotlin.math.min

/**
 * Chrome-only metrics from iOS `MonitorPlaybackLayout`.
 * Transport is three 48 pt skip/play/skip controls; four 44 pt option chips
 * trail in landscape. Inspector is a 296 pt trailing plate.
 */
object MonitorPlaybackLayout {
    const val TRANSPORT_SIZE = 48f
    const val TRANSPORT_SPACING = 8f
    const val ACTION_SIZE = 44f
    const val ACTION_SPACING = 8f
    const val PHONE_CONTENT_MAX = 630f
    const val TABLET_CONTENT_MAX = 860f
    const val INSPECTOR_WIDTH = 296f
    const val HEADER_SIDE_EXTRA = 28f
    const val HEADER_TOP_PORTRAIT = 20f
    const val HEADER_BOTTOM = 18f
    const val FOOTER_INNER_HORIZONTAL = 12f
    const val FOOTER_INNER_TOP = 14f
    const val FOOTER_INNER_BOTTOM = 5f
    const val PHOTO_HEADER_HORIZONTAL = 16f
    const val PHOTO_HEADER_TOP_EXTRA = 14f
    const val PHOTO_FAVORITE_BOTTOM = 18f
    const val CLIP_NAV_SIZE = 32f
    const val CLIP_NAV_CENTER = 22f
    const val FOOTER_GAP = 10f
    const val TITLE_SIZE = 13f
    const val SUBTITLE_SIZE = 9.5f
    const val SOURCE_SIZE = 8f
    const val SOURCE_TRACKING = 0.5f
    const val SOURCE_CORNER = 5f
    const val IDENTITY_SPACING = 4f
    const val LANDSCAPE_HEADER_SPACING = 12f
    const val PLAY_ICON_SIZE = 26f
    const val TRANSPORT_ICON_SIZE = 18f

    val transportWidth: Float get() = TRANSPORT_SIZE * 3 + TRANSPORT_SPACING * 2
    val actionsWidth: Float get() = ACTION_SIZE * 4 + ACTION_SPACING * 3
    val minimumFooterWidth: Float get() = transportWidth + actionsWidth + FOOTER_GAP

    fun transportStart(width: Float): Float =
        min((width - transportWidth) / 2f, width - minimumFooterWidth).coerceAtLeast(0f)

    fun headerGutter(sideInset: Float): Float = max(0f, sideInset) + HEADER_SIDE_EXTRA

    fun headerTop(portrait: Boolean, safeTop: Float, lockY: Float): Float =
        if (portrait) max(0f, safeTop) + HEADER_TOP_PORTRAIT else lockY

    fun clipNavEdgePadding(): Float = CLIP_NAV_CENTER - CLIP_NAV_SIZE / 2f

}

/** File metadata comes from the media adapter; the monitor never infers a source. */
@Composable
fun MonitorPlaybackHeader(title: String, subtitle: String, source: String, portrait: Boolean,
    modifier: Modifier = Modifier, actions: @Composable RowScope.() -> Unit) {
    val identity: @Composable RowScope.() -> Unit = {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(MonitorPlaybackLayout.IDENTITY_SPACING.dp)) {
            Text(
                title,
                style = MonitorTypography.text(MonitorPlaybackLayout.TITLE_SIZE, FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (subtitle.isNotBlank()) {
                Text(
                    subtitle,
                    style = MonitorTypography.text(MonitorPlaybackLayout.SUBTITLE_SIZE),
                    color = MonitorPalette.muted,
                    maxLines = if (portrait) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (source.isNotBlank()) {
                Text(
                    source,
                    style = MonitorTypography.text(MonitorPlaybackLayout.SOURCE_SIZE, FontWeight.Bold)
                        .copy(letterSpacing = MonitorPlaybackLayout.SOURCE_TRACKING.sp),
                    color = MonitorPalette.secondary,
                    modifier = Modifier
                        .background(Color.Black.copy(alpha = .5f), RoundedCornerShape(MonitorPlaybackLayout.SOURCE_CORNER.dp))
                        .padding(horizontal = 6.dp, vertical = 4.dp),
                )
            }
        }
    }
    if (portrait) {
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MonitorPlaybackLayout.IDENTITY_SPACING.dp)) {
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                content = identity,
            )
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(MonitorPlaybackLayout.ACTION_SPACING.dp, Alignment.End),
                content = actions,
            )
        }
    } else {
        Row(
            modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(MonitorPlaybackLayout.LANDSCAPE_HEADER_SPACING.dp),
        ) {
            identity()
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(MonitorPlaybackLayout.ACTION_SPACING.dp),
                content = actions,
            )
        }
    }
}

@Composable
fun MonitorPlaybackFooter(position: String, duration: String, portrait: Boolean,
    modifier: Modifier = Modifier, scrubber: @Composable () -> Unit,
    transport: @Composable () -> Unit, options: @Composable () -> Unit) {
    val configuration = LocalConfiguration.current
    val tablet = minOf(configuration.screenWidthDp, configuration.screenHeightDp) >= 600
    val contentCap = if (tablet) MonitorPlaybackLayout.TABLET_CONTENT_MAX else MonitorPlaybackLayout.PHONE_CONTENT_MAX
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = contentCap.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(2.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(position, style = MonitorTypography.readout(11f, FontWeight.Bold))
                Text(duration, color = MonitorPalette.secondary, style = MonitorTypography.readout(11f))
            }
            scrubber()
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val footerWidth = maxWidth.value
                if (portrait || footerWidth < MonitorPlaybackLayout.minimumFooterWidth) {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        transport()
                        options()
                    }
                } else {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Spacer(Modifier.width(MonitorPlaybackLayout.transportStart(footerWidth).dp))
                        transport()
                        Spacer(Modifier.weight(1f))
                        options()
                    }
                }
            }
        }
    }
}

@Immutable
data class MonitorMetadataRow(val label: String, val value: String)

@Composable
fun MonitorMetadataDrawer(rows: List<MonitorMetadataRow>, modifier: Modifier = Modifier,
    close: @Composable () -> Unit) {
    Column(
        modifier
            .width(MonitorPlaybackLayout.INSPECTOR_WIDTH.dp)
            .fillMaxHeight()
            .clip(RoundedCornerShape(14.dp))
            .monitorMaterial(MonitorMaterial.Info)
            .padding(top = 12.dp, bottom = 8.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "CLIP INFO",
                modifier = Modifier.weight(1f).padding(start = 12.dp),
                style = MonitorTypography.text(9f, FontWeight.Bold).copy(letterSpacing = 1.8.sp),
            )
            Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { close() }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            rows.forEach { row ->
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 9.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Text(row.label, color = MonitorPalette.muted, style = MonitorTypography.text(11f, FontWeight.SemiBold))
                    Text(
                        row.value,
                        modifier = Modifier.weight(1f),
                        color = MonitorPalette.secondary,
                        style = MonitorTypography.readout(11f),
                        textAlign = TextAlign.End,
                    )
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = .04f)))
            }
        }
    }
}
