package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.diagnostics.ManualProblemReportDelivery
import com.opencapture.openpocketcine.diagnostics.AppDiagnostics
import com.opencapture.openpocketcine.assists.scopeDisplayCeiling

import com.opencapture.openpocketcine.feed.fromColorMode

import com.opencapture.openpocketcine.pairing.lastSSID
import com.opencapture.openpocketcine.pairing.modelName

import com.opencapture.opencine.dji.GamepadGimbalStick
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
import com.opencapture.openpocketcine.assists.HistogramAssist
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.assists.LiveZebra
import com.opencapture.openpocketcine.assists.ParadeMode
import com.opencapture.openpocketcine.assists.PeakingColor
import com.opencapture.opencine.dji.CameraCommands
import com.opencapture.openpocketcine.assists.PeakingSense
import com.opencapture.openpocketcine.assists.ScopeGuides
import com.opencapture.openpocketcine.assists.VectorscopeZoom
import com.opencapture.openpocketcine.assists.WaveformMode
import com.opencapture.openpocketcine.assists.ZebraEditor
import com.opencapture.openpocketcine.assists.ZebraPaint
import com.opencapture.openpocketcine.assists.ZebraUnit
import com.opencapture.opencine.dji.ConnectionPhase
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.diagnostics.ManualProblemReportDialog
import com.opencapture.openpocketcine.feed.FeedUpscaler
import com.opencapture.openpocketcine.feed.LutLookResolver
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

