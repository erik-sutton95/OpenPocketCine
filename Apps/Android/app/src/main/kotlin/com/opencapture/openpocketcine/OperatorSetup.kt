package com.opencapture.openpocketcine

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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.assists.CrushClipCompensation
import com.opencapture.openpocketcine.assists.FalseColorScale
import com.opencapture.openpocketcine.assists.HistogramAssist
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.assists.LiveZebra
import com.opencapture.openpocketcine.assists.ParadeMode
import com.opencapture.openpocketcine.assists.PeakingColor
import com.opencapture.openpocketcine.assists.PeakingSense
import com.opencapture.openpocketcine.assists.ScopeGuides
import com.opencapture.openpocketcine.assists.VectorscopeZoom
import com.opencapture.openpocketcine.assists.WaveformMode
import com.opencapture.openpocketcine.assists.ZebraEditor
import com.opencapture.openpocketcine.assists.ZebraPaint
import com.opencapture.openpocketcine.assists.ZebraUnit
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.feed.FeedUpscaler
import com.opencapture.openpocketcine.feed.LutLookResolver
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.lut.LUTPicker
import com.opencapture.openpocketcine.settings.DisplayToggleItem
import com.opencapture.openpocketcine.settings.GlassPillSlider
import com.opencapture.openpocketcine.settings.PanelCloseButton
import com.opencapture.openpocketcine.settings.SettingsActionPill
import com.opencapture.openpocketcine.settings.SettingsColorDot
import com.opencapture.openpocketcine.settings.SettingsColorDots
import com.opencapture.openpocketcine.settings.SettingsCrushClipSegmented
import com.opencapture.openpocketcine.settings.SettingsDashScale
import com.opencapture.openpocketcine.settings.SettingsGroupCard
import com.opencapture.openpocketcine.settings.SettingsInlineRow
import com.opencapture.openpocketcine.settings.SettingsNumberField
import com.opencapture.openpocketcine.settings.SettingsPalette
import com.opencapture.openpocketcine.settings.SettingsPercentSlider
import com.opencapture.openpocketcine.settings.SettingsRowCard
import com.opencapture.openpocketcine.settings.SettingsSegmented
import com.opencapture.openpocketcine.settings.SettingsSwitchGraphic
import com.opencapture.openpocketcine.settings.SettingsSwitchInlineRow
import com.opencapture.openpocketcine.settings.SettingsSwitchRow
import com.opencapture.openpocketcine.settings.SettingsValueText
import com.opencapture.openpocketcine.settings.settingsClickable
import java.io.File
import java.util.Locale
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
    const val CACHE_FULL_RESOLUTION =
        "Download the original camera file when you open a clip. Off keeps only the 720p proxy to save space. Share needs the original — connect the camera if it is not cached."
    const val FEED_UPSCALER =
        "How the live-view frame is enlarged to fill the panel. The camera sends far fewer pixels than the panel has, so something always does this. Off is a plain sample, Fast is a fixed sharpening kernel, and Quality is the OS spatial upscaler.\n\nAI is different in kind: it is a machine-learning model that INFERS detail the camera never captured. It gives the sharpest-looking picture, but the fine texture it adds is invented — plausible rather than real — so it can suggest crispness the lens did not record. Judge critical focus on Quality or Fast, and treat AI as a viewing aid rather than evidence.\n\nOnly the options this device supports are shown."
    const val FALSE_COLOR_SCALE =
        "The camera color mode selects D-Log, D-Log2, Rec.709, or HLG automatically. " +
            "PStops marks minimum exposure, −3, 18% gray, skin, +2, and three clip-relative " +
            "highlight levels over luminance grayscale. IRE uses RED Video Mode-style monitor " +
            "ranges on the WAVE axis: paper black at 0, D-Log2 18% grey at 30.50, live-tap EI " +
            "ceiling at 100. Limits paints only shadow and highlight warnings, leaving other " +
            "colors untouched."
    const val FALSE_COLOR_REFERENCE =
        "Show a compact color key over live view while False Color is active."
    const val PEAKING_SENSITIVITY =
        "Higher sensitivity catches finer edges but can get noisy on detailed scenes."
    const val PEAKING_COLOR = "Choose the edge color that stays readable over your typical scene."
    const val ZEBRA_UNITS =
        "Switch between native 0-255 encoded codes and a 0-100 monitoring IRE scale."
    const val ZEBRA_HIGHLIGHT =
        "High zebra warns when bright detail approaches clipping after the active log curve is compensated."
    const val ZEBRA_MIDTONE =
        "Midtone zebra gives a curve-compensated reference band for faces or key subject exposure."
    const val WAVEFORM_BRIGHTNESS =
        "Raise trace intensity when the waveform is hard to read in bright light."
    const val PARADE_BRIGHTNESS = "Raise trace intensity when channel separation is hard to see."
    const val VECTORSCOPE_ZOOM =
        "Magnifies only the chroma trace; the graticule stays at unity. The vectorscope reads the monitor image (your active LUT, or the built-in display tone map), where chroma is meaningful."
    const val VECTORSCOPE_BRIGHTNESS =
        "Raise trace intensity when the chroma plot is hard to read."
    const val TRAFFIC_LIGHTS_COMPENSATION =
        "Stops of crush/clip tolerance before a channel indicator glows. Shared with the histogram traffic lights."
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

