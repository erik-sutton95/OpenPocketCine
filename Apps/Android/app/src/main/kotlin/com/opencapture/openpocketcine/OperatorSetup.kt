package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.OperatorHelpCopy
import com.opencapture.opencine.cameracontrols.OperatorMediaCacheDirs
import com.opencapture.opencine.cameracontrols.lutLookLabel
import com.opencapture.opencine.cameracontrols.openUrl
import com.opencapture.opencine.appkit.diagnostics.ManualProblemReportDelivery
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.opencine.vocabulary.GamepadGimbalStick
import com.opencapture.openpocketcine.diagnostics.AppDiagnostics
import com.opencapture.openpocketcine.assists.scopeDisplayCeiling

import com.opencapture.opencine.vocabulary.fromColorMode

import com.opencapture.openpocketcine.pairing.lastSSID
import com.opencapture.openpocketcine.pairing.modelName

import com.opencapture.monitorui.MonitorTab
import com.opencapture.monitorui.monitorScrollFade
import com.opencapture.monitorui.monitorTabStrip
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import com.opencapture.monitorui.MonitorJoystickSize
import com.opencapture.monitorui.MonitorLinkHealth
import com.opencapture.openpocketcine.assists.CrushClipCompensation
import com.opencapture.openpocketcine.settings.SettingsFalseColorKey
import com.opencapture.openpocketcine.assists.FalseColorScale
import com.opencapture.opencine.cameracontrols.HistogramAssist
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.opencine.cameracontrols.LiveZebra
import com.opencapture.openpocketcine.assists.ParadeMode
import com.opencapture.openpocketcine.assists.PeakingColor
import com.opencapture.openpocketcine.assists.PeakingSense
import com.opencapture.openpocketcine.assists.ScopeGuides
import com.opencapture.openpocketcine.assists.VectorscopeZoom
import com.opencapture.openpocketcine.assists.WaveformMode
import com.opencapture.opencine.cameracontrols.ZebraEditor
import com.opencapture.openpocketcine.assists.ZebraPaint
import com.opencapture.openpocketcine.assists.ZebraUnit
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.diagnostics.ManualProblemReportDialog
import com.opencapture.openpocketcine.feed.FeedUpscaler
import com.opencapture.opencine.vocabulary.LutLookResolver
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.lut.LUTPicker
import com.opencapture.openpocketcine.settings.DisplayToggleItem
import com.opencapture.openpocketcine.settings.PanelCloseButton
import com.opencapture.openpocketcine.settings.SettingsValueSlider
import com.opencapture.openpocketcine.settings.SettingsActionPill
import com.opencapture.openpocketcine.settings.SettingsColorDot
import com.opencapture.openpocketcine.settings.SettingsColorDots
import com.opencapture.openpocketcine.settings.SettingsCrushClipSegmented
import com.opencapture.openpocketcine.settings.SettingsDashScale
import com.opencapture.openpocketcine.settings.SettingsGroupCard
import com.opencapture.openpocketcine.settings.SettingsInlineRow
import com.opencapture.openpocketcine.settings.SettingsPalette
import com.opencapture.openpocketcine.settings.SettingsPercentSlider
import com.opencapture.openpocketcine.settings.SettingsRowCard
import com.opencapture.openpocketcine.settings.SettingsSegmented
import com.opencapture.openpocketcine.settings.SettingsSwitchInlineRow
import com.opencapture.openpocketcine.settings.SettingsSwitchRow
import com.opencapture.openpocketcine.settings.SettingsValueText
import com.opencapture.openpocketcine.settings.settingsClickable
import java.io.File
import java.util.Locale
import kotlinx.coroutines.delay

import com.opencapture.monitorui.settings.MonitorGimbalSettings
import com.opencapture.monitorui.settings.MonitorJoystickSettings
import com.opencapture.monitorui.settings.MonitorControllerSettings
import com.opencapture.monitorui.settings.MonitorMotionIntegerSetting
import com.opencapture.monitorui.settings.MonitorMotionChoiceSetting
import com.opencapture.monitorui.settings.MonitorMotionToggleSetting
import com.opencapture.opencine.cameracontrols.formatCacheSize
import com.opencapture.opencine.cameracontrols.formatAppVersion
import com.opencapture.opencine.cameracontrols.connectionPhaseLabel
import com.opencapture.opencine.cameracontrols.OperatorLinkHealth
import com.opencapture.opencine.cameracontrols.CleanPinTool

object SettingsHelpCopy : OperatorHelpCopy("OpenPocketCine") {
    const val PROTOCOL =
        "Camera control speaks DUML over Bluetooth and the camera's Wi-Fi. No DJI SDK is bundled or required."
}

