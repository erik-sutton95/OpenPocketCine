package com.opencapture.openpocketcine.assists

import com.opencapture.opencine.cameracontrols.LivePopupCloseButton
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.openpocketcine.feed.fromColorMode

import com.opencapture.monitorui.monitorScrollFade
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.lut.LUTPicker
import com.opencapture.openpocketcine.lut.LUTSplitComparisonBar
import com.opencapture.openpocketcine.pickerPanelGlass
import com.opencapture.openpocketcine.settings.SettingsPalette

private val CardShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)


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
    embedded: Boolean = false,
    playback: Boolean = false,
    isPhoto: Boolean = false,
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
    val panelScroll = rememberScrollState()
    Column(
        modifier
            .then(if (embedded) Modifier.fillMaxWidth() else Modifier.widthIn(max = width).width(width))
            .then(
                if ((embedded || isLut) && cap != null) {
                    Modifier.height(cap)
                } else {
                    Modifier.wrapContentHeight(align = Alignment.Top)
                        .then(if (cap != null) Modifier.heightIn(max = cap) else Modifier)
                },
            )
            .then(if (embedded) Modifier else Modifier.pickerPanelGlass(CardShape).padding(panelPad))
            .then(if (embedded && !isLut) Modifier.monitorScrollFade(panelScroll).verticalScroll(panelScroll) else Modifier),
        verticalArrangement = Arrangement.spacedBy(panelGap),
    ) {
        if (!embedded) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AssistToolGlyph(tool, LiveDesign.text, Modifier.size(15.dp))
                Spacer(Modifier.width(8.dp))
                Text(
                    tool.title.uppercase(),
                    style = LiveType.ui(15f, FontWeight.SemiBold).copy(letterSpacing = .8.sp),
                    color = LiveDesign.text,
                )
                Spacer(Modifier.weight(1f))
                LivePopupCloseButton(
                    onClick = onDismiss,
                    size = AssistLongPress.CLOSE_DP.dp,
                )
            }
        }
        val lutScroll = rememberScrollState()
        Column(
            Modifier.then(if (isLut) Modifier.weight(1f).monitorScrollFade(lutScroll).verticalScroll(lutScroll) else Modifier),
            verticalArrangement = Arrangement.spacedBy(panelGap),
        ) {
            if (embedded) {
                AssistInspectorScopePreview(tool, state, colorMode, playback)
                if (model != null) AssistInspectorImagePreview(tool, state, model, lutSelection, colorMode, playback)
            }
            if (isLut) {
                // Keep a usable catalog height while the preview and catalog scroll
                // together above the pinned exposure / comparison controls.
                Box(
                    Modifier
                        .height(212.dp)
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
                        onExposure = { state.updateLutExposure(it) },
                        onArmLut = { state.armLut() },
                        colorMode = colorMode,
                        family = model?.session?.connectedCamera?.model?.family ?: "pocket",
                        cameraName = model?.session?.connectedCamera?.name,
                        isPhoto = isPhoto && !playback,
                    )
                }
            } else {
                val optionsScroll = rememberScrollState()
                Column(
                    Modifier
                        .then(if (embedded) Modifier else Modifier.weight(1f, fill = false))
                        .fillMaxWidth()
                        .then(if (!embedded && cap != null) Modifier.monitorScrollFade(optionsScroll).verticalScroll(optionsScroll) else Modifier),
                ) {
                    if (tool == LiveAssistTool.WAVE || tool == LiveAssistTool.PARADE) {
                        AssistOptionsBody(tool, state, colorMode)
                    } else com.opencapture.monitorui.MonitorOptionGroup { AssistOptionsBody(tool, state, colorMode) }
                }
            }
        }
        if (isLut) {
            LUTSplitComparisonBar(
                splitComparison = state.splitComparison,
                splitVertical = state.splitVertical,
                lutExposureStops = state.lutExposureStops,
                onToggleSplit = { state.setSplitComparison(!state.splitComparison) },
                onSplitVertical = { state.setSplitComparison(state.splitComparison, it) },
                onExposure = { state.updateLutExposure(it) },
            )
        }
    }
}