internal object OperatorLinkHealth {
    const val TARGET_FPS = 25.0

    fun bars(
        isLive: Boolean,
        videoPackets: Int,
        hasVideoFormat: Boolean,
        measuredFps: Double = -1.0,
    ): Int {
        if (!isLive) return 0
        if (measuredFps > 0.0) {
            val score = ((measuredFps / TARGET_FPS) * 100.0).coerceIn(0.0, 100.0)
            val rounded = kotlin.math.round(score).toInt()
            if (rounded <= 0) return 1
            return ((rounded + 24) / 25).coerceIn(1, 4)
        }
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

    fun compactFps(incoming: String): String {
        val compact = if (incoming.endsWith(".00")) incoming.dropLast(3) else incoming
        return compact.ifEmpty { "—" }
    }

    fun formatMeasuredFps(fps: Double): String {
        if (fps <= 0.0) return ""
        val rounded = kotlin.math.round(fps)
        return if (kotlin.math.abs(fps - rounded) < 0.05) {
            rounded.toInt().toString()
        } else {
            String.format(Locale.US, "%.2f", fps)
        }
    }

    fun fpsChipLabel(
        isLive: Boolean,
        recovering: Boolean,
        measuredFps: Double,
        phase: ConnectionPhase,
    ): String {
        if (phase == ConnectionPhase.FAILED) return "FAIL"
        if (recovering) return "RECOV"
        if (measuredFps > 0.0) return compactFps(formatMeasuredFps(measuredFps))
        return if (!isLive && phase == ConnectionPhase.IDLE) "—" else "LINK"
    }

    fun liveTileDetail(
        isLive: Boolean,
        cameraName: String,
        fpsLabel: String,
        phaseLabel: String,
    ): String = if (isLive) "$cameraName · BLE + Wi-Fi · $fpsLabel FPS" else phaseLabel
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

internal fun lutLookLabel(
    selection: String,
    enabled: Boolean = true,
    colorMode: Int = -1,
    family: String = "pocket",
    cameraName: String? = null,
): String {
    val source =
        LutLookResolver.resolve(
            selection = selection,
            lutOn = true,
            colorMode = colorMode,
            family = family,
            cameraName = cameraName,
        )
    return LutLookResolver.statusLabel(enabled, selection, source)
}

internal fun toggledCleanPins(current: Set<String>, toolKey: String): Set<String> {
    val next = current.toMutableSet()
    if (!next.add(toolKey)) next.remove(toolKey)
    return OperatorPrefs.resolvedCleanPins(next)
}

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
    FALSE_COLOR("False Color"),
    WAVEFORM("Waveform"),
    HISTOGRAM("Histogram"),
    PEAKING("Peaking"),
    ZEBRA("Zebra"),
    PARADE("Parade"),
    VECTORSCOPE("Vectorscope"),
    TRAFFIC_LIGHTS("Traffic Lights"),
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
    val recovery by model.session.recoveryState.collectAsState()
    val status by model.session.status.collectAsState()
    var tick by remember { mutableIntStateOf(0) }
    var lastFrames by remember { mutableIntStateOf(0) }
    var lastTickAt by remember { mutableStateOf(0L) }
    var measuredFps by remember { mutableStateOf(0.0) }
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

    val density = LocalDensity.current
    val bar = LocalImmersiveBarInsets.current
    CompositionLocalProvider(LocalMonitorGlass provides null) {
    Box(
        Modifier
            .fillMaxSize()
            .background(LiveDesign.background)
            .pointerInput(Unit) { detectTapGestures {} }
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .padding(
                start = with(density) { bar.left.toDp() },
                top = with(density) { bar.top.toDp() },
                end = with(density) { bar.right.toDp() },
                bottom = with(density) { bar.bottom.toDp() },
            ),
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
                        fpsLabel = fpsLabel,
                        hasVideoFormat = model.session.hasVideoFormat,
                        onDisconnect = model::disconnect,
                    )
                    SettingsContentPane(
                        model = model,
                        isLive = isLive,
                        phaseLabel = phaseLabel,
                        bars = bars,
                        statusColorMode = status.colorMode,
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
                        fpsLabel = fpsLabel,
                        hasVideoFormat = model.session.hasVideoFormat,
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
                            statusColorMode = status.colorMode,
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
                    .padding(start = 16.dp, top = 22.dp),
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
    fpsLabel: String,
    hasVideoFormat: Boolean,
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
                SessionControls(isLive, phaseLabel, bars, cameraName, fpsLabel, hasVideoFormat, onDisconnect)
            }
        }
        if (stacked) {
            SessionControls(isLive, phaseLabel, bars, cameraName, fpsLabel, hasVideoFormat, onDisconnect)
        }
    }
}

