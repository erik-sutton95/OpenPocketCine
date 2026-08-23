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
    val vw = max(0f, viewportWidth)
    val vh = max(0f, viewportHeight)
    val ratio = if (feedAspectRatio > 0f) feedAspectRatio else 16f / 9f
    val topBar =
        ChromeRect(0f, max(0f, max(0f, safeTop) - LivePortraitMetrics.TOP_BAR_LIFT), vw, LivePortraitMetrics.TOP_BAR)
    val systemBottom = max(0f, max(0f, safeBottom) - LivePortraitMetrics.SYSTEM_BAR_LIFT)
    val systemBar =
        ChromeRect(
            0f,
            max(0f, vh - systemBottom - LivePortraitMetrics.SYSTEM_BAR),
            vw,
            LivePortraitMetrics.SYSTEM_BAR,
        )
    if (fill) {
        val span = max(0f, systemBar.minY - topBar.maxY)
        val feedHeight = min(vw * 16f / 9f, span)
        val feed = ChromeRect(0f, topBar.maxY, vw, feedHeight)
        val controlsHeight = if (clean) 0f else min(LivePortraitMetrics.CAPTURE, feed.height)
        val controls = ChromeRect(0f, feed.maxY - controlsHeight, vw, controlsHeight)
        return PortraitZones(
            topBar = topBar,
            feed = feed,
            assistToolbar = ChromeRect(0f, feed.maxY, vw, 0f),
            controls = controls,
            systemBar = systemBar,
        )
    }
    val natural = vw / ratio
    val spanForVertical = max(0f, systemBar.minY - topBar.maxY)
    if (clean) {
        val feedHeight = if (ratio >= 1f) natural else min(natural, spanForVertical)
        val feed = ChromeRect(0f, topBar.maxY + max(0f, (spanForVertical - feedHeight) / 2f), vw, feedHeight)
        return PortraitZones(
            topBar = topBar,
            feed = feed,
            assistToolbar = ChromeRect(0f, feed.maxY, vw, 0f),
            controls = ChromeRect(0f, feed.maxY, vw, 0f),
            systemBar = systemBar,
        )
    }
    val toolbar = max(0f, assistToolbarHeight)
    val chromeFloor = systemBar.minY - toolbar
    val feedHeight =
        if (ratio >= 1f) {
            natural
        } else {
            min(natural, max(0f, chromeFloor - topBar.maxY))
        }
    val y = liveFitFeedOriginY(vh, feedHeight, topBar.maxY, chromeFloor)
    val feed = ChromeRect(0f, y, vw, feedHeight)
    val assist = ChromeRect(0f, systemBar.minY - toolbar, vw, toolbar)
    val controls = ChromeRect(0f, feed.maxY, vw, max(0f, assist.minY - feed.maxY))
    return PortraitZones(topBar, feed, assist, controls, systemBar)
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
    val size = LivePortraitMetrics.TOGGLE
    val gap = LivePortraitMetrics.TOGGLE_GAP
    val parked = floorY - gap - size
    val y = if (floorY > picture.maxY) max(picture.maxY + gap, parked) else max(picture.minY, parked)
    return ChromeRect(picture.minX + max(0f, (picture.width - size) / 2f), y, size, size)
}

