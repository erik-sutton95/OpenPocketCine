package com.opencapture.openpocketcine

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.opencapture.monitorui.MonitorCapabilities
import com.opencapture.openpocketcine.assists.MonitorAssistInspector
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus

/**
 * Debug-only, deterministic visual review of production chrome. This activity
 * never starts discovery, connects a camera, starts a decoder, or fabricates a
 * connected session. Intents choose the fixture capabilities and source aspect.
 */
class MonitorPreviewActivity : ComponentActivity() {
    private lateinit var model: AppModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        WindowCompat.getInsetsController(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        model = AppModel(applicationContext)
        val capabilities = MonitorCapabilities(
            gimbal = intent.getBooleanExtra("gimbal", true),
            zoom = intent.getBooleanExtra("zoom", true),
            focus = intent.getBooleanExtra("focus", true),
            timecode = intent.getBooleanExtra("timecode", true),
        )
        val sourceAspect = intent.getFloatExtra("aspect", 16f / 9f).takeIf { it > 0f } ?: 16f / 9f
        setContent {
            OpenPocketCineTheme {
                CompositionLocalProvider(LocalMonitorGlass provides remember { MonitorGlass(GlassTier.FLAT) }) {
                    ReviewMonitor(model, capabilities, sourceAspect,
                        intent.getFloatExtra("safeTop", 0f), intent.getFloatExtra("safeBottom", 0f))
                    when (model.liveOperatorPanel) {
                        LiveOperatorPanel.SETTINGS -> OperatorSetupScreen(model) { model.liveOperatorPanel = null }
                        LiveOperatorPanel.MEDIA -> com.opencapture.openpocketcine.media.MediaLibraryScreen(model) {
                            model.liveOperatorPanel = null
                        }
                        null -> Unit
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        model.close()
        super.onDestroy()
    }
}

@Composable
private fun ReviewMonitor(model: AppModel, capabilities: MonitorCapabilities, sourceAspect: Float,
    safeTop: Float, safeBottom: Float) {
    val status = remember(capabilities) {
        CameraStatus(batteryPercent = 80, storageTotalMb = 131072, storageFreeMb = 109568,
            timecode = if (capabilities.timecode) "15:39:50:00" else null,
            shootingMode = 1, iso = 1600, isoIndex = 7, shutterDenom = 50,
            expoMode = CameraCommands.EXPO_MANUAL, colorMode = CameraCommands.COLOR_DLOG2,
            resolutionCode = CameraCommands.RES_4K, fps = 25, fpsIndex = 2,
            wbMode = 6, wbKelvin = 5600, focusMode = 2, audioChannel = 2)
    }
    LaunchedEffect(model.liveOperatorPanel) {
        if (model.liveOperatorPanel != null) model.assist.configureTool = null
    }
    var locked by remember { mutableStateOf(false) }
    var sheet by remember { mutableStateOf<LiveSheet?>(null) }
    val frames = remember { mutableStateMapOf<LiveSheet, ChromeRect>() }
    BoxWithConstraints(Modifier.fillMaxSize().background(LiveDesign.background)) {
        val width = maxWidth.value
        val height = maxHeight.value
        val portrait = height > width
        val zones = if (portrait) portraitZones(width, height, safeTop, safeBottom,
            model.assistClean, sourceAspect < 1f || model.portraitFeedAspect == PortraitFeedAspect.FILL,
            0f, sourceAspect) else null
        val fitted = LiveMonitorLayout.fit(width, height, 0f, 0f, safeTop, safeBottom,
            !model.assistClean, pictureAspect = sourceAspect)
        val layout = if (zones != null) fitted.copy(feed = zones.feed, picture = zones.feed, topDeck = zones.topBar, capture = zones.controls) else fitted
        val cluster = if (zones != null) portraitOnFeedControls(layout.onFeed,
            model.portraitFeedAspect == PortraitFeedAspect.FILL, zones.controls.height + 10f,
            zones.controls.minY - 8f, capabilities.gimbal) else layout.gimbalCluster(capabilities.gimbal)
        // Uniform fixture makes geometry, alpha and clipping differences visible.
        Box(Modifier.liveModuleFrame(layout.onFeed).background(Color(0xFF4A4C48)))
        if (zones != null) {
            LivePortraitChrome(model, layout, zones, status, locked, { locked = !locked }, sheet,
                { sheet = it }, model.assist, { model.assist.configureTool = it }, true, false,
                fpsLabel = "25", bars = 4, sourceIsVertical = sourceAspect < 1f,
                capabilities = capabilities, onTileFrame = { key, rect -> frames[key] = rect })
        } else {
            LandscapeChrome(model, layout, status, locked, { locked = !locked }, sheet,
                { sheet = it }, model.assist, { model.assist.configureTool = it }, true, false,
                "25", 4, false, {}, cluster.zoom, cluster.stick, cluster.controls, false, {},
                1.0, false, capabilities = capabilities,
                onTileFrame = { key, rect -> frames[key] = rect })
        }
        if (!locked) sheet?.let {
            LivePickerHost(it, frames, zones?.controls ?: layout.capture, zones?.topBar ?: layout.topDeck,
                width, height, 0f, 0f, 0f, 0f, 0f, zones?.controls?.minY,
                model, status, false, { sheet = it })
        }
        if (!locked && capabilities.gimbal && model.liveGimbalPanel == LiveGimbalPanel.SHEET) {
            LiveGimbalSheetHost(model, layout, cluster, 0f, 0f, 0f, 0f)
        }
        if (!locked && model.liveOperatorPanel == null) model.assist.configureTool?.let { tool ->
            MonitorAssistInspector(tool, model.assist, model, status.colorMode,
                width, height, 0f, 0f, 0f, zones?.controls?.minY ?: height,
                onDismiss = { model.assist.configureTool = null })
        }
    }
}
