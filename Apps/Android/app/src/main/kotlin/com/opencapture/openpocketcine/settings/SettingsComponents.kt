package com.opencapture.openpocketcine.settings

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.monitorui.MonitorIcon
import com.opencapture.openpocketcine.panelGlass
import kotlin.math.roundToInt

// Compose ports of the iOS operator-settings primitives (SettingsRootView /
// AppSettings: SettingsRowCard, SettingsInlineRow, SettingsSwitchInlineRow,
// SettingsSwitchGraphic, SettingsValueText, SettingsGroupCard,
// DisplayToggleItem, CloseButton, HelpBadge). Same metrics as OpenZCine
// Android; Pocket tokens stay DJI-black / cyan.

/** Ripple-free click carrying a semantics [role] (the settings-panel `chromeClickable`). */
@Composable
internal fun Modifier.settingsClickable(role: Role, enabled: Boolean = true, onClick: () -> Unit): Modifier =
    clickable(
        interactionSource = remember { MutableInteractionSource() },
        indication = null,
        enabled = enabled,
        role = role,
        onClick = onClick,
    )

/** One named swatch for [SettingsColorDots] (iOS `SettingsColorDots.Dot`). */
data class SettingsColorDot(val name: String, val color: Color)

/** iOS `SettingsPalette` - zone-scoped stripe/peaking colours; each dot shows the colour its overlay paints. */
object SettingsPalette {
    val highlight: List<SettingsColorDot> =
        listOf(
            SettingsColorDot("White", LiveDesign.text),
            SettingsColorDot("Amber", LiveDesign.amber),
            SettingsColorDot("Red", LiveDesign.rec),
        )
    val midtone: List<SettingsColorDot> =
        listOf(
            SettingsColorDot("Amber", LiveDesign.amber),
            SettingsColorDot("Cyan", Color(0f, 0.85f, 0.9f)),
            SettingsColorDot("Green", LiveDesign.good),
        )
    val peaking: List<SettingsColorDot> =
        listOf(
            SettingsColorDot("White", LiveDesign.text),
            SettingsColorDot("Blue", Color(64f / 255f, 142f / 255f, 1f)),
            SettingsColorDot("Red", LiveDesign.rec),
            SettingsColorDot("Green", LiveDesign.good),
        )
}

/** Existing assist values adapt to a compact iOS-like track rather than the 44dp drum slider. */
@Composable
fun GlassPillSlider(value: Int, range: IntRange, onChange: (Int) -> Unit, modifier: Modifier = Modifier) {
    val currentOnChange by rememberUpdatedState(onChange)
    val start = range.first.toFloat()
    val endInclusive = range.last.toFloat().coerceAtLeast(start)
    val span = (endInclusive - start).coerceAtLeast(1f)
    var widthPx by remember { mutableFloatStateOf(1f) }
    val density = LocalDensity.current
    fun atX(x: Float): Int {
        val inset = with(density) { 10.dp.toPx() }
        val t = ((x - inset) / (widthPx - 2f * inset).coerceAtLeast(1f)).coerceIn(0f, 1f)
        return (start + t * span).roundToInt().coerceIn(range)
    }
    Canvas(
        modifier
            .fillMaxWidth()
            .height(44.dp)
            .onSizeChanged { widthPx = it.width.toFloat() }
            .semantics {
                progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), start..endInclusive)
                setProgress {
                    val next = it.roundToInt().coerceIn(range)
                    if (next != value) onChange(next)
                    true
                }
            }
            .pointerInput(range) { detectTapGestures { currentOnChange(atX(it.x)) } }
            .pointerInput(range) {
                detectHorizontalDragGestures { change, _ ->
                    change.consume()
                    currentOnChange(atX(change.position.x))
                }
            },
    ) {
        val y = size.height / 2f
        val inset = 10.dp.toPx()
        val track = 2.dp.toPx()
        val t = ((value.toFloat() - start) / span).coerceIn(0f, 1f)
        val thumbX = inset + t * (size.width - 2f * inset)
        drawLine(
            LiveDesign.hairlineStrong,
            Offset(inset, y),
            Offset(size.width - inset, y),
            track,
            StrokeCap.Round,
        )
        drawLine(LiveDesign.accent, Offset(inset, y), Offset(thumbX, y), track, StrokeCap.Round)
        drawCircle(Color.White, 10.dp.toPx(), Offset(thumbX, y))
    }
}

/** Floating xmark close button on a glass circle (iOS `CloseButton`, 37pt). */
@Composable
fun PanelCloseButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(37.dp)
            .panelGlass(CircleShape)
            .settingsClickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = "Close" },
        contentAlignment = Alignment.Center,
    ) {
        MonitorIcon(
            icon = MonitorIcon.X,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(13.dp),
        )
    }
}