@Composable
private fun SessionControls(
    isLive: Boolean,
    phaseLabel: String,
    bars: Int,
    cameraName: String,
    fpsLabel: String,
    hasVideoFormat: Boolean,
    onDisconnect: () -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        if (isLive) {
            SettingsActionPill(
                title = "Disconnect",
                icon = OpcIcon.UNPLUG,
                tint = LiveDesign.rec,
                background = LiveDesign.rec.copy(alpha = 0.16f),
                onClick = onDisconnect,
            )
        }
        SettingsLiveTile(
            isLive = isLive,
            phaseLabel = phaseLabel,
            bars = bars,
            cameraName = cameraName,
            fpsLabel = fpsLabel,
            hasVideoFormat = hasVideoFormat,
        )
    }
}

@Composable
private fun SettingsTabRail(model: AppModel, hapticsEnabled: Boolean, view: View) {
    Column(
        Modifier
            .width(146.dp)
            .fillMaxHeight()
            .panelGlass(ChromeShape)
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
    val scroll = rememberScrollState()
    Row(
        modifier
            .fillMaxWidth()
            .panelGlass(ChromeShape)
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
            .background(if (selected) LiveDesign.surface else LiveDesign.surface.copy(alpha = 0f), ChromeShape)
            .settingsClickable(role = Role.Tab) {
                if (tab != model.operatorSettingsTab) operatorHaptic(view, hapticsEnabled)
                model.operatorSettingsTab = tab
            }
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(
            Modifier
                .width(6.dp)
                .height(26.dp)
                .background(
                    if (selected) LiveDesign.accent else LiveDesign.accent.copy(alpha = 0f),
                    CircleShape,
                ),
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
    statusColorMode: Int,
    expandedDisp: PocketDispMode?,
    onExpandDisp: (PocketDispMode?) -> Unit,
    onLegal: (LegalKind) -> Unit,
    onClearCache: () -> Unit,
    onOpenLut: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tab = model.operatorSettingsTab
    Column(
        modifier
            .fillMaxSize()
            .background(LiveDesign.surface, ChromeShape)
            .clip(ChromeShape)
            .border(1.dp, LiveDesign.hairline, ChromeShape)
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
                        .border(1.dp, LiveDesign.accentDim, CircleShape)
                        .padding(horizontal = 10.dp, vertical = 6.dp),
            )
        }
        Spacer(Modifier.height(10.dp))
        key(tab) {
            val scroll = rememberScrollState()
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
                        OperatorSettingsTab.ASSIST -> AssistRows(model, statusColorMode, onOpenLut)
                        OperatorSettingsTab.CONTROLS -> ControlsRows(model)
                        OperatorSettingsTab.DISPLAY ->
                            DisplayRows(model, isLive, expandedDisp, onExpandDisp)
                        OperatorSettingsTab.STORAGE -> StorageRows(model, onClearCache)
                        OperatorSettingsTab.SYSTEM -> SystemRows(onLegal)
                    }
                }
                if (scroll.canScrollForward) {
                    ScrollMoreCue(Modifier.align(Alignment.BottomCenter))
                }
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
    if (FeedUpscaler.supported.size > 1) {
        val context = LocalContext.current
        var upscaler by remember { mutableStateOf(OperatorPrefs.feedUpscaler(context)) }
        SettingsRowCard(title = "Processing") {
            SettingsInlineRow("Feed Upscaler", SettingsHelpCopy.FEED_UPSCALER, showTopDivider = false) {
                SettingsSegmented(
                    options = FeedUpscaler.supported.map { it.label },
                    selected = upscaler.label,
                    compact = true,
                ) { label ->
                    val next = FeedUpscaler.fromStored(label)
                    upscaler = next
                    OperatorPrefs.setFeedUpscaler(context, next)
                }
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
private fun AssistRows(model: AppModel, statusColorMode: Int, onOpenLut: () -> Unit) {
    val assist = model.assist
    val isPortrait = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT

    if (isPortrait) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FalseColorAssistCard(assist)
            ZebraAssistCard(assist, statusColorMode)
            WaveformAssistCard(assist)
            ParadeAssistCard(assist)
            HistogramAssistCard(assist)
            VectorscopeAssistCard(assist)
            PeakingAssistCard(assist)
            TrafficLightsAssistCard(assist)
        }
    } else {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FalseColorAssistCard(assist)
                WaveformAssistCard(assist)
                HistogramAssistCard(assist)
                PeakingAssistCard(assist)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ZebraAssistCard(assist, statusColorMode)
                ParadeAssistCard(assist)
                VectorscopeAssistCard(assist)
                TrafficLightsAssistCard(assist)
            }
        }
    }

    SettingsRowCard(title = "LUT") {
        SettingsInlineRow("Look", SettingsHelpCopy.LUT_LOOK, showTopDivider = false) {
            SettingsValueText(
                lutLookLabel(
                    selection = model.lutSelection,
                    enabled = assist.lutOn,
                    colorMode = statusColorMode,
                    family = model.session.connectedCamera?.model?.family ?: "pocket",
                    cameraName = model.session.connectedCamera?.name,
                ),
            )
        }
        SettingsInlineRow("Choose look") {
            SettingsActionPill(title = "Open", onClick = onOpenLut)
        }
    }
}

@Composable
private fun FalseColorAssistCard(assist: LiveAssistState) {
    SettingsRowCard(
        title = "False Color",
        onReset = {
            assist.setFalseColor(scale = FalseColorScale.STOPS, reference = true)
        },
    ) {
        SettingsInlineRow(
            "Scale",
            SettingsHelpCopy.FALSE_COLOR_SCALE,
            showTopDivider = false,
            stacked = true,
        ) {
            SettingsSegmented(
                options = listOf("PStops", "IRE", "Limits"),
                selected = assist.falseColorScale.menuLabel,
            ) { label ->
                assist.setFalseColor(scale = FalseColorScale.fromMenuLabel(label))
            }
        }
        SettingsSwitchRow(
            title = "Reference Display",
            isOn = assist.falseColorReference,
            help = SettingsHelpCopy.FALSE_COLOR_REFERENCE,
            stacked = true,
        ) {
            assist.setFalseColor(reference = !assist.falseColorReference)
        }
    }
}

@Composable
private fun PeakingAssistCard(assist: LiveAssistState) {
    SettingsRowCard(
        title = "Peaking",
        onReset = { assist.setPeaking(color = PeakingColor.RED, sense = PeakingSense.MED) },
    ) {
        SettingsInlineRow(
            "Sensitivity",
            SettingsHelpCopy.PEAKING_SENSITIVITY,
            showTopDivider = false,
            stacked = true,
        ) {
            SettingsSegmented(
                options = PeakingSense.entries.map { it.label },
                selected = assist.peakingSensitivity.label,
            ) { label ->
                assist.setPeaking(sense = PeakingSense.fromPersisted(label))
            }
        }
        SettingsInlineRow("Color", SettingsHelpCopy.PEAKING_COLOR, stacked = true) {
            SettingsColorDots(
                dots = SettingsPalette.peaking,
                selectedName = assist.peakingColor.label,
            ) { name ->
                assist.setPeaking(color = PeakingColor.fromPersisted(name))
            }
        }
    }
}

@Composable
private fun ZebraAssistCard(assist: LiveAssistState, colorMode: Int) {
    SettingsRowCard(
        title = "Zebra",
        onReset = {
            assist.updateZebraUnit(ZebraUnit.IRE)
            assist.setZebraHighlight(enabled = true, ire = LiveZebra.HIGHLIGHT_IRE, color = ZebraPaint.WHITE)
            assist.setZebraMidtone(enabled = true, ire = LiveZebra.MIDTONE_IRE, color = ZebraPaint.AMBER)
        },
    ) {
        SettingsInlineRow(
            "Units",
            SettingsHelpCopy.ZEBRA_UNITS,
            showTopDivider = false,
            stacked = true,
        ) {
            SettingsSegmented(
                options = listOf("0-255", "IRE"),
                selected = assist.zebraUnit.editorLabel,
            ) { label ->
                assist.updateZebraUnit(ZebraUnit.fromEditorLabel(label))
            }
        }
        val transfer = MonitorTransfer.fromColorMode(colorMode)
        val maximum = ZebraEditor.editorMaximum(assist.zebraUnit)
        ZebraZoneRow(
            title = "Highlight",
            help = SettingsHelpCopy.ZEBRA_HIGHLIGHT,
            enabled = assist.zebraHighlight,
            value = ZebraEditor.displayValue(assist.zebraHighlightIRE, assist.zebraUnit, transfer),
            maximum = maximum,
            selectedColor = assist.zebraHighlightColor.label,
            palette = SettingsPalette.highlight,
            onEnabled = { assist.setZebraHighlight(enabled = !assist.zebraHighlight) },
            onValue = {
                assist.setZebraHighlight(ire = ZebraEditor.ireFromDisplay(it, assist.zebraUnit, transfer))
            },
            onColor = { assist.setZebraHighlight(color = ZebraPaint.fromPersisted(it)) },
        )
        ZebraZoneRow(
            title = "Midtone",
            help = SettingsHelpCopy.ZEBRA_MIDTONE,
            enabled = assist.zebraMidtone,
            value = ZebraEditor.displayValue(assist.zebraMidtoneIRE, assist.zebraUnit, transfer),
            maximum = maximum,
            selectedColor = assist.zebraMidtoneColor.label,
            palette = SettingsPalette.midtone,
            onEnabled = { assist.setZebraMidtone(enabled = !assist.zebraMidtone) },
            onValue = {
                assist.setZebraMidtone(ire = ZebraEditor.ireFromDisplay(it, assist.zebraUnit, transfer))
            },
            onColor = { assist.setZebraMidtone(color = ZebraPaint.fromPersisted(it)) },
        )
    }
}

@Composable
private fun ZebraZoneRow(
    title: String,
    help: String,
    enabled: Boolean,
    value: Int,
    maximum: Int,
    selectedColor: String,
    palette: List<SettingsColorDot>,
    onEnabled: () -> Unit,
    onValue: (Int) -> Unit,
    onColor: (String) -> Unit,
) {
    SettingsInlineRow(title = title, help = help, stacked = true) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.settingsClickable(role = Role.Switch, onClick = onEnabled)) {
                SettingsSwitchGraphic(isOn = enabled)
            }
            SettingsNumberField(value = value.coerceIn(0, maximum), maximum = maximum, onChange = onValue)
            Spacer(Modifier.weight(1f))
            SettingsColorDots(dots = palette, selectedName = selectedColor, onSelect = onColor)
        }
    }
}

