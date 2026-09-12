package com.opencapture.openpocketcine

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import com.opencapture.openpocketcine.assists.AssistToolGlyph
import com.opencapture.openpocketcine.assists.LiveAssistBar
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.session.CamFov
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.math.max
import kotlin.math.min

data class PortraitZones(
    val topBar: ChromeRect,
    val feed: ChromeRect,
    val assistToolbar: ChromeRect,
    val controls: ChromeRect,
    val systemBar: ChromeRect,
)

object LivePortraitMetrics {
    val TOP_BAR get() = 44f * LiveChromeMetrics.scale
    val TOP_BAR_LIFT get() = 8f * LiveChromeMetrics.scale
    val SYSTEM_BAR get() = 100f * LiveChromeMetrics.scale
    val SYSTEM_BAR_LIFT get() = 14f * LiveChromeMetrics.scale
    val CAPTURE get() = 64f * LiveChromeMetrics.scale
    val ASSIST get() = 58f * LiveChromeMetrics.scale
    val TOGGLE get() = 40f * LiveChromeMetrics.scale
    val TOGGLE_GAP get() = 8f * LiveChromeMetrics.scale
    val ASSIST_RAIL_EXPANDED get() = 60f * LiveChromeMetrics.scale
    val ASSIST_RAIL_COLLAPSED get() = 44f * LiveChromeMetrics.scale
    val ASSIST_RAIL_EDGE get() = 10f * LiveChromeMetrics.scale
    val REC_OPTIONS get() = 40f * LiveChromeMetrics.scale
    val REC_OPTIONS_INSET get() = 10f * LiveChromeMetrics.scale
    val REC_OPTIONS_GAP get() = 8f * LiveChromeMetrics.scale

    val FIT_BELOW_FEED_SLOT: Float
        get() =
            max(
                TOGGLE_GAP + TOGGLE,
                LiveChromeMetrics.STICK_GAP + LiveChromeMetrics.ZOOM + LiveChromeMetrics.STICK_GAP +
                    LiveChromeMetrics.STICK + LiveChromeMetrics.STICK_INSET,
            )
}

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

fun portraitZones(
    viewportWidth: Float,
    viewportHeight: Float,
    safeTop: Float,
    safeBottom: Float,
    clean: Boolean,
    fill: Boolean,
    assistToolbarHeight: Float,
    feedAspectRatio: Float = 16f / 9f,
): PortraitZones {
    val layout = com.opencapture.monitorui.MonitorLayoutPolicy.portrait(
        viewportWidth, viewportHeight, safeTop, safeBottom, fill, !clean, feedAspectRatio,
    )
    fun com.opencapture.monitorui.MonitorRect.chrome() = ChromeRect(x, y, width, height)
    return PortraitZones(layout.status.chrome(), layout.picture.chrome(),
        ChromeRect(0f, layout.controlsFloor, viewportWidth, 0f), layout.values.chrome(), layout.system.chrome())
}

/**
 * iOS `LiveViewScreen` fillCrop: landscape fill over-widens a 16:9 picture to
 * the well height, then clips to the well (center crop). Vertical Pocket fill
 * stays the pillarboxed 9:16 picture and does not use this.
 */