object SettingsHelpCopy {
    const val CURRENT_TRANSPORT =
        "Pocket uses Bluetooth to pair, then the camera's own Wi-Fi for HEVC. USB-C, hotspot, and HDMI capture are not in this build."
    const val PHASE = "Where the BLE → Wi-Fi → datalink handshake is right now."
    const val CAMERA_WIFI =
        "SSID joined for this session. The password stays in the Android Keystore on this phone."
    const val SAVED_CAMERAS =
        "Pair from the home list. Settings does not start a new pair \u2014 that stays on Your cameras."
    const val EDIT_VIEW = "Opens the monitor with an eye on each element you can show or hide."
    const val FRAME_IO =
        "Sign in to upload clips from the share popup. Frame.io needs the internet, so the phone hops off the camera Wi‑Fi for the upload."
    const val RECORD_CONFIRMATION = "Ask before starting or stopping recording to prevent mistaps."
    const val SHOOTING_MODE =
        "Switch the camera between Video, Photo and the time-based modes. The camera reports " +
            "the mode back, so this follows a change made on the body itself."
    const val HAPTICS =
        "Short confirmation pulses for switches, settings, and gimbal limits. A connected controller also rumbles at a stop."
    const val JOYSTICK_SENSITIVITY =
        "How far a stick throw moves the gimbal \u2014 on-screen and a connected game controller. Small throws crawl; full throw is fastest. 4 is the captured feel. 5 reaches full speed sooner; 1 is the slowest."
    const val VIRTUAL_JOYSTICK_SIZE =
        "How large the on-screen stick is. Medium is the default. Large is easier to grab; Small keeps more of the picture clear."
    const val VIRTUAL_JOYSTICK_INVERT_PAN =
        "Reverse left and right on the on-screen stick. Off is the default. A game controller is unchanged."
    const val VIRTUAL_JOYSTICK_INVERT_TILT =
        "Reverse up and down on the on-screen stick. Off is the default. A game controller is unchanged."
    const val VIRTUAL_JOYSTICK_DEADZONE =
        "Ignore small movements near the center. The default is 8%. Increase it to make the center less sensitive."
    const val VIRTUAL_JOYSTICK_RESPONSE =
        "Standard keeps the current feel. Linear responds evenly. Fine makes small movements gentler."
    const val GIMBAL_JOYSTICK =
        "Which analog stick pans and tilts. Left is the default. The other stick does not move the gimbal."
    const val GAMEPAD =
        "A connected game controller. The selected gimbal joystick pans and tilts. Cross/A records. Circle/B recenters. Square/X is rotate-180. Triangle/Y tracks a face. L1/R1 jump zoom out/in. L2/R2 hold-to-zoom (deeper is faster). D-pad up/down ISO, left/right shutter. Unplug rests the stick. On-screen stick wins while you hold it."
    const val KEEP_SCREEN_AWAKE =
        "Prevents auto-lock while OpenPocketCine is open. A monitor should stay lit. Android may still dim when the device overheats."
    const val HDR_DISPLAY =
        "Outdoor panel brightness, not a grade. WAVE, HISTO, PARADE, VECTOR, zebras and false color still read the decoded camera signal \u2014 judge exposure there, not from how bright the picture looks. Screen recording drops back to a normal SDR picture so the file is not HDR-boosted. This is not the camera's HDR/HLG color mode. Off by default."
    const val THEME = "Charcoal field-monitor chrome with Sky Blue accents, tuned for low reflection on set."
    const val SUPPORT = "Connection, live view, controls, and troubleshooting."
    const val REPORT = "Opens a public issue form on GitHub for this project."
    const val REPORT_PROBLEM =
        "Tell us what happened. Technical details stay off unless you include them. You can attach up to three photos. Sending does not turn on automatic reports."
    const val RELIABILITY_REPORTS =
        "Optional: send crash, hang, live-feed reports and session health counts to OpenCapture through Sentry. Off by default. Turn off anytime without losing app features. Uploads wait until you leave camera Wi-Fi. Automatic reports exclude all images. No footage or GPS location. Sentry receives the connection IP; stored event IP and derived geography are removed. See Reporting Privacy below."
    const val RELIABILITY_UNAVAILABLE =
        "This build cannot send automatic reports. You can still share or delete reports stored on this phone."
    const val FEATURE = "Start an idea in this project's feature-request discussion."
    const val SOURCE =
        "View the OpenPocketCine project on GitHub. Opening this may leave the camera Wi-Fi if that is the only network."
    const val LINK_HEALTH = "How healthy the camera link is right now \u2014 delivery, not radio RSSI."
    const val CLEAR_CACHE =
        "Removes downloaded clip files from this phone. The clip list stays so you can cache them again from the camera."
    const val LUT_LOOK = "Looks apply on this phone. The file on the camera is unchanged."
    const val PROTOCOL =
        "Camera control speaks DUML over Bluetooth and the camera's Wi-Fi. No DJI SDK is bundled or required."
    const val APP_VERSION = "Current OpenPocketCine build from the native project metadata."
    const val LOCAL_CACHE = "Originals and playback proxies downloaded from the camera."
    const val CACHE_FULL_RESOLUTION =
        "Download the original camera file when you open a clip. Off keeps only the 720p proxy to save space. Share needs the original \u2014 connect the camera if it is not cached."
    const val FEED_UPSCALER =
        "How the live-view frame is enlarged to fill the panel. The camera sends far fewer pixels than the panel has, so something always does this. Off is a plain sample, Fast is a fixed sharpening kernel, and Quality is the OS spatial upscaler.\n\nAI is different in kind: it is a machine-learning model that INFERS detail the camera never captured. It gives the sharpest-looking picture, but the fine texture it adds is invented \u2014 plausible rather than real \u2014 so it can suggest crispness the lens did not record. Judge critical focus on Quality or Fast, and treat AI as a viewing aid rather than evidence.\n\nOnly the options this device supports are shown."
    const val FALSE_COLOR_SCALE =
        "The camera color mode selects D-Log, D-Log2, Rec.709, or HLG automatically. " +
            "CineStop paints five stops around 18% gray, read through the " +
            "camera's log curve: dark green −2, yellow-green −1, gray at 18%, light pink +1 " +
            "(skin), soft yellow +2 (upper skin limit). Red is clipped and violet is crushed; " +
            "other shadows are flat dark gray and other highlights flat light gray. " +
            "Video paints video-level IRE stripes (green 41–48, pink 61–70, red clip) " +
            "over luminance grayscale. IRE paints six video-level zones over " +
            "luminance grayscale: purple crush, blue near-black, green 18% gray, pink one " +
            "stop over, yellow near clip, red clip. On log, Video and IRE read the camera's " +
            "Rec.709 look (709) or the raw signal (LOG), set under Read. Limits paints only shadow and highlight warnings, leaving other colors untouched."
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

