package com.opencapture.openpocketcine

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import android.os.Build
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.diagnostics.AutomaticReportsPrompt
import com.opencapture.openpocketcine.diagnostics.ManualProblemReport
import com.opencapture.openpocketcine.diagnostics.ReliabilityReporting
import com.opencapture.openpocketcine.diagnostics.ReliabilityReportingConsent
import com.opencapture.openpocketcine.pairing.PairingExperience
import com.opencapture.openpocketcine.pairing.SavedCamerasExperience
import com.opencapture.openpocketcine.pairing.StartupColors
import com.opencapture.openpocketcine.pairing.StartupConnectionCopy
import com.opencapture.openpocketcine.pairing.isBusy
import com.opencapture.openpocketcine.pairing.pocketRuntimePermissions
import com.opencapture.openpocketcine.pairing.startupBackdrop
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    private val composeFirstFrameDrawn = AtomicBoolean(false)
    private lateinit var model: AppModel
    var hideSystemNavigation = false
    var playbackHidesSystemNavigation = false

    fun updateSystemBars() {
        applyMonitorSystemBars(window, hideSystemNavigation || playbackHidesSystemNavigation)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        splashScreen.setKeepOnScreenCondition { !composeFirstFrameDrawn.get() }
        super.onCreate(savedInstanceState)
        model = AppModel(applicationContext)
        model.gimbalGamepad.ensureListening(this, model)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        window.isNavigationBarContrastEnforced = false
        window.attributes.layoutInDisplayCutoutMode =
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        setContent {
            SideEffect { composeFirstFrameDrawn.set(true) }
            OpenPocketCineTheme {
                val haptics = rememberOperatorHaptics { model.hapticsEnabled }
                CompositionLocalProvider(LocalOperatorHaptics provides haptics) {
                    OpenPocketCineApp(model)
                }
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return
        updateSystemBars()
    }

    override fun onPause() {
        if (::model.isInitialized) model.session.noteSceneBecameInactive()
        ManualProblemReport.setForeground(false)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        ManualProblemReport.setForeground(true)
        if (::model.isInitialized) {
            model.session.noteSceneBecameActive()
            model.gimbalGamepad.ensureListening(this, model)
        }
    }

    override fun onDestroy() {
        if (::model.isInitialized) model.close()
        super.onDestroy()
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (::model.isInitialized && model.gimbalGamepad.onMotion(event, model)) return true
        return super.dispatchGenericMotionEvent(event)
    }

    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (::model.isInitialized && model.gimbalGamepad.onKey(event, model)) return true
        return super.dispatchKeyEvent(event)
    }
}

@Composable
private fun OpenPocketCineApp(model: AppModel) {
    val phase by model.session.phaseFlow.collectAsState()
    var launchSplashVisible by remember { mutableStateOf(true) }
    val activity = LocalActivity.current
    val permissions = pocketRuntimePermissions()
    fun permissionsAreGranted(): Boolean {
        val current = activity ?: return false
        return permissions.all {
            ContextCompat.checkSelfPermission(current, it) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }
    }
    var permissionsGranted by remember { mutableStateOf(permissionsAreGranted()) }
    val enableBluetooth =
        rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            if (permissionsAreGranted()) model.session.startScan()
        }
    fun requestBluetoothOn() {
        runCatching { enableBluetooth.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)) }
    }
    val launcher =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            permissionsGranted = permissionsAreGranted()
            if (permissionsGranted) beginDiscovery(model) { requestBluetoothOn() }
        }

    LaunchedEffect(model.keepScreenAwake, activity) {
        val window = activity?.window ?: return@LaunchedEffect
        if (model.keepScreenAwake) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    LaunchedEffect(Unit) {
        model.prepareStartup()
        if (permissionsAreGranted()) {
            beginDiscovery(model, onBluetoothOff = { requestBluetoothOn() })
        } else {
            launcher.launch(permissions)
        }
        delay(2_250)
        launchSplashVisible = false
        model.showsLaunchSplash = false
    }

    val showLive = phase == ConnectionPhase.LIVE || model.session.holdsMonitor
    LaunchedEffect(model.hdrDisplay, model.screenCaptured, activity) {
        HdrDisplay.apply(activity, enabled = model.hdrDisplayActive)
    }
    DisposableEffect(activity) {
        val windowManager = activity?.windowManager
        if (activity == null || windowManager == null || Build.VERSION.SDK_INT < 35) {
            return@DisposableEffect onDispose { }
        }
        val callback = java.util.function.Consumer<Int> { state ->
            model.screenCaptured = state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
        }
        // Knowing about screen recording only dims the HDR boost. A ROM that
        // refuses the callback must cost the boost, never the whole app.
        try {
            windowManager.addScreenRecordingCallback(activity.mainExecutor, callback)
        } catch (denied: SecurityException) {
            Log.w("OpcHdr", "screen-recording callback denied; the boost stays on while recording", denied)
            return@DisposableEffect onDispose { }
        }
        onDispose { runCatching { windowManager.removeScreenRecordingCallback(callback) } }
    }
    val hideNavigation = showLive && model.liveOperatorPanel == null
    LaunchedEffect(activity, hideNavigation) {
        (activity as? MainActivity)?.hideSystemNavigation = hideNavigation
        (activity as? MainActivity)?.updateSystemBars()
    }

    Box(Modifier.fillMaxSize().startupBackdrop()) {
        if (showLive) {
            LiveViewScreen(model)
        } else {
            LinkExperience(
                model = model,
                permissionsGranted = permissionsGranted,
                onRequestPermissions = { launcher.launch(permissions) },
                onEnableBluetooth = { requestBluetoothOn() },
            )
        }
        LaunchSplashOverlay(visible = launchSplashVisible)
        if (model.homePanel != null && !showLive) {
            AppPanelHost(model)
        }
        var showAutomaticPrompt by remember {
            mutableStateOf(ReliabilityReportingConsent.shouldOfferAutomaticPrompt())
        }
        if (!launchSplashVisible && !showLive && showAutomaticPrompt && model.homePanel != AppPanel.PRIVACY) {
            AutomaticReportsPrompt(
                onPrivacy = { model.homePanel = AppPanel.PRIVACY },
                onEnable = {
                    ReliabilityReporting.setConsent(true)
                    showAutomaticPrompt = false
                },
                onNotNow = {
                    ReliabilityReporting.setConsent(false)
                    showAutomaticPrompt = false
                },
            )
        }
    }
}

