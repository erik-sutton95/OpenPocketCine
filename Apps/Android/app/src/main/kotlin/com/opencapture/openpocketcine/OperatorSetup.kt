package com.opencapture.openpocketcine

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.lut.LUTPicker
import com.opencapture.openpocketcine.lut.LutCatalog
import java.io.File
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

object SettingsHelpCopy {
    const val CURRENT_TRANSPORT =
        "Pocket uses Bluetooth to pair, then the camera's own Wi-Fi for HEVC. USB-C, hotspot, and HDMI capture are not in this build."
    const val PHASE = "Where the BLE → Wi-Fi → datalink handshake is right now."
    const val CAMERA_WIFI =
        "SSID joined for this session. The password stays in the Android Keystore on this phone."
    const val SAVED_CAMERAS =
        "Pair from the home list. Settings does not start a new pair — that stays on Your cameras."
    const val EDIT_VIEW = "Opens the monitor with an eye on each element you can show or hide."
    const val FRAME_IO =
        "Sign in to upload clips from the share popup. Frame.io needs the internet, so the phone hops off the camera Wi‑Fi for the upload."
    const val RECORD_CONFIRMATION = "Ask before starting or stopping recording to prevent mistaps."
    const val HAPTICS = "Short confirmation pulses for critical switches and setting changes."
    const val JOYSTICK_SENSITIVITY =
        "How far a stick throw moves the gimbal. 4 is the current feel. 5 reaches full speed sooner; 1 is the slowest."
    const val KEEP_SCREEN_AWAKE =
        "Prevents auto-lock while OpenPocketCine is open. A monitor should stay lit. Android may still dim when the device overheats."
    const val THEME = "Charcoal field-monitor chrome with Sky Blue accents, tuned for low reflection on set."
    const val SUPPORT = "Connection, live view, controls, and troubleshooting."
    const val REPORT = "Opens a public issue form on GitHub for this project."
    const val FEATURE = "Start an idea in this project's feature-request discussion."
    const val SOURCE =
        "View the OpenPocketCine project on GitHub. Opening this may leave the camera Wi-Fi if that is the only network."
    const val LINK_HEALTH = "How healthy the camera link is right now — delivery, not radio RSSI."
    const val CLEAR_CACHE =
        "Removes downloaded clip files from this phone. The clip list stays so you can cache them again from the camera."
    const val LUT_LOOK = "Looks apply on this phone. The file on the camera is unchanged."
    const val PROTOCOL =
        "Camera control speaks DUML over Bluetooth and the camera's Wi-Fi. No DJI SDK is bundled or required."
    const val APP_VERSION = "Current OpenPocketCine build from the native project metadata."
    const val LOCAL_CACHE = "Originals and playback proxies downloaded from the camera."
}

object OpenPocketCineLinks {
    const val SOURCE = "https://github.com/erik-sutton95/OpenPocketCine"
    const val SUPPORT = "https://github.com/erik-sutton95/OpenPocketCine/discussions/categories/q-a"
    const val REPORT_PROBLEM =
        "https://github.com/erik-sutton95/OpenPocketCine/issues/new?template=bug_report.yml"
    const val FEATURE_REQUEST =
        "https://github.com/erik-sutton95/OpenPocketCine/discussions/new?category=ideas"
}

internal object OperatorLinkHealth {
    fun bars(isLive: Boolean, videoPackets: Int, hasVideoFormat: Boolean): Int {
        if (!isLive) return 0
        return when {
            hasVideoFormat && videoPackets > 0 -> 4
            videoPackets >= 400 -> 4
            videoPackets >= 120 -> 3
            videoPackets >= 1 -> 2
            else -> 1
        }
    }

    fun score(bars: Int): Int = (bars * 25).coerceIn(0, 100)

    fun caption(isLive: Boolean, bars: Int): String {
        if (!isLive) return "No live path."
        return when (bars) {
            in 3..Int.MAX_VALUE -> "Link is clean. · Stable"
            2 -> "Some loss on the link. · Watch"
            1 -> "Link is weak. · Poor"
            else -> "Waiting for the link."
        }
    }
}

internal object OperatorMediaCache {
    fun candidates(context: Context): List<File> =
        listOf(
            File(context.filesDir, "OpenPocketCine/media"),
            File(context.filesDir, "media-cache"),
            File(context.cacheDir, "media-cache"),
        )

    fun existingDir(context: Context): File? = candidates(context).firstOrNull { it.isDirectory }

