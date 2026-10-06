package com.opencapture.openpocketcine.pairing

import com.opencapture.opencine.appkit.PermissionGate
import com.opencapture.opencine.appkit.DiscoveryPermissions
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.monitorui.MonitorIcon
import com.opencapture.monitorui.MonitorPalette
import com.opencapture.monitorui.MonitorTypography
import com.opencapture.opencine.core.ConnectTarget
import com.opencapture.opencine.core.RouteDraft
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.dji.CameraConnectionSetup
import com.opencapture.opencine.dji.SharedWiFi
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import kotlinx.coroutines.delay

/** A saved camera's DJI setups (SHELL-02 document: camera Wi-Fi is the `ap` route). */
val SavedCamera.modelName: String get() = model
val SavedCamera.lastSSID: String? get() = routes.firstOrNull { it.kind == RouteKind.CAMERA_ACCESS_POINT }?.network
val SavedCamera.wifiSSID: String? get() = routes.firstOrNull { it.kind == RouteKind.INFRASTRUCTURE_NETWORK }?.network
val SavedCamera.hotspotSSID: String? get() = routes.firstOrNull { it.kind == RouteKind.PHONE_HOTSPOT }?.network

fun SavedCamera.ssid(setup: CameraConnectionSetup): String? = when (setup) {
    CameraConnectionSetup.CAMERA_WIFI -> lastSSID
    CameraConnectionSetup.WIFI -> wifiSSID
    CameraConnectionSetup.PHONE_HOTSPOT -> hotspotSSID
}

/**
 * The pair wizard's content: the Swift core, Bluetooth, permission and Location fixes with their
 * actions, then, while choosing a camera, the vendor-app precheck or, after 20 s without a
 * camera, the still-looking tip. A local VPN shows on the wizard's video-link page.
 */
@Composable
fun PairingCallouts(model: AppModel, discovery: PermissionGate, onEnableBluetooth: () -> Unit) {
    val context = LocalContext.current
    val phase by model.session.phaseFlow.collectAsState()
    val radioOn by model.session.radioOn.collectAsState()
    val state by model.cameras.state.collectAsState()
    val permissionsGranted = discovery.granted
    var locationOff by remember { mutableStateOf(false) }
    if (DiscoveryPermissions.discoveryNeedsLocationServices()) {
        LaunchedEffect(Unit) {
            while (true) {
                locationOff = !DiscoveryPermissions.locationServicesOn(context)
                delay(1_000)
            }
        }
    }
    // The tips belong to choosing a camera, as on the pair page this app has always shown.
    val choosing = state.attempts.isEmpty()
    val waitingForCamera = choosing && phase == ConnectionPhase.SCANNING && radioOn && permissionsGranted && !locationOff &&
        state.nearby.isEmpty()
    var slowScan by remember { mutableStateOf(false) }
    LaunchedEffect(waitingForCamera) {
        slowScan = false
        if (!waitingForCamera) return@LaunchedEffect
        delay(SLOW_SCAN_HINT_MS)
        slowScan = true
        DiagnosticCenter.log("info", "ble", "scan", "scan: no camera after ${SLOW_SCAN_HINT_MS / 1_000} s, hint shown")
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (model.coreVersion == null) {
            PairingCallout(
                title = "Swift core",
                body = "Swift core isn't loaded. Build with `just android-core` on an arm64 device.",
                icon = MonitorIcon.TRIANGLE_ALERT,
            )
        }
        if (!radioOn) {
            PairingCallout(
                title = "Bluetooth",
                body = "Turn Bluetooth on so we can find your Pocket.",
                icon = MonitorIcon.RADIO,
                action = "Turn on",
                onAction = onEnableBluetooth,
            )
        }
        if (!permissionsGranted) {
            val name = DiscoveryPermissions.settingsName(DiscoveryPermissions.discovery())
            PairingCallout(
                title = name,
                body = when {
                    discovery.needsSettings ->
                        "Android won’t ask again. Open Settings › Permissions › $name and choose Allow."
                    DiscoveryPermissions.discoveryNeedsLocationServices() ->
                        "Android 10 and 11 need Location to scan for Bluetooth cameras. It is only used to find your Pocket."
                    else -> "Allow Nearby devices so we can find your Pocket over Bluetooth. Location isn’t needed."
                },
                icon = MonitorIcon.RADIO,
                action = if (discovery.needsSettings) "Open Settings" else "Allow",
                onAction = discovery::request,
            )
        }
        if (permissionsGranted && locationOff) {
            PairingCallout(
                title = "Location",
                body = "Android 10 and 11 only find Bluetooth cameras while Location is on.",
                icon = MonitorIcon.RADIO,
                action = "Turn on",
                onAction = { runCatching { context.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)) } },
            )
        }
        if (slowScan && waitingForCamera) {
            PairingCallout(title = "Still looking", body = StartupConnectionCopy.STILL_LOOKING, icon = MonitorIcon.RADIO)
        } else if (choosing) {
            PairingCallout(title = "Before you pair", body = StartupConnectionCopy.PAIRING_PRECHECK, icon = MonitorIcon.TRIANGLE_ALERT)
        }
    }
}

