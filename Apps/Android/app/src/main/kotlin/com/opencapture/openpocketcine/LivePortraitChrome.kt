package com.opencapture.openpocketcine

import com.opencapture.monitorui.PortraitZones
import com.opencapture.monitorui.portraitAspectToggle
import com.opencapture.monitorui.portraitAssistToolbar
import com.opencapture.monitorui.livePortraitReadoutFrame
import com.opencapture.monitorui.LivePortraitMetrics
import com.opencapture.opencine.dji.CaptureShutterPolicy
import com.opencapture.opencine.dji.EvComp
import com.opencapture.monitorui.MonitorExposureReadout
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import com.opencapture.opencine.appkit.statusPresentation
import com.opencapture.monitorui.monitorReadoutShadow
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import com.opencapture.monitorui.MonitorQuickGestureOwner
import com.opencapture.monitorui.monitorReadoutGesture
import com.opencapture.monitorui.monitorPickerPassthrough
import com.opencapture.monitorui.monitorScrollFade
import com.opencapture.openpocketcine.assists.AssistToolGlyph
import com.opencapture.openpocketcine.assists.LiveAssistBar
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.opencine.dji.ApertureStrategy
import com.opencapture.opencine.dji.CamFov
import com.opencapture.opencine.dji.CameraCommands
import com.opencapture.opencine.dji.CameraStatus
import kotlin.math.max
import kotlin.math.min

fun liveFitFeedOriginY(
    viewportHeight: Float,
    feedHeight: Float,
    topBarMaxY: Float,
    chromeFloorY: Float,
    belowFeedSlot: Float = LivePortraitMetrics.FIT_BELOW_FEED_SLOT,
): Float {
    val height = max(0f, feedHeight)
    val top = max(0f, topBarMaxY)
    val keepClear = chromeFloorY - max(0f, belowFeedSlot)
    val ideal = (max(0f, viewportHeight) - height) / 2f
    val latest = max(top, keepClear - height)
    return min(max(ideal, top), latest)
}

fun fillAssistRail(
    feed: ChromeRect,
    captureStripTop: Float?,
    expanded: Boolean,
): ChromeRect {
    val edge = LivePortraitMetrics.ASSIST_RAIL_EDGE
    val feedBottom = feed.maxY
    val railBottom = captureStripTop?.let { min(max(it, feed.minY), feedBottom) } ?: feedBottom
    val top = feed.minY + edge
    val width =
        if (expanded) LivePortraitMetrics.ASSIST_RAIL_EXPANDED else LivePortraitMetrics.ASSIST_RAIL_COLLAPSED
    val height =
        if (expanded) max(0f, railBottom - top - edge) else LivePortraitMetrics.ASSIST_RAIL_COLLAPSED
    val y = if (expanded) top else max(top, railBottom - height - edge)
    return ChromeRect(feed.minX + edge, y, width, height)
}

