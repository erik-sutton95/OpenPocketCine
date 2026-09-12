package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.ChromeShape
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.chromeClickable

/**
 * OpenZCine `AssistToolCell`: 19dp glyph over a 9sp mono label. On-state is
 * iOS `AssistToolChip`: accent-dim fill plus a 1pt accent stroke.
 */
@Composable
internal fun AssistToolCell(
    tool: LiveAssistTool,
    isOn: Boolean,
    enabled: Boolean,
    onLongClick: (() -> Unit)?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tint = if (isOn) LiveDesign.accent else LiveDesign.muted
    Column(
        modifier =
            modifier
                .background(if (isOn) LiveDesign.accentDim else Color.Transparent, ChromeShape)
                .border(1.dp, if (isOn) LiveDesign.accent else Color.Transparent, ChromeShape)
                .chromeClickable(
                    enabled = enabled,
                    onLongClick = onLongClick,
                    onClick = onClick,
                )
                .padding(vertical = 5.dp, horizontal = 8.dp)
                .widthIn(min = 36.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.height(23.dp), contentAlignment = Alignment.Center) {
            AssistToolGlyph(tool, tint, Modifier.size(19.dp))
        }
        Text(
            tool.chipLabel,
            style = LiveType.mono(9f, FontWeight.Medium).copy(letterSpacing = 0.9.sp),
            color = tint,
            maxLines = 1,
        )
    }
}

/** Cyan edge chevron hinting at off-screen tools (OpenZCine `ScrollChevron`). */
@Composable
internal fun AssistScrollChevron(leading: Boolean, visible: Boolean, modifier: Modifier = Modifier) {
    OpcIcon(
        icon = if (leading) OpcIcon.CHEVRON_LEFT else OpcIcon.CHEVRON_RIGHT,
        contentDescription = null,
        tint = LiveDesign.accent,
        modifier =
            modifier
                .padding(horizontal = 5.dp)
                .size(12.dp)
                .alpha(if (visible) 1f else 0f),
    )
}

/** The supplied design owns assist glyphs; the existing ND extension uses Lucide. */
@Composable
internal fun AssistToolGlyph(tool: LiveAssistTool, tint: Color, modifier: Modifier = Modifier) {
    val icon = when (tool) {
        LiveAssistTool.LUT -> com.opencapture.monitorui.MonitorAssistIcon.LUT
        LiveAssistTool.PEAK -> com.opencapture.monitorui.MonitorAssistIcon.PEAKING
        LiveAssistTool.FALSE -> com.opencapture.monitorui.MonitorAssistIcon.FALSE_COLOR
        LiveAssistTool.ZEBRA -> com.opencapture.monitorui.MonitorAssistIcon.ZEBRA
        LiveAssistTool.WAVE -> com.opencapture.monitorui.MonitorAssistIcon.WAVEFORM
        LiveAssistTool.PARADE -> com.opencapture.monitorui.MonitorAssistIcon.RGB_PARADE
        LiveAssistTool.HISTO -> com.opencapture.monitorui.MonitorAssistIcon.HISTOGRAM
        LiveAssistTool.VECTOR -> com.opencapture.monitorui.MonitorAssistIcon.VECTORSCOPE
        LiveAssistTool.LIGHTS -> com.opencapture.monitorui.MonitorAssistIcon.TRAFFIC_LIGHTS
        LiveAssistTool.GUIDES -> com.opencapture.monitorui.MonitorAssistIcon.FRAME_GUIDE
        LiveAssistTool.GRID -> com.opencapture.monitorui.MonitorAssistIcon.GRID
        LiveAssistTool.CROSS -> com.opencapture.monitorui.MonitorAssistIcon.CROSSHAIR
        LiveAssistTool.MIRROR -> com.opencapture.monitorui.MonitorAssistIcon.MIRROR
        LiveAssistTool.AUDIO -> com.opencapture.monitorui.MonitorAssistIcon.AUDIO_METERS
        LiveAssistTool.ND -> null
    }
    if (icon == null) OpcIcon(OpcIcon.APERTURE, null, modifier, tint)
    else com.opencapture.monitorui.MonitorAssistIcon(icon, tint, modifier)
}
