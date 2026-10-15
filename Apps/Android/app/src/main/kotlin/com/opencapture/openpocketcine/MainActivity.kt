package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.LocalMonitorDeliveryCoordinator
import com.opencapture.opencine.cameracontrols.MonitorOperatorDeliveryChrome
import com.opencapture.opencine.cameracontrols.rememberMonitorDeliveryCoordinator
import com.opencapture.openpocketcine.media.PocketMediaShare
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.appkit.DiscoveryRestart
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import com.opencapture.opencine.appkit.MonitorActivityLaunch
import com.opencapture.opencine.appkit.MonitorAppRoot
import com.opencapture.opencine.appkit.MonitorLaunchBrand
import com.opencapture.opencine.appkit.MonitorReportsOffer
import com.opencapture.opencine.appkit.retainedMonitorRoot
import androidx.compose.ui.graphics.Color
import com.opencapture.opencine.appkit.applyMonitorSystemBars
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.opencine.appkit.rememberOperatorHaptics
import com.opencapture.opencine.cameracontrols.MonitorLegalDocumentScreen
import com.opencapture.opencine.cameracontrols.MonitorLegalPage
import com.opencapture.opencine.runtime.MonitorHDRDisplay
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.openpocketcine.diagnostics.AppDiagnostics
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Bundle
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import android.provider.Settings
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.multiview.MultiviewQualificationPolicy
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.opencapture.opencine.appkit.AppShell
import com.opencapture.opencine.appkit.ShellBrand
import com.opencapture.opencine.appkit.ShellActions
import com.opencapture.opencine.appkit.PairingWizard
import com.opencapture.opencine.platform.LocalVPNProbe
import com.opencapture.openpocketcine.diagnostics.ManualProblemReportDialog
import com.opencapture.opencine.appkit.DiscoveryPermissions
import com.opencapture.openpocketcine.pairing.PairingCallouts
import com.opencapture.opencine.appkit.PermissionGate
import com.opencapture.openpocketcine.pairing.rememberPermissionGate
import com.opencapture.openpocketcine.pairing.startupBackdrop

open class MainActivity : ComponentActivity() {
    private val launch = MonitorActivityLaunch()
    internal lateinit var model: AppModel
        private set
    var hideSystemNavigation = false
    var playbackHidesSystemNavigation = false

    fun updateSystemBars() {
        applyMonitorSystemBars(window, hideSystemNavigation || playbackHidesSystemNavigation)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen().setKeepOnScreenCondition { !launch.firstFrameDrawn }
        super.onCreate(savedInstanceState)
        // One model per task: a recreated activity keeps the session; finishing closes it.
        model = retainedMonitorRoot { createModel().also(AppModel::prepareStartup) }
        model.gimbalGamepad.ensureListening(this, model)
        launch.setContent(this) {
            OpenPocketCineTheme {
                val haptics = rememberOperatorHaptics { model.hapticsEnabled }
                // One app-scoped delivery owner: a run outlives the media screen that began it.
                val delivery = rememberMonitorDeliveryCoordinator()
                CompositionLocalProvider(LocalOperatorHaptics provides haptics, LocalMonitorDeliveryCoordinator provides delivery) {
                    OpenPocketCineApp(model)
                    Overlay(model)
                    MonitorOperatorDeliveryChrome(delivery, PocketMediaShare, { MediaHTTP.playbackMIMEType(it.name) })
                }
            }
        }
    }

    /** The activity's root model; the debug review activity scripts its camera port. */
    protected open fun createModel(): AppModel {
        val localReview = MonitorReview.decode(intent)
        return AppModel(applicationContext, discovers = localReview == null, reviewLaunch = localReview).also { model ->
            if (localReview != null) lifecycleScope.launch { MonitorReview.start(applicationContext, model, localReview) }
        }
    }

    /** Drawn over the app; empty outside the debug review activity. */
    @Composable
    protected open fun Overlay(model: AppModel) {}

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

    LaunchedEffect(Unit) {
        if (model.reviewLaunch == null && discovery.granted) {
            beginDiscovery(model, onBluetoothOff = { requestBluetoothOn() })
        } else if (model.reviewLaunch == null && !discovery.needsSettings) {
            discovery.request()
        }
    }

    val shell by model.shell.state.collectAsState()
    val showLive = shell.monitor != null
    LaunchedEffect(model.hdrDisplayActive, activity) {
        MonitorHDRDisplay.apply(activity, enabled = model.hdrDisplayActive)
    }
    val hideNavigation = (showLive && model.shellState.cover == null) || model.showsMultiview
    LaunchedEffect(activity, hideNavigation) {
        (activity as? MainActivity)?.hideSystemNavigation = hideNavigation
        (activity as? MainActivity)?.updateSystemBars()
    }

    MonitorAppRoot(
        brand = MonitorLaunchBrand(R.drawable.opc_app_logo, "OpenPocketCine", Color(0xFF0E0E0E), BrandColors.ink, OpcFonts.sora),
        keepScreenAwake = model.keepScreenAwake || model.showsMultiview,
        reports = MonitorReportsOffer(AppDiagnostics.consent, AppDiagnostics.reporting, AppDiagnostics.host.product) {
            model.homePanel = AppPanel.PRIVACY
        },
        reportsAllowed = model.reviewLaunch == null && !showLive && !model.showsMultiview && model.homePanel != AppPanel.PRIVACY,
        splash = com.opencapture.opencine.appkit.rememberMonitorLaunchSplash(enabled = model.reviewLaunch == null),
        // Knowing about screen recording only dims the HDR boost.
        onScreenRecording = { model.screenCaptured = it },
    ) {
        Box(Modifier.fillMaxSize().startupBackdrop().reviewMetadata(model.reviewLaunch)) {
            val stage = model.multiview?.takeIf { !showLive }
            // The stage is a page over the shell, which keeps its own state underneath.
            Box(if (stage != null) Modifier.clearAndSetSemantics { } else Modifier) {
                LinkExperience(
                    model = model,
                    discovery = discovery,
                    onEnableBluetooth = { requestBluetoothOn() },
                )
            }
            stage?.let { com.opencapture.openpocketcine.multiview.MultiviewScreen(model, it, onClose = model::closeMultiview) }
            if (model.showsLegalPanel && !model.showsMultiview) {
                AppPanelHost(model)
            }
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

/** DJI `startScan` clears the session's reconnect target, so it never interrupts an attempt. */
private val DISCOVERY_RESTART = DiscoveryRestart.WHEN_IDLE

/** Permission granted or Bluetooth on: look again when the integration allows it now. */
private fun beginDiscovery(model: AppModel, onBluetoothOff: () -> Unit = {}) {
    if (DISCOVERY_RESTART.allows(model.cameras.state.value, model.isLive)) model.session.startScan()
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
    // The DJI integration declares its nearby tap (pair at once) and setup naming (none).
    AppShell(model.shell, ShellBrand("OpenPocketCine"),
        ShellActions(
            diagnostics = { DiagnosticCenter.shareReport(context, model.session) },
            reportProblem = { showProblemReport = true },
            multiview = if (MultiviewQualificationPolicy.tileCount > 1) model::openMultiview else null,
        ),
        monitor = { LiveViewScreen(model) },
        page = { ShellCoverPage(model, it) },
        coverPresentation = com.opencapture.opencine.appkit.ShellCoverPresentation.SHELL,
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
            MonitorLegalDocumentScreen(PocketLegalDocuments, MonitorLegalPage.PRIVACY) { showReportingPrivacy = false }
        }
    }
}