object OpenPocketCineLinks {
    const val SOURCE = "https://github.com/erik-sutton95/OpenPocketCine"
    const val SUPPORT = "https://github.com/erik-sutton95/OpenPocketCine/discussions/categories/q-a"
    const val REPORT_PROBLEM =
        "https://github.com/erik-sutton95/OpenPocketCine/issues/new?template=bug_report.yml"
    const val FEATURE_REQUEST =
        "https://github.com/erik-sutton95/OpenPocketCine/discussions/new?category=ideas"
    const val PRIVACY = "https://openpocketcine.app/privacy/"
    const val TERMS = "https://openpocketcine.app/terms/"
}

internal object OperatorMediaCache : OperatorMediaCacheDirs({ context ->
    listOf(File(context.noBackupFilesDir, "OpenPocketCine/media"), File(context.filesDir, "OpenPocketCine/media"))
}) {
    /** Same canonical root object retires gallery writes before removing cache bytes. */
    suspend fun clearOwned(root: com.opencapture.opencine.appkit.MonitorMediaCacheRoot, fallback: () -> Unit) {
        if (!root.root.isDirectory) { fallback(); return }
        root.root.listFiles()?.forEach { cameraDir ->
            if (!cameraDir.isDirectory || cameraDir.name.startsWith(".retiring-") || cameraDir.name.startsWith(".clearing-")) return@forEach
            root.directory(cameraDir.name).clear(preserving = listOf("index.json"))
        }
    }
}


internal fun toggledCleanPins(current: Set<String>, toolKey: String): Set<String> {
    val next = current.toMutableSet()
    if (!next.add(toolKey)) next.remove(toolKey)
    return OperatorPrefs.resolvedCleanPins(next)
}

internal fun lutPickerAvailable(): Boolean = true

internal enum class AssistCard(val title: String) {
    FALSE_COLOR("False Color"),
    WAVEFORM("Waveform"),
    HISTOGRAM("Histogram"),
    PEAKING("Peaking"),
    ZEBRA("Zebra"),
    PARADE("Parade"),
    VECTORSCOPE("Vectorscope"),
    TRAFFIC_LIGHTS("Traffic Lights"),
    EV("EV Meter"),
    DESQUEEZE("Anamorphic Desqueeze"),
}

internal fun resetDispChrome(model: AppModel, mode: PocketDispMode) {
    val defaults =
        if (mode == PocketDispMode.LIVE) PocketDispChrome.liveDefaults else PocketDispChrome.cleanDefaults
    PocketDispSection.entries.forEach { section ->
        if (model.chrome(mode).isVisible(section) != defaults.isVisible(section)) {
            model.toggleChrome(section, mode)
        }
    }
}

@Composable
fun OperatorSetupScreen(model: AppModel, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val phase by model.session.phaseFlow.collectAsState()
    val failure by model.session.failure.collectAsState()
    val recovery by model.session.recoveryState.collectAsState()
    val status by model.session.chromeStatus.collectAsState()
    var tick by remember { mutableIntStateOf(0) }
    var lastFrames by remember { mutableIntStateOf(0) }
    var lastTickAt by remember { mutableLongStateOf(0L) }
    var measuredFps by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(500)
            tick += 1
            val now = SystemClock.elapsedRealtime()
            val frames = model.session.decoder.framesEnqueued.get()
            if (lastTickAt != 0L) {
                val dt = (now - lastTickAt) / 1000.0
                val presentedAge = model.session.decoder.lastPresentedAt?.let { now - it }
                measuredFps =
                    if (dt > 0 && presentedAge != null && presentedAge < 1_500) {
                        ((frames - lastFrames) / dt).coerceAtLeast(0.0)
                    } else {
                        0.0
                    }
            }
            lastFrames = frames
            lastTickAt = now
        }
    }
    tick
    val isLive = phase == ConnectionPhase.LIVE
    val bars =
        OperatorLinkHealth.bars(
            isLive,
            model.session.videoPackets,
            model.session.hasVideoFormat,
            measuredFps,
        )
    val fpsLabel =
        OperatorLinkHealth.fpsChipLabel(
            isLive = isLive,
            recovering = recovery.isRecovering,
            measuredFps = measuredFps,
            phase = phase,
        )
    val phaseLabel = connectionPhaseLabel(phase, failure)
    val view = LocalView.current
    val hapticsEnabled = model.hapticsEnabled
    var legalKind by remember { mutableStateOf<LegalKind?>(null) }
    var expandedDisp by remember { mutableStateOf<PocketDispMode?>(null) }
    var confirmClearCache by remember { mutableStateOf(false) }
    var showLutPicker by remember { mutableStateOf(false) }

    LaunchedEffect(model.chromeEditorReturnMode) {
        val returning = model.chromeEditorReturnMode ?: return@LaunchedEffect
        expandedDisp = returning
        model.chromeEditorReturnMode = null
    }

    CompositionLocalProvider(LocalMonitorGlass provides null) {
    Box(
        Modifier
            .fillMaxSize()
            .background(LiveDesign.background)
            .pointerInput(Unit) { detectTapGestures {} }
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        com.opencapture.monitorui.settings.MonitorSettingsPage(
            brand = "OPENPOCKETCINE",
            selection = model.operatorSettingsTab, tabSpacing = 0.dp,
            onSelect = { model.operatorSettingsTab = it },
            isLive = isLive, phaseLabel = phaseLabel, disconnect = model::disconnect,
            feedback = { operatorHaptic(view, model.hapticsEnabled) },
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
        ) { tab ->
            when (tab) {
                OperatorSettingsTab.LINK -> LinkRows(model, isLive, phaseLabel, bars)
                OperatorSettingsTab.SHARING -> SharingRows()
                OperatorSettingsTab.ASSIST -> AssistRows(model, status.monitorColorMode) { showLutPicker = true }
                OperatorSettingsTab.CONTROLS -> ControlsRows(model)
                OperatorSettingsTab.DISPLAY -> DisplayRows(model, isLive, expandedDisp) { expandedDisp = it }
                OperatorSettingsTab.STORAGE -> StorageRows(model) { confirmClearCache = true }
                OperatorSettingsTab.SYSTEM -> SystemRows(model) { legalKind = it }
            }
        }
        legalKind?.let { kind ->
            LegalDocumentScreen(kind = kind, onClose = { legalKind = null })
        }
        if (showLutPicker) {
            LutPickerHost(model = model, onClose = { showLutPicker = false })
        }
        if (confirmClearCache) {
            val context = LocalContext.current
            AlertDialog(
                onDismissRequest = { confirmClearCache = false },
                title = { Text("Clear cache?", color = LiveDesign.text) },
                text = {
                    Text(
                        "Removes downloaded clip files from this phone. The clip list is kept.",
                        color = LiveDesign.muted,
                    )
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            model.clearOperatorMediaCache()
                            confirmClearCache = false
                        },
                    ) {
                        Text("Clear", color = LiveDesign.rec)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { confirmClearCache = false }) {
                        Text("Cancel", color = LiveDesign.muted)
                    }
                },
                containerColor = LiveDesign.surface,
            )
        }
    }
    }
}

