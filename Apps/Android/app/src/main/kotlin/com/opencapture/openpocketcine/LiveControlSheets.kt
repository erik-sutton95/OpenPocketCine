package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.LocalOperatorHaptics
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import com.opencapture.opencine.appkit.captureField
import com.opencapture.opencine.appkit.commit
import com.opencapture.monitorui.MonitorTab
import com.opencapture.monitorui.monitorTabStrip
import com.opencapture.monitorui.MonitorQuickPreview
import com.opencapture.monitorui.monitorScrollFade
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import com.opencapture.opencine.cameracontrols.CaptureFocusChoices
import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.CapturePanelEffects
import com.opencapture.opencine.cameracontrols.IsoSheetLogic
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.cameracontrols.applyCaptureFocusChoice
import com.opencapture.opencine.cameracontrols.applyCaptureShootingMode
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.opencine.cameracontrols.isRecordingSetup
import com.opencapture.opencine.cameracontrols.isTopAnchored
import com.opencapture.opencine.vocabulary.ApertureStrategy
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureShutterPolicy
import com.opencapture.opencine.vocabulary.ShutterAngle
import com.opencapture.opencine.vocabulary.VideoAspect
import com.opencapture.opencine.vocabulary.VideoFormat
import com.opencapture.openpocketcine.assists.AssistLongPress
import com.opencapture.openpocketcine.settings.SettingsHelpBadge
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.round

@Composable
fun LiveControlSheet(
    sheet: LiveSheet,
    model: AppModel,
    status: CameraStatus,
    locked: Boolean,
    onDismiss: () -> Unit,
    maxHeightDp: Float? = null,
    preview: MonitorQuickPreview? = null,
    portrait: Boolean? = null,
    showsHeader: Boolean = true,
) {
    val availableStatus = CaptureLists.withEffectiveVideoFormats(
        status, model.session.connectedCamera?.model,
    )
    val isPortrait = portrait ?: viewportIsPortrait()
    CompositionLocalProvider(LocalCapturePreview provides preview, LocalViewportPortrait provides isPortrait) {
        if (sheet.isRecordingSetup && isPortrait && showsHeader) {
            RecordingSetupPanel(sheet, model, availableStatus, locked, onDismiss, maxHeightDp)
        } else {
            LiveControlSheetContent(sheet, model, availableStatus, locked, onDismiss, maxHeightDp, showsHeader = showsHeader)
        }
    }
}

private val LocalCapturePreview = staticCompositionLocalOf<MonitorQuickPreview?> { null }
private val LocalViewportPortrait = staticCompositionLocalOf { true }

