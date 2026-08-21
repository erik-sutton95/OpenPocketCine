package com.opencapture.openpocketcine

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.opencapture.openpocketcine.glass.LiquidSlider
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.FocusTrackMode
import java.util.Locale
import kotlin.math.abs
import kotlin.math.round
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class LiveSheet {
    ISO,
    SHUTTER,
    WB,
    FOCUS,
    EXPO,
    AUDIO,
    COLOR,
    FORMAT,
}

@Composable
fun LiveControlSheet(
    sheet: LiveSheet,
    model: AppModel,
    status: CameraStatus,
    locked: Boolean,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val enabled = !locked
    val isEvSheet = sheet == LiveSheet.SHUTTER && status.expoMode == CameraCommands.EXPO_AUTO
    val offersIsoAuto = CaptureLists.offersIsoAuto(status)
    var selectedMode by remember(sheet) {
        mutableIntStateOf(initialSelectedMode(sheet, status, model, isEvSheet))
    }
    var drumSelection by remember(sheet) { mutableStateOf("") }
    var lastApplied by remember(sheet) { mutableStateOf("") }
    var tintDraft by remember(sheet) { mutableFloatStateOf(CaptureLists.currentTint(status).toFloat()) }
    var preferredAngle by remember(sheet) { mutableStateOf(OperatorPrefs.shutterAngleDegrees(context)) }
    val scope = rememberCoroutineScope()
    var drumJob by remember { mutableStateOf<Job?>(null) }
    val isIsoAutoTab = sheet == LiveSheet.ISO && offersIsoAuto && selectedMode == 0
    val isAngleSheet = sheet == LiveSheet.SHUTTER && !isEvSheet && selectedMode == 1
    val tabs = modeTabs(sheet, isEvSheet, offersIsoAuto)

    fun enqueueDrumSend(send: () -> Unit) {
        if (!enabled) return
        drumJob?.cancel()
        drumJob = scope.launch {
            delay(80)
            send()
        }
    }

    fun reseatIsoAutoDrum() {
        val labels = CaptureLists.isoAutoLabels(status)
        val live = CaptureLists.isoAutoLabel(status)
        val next = if (live in labels) live else labels.firstOrNull().orEmpty()
        lastApplied = next
        drumSelection = next
    }

    fun reseatIsoDiscrete() {
        val labels = CaptureLists.isoDrumLabels(status)
        val live =
            when {
                status.isoIndex > 0 -> CameraCommands.isoLabel(status.isoIndex)
                status.iso > 0 -> "${status.iso}"
                else -> labels.firstOrNull().orEmpty()
            }
        val next = if (live in labels) live else labels.firstOrNull().orEmpty()
        lastApplied = next
        drumSelection = next
    }

    fun reseatIso() {
        if (offersIsoAuto) {
            selectedMode = if (status.isoIndex == 0) 0 else 1
        } else {
            selectedMode = 0
        }
        if (sheet == LiveSheet.ISO && offersIsoAuto && selectedMode == 0) {
            reseatIsoAutoDrum()
        } else {
            reseatIsoDiscrete()
        }
    }

    fun reseatEv() {
        val labels = CaptureLists.evLabels
        val live = EvComp.fromRaw(status.evComp)?.label ?: "0.0"
        val next = if (live in labels) live else "0.0"
        lastApplied = next
        drumSelection = next
    }

    fun reseatShutterAngle() {
        val labels = ShutterAngle.labels
        val fps = status.fps
        val liveDenom = status.shutterDenom
        val preferred = ShutterAngle.label(preferredAngle)
        if (liveDenom > 0) {
            val mapped =
                ShutterAngle.denom(preferredAngle, fps, CaptureLists.shutterDenoms(status))
            if (mapped == liveDenom && preferred in labels) {
                lastApplied = preferred
                drumSelection = preferred
                return
            }
            val next = ShutterAngle.nearestLabel(liveDenom, fps)
            preferredAngle = ShutterAngle.parse(next) ?: ShutterAngle.DEFAULT_DEGREES
            OperatorPrefs.setShutterAngleDegrees(context, preferredAngle)
            lastApplied = next
            drumSelection = next
            return
        }
        lastApplied = preferred
        drumSelection = if (preferred in labels) preferred else labels.firstOrNull().orEmpty()
    }

    fun reseatShutter() {
        if (selectedMode == 1 && !isEvSheet) {
            reseatShutterAngle()
            return
        }
        val labels = CaptureLists.shutterLabels(status)
        val live =
            if (status.shutterDenom > 0) CaptureLists.shutterLabel(status.shutterDenom)
            else labels.firstOrNull().orEmpty()
        val next =
            when {
                live in labels -> live
                else -> CaptureLists.nearestShutterLabel(live, status)
            }
        lastApplied = next
        drumSelection = next
    }

    fun reseatShutterOrEv() {
        if (isEvSheet) reseatEv() else reseatShutter()
    }

    fun reseatWb() {
        val k = "${CaptureLists.currentKelvin(status)}K"
        drumSelection = if (k in CaptureLists.kelvinLabels) k else "5600K"
        lastApplied = drumSelection
        tintDraft = CaptureLists.currentTint(status).toFloat()
    }

    fun reseatResolution() {
        selectedMode = if (status.resolutionCode == CameraCommands.RES_4K) 1 else 0
        val label = CaptureLists.fpsDrumLabel(status)
        drumSelection = label
        lastApplied = label
    }

    fun reseatColor() {
        val labels = CaptureLists.colorWheelLabels(status)
        val live = CameraCommands.colorLabel(status.colorMode)
        val next = if (live in labels) live else labels.firstOrNull().orEmpty()
        drumSelection = next
        lastApplied = next
    }

    fun seed() {
        when (sheet) {
            LiveSheet.ISO -> reseatIso()
            LiveSheet.SHUTTER -> {
                if (!isEvSheet) selectedMode = if (model.shutterUsesAngle) 1 else 0
                reseatShutterOrEv()
            }
            LiveSheet.WB -> {
                selectedMode =
                    if (status.wbMode == CameraCommands.WB_CUSTOM) 1 else 0
                reseatWb()
            }
            LiveSheet.AUDIO -> selectedMode = 0
            LiveSheet.FORMAT -> reseatResolution()
            LiveSheet.COLOR -> reseatColor()
            else -> selectedMode = 0
        }
    }

    fun applyVideoFormat(tab: Int, drum: String) {
        val rate = CaptureLists.fpsIndexFromDrum(drum) ?: CaptureLists.currentFpsIndex(status)
        val res = if (tab == 1) CameraCommands.RES_4K else CameraCommands.RES_1080
        if (res == status.resolutionCode && rate == status.fpsIndex) return
        model.setResolutionFps(res, rate)
    }

    fun handleModeChange(index: Int) {
        if (!enabled) return
        when {
            sheet == LiveSheet.ISO && offersIsoAuto -> {
                if (index == 0) {
                    model.setIsoIndex(0)
                    reseatIsoAutoDrum()
                } else {
                    reseatIsoDiscrete()
                    CaptureLists.isoIndexFromLabel(drumSelection)?.let { idx ->
                        if (idx in CaptureLists.isoIndices(status)) model.setIsoIndex(idx)
                    }
                }
            }
            sheet == LiveSheet.SHUTTER && !isEvSheet -> {
                model.updateShutterUsesAngle(index == 1)
                // Tab change reseats after selectedMode is written by the caller.
            }
            sheet == LiveSheet.FORMAT -> applyVideoFormat(index, drumSelection)
        }
    }

    fun applyDrum(value: String) {
        if (!enabled || value.isEmpty() || value == lastApplied) return
        lastApplied = value
        when (sheet) {
            LiveSheet.ISO -> {
                if (isIsoAutoTab) {
                    val limit = CaptureLists.isoLimit(value, status) ?: return
                    enqueueDrumSend { model.setIsoLimit(limit.rawValue) }
                    return
                }
                val idx = CaptureLists.isoIndexFromLabel(value) ?: return
                if (idx !in CaptureLists.isoIndices(status) || idx == 0) return
                enqueueDrumSend { model.setIsoIndex(idx) }
            }
            LiveSheet.SHUTTER -> {
                if (isEvSheet) {
                    if (model.facePriorityExposureEnabled) return
                    val ev = EvComp.fromLabel(value) ?: return
                    enqueueDrumSend { model.setEv(ev.thirds) }
                    return
                }
                if (selectedMode == 1) {
                    val degrees = ShutterAngle.parse(value) ?: return
                    preferredAngle = degrees
                    OperatorPrefs.setShutterAngleDegrees(context, degrees)
                    val denom =
                        ShutterAngle.denom(
                            degrees,
                            status.fps,
                            CaptureLists.shutterDenoms(status),
                        )
                    enqueueDrumSend { model.setShutterDenom(denom) }
                    return
                }
                val denom = CaptureLists.denomFromLabel(value) ?: return
                if (denom !in CaptureLists.shutterDenoms(status)) return
                enqueueDrumSend { model.setShutterDenom(denom) }
            }
            LiveSheet.WB -> {
                if (selectedMode != 1) return
                val kelvin = CaptureLists.kelvinFromLabel(value) ?: return
                model.setWhiteBalance(kelvin, CaptureLists.currentTint(status))
            }
            LiveSheet.FORMAT -> {
                applyVideoFormat(selectedMode, value)
            }
            LiveSheet.COLOR -> {
                val mode = CaptureLists.colorModeFromLabel(value) ?: return
                model.setColorMode(mode)
            }
            else -> Unit
        }
    }

    LaunchedEffect(sheet) {
        if (sheet == LiveSheet.AUDIO) model.refreshAudio()
        if (sheet == LiveSheet.FOCUS && status.focusTrack < 0) model.refreshFocusTrack()
        drumJob?.cancel()
        seed()
    }
    LaunchedEffect(sheet, status.availableIsoIndices, status.colorMode, status.isoIndex, status.isoLimit) {
        if (sheet == LiveSheet.ISO) reseatIso()
    }
    LaunchedEffect(
        sheet,
        status.availableShutterDenoms,
        status.fps,
        status.expoMode,
        status.shutterDenom,
        status.evComp,
    ) {
        if (sheet == LiveSheet.SHUTTER) {
            if (status.expoMode != CameraCommands.EXPO_AUTO) {
                selectedMode = if (model.shutterUsesAngle) 1 else 0
            }
            reseatShutterOrEv()
        }
    }
    LaunchedEffect(sheet, model.facePriorityExposureEnabled) {
        if (sheet == LiveSheet.SHUTTER && isEvSheet) reseatEv()
    }
    LaunchedEffect(sheet, status.wbMode, status.wbKelvin, status.wbTint) {
        if (sheet == LiveSheet.WB && selectedMode != 2) reseatWb()
    }
    LaunchedEffect(sheet, status.resolutionCode, status.fpsIndex, status.fps) {
        if (sheet == LiveSheet.FORMAT) reseatResolution()
    }
    LaunchedEffect(sheet, status.colorMode) {
        if (sheet == LiveSheet.COLOR) reseatColor()
    }
    DisposableEffect(sheet) { onDispose { drumJob?.cancel() } }

    Box(
        Modifier.fillMaxWidth().padding(bottom = 10.dp),
        contentAlignment = Alignment.BottomEnd,
    ) {
        Column(
            Modifier
                .widthIn(max = LiveDesign.CAPTURE_PICKER_WIDTH_DP.dp)
                .fillMaxWidth()
                .overlayGlass(ChromeShape)
                .border(1.dp, LiveDesign.hairlineStrong, ChromeShape)
                .pointerInput(Unit) { detectTapGestures(onTap = {}) }
                .padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            SheetHeader(
                title = headerTitle(sheet, isEvSheet),
                subtitle = headerSubtitle(sheet, isEvSheet, isAngleSheet, model.facePriorityExposureEnabled),
                onClose = onDismiss,
            )
            when (sheet) {
                LiveSheet.ISO -> {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (isIsoAutoTab) {
                            CaptureDrumWheel(
                                options = CaptureLists.isoAutoLabels(status),
                                selection = drumSelection,
                                interactive = enabled,
                                onSelect = {
                                    drumSelection = it
                                    applyDrum(it)
                                },
                            )
                        } else {
                            CaptureDrumWheel(
                                options = CaptureLists.isoDrumLabels(status),
                                selection = drumSelection,
                                markedValues = CaptureLists.isoMarkedLabels(status),
                                interactive = enabled,
                                onSelect = {
                                    drumSelection = it
                                    applyDrum(it)
                                },
                            )
                        }
                        PrefToggle(
                            title = CaptureLists.NATIVE_ISO_HOP_TITLE,
                            help = CaptureLists.NATIVE_ISO_HOP_HELP,
                            checked = model.nativeISOHopEnabled,
                            enabled = enabled,
                            onCheckedChange = model::updateNativeISOHopEnabled,
                        )
                    }
                }
                LiveSheet.SHUTTER -> {
                    if (isEvSheet) {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            CaptureDrumWheel(
                                options = CaptureLists.evLabels,
                                selection = drumSelection,
                                interactive = enabled && !model.facePriorityExposureEnabled,
                                onSelect = {
                                    drumSelection = it
                                    applyDrum(it)
                                },
                            )
                            PrefToggle(
                                title = CaptureLists.FACE_PRIORITY_TITLE,
                                help = CaptureLists.FACE_PRIORITY_HELP,
                                checked = model.facePriorityExposureEnabled,
                                enabled = enabled,
                                onCheckedChange = model::updateFacePriorityExposureEnabled,
                            )
                        }
                    } else if (isAngleSheet) {
                        CaptureDrumWheel(
                            options = ShutterAngle.labels,
                            selection = drumSelection,
                            interactive = enabled,
                            onSelect = {
                                drumSelection = it
                                applyDrum(it)
                            },
                        )
                    } else {
                        CaptureDrumWheel(
                            options = CaptureLists.shutterLabels(status),
                            selection = drumSelection,
                            interactive = enabled,
                            onSelect = {
                                drumSelection = it
                                applyDrum(it)
                            },
                        )
                    }
                }
                LiveSheet.WB -> {
                    when (selectedMode) {
                        0 ->
                            CheckedRows(
                                options = listOf("Auto", "Custom"),
                                selected =
                                    if (status.wbMode == CameraCommands.WB_CUSTOM) "Custom" else "Auto",
                                enabled = enabled,
                            ) { label ->
                                if (label == "Auto") {
                                    model.setWhiteBalanceAuto()
                                } else {
                                    model.setWhiteBalance(
                                        CaptureLists.currentKelvin(status),
                                        CaptureLists.currentTint(status),
                                    )
                                }
                            }
                        1 ->
                            CaptureDrumWheel(
                                options = CaptureLists.kelvinLabels,
                                selection = drumSelection,
                                interactive = enabled,
                                onSelect = {
                                    drumSelection = it
                                    applyDrum(it)
                                },
                            )
                        else ->
                            TintPad(
                                tint = tintDraft,
                                enabled = enabled,
                                onTint = { tintDraft = it },
                                onCommit = { value ->
                                    val t = value.roundToInt().coerceIn(-100, 100)
                                    model.setWhiteBalance(CaptureLists.currentKelvin(status), t)
                                },
                            )
                    }
                }
                LiveSheet.FOCUS -> {
                    if (CaptureLists.supportsFocusMode(model.session.connectedCamera?.model?.name)) {
                        FocusBody(
                            status = status,
                            enabled = enabled,
                            onContinuous = model::setFocusMode,
                            onTrack = model::setFocusTrack,
                        )
                    }
                }
                LiveSheet.EXPO -> {
                    val expoRows = listOf("Auto", "Manual")
                    val shooting = CaptureLists.shootingModeLabels
                    CheckedRows(
                        options = expoRows,
                        selected = status.expoLabel.takeIf { it in expoRows },
                        enabled = enabled,
                    ) { label ->
                        model.setExpoMode(label == "Manual")
                    }
                    if (status.shootingMode >= 0) {
                        CheckedRows(
                            options = shooting,
                            selected = CaptureLists.shootingModeLabel(status.shootingMode),
                            enabled = enabled,
                        ) { label ->
                            CaptureLists.shootingModeRaw(label)?.let { model.setShootingMode(it) }
                        }
                    }
                }
                LiveSheet.AUDIO -> AudioBody(status, enabled, selectedMode, model)
                LiveSheet.COLOR ->
                    CaptureDrumWheel(
                        options = CaptureLists.colorWheelLabels(status),
                        selection = drumSelection,
                        interactive = enabled,
                        onSelect = {
                            drumSelection = it
                            applyDrum(it)
                        },
                    )
                LiveSheet.FORMAT ->
                    CaptureDrumWheel(
                        options = CaptureLists.fpsDrumLabels,
                        selection = drumSelection,
                        interactive = enabled,
                        onSelect = {
                            drumSelection = it
                            applyDrum(it)
                        },
                    )
            }
            if (tabs.isNotEmpty()) {
                ModeBar(
                    tabs = tabs,
                    selected = selectedMode,
                    enabled = enabled,
                ) { index ->
                    selectedMode = index
                    handleModeChange(index)
                    if (sheet == LiveSheet.SHUTTER && !isEvSheet) {
                        if (index == 1) reseatShutterAngle() else reseatShutter()
                    }
                }
            }
        }
    }
}

