package com.opencapture.openpocketcine.settings

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.opencapture.openpocketcine.ChromeShape
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.openpocketcine.glass.LiquidSlider
import com.opencapture.openpocketcine.panelGlass
import kotlin.math.roundToInt

private fun chromeStyle(size: Float, weight: FontWeight, mono: Boolean = false): TextStyle =
    if (mono) LiveType.mono(size, weight) else LiveType.ui(size, weight)

/** Watch band — orange, matching iOS `SettingsDashScale` (not the cyan accent). */
private val WatchOrange = Color(0.96f, 0.52f, 0.12f)

// Compose ports of the iOS operator-settings primitives (SettingsRootView /
// AppSettings: SettingsRowCard, SettingsInlineRow, SettingsSwitchInlineRow,
// SettingsSwitchGraphic, SettingsValueText, SettingsGroupCard,
// DisplayToggleItem, CloseButton, HelpBadge). Same metrics as OpenZCine
// Android; Pocket tokens stay DJI-black / cyan.

/** Ripple-free click carrying a semantics [role] (the settings-panel `chromeClickable`). */
@Composable
internal fun Modifier.settingsClickable(role: Role, onClick: () -> Unit): Modifier =
    clickable(
        interactionSource = remember { MutableInteractionSource() },
        indication = null,
        role = role,
        onClick = onClick,
    )

/**
 * A card whose rows are divider-separated with no per-row borders (iOS
 * `SettingsRowCard`). Optional [title] / [onReset] match the assist-tool cards
 * on Operator Setup → View Assist.
 */
@Composable
fun SettingsRowCard(
    title: String? = null,
    onReset: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    Column(
        Modifier.fillMaxWidth()
            .panelGlass(ChromeShape)
            .padding(horizontal = 13.dp)
            .padding(bottom = 4.dp),
    ) {
        if (title != null) {
            Row(
                Modifier.fillMaxWidth().padding(top = 11.dp, bottom = 2.dp).defaultMinSize(minHeight = 24.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    title,
                    style = chromeStyle(13f, FontWeight.SemiBold),
                    color = LiveDesign.text,
                )
                Spacer(Modifier.weight(1f))
                if (onReset != null) {
                    SettingsResetButton(onClick = onReset)
                }
            }
        }
        content()
    }
}