    fun byteCount(context: Context): Long {
        val dir = existingDir(context) ?: return 0L
        return dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    fun clear(context: Context) {
        val mediaRoot = File(context.filesDir, "OpenPocketCine/media")
        if (mediaRoot.isDirectory) {
            mediaRoot.listFiles()?.forEach { cameraDir ->
                if (!cameraDir.isDirectory) return@forEach
                cameraDir.listFiles()?.forEach { child ->
                    if (child.name != "index.json") child.deleteRecursively()
                }
            }
            return
        }
        existingDir(context)?.listFiles()?.forEach { it.deleteRecursively() }
    }
}

internal fun formatCacheSize(bytes: Long): String {
    if (bytes <= 0L) return "Empty"
    val units = arrayOf("B", "KB", "MB", "GB", "TB")
    var value = bytes.toDouble()
    var unit = 0
    while (value >= 1024.0 && unit < units.lastIndex) {
        value /= 1024.0
        unit++
    }
    return if (unit == 0) "$bytes B" else String.format(Locale.US, "%.1f %s", value, units[unit])
}

internal fun formatAppVersion(versionName: String, versionCode: Long): String = "$versionName ($versionCode)"

internal fun lutLookLabel(selection: String): String = LutCatalog.titleFor(selection)

internal fun lutPickerAvailable(): Boolean = true

internal enum class CleanPinTool(val key: String, val title: String) {
    LUT("LUT", "LUT"),
    PEAKING("PEAK", "Peaking"),
    FALSE_COLOR("FALSE", "False Color"),
    ZEBRA("ZEBRA", "Zebra"),
    WAVEFORM("WAVE", "Waveform"),
    PARADE("PARADE", "Parade"),
    HISTOGRAM("HISTO", "Histogram"),
    VECTORSCOPE("VECTOR", "Vectorscope"),
    TRAFFIC_LIGHTS("LIGHTS", "Traffic Lights"),
    GUIDES("GUIDES", "Guides"),
    GRID("GRID", "Grid"),
    CROSSHAIR("CROSS", "Crosshair"),
    MIRROR("MIRROR", "Mirror"),
    AUDIO("AUDIO", "Audio Levels"),
}

internal enum class AssistCard(val title: String) {
    LUT("LUT"),
    PEAKING("Peaking"),
    FALSE_COLOR("False Color"),
    ZEBRA("Zebra"),
    WAVEFORM("Waveform"),
    PARADE("Parade"),
    HISTOGRAM("Histogram"),
    VECTORSCOPE("Vectorscope"),
    TRAFFIC_LIGHTS("Traffic Lights"),
    AUDIO_LEVELS("Audio Levels"),
    GUIDES("Guides"),
    GRID("Grid"),
    CROSSHAIR("Crosshair"),
    MIRROR("Mirror"),
}

internal fun connectionPhaseLabel(phase: ConnectionPhase, failure: String?): String =
    when (phase) {
        ConnectionPhase.IDLE -> "Idle"
        ConnectionPhase.SCANNING -> "Scanning for camera…"
        ConnectionPhase.CONNECTING_GATT -> "Connecting (Bluetooth)…"
        ConnectionPhase.PAIRING -> "Pairing…"
        ConnectionPhase.AWAITING_APPROVAL -> "Approve on the camera screen"
        ConnectionPhase.READING_WIFI_CREDS -> "Reading Wi-Fi credentials…"
        ConnectionPhase.JOINING_WIFI -> "Joining camera Wi-Fi…"
        ConnectionPhase.OPENING_DATALINK -> "Opening datalink…"
        ConnectionPhase.LIVE -> "Connected"
        ConnectionPhase.FAILED ->
            if (failure.isNullOrBlank()) "Failed" else "Failed: $failure"
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
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(500)
            tick += 1
        }
    }
    tick
    val isLive = phase == ConnectionPhase.LIVE
    val bars = OperatorLinkHealth.bars(isLive, model.session.videoPackets, model.session.hasVideoFormat)
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

    Box(
        Modifier
            .fillMaxSize()
            .background(LiveDesign.background)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val portrait = maxHeight > maxWidth
            val stackedTop = portrait || maxWidth < 560.dp
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (portrait) {
                    SettingsTabStrip(model, hapticsEnabled, view, Modifier.padding(start = 45.dp))
                    SettingsTopBar(
                        stacked = true,
                        isLive = isLive,
                        phaseLabel = phaseLabel,
                        bars = bars,
                        cameraName = liveCameraName(model),
                        onDisconnect = model::disconnect,
                    )
                    SettingsContentPane(
                        model = model,
                        isLive = isLive,
                        phaseLabel = phaseLabel,
                        bars = bars,
                        expandedDisp = expandedDisp,
                        onExpandDisp = { expandedDisp = it },
                        onLegal = { legalKind = it },
                        onClearCache = { confirmClearCache = true },
                        onOpenLut = { showLutPicker = true },
                        modifier = Modifier.weight(1f),
                    )
                } else {
                    SettingsTopBar(
                        stacked = stackedTop,
                        isLive = isLive,
                        phaseLabel = phaseLabel,
                        bars = bars,
                        cameraName = liveCameraName(model),
                        onDisconnect = model::disconnect,
                        modifier = Modifier.padding(start = 45.dp),
                    )
                    Row(
                        Modifier.weight(1f).fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        SettingsTabRail(model, hapticsEnabled, view)
                        SettingsContentPane(
                            model = model,
                            isLive = isLive,
                            phaseLabel = phaseLabel,
                            bars = bars,
                            expandedDisp = expandedDisp,
                            onExpandDisp = { expandedDisp = it },
                            onLegal = { legalKind = it },
                            onClearCache = { confirmClearCache = true },
                            onOpenLut = { showLutPicker = true },
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                    }
                }
            }
        }
        OperatorCloseButton(
            onClose = onClose,
            modifier =
                Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 16.dp, top = 16.dp),
        )
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
                            OperatorMediaCache.clear(context)
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
private fun SettingsTopBar(
    stacked: Boolean,
    isLive: Boolean,
    phaseLabel: String,
    bars: Int,
    cameraName: String,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    "OPENPOCKETCINE",
                    style = LiveType.ui(9.5f, FontWeight.Bold).copy(letterSpacing = 0.8.sp),
                    color = LiveDesign.accent,
                )
                Text(
                    "Operator Setup",
                    style = LiveType.title(24f, FontWeight.SemiBold),
                    color = LiveDesign.text,
                    maxLines = 1,
                )
            }
            if (!stacked) {
                SessionControls(isLive, phaseLabel, bars, cameraName, onDisconnect)
            }
        }
        if (stacked) {
            SessionControls(isLive, phaseLabel, bars, cameraName, onDisconnect)
        }
    }
}

