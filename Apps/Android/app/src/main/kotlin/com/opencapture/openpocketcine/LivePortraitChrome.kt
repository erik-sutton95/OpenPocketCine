package com.opencapture.openpocketcine

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.assists.LiveAssistBar
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
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
    const val TOP_BAR = 44f
    const val TOP_BAR_LIFT = 8f
    const val SYSTEM_BAR = 100f
    const val SYSTEM_BAR_LIFT = 14f
    const val CAPTURE = 64f
    const val ASSIST = 58f
    const val TOGGLE = 40f
    const val TOGGLE_GAP = 8f
}

fun portraitZones(
    viewportWidth: Float,
    viewportHeight: Float,
    safeTop: Float,
    safeBottom: Float,
    clean: Boolean,
    fill: Boolean,
    assistToolbarHeight: Float,
): PortraitZones {
    val vw = max(0f, viewportWidth)
    val vh = max(0f, viewportHeight)
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
    val ratio = 16f / 9f
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
    val toolbar = if (clean) 0f else max(0f, assistToolbarHeight)
    val chromeFloor = systemBar.minY - toolbar
    val available = max(0f, chromeFloor - topBar.maxY)
    val feedHeight = min(natural, available)
    val ideal = (vh - feedHeight) / 2f
    val latest = max(topBar.maxY, chromeFloor - feedHeight)
    val y = min(max(ideal, topBar.maxY), latest)
    val feed = ChromeRect(0f, y, vw, feedHeight)
    val assist = ChromeRect(0f, systemBar.minY - toolbar, vw, toolbar)
    val controls = ChromeRect(0f, feed.maxY, vw, max(0f, assist.minY - feed.maxY))
    return PortraitZones(topBar, feed, assist, controls, systemBar)
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
    onZoomCycle: () -> Unit,
    controlBusy: Boolean,
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

    Box(Modifier.fillMaxSize()) {
        if (showsStatus) {
            Box(Modifier.liveModuleFrame(zones.topBar).chromeEditStroke(editing != null, true)) {
                LivePortraitTopBar(status)
            }
        }

        if (!fill && showsAssist && zones.assistToolbar.height > 0f) {
            Box(
                Modifier
                    .liveModuleFrame(zones.assistToolbar)
                    .padding(horizontal = 12.dp, vertical = 4.dp)
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

        if (fill && showsCapture && zones.controls.height > 1f) {
            Box(
                Modifier
                    .liveModuleFrame(zones.controls)
                    .alpha(if (uiLocked) 0.4f else 1f)
                    .chromeEditStroke(editing != null, true),
            ) {
                LiveCaptureStrip(
                    status = status,
                    active = sheet,
                    enabled = !uiLocked && !controlBusy && chromeInteractive,
                    onOpen = { if (!uiLocked) onSheet(if (sheet == it) null else it) },
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
            LiveZoomChip(
                factor = LiveZoom.factor(status),
                locked = uiLocked,
                modifier = Modifier.liveModuleFrame(zoom).alpha(if (uiLocked) 0.4f else 1f).chromeEditStroke(editing != null, true),
                onCycle = onZoomCycle,
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
fun LivePortraitTopBar(status: CameraStatus) {
    Box(Modifier.fillMaxSize().background(LiveDesign.glass)) {
        Text(
            status.storageLabel,
            color = LiveDesign.text,
            style = LiveType.ui(13f, FontWeight.SemiBold),
            maxLines = 1,
            modifier = Modifier.align(Alignment.Center),
        )
        Row(
            Modifier.fillMaxSize().padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TimecodeReadout(status.timecode, portrait = true)
            Spacer(Modifier.weight(1f))
            CameraBatteryReadout(status.batteryPercent)
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
                Spacer(Modifier.width(14.dp))
                if (showsLock) {
                    LockButton(uiLocked, onClick = onLock)
                    Spacer(Modifier.width(14.dp))
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
                }
            }
            if (showsRecord) Spacer(Modifier.width(LiveDesign.RECORD_SIZE_DP.dp))
            Row(
                Modifier.weight(1f).fillMaxHeight(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.End,
            ) {
                if (showsMedia) {
                    AuxCircleButton(onClick = { model.liveOperatorPanel = LiveOperatorPanel.MEDIA }) { MediaGlyph(it) }
                    Spacer(Modifier.width(14.dp))
                }
                if (showsSettings) {
                    AuxCircleButton(onClick = { model.liveOperatorPanel = LiveOperatorPanel.SETTINGS }) { GearGlyph(it) }
                    Spacer(Modifier.width(14.dp))
                }
            }
        }
        if (showsRecord) {
            RecordButton(
                recording = status.isRecording,
                enabled = !controlBusy,
                confirm = model.recordConfirmationEnabled,
                onClick = model::pressRecord,
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
            .chromeClickable(enabled = !locked, onClick = onClick),
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
    onOpen: (LiveSheet) -> Unit,
) {
    val auto = status.expoMode == CameraCommands.EXPO_AUTO
    Row(
        modifier
            .fillMaxSize()
            .monitorGlass()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        CaptureSettingCell("ISO", status.isoLabel, "25600", active == LiveSheet.ISO, enabled) { onOpen(LiveSheet.ISO) }
        if (auto) {
            CaptureSettingCell("EV", "—", "+3.0", active == LiveSheet.SHUTTER, enabled) { onOpen(LiveSheet.SHUTTER) }
        } else {
            CaptureSettingCell("SHUTTER", status.shutterLabel, "1/16000", active == LiveSheet.SHUTTER, enabled) {
                onOpen(LiveSheet.SHUTTER)
            }
        }
        CaptureSettingCell("MODE", status.expoLabel, "Manual", active == LiveSheet.EXPO, enabled) { onOpen(LiveSheet.EXPO) }
        CaptureSettingCell("WB", status.wbLabel, "10000K", active == LiveSheet.WB, enabled) { onOpen(LiveSheet.WB) }
        CaptureSettingCell("FOCUS", status.focusLabel, "Single", active == LiveSheet.FOCUS, enabled) { onOpen(LiveSheet.FOCUS) }
        CaptureSettingCell("AUDIO", status.audioLabel, "Spatial", active == LiveSheet.AUDIO, enabled) { onOpen(LiveSheet.AUDIO) }
    }
}