/** Circular counter-clockwise reset control (iOS `SettingsResetButton`, 28dp). */
@Composable
fun SettingsResetButton(onClick: () -> Unit) {
    val description = "Reset to defaults"
    Box(
        Modifier.size(28.dp)
            .background(LiveDesign.background.copy(alpha = 0.42f), CircleShape)
            .border(1.dp, LiveDesign.hairline, CircleShape)
            .settingsClickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        // Simple two-arc “↺” mark without pulling in an icon dependency.
        Canvas(Modifier.size(12.dp)) {
            val stroke = 1.6.dp.toPx()
            drawArc(
                color = LiveDesign.muted,
                startAngle = -40f,
                sweepAngle = 260f,
                useCenter = false,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
            val tipX = size.width * 0.78f
            val tipY = size.height * 0.18f
            drawLine(
                LiveDesign.muted,
                Offset(tipX - 3.dp.toPx(), tipY),
                Offset(tipX, tipY),
                stroke,
                StrokeCap.Round,
            )
            drawLine(
                LiveDesign.muted,
                Offset(tipX, tipY),
                Offset(tipX, tipY + 3.dp.toPx()),
                stroke,
                StrokeCap.Round,
            )
        }
    }
}

/**
 * Accent capsule action used on Link / System trailing controls (iOS
 * `SettingsActionPill`). Title is uppercased to match the iOS monospaced pill.
 */
@Composable
fun SettingsActionPill(
    title: String,
    icon: OpcIcon? = null,
    tint: Color = LiveDesign.accent,
    background: Color = LiveDesign.accentDim,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Row(
        modifier
            .background(background, CircleShape)
            .border(1.dp, tint.copy(alpha = 0.5f), CircleShape)
            .settingsClickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let {
            OpcIcon(icon = it, contentDescription = null, tint = tint, modifier = Modifier.size(15.dp))
        }
        Text(
            title.uppercase(),
            style = chromeStyle(10.5f, FontWeight.Bold, mono = true),
            color = tint,
            maxLines = 1,
            letterSpacing = 0.6.sp,
        )
    }
}

/**
 * Link Health dash-scale meter (iOS `SettingsDashScale`): POOR / WATCH / STABLE
 * marker over a 12-dash track with a three-band legend.
 */
@Composable
fun SettingsDashScale(title: String, caption: String, score: Int) {
    val band =
        when {
            score >= 80 -> LinkHealthBand.STABLE
            score >= 50 -> LinkHealthBand.WATCH
            else -> LinkHealthBand.POOR
        }
    val bandColor =
        when (band) {
            LinkHealthBand.POOR -> LiveDesign.rec
            LinkHealthBand.WATCH -> WatchOrange
            LinkHealthBand.STABLE -> LiveDesign.good
        }
    val litCount =
        when (band) {
            LinkHealthBand.POOR -> 4
            LinkHealthBand.WATCH -> 8
            LinkHealthBand.STABLE -> 12
        }
    val bandSlot =
        when (band) {
            LinkHealthBand.POOR -> 0
            LinkHealthBand.WATCH -> 1
            LinkHealthBand.STABLE -> 2
        }
    Column(
        Modifier.fillMaxWidth()
            .panelGlass(ChromeShape)
            .padding(13.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Text(title, style = chromeStyle(13f, FontWeight.SemiBold), color = LiveDesign.text)
        Text(
            caption,
            style = chromeStyle(11.5f, FontWeight.Medium, mono = true),
            color = LiveDesign.muted,
        )
        Row(Modifier.fillMaxWidth().height(19.dp)) {
            repeat(3) { slot ->
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    if (slot == bandSlot) {
                        Text(
                            band.label,
                            style = chromeStyle(9.5f, FontWeight.Bold, mono = true),
                            color = bandColor,
                            letterSpacing = 0.5.sp,
                            modifier =
                                Modifier
                                    .background(bandColor.copy(alpha = 0.12f), CircleShape)
                                    .border(1.dp, bandColor, CircleShape)
                                    .padding(horizontal = 10.dp, vertical = 4.dp),
                        )
                    }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            repeat(12) { index ->
                val fill =
                    when {
                        index >= litCount -> LiveDesign.hairlineStrong
                        index < 4 -> LiveDesign.rec.copy(alpha = 0.8f)
                        index < 8 -> WatchOrange.copy(alpha = 0.85f)
                        else -> LiveDesign.good.copy(alpha = 0.9f)
                    }
                Box(
                    Modifier.weight(1f)
                        .height(6.dp)
                        .background(fill, CircleShape),
                )
            }
        }
        Row(Modifier.fillMaxWidth()) {
            DashLegend("Poor", "<50", Modifier.weight(1f), Alignment.Start)
            DashLegend("Watch", "50-79", Modifier.weight(1f), Alignment.CenterHorizontally)
            DashLegend("Stable", "80+", Modifier.weight(1f), Alignment.End)
        }
    }
}

private enum class LinkHealthBand(val label: String) {
    POOR("POOR"),
    WATCH("WATCH"),
    STABLE("STABLE"),
}

@Composable
private fun DashLegend(
    name: String,
    sub: String,
    modifier: Modifier,
    alignment: Alignment.Horizontal,
) {
    Row(
        modifier,
        horizontalArrangement =
            when (alignment) {
                Alignment.Start -> Arrangement.Start
                Alignment.End -> Arrangement.End
                else -> Arrangement.Center
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(name, style = chromeStyle(10f, FontWeight.SemiBold), color = LiveDesign.muted)
        Spacer(Modifier.size(4.dp))
        Text(sub, style = chromeStyle(9f, FontWeight.Normal, mono = true), color = LiveDesign.faint)
    }
}

/**
 * One label-plus-trailing-control row for a divider-separated card
 * (iOS `SettingsInlineRow`). When [stacked] is true (two-column View Assist
 * cards), the control sits under the title at full width.
 *
 * [help] renders the same "?" badge iOS puts beside the title — the copy that
 * explains what a control actually does lives there, not in a caption, so the
 * row stays one line until an operator asks.
 */
@Composable
fun SettingsInlineRow(
    title: String,
    help: String? = null,
    showTopDivider: Boolean = true,
    stacked: Boolean = false,
    trailing: @Composable () -> Unit,
) {
    Column {
        if (showTopDivider) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(LiveDesign.hairline))
        }
        if (stacked) {
            Column(
                Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).padding(vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        title,
                        style = chromeStyle(12.5f, FontWeight.SemiBold),
                        color = LiveDesign.text,
                        maxLines = 2,
                    )
                    help?.let { SettingsHelpBadge(it) }
                }
                trailing()
            }
        } else {
            Row(
                Modifier.fillMaxWidth().defaultMinSize(minHeight = 50.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    title,
                    style = chromeStyle(12.5f, FontWeight.SemiBold),
                    color = LiveDesign.text,
                    maxLines = 1,
                )
                help?.let { SettingsHelpBadge(it) }
                Spacer(Modifier.weight(1f))
                trailing()
            }
        }
    }
}

