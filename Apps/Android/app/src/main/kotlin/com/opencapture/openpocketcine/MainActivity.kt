package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.applyMonitorSystemBars
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.opencine.appkit.rememberOperatorHaptics
import com.opencapture.opencine.runtime.MonitorHDRDisplay
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.openpocketcine.diagnostics.AppDiagnostics
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.provider.Settings
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
import androidx.compose.ui.platform.InfiniteAnimationPolicy
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.createLifecycleAwareWindowRecomposer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.sp
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.opencapture.opencine.appkit.diagnostics.AutomaticReportsPrompt
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.multiview.MultiviewQualificationPolicy
import androidx.activity.compose.BackHandler
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.opencapture.opencine.appkit.AppShell
import com.opencapture.opencine.appkit.ShellBrand
import com.opencapture.opencine.appkit.ShellActions
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.appkit.PairingWizard
import com.opencapture.opencine.platform.LocalVPNProbe
import com.opencapture.openpocketcine.diagnostics.ManualProblemReportDialog
import com.opencapture.opencine.appkit.DiscoveryPermissions
import com.opencapture.openpocketcine.pairing.PairingCallouts
import com.opencapture.opencine.appkit.PermissionGate
import com.opencapture.openpocketcine.pairing.rememberPermissionGate
import com.opencapture.openpocketcine.pairing.startupBackdrop
import java.util.concurrent.atomic.AtomicBoolean
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private var reviewState: String? = null
    private val composeFirstFrameDrawn = AtomicBoolean(false)
    internal lateinit var model: AppModel
        private set
    var hideSystemNavigation = false
    var playbackHidesSystemNavigation = false

    fun updateSystemBars() {
        applyMonitorSystemBars(window, hideSystemNavigation || playbackHidesSystemNavigation)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        splashScreen.setKeepOnScreenCondition { !composeFirstFrameDrawn.get() }
        super.onCreate(savedInstanceState)
        // Debug review only: a scripted connection state of the cameras and pair pages.
        val review = if (BuildConfig.DEBUG) intent?.getStringExtra("opv_review_state") else null
        model = AppModel(applicationContext, discovers = true, review = review)
        if (review == "multiview") model.showsMultiview = true
        if (review?.startsWith("pair-") == true) model.pairing = true
        if (review != null) lifecycleScope.launch { ReviewCameras.start(review, model) }
        reviewState = review
        model.gimbalGamepad.ensureListening(this, model)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        window.isNavigationBarContrastEnforced = false
        window.attributes.layoutInDisplayCutoutMode =
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        // Compose's Popup polls its anchor with an infinite frame loop, so the always-mounted
        // assist palette alone woke Main every vsync (120 Hz) over live view. Pace every
        // infinite loop (Popup polls, REC pulse, spinners) like iOS's 30 Hz pulse timeline.
        val recomposer = window.decorView.createLifecycleAwareWindowRecomposer(PacedInfiniteAnimations, lifecycle)
        setContent(parent = recomposer) {
            SideEffect { composeFirstFrameDrawn.set(true) }
            OpenPocketCineTheme {
                val haptics = rememberOperatorHaptics { model.hapticsEnabled }
                CompositionLocalProvider(LocalOperatorHaptics provides haptics) {
                    OpenPocketCineApp(model)
                    ReviewCameras.AddSetup(reviewState, model)
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
        if (::model.isInitialized) model.shell.setSceneActive(false)
        AppDiagnostics.manualReport.setForeground(false)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        AppDiagnostics.manualReport.setForeground(true)
        if (::model.isInitialized) {
            model.shell.setSceneActive(true)
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
    lateinit var discovery: PermissionGate
    val enableBluetooth =
        rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            if (discovery.granted) model.session.startScan()
        }
    fun requestBluetoothOn() {
        // Without Nearby devices the enable prompt throws; Bluetooth settings still work.
        runCatching { enableBluetooth.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)) }
            .recoverCatching { activity?.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)) }
            .onFailure { DiagnosticCenter.log("warning", "ble", "enable", "bluetooth enable unavailable ${it.javaClass.simpleName}") }
    }
    discovery = rememberPermissionGate("discovery", DiscoveryPermissions.discovery()) {
        beginDiscovery(model) { requestBluetoothOn() }
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
        if (discovery.granted) {
            beginDiscovery(model, onBluetoothOff = { requestBluetoothOn() })
        } else if (!discovery.needsSettings) {
            discovery.request()
        }
        delay(2_250)
        launchSplashVisible = false
        model.showsLaunchSplash = false
    }

    val shell by model.shell.state.collectAsState()
    val showLive = shell.monitor != null
    LaunchedEffect(model.hdrDisplay, model.screenCaptured, activity) {
        MonitorHDRDisplay.apply(activity, enabled = model.hdrDisplayActive)
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
    val hideNavigation = (showLive && model.shellState.cover == null) || model.showsMultiview
    LaunchedEffect(activity, hideNavigation) {
        (activity as? MainActivity)?.hideSystemNavigation = hideNavigation
        (activity as? MainActivity)?.updateSystemBars()
    }

    Box(Modifier.fillMaxSize().startupBackdrop()) {
        if (model.showsMultiview && !showLive) {
            com.opencapture.openpocketcine.multiview.MultiviewScreen(model, onClose = model::closeMultiview)
        } else {
            LinkExperience(
                model = model,
                discovery = discovery,
                onEnableBluetooth = { requestBluetoothOn() },
            )
        }
        LaunchSplashOverlay(visible = launchSplashVisible)
        if (model.showsLegalPanel && !model.showsMultiview) {
            AppPanelHost(model)
        }
        var showAutomaticPrompt by remember {
            mutableStateOf(AppDiagnostics.consent.shouldOfferAutomaticPrompt())
        }
        if (!launchSplashVisible && !showLive && !model.showsMultiview && showAutomaticPrompt &&
            model.homePanel != AppPanel.PRIVACY
        ) {
            AutomaticReportsPrompt(
                product = AppDiagnostics.host.product,
                onPrivacy = { model.homePanel = AppPanel.PRIVACY },
                onEnable = {
                    AppDiagnostics.reporting.setConsent(true)
                    showAutomaticPrompt = false
                },
                onNotNow = {
                    AppDiagnostics.reporting.setConsent(false)
                    showAutomaticPrompt = false
                },
            )
        }
    }
}