    fun score(bars: Int): Int = MonitorLinkHealth.score(bars)

    fun caption(isLive: Boolean, bars: Int): String {
        if (!isLive) return "No live path."
        if (bars <= 0) return "Waiting for the link."
        return when (MonitorLinkHealth.band(score(bars))) {
            MonitorLinkHealth.Band.STABLE -> "Link is clean. · Stable"
            MonitorLinkHealth.Band.WATCH -> "Some loss on the link. · Watch"
            MonitorLinkHealth.Band.POOR -> "Link is weak. · Poor"
        }
    }

    fun compactFps(incoming: String): String {
        val compact = if (incoming.endsWith(".00")) incoming.dropLast(3) else incoming
        return compact.ifEmpty { "\u2014" }
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
        return if (!isLive && phase == ConnectionPhase.IDLE) "\u2014" else "LINK"
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
            File(context.noBackupFilesDir, "OpenPocketCine/media"),
            File(context.filesDir, "OpenPocketCine/media"),
            File(context.filesDir, "media-cache"),
            File(context.cacheDir, "media-cache"),
        )

    fun existingDir(context: Context): File? = candidates(context).firstOrNull { it.isDirectory }

    fun byteCount(context: Context): Long {
        val dir = existingDir(context) ?: return 0L
        return dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    /** Same canonical root object retires gallery writes before removing cache bytes. */
    suspend fun clearOwned(root: com.opencapture.opencine.appkit.MonitorMediaCacheRoot, fallback: () -> Unit) {
        if (!root.root.isDirectory) { fallback(); return }
        root.root.listFiles()?.forEach { cameraDir ->
            if (!cameraDir.isDirectory || cameraDir.name.startsWith(".retiring-") || cameraDir.name.startsWith(".clearing-")) return@forEach
            root.directory(cameraDir.name).clear(preserving = listOf("index.json"))
        }
    }

    fun clear(context: Context) {
        val mediaRoot = listOf(File(context.noBackupFilesDir, "OpenPocketCine/media"),
            File(context.filesDir, "OpenPocketCine/media")).firstOrNull { it.isDirectory }
        if (mediaRoot != null) {
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
    ND("ND", "ND Suggestion"),
    GUIDES("GUIDES", "Guides"),
    GRID("GRID", "Grid"),
    CROSSHAIR("CROSS", "Crosshair"),
    DESQUEEZE("DESQ", "Anamorphic Desqueeze"),
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
    EV("EV Meter"),
    DESQUEEZE("Anamorphic Desqueeze"),
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
            help = com.opencapture.openpocketcine.assists.AnamorphicDesqueeze.HELP,
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
    val segments = com.opencapture.openpocketcine.assists.FalseColorReference.segments(
        assist.falseColorScale, transfer, ceiling = assist.scopeDisplayCeiling)
    val markers = if (assist.falseColorScale.usesSceneStops)
        com.opencapture.openpocketcine.assists.FalseColorReference.sceneStopMarkers(transfer, ceiling = assist.scopeDisplayCeiling)
        else emptyList()
    return com.opencapture.monitorui.MonitorFalseColorReferenceValues(
        subtitle = assist.falseColorScale.menuLabel,
        segments = segments.mapIndexed { index, segment ->
            com.opencapture.monitorui.MonitorFalseColorReferenceSegment(index, segment.lowerFraction,
                segment.upperFraction, segment.band.red, segment.band.green, segment.band.blue)
        },
        markers = markers.mapIndexed { index, marker ->
            com.opencapture.monitorui.MonitorFalseColorReferenceMarker(index, marker.label, marker.fraction)
        }, axisLabels = com.opencapture.openpocketcine.assists.FalseColorReference.axisLabels(assist.falseColorScale))
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

internal fun openUrl(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri())) }
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