@Composable
private fun AssistOptionsBody(tool: LiveAssistTool, state: LiveAssistState, colorMode: Int) {
    when (tool) {
        LiveAssistTool.LUT, LiveAssistTool.EV, LiveAssistTool.LEVEL -> Spacer(Modifier.height(0.dp))
        LiveAssistTool.PEAK -> PeakingOptions(state)
        LiveAssistTool.FALSE -> FalseColorOptions(state, colorMode)
        LiveAssistTool.ZEBRA -> ZebraOptions(state, colorMode)
        LiveAssistTool.WAVE -> WaveformOptions(state)
        LiveAssistTool.PARADE -> ParadeOptions(state)
        LiveAssistTool.HISTO -> HistogramOptions(state)
        LiveAssistTool.VECTOR -> VectorscopeOptions(state)
        LiveAssistTool.LIGHTS -> LightsOptions(state)
        LiveAssistTool.ND -> NdOptions(state)
        LiveAssistTool.DESQ -> DesqueezeOptions(state)
        LiveAssistTool.GUIDES -> GuidesOptions(state)
        LiveAssistTool.GRID -> GridOptions(state)
        LiveAssistTool.CROSS -> com.opencapture.monitorui.MonitorAssistHelp(CrosshairAssist.HELP)
        LiveAssistTool.MIRROR -> MirrorOptions(state)
        LiveAssistTool.AUDIO -> com.opencapture.monitorui.MonitorAudioMenu(state.audioOrientation,
            state::updateAudioOrientation, state.audioShowDB, state::updateAudioShowDB, AudioAssist.HELP)
    }
}


@Composable
private fun PeakingOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorPeakingMenu(state.peakingSensitivity, state.peakingColor,
        SettingsPalette.peaking.map { com.opencapture.monitorui.settings.MonitorSettingsColorDot(it.name, it.color) },
        "Higher sensitivity catches finer edges but can get noisy on detailed scenes.",
        "Choose the edge color that stays readable over your typical scene.",
        onSensitivity = { haptics.selection(); state.setPeaking(sense = it) },
        onColor = { haptics.selection(); state.setPeaking(color = it) })
}

@Composable
private fun FalseColorOptions(state: LiveAssistState, colorMode: Int) {
    val haptics = LocalOperatorHaptics.current
    val scaleHelp =
            "The camera color mode selects D-Log, D-Log2, D-Log M, Rec.709, or HLG automatically. " +
                "CineStop paints five stops around 18% gray: dark green −2, yellow-green −1, gray, " +
                "pink +1 skin, yellow +2 upper skin, red clip, violet crush, flat gray elsewhere. " +
                "Video paints video-level IRE stripes over " +
                "luminance grayscale. IRE paints " +
                "six video-level zones over luminance grayscale. Limits " +
                "paints only shadow and highlight warnings." +
                " D-Log M uses a direct 0–100 signal scale. Its gray guide and CineStop stops are " +
                "Pocket 3 estimates, not calibrated sensor limits. Use IRE on other D-Log M cameras."
    val readHelp =
            "How false color reads log footage. 709 reads the camera's official Rec.709 look, " +
                "the way RED, ARRI and most monitors apply false color, so clip means clipped in " +
                "the Rec.709 image. LOG reads the raw signal like WAVE, with the full highlight " +
                "range and the camera's own clip."
    com.opencapture.monitorui.MonitorFalseColorMenu(
        listOf("CineStop", "Video", "IRE", "Limits").map(FalseColorScale::fromMenuLabel),
        state.falseColorScale, { haptics.selection(); state.setFalseColor(scale = it) }, { it.menuLabel },
        state.falseColorRec709, { haptics.selection(); state.setFalseColorRead(it) },
        falseColorReferenceValues(state, colorMode), state.falseColorReference,
        { haptics.selection(); state.setFalseColor(reference = it) }, scaleHelp, readHelp,
        "Show a compact color key over live view while False Color is active.")
}

@Composable
private fun ZebraOptions(state: LiveAssistState, colorMode: Int) {
    val haptics = LocalOperatorHaptics.current
    val transfer = MonitorTransfer.fromColorMode(colorMode)
    val maximum = ZebraEditor.editorMaximum(state.zebraUnit)
    com.opencapture.monitorui.MonitorZebraMenu(ZebraUnit.entries, state.zebraUnit, { it.editorLabel },
        { haptics.selection(); state.updateZebraUnit(it) },
        "Switch between native 0-255 encoded codes and a 0-100 monitoring IRE scale.",
        "High zebra warns when bright detail approaches clipping after the active log curve is compensated.",
        "Midtone zebra gives a curve-compensated reference band for faces or key subject exposure.",
        com.opencapture.monitorui.MonitorZebraZone(state.zebraHighlight,
            ZebraEditor.displayValue(state.zebraHighlightIRE, state.zebraUnit, transfer, state.scopeDisplayCeiling),
            maximum, state.zebraHighlightColor, SettingsPalette.highlight.map { com.opencapture.monitorui.settings.MonitorSettingsColorDot(it.name, it.color) },
            onEnabled = { haptics.selection(); state.setZebraHighlight(enabled = !state.zebraHighlight) },
            onThreshold = { state.setZebraHighlight(ire = ZebraEditor.ireFromDisplay(it, state.zebraUnit, transfer, state.scopeDisplayCeiling)) },
            onPaint = { haptics.selection(); state.setZebraHighlight(color = it) }),
        com.opencapture.monitorui.MonitorZebraZone(state.zebraMidtone,
            ZebraEditor.displayValue(state.zebraMidtoneIRE, state.zebraUnit, transfer, state.scopeDisplayCeiling),
            maximum, state.zebraMidtoneColor, SettingsPalette.midtone.map { com.opencapture.monitorui.settings.MonitorSettingsColorDot(it.name, it.color) },
            onEnabled = { haptics.selection(); state.setZebraMidtone(enabled = !state.zebraMidtone) },
            onThreshold = { state.setZebraMidtone(ire = ZebraEditor.ireFromDisplay(it, state.zebraUnit, transfer, state.scopeDisplayCeiling)) },
            onPaint = { haptics.selection(); state.setZebraMidtone(color = it) }))
}