/**
 * The pair wizard in OpenPocketCine's words (the Android pair page it has always shown): the four
 * Pocket and Nano pages, and Nearby devices or Bluetooth as the primary action while discovery
 * cannot run.
 */
internal fun pairingWizard(
    label: String,
    joinedNetwork: String?,
    vpnActive: Boolean,
    granted: Boolean,
    needsSettings: Boolean,
    radioOn: Boolean,
) = PairingWizard(
    bodies = listOf(
        "Turn the camera on and keep the phone nearby. Pocket and Nano both appear. Choose the one you want.",
        "If the camera shows Approve, tap it on that camera's screen. First-time pairing can wait up to 90 seconds.",
        "We read the camera's network over Bluetooth, then join its Wi-Fi for you.",
        "Exposure, LUTs and scopes go live as soon as the video link is up.",
    ),
    approveLines = listOf("Look for an Approve / pairing prompt", "Tap it on the camera screen"),
    joinLines = listOf("Leave the camera on. It brings up its own Wi-Fi", "On 5.8 GHz that can take about a minute; we keep trying"),
    label = label,
    joinedNetwork = joinedNetwork,
    vpnActive = vpnActive,
    blocker = when {
        !granted && needsSettings -> "Open Settings"
        !granted -> "Allow ${DiscoveryPermissions.settingsName(DiscoveryPermissions.discovery()).lowercase()}"
        !radioOn -> "Turn Bluetooth on"
        else -> null
    },
)