fun portraitOnFeedControls(
    picture: ChromeRect,
    fill: Boolean,
    bottomClearance: Float,
    floorY: Float,
): Pair<ChromeRect, ChromeRect> {
    val stickSize = LiveChromeMetrics.STICK
    val zoomSize = LiveChromeMetrics.ZOOM
    val gap = LiveChromeMetrics.STICK_GAP
    val inset = LiveChromeMetrics.STICK_INSET
    if (fill) {
        val stick =
            ChromeRect(
                picture.maxX - inset - stickSize,
                picture.maxY - bottomClearance - stickSize,
                stickSize,
                stickSize,
            )
        val zoom =
            ChromeRect(
                min(max(picture.minX, stick.maxX - zoomSize), picture.maxX - zoomSize),
                max(picture.minY, stick.minY - gap - zoomSize),
                zoomSize,
                zoomSize,
            )
        return stick to zoom
    }
    val ceiling = picture.maxY + gap
    val stickY = max(ceiling + zoomSize + gap, floorY - inset - stickSize)
    val stickX = max(picture.minX, picture.maxX - inset - stickSize)
    val stick = ChromeRect(stickX, stickY, stickSize, stickSize)
    val zoom =
        ChromeRect(
            min(max(picture.minX, stick.maxX - zoomSize), picture.maxX - zoomSize),
            max(ceiling, stick.minY - gap - zoomSize),
            zoomSize,
            zoomSize,
        )
    return stick to zoom
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
    onTileFrame: (LiveSheet, ChromeRect) -> Unit = { _, _ -> },
) {
    val fill = model.portraitFeedAspect == PortraitFeedAspect.FILL
    val editing = model.chromeEditorMode
    val showsStatus = model.chromeSectionMounts(PocketDispSection.STATUS_BAR)
    val showsLock = model.chromeSectionMounts(PocketDispSection.LOCK_BUTTON) || uiLocked
    val showsRecord = model.chromeSectionMounts(PocketDispSection.RAIL_RECORD) || status.isRecording
    val showsMedia = model.chromeSectionMounts(PocketDispSection.RAIL_MEDIA)
    val showsSettings = model.chromeSectionMounts(PocketDispSection.RAIL_SETTINGS) || status.isRecording
    val showsAssist = model.chromeSectionMounts(PocketDispSection.TOOL_BAR)
    val showsCapture = model.chromeSectionMounts(PocketDispSection.CAMERA_VALUES)
    val captureH = if (fill && showsCapture && zones.controls.height > 1f) zones.controls.height else 0f
    val floorY =
        when {
            fill && zones.controls.height > 1f -> zones.controls.minY
            zones.assistToolbar.height > 1f -> zones.assistToolbar.minY
            else -> zones.systemBar.minY
        }
    val (stick, zoom) =
        portraitOnFeedControls(
            picture = layout.onFeed,
            fill = fill,
            bottomClearance = captureH + 10f,
            floorY = floorY,
        )
    val toggle = portraitAspectToggle(layout.onFeed, floorY)
    var railExpanded by remember { mutableStateOf(false) }
    val captureTop = if (captureH > 1f) zones.controls.minY else null
    val rail = fillAssistRail(zones.feed, captureTop, railExpanded)

    Box(Modifier.fillMaxSize()) {
        if (showsStatus) {
            Box(Modifier.liveModuleFrame(zones.topBar).chromeEditStroke(editing != null, true)) {
                LivePortraitTopBar(model, status)
            }
        }

        if (model.chromeSectionMounts(PocketDispSection.RAIL_RECORD) && editing == null) {
            val recOptions =
                ChromeRect(
                    layout.feed.maxX - LivePortraitMetrics.REC_OPTIONS - LivePortraitMetrics.REC_OPTIONS_INSET,
                    zones.topBar.maxY + LivePortraitMetrics.REC_OPTIONS_GAP,
                    LivePortraitMetrics.REC_OPTIONS,
                    LivePortraitMetrics.REC_OPTIONS,
                )
            LivePortraitRecOptionsButton(
                locked = uiLocked,
                modifier = Modifier.liveModuleFrame(recOptions).alpha(if (uiLocked) 0.4f else 1f),
                onOpen = { if (!uiLocked) onSheet(if (sheet == it) null else it) },
            )
        }

        if (!fill && showsAssist && zones.assistToolbar.height > 0f) {
            val inset =
                ChromeRect(
                    zones.assistToolbar.minX + 12f,
                    zones.assistToolbar.minY + 4f,
                    max(0f, zones.assistToolbar.width - 24f),
                    max(0f, zones.assistToolbar.height - 8f),
                )
            Box(
                Modifier
                    .liveModuleFrame(inset)
                    .alpha(if (uiLocked) 0.4f else 1f)
                    .chromeEditStroke(editing != null, true),
            ) {
                LiveAssistBar(
                    state = assist,
                    locked = uiLocked || !chromeInteractive,
                    onLongPress = onAssistLongPress,
                )
            }
        }

        if (fill && showsAssist) {
            Box(
                Modifier
                    .liveModuleFrame(rail)
                    .alpha(if (uiLocked) 0.4f else 1f)
                    .chromeEditStroke(editing != null, true),
            ) {
                LivePortraitAssistRail(
                    assist = assist,
                    expanded = railExpanded,
                    locked = uiLocked || !chromeInteractive,
                    onExpandedChange = { if (!uiLocked) railExpanded = it },
                    onLongPress = onAssistLongPress,
                )
            }
        }

        if (fill && showsCapture && zones.controls.height > 1f) {
            Box(
                Modifier
                    .liveModuleFrame(zones.controls)
                    .alpha(if (uiLocked) 0.4f else 1f)
                    .chromeEditStroke(editing != null, true),
                contentAlignment = Alignment.Center,
            ) {
                LiveCaptureStrip(
                    status = status,
                    active = sheet,
                    enabled = !uiLocked && !controlBusy && chromeInteractive,
                    showFocus =
                        CaptureLists.supportsFocusModeOrDefault(model.session.connectedCamera?.model),
                    facePriority = model.facePriorityExposureEnabled,
                    shutterUsesAngle = model.shutterUsesAngle,
                    onOpen = { if (!uiLocked) onSheet(if (sheet == it) null else it) },
                    onTileFrame = onTileFrame,
                )
            }
        }

        if (editing == null) {
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

        if (model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP)) {
            val zoomReadout by model.session.zoomReadout.collectAsState()
            val zoomPinching by model.session.zoomPinching.collectAsState()
            LiveZoomChip(
                factor = zoomReadout,
                locked = uiLocked,
                pinching = zoomPinching,
                modifier =
                    Modifier
                        .liveModuleFrame(zoom)
                        .alpha(if (uiLocked) 0.4f else 1f)
                        .chromeEditStroke(editing != null, true),
                onCycle = {
                    model.session.setZoom(CamFov.nextJump(model.session.zoomCycleFrom()))
                },
            )
        }

        if (model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK)) {
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
                .background(LiveDesign.glass),
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
                if (showsMedia) {
                    AuxCircleButton(onClick = { model.liveOperatorPanel = LiveOperatorPanel.MEDIA }) {
                        OpcIcon(OpcIcon.LAYERS, contentDescription = null, tint = it, modifier = Modifier.fillMaxSize())
                    }
                    Spacer(Modifier.weight(1f))
                }
                if (showsSettings) {
                    AuxCircleButton(onClick = { model.liveOperatorPanel = LiveOperatorPanel.SETTINGS }) {
                        OpcIcon(OpcIcon.SETTINGS, contentDescription = null, tint = it, modifier = Modifier.fillMaxSize())
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
            if (fill) "FIT" else "FILL",
            color = LiveDesign.text,
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
) {
    val context = LocalContext.current
    val auto = status.expoMode == CameraCommands.EXPO_AUTO
    val shutterValue =
        if (shutterUsesAngle) {
            ShutterAngle.label(ShutterAngle.nearestDegrees(OperatorPrefs.shutterAngleDegrees(context)))
        } else {
            status.shutterLabel
        }
    val wbAuto = CaptureLists.wbIsAuto(status)
    CaptureStripShell(modifier) {
        CaptureSettingCell(
            "ISO",
            CaptureLists.isoChipValue(status),
            "25600",
            active == LiveSheet.ISO,
            enabled,
            modifier = Modifier.weight(1f).reportChromeFrame { onTileFrame(LiveSheet.ISO, it) },
        ) { onOpen(LiveSheet.ISO) }
        if (auto) {
            CaptureSettingCell(
                "EV",
                EvComp.fromRaw(status.evComp)?.label ?: "—",
                "+3.0",
                active == LiveSheet.SHUTTER,
                enabled,
                modifier = Modifier.weight(1f).reportChromeFrame { onTileFrame(LiveSheet.SHUTTER, it) },
                showFacePriorityBadge = facePriority,
            ) { onOpen(LiveSheet.SHUTTER) }
        } else {
            CaptureSettingCell(
                "SHUTTER",
                shutterValue,
                if (shutterUsesAngle) "346°" else "1/16000",
                active == LiveSheet.SHUTTER,
                enabled,
                modifier = Modifier.weight(1f).reportChromeFrame { onTileFrame(LiveSheet.SHUTTER, it) },
            ) {
                onOpen(LiveSheet.SHUTTER)
            }
        }
        CaptureSettingCell(
            "MODE",
            status.expoLabel,
            "Manual",
            active == LiveSheet.EXPO,
            enabled,
            modifier = Modifier.weight(1f).reportChromeFrame { onTileFrame(LiveSheet.EXPO, it) },
        ) { onOpen(LiveSheet.EXPO) }
        CaptureSettingCell(
            "WB",
            CaptureLists.wbChipValue(status),
            CaptureLists.wbChipWidest(),
            active == LiveSheet.WB,
            enabled,
            modifier = Modifier.weight(1f).reportChromeFrame { onTileFrame(LiveSheet.WB, it) },
            valueIcon = if (wbAuto) { { tint -> WbAutoGlyph(tint) } } else null,
        ) { onOpen(LiveSheet.WB) }
        if (showFocus) {
            CaptureSettingCell(
                "FOCUS",
                status.focusLabel,
                "Showcase",
                active == LiveSheet.FOCUS,
                enabled,
                modifier = Modifier.weight(1f).reportChromeFrame { onTileFrame(LiveSheet.FOCUS, it) },
            ) {
                onOpen(LiveSheet.FOCUS)
            }
        }
        CaptureSettingCell(
            "AUDIO",
            status.audioLabel,
            "Spatial",
            active == LiveSheet.AUDIO,
            enabled,
            modifier = Modifier.weight(1f).reportChromeFrame { onTileFrame(LiveSheet.AUDIO, it) },
        ) { onOpen(LiveSheet.AUDIO) }
    }
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
            fontFamily = FontFamily.Monospace,
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
