package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LivePopupCloseButton
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LocalOperatorHaptics
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.lut.LUTPicker
import com.opencapture.openpocketcine.lut.LUTSplitComparisonBar
import com.opencapture.openpocketcine.pickerPanelGlass
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.settings.SettingsColorDots
import com.opencapture.openpocketcine.settings.SettingsCrushClipSegmented
import com.opencapture.openpocketcine.settings.SettingsInlineRow
import com.opencapture.openpocketcine.settings.SettingsNumberField
import com.opencapture.openpocketcine.settings.SettingsPalette
import com.opencapture.openpocketcine.settings.SettingsPercentSlider
import com.opencapture.openpocketcine.settings.SettingsSegmented
import com.opencapture.openpocketcine.settings.SettingsSwitchGraphic
import com.opencapture.openpocketcine.settings.SettingsSwitchInlineRow

private val CardShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

@Composable
private fun Modifier.assistClick(onClick: () -> Unit): Modifier = chromeClickable(onClick = onClick)

/**
 * OpenZCine / iOS long-press tray. Overlay glass, not the feed-layer pill.
 *
 * [model] owns the live LUT selection. When omitted (current live-view call
 * site), the picker writes [OperatorPrefs] so a later process still restores.
 */
@Composable
fun AssistOptionsPopup(
    tool: LiveAssistTool,
    state: LiveAssistState,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    model: AppModel? = null,
    maxHeightDp: Float? = null,
    colorMode: Int = CameraCommands.COLOR_NORMAL,
) {
    val width = AssistLongPress.preferredWidthDp(tool).dp
    val context = LocalContext.current
    var fallbackLut by remember {
        mutableStateOf(model?.lutSelection ?: OperatorPrefs.lutSelection(context))
    }
    val lutSelection = model?.lutSelection ?: fallbackLut
    val cap = maxHeightDp?.dp
    val isLut = tool == LiveAssistTool.LUT
    val panelPad = AssistLongPress.PANEL_PAD_DP.dp
    val panelGap = AssistLongPress.PANEL_GAP_DP.dp
    Column(
        modifier
            .widthIn(max = width)
            .width(width)
            .then(
                if (isLut && cap != null) {
                    Modifier.height(cap)
                } else {
                    Modifier.wrapContentHeight(align = Alignment.Top)
                        .then(if (cap != null) Modifier.heightIn(max = cap) else Modifier)
                },
            )
            .pickerPanelGlass(CardShape)
            .padding(panelPad),
        verticalArrangement = Arrangement.spacedBy(panelGap),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AssistToolGlyph(tool, LiveDesign.text, Modifier.size(15.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                tool.title.uppercase(),
                style = LiveType.ui(15f, FontWeight.Bold).copy(letterSpacing = 1.2.sp),
                color = LiveDesign.text,
            )
            Spacer(Modifier.weight(1f))
            LivePopupCloseButton(
                onClick = onDismiss,
                size = AssistLongPress.CLOSE_DP.dp,
            )
        }
        if (isLut) {
            // iOS pins 50/50 under the catalog. Weight the picker so a short
            // landscape well scrolls the drum instead of clipping the footer.
            Box(
                Modifier
                    .weight(1f, fill = true)
                    .fillMaxWidth(),
            ) {
                LUTPicker(
                    selection = lutSelection,
                    onSelect = { id ->
                        if (model != null) {
                            model.updateLutSelection(id)
                        } else {
                            fallbackLut = id
                            OperatorPrefs.setLutSelection(context, id)
                        }
                        state.armLut()
                    },
                    embedded = true,
                    splitComparison = state.splitComparison,
                    splitVertical = state.splitVertical,
                    lutExposureStops = state.lutExposureStops,
                    onToggleSplit = { state.setSplitComparison(!state.splitComparison) },
                    onSplitVertical = { state.setSplitComparison(state.splitComparison, it) },
                    onNudgeExposure = { state.nudgeLutExposure(it) },
                    onArmLut = { state.armLut() },
                    colorMode = colorMode,
                    family = model?.session?.connectedCamera?.model?.family ?: "pocket",
                    cameraName = model?.session?.connectedCamera?.name,
                )
            }
        } else {
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .fillMaxWidth()
                    .then(if (cap != null) Modifier.verticalScroll(rememberScrollState()) else Modifier),
            ) {
                AssistOptionsBody(tool, state, colorMode)
            }
        }
        if (isLut) {
            LUTSplitComparisonBar(
                splitComparison = state.splitComparison,
                splitVertical = state.splitVertical,
                lutExposureStops = state.lutExposureStops,
                onToggleSplit = { state.setSplitComparison(!state.splitComparison) },
                onSplitVertical = { state.setSplitComparison(state.splitComparison, it) },
                onNudgeExposure = { state.nudgeLutExposure(it) },
            )
        }
    }
}

