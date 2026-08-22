package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.lut.LUTPicker
import com.opencapture.openpocketcine.lut.LUTSplitComparisonBar
import com.opencapture.openpocketcine.overlayGlass

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
) {
    val width = AssistLongPress.preferredWidthDp(tool).dp
    val context = LocalContext.current
    var fallbackLut by remember {
        mutableStateOf(model?.lutSelection ?: OperatorPrefs.lutSelection(context))
    }
    val lutSelection = model?.lutSelection ?: fallbackLut
    Column(
        modifier
            .widthIn(max = width)
            .width(width)
            .overlayGlass(CardShape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AssistToolGlyph(tool, LiveDesign.text, Modifier.size(15.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                tool.title.uppercase(),
                color = LiveDesign.text,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.2.sp,
            )
            Spacer(Modifier.weight(1f))
            Text(
                "✕",
                color = LiveDesign.muted,
                fontSize = 16.sp,
                modifier = Modifier.assistClick(onClick = onDismiss).padding(6.dp),
            )
        }
        if (tool == LiveAssistTool.LUT) {
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
                onToggleSplit = { state.setSplitComparison(!state.splitComparison) },
                onSplitVertical = { state.setSplitComparison(state.splitComparison, it) },
                onArmLut = { state.armLut() },
            )
            LUTSplitComparisonBar(
                splitComparison = state.splitComparison,
                splitVertical = state.splitVertical,
                onToggleSplit = { state.setSplitComparison(!state.splitComparison) },
                onSplitVertical = { state.setSplitComparison(state.splitComparison, it) },
            )
        } else {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                AssistOptionsBody(tool, state)
            }
        }
    }
}

@Composable
private fun AssistOptionsBody(tool: LiveAssistTool, state: LiveAssistState) {
    when (tool) {
        LiveAssistTool.LUT -> Spacer(Modifier.height(0.dp))
        LiveAssistTool.PEAK -> PeakingOptions(state)
        LiveAssistTool.FALSE -> FalseColorOptions(state)
        LiveAssistTool.ZEBRA -> ZebraOptions(state)
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
    OptionBlock(
        title = "Sensitivity",
        help = "Higher sensitivity catches finer edges but can get noisy on detailed scenes.",
        showTopDivider = false,
    ) {
        Segmented(
            options = PeakingSense.entries.map { it.label },
            selected = state.peakingSensitivity.label,
        ) { label ->
            state.setPeaking(sense = PeakingSense.fromPersisted(label))
        }
    }
    OptionBlock(title = "Color", help = "Choose the edge color that stays readable over your typical scene.") {
        ColorDots(
            colors =
                PeakingColor.entries.map {
                    it.label to peakingSwatch(it)
                },
            selected = state.peakingColor.label,
        ) { label ->
            state.setPeaking(color = PeakingColor.fromPersisted(label))
        }
    }
}

@Composable
private fun FalseColorOptions(state: LiveAssistState) {
    OptionBlock(
        title = "Scale",
        help =
            "The camera color mode selects D-Log, D-Log2, Rec.709, or HLG automatically. " +
                "PStops marks minimum exposure, −3, 18% gray, skin, +2, and three clip-relative " +
                "highlight levels. IRE uses WAVE-axis monitor ranges. Limits paints only shadow " +
                "and highlight warnings.",
        showTopDivider = false,
    ) {
        Segmented(
            options = listOf("PStops", "IRE", "Limits"),
            selected = state.falseColorScale.menuLabel,
        ) { label ->
            state.setFalseColor(scale = FalseColorScale.fromMenuLabel(label))
        }
    }
    OptionBlock(title = "Reference Display", help = "Show a compact color key over live view while False Color is active.") {
        ToggleRow("Reference Display", state.falseColorReference) {
            state.setFalseColor(reference = !state.falseColorReference)
        }
    }
}

@Composable
private fun ZebraOptions(state: LiveAssistState) {
    OptionBlock(
        title = "Units",
        help = "Switch between native 0-255 encoded codes and a 0-100 monitoring IRE scale.",
        showTopDivider = false,
    ) {
        Segmented(
            options = listOf("0-255", "IRE"),
            selected = state.zebraUnit.editorLabel,
        ) { label ->
            state.updateZebraUnit(ZebraUnit.fromEditorLabel(label))
        }
    }
    ZebraZoneRow(
        title = "Highlight",
        help = "High zebra warns when bright detail approaches clipping after the active log curve is compensated.",
        enabled = state.zebraHighlight,
        value = state.zebraHighlightIRE.toInt(),
        colors = listOf(ZebraPaint.WHITE, ZebraPaint.AMBER, ZebraPaint.RED),
        selected = state.zebraHighlightColor,
        onEnabled = { state.setZebraHighlight(enabled = !state.zebraHighlight) },
        onValue = { state.setZebraHighlight(ire = it.toDouble()) },
        onColor = { state.setZebraHighlight(color = it) },
    )
    ZebraZoneRow(
        title = "Midtone",
        help = "Midtone zebra gives a curve-compensated reference band for faces or key subject exposure.",
        enabled = state.zebraMidtone,
        value = state.zebraMidtoneIRE.toInt(),
        colors = listOf(ZebraPaint.AMBER, ZebraPaint.CYAN, ZebraPaint.GREEN),
        selected = state.zebraMidtoneColor,
        onEnabled = { state.setZebraMidtone(enabled = !state.zebraMidtone) },
        onValue = { state.setZebraMidtone(ire = it.toDouble()) },
        onColor = { state.setZebraMidtone(color = it) },
    )
}

@Composable
private fun ZebraZoneRow(
    title: String,
    help: String,
    enabled: Boolean,
    value: Int,
    colors: List<ZebraPaint>,
    selected: ZebraPaint,
    onEnabled: () -> Unit,
    onValue: (Int) -> Unit,
    onColor: (ZebraPaint) -> Unit,
) {
    OptionBlock(title = title, help = help) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SwitchGraphic(enabled, onEnabled)
            Stepper(value = value, range = 0..100, onChange = onValue)
            Spacer(Modifier.weight(1f))
            ColorDots(
                colors = colors.map { it.label to zebraSwatch(it) },
                selected = selected.label,
            ) { label ->
                onColor(ZebraPaint.fromPersisted(label))
            }
        }
    }
}

