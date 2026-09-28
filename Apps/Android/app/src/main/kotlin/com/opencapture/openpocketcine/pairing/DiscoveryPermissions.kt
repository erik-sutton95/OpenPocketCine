package com.opencapture.openpocketcine.pairing

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.core.net.toUri
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter

/**
 * Runtime permissions, each asked where it is used. Finding the camera needs only what the
 * Bluetooth scan and GATT connect need; this phone's Wi-Fi name asks for Location later.
 *
 * | API    | Find camera (BLE scan + connect)                 | This phone's Wi-Fi name, Wi-Fi scan results |
 * | 29-30  | ACCESS_FINE_LOCATION + Location services on      | ACCESS_FINE_LOCATION + Location services on |
 * | 31-32  | BLUETOOTH_SCAN (neverForLocation) + _CONNECT     | same                                        |
 * | 33+    | BLUETOOTH_SCAN (neverForLocation) + _CONNECT     | same                                        |
 *
 * Joining the camera or shared Wi-Fi with WifiNetworkSpecifier needs no runtime permission on
 * any level, and nothing here calls an API that needs NEARBY_WIFI_DEVICES.
 */
object DiscoveryPermissions {
    /** What the BLE scan and GATT connect need on [sdk]. */
    @SuppressLint("InlinedApi") // The API 31 names are only returned on API 31+.
    fun discovery(sdk: Int = Build.VERSION.SDK_INT): List<String> =
        if (sdk >= 31) {
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    /** Below API 31 a BLE scan returns nothing while Location services are off. */
    fun discoveryNeedsLocationServices(sdk: Int = Build.VERSION.SDK_INT): Boolean = sdk < 31

    /** Precise location reads this phone's Wi-Fi name. */
    val wifiName: List<String> = listOf(Manifest.permission.ACCESS_FINE_LOCATION)

    /** Android 12 ignores a fine-location request that does not carry coarse with it. */
    val wifiNameRequest: List<String> =
        listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

    /** The name Android's app permission page shows for [permissions]. */
    fun settingsName(permissions: List<String>): String =
        if (Manifest.permission.BLUETOOTH_SCAN in permissions) "Nearby devices" else "Location"

    enum class Route { REQUEST, SETTINGS }

    /**
     * Android stops showing the dialog after a permission is denied twice (or "Don't ask
     * again"); then [ActivityCompat.shouldShowRequestPermissionRationale] is false again and
     * only the app's Settings page can grant it.
     */
    fun route(
        missing: List<String>,
        deniedBefore: (String) -> Boolean,
        showsRationale: (String) -> Boolean,
    ): Route = if (missing.any { deniedBefore(it) && !showsRationale(it) }) Route.SETTINGS else Route.REQUEST

    fun granted(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    fun locationServicesOn(context: Context): Boolean =
        context.getSystemService(LocationManager::class.java)?.isLocationEnabled == true

    fun canReadWifiScans(context: Context): Boolean =
        wifiName.all { granted(context, it) } && locationServicesOn(context)

    fun appSettings(context: Context): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri())

    /** Report header: radio and permission state, no identifiers. */
    fun reportLines(context: Context): List<String> {
        val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter
        val bluetooth = when {
            adapter == null -> "unavailable"
            adapter.isEnabled -> "on"
            else -> "off"
        }
        val relevant = (discovery() + wifiNameRequest).distinct()
        val permissions = relevant.joinToString(" ") {
            "${shortName(it)}=${if (granted(context, it)) "granted" else "denied"}"
        }
        return listOf(
            "bluetooth: $bluetooth",
            "location services: ${if (locationServicesOn(context)) "on" else "off"}",
            "permissions: $permissions",
        )
    }

    internal fun shortName(permission: String): String = permission.substringAfterLast('.')

    private const val PREFS = "openpocketcine.permissions"

    internal fun deniedBefore(context: Context, permission: String): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(permission, false)

    internal fun rememberResult(context: Context, result: Map<String, Boolean>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit {
            result.forEach { (permission, ok) -> putBoolean(permission, !ok) }
        }
    }
}

/** One permission ask: the system dialog while Android still shows it, otherwise Settings. */
class PermissionGate internal constructor(internal val label: String) {
    var granted by mutableStateOf(false)
        internal set

    /** The dialog no longer shows; [request] opens the app's Settings page instead. */
    var needsSettings by mutableStateOf(false)
        internal set

    internal var ask: () -> Unit = {}

    fun request() = ask()
}

/**
 * [needed] is what must be granted; [request] is what the dialog asks for. [onGranted] runs
 * when the grant arrives from the dialog or from Settings on return to the app.
 */
@Composable
fun rememberPermissionGate(
    label: String,
    needed: List<String>,
    request: List<String> = needed,
    onGranted: () -> Unit = {},
): PermissionGate {
    val context = LocalContext.current
    val activity = LocalActivity.current
    val latestOnGranted by rememberUpdatedState(onGranted)
    fun refresh(gate: PermissionGate) {
        val missing = needed.filterNot { DiscoveryPermissions.granted(context, it) }
        gate.granted = missing.isEmpty()
        gate.needsSettings = activity != null && missing.isNotEmpty() &&
            DiscoveryPermissions.route(
                missing,
                deniedBefore = { DiscoveryPermissions.deniedBefore(context, it) },
                showsRationale = { ActivityCompat.shouldShowRequestPermissionRationale(activity, it) },
            ) == DiscoveryPermissions.Route.SETTINGS
    }
    val gate = remember(label) { PermissionGate(label).also(::refresh) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        DiscoveryPermissions.rememberResult(context, result)
        refresh(gate)
        val summary = result.entries.joinToString(" ") {
            "${DiscoveryPermissions.shortName(it.key)}=${if (it.value) "granted" else "denied"}"
        }
        DiagnosticCenter.log(
            "info", "permissions", label,
            "$label result $summary${if (gate.needsSettings) " next=settings" else ""}",
        )
        if (gate.granted) latestOnGranted()
    }
    gate.ask = {
        if (gate.needsSettings) {
            DiagnosticCenter.log("info", "permissions", label, "$label open app settings")
            runCatching { context.startActivity(DiscoveryPermissions.appSettings(context)) }
        } else {
            launcher.launch(request.toTypedArray())
        }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, gate) {
        val observer = LifecycleEventObserver { _, event ->
            if (event != Lifecycle.Event.ON_RESUME) return@LifecycleEventObserver
            val before = gate.granted
            refresh(gate)
            if (!before && gate.granted) {
                DiagnosticCenter.log("info", "permissions", label, "$label granted outside the dialog")
                latestOnGranted()
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    return gate
}