/** Switch row inside a row card (iOS `SettingsSwitchInlineRow`). */
@Composable
fun SettingsSwitchRow(
    title: String,
    isOn: Boolean,
    help: String? = null,
    showTopDivider: Boolean = true,
    stacked: Boolean = false,
    onToggle: () -> Unit,
) {
    SettingsInlineRow(
        title = title,
        help = help,
        showTopDivider = showTopDivider,
        stacked = stacked,
    ) {
        Box(Modifier.settingsClickable(role = Role.Switch, onClick = onToggle)) {
            SettingsSwitchGraphic(isOn = isOn)
        }
    }
}

/** iOS `SettingsSwitchInlineRow` — Pocket call-site alias of [SettingsSwitchRow]. */
@Composable
fun SettingsSwitchInlineRow(
    title: String,
    isOn: Boolean,
    help: String? = null,
    showTopDivider: Boolean = true,
    stacked: Boolean = false,
    onToggle: () -> Unit,
) {
    SettingsSwitchRow(
        title = title,
        isOn = isOn,
        help = help,
        showTopDivider = showTopDivider,
        stacked = stacked,
        onToggle = onToggle,
    )
}

/**
 * iOS `HelpBadge`: a quiet "?" beside a row title that reveals the row's help
 * copy in a glass popover.
 *
 * ponytail: a transcription of the private badge in media/PlaybackAssistOptions.kt
 * (the assist popups own theirs) — settings cannot see it. Hoist one copy if a
 * third surface ever needs it.
 */
@Composable
fun SettingsHelpBadge(text: String) {
    var open by remember { mutableStateOf(false) }
    val description = "Help"
    Box {
        // A 16dp mark inside a 24dp target. The full 44dp floor would reserve 44dp of ROW
        // width on every helped row and squeeze the trailing control off a landscape-phone
        // pane; 24dp still clears the WCAG 2.2 AA target size.
        Box(
            Modifier.size(24.dp)
                .settingsClickable(role = Role.Button) { open = !open }
                .semantics { contentDescription = description },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.size(16.dp).border(1.dp, LiveDesign.hairlineStrong, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text("?", style = chromeStyle(10f, FontWeight.Bold), color = LiveDesign.muted)
            }
        }
        if (open) {
            Popup(onDismissRequest = { open = false }) {
                Box(
                    Modifier
                        .widthIn(max = 280.dp)
                        .background(LiveDesign.surface, ChromeShape)
                        .border(1.dp, LiveDesign.hairline, ChromeShape)
                        .padding(10.dp),
                ) {
                    Text(
                        text,
                        style = chromeStyle(11f, FontWeight.Normal),
                        color = LiveDesign.text,
                    )
                }
            }
        }
    }
}