@Composable
private fun WaveformOptions(state: LiveAssistState) {
    OptionBlock(title = "Mode", showTopDivider = false) {
        Segmented(options = listOf("Luma", "RGB"), selected = state.waveMode.label) {
            state.setWaveform(mode = WaveformMode.fromPersisted(it))
        }
    }
    OptionBlock(title = "Brightness", help = "Raise trace intensity when the waveform is hard to read in bright light.") {
        Stepper(value = state.waveBrightness, range = 0..200, suffix = "%") {
            state.setWaveform(brightness = it)
        }
    }
    GuideToggles(state.waveGuides) { state.setWaveform(guides = it) }
}

@Composable
private fun ParadeOptions(state: LiveAssistState) {
    OptionBlock(title = "Mode", showTopDivider = false) {
        Segmented(options = listOf("RGB", "YRGB"), selected = state.paradeMode.label) {
            state.setParade(mode = ParadeMode.fromPersisted(it))
        }
    }
    OptionBlock(title = "Brightness", help = "Raise trace intensity when channel separation is hard to see.") {
        Stepper(value = state.paradeBrightness, range = 0..200, suffix = "%") {
            state.setParade(brightness = it)
        }
    }
    GuideToggles(state.paradeGuides) { state.setParade(guides = it) }
}

@Composable
private fun HistogramOptions(state: LiveAssistState) {
    OptionBlock(title = HistogramAssist.TRAFFIC_LIGHTS_TITLE, help = HistogramAssist.TRAFFIC_LIGHTS_HELP, showTopDivider = false) {
        ToggleRow(HistogramAssist.TRAFFIC_LIGHTS_TITLE, state.histoTrafficLights) {
            state.setHistogram(traffic = !state.histoTrafficLights)
        }
    }
    OptionBlock(title = HistogramAssist.COMPENSATION_TITLE, help = HistogramAssist.COMPENSATION_HELP) {
        CompensationPicker(state.crushClipCompensation) { state.setHistogram(compensation = it) }
    }
}

@Composable
private fun VectorscopeOptions(state: LiveAssistState) {
    OptionBlock(
        title = "Trace Zoom",
        help = "Magnifies only the chroma trace; the graticule stays at unity.",
        showTopDivider = false,
    ) {
        Segmented(
            options = VectorscopeZoom.entries.map { it.label },
            selected = state.vectorZoom.label,
        ) { state.setVectorscope(zoom = VectorscopeZoom.fromPersisted(it)) }
    }
    OptionBlock(title = "Brightness", help = "Raise trace intensity when the chroma plot is hard to read.") {
        Stepper(value = state.vectorBrightness, range = 0..200, suffix = "%") {
            state.setVectorscope(brightness = it)
        }
    }
}

@Composable
private fun LightsOptions(state: LiveAssistState) {
    OptionBlock(
        title = HistogramAssist.COMPENSATION_TITLE,
        help = "Stops of crush/clip tolerance before a channel indicator glows. Shared with the histogram traffic lights.",
        showTopDivider = false,
    ) {
        CompensationPicker(state.crushClipCompensation) { state.setCompensation(it) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun GuidesOptions(state: LiveAssistState) {
    Segmented(
        options = GuideFamily.entries.map { it.label },
        selected = state.guideFamily.label,
    ) { state.updateGuideFamily(GuideFamily.fromPersisted(it)) }
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
                        .assistClick { state.toggleGuide(aspect) }
                        .padding(horizontal = 10.dp, vertical = 12.dp),
            )
        }
    }
    Spacer(Modifier.height(10.dp))
    ToggleRow("Mask outside frame", state.guideMask) { state.updateGuideMask(!state.guideMask) }
}

@Composable
private fun GridOptions(state: LiveAssistState) {
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
    ToggleRow("Safe Border Clip", guides.clip) { onChange(guides.copy(clip = !guides.clip)) }
    ToggleRow("Safe Border Crush", guides.crush) { onChange(guides.copy(crush = !guides.crush)) }
    ToggleRow("Middle Gray", guides.middle) { onChange(guides.copy(middle = !guides.middle)) }
}

