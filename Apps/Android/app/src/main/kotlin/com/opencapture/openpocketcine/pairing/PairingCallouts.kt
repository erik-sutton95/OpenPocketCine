package com.opencapture.openpocketcine.pairing

import com.opencapture.opencine.appkit.PermissionGate
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.opencapture.opencine.appkit.AddSetupFlow
import com.opencapture.opencine.appkit.AddSetupFlowView
import com.opencapture.opencine.appkit.DiscoveryPermissions
import com.opencapture.opencine.core.StationNetwork
import com.opencapture.opencine.appkit.StationNetworkBrand
import com.opencapture.opencine.appkit.StationNetworkSetup
import com.opencapture.opencine.appkit.StationSetupPage
import com.opencapture.opencine.appkit.stationSetupChooser
import com.opencapture.opencine.dji.MultiviewNetworkStore
import com.opencapture.opencine.core.ConnectTarget
import com.opencapture.opencine.core.RouteDraft
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.dji.CameraConnectionSetup
import com.opencapture.opencine.dji.SharedWiFi
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.opencine.appkit.PairingCalloutCopy
import com.opencapture.opencine.appkit.PairingCalloutStack

/** A saved camera's DJI setups (SHELL-02 document: camera Wi-Fi is the `ap` route). */
val SavedCamera.modelName: String get() = model
val SavedCamera.lastSSID: String? get() = routes.firstOrNull { it.kind == RouteKind.CAMERA_ACCESS_POINT }?.network
val SavedCamera.wifiSSID: String? get() = routes.firstOrNull { it.kind == RouteKind.INFRASTRUCTURE_NETWORK }?.network
val SavedCamera.hotspotSSID: String? get() = routes.firstOrNull { it.kind == RouteKind.PHONE_HOTSPOT }?.network

/** This app's words and camera access-point naming for OpenCine's station-network wizard. */
val POCKET_STATION_BRAND = StationNetworkBrand(appName = "OpenPocketCine", cameraFamily = "Osmo", cameraNetworkPrefix = "osmo")

/** The saved shared networks as the station wizard reads them. */
fun List<MultiviewNetworkStore.Network>.asStationNetworks(): List<StationNetwork> =
    map { StationNetwork(it.ssid, it.password, it.hotspot) }

/** Location for this phone's Wi-Fi name, asked where the name is shown, not at first run. */
@Composable
fun rememberWifiNameAccess(): PermissionGate =
    rememberPermissionGate("wifi-name", DiscoveryPermissions.wifiName, DiscoveryPermissions.wifiNameRequest)

fun SavedCamera.ssid(setup: CameraConnectionSetup): String? = when (setup) {
    CameraConnectionSetup.CAMERA_WIFI -> lastSSID
    CameraConnectionSetup.WIFI -> wifiSSID
    CameraConnectionSetup.PHONE_HOTSPOT -> hotspotSSID
}

/**
 * The pair wizard's content: OpenCine's [PairingCalloutStack] with this app's session and copy.
 * A local VPN shows on the wizard's video-link page.
 */
@Composable
fun PairingCallouts(model: AppModel, discovery: PermissionGate, onEnableBluetooth: () -> Unit) {
    val phase by model.session.phaseFlow.collectAsState()
    val radioOn by model.session.radioOn.collectAsState()
    PairingCalloutStack(
        cameras = model.cameras,
        coreLoaded = model.coreVersion != null,
        scanning = phase == ConnectionPhase.SCANNING,
        radioOn = radioOn,
        discovery = discovery,
        copy = PairingCalloutCopy(
            cameraNoun = "Pocket",
            precheck = StartupConnectionCopy.PAIRING_PRECHECK,
            stillLooking = StartupConnectionCopy.STILL_LOOKING,
        ),
        log = DiagnosticCenter::log,
        onEnableBluetooth = onEnableBluetooth,
    )
}

/**
 * The DJI add-route slot: the station-network wizard for a saved camera. The saved setup becomes
 * a [RouteDraft]; the integration keeps the password and moves the camera. Edit setup reopens a
 * failed setup on its password or hotspot page.
 */
@Composable
fun AddSetupSlot(model: AppModel, camera: SavedCamera, done: (RouteDraft?) -> Unit) {
    AddSetupFlowView(addSetupFlow(model, camera, done))
}

/** Typed shared choice, followed by the app's existing scan/password/hotspot destination. */
@Composable
internal fun addSetupFlow(model: AppModel, camera: SavedCamera, done: (RouteDraft?) -> Unit): AddSetupFlow {
    val context = LocalContext.current
    val wifi = remember { SharedWiFi(context) }
    val failed = (model.cameras.state.collectAsState().value.failures[camera.id]?.target as? ConnectTarget.Saved)
        ?.let { target -> camera.routes.firstOrNull { it.id == target.route }?.kind }
    return AddSetupFlow(
        chooser = stationSetupChooser(camera),
        onSelect = {},
        destination = { option ->
            StationNetworkSetup(
                brand = POCKET_STATION_BRAND,
                wifiNameAccess = rememberWifiNameAccess(),
                savedNetworks = model.savedNetworks().asStationNetworks(),
                currentSsid = wifi::currentSsid,
                hotspotActive = { wifi.address(true) != null },
                scan = model.networkScan(camera),
                connect = { network ->
                    done(RouteDraft(if (network.hotspot) RouteKind.PHONE_HOTSPOT else RouteKind.INFRASTRUCTURE_NETWORK, network.ssid, network.password))
                    null
                },
                cancel = { done(null) }, complete = { done(null) }, camera = camera,
                startPage = if (option.kind == RouteKind.PHONE_HOTSPOT) StationSetupPage.Hotspot
                    else if (failed == RouteKind.INFRASTRUCTURE_NETWORK) StationSetupPage.Password(camera.wifiSSID.orEmpty())
                    else StationSetupPage.Networks,
            )
        },
        initialSelection = when (failed) {
            RouteKind.PHONE_HOTSPOT -> "phoneHotspot"
            RouteKind.INFRASTRUCTURE_NETWORK -> "wifi"
            else -> null
        },
        onCancel = { done(null) },
    )
}
