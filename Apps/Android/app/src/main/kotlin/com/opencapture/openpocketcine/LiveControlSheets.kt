package com.opencapture.openpocketcine

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
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
import com.opencapture.openpocketcine.assists.AssistLongPress
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.settings.SettingsHelpBadge
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.FocusTrackMode
import com.opencapture.openpocketcine.session.VideoFormat
import com.opencapture.openpocketcine.session.VideoFrameRate
import com.opencapture.openpocketcine.session.VideoResolution
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
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
    /** Capture-bar MODE: expo Auto/Manual. Not shooting Video/Photo. */
    EXPO,
    AUDIO,
    COLOR,
    FORMAT,
}

val LiveSheet.isTopPicker: Boolean
    get() = this == LiveSheet.FORMAT || this == LiveSheet.COLOR

@Composable
fun LiveControlSheet(
    sheet: LiveSheet,
    model: AppModel,
    status: CameraStatus,
    locked: Boolean,
    onDismiss: () -> Unit,
    maxHeightDp: Float? = null,
) {
    val context = LocalContext.current
    val enabled = !locked
    val isEvSheet = CaptureLists.isEvSheet(sheet, status.expoMode)
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
    val isAngleSheet = CaptureLists.isAngleSheet(sheet, status.expoMode, selectedMode)
    val tabs = CaptureLists.modeTabs(sheet, status, offersIsoAuto)
    val bodyFamily = model.session.connectedCamera?.model?.family ?: "pocket"
    val bodyName = model.session.connectedCamera?.model?.name ?: ""

    fun enqueueDrumSend(send: () -> Unit) {
        if (!enabled) return
        drumJob?.cancel()
        drumJob = scope.launch {
            delay(80)
            send()
        }
    }

    fun applyIsoSeat(state: IsoSheetLogic.State) {
        selectedMode = state.selectedMode
        lastApplied = state.lastApplied
        drumSelection = state.drumSelection
    }

    fun reseatIso() {
        applyIsoSeat(IsoSheetLogic.reseat(status))
    }

    fun applySeat(seat: CaptureLists.ShutterSeat) {
        preferredAngle = seat.preferredAngle
        if (seat.persistAngle) {
            OperatorPrefs.setShutterAngleDegrees(context, seat.preferredAngle)
        }
        lastApplied = seat.selection
        drumSelection = seat.selection
    }

    fun reseatEv() {
        applySeat(CaptureLists.reseatEv(status))
    }

    fun reseatShutterAngle() {
        applySeat(CaptureLists.reseatShutterAngle(status, preferredAngle))
    }

    fun reseatShutter() {
        applySeat(CaptureLists.reseatShutter(status, selectedMode, isEvSheet, preferredAngle))
    }

    fun reseatShutterOrEv() {
        if (isEvSheet) reseatEv() else reseatShutter()
    }

    fun reseatWb() {
        drumSelection = CaptureLists.wbDrumSelection(status)
        lastApplied = drumSelection
        tintDraft = CaptureLists.currentTint(status).toFloat()
    }

    fun reseatResolution() {
        val format = VideoFormat.current(status)
        val tabs = CaptureLists.formatResolutions(status)
        selectedMode = tabs.indexOf(format.resolution).coerceAtLeast(0)
        val label = format.frameRate.drumLabel
        drumSelection = label
        lastApplied = label
    }

    fun reseatColor() {
        val labels = CaptureLists.colorWheelLabels(status, bodyFamily, bodyName)
        val live = CameraCommands.colorLabel(status.colorMode, bodyFamily)
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
                selectedMode = CaptureLists.wbInitialTab(status)
                reseatWb()
            }
            LiveSheet.AUDIO -> selectedMode = CaptureLists.audioInitialTab()
            LiveSheet.FORMAT -> reseatResolution()
            LiveSheet.COLOR -> reseatColor()
            else -> selectedMode = 0
        }
    }

    fun applyVideoFormat(tab: Int, drum: String, fromDrum: Boolean) {
        val next = CaptureLists.nextVideoFormat(status, tab, drum, fromDrum) ?: return
        model.setVideoFormat(next)
    }

    fun handleModeChange(index: Int) {
        if (!enabled) return
        when {
            sheet == LiveSheet.ISO && offersIsoAuto -> {
                val (state, cmd) = IsoSheetLogic.handleModeChange(index, status)
                applyIsoSeat(state)
                when (cmd) {
                    is IsoSheetLogic.Command.SetIndex -> model.setIsoIndex(cmd.index)
                    is IsoSheetLogic.Command.SetLimit -> model.setIsoLimit(cmd.raw)
                    null -> Unit
                }
            }
            sheet == LiveSheet.SHUTTER && !isEvSheet -> {
                model.updateShutterUsesAngle(index == 1)
                // Tab change reseats after selectedMode is written by the caller.
            }
            sheet == LiveSheet.WB -> Unit
            sheet == LiveSheet.FORMAT -> applyVideoFormat(index, drumSelection, fromDrum = false)
        }
    }

    fun applyDrum(value: String) {
        if (!enabled || value.isEmpty() || value == lastApplied) return
        if (sheet == LiveSheet.COLOR && status.isRecording) {
            CaptureLists.applyColorDrum(
                label = value,
                family = bodyFamily,
                status = status,
                hopEnabled = model.nativeISOHopEnabled,
                name = bodyName,
            )?.let { model.setColorMode(it.colorMode) }
            return
        }
        lastApplied = value
        when (sheet) {
            LiveSheet.ISO -> {
                when (val cmd = IsoSheetLogic.applyDrum(value, status, selectedMode)) {
                    is IsoSheetLogic.Command.SetLimit ->
                        enqueueDrumSend { model.setIsoLimit(cmd.raw) }
                    is IsoSheetLogic.Command.SetIndex ->
                        enqueueDrumSend { model.setIsoIndex(cmd.index) }
                    null -> return
                }
            }
            LiveSheet.SHUTTER -> {
                when (
                    val cmd =
                        CaptureLists.applyShutterDrum(
                            value = value,
                            isEvSheet = isEvSheet,
                            isAngleSheet = isAngleSheet,
                            facePriority = model.facePriorityExposureEnabled,
                            status = status,
                        )
                ) {
                    is CaptureLists.ShutterDrumCommand.SetEv ->
                        enqueueDrumSend { model.setEv(cmd.thirds) }
                    is CaptureLists.ShutterDrumCommand.SetShutter ->
                        enqueueDrumSend { model.setShutterDenom(cmd.denom) }
                    is CaptureLists.ShutterDrumCommand.SetAngle -> {
                        preferredAngle = cmd.degrees
                        OperatorPrefs.setShutterAngleDegrees(context, cmd.degrees)
                        enqueueDrumSend { model.setShutterDenom(cmd.denom) }
                    }
                    CaptureLists.ShutterDrumCommand.Ignored -> Unit
                }
            }
            LiveSheet.WB -> {
                val custom = CaptureLists.wbKelvinDrumApply(selectedMode, value, status) ?: return
                model.setWhiteBalance(custom.first, custom.second)
            }
            LiveSheet.FORMAT -> {
                enqueueDrumSend { applyVideoFormat(selectedMode, value, fromDrum = true) }
            }
            LiveSheet.COLOR -> {
                val command =
                    CaptureLists.applyColorDrum(
                        label = value,
                        family = bodyFamily,
                        status = status,
                        hopEnabled = model.nativeISOHopEnabled,
                        name = bodyName,
                    ) ?: return
                // Session.setColorMode hops native ISO — same as iOS CameraSession.
                enqueueDrumSend { model.setColorMode(command.colorMode) }
            }
            else -> Unit
        }
    }

    LaunchedEffect(sheet) {
        if (CaptureLists.shouldRefreshAudio(sheet)) model.refreshAudio()
        if (sheet == LiveSheet.FOCUS &&
            CaptureLists.shouldRefreshFocusTrack(
                status,
                CaptureLists.supportsFocusModeOrDefault(model.session.connectedCamera?.model),
            )
        ) {
            model.refreshFocusTrack()
        }
        drumJob?.cancel()
        seed()
        if (sheet == LiveSheet.ISO && CaptureLists.shouldGetIsoLimit(status)) {
            model.refreshIsoLimitNow()
            reseatIso()
        }
    }
    // Match iOS CaptureControlSheets onChange keys. Do not reseat ISO/shutter drums
    // on every live isoIndex / shutterDenom tick — that snaps Manual back to Auto
    // and parks the wheel on the first option.
    LaunchedEffect(sheet, status.availableIsoIndices, status.colorMode) {
        if (sheet == LiveSheet.ISO) reseatIso()
    }
    LaunchedEffect(sheet, status.availableShutterDenoms, status.fps) {
        if (sheet == LiveSheet.SHUTTER && !isEvSheet) reseatShutter()
    }
    LaunchedEffect(sheet, status.expoMode) {
        if (sheet == LiveSheet.SHUTTER) {
            drumJob?.cancel()
            CaptureLists.shutterTabAfterExpoChange(status.expoMode, model.shutterUsesAngle)?.let {
                selectedMode = it
            }
            reseatShutterOrEv()
        }
    }
    LaunchedEffect(sheet, status.evComp, model.facePriorityExposureEnabled) {
        if (sheet == LiveSheet.SHUTTER && isEvSheet) reseatEv()
    }
    LaunchedEffect(sheet, status.resolutionCode, status.fpsIndex, status.availableVideoFormats) {
        if (sheet == LiveSheet.FORMAT) reseatResolution()
    }
    LaunchedEffect(sheet, status.colorMode) {
        if (sheet == LiveSheet.COLOR) reseatColor()
    }
    DisposableEffect(sheet) { onDispose { drumJob?.cancel() } }

    val cap = maxHeightDp?.dp
    // Bottom drums fill the well. FORMAT / COLOR hang under the top chip and hug,
    // matching iOS `LiveTopPickerHost` (not a floor-to-chip sheet).
    val fillsWell =
        sheet == LiveSheet.ISO ||
            sheet == LiveSheet.SHUTTER ||
            sheet == LiveSheet.WB
    Column(
        Modifier
            .fillMaxWidth()
            .then(
                when {
                    fillsWell && cap != null -> Modifier.height(cap)
                    else ->
                        Modifier.wrapContentHeight(align = Alignment.Top)
                            .then(if (cap != null) Modifier.heightIn(max = cap) else Modifier)
                },
            )
            .pickerPanelGlass(ChromeShape)
            .pointerInput(Unit) { detectTapGestures(onTap = {}) }
            .padding(AssistLongPress.PANEL_PAD_DP.dp),
        verticalArrangement = Arrangement.spacedBy(AssistLongPress.PANEL_GAP_DP.dp),
    ) {
            SheetHeader(
                title = CaptureLists.headerTitle(sheet, status.expoMode),
                subtitle =
                    CaptureLists.headerSubtitle(
                        sheet,
                        status.expoMode,
                        selectedMode,
                        model.facePriorityExposureEnabled,
                    ),
                onClose = onDismiss,
            )
            when (sheet) {
                LiveSheet.ISO -> {
                    Column(
                        Modifier.weight(1f, fill = fillsWell),
                        verticalArrangement = Arrangement.spacedBy(AssistLongPress.PANEL_GAP_DP.dp),
                    ) {
                        Box(Modifier.weight(1f, fill = true).fillMaxWidth()) {
                            if (isIsoAutoTab) {
                                CaptureDrumWheel(
                                    options = CaptureLists.isoAutoLabels(status),
                                    selection = drumSelection,
                                    interactive = enabled,
                                    fillHeight = true,
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
                                    fillHeight = true,
                                    onSelect = {
                                        drumSelection = it
                                        applyDrum(it)
                                    },
                                )
                            }
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
                    Column(
                        Modifier.weight(1f, fill = fillsWell),
                        verticalArrangement = Arrangement.spacedBy(AssistLongPress.PANEL_GAP_DP.dp),
                    ) {
                        Box(Modifier.weight(1f, fill = true).fillMaxWidth()) {
                            if (isEvSheet) {
                                CaptureDrumWheel(
                                    options = CaptureLists.evLabels,
                                    selection = drumSelection,
                                    interactive = enabled && !model.facePriorityExposureEnabled,
                                    fillHeight = true,
                                    onSelect = {
                                        drumSelection = it
                                        applyDrum(it)
                                    },
                                )
                            } else if (isAngleSheet) {
                                CaptureDrumWheel(
                                    options = ShutterAngle.labels,
                                    selection = drumSelection,
                                    interactive = enabled,
                                    fillHeight = true,
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
                                    fillHeight = true,
                                    onSelect = {
                                        drumSelection = it
                                        applyDrum(it)
                                    },
                                )
                            }
                        }
                        if (isEvSheet) {
                            PrefToggle(
                                title = CaptureLists.FACE_PRIORITY_TITLE,
                                help = CaptureLists.FACE_PRIORITY_HELP,
                                checked = model.facePriorityExposureEnabled,
                                enabled = enabled,
                                onCheckedChange = model::updateFacePriorityExposureEnabled,
                            )
                        }
                    }
                }
                LiveSheet.WB -> {
                    when (selectedMode) {
                        0 ->
                            CheckedRows(
                                options = CaptureLists.wbModeRows,
                                selected = CaptureLists.wbModeRowSelected(status),
                                enabled = enabled,
                            ) { label ->
                                if (CaptureLists.wbSendsAuto(label)) {
                                    model.setWhiteBalanceAuto()
                                } else {
                                    val custom = CaptureLists.wbCustomFromStatus(status)
                                    model.setWhiteBalance(custom.first, custom.second)
                                }
                            }
                        1 ->
                            Box(Modifier.weight(1f, fill = fillsWell).fillMaxWidth()) {
                                CaptureDrumWheel(
                                    options = CaptureLists.kelvinLabels,
                                    selection = drumSelection,
                                    interactive = enabled,
                                    fillHeight = true,
                                    onSelect = {
                                        drumSelection = it
                                        applyDrum(it)
                                    },
                                )
                            }
                        else -> {
                            LaunchedEffect(Unit) {
                                tintDraft = CaptureLists.currentTint(status).toFloat()
                            }
                            TintPad(
                                tint = tintDraft,
                                enabled = enabled,
                                onTint = { tintDraft = it },
                                onCommit = { value ->
                                    val tint = CaptureLists.roundedTint(value)
                                    tintDraft = tint.toFloat()
                                    if (CaptureLists.wbTintStaysAuto(status)) {
                                        model.setWhiteBalanceAuto(tint)
                                    } else {
                                        val custom = CaptureLists.wbCustomFromTint(value, status)
                                        model.setWhiteBalance(custom.first, custom.second)
                                    }
                                },
                            )
                        }
                    }
                }
                LiveSheet.FOCUS -> {
                    if (CaptureLists.supportsFocusModeOrDefault(model.session.connectedCamera?.model)) {
                        FocusBody(
                            status = status,
                            enabled = enabled,
                            onContinuous = model::setFocusMode,
                            onTrack = model::setFocusTrack,
                        )
                    }
                }
                LiveSheet.EXPO -> {
                    CheckedRows(
                        options = CaptureLists.expoLabels,
                        selected = CaptureLists.expoSelectedLabel(status.expoMode),
                        enabled = enabled,
                    ) { label ->
                        CaptureLists.expoModeFromLabel(label)?.let(model::setExpoMode)
                    }
                }
                LiveSheet.AUDIO -> AudioBody(status, enabled, selectedMode, model)
                LiveSheet.COLOR ->
                    CaptureDrumWheel(
                        options = CaptureLists.colorWheelLabels(status, bodyFamily, bodyName),
                        selection = drumSelection,
                        interactive = enabled,
                        maxHeightDp = CaptureLists.topPickerDrumHeight(maxHeightDp, hasTabs = false),
                        onSelect = {
                            drumSelection = it
                            applyDrum(it)
                        },
                    )
                LiveSheet.FORMAT ->
                    androidx.compose.runtime.key(selectedMode) {
                        CaptureDrumWheel(
                            options = CaptureLists.fpsDrumLabels(status, selectedMode),
                            selection = drumSelection,
                            interactive = enabled,
                            maxHeightDp = CaptureLists.topPickerDrumHeight(maxHeightDp, hasTabs = true),
                            onSelect = {
                                drumSelection = it
                                applyDrum(it)
                            },
                        )
                    }
            }
            if (tabs.isNotEmpty()) {
                ModeBar(
                    tabs = tabs,
                    selected = selectedMode,
                    enabled = enabled,
                ) { index ->
                    selectedMode = index
                    handleModeChange(index)
                    if (sheet == LiveSheet.SHUTTER && !isEvSheet) reseatShutter()
                }
            }
    }
}

/**
 * OpenZCine `PanelHost.topPickerBody` / `bottomPickerBody`: backdrop tap, 340dp
 * card under a top chip or 420-capped card parked 10dp above the capture bar.
 */
@Composable
fun LivePickerHost(
    sheet: LiveSheet,
    frames: Map<LiveSheet, ChromeRect>,
    bar: ChromeRect,
    topDeck: ChromeRect,
    viewportWidth: Float,
    viewportHeight: Float,
    safeLeading: Float,
    safeTrailing: Float,
    safeTop: Float,
    safeBottom: Float,
    ceilingY: Float,
    floorY: Float?,
    model: AppModel,
    status: CameraStatus,
    locked: Boolean,
    onSelect: (LiveSheet?) -> Unit,
) {
    val density = LocalDensity.current
    var panelHeight by remember(sheet) { mutableFloatStateOf(LiveChromeMetrics.DRUM_PICKER_HEIGHT) }
    val tile = frames[sheet] ?: ChromeRect(0f, 0f, 0f, 0f)
    // FORMAT / COLOR always hang under the top chip (iOS `LiveTopPickerHost`),
    // even when the capture bar is visible. Missing chip frames fall back to
    // the top deck — never a floor-to-bar capture sheet.
    val fromTop = sheet.isTopPicker
    val cell =
        when {
            fromTop && !tile.isEmpty -> tile
            fromTop ->
                ChromeRect(topDeck.midX - 40f, topDeck.minY, 80f, max(topDeck.height, 1f))
            else -> tile
        }
    val place =
        if (fromTop) {
            LivePopupPlacement.topPicker(
                cell = cell,
                panelHeight = panelHeight,
                viewportWidth = viewportWidth,
                viewportHeight = viewportHeight,
                safeLeading = safeLeading,
                safeTrailing = safeTrailing,
                safeTop = safeTop,
                safeBottom = safeBottom,
                floorY = floorY,
            )
        } else {
            LivePopupPlacement.capturePicker(
                tile = tile,
                bar = bar,
                panelHeight = panelHeight,
                viewportWidth = viewportWidth,
                viewportHeight = viewportHeight,
                safeLeading = safeLeading,
                safeTrailing = safeTrailing,
                safeTop = safeTop,
                safeBottom = safeBottom,
                ceilingY = ceilingY,
            )
        }
    var shown by remember(sheet) { mutableStateOf(false) }
    LaunchedEffect(sheet) { shown = true }
    val revealed by
        animateFloatAsState(
            if (shown) 1f else 0f,
            tween(200, easing = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)),
            label = "picker-reveal",
        )
    val slide = if (fromTop) place.y + panelHeight + 40f else place.maxHeight + 20f
    Box(
        Modifier
            .fillMaxWidth()
            .fillMaxHeight()
            .pointerInput(sheet, frames) {
                detectTapGestures { offset ->
                    val d = density.density
                    val x = offset.x / d
                    val y = offset.y / d
                    val hit =
                        frames.entries.firstOrNull { (_, rect) ->
                            rect.inset(-10f, -8f).contains(x, y)
                        }
                    when {
                        hit == null -> onSelect(null)
                        hit.key == sheet -> onSelect(null)
                        else -> onSelect(hit.key)
                    }
                }
            },
    ) {
        Box(
            Modifier
                .offset(place.x.dp, (place.y + (1f - revealed) * if (fromTop) -slide else slide).dp)
                .width(place.width.dp)
                .heightIn(max = place.maxHeight.dp)
                .graphicsLayer { alpha = revealed }
                .onSizeChanged { panelHeight = it.height / density.density },
        ) {
            androidx.compose.runtime.key(sheet) {
                LiveControlSheet(
                    sheet,
                    model,
                    status,
                    locked,
                    onDismiss = { onSelect(null) },
                    maxHeightDp = place.maxHeight,
                )
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
        LivePopupCloseButton(onClick = onClose, size = AssistLongPress.CLOSE_DP.dp)
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
    val continuous = CaptureLists.focusIsContinuous(status)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FocusTab(CaptureLists.FOCUS_TAB_SINGLE, active = !continuous, enabled = enabled) {
                onContinuous(false)
            }
            FocusTab(CaptureLists.FOCUS_TAB_CONTINUOUS, active = continuous, enabled = enabled) {
                onContinuous(true)
            }
        }
        AnimatedVisibility(
            visible = CaptureLists.focusShowsTrackChips(status),
            enter = fadeIn(tween(160)) + expandVertically(tween(160)),
            exit = fadeOut(tween(160)) + shrinkVertically(tween(160)),
        ) {
            Row(
                Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                val selected = CaptureLists.selectedFocusTrack(status)
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
                options = CaptureLists.audioChannelLabels,
                selected = CaptureLists.audioChannelLabel(status.audioChannel),
                enabled = enabled,
            ) { label ->
                CaptureLists.audioChannelValue(label)?.let(model::setAudioChannel)
            }
        1 ->
            CheckedRows(
                options = CaptureLists.audioWindLabels,
                selected = CaptureLists.audioWindLabel(status.windNr),
                enabled = enabled,
            ) { label -> model.setWindNr(label == "On") }
        2 ->
            CheckedRows(
                options = CaptureLists.audioDirLabels,
                selected = CaptureLists.audioDirLabel(status.directionalAudio),
                enabled = enabled,
            ) { label ->
                CaptureLists.audioDirValue(label)?.let(model::setDirectionalAudio)
            }
        else ->
            CheckedRows(
                options = CaptureLists.audioVocalLabels,
                selected = CaptureLists.audioVocalLabel(status.vocalBoost),
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
    val rounded = CaptureLists.roundedTint(tint)
    val label = CaptureLists.tintLabel(rounded)
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
                                val next = CaptureLists.nudgeTint(tint, -10)
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
                                val next = CaptureLists.nudgeTint(tint, 10)
                                onTint(next)
                                onCommit(next)
                            },
                        )
                        .padding(vertical = 10.dp),
                textAlign = TextAlign.Center,
            )
        }
        Text(
            CaptureLists.tintApplyLabel(rounded),
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
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            title.uppercase(),
            style = LiveType.ui(13f, FontWeight.Bold).copy(letterSpacing = 0.4.sp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        SettingsHelpBadge(help)
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
    fillHeight: Boolean = false,
    maxHeightDp: Float? = null,
    onSelect: (String) -> Unit,
) {
    if (options.isEmpty()) return
    val rowHeight = AssistLongPress.DRUM_ROW_DP.dp
    val wheelHeight =
        maxHeightDp?.dp?.coerceIn(rowHeight * 2, 176.dp) ?: 176.dp
    val optionKey = options.joinToString()
    val selectedIndex = options.indexOf(selection).coerceAtLeast(0)
    val listState = remember(optionKey) { LazyListState(firstVisibleItemIndex = selectedIndex) }
    var seated by remember(optionKey) { mutableStateOf(false) }
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
    LaunchedEffect(options, selection, optionKey) {
        seated = false
        val index = options.indexOf(selection)
        if (index >= 0) {
            listState.scrollToItem(index)
        }
    }
    LaunchedEffect(listState, options, interactive, selection) {
        snapshotFlow { listState.isScrollInProgress to centeredIndex }
            .collect { (scrolling, index) ->
                if (scrolling || !interactive || index == DRUM_NOT_LAID_OUT) return@collect
                val value = options.getOrNull(index) ?: return@collect
                if (value == selection) {
                    seated = true
                    return@collect
                }
                if (!seated) return@collect
                haptics.selection()
                onSelect(value)
            }
    }
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .then(
                if (fillHeight) Modifier.fillMaxHeight()
                else Modifier.heightIn(min = rowHeight * 3, max = wheelHeight).height(wheelHeight),
            )
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
                        drawRect(
                            Brush.verticalGradient(
                                0f to Color.Transparent,
                                AssistLongPress.DRUM_FADE_IN to Color.Black,
                                AssistLongPress.DRUM_FADE_OUT to Color.Black,
                                1f to Color.Transparent,
                            ),
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
                                if (centered) AssistLongPress.DRUM_CENTER_PT
                                else AssistLongPress.DRUM_NEIGHBOR_PT,
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
        LiveSheet.WB -> CaptureLists.wbInitialTab(status)
        LiveSheet.FORMAT -> {
            val format = VideoFormat.current(status)
            CaptureLists.formatResolutions(status).indexOf(format.resolution).coerceAtLeast(0)
        }
        else -> 0
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
        const val MIN_THIRDS = -9
        const val MAX_THIRDS = 9
        val ZERO = EvComp(0)
        val allCases: List<EvComp> = (MIN_THIRDS..MAX_THIRDS).map { EvComp(it) }

        fun fromThirds(thirds: Int): EvComp = EvComp(thirds.coerceIn(MIN_THIRDS, MAX_THIRDS))

        fun fromRaw(raw: Int): EvComp? {
            val t = raw - 0x10
            return if (t in MIN_THIRDS..MAX_THIRDS) EvComp(t) else null
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

/** COLOR drum write: `0x02/0x42` then optional native ISO hop. */
data class ColorDrumCommand(val colorMode: Int, val hopIsoIndex: Int?)

/**
 * ISO sheet reseat / apply — mirrors iOS `CapturePickerPanel` ISO seed,
 * `onChange(availableIsoIndices, colorMode)`, `applyDrum`, and Auto/Manual tabs.
 */
object IsoSheetLogic {
    data class State(
        val selectedMode: Int,
        val drumSelection: String,
        val lastApplied: String,
    )

    sealed class Command {
        data class SetIndex(val index: Int) : Command()
        data class SetLimit(val raw: Int) : Command()
    }

    fun isAutoTab(status: CameraStatus, selectedMode: Int): Boolean =
        CaptureLists.offersIsoAuto(status) && selectedMode == 0

    fun reseat(status: CameraStatus): State {
        val selectedMode =
            if (CaptureLists.offersIsoAuto(status)) {
                if (status.isoIndex == 0) 0 else 1
            } else {
                0
            }
        return reseatDrum(status, selectedMode)
    }

    fun reseatDrum(status: CameraStatus, selectedMode: Int): State {
        val autoTab = isAutoTab(status, selectedMode)
        val labels =
            if (autoTab) CaptureLists.isoAutoLabels(status) else CaptureLists.isoDrumLabels(status)
        val live =
            if (autoTab) {
                CaptureLists.isoAutoLabel(status)
            } else {
                when {
                    status.isoIndex > 0 -> CameraCommands.isoLabel(status.isoIndex)
                    status.iso > 0 -> "${status.iso}"
                    else -> labels.firstOrNull().orEmpty()
                }
            }
        val next = if (live in labels) live else labels.firstOrNull().orEmpty()
        return State(selectedMode, next, next)
    }

    fun applyDrum(value: String, status: CameraStatus, selectedMode: Int): Command? {
        if (value.isEmpty()) return null
        if (isAutoTab(status, selectedMode)) {
            val limit = CaptureLists.isoLimit(value, status) ?: return null
            return Command.SetLimit(limit.rawValue)
        }
        val idx = CaptureLists.isoIndexFromLabel(value) ?: return null
        if (idx !in CaptureLists.isoIndices(status) || idx == 0) return null
        return Command.SetIndex(idx)
    }

    fun handleModeChange(index: Int, status: CameraStatus): Pair<State, Command?> {
        if (!CaptureLists.offersIsoAuto(status)) return reseatDrum(status, 0) to null
        return if (index == 0) {
            reseatDrum(status, 0) to Command.SetIndex(0)
        } else {
            val state = reseatDrum(status, 1)
            val cmd =
                CaptureLists.isoIndexFromLabel(state.drumSelection)?.let { idx ->
                    if (idx in CaptureLists.isoIndices(status)) Command.SetIndex(idx) else null
                }
            state to cmd
        }
    }

    /** iOS `onChange` keys: `availableIsoIndices`, `colorMode` — not live `isoIndex`. */
    fun shouldReseat(previous: CameraStatus, next: CameraStatus): Boolean =
        previous.availableIsoIndices != next.availableIsoIndices ||
            previous.colorMode != next.colorMode
}

object CaptureLists {
    /** iOS `ExpoMode.allCases.map(\.label)` — MODE sheet rows. */
    val expoLabels: List<String> = listOf("Auto", "Manual")

    fun expoLabel(mode: Int): String =
        when (mode) {
            CameraCommands.EXPO_AUTO -> "Auto"
            CameraCommands.EXPO_MANUAL -> "Manual"
            else -> "—"
        }

    fun expoSelectedLabel(mode: Int): String? = expoLabel(mode).takeIf { it in expoLabels }

    fun expoModeFromLabel(label: String): Int? =
        when (label) {
            "Auto" -> CameraCommands.EXPO_AUTO
            "Manual" -> CameraCommands.EXPO_MANUAL
            else -> null
        }

    /** iOS `isEvSheet`: shutter sheet becomes EV while expo is Auto. */
    fun isEvSheet(sheet: LiveSheet, expoMode: Int): Boolean =
        sheet == LiveSheet.SHUTTER && expoMode == CameraCommands.EXPO_AUTO

    fun isAngleSheet(sheet: LiveSheet, expoMode: Int, selectedMode: Int): Boolean =
        sheet == LiveSheet.SHUTTER && !isEvSheet(sheet, expoMode) && selectedMode == 1

    /** iOS onChange expoMode: restore Speed/Angle from prefs when leaving Auto. */
    fun shutterTabAfterExpoChange(expoMode: Int, shutterUsesAngle: Boolean): Int? =
        if (expoMode != CameraCommands.EXPO_AUTO) {
            if (shutterUsesAngle) 1 else 0
        } else {
            null
        }

    fun headerTitle(sheet: LiveSheet, expoMode: Int): String =
        if (sheet == LiveSheet.SHUTTER) shutterHeaderTitle(isEvSheet(sheet, expoMode))
        else sheet.headerLabel

    fun headerSubtitle(
        sheet: LiveSheet,
        expoMode: Int,
        selectedMode: Int,
        facePriority: Boolean,
    ): String =
        if (sheet == LiveSheet.SHUTTER) {
            shutterHeaderSubtitle(
                isEvSheet(sheet, expoMode),
                isAngleSheet(sheet, expoMode, selectedMode),
                facePriority,
            )
        } else {
            sheet.subtitle
        }

    fun modeTabs(sheet: LiveSheet, expoMode: Int, offersIsoAuto: Boolean): List<String> =
        modeTabs(sheet, CameraStatus(expoMode = expoMode), offersIsoAuto)

    fun modeTabs(sheet: LiveSheet, status: CameraStatus, offersIsoAuto: Boolean): List<String> =
        when {
            sheet == LiveSheet.ISO && offersIsoAuto -> listOf("Auto", "Manual")
            sheet == LiveSheet.SHUTTER -> shutterModeTabs(isEvSheet(sheet, status.expoMode))
            sheet == LiveSheet.WB -> CaptureLists.wbTabs
            sheet == LiveSheet.AUDIO -> CaptureLists.audioTabs
            sheet == LiveSheet.FORMAT -> formatResolutions(status).map { it.tabTitle }
            else -> emptyList()
        }

    fun formatResolutions(status: CameraStatus): List<VideoResolution> =
        VideoFormat.resolutions(status.availableVideoFormats, VideoFormat.current(status).resolution)

    fun formatRates(status: CameraStatus, resolution: VideoResolution): List<VideoFrameRate> =
        VideoFormat.frameRates(
            status.availableVideoFormats,
            resolution,
            VideoFormat.current(status).frameRate,
        )

    fun fpsDrumLabels(status: CameraStatus, tab: Int): List<String> {
        val res = formatResolutions(status).getOrNull(tab) ?: VideoFormat.current(status).resolution
        return formatRates(status, res).map { it.drumLabel }
    }

    fun nextVideoFormat(
        status: CameraStatus,
        tab: Int,
        drum: String,
        fromDrum: Boolean,
    ): VideoFormat? {
        val resolutions = formatResolutions(status)
        val res = resolutions.getOrNull(tab) ?: return null
        val rates = formatRates(status, res)
        val parsed = VideoFrameRate.fromDrumLabel(drum)
        val rate =
            when {
                fromDrum -> parsed?.takeIf { it in rates } ?: return null
                parsed != null && parsed in rates -> parsed
                else -> rates.firstOrNull() ?: return null
            }
        val next = VideoFormat(res, rate)
        return next.takeIf { it != VideoFormat.current(status) }
    }

    val audioTabs: List<String> = listOf("Channel", "Wind", "Dir", "Vocal")
    val audioChannelLabels: List<String> = listOf("Stereo", "Mono", "Spatial")
    val audioWindLabels: List<String> = listOf("Off", "On")
    val audioDirLabels: List<String> = listOf("All", "Front", "Front+back")
    val audioVocalLabels: List<String> = listOf("Off", "On")

    fun audioChannelLabel(value: Int): String? = CameraCommands.audioChannelLabel(value)

    fun audioChannelValue(label: String): Int? =
        when (label) {
            "Mono" -> CameraCommands.AUDIO_MONO
            "Stereo" -> CameraCommands.AUDIO_STEREO
            "Spatial" -> CameraCommands.AUDIO_SPATIAL
            else -> null
        }

    fun audioWindLabel(value: Int): String? =
        when (value) {
            0 -> "Off"
            1 -> "On"
            else -> null
        }

    fun audioDirLabel(value: Int): String? = CameraCommands.audioDirLabel(value)

    fun audioDirValue(label: String): Int? =
        when (label) {
            "All" -> 0
            "Front" -> 1
            "Front+back" -> 2
            else -> null
        }

    fun audioVocalLabel(value: Int): String? =
        when (value) {
            0 -> "Off"
            1 -> "On"
            else -> null
        }

    /** iOS `seed` AUDIO: Channel tab + `refreshAudioState`. */
    fun audioInitialTab(): Int = 0

    fun shouldRefreshAudio(sheet: LiveSheet): Boolean = sheet == LiveSheet.AUDIO

    const val FACE_PRIORITY_TITLE = "Face Priority"
    const val FACE_PRIORITY_HELP =
        "On: EV follows faces to middle gray. Several faces use the median. First couple of seconds after a face appears are faster, then about 1 s. Off: put EV back to what it was, or 0.0."
    const val NATIVE_ISO_HOP_TITLE = "Auto Native ISO"
    const val NATIVE_ISO_HOP_HELP =
        "On: switching D-Log ↔ D-Log2 hops ISO to that curve's starred native if you were still on native. Off: keep the ISO you set."

    val evLabels: List<String> = EvComp.allCases.map { it.label }

    val kelvinValues: List<Int> = (2_000..10_000 step 100).toList()
    val kelvinLabels: List<String> = kelvinValues.map { "${it}K" }
    val wbTabs: List<String> = listOf("Mode", "Kelvin", "Tint")
    val wbModeRows: List<String> = listOf("Auto", "Custom")
    const val WB_TAB_MODE = 0
    const val WB_TAB_KELVIN = 1
    const val WB_TAB_TINT = 2

    val fpsDrumLabels: List<String> get() = VideoFrameRate.drumLabels

    val resolutionTabTitles: List<String> get() = VideoResolution.tabTitles

    /** Family fallback — D-Log2 is 4 Pro only (`colorWheelOrder`). */
    val colorWheelPocket: List<Pair<Int, String>> =
        listOf(
            CameraCommands.COLOR_NORMAL to "Normal",
            CameraCommands.COLOR_HDR to "HDR",
            CameraCommands.COLOR_DLOG to "D-Log",
        )

    val colorWheelPocket4Pro: List<Pair<Int, String>> =
        colorWheelPocket + listOf(CameraCommands.COLOR_DLOG2 to "D-Log2")

    val colorWheelPocket3: List<Pair<Int, String>> =
        listOf(
            CameraCommands.COLOR_NORMAL to "Normal",
            CameraCommands.COLOR_HDR to "HDR",
            CameraCommands.COLOR_DLOG_M to "D-Log M",
        )

    val colorWheelNano: List<Pair<Int, String>> =
        listOf(
            CameraCommands.COLOR_NORMAL to "Normal 8-bit",
            CameraCommands.COLOR_NORMAL10 to "Normal 10-bit",
            CameraCommands.COLOR_DLOG_M to "D-Log M 10-bit",
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

    fun isEvSheet(expoMode: Int): Boolean = expoMode == CameraCommands.EXPO_AUTO

    fun isAngleSheet(expoMode: Int, selectedMode: Int): Boolean =
        !isEvSheet(expoMode) && selectedMode == 1

    fun shutterModeTabs(isEvSheet: Boolean): List<String> =
        if (isEvSheet) emptyList() else listOf("Speed", "Angle")

    fun shutterHeaderTitle(isEvSheet: Boolean): String = if (isEvSheet) "EV" else "SHUTTER"

    fun shutterHeaderSubtitle(
        isEvSheet: Boolean,
        isAngleSheet: Boolean,
        facePriority: Boolean,
    ): String =
        when {
            isEvSheet -> if (facePriority) "Face priority" else "Compensation"
            isAngleSheet -> "Angle"
            else -> "Speed"
        }

    fun shutterWheelOptions(
        status: CameraStatus,
        isEvSheet: Boolean,
        isAngleSheet: Boolean,
    ): List<String> =
        when {
            isEvSheet -> evLabels
            isAngleSheet -> ShutterAngle.labels
            else -> shutterLabels(status)
        }

    data class ShutterSeat(
        val selection: String,
        val preferredAngle: Double = ShutterAngle.DEFAULT_DEGREES,
        val persistAngle: Boolean = false,
    )

    sealed class ShutterDrumCommand {
        data class SetEv(val thirds: Int) : ShutterDrumCommand()
        data class SetShutter(val denom: Int) : ShutterDrumCommand()
        data class SetAngle(val degrees: Double, val denom: Int) : ShutterDrumCommand()
        data object Ignored : ShutterDrumCommand()
    }

    enum class ShutterReseatKey {
        AVAILABLE_DENOMS,
        FPS,
        EXPO_MODE,
        EV_COMP,
        FACE_PRIORITY,
        SHUTTER_DENOM,
    }

    /** iOS `CapturePickerPanel` onChange keys. Never reseat on live 1/N ticks. */
    fun shouldReseatShutter(key: ShutterReseatKey, isEvSheet: Boolean): Boolean =
        when (key) {
            ShutterReseatKey.AVAILABLE_DENOMS, ShutterReseatKey.FPS -> !isEvSheet
            ShutterReseatKey.EXPO_MODE -> true
            ShutterReseatKey.EV_COMP, ShutterReseatKey.FACE_PRIORITY -> isEvSheet
            ShutterReseatKey.SHUTTER_DENOM -> false
        }

    fun reseatEv(status: CameraStatus): ShutterSeat {
        val labels = evLabels
        val live = EvComp.fromRaw(status.evComp)?.label ?: "0.0"
        val next = if (live in labels) live else "0.0"
        return ShutterSeat(next)
    }

    fun reseatShutterSpeed(status: CameraStatus): ShutterSeat {
        val labels = shutterLabels(status)
        val live =
            if (status.shutterDenom > 0) shutterLabel(status.shutterDenom)
            else labels.firstOrNull().orEmpty()
        val next = if (live in labels) live else nearestShutterLabel(live, status)
        return ShutterSeat(next)
    }

    fun reseatShutterAngle(status: CameraStatus, preferredAngle: Double): ShutterSeat {
        val labels = ShutterAngle.labels
        val fps = status.fps
        val liveDenom = status.shutterDenom
        val preferred = ShutterAngle.label(preferredAngle)
        if (liveDenom > 0) {
            val mapped = ShutterAngle.denom(preferredAngle, fps, shutterDenoms(status))
            if (mapped == liveDenom && preferred in labels) {
                return ShutterSeat(preferred, preferredAngle, persistAngle = false)
            }
            val next = ShutterAngle.nearestLabel(liveDenom, fps)
            val degrees = ShutterAngle.parse(next) ?: ShutterAngle.DEFAULT_DEGREES
            return ShutterSeat(next, degrees, persistAngle = true)
        }
        return ShutterSeat(preferred, preferredAngle, persistAngle = false)
    }

    fun reseatShutter(
        status: CameraStatus,
        selectedMode: Int,
        isEvSheet: Boolean,
        preferredAngle: Double,
    ): ShutterSeat =
        if (selectedMode == 1 && !isEvSheet) {
            reseatShutterAngle(status, preferredAngle)
        } else {
            reseatShutterSpeed(status)
        }

    fun applyShutterDrum(
        value: String,
        isEvSheet: Boolean,
        isAngleSheet: Boolean,
        facePriority: Boolean,
        status: CameraStatus,
    ): ShutterDrumCommand {
        if (value.isEmpty()) return ShutterDrumCommand.Ignored
        if (isEvSheet) {
            if (facePriority) return ShutterDrumCommand.Ignored
            val ev = EvComp.fromLabel(value) ?: return ShutterDrumCommand.Ignored
            return ShutterDrumCommand.SetEv(ev.thirds)
        }
        if (isAngleSheet) {
            val degrees = ShutterAngle.parse(value) ?: return ShutterDrumCommand.Ignored
            val denom = ShutterAngle.denom(degrees, status.fps, shutterDenoms(status))
            return ShutterDrumCommand.SetAngle(degrees, denom)
        }
        val denom = denomFromLabel(value) ?: return ShutterDrumCommand.Ignored
        if (denom !in shutterDenoms(status)) return ShutterDrumCommand.Ignored
        return ShutterDrumCommand.SetShutter(denom)
    }

    /** iOS `CameraSession.setVideoFormat` angle rematch. Null = no shutter write. */
    fun rematchShutterDenomAfterFps(
        usesAngle: Boolean,
        degrees: Double,
        previousFps: Int,
        nextFps: Int,
        expoMode: Int,
        currentDenom: Int,
        available: List<Int>,
    ): Int? {
        if (!usesAngle || expoMode == CameraCommands.EXPO_AUTO || previousFps == nextFps) return null
        val denom = ShutterAngle.denom(degrees, nextFps, available)
        return denom.takeIf { it != currentDenom }
    }

    fun isoFallback(colorMode: Int): List<Int> = CameraCommands.isoChoices(colorMode).map { it.first }

    fun isoIndices(status: CameraStatus): List<Int> =
        CameraCommands.isoWheelIndices(status.availableIsoIndices, isoFallback(status.colorMode))

    fun isoDrumLabels(status: CameraStatus): List<String> =
        isoIndices(status)
            .filter { it != 0 }
            .map { CameraCommands.isoLabel(it) }
            .filter { it != "—" }

    fun isoIndexFromLabel(label: String): Int? =
        CameraCommands.ISO_INDEX_BYTES.firstOrNull { CameraCommands.isoLabel(it) == label }

    fun offersIsoAuto(status: CameraStatus): Boolean = CameraCommands.offersIsoAuto(status.colorMode)

    /** GET `0x8E` pid `0x000F` only when Auto ISO exists. Unknown color = Normal. */
    fun shouldGetIsoLimit(status: CameraStatus): Boolean =
        CameraCommands.shouldGetIsoLimit(status.colorMode)

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
        val base = CameraCommands.markedIsoLabel(status.colorMode) ?: return emptySet()
        return setOf(base)
    }

    fun currentKelvin(status: CameraStatus): Int {
        val k = status.wbKelvin
        return if (k in 2_000..10_000) k else 5_600
    }

    fun currentTint(status: CameraStatus): Int = status.wbTint.coerceIn(-100, 100)

    fun kelvinFromLabel(label: String): Int? = label.removeSuffix("K").toIntOrNull()

    fun wbInitialTab(status: CameraStatus): Int =
        if (status.wbMode == CameraCommands.WB_CUSTOM) WB_TAB_KELVIN else WB_TAB_MODE

    fun wbModeRowSelected(status: CameraStatus): String =
        if (status.wbMode == CameraCommands.WB_CUSTOM) "Custom" else "Auto"

    fun wbSendsAuto(label: String): Boolean = label == "Auto"

    fun wbDrumSelection(status: CameraStatus): String {
        val k = "${currentKelvin(status)}K"
        return if (k in kelvinLabels) k else "5600K"
    }

    fun wbCustomFromStatus(status: CameraStatus): Pair<Int, Int> =
        currentKelvin(status) to currentTint(status)

    fun wbCustomFromKelvinLabel(label: String, status: CameraStatus): Pair<Int, Int>? {
        val kelvin = kelvinFromLabel(label) ?: return null
        return kelvin to currentTint(status)
    }

    fun wbKelvinDrumApply(selectedMode: Int, value: String, status: CameraStatus): Pair<Int, Int>? {
        if (selectedMode != WB_TAB_KELVIN) return null
        return wbCustomFromKelvinLabel(value, status)
    }

    fun roundedTint(value: Float): Int = value.roundToInt().coerceIn(-100, 100)

    fun nudgeTint(current: Float, delta: Int): Float = (current + delta).coerceIn(-100f, 100f)

    fun tintLabel(tint: Int): String {
        val t = tint.coerceIn(-100, 100)
        if (t == 0) return "Neutral"
        return if (t > 0) "+$t" else "$t"
    }

    fun tintApplyLabel(tint: Int): String = "Apply tint ${tint.coerceIn(-100, 100)}"

    fun wbCustomFromTint(tint: Float, status: CameraStatus): Pair<Int, Int> =
        currentKelvin(status) to roundedTint(tint)

    fun wbTintStaysAuto(status: CameraStatus): Boolean =
        status.wbMode != CameraCommands.WB_CUSTOM

    fun fpsDrumLabel(status: CameraStatus): String = VideoFormat.current(status).frameRate.drumLabel

    fun fpsIndexFromDrum(label: String): Int? = VideoFrameRate.fromDrumLabel(label)?.rawValue

    fun currentFpsIndex(status: CameraStatus): Int = VideoFormat.current(status).frameRate.rawValue

    /**
     * Angle mode is ours: keep the chosen degrees and rewrite 1/N for the new fps.
     * Returns the denom to SET, or null when nothing should change.
     */
    fun shutterDenomAfterFormatChange(
        previousFps: Int,
        nextFps: Int,
        expoMode: Int,
        shutterUsesAngle: Boolean,
        angleDegrees: Double,
        currentDenom: Int,
        available: List<Int>,
    ): Int? {
        if (!shutterUsesAngle || previousFps == nextFps || expoMode == CameraCommands.EXPO_AUTO) {
            return null
        }
        val denom = ShutterAngle.denom(angleDegrees, nextFps, available)
        return denom.takeIf { it != currentDenom }
    }

    fun colorWheelOrder(name: String, family: String): List<Pair<Int, String>> {
        val codes = CameraModel.colorModesFor(name, family)
        return codes.map { it to CameraCommands.colorLabel(it, family) }
    }

    fun colorWheel(
        family: String,
        available: List<Int> = emptyList(),
        name: String = "",
    ): List<Pair<Int, String>> {
        val order = colorWheelOrder(name, family)
        if (available.isEmpty()) return order
        val have = available.toSet()
        val ranked = order.filter { it.first in have }
        return ranked.ifEmpty { order }
    }

    fun colorWheelLabels(
        status: CameraStatus,
        family: String = "pocket",
        name: String = "",
    ): List<String> = colorWheel(family, status.availableColorModes, name).map { it.second }

    fun colorModeFromLabel(label: String, family: String = "pocket", name: String = ""): Int? {
        if (label == "Normal 8-bit") return CameraCommands.COLOR_NORMAL
        if (label == "D-Log M") return CameraCommands.COLOR_DLOG_M
        return colorWheel(family, name = name).firstOrNull { it.second == label }?.first
            ?: colorWheelPocket.firstOrNull { it.second == label }?.first
            ?: colorWheelPocket4Pro.firstOrNull { it.second == label }?.first
            ?: colorWheelPocket3.firstOrNull { it.second == label }?.first
            ?: colorWheelNano.firstOrNull { it.second == label }?.first
    }

    /**
     * COLOR drum: body wheel only, then hop ISO after the color SET — same
     * order as iOS `CameraSession.setColorMode` + `CamCapIso.nativeISOHop`.
     */
    fun applyColorDrum(
        label: String,
        family: String,
        status: CameraStatus,
        hopEnabled: Boolean,
        name: String = "",
    ): ColorDrumCommand? {
        val mode = colorModeFromLabel(label, family, name) ?: return null
        val allowed = colorWheel(family, status.availableColorModes, name).map { it.first }
        if (mode !in allowed) return null
        val hop =
            nativeIsoHop(
                from = status.colorMode,
                to = mode,
                currentIndex = status.isoIndex,
                hopEnabled = hopEnabled,
            )
        return ColorDrumCommand(mode, hop)
    }

    /**
     * If the operator is still on [from]'s native ISO, hop to [to]'s native.
     * Off-base or Auto stays put. Rec.709 / HDR have no native — no hop.
     */
    fun nativeIsoHop(from: Int, to: Int, currentIndex: Int, hopEnabled: Boolean): Int? =
        CameraCommands.nativeIsoHop(from, to, currentIndex, hopEnabled)

    /**
     * FORMAT / COLOR drums shrink into the well under the chip so the card
     * stays 8 dp below STBY instead of covering it on short landscape.
     * Chrome: 12+12 pad, 27 header, 8 gap(s), optional 51 mode bar.
     */
    fun topPickerDrumHeight(maxSheetDp: Float?, hasTabs: Boolean): Float {
        val chrome =
            AssistLongPress.PANEL_PAD_DP * 2 +
                AssistLongPress.CLOSE_DP +
                AssistLongPress.PANEL_GAP_DP * (if (hasTabs) 2 else 1) +
                if (hasTabs) LiveChromeMetrics.PICKER_MODE_BAR_HEIGHT else 0f
        val available = (maxSheetDp ?: 400f) - chrome
        return available.coerceIn(AssistLongPress.DRUM_ROW_DP * 2, 176f)
    }

    /** Top-deck chip, OpenZCine `4K · 25p`. */
    fun recFormatChipLabel(status: CameraStatus): String = VideoFormat.chipLabel(status)

    /** Remaining storage. Source order is `storage*` then `sd*`, matching iOS. */
    fun storageLabel(status: CameraStatus, showDuration: Boolean): String {
        if (showDuration) {
            return if (status.recordRemainingSec > 0) {
                "${status.recordRemainingSec / 60} Min"
            } else {
                "— Min"
            }
        }
        val free = if (status.storageFreeMb > 0) status.storageFreeMb else status.sdFreeMb
        val total = if (status.storageTotalMb > 0) status.storageTotalMb else status.sdTotalMb
        if (total > 0) {
            val gb = max(0, free) / 1024
            val pct = ((max(0, free).toDouble() / total.toDouble()) * 100.0).roundToInt()
            return "$gb GB · $pct%"
        }
        if (free > 0) return "${free / 1024} GB"
        return "—"
    }

    fun isoChipValue(status: CameraStatus): String =
        when {
            status.isoIndex == 0 -> "Auto"
            status.iso > 0 -> "${status.iso}"
            status.isoIndex > 0 -> CameraCommands.isoLabel(status.isoIndex)
            else -> "—"
        }

    fun wbChipValue(status: CameraStatus): String =
        when (status.wbMode) {
            CameraCommands.WB_CUSTOM -> if (status.wbKelvin > 0) "${status.wbKelvin}K" else "Custom"
            CameraCommands.WB_AUTO -> "Auto"
            else -> "—"
        }

    /** iOS aperture glyph when mode is not custom (Auto and unknown). */
    fun wbIsAuto(status: CameraStatus): Boolean =
        status.wbMode != CameraCommands.WB_CUSTOM

    fun wbChipWidest(): String = "10000K"

    const val FOCUS_TAB_SINGLE = "AF-S"
    const val FOCUS_TAB_CONTINUOUS = "AF-C"

    /**
     * Nano / Atto have no AF-S / AF-C. Unknown camera defaults to Pocket (supported),
     * matching iOS `CameraSession.supportsFocusMode`.
     */
    fun supportsFocusMode(modelName: String?, family: String? = null, flag: Boolean? = null): Boolean {
        if (flag == false) return false
        if (family.equals("nano", ignoreCase = true)) return false
        val n = (modelName ?: "").lowercase().replace(" ", "")
        if (n.isEmpty()) return true
        return !n.contains("nano") && !n.contains("atto")
    }

    /** iOS `connectedCamera?.model.supportsFocusMode ?? true` when [model] is present. */
    fun supportsFocusMode(model: CameraModel): Boolean =
        supportsFocusMode(model.name, model.family, model.supportsFocusMode)

    fun supportsFocusModeOrDefault(model: CameraModel?): Boolean =
        supportsFocusMode(model?.name, model?.family, model?.supportsFocusMode)

    /** iOS `focusMode == .continuous`. Unknown / AF-S is the AF-S tab. */
    fun focusIsContinuous(status: CameraStatus): Boolean =
        status.focusMode == CameraCommands.FOCUS_CONTINUOUS

    /** Horizontal AF-C chips only while continuous, matching iOS `if continuous`. */
    fun focusShowsTrackChips(status: CameraStatus): Boolean = focusIsContinuous(status)

    /** Unknown track paints Default, matching iOS `focusTrack ?? .default`. */
    fun selectedFocusTrack(status: CameraStatus): Int =
        if (status.focusTrack < 0) FocusTrackMode.DEFAULT.raw else status.focusTrack

    /** GET `0x8E` pid `0x003B` when FOCUS opens without a track. Nano never GETs. */
    fun shouldRefreshFocusTrack(status: CameraStatus, supportsFocus: Boolean): Boolean =
        supportsFocus && status.focusTrack < 0
}