@Composable
private fun CompensationPicker(selected: CrushClipCompensation, onSelect: (CrushClipCompensation) -> Unit) {
    Row(
        Modifier
            .clip(CardShape)
            .background(LiveDesign.background.copy(alpha = 0.5f))
            .border(1.dp, LiveDesign.hairline, CardShape)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        CrushClipCompensation.entries.forEach { option ->
            val active = option == selected
            Text(
                option.compactLabel,
                color = if (active) LiveDesign.text else LiveDesign.muted,
                fontSize = 12.sp,
                modifier =
                    Modifier
                        .weight(1f)
                        .clip(CardShape)
                        .background(if (active) LiveDesign.surface else Color.Transparent)
                        .assistClick { onSelect(option) }
                        .padding(vertical = 8.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

@Composable
private fun OptionBlock(
    title: String,
    help: String? = null,
    showTopDivider: Boolean = true,
    content: @Composable () -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        if (showTopDivider) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(LiveDesign.hairline))
            Spacer(Modifier.height(10.dp))
        }
        Text(title, color = LiveDesign.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        if (help != null) {
            Text(help, color = LiveDesign.muted, fontSize = 11.sp, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
        } else {
            Spacer(Modifier.height(8.dp))
        }
        content()
    }
}

@Composable
private fun OptionCopy(text: String) {
    Text(text, color = LiveDesign.muted, fontSize = 13.sp)
}

@Composable
private fun Segmented(options: List<String>, selected: String, onSelect: (String) -> Unit) {
    Row(
        Modifier
            .clip(CardShape)
            .background(LiveDesign.background.copy(alpha = 0.5f))
            .border(1.dp, LiveDesign.hairline, CardShape)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        options.forEach { option ->
            val active = option == selected
            Text(
                option,
                color = if (active) LiveDesign.text else LiveDesign.muted,
                fontSize = 12.sp,
                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
                modifier =
                    Modifier
                        .weight(1f)
                        .clip(CardShape)
                        .background(if (active) LiveDesign.surface else Color.Transparent)
                        .assistClick { onSelect(option) }
                        .padding(vertical = 8.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

@Composable
private fun ToggleRow(title: String, on: Boolean, onToggle: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(CardShape)
            .background(if (on) LiveDesign.accentDim else LiveDesign.glassBright)
            .assistClick(onClick = onToggle)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = LiveDesign.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        SwitchGraphic(on)
    }
}

@Composable
private fun SwitchGraphic(on: Boolean, onClick: (() -> Unit)? = null) {
    Box(
        Modifier
            .size(22.dp)
            .clip(CircleShape)
            .border(1.5.dp, if (on) LiveDesign.accent else LiveDesign.muted, CircleShape)
            .background(if (on) LiveDesign.accent else Color.Transparent)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        if (on) Text("✓", color = LiveDesign.background, fontSize = 11.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun Stepper(value: Int, range: IntRange, suffix: String = "", onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "−",
            color = LiveDesign.text,
            fontSize = 16.sp,
            modifier =
                Modifier
                    .clip(CardShape)
                    .background(LiveDesign.background.copy(alpha = 0.5f))
                    .assistClick { onChange((value - 1).coerceIn(range.first, range.last)) }
                    .padding(horizontal = 10.dp, vertical = 4.dp),
        )
        Text(
            "$value$suffix",
            color = LiveDesign.text,
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace,
            modifier = Modifier.width(48.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        Text(
            "+",
            color = LiveDesign.text,
            fontSize = 16.sp,
            modifier =
                Modifier
                    .clip(CardShape)
                    .background(LiveDesign.background.copy(alpha = 0.5f))
                    .assistClick { onChange((value + 1).coerceIn(range.first, range.last)) }
                    .padding(horizontal = 10.dp, vertical = 4.dp),
        )
    }
}

@Composable
private fun ColorDots(colors: List<Pair<String, Color>>, selected: String, onSelect: (String) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        colors.forEach { (label, color) ->
            val on = label == selected
            Box(
                Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(LiveDesign.background.copy(alpha = 0.5f))
                    .border(if (on) 2.dp else 1.dp, if (on) color else LiveDesign.hairline, CircleShape)
                    .assistClick { onSelect(label) },
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(13.dp).clip(CircleShape).background(color))
            }
        }
    }
}

private fun peakingSwatch(color: PeakingColor): Color =
    when (color) {
        PeakingColor.WHITE -> LiveDesign.text
        PeakingColor.BLUE -> LiveDesign.info
        PeakingColor.RED -> LiveDesign.rec
        PeakingColor.GREEN -> LiveDesign.good
    }

private fun zebraSwatch(paint: ZebraPaint): Color =
    when (paint) {
        ZebraPaint.WHITE -> LiveDesign.text
        ZebraPaint.AMBER -> LiveDesign.amber
        ZebraPaint.RED -> LiveDesign.rec
        ZebraPaint.CYAN -> LiveDesign.info
        ZebraPaint.GREEN -> LiveDesign.good
    }
