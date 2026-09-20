package com.opencapture.openpocketcine

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import com.opencapture.monitorui.MonitorBackdropSource
import com.opencapture.monitorui.LocalMonitorBackdrops
import com.opencapture.monitorui.monitorBackdropSource
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
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
import androidx.core.graphics.scale
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
        if (intent.getStringExtra("surface") == "reporting-consent") {
            // Preview the real layout without reading or changing reporting consent.
            setContent {
                OpenPocketCineTheme {
                    com.opencapture.openpocketcine.diagnostics.AutomaticReportsPrompt(
                        onPrivacy = {}, onEnable = {}, onNotNow = {},
                    )
                }
            }
            return
        }
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
                    if (intent.getStringExtra("surface") == "catalog") {
                        ReviewClipCapabilities(intent.getBooleanExtra("clipStar", false))
                    } else {
                        ReviewMonitor(model, capabilities, sourceAspect,
                            intent.getFloatExtra("safeTop", 0f), intent.getFloatExtra("safeBottom", 0f),
                            intent.getBooleanExtra("patterned", false))
                    }
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
        if (::model.isInitialized) model.close()
        super.onDestroy()
    }
}

@Composable
private fun ReviewMonitor(model: AppModel, capabilities: MonitorCapabilities, sourceAspect: Float,
    safeTop: Float, safeBottom: Float, patterned: Boolean = false) {
    val status = remember(capabilities) {
        CameraStatus(batteryPercent = 80, storageTotalMb = 131072, storageFreeMb = 109568,
            timecode = if (capabilities.timecode) "15:39:50:00" else null,
            shootingMode = 1, iso = 1600, isoIndex = 7, shutterDenom = 50,
            expoMode = CameraCommands.EXPO_MANUAL, colorMode = CameraCommands.COLOR_DLOG2,
            resolutionCode = CameraCommands.RES_4K, fps = 25, fpsIndex = 2,
            wbMode = 6, wbKelvin = 5600, focusMode = 2, focusTrack = 0, audioChannel = 2, audioMetersLeft = -21.0, audioMetersRight = -14.0)
    }
    LaunchedEffect(model.liveOperatorPanel) {
        if (model.liveOperatorPanel != null) model.assist.configureTool = null
    }
    var locked by remember { mutableStateOf(false) }
    var sheet by remember { mutableStateOf<LiveSheet?>(null) }
    val context = LocalContext.current
    val image = remember(context, patterned) {
        if (patterned) context.assets.open("monitor_backdrop_reference.png").use { BitmapFactory.decodeStream(it) } else null
    }
    val backdrop = remember(image) { MonitorBackdropSource().apply {
        this.image = image?.let { it.scale(180, 120) }
    } }
    val readoutRegions = remember { com.opencapture.monitorui.MonitorReadoutRegions() }
    CompositionLocalProvider(
        LocalMonitorBackdrops provides if (image != null) listOf(backdrop) else emptyList(),
        com.opencapture.monitorui.LocalMonitorReadoutRegions provides readoutRegions,
    ) {
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
        val cluster = if (zones != null) portraitOnFeedControls(width, zones.assistToolbar.minY,
            capabilities.gimbal) else layout.gimbalCluster(capabilities.gimbal)
        // Optional pattern exercises the production widgets against a passive sampled source.
        if (image != null) Image(image.asImageBitmap(), null,
            Modifier.liveModuleFrame(layout.onFeed).monitorBackdropSource(backdrop), contentScale = ContentScale.FillBounds)
        else Box(Modifier.liveModuleFrame(layout.onFeed).background(Color(0xFF4A4C48)))
        com.opencapture.openpocketcine.assists.LiveAssistLayer(model.assist, status, focus = null,
            feedFrame = layout.onFeed, placementFrame = ChromeRect(6f, safeTop + 6f, width - 12f,
                (zones?.systemBar?.minY ?: (height - safeBottom)) - safeTop - 12f), locked = locked,
            onOpenOptions = { tool, frame -> model.assist.longPressAnchor = frame; model.assist.configureTool = tool })
        if (zones != null) {
            LivePortraitChrome(model, layout, zones, status, locked, { locked = !locked }, sheet,
                { sheet = it }, model.assist, { model.assist.configureTool = it }, true, false,
                fpsLabel = "25", bars = 4, sourceIsVertical = sourceAspect < 1f,
                capabilities = capabilities)
        } else {
            LandscapeChrome(model, layout, status, locked, { locked = !locked }, sheet,
                { sheet = it }, model.assist, { model.assist.configureTool = it }, true, false,
                "25", 4, false, {}, cluster.zoom, cluster.stick, cluster.controls, false, {},
                1.0, false, capabilities = capabilities)
        }
        if (!locked) sheet?.let {
            LivePickerHost(it, width, height, 0f, 0f, safeTop, safeBottom, zones?.systemBar?.minY,
                model, status, false, { sheet = it }, zones?.topBar?.maxY)
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
}

/** Real shared card layouts with identical data and different optional actions. */
@Composable
private fun ReviewClipCapabilities(canFavorite: Boolean) {
    var favorite by remember { mutableStateOf(false) }
    val clip = com.opencapture.monitorui.MonitorClipValue(
        "fixture", "Fixture clip", "4K · 25p", "00:12", "LOCAL", favorite)
    val toggle: (() -> Unit)? = if (canFavorite) ({ favorite = !favorite }) else null
    androidx.compose.foundation.layout.Column(
        Modifier.fillMaxSize().background(com.opencapture.monitorui.MonitorPalette.background)
            .padding(16.dp),
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(16.dp),
    ) {
        androidx.compose.material3.Text("Camera capabilities",
            style = com.opencapture.monitorui.MonitorTypography.text(20f))
        for (list in listOf(false, true)) {
            com.opencapture.monitorui.MonitorClipCard(clip, list, selecting = false, selected = false,
                onOpen = {}, onSelect = {}, onFavorite = toggle) {
                Box(Modifier.fillMaxSize().background(Color(0xFF4A4C48)))
            }
        }
    }
}