@Composable
private fun WaveformAssistCard(assist: LiveAssistState) {
    SettingsRowCard(
        title = "Waveform",
        onReset = { assist.setWaveform(mode = WaveformMode.RGB, brightness = 100, guides = ScopeGuides()) },
    ) {
        SettingsInlineRow("Mode", showTopDivider = false, stacked = true) {
            SettingsSegmented(
                options = WaveformMode.entries.map { it.label },
                selected = assist.waveMode.label,
            ) { label ->
                assist.setWaveform(mode = WaveformMode.fromPersisted(label))
            }
        }
        SettingsInlineRow("Brightness", SettingsHelpCopy.WAVEFORM_BRIGHTNESS, stacked = true) {
            SettingsPercentSlider(value = assist.waveBrightness, range = 0..200) {
                assist.setWaveform(brightness = it)
            }
        }
        ScopeGuideRows(assist.waveGuides) { assist.setWaveform(guides = it) }
    }
}

@Composable
private fun ParadeAssistCard(assist: LiveAssistState) {
    SettingsRowCard(
        title = "Parade",
        onReset = { assist.setParade(mode = ParadeMode.RGB, brightness = 100, guides = ScopeGuides()) },
    ) {
        SettingsInlineRow("Mode", showTopDivider = false, stacked = true) {
            SettingsSegmented(
                options = ParadeMode.entries.map { it.label },
                selected = assist.paradeMode.label,
            ) { label ->
                assist.setParade(mode = ParadeMode.fromPersisted(label))
            }
        }
        SettingsInlineRow("Brightness", SettingsHelpCopy.PARADE_BRIGHTNESS, stacked = true) {
            SettingsPercentSlider(value = assist.paradeBrightness, range = 0..200) {
                assist.setParade(brightness = it)
            }
        }
        ScopeGuideRows(assist.paradeGuides) { assist.setParade(guides = it) }
    }
}