@Composable
fun LivePortraitChrome(
    model: AppModel,
    layout: LiveMonitorLayout,
    zones: PortraitZones,
    status: CameraStatus,
    uiLocked: Boolean,
    onLock: () -> Unit,
    sheet: LiveSheet?,
    onSheet: (LiveSheet?) -> Unit,
    assist: LiveAssistState,
    onAssistLongPress: (LiveAssistTool) -> Unit,
    chromeInteractive: Boolean,
    controlBusy: Boolean,
    focusOffCenter: Boolean,
    onFocusReset: () -> Unit,
    fpsLabel: String = "—",
    bars: Int = 0,
    sourceIsVertical: Boolean = false,
    capabilities: com.opencapture.opencine.core.MonitorLayoutCapabilities = model.monitorLayout(),
    onTileFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
    readoutFrame: ChromeRect = livePortraitReadoutFrame(layout, zones),
    onAssistBoundsChanged: (ChromeRect?) -> Unit = {},
    captureQuickActive: Boolean = false,
) {
    val captureOpen = sheet != null || captureQuickActive
    val desqueezeVisible = assist.isVisible(LiveAssistTool.DESQ)
    val fill = sourceIsVertical || (!desqueezeVisible && model.portraitFeedAspect == PortraitFeedAspect.FILL)
    val tablet = min(layout.viewportWidth, layout.viewportHeight) >= 600f
    val editing = model.chromeEditorMode
    val showsAssist = model.chromeSectionMounts(PocketDispSection.TOOL_BAR) &&
        model.liveOperatorPanel == null && assist.configureTool == null

    val floorY = zones.assistToolbar.minY
    val showGimbalButton =
        capabilities.gimbal && model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK)
    val cluster = layout.gimbalCluster(showGimbalButton)
    val stick = cluster.stick
    val zoom = cluster.zoom
    val gimbalButton = cluster.controls
    val toggle = portraitAspectToggle(layout.viewportWidth, floorY)
    val rail = portraitAssistToolbar(floorY, tablet)

    Box(Modifier.fillMaxSize()) {
        if (showsAssist) {
            Box(
                Modifier
                    .liveModuleFrame(rail)
                    .alpha(if (uiLocked) 0.4f else 1f)
                    .chromeEditStroke(editing != null, true),
            ) {
                com.opencapture.openpocketcine.assists.MonitorAssistCluster(
                    portrait = true, locked = uiLocked || !chromeInteractive,
                    isOn = assist::isOn, onToggle = { assist.toggle(it) }, onLongPress = onAssistLongPress,
                    showsAudio = capabilities.audio && CaptureShutterPolicy.showsAudioControls(status.shootingMode),
                    onBoundsChanged = onAssistBoundsChanged,
                )
            }
        }



        if (editing == null && !sourceIsVertical && !desqueezeVisible) {
            LivePortraitAspectToggle(
                fill = fill,
                locked = uiLocked,
                modifier = Modifier.liveModuleFrame(toggle).alpha(if (uiLocked) 0.4f else 1f),
                onClick = {
                    if (!uiLocked) {
                        model.updatePortraitFeedAspect(
                            if (fill) PortraitFeedAspect.FIT_16X9 else PortraitFeedAspect.FILL,
                        )
                    }
                },
            )
        }

        if (!captureOpen && capabilities.zoom && model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP)) {
            val zoomReadout by model.session.zoomReadout.collectAsState()
            val zoomDialReadout by model.session.zoomDialReadout.collectAsState()
            val zoomPinching by model.session.zoomPinching.collectAsState()
            val zoomBlocked =
                CamFov.zoomNeedsColorHopWhileRecording(
                    model.session.zoomNextJump(),
                    status.colorMode,
                    status.isRecording,
                )
            LiveZoomChip(
                factor = commonZoomReadout(model, zoomReadout),
                dialFactor = zoomDialReadout,
                locked = uiLocked,
                pinching = zoomPinching,
                dimmed = zoomBlocked,
                modifier =
                    Modifier
                        .liveModuleFrame(zoom)
                        .alpha(if (uiLocked || zoomBlocked) 0.4f else 1f)
                        .chromeEditStroke(editing != null, true),
                onCycle = {
                    model.commitZoomCycle(LiveZoom.nextJump(model.zoomCycleFrom(), model.monitorZoomStops().primary))
                },
                onDigitalCycle = model.monitorZoomStops().secondary.takeIf { it.isNotEmpty() }?.let { stops ->
                    { model.commitZoomCycle(LiveZoom.nextJump(model.zoomCycleFrom(), stops)) }
                },
                maximum = model.session.zoomMax(),
                opticalStops = if (3.0 in model.session.zoomStops()) listOf(1.0, 3.0) else listOf(1.0),
                onDial = model::updateNativeZoomGesture,
                onDialEnd = model.session::endZoomPinch,
            )
        }

        if (!captureOpen && showGimbalButton && !gimbalButton.isEmpty) {
            LiveGimbalButton(
                locked = uiLocked,
                onClick = {
                    model.liveGimbalPanel =
                        if (model.liveGimbalPanel == LiveGimbalPanel.SHEET) LiveGimbalPanel.NONE
                        else LiveGimbalPanel.SHEET
                },
                modifier =
                    Modifier
                        .liveModuleFrame(gimbalButton)
                        .alpha(if (uiLocked) 0.4f else 1f),
            )
        }
        if (showGimbalButton) {
            Box(Modifier.liveModuleFrame(stick).alpha(if (captureOpen) 0f else 1f).chromeEditStroke(editing != null, true)) {
                LiveGimbalStick(
                    enabled = !captureOpen && !uiLocked && model.liveOperatorPanel == null && chromeInteractive,
                    onMove = model::updateGimbalStick,
                    onRelease = model::endGimbalStick,
                    onRecenter = { model.session.performGimbalDoubleTap() },
                    onFlip = { model.session.flipGimbal() },
                )
            }
        }
        if (!captureOpen && showGimbalButton && chromeInteractive && !uiLocked && model.liveOperatorPanel == null) {
            LiveGimbalOverlay(
                model = model,
                layout = layout,
                feed = layout.onFeed,
                joystickBounds = stick,
                zoomBounds = if (capabilities.zoom && model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP)) zoom
                    else ChromeRect(0f, 0f, 0f, 0f),
                uiLocked = uiLocked,
            )
        }
        // Same slot as landscape: leading of the stick, on its bottom edge (iOS `focusReset`).
        if (!uiLocked && focusOffCenter && chromeInteractive) {
            Box(Modifier.liveModuleFrame(layout.focusReset)) {
                LiveFocusResetButton(onClick = onFocusReset)
            }
        }


    }
}