@Composable
fun AppSettingsScreen(model: AppModel, onClose: () -> Unit = { model.homePanel = null }) {
    OperatorSetupScreen(model, onClose)
}

private fun liveCameraName(model: AppModel): String =
    model.session.connectedCamera?.name
        ?: model.savedCameras.firstOrNull()?.displayName
        ?: "Pocket"

@Composable
private fun LutPickerHost(model: AppModel, onClose: () -> Unit) {
    LUTPicker(model = model, onClose = onClose)
}

@Composable
private fun LinkRows(model: AppModel, isLive: Boolean, phaseLabel: String, bars: Int) {
    com.opencapture.monitorui.settings.MonitorLinkHealthScale(
        title = "Link Health",
        caption = OperatorLinkHealth.caption(isLive, bars),
        score = OperatorLinkHealth.score(bars),
    )
    com.opencapture.monitorui.settings.MonitorConnectionSettings(
        transport = if (isLive) "BLE + Wi-Fi active" else "Not connected",
        transportHelp = SettingsHelpCopy.CURRENT_TRANSPORT,
        phase = phaseLabel, phaseHelp = SettingsHelpCopy.PHASE,
        network = model.session.joinedSSID?.takeIf { it.isNotEmpty() },
        networkHelp = SettingsHelpCopy.CAMERA_WIFI,
    )
    if (FeedUpscaler.supported.size > 1) {
        val context = LocalContext.current
        var upscaler by remember { mutableStateOf(OperatorPrefs.feedUpscaler(context)) }
        com.opencapture.monitorui.settings.MonitorSettingsRowCard(title = "Processing") {
            com.opencapture.monitorui.settings.MonitorSettingsInlineRow("Feed Upscaler", SettingsHelpCopy.FEED_UPSCALER, showTopDivider = false) {
                com.opencapture.monitorui.settings.MonitorSettingsSegmented(
                    options = FeedUpscaler.supported.map { it.label },
                    selected = upscaler.label,
                    compact = true,
                    fillWidth = false,
                ) { label ->
                    val next = FeedUpscaler.fromStored(label)
                    upscaler = next
                    OperatorPrefs.setFeedUpscaler(context, next)
                }
            }
        }
    }
    val saved = model.cameras.state.collectAsState().value.saved
    com.opencapture.monitorui.settings.MonitorSavedCameraSettings(cameras = saved.map { camera ->
        val network = camera.lastSSID
        com.opencapture.monitorui.settings.MonitorSavedCameraSummary(
            camera.id, camera.displayName, camera.modelName + (network?.let { " · $it" } ?: ""), network)
    }, emptyHelp = SettingsHelpCopy.SAVED_CAMERAS)
}

@Composable
private fun SharingRows() {
    SettingsRowCard {
        Text(
            "Coming soon...",
            style = LiveType.ui(15f, FontWeight.Medium),
            color = LiveDesign.muted,
            modifier = Modifier.fillMaxWidth().padding(vertical = 18.dp, horizontal = 2.dp),
        )
    }
}