@Composable
private fun SessionControls(
    isLive: Boolean,
    phaseLabel: String,
    bars: Int,
    cameraName: String,
    onDisconnect: () -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        if (isLive) {
            SettingsActionPill(
                title = "Disconnect",
                tint = LiveDesign.rec,
                background = LiveDesign.rec.copy(alpha = 0.16f),
                icon = {
                    Icon(
                        Icons.Filled.LinkOff,
                        contentDescription = null,
                        tint = LiveDesign.rec,
                        modifier = Modifier.size(13.dp),
                    )
                },
                onClick = onDisconnect,
            )
        }
        SettingsLiveTile(isLive = isLive, phaseLabel = phaseLabel, bars = bars, cameraName = cameraName)
    }
}

@Composable
private fun SettingsTabRail(model: AppModel, hapticsEnabled: Boolean, view: View) {
    val shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
    Column(
        Modifier
            .width(146.dp)
            .fillMaxHeight()
            .background(LiveDesign.glass, shape)
            .border(1.dp, LiveDesign.hairline, shape)
            .padding(6.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        OperatorSettingsTab.entries.forEach { tab ->
            SettingsTabButton(tab, model, hapticsEnabled, view, Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun SettingsTabStrip(
    model: AppModel,
    hapticsEnabled: Boolean,
    view: View,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
    val scroll = rememberScrollState()
    Row(
        modifier
            .fillMaxWidth()
            .background(LiveDesign.glass, shape)
            .border(1.dp, LiveDesign.hairline, shape)
            .horizontalScroll(scroll)
            .padding(6.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        OperatorSettingsTab.entries.forEach { tab ->
            SettingsTabButton(tab, model, hapticsEnabled, view, Modifier.widthIn(min = 128.dp))
        }
    }
}

@Composable
private fun SettingsTabButton(
    tab: OperatorSettingsTab,
    model: AppModel,
    hapticsEnabled: Boolean,
    view: View,
    modifier: Modifier = Modifier,
) {
    val selected = model.operatorSettingsTab == tab
    Row(
        modifier
            .height(43.dp)
            .clip(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))
            .background(if (selected) LiveDesign.surface else Color.Transparent)
            .chromeClickable(onClick = {
                if (tab != model.operatorSettingsTab) operatorHaptic(view, hapticsEnabled)
                model.operatorSettingsTab = tab
            })
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(
            Modifier
                .width(6.dp)
                .height(26.dp)
                .clip(RoundedCornerShape(50))
                .background(if (selected) LiveDesign.accent else Color.Transparent),
        )
        Column(Modifier.weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                tab.title,
                style = LiveType.ui(13f, FontWeight.SemiBold),
                color = if (selected) LiveDesign.text else LiveDesign.muted,
                maxLines = 1,
            )
            Text(
                tab.rail,
                style = LiveType.ui(10.5f),
                color = LiveDesign.faint,
                maxLines = 2,
            )
        }
    }
}

@Composable
private fun SettingsContentPane(
    model: AppModel,
    isLive: Boolean,
    phaseLabel: String,
    bars: Int,
    expandedDisp: PocketDispMode?,
    onExpandDisp: (PocketDispMode?) -> Unit,
    onLegal: (LegalKind) -> Unit,
    onClearCache: () -> Unit,
    onOpenLut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tab = model.operatorSettingsTab
    val shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
    val scroll = rememberScrollState()
    Column(
        modifier
            .fillMaxSize()
            .background(LiveDesign.surface, shape)
            .clip(shape)
            .border(1.dp, LiveDesign.hairline, shape)
            .padding(12.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(tab.title, style = LiveType.title(24f, FontWeight.SemiBold), color = LiveDesign.text)
                Text(tab.subtitle, style = LiveType.ui(12.5f), color = LiveDesign.muted, maxLines = 2)
            }
            Text(
                tab.pill.uppercase(),
                style = LiveType.mono(10f, FontWeight.Bold).copy(letterSpacing = 0.6.sp, color = LiveDesign.accent),
                modifier =
                    Modifier
                        .border(1.dp, LiveDesign.accentDim, RoundedCornerShape(50))
                        .padding(horizontal = 10.dp, vertical = 6.dp),
            )
        }
        Spacer(Modifier.height(10.dp))
        Box(Modifier.weight(1f).fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(scroll)
                    .padding(bottom = 22.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                when (tab) {
                    OperatorSettingsTab.LINK ->
                        LinkRows(model, isLive, phaseLabel, bars)
                    OperatorSettingsTab.SHARING -> SharingRows()
                    OperatorSettingsTab.ASSIST -> AssistRows(model, onOpenLut)
                    OperatorSettingsTab.CONTROLS -> ControlsRows(model)
                    OperatorSettingsTab.DISPLAY ->
                        DisplayRows(model, isLive, expandedDisp, onExpandDisp)
                    OperatorSettingsTab.STORAGE -> StorageRows(onClearCache)
                    OperatorSettingsTab.SYSTEM -> SystemRows(onLegal)
                }
            }
            if (scroll.canScrollForward) {
                ScrollMoreCue(Modifier.align(Alignment.BottomCenter))
            }
        }
    }
}

@Composable
private fun LinkRows(model: AppModel, isLive: Boolean, phaseLabel: String, bars: Int) {
    SettingsDashScale(
        title = "Link Health",
        caption = OperatorLinkHealth.caption(isLive, bars),
        score = OperatorLinkHealth.score(bars),
    )
    SettingsRowCard(title = "Connection") {
        SettingsInlineRow("Current Transport", SettingsHelpCopy.CURRENT_TRANSPORT, showTopDivider = false) {
            SettingsValueText(if (isLive) "BLE + Wi-Fi active" else "Not connected")
        }
        SettingsInlineRow("Phase", SettingsHelpCopy.PHASE) {
            SettingsValueText(phaseLabel)
        }
        val ssid = model.session.joinedSSID
        if (!ssid.isNullOrEmpty()) {
            SettingsInlineRow("Camera Wi-Fi", SettingsHelpCopy.CAMERA_WIFI) {
                SettingsValueText(ssid)
            }
        }
    }
    SettingsRowCard(title = "Your cameras") {
        if (model.savedCameras.isEmpty()) {
            SettingsInlineRow("Saved", SettingsHelpCopy.SAVED_CAMERAS, showTopDivider = false) {
                SettingsValueText("None")
            }
        } else {
            model.savedCameras.forEachIndexed { index, camera ->
                val help = camera.modelName + (camera.lastSSID?.let { " · $it" } ?: "")
                SettingsInlineRow(camera.displayName, help, showTopDivider = index > 0) {
                    SettingsValueText(camera.lastSSID ?: "Saved")
                }
            }
        }
    }
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
private fun AssistRows(model: AppModel, onOpenLut: () -> Unit) {
    AssistToolCard("LUT") {
        SettingsInlineRow("Look", SettingsHelpCopy.LUT_LOOK, showTopDivider = false) {
            SettingsValueText(lutLookLabel(model.lutSelection))
        }
        SettingsInlineRow("Choose look") {
            SettingsActionPill(title = "Open", onClick = onOpenLut)
        }
    }
    AssistCard.entries.filter { it != AssistCard.LUT }.forEach { card ->
        AssistToolCard(card.title) {
            Text(
                "Configure this tool from the live toolbar.",
                style = LiveType.ui(11.5f, FontWeight.SemiBold),
                color = LiveDesign.muted,
                modifier = Modifier.padding(vertical = 10.dp),
            )
        }
    }
}

@Composable
private fun AssistToolCard(title: String, content: @Composable () -> Unit) {
    SettingsRowCard(title = title, onReset = {}) { content() }
}

@Composable
private fun ControlsRows(model: AppModel) {
    val view = LocalView.current
    SettingsRowCard {
        SettingsSwitchInlineRow(
            title = "Record Confirmation",
            help = SettingsHelpCopy.RECORD_CONFIRMATION,
            showTopDivider = false,
            isOn = model.recordConfirmationEnabled,
        ) {
            operatorHaptic(view, model.hapticsEnabled)
            model.updateRecordConfirmationEnabled(!model.recordConfirmationEnabled)
        }
        SettingsSwitchInlineRow(
            title = "Haptics",
            help = SettingsHelpCopy.HAPTICS,
            isOn = model.hapticsEnabled,
        ) {
            val next = !model.hapticsEnabled
            operatorHaptic(view, model.hapticsEnabled)
            model.updateHapticsEnabled(next)
        }
        SettingsInlineRow(
            title = "Joystick Sensitivity",
            help = SettingsHelpCopy.JOYSTICK_SENSITIVITY,
            stacked = true,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                Slider(
                    value = model.gimbalStickSensitivity.toFloat(),
                    onValueChange = { next ->
                        val clamped = next.roundToInt().coerceIn(1, 5)
                        if (clamped != model.gimbalStickSensitivity) {
                            operatorHaptic(view, model.hapticsEnabled)
                            model.updateGimbalStickSensitivity(clamped)
                        }
                    },
                    valueRange = 1f..5f,
                    steps = 3,
                    modifier = Modifier.weight(1f).semantics { contentDescription = "Joystick sensitivity" },
                    colors =
                        SliderDefaults.colors(
                            thumbColor = LiveDesign.accent,
                            activeTrackColor = LiveDesign.accent,
                            inactiveTrackColor = LiveDesign.hairline,
                        ),
                )
                Text(
                    "${model.gimbalStickSensitivity}",
                    style = LiveType.mono(12f),
                    color = LiveDesign.text,
                    modifier = Modifier.width(24.dp),
                )
            }
        }
        SettingsSwitchInlineRow(
            title = "Keep Screen Awake",
            help = SettingsHelpCopy.KEEP_SCREEN_AWAKE,
            isOn = model.keepScreenAwake,
        ) {
            operatorHaptic(view, model.hapticsEnabled)
            model.updateKeepScreenAwake(!model.keepScreenAwake)
        }
    }
}

@Composable
private fun DisplayRows(
    model: AppModel,
    isLive: Boolean,
    expandedDisp: PocketDispMode?,
    onExpandDisp: (PocketDispMode?) -> Unit,
) {
    val view = LocalView.current
    PocketDispMode.entries.forEach { mode ->
        SettingsRowCard(
            title = mode.settingsTitle,
            onReset = {
                operatorHaptic(view, model.hapticsEnabled)
                resetDispChrome(model, mode)
            },
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .chromeClickable(onClick = {
                        operatorHaptic(view, model.hapticsEnabled)
                        onExpandDisp(if (expandedDisp == mode) null else mode)
                    })
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    mode.settingsCaption,
                    style = LiveType.ui(11f, FontWeight.SemiBold),
                    color = LiveDesign.muted,
                    modifier = Modifier.weight(1f),
                )
                Icon(
                    if (expandedDisp == mode) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = LiveDesign.faint,
                    modifier = Modifier.size(16.dp),
                )
            }
            if (expandedDisp == mode) {
                DispSectionBody(model, mode, isLive, view)
            }
        }
    }
}

@Composable
private fun DispSectionBody(model: AppModel, mode: PocketDispMode, isLive: Boolean, view: View) {
    if (isLive) {
        SettingsActionPill(
            title = "Edit view",
            onClick = {
                operatorHaptic(view, model.hapticsEnabled)
                model.homePanel = null
                model.beginChromeEditing(mode)
            },
        )
        Text(
            SettingsHelpCopy.EDIT_VIEW,
            style = LiveType.ui(11f),
            color = LiveDesign.faint,
            modifier = Modifier.padding(vertical = 8.dp),
        )
    } else {
        Text(
            "Connect to arrange this on the monitor.",
            style = LiveType.ui(11f, FontWeight.SemiBold),
            color = LiveDesign.muted,
            modifier = Modifier.padding(vertical = 6.dp),
        )
        DispToggles(model, mode, view)
    }
    if (mode == PocketDispMode.CLEAN) {
        Text(
            "View assists that stay on in clean view",
            style = LiveType.ui(11f, FontWeight.SemiBold),
            color = LiveDesign.muted,
            modifier = Modifier.padding(top = 8.dp, bottom = 6.dp),
        )
        CleanViewPinStrip(model, view)
    }
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

@Composable
private fun DispToggles(model: AppModel, mode: PocketDispMode, view: View) {
    val chrome = model.chrome(mode)
    dispToggleSpecs.forEachIndexed { index, spec ->
        SettingsSwitchInlineRow(
            title = spec.title,
            help = spec.help,
            showTopDivider = true,
            isOn = chrome.isVisible(spec.section),
        ) {
            operatorHaptic(view, model.hapticsEnabled)
            model.toggleChrome(spec.section, mode)
        }
    }
}

@Composable
private fun CleanViewPinStrip(model: AppModel, view: View) {
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        CleanPinTool.entries.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                row.forEach { tool ->
                    val on = tool.key in model.cleanViewPinnedTools
                    DisplayToggleItem(
                        title = tool.title,
                        isOn = on,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            operatorHaptic(view, model.hapticsEnabled)
                            val next = model.cleanViewPinnedTools.toMutableSet()
                            if (!next.add(tool.key)) next.remove(tool.key)
                            model.updateCleanViewPinnedTools(next)
                        },
                    )
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun StorageRows(onClearCache: () -> Unit) {
    val context = LocalContext.current
    val bytes = OperatorMediaCache.byteCount(context)
    val cacheLabel =
        if (OperatorMediaCache.existingDir(context) == null) "Empty" else formatCacheSize(bytes)
    SettingsRowCard {
        SettingsInlineRow("Frame.io", SettingsHelpCopy.FRAME_IO, showTopDivider = false) {
            SettingsValueText("Not configured")
        }
    }
    SettingsRowCard {
        SettingsInlineRow("Local Media Cache", SettingsHelpCopy.LOCAL_CACHE, showTopDivider = false) {
            SettingsValueText(cacheLabel)
        }
        SettingsInlineRow("Clear Cache", SettingsHelpCopy.CLEAR_CACHE) {
            Text(
                "Clear",
                style = LiveType.ui(13f, FontWeight.SemiBold),
                color = LiveDesign.rec,
                modifier = Modifier.chromeClickable(onClick = onClearCache),
            )
        }
    }
}

@Composable
private fun SystemRows(onLegal: (LegalKind) -> Unit) {
    val context = LocalContext.current
    SettingsRowCard(title = "Help & Feedback") {
        SettingsInlineRow("Support", SettingsHelpCopy.SUPPORT, showTopDivider = false) {
            SettingsActionPill("Open") { openUrl(context, OpenPocketCineLinks.SUPPORT) }
        }
        SettingsInlineRow("Report a Problem", SettingsHelpCopy.REPORT) {
            SettingsActionPill("Report") { openUrl(context, OpenPocketCineLinks.REPORT_PROBLEM) }
        }
        SettingsInlineRow("Request a Feature", SettingsHelpCopy.FEATURE) {
            SettingsActionPill("Request") { openUrl(context, OpenPocketCineLinks.FEATURE_REQUEST) }
        }
    }
    SettingsRowCard(title = "Project & Legal") {
        SettingsInlineRow("Source Code", SettingsHelpCopy.SOURCE, showTopDivider = false) {
            SettingsActionPill("Open") { openUrl(context, OpenPocketCineLinks.SOURCE) }
        }
        SettingsInlineRow("Privacy", "What this app stores on this phone.") {
            SettingsActionPill("Open") { onLegal(LegalKind.PRIVACY) }
        }
        SettingsInlineRow("Terms", "How you can use OpenPocketCine.") {
            SettingsActionPill("Open") { onLegal(LegalKind.TERMS) }
        }
        SettingsInlineRow("Licenses", "Apache 2.0 and third-party notices.") {
            SettingsActionPill("Open") { onLegal(LegalKind.LICENSES) }
        }
        SettingsInlineRow("NOTICE", "Attribution shipped with the app.") {
            SettingsActionPill("Open") { onLegal(LegalKind.NOTICE) }
        }
    }
    SettingsRowCard(title = "App Information") {
        SettingsInlineRow("Theme", SettingsHelpCopy.THEME, showTopDivider = false) {
            SettingsValueText("DJI Black")
        }
        SettingsInlineRow("Protocol Implementation", SettingsHelpCopy.PROTOCOL) {
            SettingsValueText("DUML / BLE + Wi-Fi")
        }
        SettingsInlineRow("App Version", SettingsHelpCopy.APP_VERSION) {
            SettingsValueText(formatAppVersion(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toLong()))
        }
    }
}

private fun openUrl(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}

private fun operatorHaptic(view: View, enabled: Boolean) {
    if (!enabled) return
    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
}

@Composable
fun OperatorCloseButton(onClose: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(37.dp)
            .clip(CircleShape)
            .background(LiveDesign.glass)
            .border(1.dp, LiveDesign.hairline, CircleShape)
            .chromeClickable(onClick = onClose)
            .semantics { contentDescription = "Close" },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Filled.Close,
            contentDescription = null,
            tint = LiveDesign.text,
            modifier = Modifier.size(14.dp),
        )
    }
}

@Composable
private fun HelpBadge(text: String) {
    var showing by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier
                .size(16.dp)
                .clip(CircleShape)
                .background(LiveDesign.background.copy(alpha = 0.5f))
                .border(1.dp, LiveDesign.hairline, CircleShape)
                .chromeClickable(onClick = { showing = !showing }),
            contentAlignment = Alignment.Center,
        ) {
            Text("?", style = LiveType.ui(8.5f, FontWeight.Bold), color = LiveDesign.faint)
        }
        DropdownMenu(expanded = showing, onDismissRequest = { showing = false }) {
            Text(
                text,
                style = LiveType.ui(12f),
                color = LiveDesign.text,
                modifier = Modifier.width(248.dp).padding(12.dp),
            )
        }
    }
}