@Composable
private fun WaveformOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorScopeTraceMenu(WaveformMode.entries, state.waveMode,
        { haptics.selection(); state.setWaveform(mode = it) }, { it.label },
        state.waveBrightness, { state.setWaveform(brightness = it) }, state.waveGuides,
        { haptics.selection(); state.setWaveform(guides = it) })
}

@Composable
private fun ParadeOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorScopeTraceMenu(ParadeMode.entries, state.paradeMode,
        { haptics.selection(); state.setParade(mode = it) }, { it.label },
        state.paradeBrightness, { state.setParade(brightness = it) }, state.paradeGuides,
        { haptics.selection(); state.setParade(guides = it) })
}


@Composable
private fun HistogramOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorHistogramMenu(state.histoTrafficLights,
        { haptics.selection(); state.setHistogram(traffic = !state.histoTrafficLights) },
        state.crushClipCompensation, { haptics.selection(); state.setHistogram(compensation = it) },
        HistogramAssist.TRAFFIC_LIGHTS_HELP, HistogramAssist.COMPENSATION_HELP)
}

@Composable
private fun VectorscopeOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorVectorscopeMenu(state.vectorZoom,
        { haptics.selection(); state.setVectorscope(zoom = it) }, state.vectorBrightness,
        { state.setVectorscope(brightness = it) })
}

@Composable
private fun LightsOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorCrushClipMenu(state.crushClipCompensation,
        { haptics.selection(); state.setCompensation(it) },
        "Stops of crush/clip tolerance before a channel indicator glows. Shared with the histogram traffic lights.",
        showTopDivider = false)
}

@Composable
private fun NdOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorNDMenu(state.ndNotation, {
        haptics.selection(); state.ndNotation = it; state.persist()
    }, NDAssist.NOTATION_TITLE, NDAssist.NOTATION_HELP, NDAssist.HELP)
}

@Composable
private fun GuidesOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorGuidesMenu(state.guideFamily, state.selectedGuides, state.guideMask,
        { haptics.selection(); state.updateGuideFamily(it) },
        { haptics.selection(); state.toggleGuide(it) },
        { haptics.selection(); state.updateGuideMask(it) }, ratioFeedback = { haptics.selection() },
        choiceBackground = LiveDesign.glassBright)
}

@Composable
private fun GridOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorGridMenu(state.gridThirds, { haptics.selection(); state.setGridOption(thirds = it) },
        state.gridPhi, { haptics.selection(); state.setGridOption(phi = it) },
        state.gridDiagonal, { haptics.selection(); state.setGridOption(diagonal = it) })
}

/** iOS `MirrorLongPressMenu`: help copy, then Grid-style axis switches. */
@Composable
private fun MirrorOptions(state: LiveAssistState) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorMirrorMenu(state.mirrorHorizontal,
        { haptics.selection(); state.setMirrorAxes(horizontal = it) }, state.mirrorVertical,
        { haptics.selection(); state.setMirrorAxes(vertical = it) },
        MirrorAssist.EXPLANATION, MirrorAssist.HORIZONTAL_HELP, MirrorAssist.VERTICAL_HELP)
}




@Composable
internal fun DesqueezeOptions(state: LiveAssistState) {
    com.opencapture.monitorui.MonitorDesqueezeMenu(state.desqueezePreset, state.desqueezeCustom,
        state.desqueezeCustomFactor, state.desqueezeDirection, AnamorphicDesqueeze.HELP,
        onSelect = { if (it == null) state.selectCustomDesqueeze() else state.selectDesqueezePreset(it) },
        onFactor = state::updateDesqueezeFactor, onDirection = state::updateDesqueezeDirection)
}