@Composable
internal fun AssistRows(model: AppModel, statusColorMode: Int, onOpenLut: () -> Unit) {
    val assist = model.assist
    com.opencapture.monitorui.settings.MonitorViewAssistSettings(assistSettingsSections(assist, statusColorMode))

    com.opencapture.monitorui.settings.MonitorExposureMeterSettings(
        isOn = assist.evMeter,
        help = "Show the camera's exposure meter at the picture's left edge in DISP 1. Auto and Manual use the camera reading without changing exposure settings.",
        onToggle = { assist.toggle(LiveAssistTool.EV) },
    )

    com.opencapture.monitorui.settings.MonitorSettingsRowCard(title = "Anamorphic Desqueeze", onReset = {
        assist.updateDesqueezeFactor(1.33)
        assist.selectDesqueezePreset(com.opencapture.openpocketcine.assists.DesqueezePreset.X133)
        assist.updateDesqueezeDirection(com.opencapture.openpocketcine.assists.DesqueezeDirection.HORIZONTAL)
    }) {
        com.opencapture.monitorui.settings.MonitorSettingsSwitchInlineRow("Enabled", isOn = assist.desqueeze, showTopDivider = false) {
            assist.toggle(LiveAssistTool.DESQ)
        }
        com.opencapture.monitorui.MonitorDesqueezeMenu(
            preset = assist.desqueezePreset, custom = assist.desqueezeCustom,
            factor = assist.desqueezeCustomFactor, direction = assist.desqueezeDirection,
            help = com.opencapture.opencine.cameracontrols.AnamorphicDesqueeze.HELP,
            onSelect = { if (it == null) assist.selectCustomDesqueeze()
                else assist.selectDesqueezePreset(it) },
            onFactor = assist::updateDesqueezeFactor,
            onDirection = { assist.updateDesqueezeDirection(it) },
        )
    }

    com.opencapture.monitorui.settings.MonitorLookSettings(
        look = lutLookLabel(
            selection = model.lutSelection,
            enabled = assist.lutOn,
            colorMode = statusColorMode,
            family = model.session.connectedCamera?.model?.family ?: "pocket",
            cameraName = model.session.connectedCamera?.name,
        ),
        help = SettingsHelpCopy.LUT_LOOK, onOpen = onOpenLut,
    )
}