@Composable
private fun AssistOptionsBody(tool: LiveAssistTool, state: LiveAssistState, colorMode: Int) {
    when (tool) {
        LiveAssistTool.LUT -> Spacer(Modifier.height(0.dp))
        LiveAssistTool.PEAK -> PeakingOptions(state)
        LiveAssistTool.FALSE -> FalseColorOptions(state)
        LiveAssistTool.ZEBRA -> ZebraOptions(state, colorMode)
        LiveAssistTool.WAVE -> WaveformOptions(state)
        LiveAssistTool.PARADE -> ParadeOptions(state)
        LiveAssistTool.HISTO -> HistogramOptions(state)
        LiveAssistTool.VECTOR -> VectorscopeOptions(state)
        LiveAssistTool.LIGHTS -> LightsOptions(state)
        LiveAssistTool.GUIDES -> GuidesOptions(state)
        LiveAssistTool.GRID -> GridOptions(state)
        LiveAssistTool.CROSS -> OptionCopy(CrosshairAssist.HELP)
        LiveAssistTool.MIRROR -> OptionCopy(MirrorAssist.EXPLANATION)
        LiveAssistTool.AUDIO -> OptionCopy(AudioAssist.HELP)
    }
}

@Composable
private fun PeakingOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    SettingsInlineRow("Sensitivity", help = "Higher sensitivity catches finer edges but can get noisy on detailed scenes.", showTopDivider = false, stacked = true) {
        SettingsSegmented(
            options = PeakingSense.entries.map { it.label },
            selected = state.peakingSensitivity.label,
        ) { label ->
            haptics.selection()
            state.setPeaking(sense = PeakingSense.fromPersisted(label))
        }
    }
    SettingsInlineRow("Color", help = "Choose the edge color that stays readable over your typical scene.", stacked = true) {
        SettingsColorDots(
            dots = SettingsPalette.peaking,
            selectedName = state.peakingColor.label,
        ) { label ->
            haptics.selection()
            state.setPeaking(color = PeakingColor.fromPersisted(label))
        }
    }
}

@Composable
private fun FalseColorOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    SettingsInlineRow(
        "Scale",
        help =
            "The camera color mode selects D-Log, D-Log2, Rec.709, or HLG automatically. " +
                "PStops marks minimum exposure, −3, 18% gray, skin, +2, and three clip-relative " +
                "highlight levels. IRE uses WAVE-axis monitor ranges. Limits paints only shadow " +
                "and highlight warnings.",
        showTopDivider = false,
        stacked = true,
    ) {
        SettingsSegmented(
            options = listOf("PStops", "IRE", "Limits"),
            selected = state.falseColorScale.menuLabel,
        ) { label ->
            haptics.selection()
            state.setFalseColor(scale = FalseColorScale.fromMenuLabel(label))
        }
    }
    SettingsSwitchInlineRow(
        title = "Reference Display",
        isOn = state.falseColorReference,
        help = "Show a compact color key over live view while False Color is active.",
        stacked = true,
    ) {
        haptics.selection()
        state.setFalseColor(reference = !state.falseColorReference)
    }
}