@Composable
private fun SettingsInlineRow(
    title: String,
    help: String? = null,
    showTopDivider: Boolean = true,
    stacked: Boolean = false,
    trailing: @Composable () -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        if (showTopDivider) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(LiveDesign.hairline))
        }
        if (stacked) {
            Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SettingsLabelRow(title, help, stacked = true)
                trailing()
            }
        } else {
            Row(
                Modifier.fillMaxWidth().height(50.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SettingsLabelRow(title, help, stacked = false, modifier = Modifier.weight(1f))
                trailing()
            }
        }
    }
}

@Composable
private fun SettingsLabelRow(
    title: String,
    help: String?,
    stacked: Boolean,
    modifier: Modifier = Modifier,
) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            title,
            style = LiveType.ui(12.5f, FontWeight.SemiBold),
            color = LiveDesign.text,
            maxLines = if (stacked) 2 else 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (help != null) HelpBadge(help)
    }
}

@Composable
private fun SettingsValueText(value: String) {
    Text(
        value,
        style = LiveType.mono(12.5f),
        color = LiveDesign.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
private fun SettingsActionPill(
    title: String,
    tint: Color = LiveDesign.accent,
    background: Color = LiveDesign.accentDim,
    icon: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(background)
            .border(1.dp, tint.copy(alpha = 0.5f), RoundedCornerShape(50))
            .chromeClickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        icon?.invoke()
        Text(
            title.uppercase(),
            style = LiveType.mono(10.5f, FontWeight.Bold).copy(letterSpacing = 0.6.sp, color = tint),
            maxLines = 1,
        )
    }
}

@Composable
private fun SettingsSwitchGraphic(isOn: Boolean) {
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

@Composable
private fun SettingsSwitchInlineRow(
    title: String,
    help: String? = null,
    showTopDivider: Boolean = true,
    isOn: Boolean,
    onToggle: () -> Unit,
) {
    SettingsInlineRow(title, help, showTopDivider) {
        Box(Modifier.chromeClickable(onClick = onToggle)) {
            SettingsSwitchGraphic(isOn)
        }
    }
}

@Composable
private fun SettingsRowCard(
    title: String? = null,
    onReset: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(LiveDesign.glass, shape)
            .border(1.dp, LiveDesign.hairline, shape)
            .padding(start = 13.dp, end = 13.dp, bottom = 4.dp),
    ) {
        if (title != null) {
            Row(
                Modifier.fillMaxWidth().padding(top = 11.dp, bottom = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, style = LiveType.ui(13f, FontWeight.SemiBold), color = LiveDesign.text, modifier = Modifier.weight(1f))
                if (onReset != null) {
                    Box(
                        Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(LiveDesign.background.copy(alpha = 0.42f))
                            .border(1.dp, LiveDesign.hairline, CircleShape)
                            .chromeClickable(onClick = onReset)
                            .semantics { contentDescription = "Reset to defaults" },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null, tint = LiveDesign.muted, modifier = Modifier.size(12.dp))
                    }
                }
            }
        } else {
            Spacer(Modifier.height(8.dp))
        }
        content()
    }
}