@Composable
fun LivePortraitTopBar(model: AppModel, status: CameraStatus) {
    Box(Modifier.fillMaxSize().monitorMaterial(MonitorMaterial.Expanded)) {
        if (model.chromeSectionMounts(PocketDispSection.STORAGE)) {
            Text(
                portraitStorageLabel(status),
                color = LiveDesign.text,
                style = LiveType.ui(13f, FontWeight.SemiBold),
                maxLines = 1,
                modifier = Modifier.align(Alignment.Center),
            )
        }
        Row(
            Modifier.fillMaxSize().padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (model.chromeSectionMounts(PocketDispSection.TIMECODE)) {
                TimecodeReadout(status.timecode, portrait = true)
            }
            Spacer(Modifier.weight(1f))
            if (model.chromeSectionMounts(PocketDispSection.BATTERIES)) {
                CameraBatteryReadout(status.batteryPercent)
            }
        }
    }
}

@Composable
fun LivePortraitAspectToggle(
    fill: Boolean,
    locked: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(LivePortraitMetrics.TOGGLE.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.55f))
            .border(1.dp, LiveDesign.hairline, CircleShape)
            .chromeClickable(enabled = !locked, onClick = onClick)
            .semantics { contentDescription = if (fill) "Fit feed in frame" else "Fill frame with feed" },
        contentAlignment = Alignment.Center,
    ) {
        OpcIcon(if (fill) OpcIcon.MINIMIZE else OpcIcon.MAXIMIZE, null, Modifier.size(15.dp), LiveDesign.text)
    }
}

