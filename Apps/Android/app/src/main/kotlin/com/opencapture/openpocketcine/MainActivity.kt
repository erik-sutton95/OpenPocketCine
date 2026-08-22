package com.opencapture.openpocketcine

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.pairing.PairingExperience
import com.opencapture.openpocketcine.pairing.SavedCamerasExperience
import com.opencapture.openpocketcine.pairing.StartupColors
import com.opencapture.openpocketcine.pairing.StartupConnectionCopy
import com.opencapture.openpocketcine.pairing.StartupHeader
import com.opencapture.openpocketcine.pairing.isBusy
import com.opencapture.openpocketcine.pairing.pocketRuntimePermissions
import com.opencapture.openpocketcine.pairing.startupBackdrop
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    private val composeFirstFrameDrawn = AtomicBoolean(false)
    private lateinit var model: AppModel

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        splashScreen.setKeepOnScreenCondition { !composeFirstFrameDrawn.get() }
        super.onCreate(savedInstanceState)
        model = AppModel(applicationContext)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        window.isNavigationBarContrastEnforced = false
        window.attributes.layoutInDisplayCutoutMode =
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        applyImmersiveSystemBars(window)
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
        if (hasFocus) applyImmersiveSystemBars(window)
    }

    override fun onPause() {
        if (::model.isInitialized) model.session.noteSceneBecameInactive()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (::model.isInitialized) model.session.noteSceneBecameActive()
    }

    override fun onDestroy() {
        if (::model.isInitialized) model.close()
        super.onDestroy()
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

    LaunchedEffect(activity) {
        val window = activity?.window ?: return@LaunchedEffect
        applyImmersiveSystemBars(window)
    }

    val showLive = phase == ConnectionPhase.LIVE || model.session.holdsMonitor
    ImmersiveSystemBarCycle {
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
    val phase by model.session.phaseFlow.collectAsState()
    val reconnecting by model.session.isReconnecting.collectAsState()
    val busy = phase.isBusy() || reconnecting
    val headerTitle =
        when {
            model.shouldShowWizard -> "Connection setup"
            model.savedCameras.isNotEmpty() -> "Operator Setup"
            else -> "Find your camera"
        }
    val statusTitle =
        StartupConnectionCopy.statusTitle(
            phase,
            isDiscovering = phase == ConnectionPhase.SCANNING || (model.shouldShowWizard && phase != ConnectionPhase.LIVE),
            isReconnecting = reconnecting,
        )
    val context = LocalContext.current
    val density = LocalDensity.current
    val bar = LocalImmersiveBarInsets.current
    val barStart by animateDpAsState(with(density) { bar.left.toDp() }, label = "barStart")
    val barTop by animateDpAsState(with(density) { bar.top.toDp() }, label = "barTop")
    val barEnd by animateDpAsState(with(density) { bar.right.toDp() }, label = "barEnd")
    val barBottom by animateDpAsState(with(density) { bar.bottom.toDp() }, label = "barBottom")
    Column(
        Modifier
            .fillMaxSize()
            .padding(start = barStart, top = 16.dp + barTop, end = barEnd, bottom = 16.dp + barBottom),
    ) {
        Box(Modifier.padding(horizontal = 20.dp)) {
            StartupHeader(
                title = headerTitle,
                statusTitle = statusTitle,
                isBusy = busy,
                onPrivacy = { openUrl(context, OpenPocketCineLinks.PRIVACY) },
                onTerms = { openUrl(context, OpenPocketCineLinks.TERMS) },
            )
        }
        Box(Modifier.weight(1f).padding(start = 20.dp, end = 24.dp, top = 8.dp)) {
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