/** Facts use the actual app state, saved actions and sampled source calibration. */
internal fun assistSettingsSections(assist: LiveAssistState, colorMode: Int):
    List<com.opencapture.monitorui.settings.MonitorAssistSettingsSection> {
    val transfer = MonitorTransfer.fromColorMode(colorMode)
    val maximum = ZebraEditor.editorMaximum(assist.zebraUnit)
    return listOf(
        com.opencapture.monitorui.settings.MonitorAssistSettingsSection.FalseColor(
            listOf("CineStop", "Video", "IRE", "Limits").map(FalseColorScale::fromMenuLabel),
            assist.falseColorScale, { assist.setFalseColor(scale = it) }, { it.menuLabel },
            readChoice = null, reference = settingsFalseColorReferenceValues(assist, colorMode),
            referenceEnabled = assist.falseColorReference,
            onReferenceEnabled = { assist.setFalseColor(reference = it) },
            scaleHelp = SettingsHelpCopy.FALSE_COLOR_SCALE, readHelp = "",
            referenceHelp = SettingsHelpCopy.FALSE_COLOR_REFERENCE,
            reset = { assist.setFalseColor(scale = FalseColorScale.SCENE_STOPS, reference = true) }),
        com.opencapture.monitorui.settings.MonitorAssistSettingsSection.ZebraSliders(
            ZebraUnit.entries, assist.zebraUnit, { it.editorLabel }, assist::updateZebraUnit,
            SettingsHelpCopy.ZEBRA_UNITS, SettingsHelpCopy.ZEBRA_HIGHLIGHT, SettingsHelpCopy.ZEBRA_MIDTONE,
            com.opencapture.monitorui.MonitorZebraZone(assist.zebraHighlight,
                ZebraEditor.displayValue(assist.zebraHighlightIRE, assist.zebraUnit, transfer, assist.scopeDisplayCeiling),
                maximum, assist.zebraHighlightColor, commonColors(SettingsPalette.highlight),
                onEnabled = { assist.setZebraHighlight(enabled = !assist.zebraHighlight) },
                onThreshold = { assist.setZebraHighlight(ire = ZebraEditor.ireFromDisplay(it, assist.zebraUnit, transfer, assist.scopeDisplayCeiling)) },
                onPaint = { assist.setZebraHighlight(color = it) }, allowsEditingWhenOff = true),
            com.opencapture.monitorui.MonitorZebraZone(assist.zebraMidtone,
                ZebraEditor.displayValue(assist.zebraMidtoneIRE, assist.zebraUnit, transfer, assist.scopeDisplayCeiling),
                maximum, assist.zebraMidtoneColor, commonColors(SettingsPalette.midtone),
                onEnabled = { assist.setZebraMidtone(enabled = !assist.zebraMidtone) },
                onThreshold = { assist.setZebraMidtone(ire = ZebraEditor.ireFromDisplay(it, assist.zebraUnit, transfer, assist.scopeDisplayCeiling)) },
                onPaint = { assist.setZebraMidtone(color = it) }, allowsEditingWhenOff = true),
            reset = {
                assist.updateZebraUnit(ZebraUnit.IRE)
                assist.setZebraHighlight(enabled = true, ire = LiveZebra.HIGHLIGHT_IRE, color = ZebraPaint.WHITE)
                assist.setZebraMidtone(enabled = true, ire = LiveZebra.MIDTONE_IRE, color = ZebraPaint.AMBER)
            }),
        com.opencapture.monitorui.settings.MonitorAssistSettingsSection.Trace.waveform(
            WaveformMode.entries, assist.waveMode, { assist.setWaveform(mode = it) }, { it.label },
            assist.waveBrightness, { assist.setWaveform(brightness = it) }, assist.waveGuides,
            { assist.setWaveform(guides = it) },
            reset = { assist.setWaveform(mode = WaveformMode.RGB, brightness = 100, guides = ScopeGuides()) }),
        com.opencapture.monitorui.settings.MonitorAssistSettingsSection.Trace.parade(
            ParadeMode.entries, assist.paradeMode, { assist.setParade(mode = it) }, { it.label },
            assist.paradeBrightness, { assist.setParade(brightness = it) }, assist.paradeGuides,
            { assist.setParade(guides = it) },
            reset = { assist.setParade(mode = ParadeMode.RGB, brightness = 100, guides = ScopeGuides()) }),
        com.opencapture.monitorui.settings.MonitorAssistSettingsSection.Histogram(
            assist.histoTrafficLights, { assist.setHistogram(traffic = !assist.histoTrafficLights) },
            assist.crushClipCompensation, { assist.setHistogram(compensation = it) },
            HistogramAssist.TRAFFIC_LIGHTS_HELP, HistogramAssist.COMPENSATION_HELP,
            reset = { assist.setHistogram(traffic = true, compensation = CrushClipCompensation.ZERO) }),
        com.opencapture.monitorui.settings.MonitorAssistSettingsSection.Vectorscope(
            assist.vectorZoom, { assist.setVectorscope(zoom = it) },
            assist.vectorBrightness, { assist.setVectorscope(brightness = it) },
            reset = { assist.setVectorscope(zoom = VectorscopeZoom.X1, brightness = 100) }),
        com.opencapture.monitorui.settings.MonitorAssistSettingsSection.Peaking(
            assist.peakingSensitivity, assist.peakingColor, commonColors(SettingsPalette.peaking),
            SettingsHelpCopy.PEAKING_SENSITIVITY, SettingsHelpCopy.PEAKING_COLOR,
            { assist.setPeaking(sense = it) }, { assist.setPeaking(color = it) },
            reset = { assist.setPeaking(color = PeakingColor.RED, sense = PeakingSense.MED) }),
        com.opencapture.monitorui.settings.MonitorAssistSettingsSection.TrafficLights(
            assist.crushClipCompensation, { assist.setCompensation(it) }, SettingsHelpCopy.TRAFFIC_LIGHTS_COMPENSATION,
            reset = { assist.setCompensation(CrushClipCompensation.ZERO) }),
    )
}

/** Preserve the settings key's raw-signal policy; the long-press Read choice stays independent. */
private fun settingsFalseColorReferenceValues(assist: LiveAssistState, colorMode: Int):
    com.opencapture.monitorui.MonitorFalseColorReferenceValues {
    val transfer = MonitorTransfer.fromColorMode(colorMode)
    val segments = com.opencapture.opencine.cameracontrols.FalseColorReference.segments(
        assist.falseColorScale, transfer, ceiling = assist.scopeDisplayCeiling)
    val markers = if (assist.falseColorScale.usesSceneStops)
        com.opencapture.opencine.cameracontrols.FalseColorReference.sceneStopMarkers(transfer, ceiling = assist.scopeDisplayCeiling)
        else emptyList()
    return com.opencapture.monitorui.MonitorFalseColorReferenceValues(
        subtitle = assist.falseColorScale.menuLabel,
        segments = segments.mapIndexed { index, segment ->
            com.opencapture.monitorui.MonitorFalseColorReferenceSegment(index, segment.lowerFraction,
                segment.upperFraction, segment.band.red, segment.band.green, segment.band.blue)
        },
        markers = markers.mapIndexed { index, marker ->
            com.opencapture.monitorui.MonitorFalseColorReferenceMarker(index, marker.label, marker.fraction)
        }, axisLabels = com.opencapture.opencine.cameracontrols.FalseColorReference.axisLabels(assist.falseColorScale))
}