@Composable
fun LiveCaptureStrip(
    status: CameraStatus,
    active: LiveSheet?,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    showFocus: Boolean = true,
    showAperture: Boolean = false,
    showAudio: Boolean = true,
    facePriority: Boolean = false,
    shutterUsesAngle: Boolean = false,
    onOpen: (LiveSheet) -> Unit,
    onTileFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
    model: AppModel? = null,
    onQuickActiveChange: (Boolean) -> Unit = {},
    quickBottomClearanceDp: Float = 0f,
    portrait: Boolean? = null,
) {
    val context = LocalContext.current
    model?.control?.state?.collectAsState()?.value
    val auto = status.expoMode == CameraCommands.EXPO_AUTO
    val aeLocked = model?.session?.aeLock?.collectAsState()?.value != null
    val awbLocked = model?.session?.awbLockKelvin?.collectAsState()?.value != null
    val shutter = captureShutterReadout(
        status,
        shutterUsesAngle,
        OperatorPrefs.shutterAngleDegrees(context),
    )
    fun value(sheet: LiveSheet, label: String, readout: String, annotation: String? = null,
        valueIcon: OpcIcon? = null, badgeIcon: OpcIcon? = null) =
        com.opencapture.openpocketcine.monitor.MonitorValue(
            sheet.name, label, readout, selected = active == sheet, annotation = annotation,
            valueIcon = valueIcon, badgeIcon = badgeIcon,
        )
    val values = buildList {
        add(value(LiveSheet.ISO, "ISO", captureReadoutLabel(LiveSheet.ISO, status, model, CaptureLists.isoChipValue(status))))
        add(value(LiveSheet.SHUTTER,
            if (auto) MonitorExposureReadout.autoEvCaption(status.shutterDenom)
            else "SHUTTER",
            captureReadoutLabel(LiveSheet.SHUTTER, status, model, if (auto) EvComp.fromRaw(status.evComp)?.label ?: "—" else shutter),
            if (auto && facePriority) CaptureLists.FACE_PRIORITY_TITLE else null,
            badgeIcon = if (auto && facePriority) OpcIcon.SCAN else null))
        add(value(LiveSheet.EXPO, "EXPOSURE", if (aeLocked) CaptureLists.AE_LOCK
            else if (status.expoMode == CameraCommands.EXPO_MANUAL) "M" else if (auto) "A" else "—"))
        add(value(LiveSheet.WB, "WB", captureReadoutLabel(LiveSheet.WB, status, model, CaptureLists.wbChipValue(status, awbLocked)),
            valueIcon = if (CaptureLists.wbIsAuto(status) && !awbLocked) OpcIcon.APERTURE else null))
        if (showFocus) add(value(LiveSheet.FOCUS, "FOCUS", status.focusLabel))
        if (showAperture) add(value(LiveSheet.APERTURE, "APERTURE", ApertureStrategy.tileValue(status)))
        if (showAudio && CaptureShutterPolicy.showsAudioControls(status.shootingMode)) {
            add(value(LiveSheet.AUDIO, "AUDIO", status.audioLabel))
        }
    }
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    val quickLifetime = rememberCaptureQuickLifetime(model)
    val isPortrait = portrait ?: (configuration.screenHeightDp > configuration.screenWidthDp)
    com.opencapture.openpocketcine.monitor.MonitorCameraValues(
        values = values,
        enabled = enabled && quickLifetime.active,
        portrait = isPortrait,
        modifier = modifier,
        quickControl = { id -> model?.let { captureQuickControl(LiveSheet.valueOf(id), status, it, context, quickLifetime) } },
        quickPreview = { id, preview, maxHeight ->
            model?.let {
                LiveControlSheet(LiveSheet.valueOf(id), it, status, locked = false,
                    onDismiss = {}, maxHeightDp = maxHeight, preview = preview,
                    portrait = isPortrait)
            }
        },
        onQuickActiveChange = onQuickActiveChange,
        quickBottomClearanceDp = quickBottomClearanceDp,
        onQuickCommit = { id, source, value -> model?.let {
            releaseCaptureQuickControl(LiveSheet.valueOf(id), source, value, it, context, quickLifetime,
                enabled && active == null)
        } },
        onOpen = { onOpen(LiveSheet.valueOf(it)) },
        onFrame = { id, rect -> onTileFrame(LiveSheet.valueOf(id), rect) },
    )
}