/**
 * iOS `SettingsSegmented`: pill track with equal or intrinsic segments. Active
 * segment uses surface fill + primary text (not accent chips).
 */
@Composable
fun SettingsSegmented(
    options: List<String>,
    selected: String,
    compact: Boolean = true,
    onSelect: (String) -> Unit,
) {
    Row(
        Modifier
            .then(if (compact) Modifier.fillMaxWidth() else Modifier)
            .background(LiveDesign.background.copy(alpha = 0.5f), ChromeShape)
            .border(1.dp, LiveDesign.hairline, ChromeShape)
            .padding(3.dp)
            .selectableGroup(),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        options.forEach { option ->
            val active = option == selected
            Box(
                Modifier
                    .then(if (compact) Modifier.weight(1f) else Modifier)
                    .defaultMinSize(minHeight = if (compact) 32.dp else 30.dp)
                    .background(
                        if (active) LiveDesign.surface else Color.Transparent,
                        ChromeShape,
                    )
                    .selectable(
                        selected = active,
                        role = Role.RadioButton,
                        onClick = { if (!active) onSelect(option) },
                    )
                    .padding(horizontal = if (compact) 8.dp else 11.dp, vertical = 6.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    option,
                    style = chromeStyle(if (compact) 11f else 11.5f, if (active) FontWeight.SemiBold else FontWeight.Medium),
                    color = if (active) LiveDesign.text else LiveDesign.muted,
                    maxLines = 1,
                )
            }
        }
    }
}

/**
 * iOS `SettingsColorDots`: real colour circles (not text labels), selected with
 * a matching stroke ring.
 */
@Composable
fun SettingsColorDots(
    dots: List<SettingsColorDot>,
    selectedName: String,
    compact: Boolean = true,
    onSelect: (String) -> Unit,
) {
    val diameter = if (compact) 15.dp else 13.dp
    val hit = 44.dp
    Row(horizontalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 6.dp)) {
        dots.forEach { dot ->
            val active = dot.name == selectedName
            Box(
                Modifier
                    .size(hit)
                    .settingsClickable(role = Role.RadioButton) {
                        if (!active) onSelect(dot.name)
                    }
                    .semantics { contentDescription = dot.name },
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .size(diameter + 10.dp)
                        .background(LiveDesign.background.copy(alpha = 0.5f), CircleShape)
                        .border(
                            width = if (active) 2.dp else 1.dp,
                            color = if (active) dot.color else LiveDesign.hairline,
                            shape = CircleShape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(diameter).background(dot.color, CircleShape))
                }
            }
        }
    }
}

/** One named swatch for [SettingsColorDots] (iOS `SettingsColorDots.Dot`). */
data class SettingsColorDot(val name: String, val color: Color)

/** iOS `SettingsPalette` — zone-scoped stripe/peaking colours. */
object SettingsPalette {
    val highlight: List<SettingsColorDot> =
        listOf(
            SettingsColorDot("White", LiveDesign.text),
            SettingsColorDot("Amber", LiveDesign.accent),
            SettingsColorDot("Red", LiveDesign.rec),
        )
    val midtone: List<SettingsColorDot> =
        listOf(
            SettingsColorDot("Amber", LiveDesign.accent),
            SettingsColorDot("Cyan", LiveDesign.info),
            SettingsColorDot("Green", LiveDesign.good),
        )
    val peaking: List<SettingsColorDot> =
        listOf(
            SettingsColorDot("White", LiveDesign.text),
            SettingsColorDot("Blue", LiveDesign.info),
            SettingsColorDot("Red", LiveDesign.rec),
            SettingsColorDot("Green", LiveDesign.good),
        )
}