@Composable
private fun ControlsRows(model: AppModel) {
    val view = LocalView.current
    val context = LocalContext.current
    val status by model.session.chromeStatus.collectAsState()
    val layout = remember(status) { model.monitorLayout() }
    var gimbalGamepadStick by remember {
        mutableStateOf(OperatorPrefs.gimbalGamepadStick(context))
    }
    com.opencapture.monitorui.settings.MonitorOperatorSafetySettings(
        recordConfirmation = model.recordConfirmationEnabled, haptics = model.hapticsEnabled,
        keepScreenAwake = model.keepScreenAwake,
        onRecordConfirmation = model::updateRecordConfirmationEnabled,
        onHaptics = model::updateHapticsEnabled, onKeepScreenAwake = model::updateKeepScreenAwake,
        hapticsHelp = SettingsHelpCopy.HAPTICS, keepScreenAwakeHelp = SettingsHelpCopy.KEEP_SCREEN_AWAKE,
        feedback = { operatorHaptic(view, model.hapticsEnabled) },
    )
    if (layout.gimbal) {
        MonitorGimbalSettings(sensitivity = MonitorMotionIntegerSetting(
            value = model.gimbalStickSensitivity, range = 1..5, help = SettingsHelpCopy.JOYSTICK_SENSITIVITY,
        ) { next ->
            if (next != model.gimbalStickSensitivity) {
                operatorHaptic(view, model.hapticsEnabled)
                model.updateGimbalStickSensitivity(next)
            }
        })
        MonitorJoystickSettings(
            size = MonitorMotionChoiceSetting(MonitorJoystickSize.entries.map { it.label },
                model.virtualJoystickSize.label, SettingsHelpCopy.VIRTUAL_JOYSTICK_SIZE) { label ->
                val next = MonitorJoystickSize.fromLabel(label)
                if (next != model.virtualJoystickSize) {
                    operatorHaptic(view, model.hapticsEnabled)
                    model.updateVirtualJoystickSize(next)
                }
            },
            invertPan = MonitorMotionToggleSetting(model.virtualJoystickInvertPan,
                SettingsHelpCopy.VIRTUAL_JOYSTICK_INVERT_PAN) { next ->
                operatorHaptic(view, model.hapticsEnabled)
                model.updateVirtualJoystickInvertPan(next)
            },
            invertTilt = MonitorMotionToggleSetting(model.virtualJoystickInvertTilt,
                SettingsHelpCopy.VIRTUAL_JOYSTICK_INVERT_TILT) { next ->
                operatorHaptic(view, model.hapticsEnabled)
                model.updateVirtualJoystickInvertTilt(next)
            },
            deadZone = MonitorMotionIntegerSetting(model.virtualJoystickDeadzonePercent,
                0..25, SettingsHelpCopy.VIRTUAL_JOYSTICK_DEADZONE, suffix = "%") { next ->
                if (next != model.virtualJoystickDeadzonePercent) {
                    operatorHaptic(view, model.hapticsEnabled)
                    model.updateVirtualJoystickDeadzonePercent(next)
                }
            },
            response = MonitorMotionChoiceSetting(CameraCommands.VirtualJoystickCurve.entries.map { it.label },
                model.virtualJoystickResponseCurve.label, SettingsHelpCopy.VIRTUAL_JOYSTICK_RESPONSE) { label ->
                val next = CameraCommands.VirtualJoystickCurve.fromLabel(label)
                if (next != model.virtualJoystickResponseCurve) {
                    operatorHaptic(view, model.hapticsEnabled)
                    model.updateVirtualJoystickResponseCurve(next)
                }
            },
            identifierPrefix = "gimbal.virtual",
        )
    }
    MonitorControllerSettings(
        stick = MonitorMotionChoiceSetting(GamepadGimbalStick.entries.map { it.label },
            gimbalGamepadStick.label, SettingsHelpCopy.GIMBAL_JOYSTICK) { label ->
            val next = GamepadGimbalStick.fromLabel(label)
            if (next != gimbalGamepadStick) {
                operatorHaptic(view, model.hapticsEnabled)
                OperatorPrefs.setGimbalGamepadStick(context, next)
                gimbalGamepadStick = next
                model.gimbalGamepad.noteStickSelectionChanged(model)
            }
        },
        status = if (model.gamepadConnected) "Connected" else "Not connected",
        statusHelp = SettingsHelpCopy.GAMEPAD,
    )
}

