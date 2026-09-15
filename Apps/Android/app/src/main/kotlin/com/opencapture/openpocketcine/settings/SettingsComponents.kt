package com.opencapture.openpocketcine.settings

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import com.opencapture.monitorui.LocalMonitorInspectorHelp
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import com.opencapture.openpocketcine.assists.FalseColorReference
import com.opencapture.openpocketcine.assists.FalseColorScale
import com.opencapture.openpocketcine.feed.MonitorTransfer
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import com.opencapture.openpocketcine.ChromeShape
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.monitorui.MonitorLinkHealth
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.panelGlass
import kotlin.math.roundToInt

private fun chromeStyle(size: Float, weight: FontWeight, mono: Boolean = false): TextStyle =
    if (mono) LiveType.mono(size, weight) else LiveType.ui(size, weight)

/** iOS `monitorCardSurface`: solid Field Monitor card with a hairline border. */
private fun Modifier.settingsCardSurface(): Modifier =
    background(LiveDesign.surface, ChromeShape).border(1.dp, LiveDesign.hairline, ChromeShape)

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
        Modifier
            .fillMaxWidth()
            .settingsCardSurface()
            .padding(horizontal = 13.dp)
            .padding(top = if (title != null) 0.dp else 8.dp, bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(com.opencapture.monitorui.MonitorLayoutPolicy.SETTINGS_TITLE_CONTENT_GAP.dp),
    ) {
        if (title != null) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(top = 11.dp)
                    .heightIn(min = com.opencapture.monitorui.MonitorLayoutPolicy.SETTINGS_TITLE_MIN_HEIGHT.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, style = chromeStyle(13f, FontWeight.SemiBold), color = LiveDesign.text)
                Spacer(Modifier.weight(1f))
                if (onReset != null) SettingsResetButton(onClick = onReset)
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
        OpcIcon(OpcIcon.ROTATE_CW, null, Modifier.size(12.dp), LiveDesign.muted)
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
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Row(
        modifier
            .alpha(if (enabled) 1f else 0.45f)
            .background(background, CircleShape)
            .border(1.dp, tint.copy(alpha = 0.5f), CircleShape)
            .settingsClickable(role = Role.Button, enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let {
            OpcIcon(icon = it, contentDescription = null, tint = tint, modifier = Modifier.size(13.dp))
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
    val band = MonitorLinkHealth.band(score)
    val bandColor = MonitorLinkHealth.color(score)
    val litCount =
        when (band) {
            MonitorLinkHealth.Band.POOR -> 4
            MonitorLinkHealth.Band.WATCH -> 8
            MonitorLinkHealth.Band.STABLE -> 12
        }
    val bandSlot =
        when (band) {
            MonitorLinkHealth.Band.POOR -> 0
            MonitorLinkHealth.Band.WATCH -> 1
            MonitorLinkHealth.Band.STABLE -> 2
        }
    val bandLabel =
        when (band) {
            MonitorLinkHealth.Band.POOR -> "POOR"
            MonitorLinkHealth.Band.WATCH -> "WATCH"
            MonitorLinkHealth.Band.STABLE -> "STABLE"
        }
    Column(
        Modifier.fillMaxWidth()
            .settingsCardSurface()
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
                            bandLabel,
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
                        index < 4 -> MonitorLinkHealth.poor.copy(alpha = 0.8f)
                        index < 8 -> MonitorLinkHealth.watch.copy(alpha = 0.85f)
                        else -> MonitorLinkHealth.stable.copy(alpha = 0.9f)
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
    val inspectorHelp = LocalMonitorInspectorHelp.current
    val label = @Composable {
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                title,
                style = chromeStyle(12.5f, FontWeight.SemiBold),
                color = LiveDesign.text,
                maxLines = if (stacked) 2 else 1,
            )
            if (inspectorHelp == null) help?.let { SettingsHelpBadge(it) }
        }
    }
    Column {
        if (showTopDivider) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(LiveDesign.hairline))
        }
        if (stacked) {
            Column(
                Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).padding(vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                label()
                Box(Modifier.fillMaxWidth()) { trailing() }
            }
        } else {
            Row(
                Modifier.fillMaxWidth().defaultMinSize(minHeight = 50.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                label()
                Box(
                    Modifier.weight(1f).padding(start = 4.dp),
                    contentAlignment = Alignment.CenterEnd,
                ) {
                    trailing()
                }
            }
        }
        if (inspectorHelp == true && !help.isNullOrEmpty()) {
            Text(
                help,
                modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
                style = chromeStyle(10f, FontWeight.Normal),
                color = LiveDesign.muted,
            )
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
    testTag: String? = null,
    onToggle: () -> Unit,
) {
    SettingsInlineRow(
        title = title,
        help = help,
        showTopDivider = showTopDivider,
        stacked = stacked,
    ) {
        val access =
            Modifier.settingsClickable(role = Role.Switch, onClick = onToggle).semantics {
                contentDescription = title
                toggleableState = if (isOn) ToggleableState.On else ToggleableState.Off
                stateDescription = if (isOn) "On" else "Off"
            }.then(if (testTag != null) Modifier.testTag(testTag) else Modifier)
        Box(access) {
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
    testTag: String? = null,
    onToggle: () -> Unit,
) {
    SettingsSwitchRow(
        title = title,
        isOn = isOn,
        help = help,
        showTopDivider = showTopDivider,
        stacked = stacked,
        testTag = testTag,
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
                Modifier
                    .size(16.dp)
                    .background(LiveDesign.background.copy(alpha = 0.5f), CircleShape)
                    .border(1.dp, LiveDesign.hairline, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                OpcIcon(OpcIcon.INFO, null, Modifier.size(9.dp), LiveDesign.faint)
            }
        }
        if (open) {
            Popup(onDismissRequest = { open = false }) {
                Box(
                    Modifier
                        .width(248.dp)
                        .background(LiveDesign.surface, ChromeShape)
                        .border(1.dp, LiveDesign.hairline, ChromeShape)
                        .padding(12.dp),
                ) {
                    Text(
                        text,
                        style = chromeStyle(12f, FontWeight.Normal),
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
    fillWidth: Boolean = compact,
    accentSelection: Boolean = false,
    testTag: String? = null,
    onSelect: (String) -> Unit,
) {
    BoxWithConstraints {
        val labelSize = if (compact && fillWidth && options.size >= 4 && maxWidth < 260.dp) 9.5f else if (compact) 11f else 11.5f
        Row(
            Modifier
                .then(if (testTag != null) Modifier.testTag(testTag) else Modifier)
                .then(if (fillWidth) Modifier.fillMaxWidth() else Modifier)
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
                        .then(if (fillWidth) Modifier.weight(1f) else Modifier)
                        .defaultMinSize(minHeight = if (compact) 32.dp else 30.dp)
                        .background(
                            if (active) { if (accentSelection) LiveDesign.accent else LiveDesign.surface } else Color.Transparent,
                            ChromeShape,
                        )
                        .selectable(
                            selected = active,
                            role = Role.RadioButton,
                            onClick = { if (!active) onSelect(option) },
                        )
                        .padding(horizontal = if (compact && fillWidth) 2.dp else if (compact) 8.dp else 11.dp, vertical = 6.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        option,
                        style = chromeStyle(labelSize, if (active) FontWeight.SemiBold else FontWeight.Medium),
                        color = if (active) { if (accentSelection) Color(0xFF08191F) else LiveDesign.text } else LiveDesign.muted,
                        maxLines = 1,
                    )
                }
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
    enabled: Boolean = true,
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
                        if (enabled && !active) onSelect(dot.name)
                    }
                    .semantics { contentDescription = dot.name; if (!enabled) disabled() },
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .size(36.dp)
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
 * Done on the IME commits and hides the pad. Bring-into-view so Operator Setup
 * on a small phone still reveals Highlight / Midtone.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SettingsNumberField(
    value: Int,
    maximum: Int,
    onChange: (Int) -> Unit,
) {
    var editing by remember { mutableStateOf(false) }
    var draft by remember(value) { mutableStateOf(value.toString()) }
    val focusRequester = remember { FocusRequester() }
    val bringIntoView = remember { BringIntoViewRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    fun commit() {
        draft.toIntOrNull()?.let { onChange(it.coerceIn(0, maximum)) }
        editing = false
        keyboard?.hide()
    }
    Box(
        Modifier
            .height(30.dp)
            .width(44.dp)
            .background(LiveDesign.background.copy(alpha = 0.5f), ChromeShape)
            .border(1.dp, LiveDesign.hairline, ChromeShape)
            .bringIntoViewRequester(bringIntoView)
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
            LaunchedEffect(Unit) {
                focusRequester.requestFocus()
                bringIntoView.bringIntoView()
            }
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

/** Compact native slider with the existing trailing numeric readout. */
@Composable
fun SettingsPercentSlider(
    value: Int,
    range: IntRange,
    onChange: (Int) -> Unit,
) {
    SettingsValueSlider(value = value, range = range, label = "$value%", onChange = onChange)
}

/** Thin accent track + white thumb, matching iOS `Slider` in Operator Setup. */
@Composable
fun SettingsValueSlider(
    value: Int,
    range: IntRange,
    label: String,
    onChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    labelWidth: Int = 40,
) {
    Row(
        modifier.fillMaxWidth(),
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
            label,
            style = chromeStyle(12f, FontWeight.Medium, mono = true),
            color = LiveDesign.text,
            textAlign = TextAlign.End,
            modifier = Modifier.width(labelWidth.dp),
        )
    }
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

/**
 * iOS `SettingsCrushClipSegmented`: five equal stop segments with fraction
 * glyphs (0 · ¼ · ½ · ¾ · 1).
 */
@Composable
fun SettingsCrushClipSegmented(
    options: List<Pair<String, String>>,
    selectedLabel: String,
    accentSelection: Boolean = false,
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
                        if (active) { if (accentSelection) LiveDesign.accent else LiveDesign.surface } else Color.Transparent,
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
                    color = if (active) { if (accentSelection) Color(0xFF08191F) else LiveDesign.text } else LiveDesign.muted,
                    maxLines = 1,
                )
            }
        }
    }
}

/** iOS `SettingsSwitchGraphic`: 39×22 capsule, cyan thumb on dim track when on. */
@Composable
fun SettingsSwitchGraphic(isOn: Boolean) {
    val thumbX by animateFloatAsState(if (isOn) 20.5f else 3.5f, tween(160), label = "settings-switch")
    Box(
        Modifier
            .size(39.dp, 22.dp)
            .background(if (isOn) LiveDesign.accentDim else LiveDesign.surface, CircleShape)
            .border(1.dp, if (isOn) LiveDesign.accentDim else LiveDesign.hairline, CircleShape),
    ) {
        Box(
            Modifier
                .offset(x = thumbX.dp, y = 3.5.dp)
                .size(15.dp)
                .background(if (isOn) LiveDesign.accent else LiveDesign.muted, CircleShape),
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
        Modifier.fillMaxWidth().settingsCardSurface().padding(horizontal = 13.dp, vertical = 11.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
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

/** Compact settings key; uses the same transfer-aware bands as the live reference. */
@Composable
fun SettingsFalseColorKey(scale: FalseColorScale, colorMode: Int) {
    val segments = FalseColorReference.segments(scale, MonitorTransfer.fromColorMode(colorMode))
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Canvas(Modifier.fillMaxWidth().height(11.dp)) {
            drawRect(Color.White.copy(alpha = 0.5f))
            segments.forEach { segment ->
                val lo = segment.lowerFraction.toFloat()
                val hi = segment.upperFraction.toFloat()
                drawRect(
                    Color(segment.band.red.toFloat(), segment.band.green.toFloat(), segment.band.blue.toFloat()),
                    Offset(size.width * lo, 0f),
                    Size(maxOf(1f, size.width * (hi - lo)), size.height),
                )
            }
        }
        if (scale == FalseColorScale.EL_ZONE) {
            BoxWithConstraints(Modifier.fillMaxWidth().height(12.dp)) {
                val rulerWidth = maxWidth
                FalseColorReference.elZoneAxisMarkers().forEach { marker ->
                    Text(marker.label, style = LiveType.mono(7f), color = LiveDesign.muted,
                        modifier = Modifier.offset(x = (rulerWidth * marker.fraction.toFloat() - 8.dp)
                            .coerceIn(0.dp, (rulerWidth - 16.dp).coerceAtLeast(0.dp))))
                }
            }
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                FalseColorReference.axisLabels(scale).forEach { label ->
                    Text(label, style = LiveType.ui(7f), color = LiveDesign.muted)
                }
            }
        }
    }
}