@Composable
private fun HistogramAssistCard(assist: LiveAssistState) {
    SettingsRowCard(
        title = "Histogram",
        onReset = {
            assist.setHistogram(traffic = true, compensation = CrushClipCompensation.ZERO)
        },
    ) {
        SettingsSwitchRow(
            title = HistogramAssist.TRAFFIC_LIGHTS_TITLE,
            isOn = assist.histoTrafficLights,
            help = HistogramAssist.TRAFFIC_LIGHTS_HELP,
            showTopDivider = false,
            stacked = true,
        ) {
            assist.setHistogram(traffic = !assist.histoTrafficLights)
        }
        SettingsInlineRow(
            title = HistogramAssist.COMPENSATION_TITLE,
            help = HistogramAssist.COMPENSATION_HELP,
            stacked = true,
        ) {
            CrushClipControl(assist.crushClipCompensation) { assist.setHistogram(compensation = it) }
        }
    }
}

@Composable
private fun VectorscopeAssistCard(assist: LiveAssistState) {
    SettingsRowCard(
        title = "Vectorscope",
        onReset = { assist.setVectorscope(zoom = VectorscopeZoom.X1, brightness = 100) },
    ) {
        SettingsInlineRow(
            "Trace Zoom",
            SettingsHelpCopy.VECTORSCOPE_ZOOM,
            showTopDivider = false,
            stacked = true,
        ) {
            SettingsSegmented(
                options = VectorscopeZoom.entries.map { it.label },
                selected = assist.vectorZoom.label,
            ) { label ->
                assist.setVectorscope(zoom = VectorscopeZoom.fromPersisted(label))
            }
        }
        SettingsInlineRow("Brightness", SettingsHelpCopy.VECTORSCOPE_BRIGHTNESS, stacked = true) {
            SettingsPercentSlider(value = assist.vectorBrightness, range = 0..200) {
                assist.setVectorscope(brightness = it)
            }
        }
    }
}