/** iOS `a.circle.fill` stand-in for Auto white-balance. */
@Composable
private fun WbAutoGlyph(tint: Color, modifier: Modifier = Modifier) {
    Box(modifier.size(18.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(tint)
        }
        Text(
            "A",
            color = LiveDesign.background,
            style = LiveType.ui(10f, FontWeight.Bold),
            maxLines = 1,
        )
    }
}

@Composable
fun LivePortraitAssistRail(
    assist: LiveAssistState,
    expanded: Boolean,
    locked: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onLongPress: (LiveAssistTool) -> Unit,
    showsAudio: Boolean = true,
) {
    if (!expanded) {
        Box(
            Modifier
                .fillMaxSize()
                .clip(CircleShape)
                .monitorGlass(CircleShape)
                .chromeClickable(enabled = !locked) { onExpandedChange(true) }
                .semantics { contentDescription = "Show view assists" },
            contentAlignment = Alignment.Center,
        ) {
            SliderHorizontal3Glyph(LiveDesign.text, Modifier.size(18.dp))
        }
        return
    }
    Column(
        Modifier
            .fillMaxSize()
            .clip(ChromeShape)
            .monitorGlass()
            .padding(horizontal = 4.dp),
    ) {
        Box(
            Modifier
                .align(Alignment.CenterHorizontally)
                .size(36.dp, 28.dp)
                .chromeClickable(enabled = !locked) { onExpandedChange(false) }
                .semantics { contentDescription = "Hide view assists" },
            contentAlignment = Alignment.Center,
        ) {
            ChevronLeftGlyph(LiveDesign.accent, Modifier.size(13.dp))
        }
        val railScroll = rememberScrollState()
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .monitorScrollFade(railScroll)
                .verticalScroll(railScroll)
                .padding(vertical = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            val tools =
                if (showsAudio) LiveAssistTool.toolbarCases + LiveAssistTool.AUDIO
                else LiveAssistTool.toolbarCases
            tools.forEach { tool ->
                LivePortraitRailTool(
                    tool = tool,
                    on = assist.isOn(tool),
                    locked = locked,
                    onClick = { assist.toggle(tool) },
                    onLongPress = {
                        if (tool.hasConfiguration) onLongPress(tool)
                    },
                )
            }
        }
    }
}

@Composable
fun LivePortraitRecOptionsButton(
    locked: Boolean,
    modifier: Modifier = Modifier,
    onOpen: (LiveSheet) -> Unit,
    isPhoto: Boolean = false,
) {
    var open by remember { mutableStateOf(false) }
    val menuOffset = with(LocalDensity.current) { IntOffset(0, 8.dp.roundToPx()) }
    Box(modifier) {
        Box(
            Modifier
                .fillMaxSize()
                .clip(CircleShape)
                .monitorGlass(CircleShape)
                .chromeClickable(enabled = !locked) { open = !open }
                .semantics { contentDescription = "Recording options" },
            contentAlignment = Alignment.Center,
        ) {
            VideoGlyph(LiveDesign.text.copy(alpha = 0.86f))
        }
        if (open) {
            Popup(
                alignment = Alignment.BottomEnd,
                offset = menuOffset,
                onDismissRequest = { open = false },
            ) {
                Column(Modifier.width(220.dp).monitorMaterial(MonitorMaterial.Expanded)) {
                    if (isPhoto) {
                        LivePopupAction("Shooting mode") {
                            open = false
                            onOpen(LiveSheet.MODE)
                        }
                    } else {
                        LivePopupAction("Resolution · Framerate") {
                            open = false
                            onOpen(LiveSheet.FORMAT)
                        }
                        Box(Modifier.fillMaxWidth().height(1.dp).background(LiveDesign.hairline))
                        LivePopupAction("Color") {
                            open = false
                            onOpen(LiveSheet.COLOR)
                        }
                    }
                }
            }
        }
    }
}