/**
 * The DJI add-route slot: the station-network wizard for a saved camera. The saved setup becomes
 * a [RouteDraft]; the integration keeps the password and moves the camera. Edit setup reopens a
 * failed setup on its password or hotspot page.
 */
@Composable
fun AddSetupSlot(model: AppModel, camera: SavedCamera, done: (RouteDraft?) -> Unit) {
    val context = LocalContext.current
    val wifi = remember { SharedWiFi(context) }
    val failed = (model.cameras.state.collectAsState().value.failures[camera.id]?.target as? ConnectTarget.Saved)
        ?.let { target -> camera.routes.firstOrNull { it.id == target.route }?.kind }
    StationNetworkSetup(
        savedNetworks = model.savedNetworks(),
        currentSsid = wifi::currentSsid,
        hotspotActive = { wifi.address(true) != null },
        scan = model.networkScan(camera),
        connect = { network ->
            done(RouteDraft(if (network.hotspot) RouteKind.PHONE_HOTSPOT else RouteKind.INFRASTRUCTURE_NETWORK, network.ssid, network.password))
            null
        },
        cancel = { done(null) },
        complete = { done(null) },
        camera = camera,
        startPage = when (failed) {
            RouteKind.PHONE_HOTSPOT -> "hotspot"
            RouteKind.INFRASTRUCTURE_NETWORK -> "password"
            else -> "choose"
        },
        startNetwork = camera.wifiSSID.orEmpty(),
    )
}

@Composable
private fun PairingCallout(
    title: String,
    body: String,
    icon: MonitorIcon,
    action: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(11.dp)
    Column(
        Modifier.fillMaxWidth()
            .background(Color.White.copy(alpha = 0.03f), shape)
            .border(1.dp, Color.White.copy(alpha = 0.06f), shape)
            .then(
                if (onAction != null) Modifier.clickable(role = Role.Button, onClick = onAction)
                else Modifier,
            )
            .padding(13.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            Box(
                Modifier.size(26.dp).background(MonitorPalette.accent.copy(alpha = 0.12f), RoundedCornerShape(8.dp)),
                contentAlignment = Alignment.Center,
            ) {
                MonitorIcon(icon, null, Modifier.size(14.dp), MonitorPalette.accent)
            }
            Text(
                title.uppercase(),
                color = MonitorPalette.secondary,
                style = MonitorTypography.text(9f, FontWeight.Bold).copy(letterSpacing = 1.4.sp),
                maxLines = 1,
                modifier = Modifier.weight(1f),
            )
            if (action != null) {
                Text(
                    action,
                    color = MonitorPalette.accent,
                    style = MonitorTypography.text(11f, FontWeight.SemiBold),
                    maxLines = 1,
                )
            }
        }
        Text(
            body,
            color = MonitorPalette.secondary,
            style = MonitorTypography.text(12.5f).copy(lineHeight = 15.5.sp),
        )
    }
}

private const val SLOW_SCAN_HINT_MS = 20_000L