@Composable
private fun TrafficLightsAssistCard(assist: LiveAssistState) {
    SettingsRowCard(
        title = "Traffic Lights",
        onReset = { assist.setCompensation(CrushClipCompensation.ZERO) },
    ) {
        SettingsInlineRow(
            title = HistogramAssist.COMPENSATION_TITLE,
            help = SettingsHelpCopy.TRAFFIC_LIGHTS_COMPENSATION,
            showTopDivider = false,
            stacked = true,
        ) {
            CrushClipControl(assist.crushClipCompensation) { assist.setCompensation(it) }
        }
    }
}

@Composable
private fun CrushClipControl(selected: CrushClipCompensation, onSelect: (CrushClipCompensation) -> Unit) {
    SettingsCrushClipSegmented(
        options = CrushClipCompensation.entries.map { it.label to it.compactLabel },
        selectedLabel = selected.label,
    ) { label ->
        CrushClipCompensation.entries.firstOrNull { it.label == label }?.let(onSelect)
    }
}

@Composable
private fun ScopeGuideRows(guides: ScopeGuides, onChange: (ScopeGuides) -> Unit) {
    SettingsSwitchRow("Safe Border Clip", isOn = guides.clip, stacked = true) {
        onChange(guides.copy(clip = !guides.clip))
    }
    SettingsSwitchRow("Safe Border Crush", isOn = guides.crush, stacked = true) {
        onChange(guides.copy(crush = !guides.crush))
    }
    SettingsSwitchRow("Middle Gray", isOn = guides.middle, stacked = true) {
        onChange(guides.copy(middle = !guides.middle))
    }
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
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                GlassPillSlider(
                    value = model.gimbalStickSensitivity,
                    range = 1..5,
                    onChange = { next ->
                        if (next != model.gimbalStickSensitivity) {
                            operatorHaptic(view, model.hapticsEnabled)
                            model.updateGimbalStickSensitivity(next)
                        }
                    },
                    modifier = Modifier.weight(1f),
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
        SettingsGroupCard(
            title = mode.settingsTitle,
            caption = mode.settingsCaption,
            onReset = {
                operatorHaptic(view, model.hapticsEnabled)
                resetDispChrome(model, mode)
            },
            captionMaxLines = Int.MAX_VALUE,
            expanded = expandedDisp == mode,
            onExpandToggle = {
                operatorHaptic(view, model.hapticsEnabled)
                onExpandDisp(if (expandedDisp == mode) null else mode)
            },
        ) {
            DispSectionBody(model, mode, isLive, view)
        }
    }
}