/** Shared floating-menu action used by Live View and Multiview camera menus. */
@Composable
internal fun LivePopupAction(
    title: String, enabled: Boolean = true, destructive: Boolean = false,
    onClick: () -> Unit,
) {
    Text(
        title,
        color = if (destructive) LiveDesign.rec else LiveDesign.text,
        style = LiveType.ui(14f, FontWeight.Medium),
        maxLines = 2,
        modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { role = Role.Button }
            .padding(horizontal = 14.dp, vertical = 12.dp),
    )
}

@Composable
private fun LivePortraitRailTool(
    tool: LiveAssistTool,
    on: Boolean,
    locked: Boolean,
    onClick: () -> Unit,
    onLongPress: () -> Unit,
) {
    val tint = if (on) LiveDesign.accent else LiveDesign.muted
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .background(if (on) LiveDesign.accentDim else Color.Transparent, ChromeShape)
                .border(1.dp, if (on) LiveDesign.accent else Color.Transparent, ChromeShape)
                .chromeClickable(
                    enabled = !locked,
                    onLongClick = if (tool.hasConfiguration) onLongPress else null,
                    onClick = onClick,
                )
                // Portrait rail speaks the same sentence as the landscape cell.
                .clearAndSetSemantics {
                    val options = if (tool.hasConfiguration) ". Hold for options" else ""
                    contentDescription = "${tool.title}, ${if (on) "on" else "off"}$options"
                    if (locked) disabled()
                }
                .padding(vertical = 5.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        AssistToolGlyph(tool = tool, tint = tint, modifier = Modifier.size(19.dp))
        Text(
            tool.chipLabel,
            color = tint,
            fontSize = 9.sp,
            fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
            maxLines = 1,
            letterSpacing = 0.9.sp,
        )
    }
}

@Composable
private fun SliderHorizontal3Glyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val stroke = size.minDimension * 0.085f
        val knobRadius = size.minDimension * 0.09f
        val rows = listOf(0.24f, 0.5f, 0.76f)
        val knobs = listOf(0.68f, 0.34f, 0.58f)
        rows.forEachIndexed { index, rowY ->
            val y = size.height * rowY
            drawLine(
                tint,
                Offset(size.width * 0.06f, y),
                Offset(size.width * 0.94f, y),
                strokeWidth = stroke,
                cap = StrokeCap.Round,
            )
            drawCircle(tint, radius = knobRadius, center = Offset(size.width * knobs[index], y))
        }
    }
}

@Composable
private fun ChevronLeftGlyph(tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val path =
            Path().apply {
                moveTo(size.width * 0.62f, size.height * 0.22f)
                lineTo(size.width * 0.38f, size.height * 0.5f)
                lineTo(size.width * 0.62f, size.height * 0.78f)
            }
        drawPath(
            path,
            tint,
            style = Stroke(width = size.minDimension * 0.12f, cap = StrokeCap.Round),
        )
    }
}

private fun portraitStorageLabel(status: CameraStatus): String =
    CaptureLists.storageLabel(status, showDuration = false)