/** Permission granted or Bluetooth on: look again, unless a camera is connecting or live. */
private fun beginDiscovery(model: AppModel, onBluetoothOff: () -> Unit = {}) {
    val state = model.cameras.state.value
    if (state.attempts.isEmpty() && state.connected == null && !model.isLive) model.session.startScan()
    if (!model.session.radioOn.value) onBluetoothOff()
}

@Composable
private fun LinkExperience(
    model: AppModel,
    discovery: PermissionGate,
    onEnableBluetooth: () -> Unit,
) {
    val context = LocalContext.current
    val state by model.cameras.state.collectAsState()
    // No saved camera opens the pair page, as at first launch.
    val pairing = state.saved.isEmpty() || model.pairing
    var showProblemReport by remember { mutableStateOf(false) }
    var showReportingPrivacy by remember { mutableStateOf(false) }
    val phase by model.session.phaseFlow.collectAsState()
    val radioOn by model.session.radioOn.collectAsState()
    // Main's setup chip menu: Forget only, no Rename setup.
    AppShell(model.shell, ShellBrand("OpenPocketCine", renamesSetups = false),
        ShellActions(
            diagnostics = { DiagnosticCenter.shareReport(context, model.session) },
            reportProblem = { showProblemReport = true },
            multiview = if (MultiviewQualificationPolicy.tileCount > 1) model::openMultiview else null,
            // Pair on a nearby card connects it at once, on the pair page.
            pair = {
                model.shell.beginPairing()
                state.nearby.firstOrNull { it.id == model.cameras.state.value.selection }?.let(model.cameras::connect)
            }),
        monitor = { LiveViewScreen(model) },
        page = { ShellCoverPage(model, it) },
        coverPresentation = com.opencapture.opencine.appkit.ShellCoverPresentation.SHELL,
        pageFrame = { route, content ->
            val pair = route == ShellModel.Route.PAIR
            if (pair) {
                Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(vertical = 16.dp)) {
                    Box(Modifier.weight(1f).padding(horizontal = 14.dp)) {
                        // As the pair page always did: Back stops a connect and leaves the page.
                        BackHandler(enabled = state.attempts.isNotEmpty() || state.saved.isNotEmpty()) {
                            model.cameras.cancelAll()
                            model.shell.endPairing()
                        }
                        content()
                    }
                }
            } else content()
        },
        pairingFlow = pairingWizard(
            label = PairingWizard.phaseLabel(
                when {
                    state.attempts.isEmpty() -> ConnectionPhase.SCANNING
                    phase == ConnectionPhase.IDLE -> ConnectionPhase.CONNECTING_GATT
                    else -> phase
                },
            ),
            joinedNetwork = model.session.joinedSSID, vpnActive = LocalVPNProbe.isActive(context),
            granted = discovery.granted, needsSettings = discovery.needsSettings, radioOn = radioOn,
        ).flow(
            model.cameras, onDone = model.shell::endPairing, rescan = model.session::startScan,
            onBlocker = { if (!discovery.granted) discovery.request() else onEnableBluetooth() },
            content = { PairingCallouts(model, discovery, onEnableBluetooth) },
        ))
    if (showProblemReport) {
        ManualProblemReportDialog(model = model, onClose = { showProblemReport = false }, onPrivacy = { showReportingPrivacy = true })
    }
    if (showReportingPrivacy) {
        Dialog(onDismissRequest = { showReportingPrivacy = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            LegalDocumentScreen(kind = LegalKind.PRIVACY, onClose = { showReportingPrivacy = false })
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

/** Infinite frame loops tick at about 30 Hz instead of every vsync; finite animations are untouched. */
private object PacedInfiniteAnimations : InfiniteAnimationPolicy {
    override suspend fun <R> onInfiniteOperation(block: suspend () -> R): R {
        delay(25)
        return block()
    }
}
