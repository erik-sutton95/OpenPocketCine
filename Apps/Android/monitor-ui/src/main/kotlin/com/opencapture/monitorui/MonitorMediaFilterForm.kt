package com.opencapture.monitorui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.clickable
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Immutable
data class MonitorMediaColorOption(val id: Int, val label: String)

@Composable
fun MonitorMediaFilterForm(
    formats: List<String>,
    resolutions: List<String>,
    colors: List<MonitorMediaColorOption>,
    formatSelection: Set<String>,
    resolutionSelection: Set<String>,
    colorSelection: Set<Int>,
    dateStartLabel: String?,
    dateEndLabel: String?,
    hasDates: Boolean,
    onToggleFormat: (String) -> Unit,
    onToggleResolution: (String) -> Unit,
    onToggleColor: (Int) -> Unit,
    onPickStart: () -> Unit,
    onPickEnd: () -> Unit,
    onClear: () -> Unit,
) {
    val empty = formats.isEmpty() && resolutions.isEmpty() && !hasDates && colors.isEmpty()
    val active = formatSelection.isNotEmpty() || resolutionSelection.isNotEmpty() ||
        colorSelection.isNotEmpty() || dateStartLabel != null || dateEndLabel != null
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (formats.isNotEmpty()) FilterChips("FORMAT", formats, formatSelection, onToggleFormat)
        if (resolutions.isNotEmpty()) FilterChips("RESOLUTION", resolutions, resolutionSelection, onToggleResolution)
        if (hasDates) {
            FilterHeading("DATE")
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                FilterDateChip("Start", dateStartLabel, Modifier.weight(1f), onPickStart)
                Text("–", color = MonitorPalette.muted, style = MonitorTypography.text(10.5f, FontWeight.SemiBold))
                FilterDateChip("End", dateEndLabel, Modifier.weight(1f), onPickEnd)
            }
        }
        if (colors.isNotEmpty()) {
            FilterChips("COLOUR", colors.map { it.label }, colors.filter { it.id in colorSelection }.map { it.label }.toSet()) { title ->
                colors.firstOrNull { it.label == title }?.let { onToggleColor(it.id) }
            }
        }
        if (empty) {
            Text("Nothing in this tab to filter by.", color = MonitorPalette.faint, style = MonitorTypography.text(11f))
        }
        if (active) {
            Text(
                "Clear all filters",
                color = MonitorPalette.accent,
                style = MonitorTypography.text(11f, FontWeight.SemiBold),
                modifier = Modifier.padding(top = 2.dp).clickable(onClick = onClear),
            )
        }
    }
}

@Composable
private fun FilterHeading(title: String) {
    Text(title, color = MonitorPalette.muted, style = MonitorTypography.text(9f, FontWeight.Bold),
        modifier = Modifier.padding(bottom = 5.dp))
}

@Composable
private fun FilterChips(title: String, titles: List<String>, active: Set<String>, onToggle: (String) -> Unit) {
    Column(Modifier.padding(bottom = 2.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        FilterHeading(title)
        titles.forEach { title ->
            val on = title in active
            Text(
                title,
                color = if (on) MonitorPalette.accent else MonitorPalette.muted,
                style = MonitorTypography.text(10f, FontWeight.SemiBold),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(999.dp))
                    .background(if (on) MonitorPalette.accent.copy(alpha = .14f) else Color.White.copy(alpha = .04f))
                    .clickable { onToggle(title) }
                    .padding(horizontal = 8.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun FilterDateChip(title: String, label: String?, modifier: Modifier, onClick: () -> Unit) {
    Text(
        label ?: title,
        color = if (label == null) MonitorPalette.muted else MonitorPalette.text,
        style = MonitorTypography.text(10.5f, FontWeight.SemiBold),
        modifier = modifier
            .clip(RoundedCornerShape(9.dp))
            .background(Color.White.copy(alpha = 0.04f))
            .clickable(onClick = onClick)
            .semantics { contentDescription = title }
            .heightIn(min = 34.dp)
            .padding(horizontal = 11.dp, vertical = 8.dp),
    )
}