@Composable
internal fun LivePortraitStatus(model: AppModel, layout: LiveMonitorLayout, status: CameraStatus,
    uiLocked: Boolean, chromeInteractive: Boolean, sheet: LiveSheet?, onSheet: (LiveSheet?) -> Unit,
    fpsLabel: String, bars: Int, onQuickActivityChange: (Boolean) -> Unit) {
    val field = checkNotNull(layout.field)
    val tablet = field.tablet
    val readoutFrame = layout.topDeck
    val capabilities = model.monitorLayout()
            val recContext = LocalContext.current
            val recLifetime = rememberCaptureQuickLifetime(model)
            val recOwner = remember { MonitorQuickGestureOwner() }
            val recInteractive = !uiLocked && chromeInteractive
            val notifyTop by rememberUpdatedState<(Boolean) -> Unit> { onQuickActivityChange(it); if (it) onSheet(null) }
            LaunchedEffect(recOwner.active) { notifyTop(recOwner.active != null) }
            DisposableEffect(Unit) { onDispose { notifyTop(false) } }
    val common by model.control.state.collectAsState()
    common
    com.opencapture.monitorui.MonitorStatusChrome(field,
        model.control.statusPresentation(status.recordElapsedSec),
        showsTimecode = CaptureShutterPolicy.showsVideoTransport(status.shootingMode) && capabilities.timecode && model.chromeSectionMounts(PocketDispSection.TIMECODE),
        showsRecording = CaptureShutterPolicy.showsVideoTransport(status.shootingMode) && model.chromeSectionMounts(PocketDispSection.REC_READOUT),
        modifier = Modifier.monitorReadoutShadow(),
        storage = {
            if (model.chromeSectionMounts(PocketDispSection.STORAGE)) Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                SdCardGlyph(LiveDesign.text)
                Text(portraitStorageLabel(status).substringBefore(" ·"), style = LiveType.mono(13.5f, FontWeight.SemiBold))
            }
        }, link = {
            com.opencapture.openpocketcine.monitor.MonitorTelemetry(bars, fpsLabel,
                model.phoneBatteryPercent, status.batteryPercent, horizontal = true, showsPower = false)
        }, format = {
                val setupSheet = CaptureShutterPolicy.portraitSetupSheet(status.shootingMode)
                val setupIsMode = CaptureShutterPolicy.portraitSetupOpensMode(status.shootingMode)
                val setupValue = CaptureShutterPolicy.portraitSetupLabel(status)
                val setupCaption = CaptureShutterPolicy.portraitSetupCaption(
                    status, model.session.connectedCamera?.model?.family ?: "pocket")
                val setupTint =
                    if (sheet == setupSheet || recOwner.active == setupSheet.name) LiveDesign.accent else LiveDesign.text
                // iOS: the format sits on the timecode line at its size; the color hangs smaller below.
                Box(
                    contentAlignment = Alignment.BottomEnd,
                    modifier = Modifier
                        .monitorReadoutGesture(
                            captureQuickControl(setupSheet, status, model, recContext, recLifetime),
                            recInteractive && recLifetime.active && (recOwner.owner == null || recOwner.owner == setupSheet.name),
                            { onSheet(if (sheet == setupSheet) null else setupSheet) },
                            { source, value ->
                                releaseCaptureQuickControl(setupSheet, source, value, model, recContext, recLifetime, recInteractive)
                            },
                            0f, recOwner, setupSheet.name,
                            { preview, maxHeight ->
                                LiveControlSheet(setupSheet, model, status, locked = false,
                                    onDismiss = {}, maxHeightDp = maxHeight, preview = preview,
                                    portrait = true)
                            },
                            fromTop = true, ceilingY = readoutFrame.maxY,
                            onPreviewBegin = { notifyTop(true) },
                        )
                        .clearAndSetSemantics {
                            contentDescription = if (setupIsMode) "Shooting mode" else "Recording options"
                            stateDescription = setupValue
                        },
                ) {
                    Text(
                        setupValue,
                        color = setupTint,
                        style = if (setupIsMode) LiveType.mono(12f, FontWeight.SemiBold)
                        else LiveType.mono(if (tablet) 25f else 23f, FontWeight.Medium),
                        maxLines = 1,
                        softWrap = false,
                    )
                    if (setupCaption != null) {
                        Text(
                            setupCaption,
                            color = setupTint,
                            style = LiveType.ui(11f, FontWeight.SemiBold),
                            maxLines = 1,
                            softWrap = false,
                            modifier = Modifier.offset(y = 18.dp).wrapContentWidth(Alignment.End, unbounded = true),
                        )
                    }
                }
        })
}
