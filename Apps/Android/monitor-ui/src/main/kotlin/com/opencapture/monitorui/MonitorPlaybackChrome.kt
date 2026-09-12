package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** File metadata comes from the media adapter; the monitor never infers a source. */
@Composable
fun MonitorPlaybackHeader(title: String, subtitle: String, source: String, portrait: Boolean,
    modifier: Modifier = Modifier, back: @Composable () -> Unit, actions: @Composable RowScope.() -> Unit) {
    val identity: @Composable RowScope.() -> Unit = {
        back()
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MonitorTypography.text(12.5f, FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = MonitorTypography.text(9.5f), color = Color(0xFFB6BBBC), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (source.isNotBlank()) Text(source, style = MonitorTypography.text(9f, FontWeight.SemiBold),
            modifier = Modifier.background(Color.Black.copy(alpha = .5f), RoundedCornerShape(6.dp)).padding(7.dp, 5.dp))
    }
    if (portrait) Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), content = identity)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End), content = actions)
    } else Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) { identity(); actions() }
}

@Composable
fun MonitorPlaybackFooter(position: String, duration: String, portrait: Boolean,
    modifier: Modifier = Modifier, scrubber: @Composable () -> Unit,
    transport: @Composable () -> Unit, options: @Composable () -> Unit) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
    val stacked = portrait || maxWidth < 760.dp
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(position, style = MonitorTypography.readout(11f, FontWeight.SemiBold))
            Text(duration, color = Color(0xFFB6BBBC), style = MonitorTypography.readout(11f))
        }
        scrubber()
        if (stacked) {
            Box(Modifier.padding(vertical = 5.dp)) { transport() }
            Box(Modifier.padding(top = 4.dp)) { options() }
        } else {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                transport()
                Box(Modifier.align(Alignment.CenterEnd)) { options() }
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
    Column(modifier.width(296.dp).fillMaxHeight()
        .clip(RoundedCornerShape(topStart = 14.dp, bottomStart = 14.dp))
        .background(Color(0xFF141618).copy(alpha = .82f)).padding(top = 12.dp, bottom = 8.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("CLIP INFO", modifier = Modifier.weight(1f), style = MonitorTypography.text(9f, FontWeight.SemiBold))
            close()
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            rows.forEach { row ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 9.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                    Text(row.label, color = MonitorPalette.muted, style = MonitorTypography.text(11f, FontWeight.SemiBold))
                    Text(row.value, modifier = Modifier.weight(1f), style = MonitorTypography.readout(11f), textAlign = TextAlign.End)
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = .04f)))
            }
        }
    }
}