/** Format, color and shooting mode share one native recording-options panel. */
@Composable
private fun RecordingSetupPanel(
    initial: LiveSheet, model: AppModel, status: CameraStatus, locked: Boolean,
    onDismiss: () -> Unit, maxHeightDp: Float?,
) {
    val preview = LocalCapturePreview.current
    val enabled = !locked && preview == null
    val tabNames = CaptureShutterPolicy.recordingCategoryTabs(status.shootingMode)
    var tab by remember(initial, tabNames) {
        mutableStateOf(
            when {
                "Mode" in tabNames && (initial == LiveSheet.MODE || tabNames == listOf("Mode")) -> "Mode"
                initial == LiveSheet.COLOR && "Color" in tabNames -> "Color"
                else -> tabNames.firstOrNull() ?: "Format"
            },
        )
    }
    val categories: @Composable () -> Unit = {
        if (tabNames.size > 1) {
            ModeBar(tabNames, tabNames.indexOf(tab).coerceAtLeast(0), enabled) {
                tab = tabNames[it]
            }
        }
    }
    androidx.compose.runtime.key(tab) {
        if (tab == "Mode" || tabNames == listOf("Mode")) {
            val modeScroll = rememberScrollState()
            Column(Modifier.fillMaxWidth().then(if (maxHeightDp != null) Modifier.heightIn(max = maxHeightDp.dp) else Modifier)
                .pickerPanelGlass(capturePanelShape(fromTop = true, portrait = viewportIsPortrait()))
                .monitorScrollFade(modeScroll).verticalScroll(modeScroll, enabled = preview == null).padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SheetHeader("SHOOTING MODE", "Capture mode", onDismiss)
                val bodyName = model.session.connectedCamera?.model?.name
                val labels = CaptureLists.shootingModeLabels(bodyName, status.shootingMode)
                CaptureDrumWheel(labels, CameraCommands.shootingModeLabel(status.shootingMode, bodyName).orEmpty()
                    .takeIf { it in labels }.orEmpty(),
                    interactive = enabled && !status.isRecording) { label ->
                    applyCaptureShootingMode(label, model.session.status.value,
                        model.session.connectedCamera?.model?.name, send = model::setShootingMode)
                }
                if (tabNames.size > 1 &&
                    com.opencapture.monitorui.MonitorLayoutPolicy.showsRecordingCategoryTabs(viewportIsPortrait(), preview != null)
                ) {
                    categories()
                }
                if (status.isRecording) Text("Stop recording to change mode.", color = LiveDesign.muted, style = LiveType.text(11f))
                if (com.opencapture.monitorui.MonitorLayoutPolicy.showsCaptureGrabber(preview != null, fromTop = true)) {
                    com.opencapture.monitorui.MonitorPanelGrabber()
                }
            }
        } else {
            LiveControlSheetContent(if (tab == "Color") LiveSheet.COLOR else LiveSheet.FORMAT,
                model, status, locked, onDismiss, maxHeightDp, footer = categories)
        }
    }
}

