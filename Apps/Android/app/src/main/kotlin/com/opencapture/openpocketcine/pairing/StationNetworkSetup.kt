package com.opencapture.openpocketcine.pairing

import android.Manifest
import android.content.Intent
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.location.LocationManager
import android.provider.Settings
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.net.toUri
import com.opencapture.monitorui.MonitorLinkHealth
import com.opencapture.monitorui.MonitorPalette
import com.opencapture.monitorui.MonitorTypography
import com.opencapture.monitorui.monitorScrollFade
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.multiview.MultiviewNetworkStore
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Shared station-network form for Multiview and a saved camera's Add setup (iOS
 * `StationNetworkSetupView`). Callers supply radio work and persist only a confirmed network.
 * [scan] is null when the camera is not nearby over Bluetooth. [startPage] and [startNetwork]
 * reopen a failed setup on its password or hotspot page.
 */
@Composable
fun StationNetworkSetup(
    savedNetworks: List<MultiviewNetworkStore.Network>,
    currentSsid: () -> String?,
    hotspotActive: () -> Boolean,
    scan: (suspend ((String) -> Unit) -> Unit)?,
    connect: suspend (MultiviewNetworkStore.Network) -> String?,
    cancel: () -> Unit,
    complete: () -> Unit,
    lockedNetwork: MultiviewNetworkStore.Network? = null,
    warning: String? = null,
    camera: SavedCamera? = null,
    startPage: String = "choose",
    startNetwork: String = "",
) {
    val context = LocalContext.current
    // The keyboard must not replace the focused field by changing the form layout.
    val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val scope = rememberCoroutineScope()
    val latestScan by rememberUpdatedState(scan)
    var page by remember { mutableStateOf(startPage) }
    var current by remember { mutableStateOf<String?>(null) }
    var locationPermission by remember { mutableStateOf(false) }
    var locationEnabled by remember { mutableStateOf(false) }
    var hotspotDetected by remember { mutableStateOf(false) }
    var network by remember { mutableStateOf(startNetwork) }
    var password by remember {
        mutableStateOf(savedNetworks.firstOrNull { !it.hotspot && it.ssid == startNetwork }?.password.orEmpty())
    }
    val knownHotspot = camera?.hotspotSSID?.let { name -> savedNetworks.firstOrNull { it.hotspot && it.ssid == name } }
        ?: savedNetworks.lastOrNull { it.hotspot }
    var hotspotName by remember { mutableStateOf(knownHotspot?.ssid ?: camera?.hotspotSSID.orEmpty()) }
    var hotspotPassword by remember { mutableStateOf(knownHotspot?.password.orEmpty()) }
    var hotspotTouched by remember { mutableStateOf(false) }
    var otherNetwork by remember { mutableStateOf(false) }
    var otherName by remember { mutableStateOf("") }
    val found = remember { mutableStateListOf<String>() }
    var scanJob by remember { mutableStateOf<Job?>(null) }
    var scanned by remember { mutableStateOf(false) }
    var scanFailed by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val formScroll = rememberScrollState()
    val leadingScroll = rememberScrollState()
    val scanning = scanJob != null
    val saved = savedNetworks.filter { !it.hotspot && !it.ssid.startsWith("osmo", ignoreCase = true) }
    val phones = found.filter {
        listOf("iphone", "ipad", "android", "galaxy", "pixel").any { token -> it.contains(token, ignoreCase = true) }
    }

    fun isCameraNetwork(name: String) = name.startsWith("osmo", ignoreCase = true) || name == camera?.lastSSID
    val networkHint =
        if (camera == null) "This phone joins first. Every camera you add will use the same Wi-Fi."
        else "The camera and this phone must be on the same Wi-Fi."

    fun startScan() {
        val scanner = latestScan
        if (scanner == null || scanning || working || lockedNetwork != null) return
        scanned = true
        scanFailed = false
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                scanner { name ->
                    if (!working && !isCameraNetwork(name) && name !in found) found += name
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                scanFailed = true
            } finally {
                scanJob = null
            }
        }
        scanJob = job
        job.start()
    }
    fun finish(action: suspend () -> Unit) {
        if (working) return
        working = true
        scope.launch {
            try {
                scanJob?.cancelAndJoin()
                action()
            } finally {
                working = false
            }
        }
    }
    fun back() {
        if (working) return
        if (lockedNetwork != null) complete()
        else when (page) {
            "choose" -> finish { cancel() }
            "password" -> { error = null; page = "networks" }
            else -> finish { error = null; page = "choose"; scanned = false }
        }
    }
    fun choose(name: String) {
        network = name
        password = saved.firstOrNull { it.ssid == name }?.password.orEmpty()
        error = null
        page = "password"
    }
    fun submit(hotspot: Boolean) {
        val selected = MultiviewNetworkStore.Network(
            if (hotspot) hotspotName.trim() else network,
            if (hotspot) hotspotPassword else password,
            hotspot,
        )
        finish {
            error = connect(selected)
            if (error == null) complete()
        }
    }
    fun settings() {
        context.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
    }

    LaunchedEffect(page) {
        if (!scanned && (page == "networks" || (page == "hotspot" && hotspotName.isEmpty()))) startScan()
    }
    LaunchedEffect(phones) {
        if (!hotspotTouched && hotspotName.isEmpty() && phones.size == 1) {
            hotspotName = phones.single()
            hotspotPassword = savedNetworks.firstOrNull { it.hotspot && it.ssid == hotspotName }?.password.orEmpty()
        }
    }
    LaunchedEffect(Unit) {
        while (true) {
            locationPermission = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            locationEnabled = context.getSystemService(LocationManager::class.java)?.isLocationEnabled == true
            current = currentSsid()?.takeUnless { it.startsWith("osmo", ignoreCase = true) }
            hotspotDetected = hotspotActive()
            delay(1_000)
        }
    }
    DisposableEffect(Unit) { onDispose { scanJob?.cancel() } }
    LaunchedEffect(page) { formScroll.scrollTo(0); leadingScroll.scrollTo(0) }

    val columns = if (lockedNetwork != null) null else when (page) {
        "networks" -> SetupColumns({
            SetupSectionHeader("THIS PHONE IS ON", Modifier.testTag("stationSetup.currentHeader"))
            current?.let { name ->
                SetupNetworkRow(name, detail = if (saved.any { it.ssid == name }) "Connected · password saved" else "Connected", enabled = !working, lock = true) { choose(name) }
            } ?: SetupNetworkRow(
                "Show this phone’s Wi-Fi",
                detail = when {
                    !locationPermission -> "Allow precise Location in app Settings to show the Wi-Fi name."
                    !locationEnabled -> "Turn on Location in Settings to show the Wi-Fi name."
                    else -> "Connect this phone to Wi-Fi, or choose the network below."
                }, enabled = !working,
            ) {
                context.startActivity(when {
                    !locationPermission -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri())
                    !locationEnabled -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                    else -> Intent(Settings.ACTION_WIFI_SETTINGS)
                })
            }
            val known = saved.filter { it.ssid != current }.distinctBy { it.ssid }
            if (known.isNotEmpty()) SetupSectionHeader("SAVED ON THIS PHONE")
            known.forEach { item -> SetupNetworkRow(item.ssid, detail = "Password saved", enabled = !working, lock = true) { choose(item.ssid) } }
        }, {
            // Same height as SetupSectionHeader; Scan again keeps its 48 dp target past the row.
            Row(Modifier.fillMaxWidth().height(SETUP_HEADER_HEIGHT).testTag("stationSetup.nearbyHeader"), verticalAlignment = Alignment.CenterVertically) {
                SetupSection("NEARBY")
                Spacer(Modifier.weight(1f))
                if (scanning) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                else if (scan != null) {
                    TextButton(onClick = ::startScan, enabled = !working, modifier = Modifier.requiredHeight(48.dp)) { Text("Scan again") }
                }
            }
            val nearby = found.filter { it != current && saved.none { saved -> saved.ssid == it } }
            nearby.forEach { name -> SetupNetworkRow(name, enabled = !working, lock = true) { choose(name) } }
            if (scanning || nearby.isEmpty()) {
                SetupIconHint(if (scanning) null else OpcIcon.SCAN, MaterialTheme.colorScheme.primary,
                    when {
                        scanning -> "The camera is looking for networks… Networks appear here as it finds them."
                        scan == null -> "Turn on the camera nearby to scan for networks, or enter a network name."
                        scanFailed -> "The scan did not finish. Turn on a camera and try Scan again."
                        else -> "No networks found yet. Turn on a camera or enter a network name."
                    }, Modifier.testTag("stationSetup.scanStatus"),
                )
            }
            SetupHint(networkHint)
        })
        "password" -> SetupColumns({
            SetupSectionHeader("NETWORK")
            SetupNetworkRow(network, detail = if (network == current) "This phone’s current network" else "This phone joins it too", enabled = false,
                modifier = Modifier.testTag("stationSetup.networkSummary")) {}
            SetupChecklist()
        }, {
            SetupPasswordField("Password", password, !working) { password = it }
            SetupHint(if (camera == null) "Saved securely on this phone for all cameras." else "Saved securely on this phone. Multiview can reuse it.")
        })
        "hotspot" -> SetupColumns({
            SetupSectionHeader("THIS PHONE’S HOTSPOT")
            SetupIconHint(if (hotspotDetected) OpcIcon.RADIO else OpcIcon.TRIANGLE_ALERT,
                if (hotspotDetected) MonitorLinkHealth.stable else MonitorLinkHealth.watch,
                if (hotspotDetected) "Phone hotspot is active" else "Phone hotspot not detected yet. It can appear once a camera joins.")
            SetupSection("IN SETTINGS")
            SetupHint("1. Turn on this phone’s Wi-Fi hotspot.\n2. Use WPA2 security and 2.4 GHz for compatibility.")
            TextButton(onClick = ::settings, enabled = !working) {
                OpcIcon(OpcIcon.SETTINGS, null, Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                Text("Open Settings")
            }
        }, {
            SetupSectionHeader("HOTSPOT NAME")
            OutlinedTextField(
                value = hotspotName, onValueChange = { hotspotTouched = true; hotspotName = it },
                placeholder = { Text("Hotspot name") }, enabled = !working, singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("stationSetup.hotspotName")
                    .semantics { contentDescription = "Hotspot name" },
            )
            if (phones.size > 1 || (phones.size == 1 && phones.single() != hotspotName)) {
                phones.forEach { name -> TextButton(onClick = { hotspotTouched = true; hotspotName = name }, enabled = !working) { Text(name) } }
            }
            SetupHint("Copy the hotspot name and password from Settings once. Android keeps the password private.")
            SetupPasswordField("Hotspot password", hotspotPassword, !working) { hotspotPassword = it }
        })
        else -> null
    }
    val status: @Composable ColumnScope.() -> Unit = {
        if (working) Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            Text(if (scanning) "Finishing camera scan…" else "Connecting…")
        }
        (error ?: warning)?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("stationSetup.error")) }
    }
    // The scrolling form yields to the keyboard; primary and manual-entry
    // actions retain a stable bottom slot outside long network lists.
    val footer: @Composable (Modifier) -> Unit = { modifier ->
        if (lockedNetwork == null && page != "choose") Column(modifier.fillMaxWidth()) {
            if (page == "networks") {
                SetupNetworkRow("Other network…", icon = OpcIcon.PLUS, enabled = !working,
                    modifier = Modifier.testTag("stationSetup.otherNetwork")) {
                    otherName = ""; otherNetwork = true
                }
            } else {
                val hotspot = page == "hotspot"
                val ssid = if (hotspot) hotspotName.trim() else network
                val passphrase = if (hotspot) hotspotPassword else password
                Button(
                    onClick = { submit(hotspot) },
                    enabled = !working && validStationCredentials(ssid, passphrase, hotspot),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp).testTag("stationSetup.connect"),
                ) { Text(if (hotspot) "Connect over Hotspot" else "Connect over Wi-Fi") }
            }
        }
    }

    Dialog(onDismissRequest = ::back, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().safeDrawingPadding().imePadding().padding(16.dp), contentAlignment = Alignment.Center) {
            Surface(
                modifier = Modifier.widthIn(max = if (landscape) 840.dp else 520.dp).fillMaxWidth()
                    .fillMaxHeight().testTag(if (camera == null) "multiview.networkSetup" else "addSetup"),
                color = MonitorPalette.backgroundDeep, shape = RoundedCornerShape(20.dp),
            ) {
                Column(Modifier.fillMaxSize()) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = ::back, enabled = !working) { Text(if (page == "choose") "Cancel" else "Back") }
                        Text(
                            if (lockedNetwork != null) "Shared Wi-Fi" else when (page) {
                                "choose" -> if (camera == null) "Connect your cameras" else "Add setup"
                                "hotspot" -> "Phone hotspot"
                                else -> "Wi-Fi"
                            }, style = LiveType.text(16f, FontWeight.SemiBold), modifier = Modifier.weight(1f),
                        )
                    }
                    if (landscape && columns != null) {
                        // Landscape: the leading column stays put; only the form column scrolls.
                        Row(Modifier.weight(1f).padding(horizontal = 18.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            // ponytail: scrolls only if it overflows (long saved list, keyboard up).
                            Column(
                                Modifier.weight(1f).verticalScroll(leadingScroll).padding(vertical = 18.dp),
                                verticalArrangement = Arrangement.spacedBy(12.dp), content = columns.leading,
                            )
                            Column(Modifier.weight(1f)) {
                                Column(
                                    Modifier.weight(1f).monitorScrollFade(formScroll).verticalScroll(formScroll)
                                        .padding(vertical = 18.dp).testTag("stationSetup.form"),
                                    verticalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    columns.trailing(this)
                                    status()
                                }
                                footer(Modifier.padding(vertical = 16.dp))
                            }
                        }
                    } else {
                        Column(
                            Modifier.weight(1f).monitorScrollFade(formScroll).verticalScroll(formScroll).padding(18.dp)
                                .testTag("stationSetup.form"),
                            verticalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            when {
                                lockedNetwork != null -> {
                                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                        OpcIcon(OpcIcon.WIFI, null, Modifier.size(20.dp))
                                        Text(lockedNetwork.ssid, style = LiveType.display(22f))
                                    }
                                    SetupHint("Cameras are using this network. Remove them before changing it.")
                                    Button(onClick = complete) { Text("Done") }
                                }
                                columns != null -> { columns.leading(this); columns.trailing(this) }
                                else -> {
                                    camera?.let { SetupHint("${it.displayName} · ${it.modelName}") }
                                    Text(
                                        if (camera == null) "How will your cameras connect?" else "How should this camera connect?",
                                        style = LiveType.display(22f, FontWeight.SemiBold),
                                    )
                                    fun added(ssid: String?, body: String) = ssid?.let { "Added · $it. $body" } ?: body
                                    AdaptiveSetupColumns(landscape, {
                                        SetupNetworkRow(
                                            if (camera == null) "Local Wi-Fi" else "Wi-Fi",
                                            detail = added(camera?.wifiSSID, "A router, venue network or another device’s hotspot. This phone joins it too."),
                                            icon = OpcIcon.WIFI, enabled = !working,
                                            modifier = Modifier.testTag("stationSetup.wifi"),
                                        ) {
                                            page = "networks"
                                        }
                                    }, {
                                        SetupNetworkRow(
                                            if (camera == null) "Phone hotspot" else "Hotspot",
                                            detail = added(camera?.hotspotSSID, "This phone’s Wi-Fi hotspot. Best on the move."),
                                            icon = OpcIcon.RADIO, enabled = !working,
                                            modifier = Modifier.testTag("stationSetup.phoneHotspot"),
                                        ) {
                                            page = "hotspot"
                                        }
                                    })
                                    SetupHint(
                                        if (camera == null) "Choose the shared network before adding cameras. Saved passwords stay on this phone."
                                        else "Camera Wi-Fi stays available. Switch setups from the camera’s chips at any time.",
                                    )
                                }
                            }
                            status()
                        }
                        footer(Modifier.padding(horizontal = 18.dp, vertical = 16.dp))
                    }
                }
            }
        }
    }
    if (otherNetwork) AlertDialog(
        onDismissRequest = { otherNetwork = false }, title = { Text("Other network") },
        text = { OutlinedTextField(value = otherName, onValueChange = { otherName = it }, label = { Text("Network name") }, singleLine = true) },
        confirmButton = { TextButton(onClick = { otherNetwork = false; choose(otherName.trim()) }, enabled = otherName.trim().isNotEmpty()) { Text("Next") } },
        dismissButton = { TextButton(onClick = { otherNetwork = false }) { Text("Cancel") } },
    )
}