@Composable
private fun ZebraOptions(state: LiveAssistState, colorMode: Int) {
    val haptics = LocalOperatorHaptics.current
    val transfer = MonitorTransfer.fromColorMode(colorMode)
    val maximum = ZebraEditor.editorMaximum(state.zebraUnit)
    SettingsInlineRow(
        "Units",
        help = "Switch between native 0-255 encoded codes and a 0-100 monitoring IRE scale.",
        showTopDivider = false,
        stacked = true,
    ) {
        SettingsSegmented(
            options = listOf("0-255", "IRE"),
            selected = state.zebraUnit.editorLabel,
        ) { label ->
            haptics.selection()
            state.updateZebraUnit(ZebraUnit.fromEditorLabel(label))
        }
    }
    ZebraZoneRow(
        title = "Highlight",
        help = "High zebra warns when bright detail approaches clipping after the active log curve is compensated.",
        enabled = state.zebraHighlight,
        value = ZebraEditor.displayValue(state.zebraHighlightIRE, state.zebraUnit, transfer),
        maximum = maximum,
        selected = state.zebraHighlightColor.label,
        palette = SettingsPalette.highlight,
        onEnabled = {
            haptics.selection()
            state.setZebraHighlight(enabled = !state.zebraHighlight)
        },
        onValue = {
            state.setZebraHighlight(ire = ZebraEditor.ireFromDisplay(it, state.zebraUnit, transfer))
        },
        onColor = {
            haptics.selection()
            state.setZebraHighlight(color = ZebraPaint.fromPersisted(it))
        },
    )
    ZebraZoneRow(
        title = "Midtone",
        help = "Midtone zebra gives a curve-compensated reference band for faces or key subject exposure.",
        enabled = state.zebraMidtone,
        value = ZebraEditor.displayValue(state.zebraMidtoneIRE, state.zebraUnit, transfer),
        maximum = maximum,
        selected = state.zebraMidtoneColor.label,
        palette = SettingsPalette.midtone,
        onEnabled = {
            haptics.selection()
            state.setZebraMidtone(enabled = !state.zebraMidtone)
        },
        onValue = {
            state.setZebraMidtone(ire = ZebraEditor.ireFromDisplay(it, state.zebraUnit, transfer))
        },
        onColor = {
            haptics.selection()
            state.setZebraMidtone(color = ZebraPaint.fromPersisted(it))
        },
    )
}

@Composable
private fun ZebraZoneRow(
    title: String,
    help: String,
    enabled: Boolean,
    value: Int,
    maximum: Int,
    selected: String,
    palette: List<com.opencapture.openpocketcine.settings.SettingsColorDot>,
    onEnabled: () -> Unit,
    onValue: (Int) -> Unit,
    onColor: (String) -> Unit,
) {
    SettingsInlineRow(title = title, help = help, stacked = true) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(Modifier.chromeClickable(onClick = onEnabled).semantics { role = Role.Switch }) {
                SettingsSwitchGraphic(isOn = enabled)
            }
            SettingsNumberField(value = value.coerceIn(0, maximum), maximum = maximum, onChange = onValue)
            Spacer(Modifier.weight(1f))
            SettingsColorDots(dots = palette, selectedName = selected, onSelect = onColor)
        }
    }
}

@Composable
private fun WaveformOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    SettingsInlineRow("Mode", showTopDivider = false, stacked = true) {
        SettingsSegmented(options = listOf("Luma", "RGB"), selected = state.waveMode.label) {
            haptics.selection()
            state.setWaveform(mode = WaveformMode.fromPersisted(it))
        }
    }
    SettingsInlineRow("Brightness", help = "Raise trace intensity when the waveform is hard to read in bright light.", stacked = true) {
        SettingsPercentSlider(value = state.waveBrightness, range = 0..200) {
            state.setWaveform(brightness = it)
        }
    }
    GuideToggles(state.waveGuides) {
        haptics.selection()
        state.setWaveform(guides = it)
    }
}

@Composable
private fun ParadeOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    SettingsInlineRow("Mode", showTopDivider = false, stacked = true) {
        SettingsSegmented(options = listOf("RGB", "YRGB"), selected = state.paradeMode.label) {
            haptics.selection()
            state.setParade(mode = ParadeMode.fromPersisted(it))
        }
    }
    SettingsInlineRow("Brightness", help = "Raise trace intensity when channel separation is hard to see.", stacked = true) {
        SettingsPercentSlider(value = state.paradeBrightness, range = 0..200) {
            state.setParade(brightness = it)
        }
    }
    GuideToggles(state.paradeGuides) {
        haptics.selection()
        state.setParade(guides = it)
    }
}

@Composable
private fun HistogramOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    SettingsSwitchInlineRow(
        title = HistogramAssist.TRAFFIC_LIGHTS_TITLE,
        isOn = state.histoTrafficLights,
        help = HistogramAssist.TRAFFIC_LIGHTS_HELP,
        showTopDivider = false,
        stacked = true,
    ) {
        haptics.selection()
        state.setHistogram(traffic = !state.histoTrafficLights)
    }
    SettingsInlineRow(HistogramAssist.COMPENSATION_TITLE, HistogramAssist.COMPENSATION_HELP, stacked = true) {
        CompensationPicker(state.crushClipCompensation) {
            haptics.selection()
            state.setHistogram(compensation = it)
        }
    }
}