@Composable
private fun LiveControlSheetContent(
    sheet: LiveSheet,
    model: AppModel,
    status: CameraStatus,
    locked: Boolean,
    onDismiss: () -> Unit,
    maxHeightDp: Float?,
    footer: (@Composable () -> Unit)? = null,
    showsHeader: Boolean = true,
) {
    val context = LocalContext.current
    val commonField = remember(sheet, model.control) {
        val key = capturePanelSettingKey(sheet, status.expoMode)
        key?.let { model.control.captureField(it) }
    }
    val preview = LocalCapturePreview.current
    val effects = CapturePanelEffects(preview != null)
    val enabled = !locked && preview == null
    val isEvSheet = CaptureLists.isEvSheet(sheet, status.expoMode)
    @Composable fun commonDrum() {
        val field = retainedCapturePanelField(commonField, sheet, status.expoMode)
        if (field == null) {
            Text("Setting not available", color = LiveDesign.muted)
        } else {
            val choices = field.choices.filter { choice -> when (val value = choice.value) {
                is com.opencapture.opencine.core.SettingValue.Iso -> value.value is com.opencapture.opencine.core.ISOValue.Manual
                is com.opencapture.opencine.core.SettingValue.Shutter -> value.value is com.opencapture.opencine.core.ShutterValue.Duration
                is com.opencapture.opencine.core.SettingValue.WhiteBalance -> value.value is com.opencapture.opencine.core.WhiteBalanceValue.Kelvin
                is com.opencapture.opencine.core.SettingValue.ExposureCompensation -> true
                else -> false
            } }
            com.opencapture.opencine.appkit.MonitorCaptureDrum(model.control, field,
                enabled = enabled && (!isEvSheet || !model.facePriorityExposureEnabled), choices = choices)
        }
    }
    val offersIsoAuto = CaptureLists.offersIsoAuto(status)
    var selectedMode by remember(sheet) {
        mutableIntStateOf(initialSelectedMode(sheet, status, model, isEvSheet))
    }
    var selectedAspect by remember(sheet) {
        mutableStateOf(
            VideoFormat.current(status).resolution.aspect ?: VideoAspect.SIXTEEN_NINE,
        )
    }
    var drumSelection by remember(sheet) { mutableStateOf("") }
    var lastApplied by remember(sheet) { mutableStateOf("") }
    var preferredAngle by remember(sheet) { mutableDoubleStateOf(OperatorPrefs.shutterAngleDegrees(context)) }
    val isIsoAutoTab = sheet == LiveSheet.ISO && offersIsoAuto && selectedMode == 0
    val isAngleSheet = CaptureLists.isAngleSheet(
        sheet, status.expoMode, selectedMode, status.shootingMode,
    )
    val formatAspects = CaptureLists.formatAspects(status)
    val tabs = CaptureLists.modeTabs(sheet, status, offersIsoAuto, selectedAspect)
    val bodyFamily = model.session.connectedCamera?.model?.family ?: "pocket"
    val bodyName = model.session.connectedCamera?.model?.name ?: ""

    // The shared drum reports one settled value. Dispatch here, with no second
    // delayed closure that could outlive this source, frame rate, or option set.
    fun commitDrumValue(send: () -> Unit) { if (enabled) send() }

    fun applyIsoSeat(state: IsoSheetLogic.State) {
        selectedMode = state.selectedMode
        lastApplied = state.lastApplied
        drumSelection = state.drumSelection
    }

    fun reseatIso() {
        applyIsoSeat(IsoSheetLogic.reseat(status, bodyName))
    }

    fun applySeat(seat: CaptureLists.ShutterSeat) {
        if (isAngleSheet) preferredAngle = seat.preferredAngle
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
    }

    fun reseatResolution() {
        if (CameraCommands.isPhotoMode(status.shootingMode)) {
            drumSelection = CaptureLists.PHOTO_FORMAT_READOUT
            lastApplied = drumSelection
            return
        }
        val format = VideoFormat.current(status)
        selectedAspect = format.resolution.aspect ?: VideoAspect.SIXTEEN_NINE
        val tabs = CaptureLists.formatResolutions(status, selectedAspect)
        selectedMode = tabs.indexOf(format.resolution).coerceAtLeast(0)
        val label = format.frameRate.drumLabel
        drumSelection = label
        lastApplied = label
    }

    fun handleAspectChange(aspect: VideoAspect) {
        if (!enabled || aspect == selectedAspect || CameraCommands.isPhotoMode(status.shootingMode)) return
        selectedAspect = aspect
        val sizes = CaptureLists.formatResolutions(status, aspect)
        val match =
            sizes.firstOrNull { it.sizeTitle == VideoFormat.current(status).resolution.sizeTitle }
                ?: sizes.firstOrNull()
                ?: return
        selectedMode = sizes.indexOf(match).coerceAtLeast(0)
        val rates = CaptureLists.formatRates(status, match)
        val currentRate = VideoFormat.current(status).frameRate
        val rate = if (currentRate in rates) currentRate else rates.firstOrNull() ?: return
        drumSelection = rate.drumLabel
        lastApplied = drumSelection
        val next = VideoFormat(match, rate)
        if (next != VideoFormat.current(status)) model.setVideoFormat(next)
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
                if (!isEvSheet) {
                    selectedMode =
                        if (CameraCommands.isPhotoMode(status.shootingMode) || !model.shutterUsesAngle) 0
                        else 1
                }
                reseatShutterOrEv()
            }
            LiveSheet.WB -> {
                selectedMode = CaptureLists.wbInitialTab(status, model.session.awbLockKelvin.value != null)
                reseatWb()
            }
            LiveSheet.AUDIO -> selectedMode = CaptureLists.audioInitialTab()
            LiveSheet.FORMAT -> reseatResolution()
            LiveSheet.COLOR -> reseatColor()
            LiveSheet.MODE -> {
                val live = CameraCommands.shootingModeLabel(status.shootingMode, bodyName).orEmpty()
                val labels = CaptureLists.shootingModeLabels(bodyName, status.shootingMode)
                drumSelection = if (live in labels) live else ""
                lastApplied = drumSelection
            }
            else -> selectedMode = 0
        }
    }

    fun applyVideoFormat(tab: Int, drum: String, fromDrum: Boolean) {
        if (!CaptureLists.formatPickerEditable(status)) return
        val next = CaptureLists.nextVideoFormat(status, tab, drum, fromDrum, selectedAspect) ?: return
        model.setVideoFormat(next)
    }

    fun handleModeChange(index: Int) {
        if (!enabled) return
        when {
            sheet == LiveSheet.ISO && offersIsoAuto -> {
                val (state, cmd) = IsoSheetLogic.handleModeChange(index, status, bodyName)
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
                when (val cmd = IsoSheetLogic.applyDrum(value, status, selectedMode, bodyName)) {
                    is IsoSheetLogic.Command.SetLimit ->
                        commitDrumValue { model.setIsoLimit(cmd.raw) }
                    is IsoSheetLogic.Command.SetIndex ->
                        commitDrumValue { model.setIsoIndex(cmd.index) }
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
                        commitDrumValue { model.setEv(cmd.thirds) }
                    is CaptureLists.ShutterDrumCommand.SetShutter ->
                        commitDrumValue { model.setShutterDenom(cmd.denom) }
                    is CaptureLists.ShutterDrumCommand.SetAngle -> {
                        commitDrumValue {
                            preferredAngle = cmd.degrees
                            model.session.setShutterAngle(cmd.degrees)
                        }
                    }
                    CaptureLists.ShutterDrumCommand.Ignored -> Unit
                }
            }
            LiveSheet.WB -> {
                val custom = CaptureLists.wbKelvinDrumApply(selectedMode, value, status) ?: return
                model.setWhiteBalance(custom.first, custom.second)
            }
            LiveSheet.FORMAT -> {
                commitDrumValue { applyVideoFormat(selectedMode, value, fromDrum = true) }
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
                commitDrumValue { model.setColorMode(command.colorMode) }
            }
            LiveSheet.MODE -> {
                commitDrumValue {
                    applyCaptureShootingMode(value, model.session.status.value,
                        model.session.connectedCamera?.model?.name, send = model::setShootingMode)
                }
            }
            else -> Unit
        }
    }

    // Read-only preview mounts cannot seed preferences or issue any camera GET.
    // Effects also guard reseating so a future caller cannot accidentally persist an angle.
    if (preview == null) {
        LaunchedEffect(sheet) {
            effects.mount(sheet, status, model.monitorLayout().focus,
                model::refreshAudio, model::refreshFocusTrack, { model.refreshIsoLimitNow() }, ::seed, ::reseatIso)
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
                CaptureLists.shutterTabAfterExpoChange(
                    status.expoMode, model.shutterUsesAngle, status.shootingMode,
                )?.let {
                    selectedMode = it
                }
                reseatShutterOrEv()
            }
        }
        LaunchedEffect(sheet, status.evComp, model.facePriorityExposureEnabled) {
            if (sheet == LiveSheet.SHUTTER && isEvSheet) reseatEv()
        }
        LaunchedEffect(
            sheet, status.shootingMode, status.resolutionCode, status.fpsIndex,
            status.availableVideoFormats,
        ) {
            if (sheet == LiveSheet.FORMAT && !model.session.isFormatPinActive) reseatResolution()
        }
        LaunchedEffect(sheet, status.shootingMode) {
            if (sheet == LiveSheet.SHUTTER && CameraCommands.isPhotoMode(status.shootingMode) && !isEvSheet) {
                selectedMode = 0
                reseatShutter()
            }
        }
        LaunchedEffect(sheet, status.colorMode) {
            if (sheet == LiveSheet.COLOR) reseatColor()
        }
    }

    val cap = maxHeightDp?.dp
    val compact = preview != null
    val fromTop = sheet.isTopAnchored
    val portrait = viewportIsPortrait()
    val topPadding = if (showsHeader) com.opencapture.monitorui.MonitorLayoutPolicy.captureTopPadding(fromTop, portrait, compact) else 0f
    // Every drum has the same 86dp viewport; the card hugs its own controls.
    val sheetScroll = rememberScrollState()
    Column(
        Modifier
            .fillMaxWidth()
            .then(Modifier.wrapContentHeight(align = Alignment.Top))
            .then(if (cap != null) Modifier.heightIn(max = cap) else Modifier)
            .pickerPanelGlass(capturePanelShape(fromTop, portrait))
            .monitorScrollFade(sheetScroll)
            .verticalScroll(sheetScroll, enabled = preview == null)
            .pointerInput(Unit) { detectTapGestures(onTap = {}) }
            .padding(horizontal = 14.dp)
            .padding(
                top = topPadding.dp,
                bottom = when {
                    compact -> com.opencapture.monitorui.MonitorLayoutPolicy.compactCaptureBottomPadding(
                        topPadding).dp
                    fromTop -> 14.dp
                    else -> 11.dp
                },
            ),
        verticalArrangement = Arrangement.spacedBy(AssistLongPress.PANEL_GAP_DP.dp),
    ) {
            if (showsHeader) SheetHeader(
                title = CaptureLists.headerTitle(sheet, status.expoMode, status.shootingMode),
                subtitle =
                    if (compact) "drag to set"
                    else
                        CaptureLists.headerSubtitle(
                            sheet,
                            status.expoMode,
                            selectedMode,
                            model.facePriorityExposureEnabled,
                            status.shootingMode,
                        ),
                onClose = onDismiss,
                showsClose = !compact,
            )
            if (preview != null) {
                CaptureDrumWheel(
                    options = preview.control.options,
                    selection = preview.selection,
                    markedValues = preview.control.marked,
                    interactive = false,
                    onSelect = {},
                )
            } else when (sheet) {
                LiveSheet.ISO -> {
                    Column(
                        Modifier.wrapContentHeight(),
                        verticalArrangement = Arrangement.spacedBy(AssistLongPress.PANEL_GAP_DP.dp),
                    ) {
                        Box(Modifier.fillMaxWidth()) {
                            if (isIsoAutoTab) {
                                CaptureDrumWheel(
                                    options = CaptureLists.isoAutoLabels(status, bodyName),
                                    selection = drumSelection,
                                    interactive = enabled,

                                    onSelect = {
                                        drumSelection = it
                                        applyDrum(it)
                                    },
                                )
                            } else {
                                commonDrum()
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
                        Modifier.wrapContentHeight(),
                        verticalArrangement = Arrangement.spacedBy(AssistLongPress.PANEL_GAP_DP.dp),
                    ) {
                        Box(Modifier.fillMaxWidth()) {
                            if (isEvSheet) {
                                commonDrum()
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
                                commonDrum()
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
                        0 -> {
                            val awbLocked = model.session.awbLockKelvin.collectAsState().value != null
                            CheckedRows(
                                options = CaptureLists.wbModeRows(
                                    awbLocked || model.session.autoWhiteBalanceLock(status) != null),
                                selected = CaptureLists.wbModeRowSelected(status, awbLocked),
                                enabled = enabled,
                            ) { label ->
                                if (label == CaptureLists.AWB_LOCK) {
                                    model.session.lockAutoWhiteBalance()
                                } else if (CaptureLists.wbSendsAuto(label)) {
                                    model.setWhiteBalanceAuto()
                                } else {
                                    val custom = CaptureLists.wbCustomFromStatus(status)
                                    model.setWhiteBalance(custom.first, custom.second)
                                }
                            }
                        }
                        1 ->
                            Box(Modifier.wrapContentHeight().fillMaxWidth()) {
                                commonDrum()
                            }
                        else -> {
                            CaptureDrumWheel(
                                options = (-100..100).map(CaptureLists::tintLabel),
                                selection = CaptureLists.tintLabel(CaptureLists.currentTint(status)),
                                interactive = enabled,
                            ) { label ->
                                val value = label.replace('−', '-').removePrefix("+").toIntOrNull()
                                    ?: return@CaptureDrumWheel
                                if (CaptureLists.wbTintStaysAuto(status)) model.setWhiteBalanceAuto(value)
                                else model.setWhiteBalance(CaptureLists.currentKelvin(status), value)
                            }
                        }
                    }
                }
                LiveSheet.FOCUS -> {
                    if (model.monitorLayout().focus) {
                        FocusBody(
                            status = status,
                            enabled = enabled,
                            onSelect = { label ->
                                val field = commonField
                                val editor = field?.editor
                                if (editor != null && model.control.isCurrent(editor) && enabled) {
                                    val value = commonFocusValue(label,
                                        com.opencapture.opencine.vocabulary.FocusTrackMode.fromRaw(status.focusTrack))
                                    if (value != null) model.control.commit(value, editor, "FOCUS $label")
                                    else applyCaptureFocusChoice(label, status, model)
                                }
                            },
                        )
                    }
                }
                LiveSheet.APERTURE -> {
                    if (model.monitorLayout().iris) {
                        CheckedRows(
                            options = CaptureLists.apertureLabels(status),
                            selected = ApertureStrategy.label(status.apertureStrategy),
                            enabled = enabled,
                        ) { label ->
                            CaptureLists.apertureFromLabel(label)?.let(model::setApertureStrategy)
                        }
                    }
                }
                LiveSheet.EXPO -> {
                    val aeLocked = model.session.aeLock.collectAsState().value != null
                    CheckedRows(
                        options = CaptureLists.expoLabels(aeLocked),
                        selected = CaptureLists.expoSelectedLabel(status.expoMode, aeLocked),
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

                        onSelect = {
                            drumSelection = it
                            applyDrum(it)
                        },
                    )
                LiveSheet.FORMAT ->
                    androidx.compose.runtime.key(selectedMode) {
                        CaptureDrumWheel(
                            options = CaptureLists.formatDrumLabels(status, selectedMode, selectedAspect),
                            selection = drumSelection,
                            interactive = enabled && CaptureLists.formatPickerEditable(status),

                            onSelect = {
                                drumSelection = it
                                applyDrum(it)
                            },
                        )
                    }
                LiveSheet.MODE -> {
                    val labels = CaptureLists.shootingModeLabels(bodyName, status.shootingMode)
                    CaptureDrumWheel(
                        options = labels,
                        selection = CameraCommands.shootingModeLabel(status.shootingMode, bodyName).orEmpty()
                            .takeIf { it in labels }.orEmpty(),
                        interactive = enabled && !status.isRecording,
                        onSelect = {
                            drumSelection = it
                            applyDrum(it)
                        },
                    )
                    if (status.isRecording) Text("Stop recording to change mode.",
                        color = LiveDesign.muted, style = LiveType.text(11f))
                }
            }
            if (!compact) {
                if (sheet == LiveSheet.FORMAT && formatAspects.size > 1 &&
                    CaptureLists.formatPickerEditable(status)
                ) {
                    ModeBar(
                        tabs = formatAspects.map { it.label },
                        selected = formatAspects.indexOf(selectedAspect).coerceAtLeast(0),
                        enabled = enabled,
                        uppercase = false,
                    ) { index ->
                        formatAspects.getOrNull(index)?.let(::handleAspectChange)
                    }
                }
                if (tabs.isNotEmpty()) {
                    ModeBar(
                        tabs = tabs,
                        selected = selectedMode,
                        enabled = enabled &&
                            (sheet != LiveSheet.FORMAT || CaptureLists.formatPickerEditable(status)),
                    ) { index ->
                        selectedMode = index
                        handleModeChange(index)
                        if (sheet == LiveSheet.SHUTTER && !isEvSheet) reseatShutter()
                    }
                }
                if (com.opencapture.monitorui.MonitorLayoutPolicy.showsRecordingCategoryTabs(portrait, compact)) {
                    footer?.invoke()
                }
                if (com.opencapture.monitorui.MonitorLayoutPolicy.showsCaptureGrabber(compact, fromTop)) {
                    com.opencapture.monitorui.MonitorPanelGrabber()
                }
            }
    }
}

/**
 * Camera values sit on the bottom-center well; recording categories hang from
 * the top edge. Outside taps dismiss the persistent drawer.
 */
@Composable
fun LivePickerHost(
    sheet: LiveSheet,
    viewportWidth: Float,
    viewportHeight: Float,
    safeLeading: Float,
    safeTrailing: Float,
    safeTop: Float,
    safeBottom: Float,
    floorY: Float?,
    model: AppModel,
    status: CameraStatus,
    locked: Boolean,
    onSelect: (LiveSheet?) -> Unit,
    ceilingY: Float? = null,
) {
    val density = LocalDensity.current
    var panelHeight by remember(sheet) { mutableFloatStateOf(LiveChromeMetrics.DRUM_PICKER_HEIGHT) }
    val fromTop = sheet.isTopAnchored
    val portrait = viewportHeight > viewportWidth
    val place = if (fromTop) {
        LivePopupPlacement.topCapturePanel(panelHeight, viewportWidth, viewportHeight,
            safeLeading, safeTrailing, safeTop, safeBottom, ceilingY, floorY)
    } else {
        LivePopupPlacement.bottomCapturePanel(panelHeight, viewportWidth, viewportHeight,
            safeLeading, safeTrailing, safeTop, safeBottom, floorY)
    }
    Box(
        Modifier
            .fillMaxWidth()
            .fillMaxHeight(),
    ) {
        com.opencapture.monitorui.MonitorReadoutDismissBackdrop(onDismiss = { onSelect(null) })
        androidx.compose.runtime.key(sheet) {
            com.opencapture.monitorui.MonitorCaptureReveal(
                Modifier
                    .offset(place.x.dp, place.y.dp)
                    .width(place.width.dp)
                    .heightIn(max = place.maxHeight.dp)
                    .onSizeChanged { panelHeight = it.height / density.density },
                fromTop = fromTop,
            ) {
                androidx.compose.runtime.key(sheet) {
                    LiveControlSheet(
                        sheet,
                        model,
                        status,
                        locked,
                        onDismiss = { onSelect(null) },
                        maxHeightDp = place.maxHeight,
                        portrait = portrait,
                    )
                }
            }
        }
    }
}

@Composable
private fun viewportIsPortrait(): Boolean = LocalViewportPortrait.current

private fun capturePanelShape(fromTop: Boolean, portrait: Boolean): RoundedCornerShape {
    val top = com.opencapture.monitorui.MonitorLayoutPolicy.capturePanelTopCorner(fromTop, portrait).dp
    val bottom = com.opencapture.monitorui.MonitorLayoutPolicy.capturePanelBottomCorner(fromTop, portrait).dp
    return RoundedCornerShape(topStart = top, topEnd = top, bottomStart = bottom, bottomEnd = bottom)
}

@Composable
private fun SheetHeader(title: String, subtitle: String, onClose: () -> Unit,
    showsClose: Boolean = true) {
    val interactive = LocalCapturePreview.current == null
    Row(
        Modifier.fillMaxWidth().then(
            if (!showsClose) Modifier.height(com.opencapture.monitorui.MonitorLayoutPolicy.CAPTURE_HEADER_HEIGHT.dp)
            else Modifier,
        ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Text(
                title,
                style = LiveType.ui(9f, FontWeight.SemiBold).copy(letterSpacing = 1.8.sp),
                maxLines = 1,
            )
            Text(
                subtitle.uppercase(),
                style = LiveType.ui(8.5f).copy(letterSpacing = 1.19.sp),
                color = LiveDesign.faint,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(bottom = 2.dp),
            )
        }
        if (showsClose) {
            Box(Modifier.size(44.dp).chromeClickable(enabled = interactive, onClick = { if (interactive) onClose() })
                .semantics { contentDescription = "Close camera control" }, contentAlignment = Alignment.Center) {
                OpcIcon(OpcIcon.X, null, Modifier.size(13.dp), LiveDesign.muted)
            }
        }
    }
}

@Composable
private fun ModeBar(
    tabs: List<String>,
    selected: Int,
    enabled: Boolean,
    uppercase: Boolean = true,
    onSelect: (Int) -> Unit,
) {
    val haptics = LocalOperatorHaptics.current
    Row(Modifier.fillMaxWidth().monitorTabStrip()) {
        tabs.forEachIndexed { index, title ->
            val active = index == selected
            MonitorTab(active, { haptics.selection(); onSelect(index) }, Modifier.weight(1f), enabled = enabled,
                separator = index > 0, accessibilityLabel = title, horizontalPadding = 0.dp) {
                Text(if (uppercase) title.uppercase() else title,
                    style = LiveType.ui(11f, FontWeight.SemiBold).copy(letterSpacing = .44.sp),
                    color = if (active) LiveDesign.accent else LiveDesign.muted, maxLines = 1,
                    textAlign = TextAlign.Center)
            }
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
    var shown by remember(options) { mutableStateOf(selected.orEmpty()) }
    LaunchedEffect(selected) {
        if (!selected.isNullOrEmpty() && selected != shown) shown = selected
    }
    CaptureDrumWheel(options, shown, interactive = enabled, onSelect = { value ->
        if (value != shown) {
            shown = value
            onSelect(value)
        }
    })
}


@Composable
private fun FocusBody(status: CameraStatus, enabled: Boolean, onSelect: (String) -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        CaptureDrumWheel(CaptureFocusChoices.labels, CaptureFocusChoices.selection(status), interactive = enabled, onSelect = onSelect)
        Text("AF-S focuses once. AF-C follows focus continuously; Showcase, Lock and Priority use the camera's supported tracking modes.",
            style = LiveType.ui(9.5f).copy(lineHeight = 13.3.sp), color = LiveDesign.faint)
    }
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
private fun PrefToggle(
    title: String,
    help: String,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val preview = LocalCapturePreview.current
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp)
        .chromeClickable(enabled = enabled && preview == null) { if (enabled && preview == null) onCheckedChange(!checked) }
        .semantics { role = Role.Switch }.alpha(if (enabled || preview != null) 1f else .45f),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = LiveType.ui(11.5f, FontWeight.SemiBold))
            Text(help, style = LiveType.ui(9.5f).copy(lineHeight = 13.3.sp), color = LiveDesign.faint)
        }
        CaptureSwitchGraphic(checked)
    }
}

@Composable
private fun CaptureSwitchGraphic(isOn: Boolean) {
    Box(
        Modifier
            .width(38.dp)
            .height(22.dp)
            .clip(RoundedCornerShape(50))
            .background(if (isOn) LiveDesign.accentDim else LiveDesign.surface)
            .border(1.dp, if (isOn) LiveDesign.accentDim else LiveDesign.hairline, RoundedCornerShape(50)),
    ) {
        Box(
            Modifier
                .align(if (isOn) Alignment.CenterEnd else Alignment.CenterStart)
                .padding(2.dp)
                .size(18.dp)
                .clip(CircleShape)
                .background(LiveDesign.text),
        )
    }
}

/** Camera mapping stays above this shared, presentation-only horizontal drum. */
@Composable
private fun CaptureDrumWheel(
    options: List<String>, selection: String, markedValues: Set<String> = emptySet(),
    interactive: Boolean = true,
    onSelect: (String) -> Unit,
) {
    val haptics = LocalOperatorHaptics.current
    val preview = LocalCapturePreview.current
    com.opencapture.monitorui.MonitorValueDrum(
        preview?.control?.options ?: options, preview?.selection ?: selection,
        markedValues = preview?.control?.marked ?: markedValues,
        interactive = interactive && preview == null, displayPosition = preview?.position,
        dimDisabled = preview == null, onDetent = { haptics.confirm() },
        onSelect = { value -> if (interactive && preview == null) onSelect(value) },
    )
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
        LiveSheet.SHUTTER ->
            if (!isEvSheet && model.shutterUsesAngle && !CameraCommands.isPhotoMode(status.shootingMode)) 1
            else 0
        LiveSheet.WB -> CaptureLists.wbInitialTab(status, model.session.awbLockKelvin.value != null)
        LiveSheet.FORMAT -> {
            val format = VideoFormat.current(status)
            CaptureLists.formatResolutions(status).indexOf(format.resolution).coerceAtLeast(0)
        }
        else -> 0
    }