/**
 * iOS `SettingsNumberField`: compact mono value field with digit pad and clamp.
 */
@Composable
fun SettingsNumberField(
    value: Int,
    maximum: Int,
    onChange: (Int) -> Unit,
) {
    var editing by remember { mutableStateOf(false) }
    var draft by remember(value) { mutableStateOf(value.toString()) }
    val focusRequester = remember { FocusRequester() }
    fun commit() {
        draft.toIntOrNull()?.let { onChange(it.coerceIn(0, maximum)) }
        editing = false
    }
    Box(
        Modifier
            .height(30.dp)
            .width(44.dp)
            .background(LiveDesign.background.copy(alpha = 0.5f), ChromeShape)
            .border(1.dp, LiveDesign.hairline, ChromeShape)
            .then(
                if (editing) {
                    Modifier
                } else {
                    Modifier.settingsClickable(role = Role.Button) { editing = true }
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        if (editing) {
            LaunchedEffect(Unit) { focusRequester.requestFocus() }
            BasicTextField(
                value = draft,
                onValueChange = { next -> draft = next.filter(Char::isDigit).take(3) },
                textStyle =
                    chromeStyle(12f, FontWeight.SemiBold, mono = true)
                        .copy(color = LiveDesign.text, textAlign = TextAlign.Center),
                keyboardOptions =
                    KeyboardOptions(
                        keyboardType = KeyboardType.Number,
                        imeAction = ImeAction.Done,
                    ),
                keyboardActions = KeyboardActions(onDone = { commit() }),
                singleLine = true,
                cursorBrush = SolidColor(LiveDesign.accent),
                modifier =
                    Modifier
                        .widthIn(min = 28.dp, max = 40.dp)
                        .focusRequester(focusRequester)
                        .onFocusChanged { if (!it.isFocused && editing) commit() },
            )
        } else {
            Text(
                value.toString(),
                style = chromeStyle(12f, FontWeight.SemiBold, mono = true),
                color = LiveDesign.text,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/**
 * iOS / Kyant liquid-glass percent slider: [LiquidSlider] thumb over a thin
 * track, with a trailing mono percent readout.
 */
@Composable
fun SettingsPercentSlider(
    value: Int,
    range: IntRange,
    onChange: (Int) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(9.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        GlassPillSlider(
            value = value,
            range = range,
            onChange = onChange,
            modifier = Modifier.weight(1f),
        )
        Text(
            "$value%",
            style = chromeStyle(12f, FontWeight.Medium, mono = true),
            color = LiveDesign.text,
            textAlign = TextAlign.End,
            modifier = Modifier.width(40.dp),
        )
    }
}

/**
 * Operator-facing brightness slider backed by Kyant's catalog [LiquidSlider]
 * (https://github.com/Kyant0/AndroidLiquidGlass). Samples the monitor feed
 * backdrop when present; otherwise records a local layer so the glass thumb
 * still has something to refract in standalone Operator Setup.
 */
@Composable
fun GlassPillSlider(
    value: Int,
    range: IntRange,
    onChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val monitorGlass = LocalMonitorGlass.current
    // Settings never samples the live-feed Kyant backdrop. Solid capsule only.
    val useLiquidGlass = false
    val localBackdrop = rememberLayerBackdrop()
    val sceneBackdrop = monitorGlass?.layerBackdrop
    val latestOnChange by rememberUpdatedState(onChange)
    val latestValue by rememberUpdatedState(value)
    val floatRange = range.first.toFloat()..range.last.toFloat()
    // Continuous thumb position while dragging. Discrete onChange (Int steps) alone cannot
    // drive a smooth pill drag — intermediate floats would be rounded away and the thumb
    // would stick (especially on short ranges like desqueeze 0…10).
    var displayValue by remember { mutableFloatStateOf(value.toFloat()) }
    // Accept external commits without yanking the pill back to the last Int mid-drag.
    SideEffect {
        if (displayValue.roundToInt().coerceIn(range) != value) {
            displayValue = value.toFloat()
        }
    }

    Box(
        modifier
            .height(40.dp)
            .then(
                if (useLiquidGlass && sceneBackdrop == null) {
                    Modifier.layerBackdrop(localBackdrop)
                } else {
                    Modifier
                },
            )
            .semantics(mergeDescendants = true) {
                stateDescription = "$value%"
                setProgress { target ->
                    val next =
                        (range.first + target * (range.last - range.first))
                            .roundToInt()
                            .coerceIn(range)
                    displayValue = next.toFloat()
                    latestOnChange(next)
                    true
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        if (useLiquidGlass && sceneBackdrop == null) {
            Box(
                Modifier
                    .matchParentSize()
                    .background(
                        brush =
                            Brush.horizontalGradient(
                                colors =
                                    listOf(
                                        LiveDesign.surface,
                                        LiveDesign.background,
                                        LiveDesign.surface,
                                    ),
                            ),
                    ),
            )
        }
        LiquidSlider(
            value = { displayValue },
            onValueChange = { next ->
                displayValue = next
                val rounded = next.roundToInt().coerceIn(range)
                if (rounded != latestValue) latestOnChange(rounded)
            },
            valueRange = floatRange,
            visibilityThreshold = 0.5f,
            backdrop = sceneBackdrop ?: localBackdrop,
            modifier = Modifier.fillMaxWidth(),
            accentColor = LiveDesign.accent,
            useLiquidGlass = useLiquidGlass,
        )
    }
}

/**
 * iOS `SettingsCrushClipSegmented`: five equal stop segments with fraction
 * glyphs (0 · ¼ · ½ · ¾ · 1).
 */
@Composable
fun SettingsCrushClipSegmented(
    options: List<Pair<String, String>>,
    selectedLabel: String,
    onSelect: (String) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(LiveDesign.background.copy(alpha = 0.5f), ChromeShape)
            .border(1.dp, LiveDesign.hairline, ChromeShape)
            .padding(4.dp)
            .selectableGroup(),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        options.forEach { (label, compact) ->
            val active = label == selectedLabel
            Box(
                Modifier
                    .weight(1f)
                    .defaultMinSize(minHeight = 34.dp)
                    .background(
                        if (active) LiveDesign.surface else Color.Transparent,
                        ChromeShape,
                    )
                    .selectable(
                        selected = active,
                        role = Role.RadioButton,
                        onClick = { if (!active) onSelect(label) },
                    )
                    // The segment shows a fraction glyph; the full stop value is what a screen
                    // reader has to say, so it announces the label rather than "¼".
                    .semantics { contentDescription = label },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    compact,
                    style = chromeStyle(12f, if (active) FontWeight.SemiBold else FontWeight.Medium),
                    color = if (active) LiveDesign.text else LiveDesign.muted,
                    maxLines = 1,
                )
            }
        }
    }
}

/** The accent capsule switch graphic (iOS `SettingsSwitchGraphic`, 39×22). */
@Composable
fun SettingsSwitchGraphic(isOn: Boolean) {
    Box(
        Modifier.size(width = 39.dp, height = 22.dp)
            .background(if (isOn) LiveDesign.accentDim else LiveDesign.surface, CircleShape)
            .border(1.dp, if (isOn) LiveDesign.accentDim else LiveDesign.hairline, CircleShape)
            .padding(3.5.dp),
        contentAlignment = if (isOn) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(
            Modifier.size(15.dp)
                .background(if (isOn) LiveDesign.accent else LiveDesign.muted, CircleShape)
        )
    }
}

/** Plain monospace value text (iOS `SettingsValueText`). */
@Composable
fun SettingsValueText(value: String) {
    Text(
        value,
        style = chromeStyle(12.5f, FontWeight.Medium, mono = true),
        color = LiveDesign.muted,
        maxLines = 1,
    )
}

/** Accent inline action ("Open", "Sign in") — the iOS System-tab link button treatment. */
@Composable
fun SettingsLinkAction(
    title: String,
    contentDescription: String = title,
    onClick: () -> Unit,
): Unit {
    Box(
        Modifier.defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .settingsClickable(role = Role.Button, onClick = onClick)
            .semantics { this.contentDescription = contentDescription }
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            style = chromeStyle(13f, FontWeight.SemiBold),
            color = LiveDesign.accent,
        )
    }
}

/**
 * Quiet utility text link — mirrors the startup header's Privacy/Terms
 * treatment (iOS `StartupHeader.legalLink`): deliberately dimmer than row
 * titles so it never competes with them.
 */
@Composable
fun SettingsQuietLink(title: String, onClick: () -> Unit): Unit {
    Box(
        Modifier.defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .settingsClickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = LiveDesign.faint,
            maxLines = 1,
        )
    }
}

/**
 * Titled glass card with an optional per-tool reset and free-form content.
 *
 * [captionMaxLines] defaults to the compact settings-card treatment. Flows
 * that communicate a consequential choice can opt into an unbounded caption
 * so accessibility font scaling never hides that context.
 */
@Composable
fun SettingsGroupCard(
    title: String,
    caption: String,
    onReset: (() -> Unit)? = null,
    captionMaxLines: Int = 2,
    /**
     * When non-null the card collapses to its header and the whole header toggles it. Long tabs
     * (Display carries three DISP sections) read as a short list of sections this way instead of
     * one unbroken scroll of controls.
     */
    expanded: Boolean? = null,
    onExpandToggle: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val isExpanded = expanded ?: true
    Column(
        Modifier.fillMaxWidth().panelGlass(ChromeShape).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        Column(
            Modifier.then(
                if (expanded != null && onExpandToggle != null) {
                    Modifier.settingsClickable(role = Role.Button, onClick = onExpandToggle)
                } else {
                    Modifier
                }
            ),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    title,
                    style = chromeStyle(13f, FontWeight.SemiBold),
                    color = LiveDesign.text,
                )
                Spacer(Modifier.weight(1f))
                if (onReset != null && isExpanded) {
                    SettingsResetButton(onClick = onReset)
                }
                if (expanded != null) {
                    OpcIcon(
                        icon = if (isExpanded) OpcIcon.CHEVRON_UP else OpcIcon.CHEVRON_DOWN,
                        contentDescription = null,
                        tint = LiveDesign.muted,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
            Text(
                caption,
                style = chromeStyle(11.5f, FontWeight.Normal),
                color = LiveDesign.muted,
                maxLines = captionMaxLines,
            )
        }
        if (isExpanded) {
            content()
        }
    }
}

/** Small label + switch tile for toggle grids (iOS `DisplayToggleItem`). */
@Composable
fun DisplayToggleItem(
    title: String,
    isOn: Boolean,
    modifier: Modifier = Modifier,
    onToggle: () -> Unit,
) {
    Row(
        modifier
            .height(46.dp)
            .background(LiveDesign.background.copy(alpha = 0.38f), ChromeShape)
            .border(1.dp, LiveDesign.hairline, ChromeShape)
            .settingsClickable(role = Role.Switch, onClick = onToggle)
            .padding(horizontal = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            style = chromeStyle(11.5f, FontWeight.SemiBold),
            color = LiveDesign.text,
            maxLines = 1,
        )
        Spacer(Modifier.weight(1f))
        SettingsSwitchGraphic(isOn = isOn)
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
        OpcIcon(
            icon = OpcIcon.X,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(13.dp),
        )
    }
}
