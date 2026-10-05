package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.feed.fromColorMode
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import com.opencapture.monitorui.MonitorWaveformScopePlot
import com.opencapture.monitorui.MonitorParadeScopePlot
import com.opencapture.monitorui.MonitorVectorscopeScopePlot
import com.opencapture.monitorui.MonitorScopeGuides
import com.opencapture.openpocketcine.ChromeRect
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.NDFilterRecommendation
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.ScopeAssistBundle
import com.opencapture.openpocketcine.feed.WaveformIre

private val PanelShape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)

@Composable
internal fun MovableAssistPanel(
    tool: LiveAssistTool, base: AssistSize, scale: Double, stored: StoredCenter?,
    canvas: AssistRect, placementBounds: AssistRect, defaultCenter: AssistPoint, enabled: Boolean,
    onStore: (StoredCenter) -> Unit, onScale: ((Double) -> Unit)? = null,
    onOpenOptions: ((ChromeRect) -> Unit)? = null, onActivate: () -> Unit = {},
    fillPlate: Boolean = true, chip: Boolean = false, content: @Composable (AssistSize) -> Unit,
) {
    val haptics = LocalOperatorHaptics.current
    com.opencapture.monitorui.MonitorMovableScopePanel(
        identity = tool.name, base = base, scale = scale, stored = stored, canvas = canvas,
        placementBounds = placementBounds, defaultCenter = defaultCenter, enabled = enabled,
        onStore = onStore, onScale = onScale,
        onOpenOptions = onOpenOptions?.let { open -> { rect -> open(ChromeRect(rect.x, rect.y, rect.width, rect.height)) } },
        anchorOrigin = com.opencapture.openpocketcine.LocalLiveCanvasOrigin.current,
        onActivate = onActivate, onConfirm = { haptics.confirm() },
        fillPlate = fillPlate, chip = chip, content = content,
    )
}
@Composable
internal fun WaveformPanel(state: LiveAssistState, colorMode: Int, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    val bundle = previewBundle ?: state.scopeBundle
    val transfer = bundle.resolvedTransfer(colorMode)
    val table = remember(transfer, bundle.iso, bundle.ceiling) { WaveformIre.levelTable(transfer, bundle.iso, bundle.ceiling) }
    MonitorWaveformScopePlot(bundle, transfer, table, state.waveMode,
        WaveformAssist.intensity(state.waveBrightness),
        MonitorScopeGuides(state.waveGuides.clip, state.waveGuides.crush, state.waveGuides.middle), modifier)
}

@Composable
internal fun ParadePanel(state: LiveAssistState, colorMode: Int, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    val bundle = previewBundle ?: state.scopeBundle
    val transfer = bundle.resolvedTransfer(colorMode)
    val table = remember(transfer, bundle.iso, bundle.ceiling) { WaveformIre.levelTable(transfer, bundle.iso, bundle.ceiling) }
    MonitorParadeScopePlot(bundle, transfer, table, state.paradeMode,
        ParadeAssist.intensity(state.paradeBrightness),
        MonitorScopeGuides(state.paradeGuides.clip, state.paradeGuides.crush, state.paradeGuides.middle), modifier)
}

@Composable
internal fun HistogramPanel(state: LiveAssistState, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    val bundle = previewBundle ?: state.scopeBundle
    com.opencapture.monitorui.MonitorHistogramScopePlot(bundle.histogramDisplay, bundle.traffic,
        state.histoTrafficLights, modifier)
}

@Composable
internal fun VectorscopePanel(state: LiveAssistState, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    MonitorVectorscopeScopePlot(previewBundle ?: state.scopeBundle, state.vectorZoom, state.vectorBrightness, modifier)
}

@Composable
internal fun TrafficLightsPanel(state: LiveAssistState, modifier: Modifier = Modifier,
    previewBundle: com.opencapture.openpocketcine.feed.ScopeAssistBundle? = null) {
    com.opencapture.monitorui.MonitorTrafficLightsMeter((previewBundle ?: state.scopeBundle).traffic, modifier)
}


object NDAssist {
    const val HELP =
        "Meters the live picture against middle gray and suggests a screw-on ND - stops and ND number - to balance it. The app cannot set a filter."
    const val METER_TITLE = "ND"
    const val NOTATION_TITLE = "Units"
    const val NOTATION_HELP =
        "Stops vs middle gray, filter factor (ND16 / ND32 / ND64), or optical density (ND 0.3 = 1 stop)."
}

@Composable
internal fun NDMeterPanel(state: LiveAssistState, modifier: Modifier = Modifier) {
    val transfer = state.scopeBundle.transfer
    val reading =
        NDFilterRecommendation.reading(state.scopeBundle.samples.histogramLuma, transfer)
    com.opencapture.monitorui.MonitorNDFilterChip(reading, state.ndNotation, modifier,
        emptyLabel = NDFilterRecommendation.NONE_LABEL)
}

private fun ScopeAssistBundle.resolvedTransfer(colorMode: Int): MonitorTransfer =
    if (revision > 0L) transfer else MonitorTransfer.fromColorMode(colorMode)

@Composable
internal fun Modifier.scopePanelChrome(): Modifier =
    monitorMaterial(MonitorMaterial.Scope, PanelShape)