fun portraitFillCropContent(well: ChromeRect): ChromeRect {
    val contentWidth = well.height * 16f / 9f
    return ChromeRect(well.midX - contentWidth / 2f, well.minY, contentWidth, well.height)
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

fun portraitAspectToggle(picture: ChromeRect, floorY: Float): ChromeRect {
    val size = 48f
    val y = max(picture.minY, floorY - 8f - size)
    return ChromeRect(picture.midX - size / 2, y, size, size)
}

fun portraitOnFeedControls(
    picture: ChromeRect,
    fill: Boolean,
    bottomClearance: Float,
    floorY: Float,
    showGimbalButton: Boolean = false,
): GimbalCluster {
    // The floor belongs to the camera-values strip, independent of fit/fill.
    val floor = max(picture.minY + 156f, floorY)
    val well = ChromeRect(picture.minX, picture.minY, picture.width, max(0f, floor - picture.minY))
    return GimbalCluster.inTrailingBottom(well, floor - 16f, floor,
        showGimbalButton = showGimbalButton)
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
    fpsLabel: String = "—",
    bars: Int = 0,
    sourceIsVertical: Boolean = false,
    capabilities: com.opencapture.monitorui.MonitorCapabilities = model.monitorCapabilities(status),
    onTileFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
) {
    val fill = sourceIsVertical || model.portraitFeedAspect == PortraitFeedAspect.FILL
    val tablet = min(layout.viewportWidth, layout.viewportHeight) >= 600f
    val editing = model.chromeEditorMode
    val showsStatus = model.chromeSectionMounts(PocketDispSection.STATUS_BAR)
    val showsLock = model.chromeSectionMounts(PocketDispSection.LOCK_BUTTON) || uiLocked
    val showsRecord = model.chromeSectionMounts(PocketDispSection.RAIL_RECORD) || status.isRecording
    val showsMedia = model.chromeSectionMounts(PocketDispSection.RAIL_MEDIA)
    val showsSettings = model.chromeSectionMounts(PocketDispSection.RAIL_SETTINGS) || status.isRecording
    val showsAssist = model.chromeSectionMounts(PocketDispSection.TOOL_BAR)
    val showsCapture = model.chromeSectionMounts(PocketDispSection.CAMERA_VALUES)
    val captureH = if (showsCapture) zones.controls.height else 0f
    val floorY = zones.controls.minY - 8f
    val showGimbalButton =
        capabilities.gimbal && model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK)
    val cluster =
        portraitOnFeedControls(
            picture = if (tablet) ChromeRect(0f, layout.onFeed.minY, layout.viewportWidth, layout.onFeed.height) else layout.onFeed,
            fill = fill,
            bottomClearance = captureH + 10f,
            floorY = floorY,
            showGimbalButton = showGimbalButton,
        )
    val stick = cluster.stick
    val zoom = cluster.zoom
    val gimbalButton = cluster.controls
    val toggle = portraitAspectToggle(layout.onFeed, floorY)
    val rail = ChromeRect(if (tablet) 14f else zones.feed.minX + 10f, floorY - if (tablet) 102f else 94f,
        if (tablet) 60f else 52f, if (tablet) 86f else 78f)

    Box(Modifier.fillMaxSize()) {
        if (showsStatus) {
            val gaugeTop = if (tablet) 82f else max(4f, zones.topBar.minY - 16f)
            Box(Modifier.liveModuleFrame(ChromeRect(if (tablet) 14f else layout.viewportWidth - 118f,
                gaugeTop, if (tablet) 46f else 104f, if (tablet) 54f else 28f))) {
                com.opencapture.openpocketcine.monitor.MonitorTelemetry(bars, fpsLabel,
                    model.phoneBatteryPercent, status.batteryPercent, horizontal = !tablet)
            }
            if (model.chromeSectionMounts(PocketDispSection.STORAGE)) {
                Row(Modifier.liveModuleFrame(ChromeRect(14f, if (tablet) 52f else gaugeTop, 120f, 28f)),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    SdCardGlyph(LiveDesign.text)
                    Text(portraitStorageLabel(status).substringBefore(" ·"), style = LiveType.mono(13.5f, FontWeight.SemiBold))
                }
            }
            val lineY = if (tablet) 8f else max(max(zones.topBar.minY + 20f, gaugeTop + 36f), zones.feed.minY + 8f)
            Box(Modifier.liveModuleFrame(ChromeRect(0f, lineY, layout.viewportWidth, 28f)), contentAlignment = Alignment.Center) {
                if (capabilities.timecode && model.chromeSectionMounts(PocketDispSection.TIMECODE)) TimecodeReadout(status.timecode)
                if (model.chromeSectionMounts(PocketDispSection.REC_READOUT)) {
                    Box(Modifier.align(Alignment.CenterStart).padding(start = 14.dp)) { RecChip(status.isRecording, status.recordElapsedSec) }
                }
                Text("REC SETUP", style = LiveType.ui(13f, FontWeight.Medium),
                    modifier = Modifier.align(Alignment.CenterEnd).padding(end = 14.dp)
                        .chromeClickable(enabled = !uiLocked && chromeInteractive) { onSheet(LiveSheet.FORMAT) })
            }
        }

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
                )
            }
        }

        if (showsCapture && zones.controls.height > 1f) {
            Box(
                Modifier
                    .liveModuleFrame(zones.controls)
                    .alpha(if (uiLocked) 0.4f else 1f)
                    .chromeEditStroke(editing != null, true),
                contentAlignment = Alignment.Center,
            ) {
                LiveCaptureStrip(
                    status = status,
                    model = model,
                    active = sheet,
                    enabled = !uiLocked && !controlBusy && chromeInteractive,
                    showFocus =
                        capabilities.focus,
                    facePriority = model.facePriorityExposureEnabled,
                    shutterUsesAngle = model.shutterUsesAngle,
                    onOpen = { if (!uiLocked) onSheet(if (sheet == it) null else it) },
                    onTileFrame = onTileFrame,
                )
            }
        }

        if (editing == null && !sourceIsVertical) {
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

        if (capabilities.zoom && model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP)) {
            val zoomReadout by model.session.zoomReadout.collectAsState()
            val zoomPinching by model.session.zoomPinching.collectAsState()
            val zoomBlocked =
                CamFov.zoomNeedsColorHopWhileRecording(
                    model.session.zoomNextJump(),
                    status.colorMode,
                    status.isRecording,
                )
            LiveZoomChip(
                factor = zoomReadout,
                locked = uiLocked,
                pinching = zoomPinching,
                dimmed = zoomBlocked,
                modifier =
                    Modifier
                        .liveModuleFrame(zoom)
                        .alpha(if (uiLocked || zoomBlocked) 0.4f else 1f)
                        .chromeEditStroke(editing != null, true),
                onCycle = {
                    model.session.setZoom(model.session.zoomNextJump())
                },
                maximum = model.session.zoomMax(),
                opticalStops = if (3.0 in model.session.zoomStops()) listOf(1.0, 3.0) else listOf(1.0),
                onDial = model.session::updateZoomPinch,
                onDialEnd = model.session::endZoomPinch,
                dialForeground = {
                    if (showsRecord) {
                        val diameter = if (tablet) 84f else LiveChromeMetrics.RECORD
                        Box(Modifier.liveModuleFrame(ChromeRect(layout.viewportWidth / 2f - diameter / 2f,
                            zones.systemBar.midY - diameter / 2f, diameter, diameter))) {
                            RecordButton(status.isRecording, !controlBusy, Modifier.fillMaxSize(),
                                confirm = model.recordConfirmationEnabled,
                                photo = CameraCommands.isPhotoMode(status.shootingMode), onClick = model::pressShutter)
                        }
                    }
                },
            )
        }

        if (showGimbalButton && !gimbalButton.isEmpty) {
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
            Box(Modifier.liveModuleFrame(stick).chromeEditStroke(editing != null, true)) {
                LiveGimbalStick(
                    enabled = !uiLocked && model.liveOperatorPanel == null && chromeInteractive,
                    onMove = model::updateGimbalStick,
                    onRelease = model::endGimbalStick,
                    onRecenter = { model.session.recenterGimbal() },
                    onFlip = { model.session.flipGimbal() },
                )
            }
        }
        if (showGimbalButton && chromeInteractive && !uiLocked && model.liveOperatorPanel == null) {
            LiveGimbalOverlay(
                model = model,
                layout = layout,
                feed = layout.onFeed,
                uiLocked = uiLocked,
            )
        }

        Box(
            Modifier
                .fillMaxWidth()
                .liveModuleFrame(
                    ChromeRect(
                        0f,
                        zones.systemBar.minY,
                        layout.viewportWidth,
                        max(0f, layout.viewportHeight - zones.systemBar.minY),
                    ),
                )
                .background(LiveDesign.background),
        )

        Box(Modifier.liveModuleFrame(zones.systemBar)) {
            LivePortraitSystemBar(
                model = model,
                assist = assist,
                status = status,
                uiLocked = uiLocked,
                onLock = onLock,
                chromeInteractive = chromeInteractive,
                showsLock = showsLock,
                showsRecord = showsRecord,
                showsMedia = showsMedia,
                showsSettings = showsSettings,
                controlBusy = controlBusy,
            )
        }
    }
}