private fun beginDiscovery(model: AppModel, onBluetoothOff: () -> Unit = {}) {
    model.session.startScan()
    if (!model.session.radioOn.value) onBluetoothOff()
}

@Composable
private fun LinkExperience(
    model: AppModel,
    permissionsGranted: Boolean,
    onRequestPermissions: () -> Unit,
    onEnableBluetooth: () -> Unit,
) {
    val density = LocalDensity.current
    val layoutDir = LocalLayoutDirection.current
    val configuration = LocalConfiguration.current
    val camerasHome = !model.shouldShowWizard
    val landscapeHome = configuration.screenWidthDp > configuration.screenHeightDp
    val homeSide = with(density) {
        val leading = WindowInsets.safeDrawing.getLeft(this, layoutDir).toDp()
        val trailing = WindowInsets.safeDrawing.getRight(this, layoutDir).toDp()
        com.opencapture.monitorui.MonitorLayoutPolicy.pageSideInsets(
            landscape = true, safeLeading = leading.value, safeTrailing = trailing.value,
        ).first.dp
    }
    Column(
        Modifier
            .fillMaxSize()
            // Cameras landscape mirrors the larger cutout onto both sides so the list stays
            // centered; pairing and live chrome keep their own edges.
            .then(
                if (camerasHome && landscapeHome) {
                    Modifier
                        .padding(start = homeSide, end = homeSide)
                        .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Vertical))
                } else {
                    Modifier.windowInsetsPadding(WindowInsets.safeDrawing)
                },
            )
            .padding(vertical = 16.dp),
    ) {
        Box(Modifier.weight(1f).padding(
            start = if (model.shouldShowWizard) 14.dp else 18.dp,
            end = if (model.shouldShowWizard) 14.dp else 18.dp,
            top = if (model.shouldShowWizard) 0.dp else 8.dp,
        )) {
            if (model.shouldShowWizard) {
                PairingExperience(model, permissionsGranted, onRequestPermissions, onEnableBluetooth)
            } else {
                SavedCamerasExperience(model)
            }
        }
    }
}

@Composable
private fun LaunchSplashOverlay(visible: Boolean) {
    AnimatedVisibility(
        visible = visible,
        enter = androidx.compose.animation.EnterTransition.None,
        exit = fadeOut(tween(durationMillis = 350)),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color(0xFF0E0E0E))) {
            val landscape = maxWidth >= maxHeight
            val logoSize = minOf(maxWidth * if (landscape) 0.16f else 0.28f, 96.dp)
            val logoCorner = logoSize * 0.22f
            val wordmarkSp = if (landscape) 34.sp else 30.sp
            @Composable
            fun OpcMark() {
                Image(
                    painter = painterResource(R.drawable.opc_app_logo),
                    contentDescription = "OpenPocketCine",
                    modifier = Modifier
                        .size(logoSize)
                        .clip(RoundedCornerShape(logoCorner)),
                    contentScale = ContentScale.Fit,
                )
            }
            if (landscape) {
                Row(
                    Modifier.fillMaxSize().padding(horizontal = max(32.dp, maxWidth * 0.08f)),
                    horizontalArrangement = Arrangement.spacedBy(max(32.dp, maxWidth * 0.06f), Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OpcMark()
                    Text(
                        "OpenPocketCine",
                        color = BrandColors.ink,
                        style = LiveType.display(wordmarkSp.value, FontWeight.Bold),
                    )
                }
            } else {
                Column(
                    Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically),
                ) {
                    OpcMark()
                    Text(
                        "OpenPocketCine",
                        color = BrandColors.ink,
                        style = LiveType.display(wordmarkSp.value, FontWeight.Bold),
                    )
                }
            }
        }
    }
}