internal fun validStationCredentials(ssid: String, password: String, hotspot: Boolean): Boolean =
    ssid.toByteArray(Charsets.UTF_8).size in 1..32 && password.toByteArray(Charsets.UTF_8).size <= 63 &&
        (password.length >= 8 || (!hotspot && password.isEmpty()))

/** One landscape column each; portrait stacks them. */
private class SetupColumns(val leading: @Composable ColumnScope.() -> Unit, val trailing: @Composable ColumnScope.() -> Unit)

@Composable
private fun AdaptiveSetupColumns(landscape: Boolean, first: @Composable ColumnScope.() -> Unit, second: @Composable ColumnScope.() -> Unit) {
    if (landscape) Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp), content = first)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp), content = second)
    } else Column(verticalArrangement = Arrangement.spacedBy(14.dp)) { first(); second() }
}

/** The app's eyebrow (Settings cards, Cameras groups). */
@Composable
private fun SetupSection(text: String) {
    Text(text, color = MonitorPalette.faint, style = MonitorTypography.text(8.5f, FontWeight.Bold).copy(letterSpacing = 1.7.sp))
}

/** Fixed height so paired columns keep their headings and card tops aligned. */
private val SETUP_HEADER_HEIGHT = 24.dp

@Composable
private fun SetupSectionHeader(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().height(SETUP_HEADER_HEIGHT), verticalAlignment = Alignment.CenterVertically) {
        SetupSection(text)
    }
}