@Composable
fun LivePortraitTopBar(model: AppModel, status: CameraStatus) {
    Box(Modifier.fillMaxSize().background(LiveDesign.glass)) {
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
fun LivePortraitSystemBar(
    model: AppModel,
    assist: LiveAssistState,
    status: CameraStatus,
    uiLocked: Boolean,
    onLock: () -> Unit,
    chromeInteractive: Boolean,
    showsLock: Boolean,
    showsRecord: Boolean,
    showsMedia: Boolean,
    showsSettings: Boolean,
    controlBusy: Boolean,
) {
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    val tablet = min(configuration.screenWidthDp, configuration.screenHeightDp) >= 600
    if (tablet) {
        Box(Modifier.fillMaxSize().padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
            Row(Modifier.align(Alignment.CenterStart), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (showsLock) LockButton(uiLocked, Modifier.size(48.dp), onClick = onLock)
                if (chromeInteractive) DispButton(clean = model.assistClean, modifier = Modifier.size(48.dp), onClick = {
                    if (!uiLocked) { val clean = !model.assistClean; model.setDisplayMode(clean); assist.clean = clean }
                })
            }
            if (showsRecord) RecordButton(status.isRecording, !controlBusy, Modifier.size(84.dp),
                confirm = model.recordConfirmationEnabled, photo = CameraCommands.isPhotoMode(status.shootingMode),
                onClick = model::pressShutter)
            Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (showsSettings) AuxCircleButton(Modifier.size(48.dp), onClick = { model.liveOperatorPanel = LiveOperatorPanel.SETTINGS }) {
                    OpcIcon(OpcIcon.SETTINGS, "Settings", Modifier.fillMaxSize(), it)
                }
                if (showsMedia) AuxCircleButton(Modifier.size(48.dp), onClick = { model.liveOperatorPanel = LiveOperatorPanel.MEDIA }) {
                    OpcIcon(OpcIcon.FILM, "Media", Modifier.fillMaxSize(), it)
                }
            }
        }
        return
    }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.weight(1f).fillMaxHeight(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(Modifier.weight(1f))
                if (showsLock) {
                    LockButton(uiLocked, onClick = onLock)
                    Spacer(Modifier.weight(1f))
                }
                if (chromeInteractive) {
                    DispButton(
                        clean = model.assistClean,
                        onClick = {
                            if (!uiLocked) {
                                val next = !model.assistClean
                                model.setDisplayMode(next)
                                assist.clean = next
                            }
                        },
                    )
                    Spacer(Modifier.weight(1f))
                }
            }
            if (showsRecord) Spacer(Modifier.width(LiveChromeMetrics.RECORD.dp))
            Row(
                Modifier.weight(1f).fillMaxHeight(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(Modifier.weight(1f))
                if (showsSettings) {
                    AuxCircleButton(onClick = { model.liveOperatorPanel = LiveOperatorPanel.SETTINGS }) {
                        OpcIcon(OpcIcon.SETTINGS, contentDescription = "Settings", tint = it, modifier = Modifier.fillMaxSize())
                    }
                    Spacer(Modifier.weight(1f))
                }
                if (showsMedia) {
                    AuxCircleButton(onClick = { model.liveOperatorPanel = LiveOperatorPanel.MEDIA }) {
                        OpcIcon(OpcIcon.FILM, contentDescription = "Media", tint = it, modifier = Modifier.fillMaxSize())
                    }
                    Spacer(Modifier.weight(1f))
                }
            }
        }
        if (showsRecord) {
            RecordButton(
                recording = status.isRecording,
                enabled = !controlBusy,
                confirm = model.recordConfirmationEnabled,
                photo = CameraCommands.isPhotoMode(status.shootingMode),
                onClick = model::pressShutter,
            )
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
        Text(
            if (fill) "FILL" else "FIT",
            color = if (fill) LiveDesign.accent else LiveDesign.text,
            style = LiveType.ui(9f, FontWeight.Bold),
            maxLines = 1,
        )
    }
}

@Composable
fun LiveCaptureStrip(
    status: CameraStatus,
    active: LiveSheet?,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    showFocus: Boolean = true,
    facePriority: Boolean = false,
    shutterUsesAngle: Boolean = false,
    onOpen: (LiveSheet) -> Unit,
    onTileFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
    model: AppModel? = null,
) {
    val context = LocalContext.current
    val auto = status.expoMode == CameraCommands.EXPO_AUTO
    val shutter = if (shutterUsesAngle) {
        ShutterAngle.label(ShutterAngle.nearestDegrees(OperatorPrefs.shutterAngleDegrees(context)))
    } else status.shutterLabel
    fun value(sheet: LiveSheet, label: String, readout: String, annotation: String? = null) =
        com.opencapture.openpocketcine.monitor.MonitorValue(
            sheet.name, label, readout, selected = active == sheet, annotation = annotation,
        )
    val values = buildList {
        add(value(LiveSheet.ISO, "ISO", CaptureLists.isoChipValue(status)))
        add(value(LiveSheet.SHUTTER, if (auto) "EV" else "SHUTTER",
            if (auto) EvComp.fromRaw(status.evComp)?.label ?: "—" else shutter,
            if (auto && facePriority) "FACE" else null))
        add(value(LiveSheet.EXPO, "EXPOSURE", if (status.expoMode == CameraCommands.EXPO_MANUAL) "M" else if (auto) "A" else "—"))
        add(value(LiveSheet.WB, "WB", CaptureLists.wbChipValue(status)))
        if (showFocus) add(value(LiveSheet.FOCUS, "FOCUS", status.focusLabel))
        add(value(LiveSheet.AUDIO, "AUDIO", status.audioLabel))
    }
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    com.opencapture.openpocketcine.monitor.MonitorCameraValues(
        values = values,
        enabled = enabled,
        portrait = configuration.screenHeightDp > configuration.screenWidthDp,
        modifier = modifier,
        quickControl = { id -> model?.let { captureQuickControl(LiveSheet.valueOf(id), status, it, context) } },
        onQuickCommit = { id, value -> if (enabled) model?.let { applyCaptureQuickControl(LiveSheet.valueOf(id), value, status, it, context) } },
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
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(vertical = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            val tools = LiveAssistTool.toolbarCases + LiveAssistTool.AUDIO
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
                Column(Modifier.width(220.dp).background(LiveDesign.glass)) {
                    RecOptionsRow("Resolution · Framerate") {
                        open = false
                        onOpen(LiveSheet.FORMAT)
                    }
                    Box(Modifier.fillMaxWidth().height(1.dp).background(LiveDesign.hairline))
                    RecOptionsRow("Color") {
                        open = false
                        onOpen(LiveSheet.COLOR)
                    }
                }
            }
        }
    }
}

@Composable
private fun RecOptionsRow(title: String, onClick: () -> Unit) {
    Text(
        title,
        color = LiveDesign.text,
        style = LiveType.ui(14f, FontWeight.Medium),
        maxLines = 1,
        modifier =
            Modifier
                .fillMaxWidth()
                .chromeClickable(onClick = onClick)
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