@Composable
private fun DisplayRows(
    model: AppModel, isLive: Boolean, expandedDisp: PocketDispMode?,
    onExpandDisp: (PocketDispMode?) -> Unit,
) {
    val view = LocalView.current
    com.opencapture.monitorui.settings.MonitorPanelSettings(
        hdrDisplay = model.hdrDisplay, help = SettingsHelpCopy.HDR_DISPLAY,
        onChange = model::updateHdrDisplay, feedback = { operatorHaptic(view, model.hapticsEnabled) },
    )
    val status by model.session.chromeStatus.collectAsState()
    val capabilities = remember(status) { model.monitorLayout() }
    val sections = PocketDispMode.entries.map { mode ->
        val chrome = model.chrome(mode)
        com.opencapture.monitorui.settings.MonitorDisplaySection(
            id = mode.name, title = mode.settingsTitle,
            caption = if (mode == PocketDispMode.CLEAN)
                "A stripped-back image. Same elements as DISP 1 \u2014 status, tool and capture bars start off. Pin which view assists stay on."
                else mode.settingsCaption,
            reset = { operatorHaptic(view, model.hapticsEnabled); resetDispChrome(model, mode) },
            edit = if (isLive) ({
                operatorHaptic(view, model.hapticsEnabled)
                model.homePanel = null
                model.beginChromeEditing(mode)
            }) else null,
            unavailableEditHelp = "Connect to arrange this on the monitor.",
            visibility = dispToggleSpecs.filter {
                when (it.section) {
                    PocketDispSection.GIMBAL_STICK -> capabilities.gimbal
                    PocketDispSection.ZOOM_CHIP -> capabilities.zoom
                    else -> true
                }
            }.map { spec ->
                com.opencapture.monitorui.settings.MonitorDisplayToggle(
                    id = mode.name + "." + spec.section.name, title = spec.title,
                    isOn = chrome.isVisible(spec.section), help = spec.help, action = {
                        operatorHaptic(view, model.hapticsEnabled)
                        model.toggleChrome(spec.section, mode)
                    })
            },
            pinsTitle = "View assists that stay on in clean view",
            pins = if (mode == PocketDispMode.CLEAN) cleanViewPins(model, view) else emptyList(),
            style = com.opencapture.monitorui.settings.MonitorDisplaySectionStyle.CONTROLS,
        )
    }
    com.opencapture.monitorui.settings.MonitorDisplaySections(sections = sections)
}

private data class DispToggleSpec(val section: PocketDispSection, val title: String, val help: String)

private val dispToggleSpecs =
    listOf(
        DispToggleSpec(
            PocketDispSection.STATUS_BAR,
            "Status Bar",
            "REC, timecode, format, and FPS along the top of the feed.",
        ),
        DispToggleSpec(PocketDispSection.TOOL_BAR, "Tool Bar", "The view-assist strip under the feed."),
        DispToggleSpec(
            PocketDispSection.CAMERA_VALUES,
            "Camera Values",
            "ISO, shutter, white balance, and the rest of the capture strip.",
        ),
        DispToggleSpec(
            PocketDispSection.LOCK_BUTTON,
            "Lock Button",
            "Side-rail lock. Remounts while the interface is locked.",
        ),
        DispToggleSpec(PocketDispSection.BATTERIES, "Batteries", "Phone and camera battery cluster."),
        DispToggleSpec(PocketDispSection.REC_READOUT, "REC", "Standby / recording chip on the status bar."),
        DispToggleSpec(PocketDispSection.TIMECODE, "Timecode", "Running timecode on the status bar."),
        DispToggleSpec(PocketDispSection.FORMAT, "Format", "Recording resolution and frame rate."),
        DispToggleSpec(PocketDispSection.COLOR, "Color", "Color mode chip on the status bar."),
        DispToggleSpec(PocketDispSection.STORAGE, "Storage", "Remaining media time on the status bar."),
        DispToggleSpec(PocketDispSection.FPS, "FPS", "Live-view rate and link bars."),
        DispToggleSpec(PocketDispSection.RAIL_RECORD, "Record", "Rail record lamp. Stays available while rolling."),
        DispToggleSpec(PocketDispSection.RAIL_MEDIA, "Media", "Rail media button."),
        DispToggleSpec(PocketDispSection.RAIL_SETTINGS, "Settings", "Rail settings button. Always an escape hatch."),
        DispToggleSpec(PocketDispSection.ZOOM_CHIP, "Zoom Chip", "Live zoom readout on the feed."),
        DispToggleSpec(PocketDispSection.GIMBAL_STICK, "Gimbal Stick", "On-screen gimbal stick."),
        DispToggleSpec(PocketDispSection.FOCUS_BOX, "AF Box", "Focus and face-tracking brackets on the feed."),
    )

private fun cleanViewPins(model: AppModel, view: View): List<com.opencapture.monitorui.settings.MonitorDisplayToggle> =
    CleanPinTool.entries.filter { it != CleanPinTool.AUDIO || model.monitorLayout().audio }.map { tool ->
        com.opencapture.monitorui.settings.MonitorDisplayToggle(
            id = "clean.pin." + tool.key, title = tool.title,
            isOn = model.assist.pinned.any { it.name == tool.key },
            accessibilityLabel = "Keep ${tool.title} in clean view", action = {
                operatorHaptic(view, model.hapticsEnabled)
                val next = toggledCleanPins(model.assist.pinned.map { it.name }.toSet(), tool.key)
                model.assist.pinned = next.mapNotNull(LiveAssistTool::fromPersisted).toSet()
                model.updateCleanViewPinnedTools(next)
            })
    }