@Composable
private fun DispSectionBody(model: AppModel, mode: PocketDispMode, isLive: Boolean, view: View) {
    if (isLive) {
        SettingsActionPill(
            title = "Edit view",
            modifier = Modifier.padding(vertical = 8.dp),
            onClick = {
                operatorHaptic(view, model.hapticsEnabled)
                model.homePanel = null
                model.beginChromeEditing(mode)
            },
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
    dispToggleSpecs.forEach { spec ->
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
    val assist = model.assist
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        CleanPinTool.entries.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                row.forEach { tool ->
                    val on = assist.pinned.any { it.name == tool.key }
                    DisplayToggleItem(
                        title = tool.title,
                        isOn = on,
                        modifier = Modifier.weight(1f),
                        onToggle = {
                            operatorHaptic(view, model.hapticsEnabled)
                            val next = toggledCleanPins(assist.pinned.map { it.name }.toSet(), tool.key)
                            assist.pinned =
                                next.mapNotNull(LiveAssistTool::fromPersisted).toSet()
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
private fun StorageRows(model: AppModel, onClearCache: () -> Unit) {
    val context = LocalContext.current
    val view = LocalView.current
    val bytes = OperatorMediaCache.byteCount(context)
    val cacheLabel =
        if (OperatorMediaCache.existingDir(context) == null) "Empty" else formatCacheSize(bytes)
    SettingsRowCard {
        SettingsInlineRow("Frame.io", SettingsHelpCopy.FRAME_IO, showTopDivider = false) {
            SettingsValueText("Not configured")
        }
    }
    SettingsRowCard {
        SettingsSwitchInlineRow(
            title = "Full Resolution Caching",
            isOn = model.cacheFullResolution,
            help = SettingsHelpCopy.CACHE_FULL_RESOLUTION,
            showTopDivider = false,
        ) {
            operatorHaptic(view, model.hapticsEnabled)
            model.updateCacheFullResolution(!model.cacheFullResolution)
        }
        SettingsInlineRow("Local Media Cache", SettingsHelpCopy.LOCAL_CACHE) {
            SettingsValueText(cacheLabel)
        }
        SettingsInlineRow("Clear Cache", SettingsHelpCopy.CLEAR_CACHE) {
            Text(
                "Clear",
                style = LiveType.ui(13f, FontWeight.SemiBold),
                color = LiveDesign.rec,
                modifier = Modifier.settingsClickable(role = Role.Button, onClick = onClearCache),
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
            SettingsActionPill("Open") { openUrl(context, OpenPocketCineLinks.PRIVACY) }
        }
        SettingsInlineRow("Terms", "How you can use OpenPocketCine.") {
            SettingsActionPill("Open") { openUrl(context, OpenPocketCineLinks.TERMS) }
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

internal fun openUrl(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}

private fun operatorHaptic(view: View, enabled: Boolean) {
    if (!enabled) return
    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
}

@Composable
fun OperatorCloseButton(onClose: () -> Unit, modifier: Modifier = Modifier) {
    PanelCloseButton(onClick = onClose, modifier = modifier)
}

@Composable
private fun SettingsLiveTile(
    isLive: Boolean,
    phaseLabel: String,
    bars: Int,
    cameraName: String,
    fpsLabel: String,
    hasVideoFormat: Boolean,
) {
    val tint =
        when {
            !isLive -> LiveDesign.faint
            bars >= 3 -> LiveDesign.good
            bars == 2 -> LiveDesign.accent
            bars == 1 -> LiveDesign.rec
            hasVideoFormat -> LiveDesign.accent
            else -> LiveDesign.faint
        }
    val lit =
        when {
            !isLive -> 0
            bars > 0 -> bars.coerceIn(0, 4)
            hasVideoFormat -> 2
            else -> 1
        }
    val detail = OperatorLinkHealth.liveTileDetail(isLive, cameraName, fpsLabel, phaseLabel)
    Row(
        Modifier
            .background(LiveDesign.surface, ChromeShape)
            .border(1.dp, LiveDesign.hairline, ChromeShape)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(8.dp).background(tint, CircleShape))
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
                        .background(
                            if (index < lit) tint.copy(alpha = 0.52f + index * 0.12f) else LiveDesign.hairline,
                            CircleShape,
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
        OpcIcon(
            icon = OpcIcon.CHEVRON_DOWN,
            contentDescription = null,
            tint = LiveDesign.muted,
            modifier = Modifier.size(10.dp),
        )
    }
}