@Composable
private fun SetupHint(text: String, modifier: Modifier = Modifier) { Text(text, modifier, style = LiveType.text(13f), color = MaterialTheme.colorScheme.onSurfaceVariant) }

/** iOS status and checklist rows: a leading glyph beside the hint. */
@Composable
private fun SetupIconHint(icon: OpcIcon?, tint: Color, text: String, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        icon?.let { OpcIcon(it, null, Modifier.size(18.dp), tint) }
        SetupHint(text)
    }
}

@Composable
private fun SetupNetworkRow(title: String, modifier: Modifier = Modifier, detail: String? = null, icon: OpcIcon = OpcIcon.WIFI, enabled: Boolean = true, lock: Boolean = false, onClick: () -> Unit) {
    Surface(onClick = onClick, enabled = enabled, modifier = modifier, shape = RoundedCornerShape(12.dp),
        color = MonitorPalette.surface, border = BorderStroke(1.dp, MonitorPalette.border)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OpcIcon(icon, null, Modifier.size(20.dp), MaterialTheme.colorScheme.primary)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(title, style = LiveType.text(15f, FontWeight.Medium))
                detail?.let { SetupHint(it) }
            }
            if (lock) OpcIcon(OpcIcon.LOCK, null, Modifier.size(13.dp), MonitorPalette.faint)
            if (enabled) OpcIcon(OpcIcon.CHEVRON_RIGHT, null, Modifier.size(16.dp), MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun SetupPasswordField(label: String, value: String, enabled: Boolean, onChange: (String) -> Unit) {
    var reveal by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SetupSectionHeader(label.uppercase())
        OutlinedTextField(
            value = value, onValueChange = onChange, placeholder = { Text(label) }, enabled = enabled, singleLine = true,
            visualTransformation = if (reveal) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            trailingIcon = { IconButton(onClick = { reveal = !reveal }) {
                OpcIcon(if (reveal) OpcIcon.EYE_OFF else OpcIcon.EYE, if (reveal) "Hide password" else "Show password", Modifier.size(20.dp))
            } }, modifier = Modifier.fillMaxWidth().testTag("stationSetup.password")
                .semantics { contentDescription = label },
        )
    }
}

@Composable
private fun SetupChecklist() {
    SetupSection("BEFORE YOU CONNECT")
    SetupIconHint(OpcIcon.CHECK, MonitorLinkHealth.stable, "WPA2 or WPA2/WPA3 mixed. WPA3-only networks can refuse some cameras.")
    SetupIconHint(OpcIcon.CHECK, MonitorLinkHealth.stable, "Devices can see each other. Guest networks with client isolation block the picture.")
    SetupIconHint(OpcIcon.CHECK, MonitorLinkHealth.stable, "Cameras within range. Each camera leaves its own Wi-Fi and joins this one.")
}