@Composable
private fun DisplayToggleItem(
    title: String,
    isOn: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
    Row(
        modifier
            .height(46.dp)
            .clip(shape)
            .background(LiveDesign.background.copy(alpha = 0.38f))
            .border(1.dp, LiveDesign.hairline, shape)
            .chromeClickable(onClick = onClick)
            .padding(horizontal = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Text(
            title,
            style = LiveType.ui(11.5f, FontWeight.SemiBold),
            color = LiveDesign.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        Box(Modifier.size(width = 34.dp, height = 19.dp), contentAlignment = Alignment.Center) {
            SettingsSwitchGraphic(isOn)
        }
    }
}

@Composable
private fun SettingsDashScale(title: String, caption: String, score: Int) {
    val shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
    val band =
        when {
            score >= 80 -> 2
            score >= 50 -> 1
            else -> 0
        }
    val watch = Color(0.96f, 0.52f, 0.12f)
    val bandColor =
        when (band) {
            2 -> LiveDesign.good
            1 -> watch
            else -> LiveDesign.rec
        }
    val bandName =
        when (band) {
            2 -> "STABLE"
            1 -> "WATCH"
            else -> "POOR"
        }
    val litCount =
        when (band) {
            2 -> 12
            1 -> 8
            else -> 4
        }
    Column(
        Modifier
            .fillMaxWidth()
            .background(LiveDesign.glass, shape)
            .border(1.dp, LiveDesign.hairline, shape)
            .padding(13.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Text(title, style = LiveType.ui(13f, FontWeight.SemiBold), color = LiveDesign.text)
        Text(caption, style = LiveType.mono(11.5f), color = LiveDesign.muted)
        Row(Modifier.fillMaxWidth().height(19.dp)) {
            repeat(3) { slot ->
                Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                    if (slot == band) {
                        Text(
                            bandName,
                            style = LiveType.mono(9.5f, FontWeight.Bold).copy(letterSpacing = 0.5.sp, color = bandColor),
                            modifier =
                                Modifier
                                    .background(bandColor.copy(alpha = 0.12f), RoundedCornerShape(50))
                                    .border(1.dp, bandColor, RoundedCornerShape(50))
                                    .padding(horizontal = 10.dp, vertical = 4.dp),
                        )
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.fillMaxWidth()) {
            repeat(12) { index ->
                val fill =
                    when {
                        index >= litCount -> LiveDesign.hairlineStrong
                        index < 4 -> LiveDesign.rec.copy(alpha = 0.8f)
                        index < 8 -> watch.copy(alpha = 0.85f)
                        else -> LiveDesign.good.copy(alpha = 0.9f)
                    }
                Box(
                    Modifier
                        .weight(1f)
                        .height(6.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(fill),
                )
            }
        }
        Row(Modifier.fillMaxWidth()) {
            Text("Poor  <50", style = LiveType.ui(10f, FontWeight.SemiBold), color = LiveDesign.muted, modifier = Modifier.weight(1f))
            Text(
                "Watch  50-79",
                style = LiveType.ui(10f, FontWeight.SemiBold),
                color = LiveDesign.muted,
                modifier = Modifier.weight(1f),
            )
            Text(
                "Stable  80+",
                style = LiveType.ui(10f, FontWeight.SemiBold),
                color = LiveDesign.muted,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun SettingsLiveTile(isLive: Boolean, phaseLabel: String, bars: Int, cameraName: String) {
    val tint =
        when {
            !isLive -> LiveDesign.faint
            bars >= 3 -> LiveDesign.good
            bars == 2 -> LiveDesign.accent
            bars == 1 -> LiveDesign.rec
            else -> LiveDesign.faint
        }
    val lit = if (isLive) bars.coerceIn(0, 4) else 0
    val shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
    val detail = if (isLive) "$cameraName · BLE + Wi-Fi" else phaseLabel
    Row(
        Modifier
            .background(LiveDesign.surface, shape)
            .border(1.dp, LiveDesign.hairline, shape)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(tint))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                if (isLive) "Active Link" else "No Link",
                style = LiveType.ui(12f, FontWeight.SemiBold),
                color = LiveDesign.text,
                maxLines = 1,
            )
            Text(
                detail,
                style = LiveType.mono(10.5f),
                color = LiveDesign.muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.Bottom) {
            repeat(4) { index ->
                Box(
                    Modifier
                        .width(3.dp)
                        .height((6 + index * 3).dp)
                        .clip(RoundedCornerShape(1.5.dp))
                        .background(
                            if (index < lit) tint.copy(alpha = 0.52f + index * 0.12f) else LiveDesign.hairline,
                        ),
                )
            }
        }
    }
}

@Composable
private fun ScrollMoreCue(modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxWidth()
            .height(58.dp)
            .background(
                Brush.verticalGradient(listOf(LiveDesign.surface.copy(alpha = 0f), LiveDesign.surface)),
            )
            .padding(bottom = 13.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Bottom,
    ) {
        Text(
            "MORE",
            style = LiveType.mono(9.5f, FontWeight.Bold).copy(letterSpacing = 1.2.sp, color = LiveDesign.muted),
        )
        Icon(
            Icons.Filled.KeyboardArrowDown,
            contentDescription = null,
            tint = LiveDesign.muted,
            modifier = Modifier.size(10.dp),
        )
    }
}