@Composable
private fun VectorscopeOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    SettingsInlineRow(
        "Trace Zoom",
        help = "Magnifies only the chroma trace; the graticule stays at unity.",
        showTopDivider = false,
        stacked = true,
    ) {
        SettingsSegmented(
            options = VectorscopeZoom.entries.map { it.label },
            selected = state.vectorZoom.label,
        ) {
            haptics.selection()
            state.setVectorscope(zoom = VectorscopeZoom.fromPersisted(it))
        }
    }
    SettingsInlineRow("Brightness", help = "Raise trace intensity when the chroma plot is hard to read.", stacked = true) {
        SettingsPercentSlider(value = state.vectorBrightness, range = 0..200) {
            state.setVectorscope(brightness = it)
        }
    }
}

@Composable
private fun LightsOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    SettingsInlineRow(
        HistogramAssist.COMPENSATION_TITLE,
        help = "Stops of crush/clip tolerance before a channel indicator glows. Shared with the histogram traffic lights.",
        showTopDivider = false,
        stacked = true,
    ) {
        CompensationPicker(state.crushClipCompensation) {
            haptics.selection()
            state.setCompensation(it)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun GuidesOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    SettingsSegmented(
        options = GuideFamily.entries.map { it.label },
        selected = state.guideFamily.label,
    ) {
        haptics.selection()
        state.updateGuideFamily(GuideFamily.fromPersisted(it))
    }
    Spacer(Modifier.height(10.dp))
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        GuideAspect.ratios(state.guideFamily).forEach { aspect ->
            val on = aspect in state.selectedGuides
            Text(
                aspect.label,
                color = if (on) LiveDesign.accent else LiveDesign.text,
                fontSize = 14.sp,
                fontFamily = FontFamily.Monospace,
                modifier =
                    Modifier
                        .clip(CardShape)
                        .background(if (on) LiveDesign.accentDim else LiveDesign.glassBright)
                        .border(1.dp, if (on) LiveDesign.accentDim else LiveDesign.hairline, CardShape)
                        .assistClick {
                            haptics.selection()
                            state.toggleGuide(aspect)
                        }
                        .padding(horizontal = 10.dp, vertical = 12.dp),
            )
        }
    }
    Spacer(Modifier.height(10.dp))
    SettingsSwitchInlineRow("Mask outside frame", isOn = state.guideMask, showTopDivider = false, stacked = true) {
        haptics.selection()
        state.updateGuideMask(!state.guideMask)
    }
}

@Composable
private fun GridOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        GridAssist.optionLabels.forEach { label ->
            val on =
                when (label) {
                    "Thirds" -> state.gridThirds
                    "Phi Grid" -> state.gridPhi
                    else -> state.gridDiagonal
                }
            Text(
                label,
                color = if (on) LiveDesign.accent else LiveDesign.text,
                fontSize = 14.sp,
                fontFamily = FontFamily.Monospace,
                modifier =
                    Modifier
                        .weight(1f)
                        .clip(CardShape)
                        .background(if (on) LiveDesign.accentDim else LiveDesign.glassBright)
                        .border(1.dp, if (on) LiveDesign.accentDim else LiveDesign.hairline, CardShape)
                        .assistClick {
                            haptics.selection()
                            when (label) {
                                "Thirds" -> state.setGridOption(thirds = !state.gridThirds)
                                "Phi Grid" -> state.setGridOption(phi = !state.gridPhi)
                                else -> state.setGridOption(diagonal = !state.gridDiagonal)
                            }
                        }
                        .padding(vertical = 16.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

@Composable
private fun GuideToggles(guides: ScopeGuides, onChange: (ScopeGuides) -> Unit) {
    SettingsSwitchInlineRow("Safe Border Clip", isOn = guides.clip, stacked = true) {
        onChange(guides.copy(clip = !guides.clip))
    }
    SettingsSwitchInlineRow("Safe Border Crush", isOn = guides.crush, stacked = true) {
        onChange(guides.copy(crush = !guides.crush))
    }
    SettingsSwitchInlineRow("Middle Gray", isOn = guides.middle, stacked = true) {
        onChange(guides.copy(middle = !guides.middle))
    }
}

@Composable
private fun CompensationPicker(selected: CrushClipCompensation, onSelect: (CrushClipCompensation) -> Unit) {
    SettingsCrushClipSegmented(
        options = CrushClipCompensation.entries.map { it.label to it.compactLabel },
        selectedLabel = selected.label,
    ) { label ->
        CrushClipCompensation.entries.firstOrNull { it.label == label }?.let(onSelect)
    }
}

@Composable
private fun OptionCopy(text: String) {
    Text(text, color = LiveDesign.muted, fontSize = 13.sp)
}