@Composable
private fun StorageRows(model: AppModel, onClearCache: () -> Unit) {
    val context = LocalContext.current
    val view = LocalView.current
    val bytes = OperatorMediaCache.byteCount(context)
    val cacheLabel =
        if (OperatorMediaCache.existingDir(context) == null) "Empty" else formatCacheSize(bytes)
    com.opencapture.monitorui.settings.MonitorAccountSettings(
        title = "Frame.io", help = SettingsHelpCopy.FRAME_IO,
        state = com.opencapture.monitorui.settings.MonitorAccountState.NOT_CONFIGURED,
    )
    com.opencapture.monitorui.settings.MonitorCacheSettings(
        cacheOriginals = model.cacheFullResolution, sizeLabel = cacheLabel,
        cacheHelp = SettingsHelpCopy.CACHE_FULL_RESOLUTION,
        scopeHelp = SettingsHelpCopy.LOCAL_CACHE, clearHelp = SettingsHelpCopy.CLEAR_CACHE,
        onCacheOriginals = model::updateCacheFullResolution, clear = onClearCache,
        feedback = { operatorHaptic(view, model.hapticsEnabled) },
    )
}

@Composable
private fun SystemRows(model: AppModel, onLegal: (LegalKind) -> Unit) {
    val context = LocalContext.current
    val view = LocalView.current
    var reliabilityOptIn by remember { mutableStateOf(AppDiagnostics.reporting.isOptedIn) }
    var diagnosticOptions by remember { mutableStateOf(false) }
    var showReportForm by remember { mutableStateOf(false) }
    val report by AppDiagnostics.manualReport.snapshot.collectAsState()
    com.opencapture.monitorui.settings.MonitorSupportSettings(
        automaticReports = reliabilityOptIn, available = AppDiagnostics.reporting.isAvailable,
        automaticHelp = SettingsHelpCopy.RELIABILITY_REPORTS,
        unavailableHelp = SettingsHelpCopy.RELIABILITY_UNAVAILABLE,
        onAutomaticReports = { reliabilityOptIn = it; AppDiagnostics.reporting.setConsent(it) },
        report = { showReportForm = true }, privacy = { onLegal(LegalKind.PRIVACY) },
        status = if (report.delivery == ManualProblemReportDelivery.IDLE) null else
            com.opencapture.monitorui.settings.MonitorReportStatus(report.statusLabel,
                report.detail ?: "This phone keeps one report until Sentry accepts it or you discard it.", report.eventId),
        discard = if (report.allowsDiscard) ({ AppDiagnostics.manualReport.discard() }) else null,
        feedback = { operatorHaptic(view, model.hapticsEnabled) },
    )
    com.opencapture.monitorui.settings.MonitorDiagnosticSettings(
        expanded = diagnosticOptions, onExpanded = { diagnosticOptions = it },
        deleteHelp = "Remove saved feed reports from this phone. Connection logs remain. Turn off automatic reporting to clear pending uploads. Reports already sent cannot be removed here.",
        save = { DiagnosticCenter.shareReport(context, model.session, copyForFeedback = false) },
        delete = {
            AppDiagnostics.incidents.deleteStoredReports { deleted ->
                android.widget.Toast.makeText(context,
                    if (deleted) "Saved feed reports deleted" else "Couldn't delete saved feed reports. Please try again.",
                    android.widget.Toast.LENGTH_LONG).show()
            }
        },
    )
    if (showReportForm) {
        ManualProblemReportDialog(
            model = model,
            onClose = { showReportForm = false },
            onPrivacy = {
                showReportForm = false
                onLegal(LegalKind.PRIVACY)
            },
        )
    }

    com.opencapture.monitorui.settings.MonitorProjectLegalSettings(
        sourceHelp = SettingsHelpCopy.SOURCE, termsHelp = "How you can use OpenPocketCine.",
        source = { openUrl(context, OpenPocketCineLinks.SOURCE) },
        privacy = { onLegal(LegalKind.PRIVACY) },
        terms = { openUrl(context, OpenPocketCineLinks.TERMS) },
        licenses = { onLegal(LegalKind.LICENSES) }, notice = { onLegal(LegalKind.NOTICE) },
    )
    com.opencapture.monitorui.settings.MonitorAppInformationSettings(
        theme = "DJI Black", protocolName = "DUML / BLE + Wi-Fi",
        version = formatAppVersion(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toLong()),
        themeHelp = SettingsHelpCopy.THEME,
        protocolHelp = SettingsHelpCopy.PROTOCOL,
        versionHelp = SettingsHelpCopy.APP_VERSION,
    )
}


private fun operatorHaptic(view: View, enabled: Boolean) {
    if (!enabled) return
    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
}

@Composable
fun OperatorCloseButton(onClose: () -> Unit, modifier: Modifier = Modifier) {
    PanelCloseButton(onClick = onClose, modifier = modifier)
}

/** Maps the app settings palette dots onto the shared settings color dot. */
private fun commonColors(colors: List<SettingsColorDot>) = colors.map {
    com.opencapture.monitorui.settings.MonitorSettingsColorDot(it.name, it.color)
}