@Composable
private fun SheetHeader(title: String, subtitle: String, onClose: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.weight(1f),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                title,
                style = LiveType.ui(18f, FontWeight.ExtraBold).copy(letterSpacing = 2.sp),
                maxLines = 1,
            )
            Text(
                subtitle.uppercase(),
                style = LiveType.mono(11f, FontWeight.SemiBold).copy(letterSpacing = 1.5.sp),
                color = LiveDesign.faint,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(bottom = 2.dp),
            )
        }
        Box(
            Modifier
                .size(34.dp)
                .glass(CircleShape)
                .chromeClickable(onClick = onClose)
                .semantics { contentDescription = "Close" },
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.size(13.dp)) {
                val stroke = 2.2.dp.toPx()
                drawLine(
                    LiveDesign.text,
                    Offset(0f, 0f),
                    Offset(size.width, size.height),
                    stroke,
                    StrokeCap.Round,
                )
                drawLine(
                    LiveDesign.text,
                    Offset(size.width, 0f),
                    Offset(0f, size.height),
                    stroke,
                    StrokeCap.Round,
                )
            }
        }
    }
}

@Composable
private fun ModeBar(tabs: List<String>, selected: Int, enabled: Boolean, onSelect: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        tabs.forEachIndexed { index, title ->
            val active = index == selected
            Text(
                title.uppercase(),
                style = LiveType.ui(13f, FontWeight.Bold).copy(letterSpacing = 0.5.sp),
                color = if (active) LiveDesign.accent else LiveDesign.muted,
                textAlign = TextAlign.Center,
                modifier =
                    Modifier.weight(1f)
                        .clip(ChromeShape)
                        .background(if (active) LiveDesign.accentDim else LiveDesign.background.copy(alpha = 0.28f))
                        .border(1.5.dp, if (active) LiveDesign.accent else LiveDesign.hairline, ChromeShape)
                        .chromeClickable(enabled = enabled, onClick = { onSelect(index) })
                        .padding(vertical = 12.dp)
                        .fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun CheckedRows(
    options: List<String>,
    selected: String?,
    enabled: Boolean,
    onSelect: (String) -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, option ->
            val on = option == selected
            Row(
                Modifier.fillMaxWidth()
                    .chromeClickable(enabled = enabled, onClick = { onSelect(option) })
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    option,
                    style = LiveType.ui(17f, FontWeight.Medium),
                    color = if (on) LiveDesign.accent else LiveDesign.text,
                    modifier = Modifier.weight(1f),
                )
                if (on) {
                    Text("✓", color = LiveDesign.accent, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            if (index != options.lastIndex) {
                Box(Modifier.fillMaxWidth().height(1.dp).background(LiveDesign.hairline))
            }
        }
    }
}

private val FocusTrackCapsule = RoundedCornerShape(percent = 50)

@Composable
private fun FocusBody(
    status: CameraStatus,
    enabled: Boolean,
    onContinuous: (Boolean) -> Unit,
    onTrack: (Int) -> Unit,
) {
    val continuous = status.focusMode == CameraCommands.FOCUS_CONTINUOUS
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FocusTab("AF-S", active = !continuous, enabled = enabled) { onContinuous(false) }
            FocusTab("AF-C", active = continuous, enabled = enabled) { onContinuous(true) }
        }
        AnimatedVisibility(
            visible = continuous,
            enter = fadeIn(tween(160)) + expandVertically(tween(160)),
            exit = fadeOut(tween(160)) + shrinkVertically(tween(160)),
        ) {
            Row(
                Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                val selected = if (status.focusTrack < 0) FocusTrackMode.DEFAULT.raw else status.focusTrack
                FocusTrackMode.entries.forEach { track ->
                    val on = selected == track.raw
                    Text(
                        track.label,
                        style = LiveType.ui(13f, FontWeight.Bold).copy(letterSpacing = 0.3.sp),
                        color = if (on) LiveDesign.accent else LiveDesign.muted,
                        maxLines = 1,
                        softWrap = false,
                        modifier =
                            Modifier.clip(FocusTrackCapsule)
                                .background(
                                    if (on) LiveDesign.accentDim else LiveDesign.background.copy(alpha = 0.28f),
                                )
                                .border(
                                    1.5.dp,
                                    if (on) LiveDesign.accent else LiveDesign.hairline,
                                    FocusTrackCapsule,
                                )
                                .chromeClickable(enabled = enabled, onClick = { onTrack(track.raw) })
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun RowScope.FocusTab(title: String, active: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Text(
        title.uppercase(),
        style = LiveType.ui(13f, FontWeight.Bold).copy(letterSpacing = 0.5.sp),
        color = if (active) LiveDesign.accent else LiveDesign.muted,
        textAlign = TextAlign.Center,
        modifier =
            Modifier.weight(1f)
                .clip(ChromeShape)
                .background(if (active) LiveDesign.accentDim else LiveDesign.background.copy(alpha = 0.28f))
                .border(1.5.dp, if (active) LiveDesign.accent else LiveDesign.hairline, ChromeShape)
                .chromeClickable(enabled = enabled, onClick = onClick)
                .padding(vertical = 12.dp)
                .fillMaxWidth(),
    )
}

@Composable
private fun AudioBody(status: CameraStatus, enabled: Boolean, selectedMode: Int, model: AppModel) {
    when (selectedMode) {
        0 ->
            CheckedRows(
                options = listOf("Stereo", "Mono", "Spatial"),
                selected =
                    when (status.audioChannel) {
                        CameraCommands.AUDIO_STEREO -> "Stereo"
                        CameraCommands.AUDIO_MONO -> "Mono"
                        CameraCommands.AUDIO_SPATIAL -> "Spatial"
                        else -> null
                    },
                enabled = enabled,
            ) { label ->
                val value =
                    when (label) {
                        "Mono" -> CameraCommands.AUDIO_MONO
                        "Spatial" -> CameraCommands.AUDIO_SPATIAL
                        else -> CameraCommands.AUDIO_STEREO
                    }
                model.setAudioChannel(value)
            }
        1 ->
            CheckedRows(
                options = listOf("Off", "On"),
                selected =
                    when (status.windNr) {
                        1 -> "On"
                        0 -> "Off"
                        else -> null
                    },
                enabled = enabled,
            ) { label -> model.setWindNr(label == "On") }
        2 ->
            CheckedRows(
                options = listOf("All", "Front", "Front+back"),
                selected =
                    when (status.directionalAudio) {
                        0 -> "All"
                        1 -> "Front"
                        2 -> "Front+back"
                        else -> null
                    },
                enabled = enabled,
            ) { label ->
                val mode =
                    when (label) {
                        "Front" -> 1
                        "Front+back" -> 2
                        else -> 0
                    }
                model.setDirectionalAudio(mode)
            }
        else ->
            CheckedRows(
                options = listOf("Off", "On"),
                selected =
                    when (status.vocalBoost) {
                        1 -> "On"
                        0 -> "Off"
                        else -> null
                    },
                enabled = enabled,
            ) { label -> model.setVocalBoost(label == "On") }
    }
}

@Composable
private fun TintPad(
    tint: Float,
    enabled: Boolean,
    onTint: (Float) -> Unit,
    onCommit: (Float) -> Unit,
) {
    val rounded = tint.roundToInt()
    val label =
        when {
            rounded == 0 -> "Neutral"
            rounded > 0 -> "+$rounded"
            else -> "$rounded"
        }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            label,
            style = LiveType.ui(17f, FontWeight.SemiBold),
            color = if (rounded == 0) LiveDesign.muted else LiveDesign.accent,
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "−10",
                style = LiveType.ui(14f, FontWeight.Bold),
                color = LiveDesign.accent,
                modifier =
                    Modifier.width(56.dp)
                        .height(40.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(LiveDesign.accentDim)
                        .chromeClickable(
                            enabled = enabled,
                            onClick = {
                                val next = (tint - 10f).coerceIn(-100f, 100f)
                                onTint(next)
                                onCommit(next)
                            },
                        )
                        .padding(vertical = 10.dp),
                textAlign = TextAlign.Center,
            )
            TintGlassSlider(
                tint = tint,
                enabled = enabled,
                onTint = onTint,
                onCommit = onCommit,
                modifier = Modifier.weight(1f),
            )
            Text(
                "+10",
                style = LiveType.ui(14f, FontWeight.Bold),
                color = LiveDesign.accent,
                modifier =
                    Modifier.width(56.dp)
                        .height(40.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(LiveDesign.accentDim)
                        .chromeClickable(
                            enabled = enabled,
                            onClick = {
                                val next = (tint + 10f).coerceIn(-100f, 100f)
                                onTint(next)
                                onCommit(next)
                            },
                        )
                        .padding(vertical = 10.dp),
                textAlign = TextAlign.Center,
            )
        }
        Text(
            "Apply tint $rounded",
            style = LiveType.ui(13f, FontWeight.SemiBold),
            color = LiveDesign.accent,
            modifier = Modifier.chromeClickable(enabled = enabled, onClick = { onCommit(tint) }).padding(vertical = 4.dp),
        )
    }
}

@Composable
private fun TintGlassSlider(
    tint: Float,
    enabled: Boolean,
    onTint: (Float) -> Unit,
    onCommit: (Float) -> Unit,
    modifier: Modifier = Modifier,
) {
    val monitorGlass = LocalMonitorGlass.current
    val useLiquidGlass = enabled && monitorGlass?.tier == GlassTier.FULL
    val localBackdrop = rememberLayerBackdrop()
    val sceneBackdrop = monitorGlass?.overlayBackdrop ?: monitorGlass?.layerBackdrop
    val latestTint by rememberUpdatedState(tint)
    val latestOnTint by rememberUpdatedState(onTint)
    val latestOnCommit by rememberUpdatedState(onCommit)
    Box(
        modifier
            .height(40.dp)
            .alpha(if (enabled) 1f else 0.45f)
            .then(if (useLiquidGlass && sceneBackdrop == null) Modifier.layerBackdrop(localBackdrop) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        LiquidSlider(
            value = { latestTint },
            onValueChange = { next -> latestOnTint(next.coerceIn(-100f, 100f)) },
            onValueChangeFinished = { latestOnCommit(latestTint) },
            valueRange = -100f..100f,
            visibilityThreshold = 1f,
            backdrop = sceneBackdrop ?: localBackdrop,
            accentColor = LiveDesign.accent,
            useLiquidGlass = useLiquidGlass,
        )
    }
}

@Composable
private fun PrefToggle(
    title: String,
    help: String,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    var showingHelp by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                title.uppercase(),
                style = LiveType.ui(13f, FontWeight.Bold).copy(letterSpacing = 0.4.sp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            Box(
                Modifier.size(16.dp)
                    .clip(CircleShape)
                    .background(LiveDesign.background.copy(alpha = 0.5f))
                    .border(1.dp, LiveDesign.hairline, CircleShape)
                    .chromeClickable(onClick = { showingHelp = !showingHelp }),
                contentAlignment = Alignment.Center,
            ) {
                Text("?", color = LiveDesign.faint, fontSize = 8.sp, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.weight(1f))
            Box(
                Modifier
                    .chromeClickable(enabled = enabled, onClick = { onCheckedChange(!checked) })
                    .semantics { role = Role.Switch }
                    .alpha(if (enabled) 1f else 0.45f),
            ) {
                CaptureSwitchGraphic(checked)
            }
        }
        if (showingHelp) {
            Text(help, style = LiveType.ui(12f), color = LiveDesign.muted)
        }
    }
}

@Composable
private fun CaptureSwitchGraphic(isOn: Boolean) {
    Box(
        Modifier
            .width(39.dp)
            .height(22.dp)
            .clip(RoundedCornerShape(50))
            .background(if (isOn) LiveDesign.accentDim else LiveDesign.surface)
            .border(1.dp, if (isOn) LiveDesign.accentDim else LiveDesign.hairline, RoundedCornerShape(50)),
    ) {
        Box(
            Modifier
                .align(if (isOn) Alignment.CenterEnd else Alignment.CenterStart)
                .padding(3.5.dp)
                .size(15.dp)
                .clip(CircleShape)
                .background(if (isOn) LiveDesign.accent else LiveDesign.muted),
        )
    }
}

/** Sentinel until the lazy list measures — never treat row 0 as settled pre-layout. */
private const val DRUM_NOT_LAID_OUT = -1

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CaptureDrumWheel(
    options: List<String>,
    selection: String,
    markedValues: Set<String> = emptySet(),
    interactive: Boolean = true,
    onSelect: (String) -> Unit,
) {
    if (options.isEmpty()) return
    val rowHeight = 52.dp
    val wheelHeight = 176.dp
    val optionKey = options.joinToString()
    val selectedIndex = options.indexOf(selection).coerceAtLeast(0)
    val listState = remember(optionKey) { LazyListState(firstVisibleItemIndex = selectedIndex) }
    val snap =
        rememberSnapFlingBehavior(
            lazyListState = listState,
            snapPosition = SnapPosition.Center,
        )
    val haptics = LocalOperatorHaptics.current
    val centeredIndex by remember(listState) {
        derivedStateOf {
            val layout = listState.layoutInfo
            val center = (layout.viewportStartOffset + layout.viewportEndOffset) / 2
            layout.visibleItemsInfo
                .minByOrNull { abs(it.offset + it.size / 2 - center) }
                ?.index ?: DRUM_NOT_LAID_OUT
        }
    }
    LaunchedEffect(options, selection) {
        val index = options.indexOf(selection).coerceAtLeast(0)
        if (listState.isScrollInProgress) return@LaunchedEffect
        if (centeredIndex == index) return@LaunchedEffect
        listState.scrollToItem(index)
    }
    LaunchedEffect(listState, options, interactive) {
        snapshotFlow { listState.isScrollInProgress to centeredIndex }
            .collect { (scrolling, index) ->
                if (scrolling || !interactive) return@collect
                val value = options.getOrNull(index) ?: return@collect
                if (value != selection) {
                    haptics.selection()
                    onSelect(value)
                }
            }
    }
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .heightIn(min = rowHeight * 3, max = wheelHeight)
            .height(wheelHeight)
            .alpha(if (interactive) 1f else 0.55f),
        contentAlignment = Alignment.Center,
    ) {
        val actualHeight = maxHeight
        val edgePadding = ((actualHeight - rowHeight) / 2).coerceAtLeast(0.dp)
        LazyColumn(
            state = listState,
            userScrollEnabled = interactive,
            flingBehavior = snap,
            contentPadding = PaddingValues(vertical = edgePadding),
            modifier =
                Modifier.fillMaxWidth()
                    .height(actualHeight)
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        val fade = size.height * 0.22f
                        drawRect(
                            Brush.verticalGradient(
                                0f to Color.Transparent,
                                1f to Color.Black,
                                endY = fade,
                            ),
                            size = Size(size.width, fade),
                            blendMode = BlendMode.DstIn,
                        )
                        drawRect(
                            Brush.verticalGradient(
                                0f to Color.Black,
                                1f to Color.Transparent,
                                startY = size.height - fade,
                                endY = size.height,
                            ),
                            topLeft = Offset(0f, size.height - fade),
                            size = Size(size.width, fade),
                            blendMode = BlendMode.DstIn,
                        )
                    },
        ) {
            items(options.size, key = { options[it] }) { index ->
                val option = options[index]
                val centered = index == centeredIndex
                Row(
                    Modifier.fillMaxWidth()
                        .height(rowHeight)
                        .chromeClickable(enabled = interactive, onClick = { onSelect(option) }),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        option,
                        style =
                            LiveType.mono(
                                if (centered) 30f else 23f,
                                if (centered) FontWeight.SemiBold else FontWeight.Normal,
                            ),
                        color = if (centered) LiveDesign.accent else LiveDesign.muted.copy(alpha = 0.7f),
                        maxLines = 1,
                    )
                    if (option in markedValues) {
                        Text(
                            " ★",
                            style = LiveType.mono(if (centered) 13f else 10f, FontWeight.SemiBold),
                            color = if (centered) LiveDesign.accent else LiveDesign.muted.copy(alpha = 0.7f),
                        )
                    }
                }
            }
        }
        Box(
            Modifier.fillMaxWidth().height(1.dp).offset(y = -rowHeight / 2)
                .background(LiveDesign.hairlineStrong),
        )
        Box(
            Modifier.fillMaxWidth().height(1.dp).offset(y = rowHeight / 2)
                .background(LiveDesign.hairlineStrong),
        )
    }
}

private fun initialSelectedMode(
    sheet: LiveSheet,
    status: CameraStatus,
    model: AppModel,
    isEvSheet: Boolean,
): Int =
    when (sheet) {
        LiveSheet.ISO ->
            if (CaptureLists.offersIsoAuto(status) && status.isoIndex != 0) 1 else 0
        LiveSheet.SHUTTER -> if (!isEvSheet && model.shutterUsesAngle) 1 else 0
        LiveSheet.WB -> if (status.wbMode == CameraCommands.WB_CUSTOM) 1 else 0
        LiveSheet.FORMAT -> if (status.resolutionCode == CameraCommands.RES_4K) 1 else 0
        else -> 0
    }

private fun modeTabs(sheet: LiveSheet, isEvSheet: Boolean, offersIsoAuto: Boolean): List<String> =
    when {
        sheet == LiveSheet.ISO && offersIsoAuto -> listOf("Auto", "Manual")
        sheet == LiveSheet.SHUTTER && !isEvSheet -> listOf("Speed", "Angle")
        sheet == LiveSheet.WB -> listOf("Mode", "Kelvin", "Tint")
        sheet == LiveSheet.AUDIO -> listOf("Channel", "Wind", "Dir", "Vocal")
        sheet == LiveSheet.FORMAT -> listOf("1080", "4K")
        else -> emptyList()
    }

private fun headerTitle(sheet: LiveSheet, isEvSheet: Boolean): String =
    if (isEvSheet) "EV" else sheet.headerLabel

private fun headerSubtitle(
    sheet: LiveSheet,
    isEvSheet: Boolean,
    isAngleSheet: Boolean,
    facePriority: Boolean,
): String =
    when {
        isEvSheet -> if (facePriority) "Face priority" else "Compensation"
        sheet == LiveSheet.SHUTTER -> if (isAngleSheet) "Angle" else "Speed"
        else -> sheet.subtitle
    }

val LiveSheet.headerLabel: String
    get() =
        when (this) {
            LiveSheet.ISO -> "ISO"
            LiveSheet.SHUTTER -> "SHUTTER"
            LiveSheet.WB -> "WB"
            LiveSheet.FOCUS -> "FOCUS"
            LiveSheet.EXPO -> "MODE"
            LiveSheet.AUDIO -> "AUDIO"
            LiveSheet.COLOR -> "COLOR"
            LiveSheet.FORMAT -> "RESOLUTION"
        }

val LiveSheet.subtitle: String
    get() =
        when (this) {
            LiveSheet.ISO -> "Sensitivity"
            LiveSheet.SHUTTER -> "Angle / speed"
            LiveSheet.WB -> "Kelvin / auto / tint"
            LiveSheet.FOCUS -> "AF-S / AF-C"
            LiveSheet.EXPO -> "Exposure"
            LiveSheet.AUDIO -> "Channel · wind · direction · vocal"
            LiveSheet.COLOR -> "Color mode"
            LiveSheet.FORMAT -> "Frame rate"
        }

/** Operator shutter-angle ladder. Body only accepts 1/N; convert locally. */
object ShutterAngle {
    val degrees: List<Double> =
        listOf(5.6, 11.2, 22.5, 45.0, 72.0, 86.4, 90.0, 108.0, 144.0, 172.0, 180.0, 216.0, 288.0, 346.0, 360.0)
    const val DEFAULT_DEGREES = 180.0
    val labels: List<String> = degrees.map { label(it) }

    fun effectiveFps(fps: Int): Int = if (fps in 8..240) fps else 24

    fun label(value: Double): String {
        val rounded = round(value)
        return if (abs(value - rounded) < 0.05) {
            "${rounded.toInt()}°"
        } else {
            String.format(Locale.US, "%.1f°", value)
        }
    }

    fun parse(label: String): Double? {
        val trimmed = label.replace("°", "").trim()
        val value = trimmed.toDoubleOrNull() ?: return null
        if (value <= 0.0 || value > 360.0) return null
        return value
    }

    fun denom(degrees: Double, fps: Int): Int {
        val angle = degrees.coerceAtLeast(0.1)
        val rate = effectiveFps(fps).toDouble()
        val raw = round(360.0 * rate / angle).toInt()
        return raw.coerceIn(1, 16_000)
    }

    fun denom(degrees: Double, fps: Int, available: List<Int>): Int {
        val ideal = denom(degrees, fps)
        return CaptureLists.nearestDenom(ideal, available) ?: ideal
    }

    fun degrees(denom: Int, fps: Int): Double {
        if (denom <= 0) return DEFAULT_DEGREES
        return 360.0 * effectiveFps(fps).toDouble() / denom.toDouble()
    }

    fun nearestDegrees(value: Double): Double =
        degrees.minByOrNull { abs(it - value) } ?: DEFAULT_DEGREES

    fun nearestLabel(denom: Int, fps: Int): String = label(nearestDegrees(degrees(denom, fps)))
}

data class EvComp(val thirds: Int) {
    val rawValue: Int get() = 0x10 + thirds

    val label: String
        get() {
            if (thirds == 0) return "0.0"
            val sign = if (thirds > 0) "+" else MINUS
            val absThirds = abs(thirds)
            val frac = listOf(".0", ".3", ".7")[absThirds % 3]
            return "$sign${absThirds / 3}$frac"
        }

    companion object {
        const val MINUS = "\u2212"
        val allCases: List<EvComp> = (-9..9).map { EvComp(it) }

        fun fromRaw(raw: Int): EvComp? {
            val t = raw - 0x10
            return if (t in -9..9) EvComp(t) else null
        }

        fun fromLabel(label: String): EvComp? {
            if (label == "0.0") return EvComp(0)
            val negative = label.startsWith(MINUS) || label.startsWith("-")
            val positive = label.startsWith("+")
            if (!negative && !positive) return null
            val body = label.drop(1)
            val parts = body.split('.', limit = 2)
            if (parts.size != 2) return null
            val whole = parts[0].toIntOrNull() ?: return null
            val frac = parts[1].toIntOrNull() ?: return null
            val fracThirds =
                when (frac) {
                    0 -> 0
                    3 -> 1
                    7 -> 2
                    else -> return null
                }
            val t = whole * 3 + fracThirds
            if (t !in 0..9) return null
            return EvComp(if (negative) -t else t)
        }
    }
}

enum class IsoLimit(val rawValue: Int) {
    Max200(0x02),
    Max400(0x03),
    Max800(0x04),
    Max1600(0x05),
    Max3200(0x06),
    Max6400(0x07),
    Max12800(0x08),
    Max25600(0x09),
    ;

    val ceiling: Int get() = 100 shl (rawValue - 1)

    fun label(base: Int): String = "$base\u2013$ceiling"
}

object CaptureLists {
    const val FACE_PRIORITY_TITLE = "Face Priority"
    const val FACE_PRIORITY_HELP =
        "On: EV follows faces to middle gray. Several faces use the median. First couple of seconds after a face appears are faster, then about 1 s. Off: put EV back to what it was, or 0.0."
    const val NATIVE_ISO_HOP_TITLE = "Auto Native ISO"
    const val NATIVE_ISO_HOP_HELP =
        "On: switching D-Log ↔ D-Log2 hops ISO to that curve's starred native if you were still on native. Off: keep the ISO you set."

    val evLabels: List<String> = EvComp.allCases.map { it.label }

    val kelvinValues: List<Int> = (2_000..10_000 step 100).toList()
    val kelvinLabels: List<String> = kelvinValues.map { "${it}K" }

    val fpsDrumLabels: List<String> = listOf("24p", "25p", "30p", "48p", "50p", "60p")

    val shootingModeLabels: List<String> =
        listOf("SlowMo", "Video", "TimeLapse", "Photo", "HyperLapse", "SuperNight")

    val colorWheel: List<Pair<Int, String>> =
        listOf(
            CameraCommands.COLOR_NORMAL to "Normal",
            CameraCommands.COLOR_HDR to "HDR",
            CameraCommands.COLOR_DLOG to "D-Log",
            CameraCommands.COLOR_DLOG2 to "D-Log2",
        )

    fun shutterDenoms(status: CameraStatus): List<Int> =
        CameraCommands.shutterWheelDenoms(status.availableShutterDenoms, status.shutterDenom)

    fun shutterLabel(denom: Int): String = "1/$denom"

    fun shutterLabels(status: CameraStatus): List<String> = shutterDenoms(status).map(::shutterLabel)

    fun denomFromLabel(label: String): Int? = label.removePrefix("1/").toIntOrNull()

    fun nearestDenom(current: Int, denoms: List<Int>): Int? =
        denoms.minByOrNull { abs(it - current) }

    fun nearestShutterLabel(label: String, status: CameraStatus): String {
        val denoms = shutterDenoms(status)
        val denom = denomFromLabel(label)
        val near = if (denom != null) nearestDenom(denom, denoms) else denoms.firstOrNull()
        return if (near != null) shutterLabel(near) else denoms.firstOrNull()?.let(::shutterLabel).orEmpty()
    }

    fun isoFallback(colorMode: Int): List<Int> = CameraCommands.isoChoices(colorMode).map { it.first }

    fun isoIndices(status: CameraStatus): List<Int> {
        val available = status.availableIsoIndices
        return if (available.isNotEmpty()) available else isoFallback(status.colorMode)
    }

    fun isoDrumLabels(status: CameraStatus): List<String> =
        isoIndices(status)
            .filter { it != 0 }
            .map { CameraCommands.isoLabel(it) }
            .filter { it != "—" }

    fun isoIndexFromLabel(label: String): Int? =
        listOf(0x00, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B)
            .firstOrNull { CameraCommands.isoLabel(it) == label }

    fun offersIsoAuto(status: CameraStatus): Boolean = status.colorMode != CameraCommands.COLOR_DLOG2

    fun isoAutoBase(colorMode: Int): Int? =
        when (colorMode) {
            CameraCommands.COLOR_DLOG2 -> null
            CameraCommands.COLOR_DLOG -> 400
            else -> 100
        }

    fun isoAutoLimits(colorMode: Int): List<IsoLimit> =
        when (colorMode) {
            CameraCommands.COLOR_DLOG2 -> emptyList()
            CameraCommands.COLOR_DLOG ->
                listOf(IsoLimit.Max800, IsoLimit.Max1600, IsoLimit.Max3200, IsoLimit.Max6400)
            else ->
                listOf(
                    IsoLimit.Max200,
                    IsoLimit.Max400,
                    IsoLimit.Max800,
                    IsoLimit.Max1600,
                    IsoLimit.Max3200,
                    IsoLimit.Max6400,
                    IsoLimit.Max12800,
                    IsoLimit.Max25600,
                )
        }

    fun isoAutoLabels(status: CameraStatus): List<String> {
        val base = isoAutoBase(status.colorMode) ?: return emptyList()
        return isoAutoLimits(status.colorMode).map { it.label(base) }
    }

    fun isoAutoLabel(status: CameraStatus): String {
        val base = isoAutoBase(status.colorMode) ?: return ""
        val limit = IsoLimit.entries.firstOrNull { it.rawValue == status.isoLimit } ?: return ""
        return limit.label(base)
    }

    fun isoLimit(fromLabel: String, status: CameraStatus): IsoLimit? {
        val base = isoAutoBase(status.colorMode) ?: return null
        return isoAutoLimits(status.colorMode).firstOrNull { it.label(base) == fromLabel }
    }

    fun isoMarkedLabels(status: CameraStatus): Set<String> {
        val base = CameraCommands.baseIsoLabel(status.colorMode) ?: return emptySet()
        return setOf(base)
    }

    fun currentKelvin(status: CameraStatus): Int {
        val k = status.wbKelvin
        return if (k in 2_000..10_000) k else 5_600
    }

    fun currentTint(status: CameraStatus): Int = status.wbTint.coerceIn(-100, 100)

    fun kelvinFromLabel(label: String): Int? = label.removeSuffix("K").toIntOrNull()

    fun fpsDrumLabel(status: CameraStatus): String {
        val fps =
            when {
                status.fps > 0 -> status.fps
                else -> CameraCommands.fpsFromIndex(status.fpsIndex)
            } ?: 24
        val label = "${fps}p"
        return if (label in fpsDrumLabels) label else "24p"
    }

    fun fpsIndexFromDrum(label: String): Int? {
        val fps = label.removeSuffix("p").toIntOrNull() ?: return null
        return CameraCommands.fpsIndex(fps)
    }

    fun currentFpsIndex(status: CameraStatus): Int =
        when {
            status.fpsIndex > 0 -> status.fpsIndex
            else -> CameraCommands.fpsIndex(status.fps) ?: 1
        }

    fun colorWheelLabels(@Suppress("UNUSED_PARAMETER") status: CameraStatus): List<String> =
        colorWheel.map { it.second }

    fun colorModeFromLabel(label: String): Int? = colorWheel.firstOrNull { it.second == label }?.first

    fun shootingModeLabel(code: Int): String? =
        when (code) {
            0x00 -> "SlowMo"
            0x01 -> "Video"
            0x02 -> "TimeLapse"
            0x05, 0x17 -> "Photo"
            0x0A -> "HyperLapse"
            0x28 -> "SuperNight"
            else -> null
        }

    fun shootingModeRaw(label: String): Int? =
        when (label) {
            "SlowMo" -> 0x00
            "Video" -> 0x01
            "TimeLapse" -> 0x02
            "Photo" -> 0x05
            "HyperLapse" -> 0x0A
            "SuperNight" -> 0x28
            else -> null
        }

    /** Nano / Atto have no AF-S / AF-C. Unknown name defaults to Pocket (supported). */
    fun supportsFocusMode(modelName: String?): Boolean {
        val n = (modelName ?: "").lowercase().replace(" ", "")
        if (n.isEmpty()) return true
        return !n.contains("nano") && !n.contains("atto")
    }
}
