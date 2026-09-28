package com.opencapture.openpocketcine.pairing

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.location.LocationManager
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.statusBarsIgnoringVisibility
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.net.toUri
import com.opencapture.monitorui.MonitorCameraAction
import com.opencapture.monitorui.MonitorLinkHealth
import com.opencapture.monitorui.MonitorPalette
import com.opencapture.monitorui.MonitorTypography
import com.opencapture.monitorui.monitorScrollFade
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.multiview.MultiviewNetworkStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** iOS `StationNetworkSetupView.Page`; an empty path is the choose page. */
private sealed interface SetupPage {
    data object Networks : SetupPage
    data object Hotspot : SetupPage
    data class Password(val ssid: String) : SetupPage
}

/** One landscape column; null lays the whole page out in one column. */
private enum class SetupSide { LEADING, TRAILING }

/**
 * Shared station-network wizard for Multiview and a saved camera's Add setup (iOS
 * `StationNetworkSetupView`, 1:1). Callers supply radio work and persist only a confirmed
 * network. [scan] is null when the camera is not nearby over Bluetooth. [startPage] and
 * [startNetwork] reopen a failed setup on its password or hotspot page. [cameraSsids] are
 * camera access points, never offered as a shared network. [lockedNetwork] shows Multiview's
 * Shared Wi-Fi page while cameras use it.
 */
@OptIn(ExperimentalLayoutApi::class)
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
    cameraSsids: Set<String> = emptySet(),
    startPage: String = "choose",
    startNetwork: String = "",
) {
    val context = LocalContext.current
    // The keyboard must not replace the focused field by changing the form layout.
    val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val scope = rememberCoroutineScope()
    val latestScan by rememberUpdatedState(scan)
    val path = remember {
        mutableStateListOf<SetupPage>().apply {
            when (startPage) {
                "networks" -> add(SetupPage.Networks)
                "hotspot" -> add(SetupPage.Hotspot)
                "password" -> add(SetupPage.Password(startNetwork))
            }
        }
    }
    val top = path.lastOrNull()
    var current by remember { mutableStateOf<String?>(null) }
    var locationHint by remember { mutableStateOf<Pair<String, String>?>(null) }
    var hotspotDetected by remember { mutableStateOf(false) }
    var password by remember { mutableStateOf("") }
    var hotspotName by remember { mutableStateOf("") }
    var hotspotPassword by remember { mutableStateOf("") }
    var hotspotTouched by remember { mutableStateOf(false) }
    var reveal by remember { mutableStateOf(false) }
    var otherNetwork by remember { mutableStateOf(false) }
    var otherName by remember { mutableStateOf("") }
    val found = remember { mutableStateListOf<String>() }
    var scanJob by remember { mutableStateOf<Job?>(null) }
    var scanFinished by remember { mutableStateOf(false) }
    var scanFailed by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scanning = scanJob != null
    val warningColor = MonitorLinkHealth.watch
    val good = MonitorLinkHealth.stable

    fun isCameraNetwork(name: String) =
        name.startsWith("osmo", ignoreCase = true) || name == camera?.lastSSID || name in cameraSsids
    fun storedPassword(ssid: String, hotspot: Boolean) =
        savedNetworks.lastOrNull { it.hotspot == hotspot && it.ssid == ssid }?.password
    val networkHint =
        if (camera == null) "This phone joins first. Every camera you add will use the same Wi-Fi."
        else "The camera and this phone must be on the same Wi-Fi."
    // Saved on this phone with passwords; the store holds no password-less entries.
    val saved = savedNetworks.filter { !it.hotspot }.map { it.ssid }.distinct()
        .filter { it != current && !isCameraNetwork(it) }
    fun hasPassword(ssid: String) = storedPassword(ssid, false) != null
    // The camera sees this phone's hotspot. One phone-like network is taken as this phone's
    // until the operator types.
    val phones = found.filter {
        listOf("iphone", "ipad", "android", "galaxy", "pixel").any { token -> it.contains(token, ignoreCase = true) }
    }

    fun prefill(next: SetupPage) {
        reveal = false
        when (next) {
            is SetupPage.Password -> password = storedPassword(next.ssid, false).orEmpty()
            SetupPage.Hotspot -> if (hotspotName.isEmpty()) {
                // A hotspot saved by Multiview or another camera is this same phone's.
                val known = camera?.hotspotSSID?.let { name -> savedNetworks.lastOrNull { it.hotspot && it.ssid == name } }
                    ?: savedNetworks.lastOrNull { it.hotspot }
                hotspotName = known?.ssid ?: camera?.hotspotSSID.orEmpty()
                hotspotPassword = known?.password.orEmpty()
            }
            SetupPage.Networks -> Unit
        }
    }
    fun open(next: SetupPage) {
        prefill(next)
        error = null
        path += next
    }
    fun suggestHotspot() {
        if (hotspotTouched || hotspotName.isNotEmpty() || phones.size != 1) return
        hotspotName = phones.single()
        hotspotPassword = storedPassword(hotspotName, true) ?: hotspotPassword
    }
    fun startScan() {
        val scanner = latestScan
        if (scanner == null || scanJob != null || scanFinished || working || lockedNetwork != null) return
        scanFailed = false
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                scanner { name ->
                    if (!working && name !in found && !isCameraNetwork(name)) {
                        found += name
                        suggestHotspot()
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                scanFailed = true
            } finally {
                scanFinished = !scanFailed
                scanJob = null
            }
        }
        scanJob = job
        job.start()
    }
    fun rescan() {
        scanFinished = false
        startScan()
    }
    /** Saving starts a Bluetooth connect, so a running scan first returns the camera to its own Wi-Fi. */
    fun finish(close: () -> Unit, action: suspend () -> Boolean) {
        if (working) return
        working = true
        scope.launch {
            try {
                scanJob?.cancelAndJoin()
                if (action()) close()
            } finally {
                working = false
            }
        }
    }
    fun dismiss() = finish(cancel) { true }
    fun submit(network: MultiviewNetworkStore.Network) = finish(complete) {
        error = connect(network)
        error == null
    }
    fun settings(intent: Intent) = context.startActivity(intent)

    LaunchedEffect(Unit) { path.toList().forEach(::prefill) }
    // Wi-Fi scans the moment it opens; Hotspot only when it needs the name.
    LaunchedEffect(top) {
        if (top == SetupPage.Networks || (top == SetupPage.Hotspot && hotspotName.isEmpty())) startScan()
    }
    LaunchedEffect(Unit) {
        while (true) {
            val permitted = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val located = context.getSystemService(LocationManager::class.java)?.isLocationEnabled == true
            val ssid = currentSsid()
            current = ssid?.takeUnless(::isCameraNetwork)
            locationHint = when {
                ssid != null -> null
                !permitted -> "Allow Location to show this phone’s Wi-Fi" to
                    "Settings › Apps › OpenPocketCine › Permissions › Location. Only the Wi-Fi name is used."
                !located -> "Turn on Location to show this phone’s Wi-Fi" to
                    "Settings › Location. Only the Wi-Fi name is used."
                else -> null
            }
            hotspotDetected = hotspotActive()
            delay(1_000)
        }
    }
    DisposableEffect(Unit) { onDispose { scanJob?.cancel() } }

    fun back() {
        when {
            working -> Unit
            lockedNetwork != null -> complete()
            path.isNotEmpty() -> { path.removeAt(path.lastIndex); error = null }
            // iOS keeps the sheet from being swiped away while the camera scans.
            !scanning -> dismiss()
        }
    }

    // --- Pieces bound to wizard state ---

    @Composable
    fun networkRow(name: String, detail: String? = null, detailColor: Color? = null) = SetupRow(
        OpcIcon.WIFI, name, detail, detailColor = detailColor, lock = true,
        modifier = Modifier.setupClickable(!working) { open(SetupPage.Password(name)) }
            .testTag("stationSetup.network.$name"),
    )

    @Composable
    fun columns(side: SetupSide?, spacing: Dp, leading: @Composable () -> Unit, trailing: @Composable () -> Unit) {
        when (side) {
            SetupSide.LEADING -> leading()
            SetupSide.TRAILING -> trailing()
            null -> Column(verticalArrangement = Arrangement.spacedBy(spacing)) { leading(); trailing() }
        }
    }

    // --- Choose ---

    @Composable
    fun choice(setup: CameraConnectionSetup, icon: OpcIcon, body: String, tag: String, modifier: Modifier) {
        val tile: @Composable () -> Unit = {
            Box(Modifier.size(44.dp).background(MonitorPalette.accent.copy(alpha = .14f), RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center) {
                OpcIcon(icon, null, Modifier.size(22.dp), MonitorPalette.accent)
            }
        }
        val text: @Composable (Modifier) -> Unit = { textModifier ->
            Column(textModifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(setup.title, style = setupFont(17f, FontWeight.SemiBold))
                    camera?.ssid(setup)?.let {
                        Text("Added · $it", color = good, style = setupFont(10.5f, FontWeight.SemiBold),
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                Text(body, color = MonitorPalette.muted, style = setupFont(12.5f))
                if (landscape) Spacer(Modifier.weight(1f))
                Text(tag, color = MonitorPalette.secondary, style = setupFont(10.5f, FontWeight.SemiBold),
                    modifier = Modifier.padding(top = 4.dp).background(MonitorPalette.tile, RoundedCornerShape(6.dp))
                        .padding(horizontal = 9.dp, vertical = 5.dp))
            }
        }
        val card = modifier.setupCard().setupClickable(!working) {
            open(if (setup == CameraConnectionSetup.WIFI) SetupPage.Networks else SetupPage.Hotspot)
        }.padding(16.dp).testTag("stationSetup.${setup.raw}")
        if (landscape) {
            Column(card, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                tile()
                text(Modifier.weight(1f))
            }
        } else {
            Row(card.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                tile()
                text(Modifier.weight(1f))
                OpcIcon(OpcIcon.CHEVRON_RIGHT, null, Modifier.align(Alignment.CenterVertically).size(18.dp), MonitorPalette.faint)
            }
        }
    }

    @Composable
    fun choosePage() {
        val question = if (camera == null) "How will your cameras connect?" else "How should this camera connect?"
        Column(verticalArrangement = Arrangement.spacedBy(if (landscape) 12.dp else 14.dp)) {
            if (landscape) {
                Row {
                    Text(question, Modifier.weight(1f).alignByBaseline(), style = setupFont(18f, FontWeight.SemiBold))
                    camera?.let {
                        Text(it.modelName, Modifier.alignByBaseline(), color = MonitorPalette.muted, style = setupFont(11.5f))
                    }
                }
            } else {
                camera?.let {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        OpcIcon(OpcIcon.CAMERA, null, Modifier.size(16.dp), MonitorPalette.muted)
                        Text("${it.displayName} · ${it.modelName}", color = MonitorPalette.muted, style = setupFont(12.5f))
                    }
                }
                Text(question, style = setupFont(22f, FontWeight.SemiBold))
            }
            val wifiBody = "A router, venue network or another device’s hotspot. Cameras and this phone join the same Wi-Fi."
            val hotspotBody = "This phone’s hotspot. Works anywhere you have mobile data."
            if (landscape) {
                // Equal-height tiles side by side.
                Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    choice(CameraConnectionSetup.WIFI, OpcIcon.WIFI, wifiBody, "Best for studios and several cameras",
                        Modifier.weight(1f).fillMaxHeight())
                    choice(CameraConnectionSetup.PHONE_HOTSPOT, OpcIcon.RADIO, hotspotBody, "Best on the move",
                        Modifier.weight(1f).fillMaxHeight())
                }
            } else {
                choice(CameraConnectionSetup.WIFI, OpcIcon.WIFI, wifiBody, "Best for studios and several cameras", Modifier)
                choice(CameraConnectionSetup.PHONE_HOTSPOT, OpcIcon.RADIO, hotspotBody, "Best on the move", Modifier)
            }
            Text(
                if (camera == null) "Choose the shared network before adding cameras. Saved passwords stay on this phone."
                else "Camera Wi-Fi stays available. Switch setups from the camera’s chips at any time.",
                color = MonitorPalette.muted, style = setupFont(if (landscape) 11.5f else 12f),
            )
        }
    }

    // --- Wi-Fi ---

    @Composable
    fun networksPage(side: SetupSide?) = columns(side, 7.dp, {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            if (!landscape) {
                Text("Choose the network", style = setupFont(22f, FontWeight.SemiBold))
                SetupHint(networkHint, Modifier.padding(bottom = 8.dp))
            }
            val here = current
            val hint = locationHint
            if (here != null || hint != null) {
                SetupSectionHeader("THIS PHONE IS ON", Modifier.testTag("stationSetup.currentHeader"))
                SetupGroup {
                    if (here != null) {
                        networkRow(here, if (hasPassword(here)) "Connected · password saved" else "Connected", good)
                    } else if (hint != null) {
                        SetupRow(OpcIcon.WIFI, hint.first, hint.second,
                            modifier = Modifier.setupClickable(!working) {
                                settings(
                                    if (hint.first.startsWith("Allow")) {
                                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri())
                                    } else Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS),
                                )
                            }.testTag("stationSetup.locationHint"))
                    }
                }
            }
            if (saved.isNotEmpty()) {
                SetupSectionHeader("SAVED ON THIS PHONE", Modifier.padding(top = 6.dp))
                SetupGroup {
                    saved.forEachIndexed { index, name ->
                        if (index > 0) SetupDivider()
                        networkRow(name, if (hasPassword(name)) "Password saved" else null)
                    }
                }
            }
        }
    }, {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            // Same height as SetupSectionHeader; Scan again keeps its 44 dp target past the row.
            Box(
                Modifier.padding(top = if (landscape) 0.dp else 6.dp).fillMaxWidth().height(SETUP_HEADER_HEIGHT)
                    .testTag("stationSetup.nearbyHeader"),
            ) {
                Row(Modifier.align(Alignment.CenterStart), horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    SetupSection("NEARBY")
                    if (scanning) SetupSpinner(12.dp)
                }
                if (!scanning && scan != null) {
                    Box(
                        Modifier.align(Alignment.CenterEnd).wrapContentHeight(unbounded = true).heightIn(min = 44.dp)
                            .setupClickable(!working, ::rescan).testTag("stationSetup.rescan"),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("Scan again", style = setupFont(12f, FontWeight.SemiBold))
                    }
                }
            }
            SetupGroup {
                val nearby = found.filter { it !in saved && it != current }
                nearby.forEachIndexed { index, name ->
                    if (index > 0) SetupDivider()
                    networkRow(name, if (hasPassword(name)) "Password saved" else null)
                }
                if (scan == null || scanning || nearby.isEmpty()) {
                    if (nearby.isNotEmpty()) SetupDivider()
                    SetupRow(
                        if (scanning) null else OpcIcon.SCAN,
                        when {
                            scanning -> "The camera is looking for networks…"
                            scan == null -> "Turn the camera on to find networks"
                            else -> "No networks found yet"
                        },
                        when {
                            scanning -> "Networks appear here as it finds them"
                            scanFailed -> "The scan did not finish. Try Scan again."
                            else -> null
                        },
                        progress = scanning, chevron = false, modifier = Modifier.testTag("stationSetup.scanStatus"),
                    )
                }
            }
            if (landscape) SetupHint(networkHint, Modifier.padding(top = 4.dp))
        }
    })

    @Composable
    fun passwordPage(ssid: String, side: SetupSide?) {
        val summary: @Composable () -> Unit = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SetupSectionHeader("NETWORK")
                Row(
                    Modifier.fillMaxWidth().setupCard().padding(horizontal = 16.dp, vertical = 13.dp)
                        .semantics(mergeDescendants = true) {}.testTag("stationSetup.networkSummary"),
                    horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(38.dp).background(MonitorPalette.accent.copy(alpha = .14f), RoundedCornerShape(10.dp)),
                        contentAlignment = Alignment.Center) {
                        OpcIcon(OpcIcon.WIFI, null, Modifier.size(19.dp), MonitorPalette.accent)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(ssid, style = setupFont(16f, FontWeight.SemiBold))
                        Text(if (ssid == current) "This phone’s current network" else "This phone joins it too",
                            color = MonitorPalette.muted, style = setupFont(11.5f))
                    }
                }
            }
        }
        val checklist: @Composable () -> Unit = {
            Column(
                Modifier.fillMaxWidth().setupCard().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(13.dp),
            ) {
                SetupSection("BEFORE YOU CONNECT")
                SetupCheck("WPA2 or WPA2/WPA3 mixed", if (landscape) null else "WPA3-only networks can refuse some cameras.")
                SetupCheck("Devices can see each other", if (landscape) null else "Guest networks with client isolation block the picture.")
                SetupCheck("Camera within range", if (landscape) null else "The camera leaves its own Wi-Fi and joins this one.")
            }
        }
        val field: @Composable () -> Unit = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SetupSecureField("PASSWORD", password, reveal, !working, "stationSetup.password", { reveal = !reveal }) { password = it }
                SetupHint("Saved on this phone. Multiview can reuse it.")
            }
        }
        // Portrait keeps the password under the network, above the checklist.
        if (side == null) {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) { summary(); field(); checklist() }
        } else {
            columns(side, 10.dp, { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { summary(); checklist() } }, field)
        }
    }

    // --- Hotspot ---

    @Composable
    fun hotspotPage(side: SetupSide?) {
        val tint = if (hotspotDetected) good else warningColor
        val status: @Composable () -> Unit = {
            Row(
                Modifier.fillMaxWidth().background(tint.copy(alpha = .1f), RoundedCornerShape(12.dp))
                    .border(1.dp, tint.copy(alpha = .3f), RoundedCornerShape(12.dp))
                    .padding(horizontal = 14.dp, vertical = 12.dp).testTag("stationSetup.hotspotStatus"),
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically,
            ) {
                OpcIcon(if (hotspotDetected) OpcIcon.RADIO else OpcIcon.TRIANGLE_ALERT, null, Modifier.size(18.dp), tint)
                Text(
                    if (hotspotDetected) "Hotspot is on" else "Hotspot not detected yet. It can appear once the camera joins.",
                    color = tint, style = setupFont(13f, FontWeight.SemiBold),
                )
            }
        }
        val checklist: @Composable () -> Unit = {
            Column(Modifier.fillMaxWidth().setupCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(13.dp)) {
                SetupSection("IN SETTINGS › HOTSPOT")
                SetupNumbered(1, "Turn on Hotspot", if (landscape) null else "Lets the camera join this phone.")
                SetupNumbered(2, "Use the 2.4 GHz band", if (landscape) null else "Every Osmo camera supports 2.4 GHz.")
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(12.dp)).background(MonitorPalette.tile)
                        .setupClickable(!working) { settings(Intent(Settings.ACTION_WIRELESS_SETTINGS)) },
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OpcIcon(OpcIcon.SETTINGS, null, Modifier.size(16.dp), MonitorPalette.text)
                    Text("Open Settings", style = setupFont(13.5f, FontWeight.SemiBold))
                }
            }
        }
        val name: @Composable () -> Unit = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SetupSectionHeader("HOTSPOT NAME")
                SetupInput(
                    hotspotName, { hotspotTouched = true; hotspotName = it }, "Hotspot name", !working,
                    Modifier.testTag("stationSetup.hotspotName").semantics { contentDescription = "Hotspot name" },
                )
                if (phones.size > 1 || (phones.size == 1 && phones.single() != hotspotName)) {
                    val chips = rememberScrollState()
                    Row(
                        Modifier.monitorScrollFade(chips, vertical = false).horizontalScroll(chips),
                        horizontalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        phones.forEach { phone ->
                            Box(
                                Modifier.padding(vertical = 5.dp).heightIn(min = 34.dp).clip(RoundedCornerShape(9.dp))
                                    .background(MonitorPalette.tile)
                                    .setupClickable(!working) { hotspotTouched = true; hotspotName = phone }
                                    .padding(horizontal = 12.dp),
                                contentAlignment = Alignment.Center,
                            ) { Text(phone, style = setupFont(12f, FontWeight.SemiBold)) }
                        }
                    }
                }
                if (scanning && hotspotName.isEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        SetupSpinner(12.dp)
                        SetupHint("The camera is looking for this phone’s hotspot…")
                    }
                } else if (!landscape) {
                    SetupHint("The network name shown in Settings › Hotspot.")
                }
            }
        }
        val pass: @Composable () -> Unit = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SetupSecureField("HOTSPOT PASSWORD", hotspotPassword, reveal, !working, "stationSetup.hotspotPassword",
                    { reveal = !reveal }) { hotspotPassword = it }
                if (!landscape) {
                    SetupHint("Android keeps it private: copy it from Settings › Hotspot once. It is remembered here.")
                }
            }
        }
        if (side != null) {
            columns(side, 10.dp, {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        SetupSectionHeader("THIS PHONE’S HOTSPOT")
                        status()
                    }
                    checklist()
                }
            }, {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { name(); pass() }
            })
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) { status(); checklist(); name(); pass() }
        }
    }

    @Composable
    fun content(page: SetupPage?, side: SetupSide?) {
        when (page) {
            null -> choosePage()
            SetupPage.Networks -> networksPage(side)
            is SetupPage.Password -> passwordPage(page.ssid, side)
            SetupPage.Hotspot -> hotspotPage(side)
        }
    }

    /** The scrolling form: the whole page in portrait, the trailing column in landscape. */
    @Composable
    fun form(page: SetupPage?, side: SetupSide?, inset: Dp, modifier: Modifier) {
        val scroll = rememberScrollState()
        Column(
            modifier.fillMaxWidth().monitorScrollFade(scroll).verticalScroll(scroll)
                .padding(start = inset, end = inset, top = 8.dp, bottom = 16.dp).testTag("stationSetup.form"),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            content(page, side)
            if (working) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SetupSpinner(20.dp)
                    Text(if (scanning) "Finishing camera scan…" else "Connecting…", color = MonitorPalette.muted,
                        style = setupFont(15f))
                }
            }
            (error ?: warning)?.let {
                Text(it, color = warningColor, style = setupFont(13f), modifier = Modifier.testTag("stationSetup.error"))
            }
        }
    }

    /** Connect / Other network, pinned under the form above the safe area or keyboard. */
    @Composable
    fun footer(page: SetupPage?, inset: Dp) {
        if (page == null) return
        Box(Modifier.fillMaxWidth().padding(start = inset, end = inset, top = 8.dp, bottom = 16.dp)) {
            when (page) {
                SetupPage.Networks -> SetupRow(
                    OpcIcon.PLUS, "Other network…", null,
                    modifier = Modifier.setupCard().setupClickable(!working) { otherName = ""; otherNetwork = true }
                        .testTag("stationSetup.otherNetwork"),
                )
                is SetupPage.Password -> MonitorCameraAction(
                    "Connect over Wi-Fi", primary = true,
                    enabled = !working && validStationCredentials(page.ssid, password, hotspot = false),
                    contentDescription = "Connect over Wi-Fi",
                    onClick = { submit(MultiviewNetworkStore.Network(page.ssid, password, false)) },
                    modifier = Modifier.fillMaxWidth().testTag("stationSetup.connect"),
                )
                SetupPage.Hotspot -> {
                    val trimmed = hotspotName.trim()
                    MonitorCameraAction(
                        "Connect over Hotspot", primary = true,
                        enabled = !working && validStationCredentials(trimmed, hotspotPassword, hotspot = true),
                        contentDescription = "Connect over Hotspot",
                        onClick = { submit(MultiviewNetworkStore.Network(trimmed, hotspotPassword, true)) },
                        modifier = Modifier.fillMaxWidth().testTag("stationSetup.connect"),
                    )
                }
            }
        }
    }

    Dialog(
        onDismissRequest = ::back,
        properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false, decorFitsSystemWindows = false),
    ) {
        BackHandler(onBack = ::back)
        // iOS large sheet: portrait floats below the status bar with rounded top corners and a
        // grabber; landscape covers the screen.
        Column(Modifier.fillMaxSize()) {
            // The sheet starts under the status bar area even when the app hides the bar.
            if (!landscape) Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBarsIgnoringVisibility.union(WindowInsets.displayCutout)))
            Column(
                Modifier.fillMaxSize()
                    .clip(if (landscape) RoundedCornerShape(0.dp) else RoundedCornerShape(topStart = 38.dp, topEnd = 38.dp))
                    // Shared Wi-Fi is Multiview's own sheet on the app background.
                    .background(if (lockedNetwork != null) MonitorPalette.background else SETUP_PAGE_BACKGROUND)
                    // Safe drawing includes the keyboard, so the pinned footer rides above it.
                    .windowInsetsPadding(
                        if (landscape) WindowInsets.safeDrawing
                        else WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom),
                    )
                    .testTag(if (camera == null) "multiview.networkSetup" else "addSetup"),
            ) {
                if (!landscape) {
                    Box(Modifier.fillMaxWidth().padding(top = 5.dp), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(36.dp, 5.dp).background(Color.White.copy(alpha = .3f), CircleShape))
                    }
                }
                val title = when {
                    lockedNetwork != null -> "Shared Wi-Fi"
                    top == null -> if (camera == null) "Connect your cameras" else "Add setup"
                    top == SetupPage.Hotspot -> "Hotspot"
                    else -> "Wi-Fi"
                }
                SetupNavigationBar(
                    title,
                    leading = when {
                        lockedNetwork != null -> null
                        top == null -> SetupBarAction.Cancel
                        else -> SetupBarAction.Back
                    },
                    trailingDone = lockedNetwork != null,
                    enabled = !working,
                    onLeading = { if (top == null) dismiss() else back() },
                    onDone = complete,
                )
                val inset = if (landscape) 24.dp else 18.dp
                when {
                    // iOS centers the leading-aligned block when it is narrower than the page.
                    lockedNetwork != null -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.TopCenter) {
                        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                OpcIcon(OpcIcon.WIFI, null, Modifier.size(20.dp), MonitorPalette.text)
                                Text(lockedNetwork.ssid, style = setupFont(15f))
                            }
                            Text("Cameras are using this network. Remove them before changing it.",
                                color = MonitorPalette.muted, style = setupFont(15f))
                        }
                    }
                    landscape && top != null -> Row(
                        Modifier.weight(1f).padding(horizontal = 24.dp),
                        horizontalArrangement = Arrangement.spacedBy(if (top == SetupPage.Networks) 16.dp else 14.dp),
                    ) {
                        // Landscape: the leading column stays put; only the form column scrolls,
                        // with Connect / Other network pinned beneath it.
                        // ponytail: scrolls only if it overflows (long saved list, keyboard up).
                        val leading = rememberScrollState()
                        Column(Modifier.weight(1f).fillMaxHeight().verticalScroll(leading).padding(top = 8.dp, bottom = 16.dp)) {
                            content(top, SetupSide.LEADING)
                        }
                        Column(Modifier.weight(1f).fillMaxHeight()) {
                            form(top, SetupSide.TRAILING, 0.dp, Modifier.weight(1f))
                            footer(top, 0.dp)
                        }
                    }
                    else -> {
                        form(top, null, inset, Modifier.weight(1f))
                        footer(top, inset)
                    }
                }
            }
        }
    }
    if (otherNetwork) Dialog(onDismissRequest = { otherNetwork = false }) {
        val focus = remember { FocusRequester() }
        LaunchedEffect(Unit) { focus.requestFocus() }
        // iOS alert: centered title, one field, Cancel and Next capsules.
        Column(
            Modifier.widthIn(max = 300.dp).fillMaxWidth().clip(RoundedCornerShape(34.dp)).background(SETUP_ALERT_BACKGROUND)
                .padding(horizontal = 16.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Other network", style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = MonitorPalette.text))
            SetupInput(otherName, { otherName = it }, "Network name", true,
                Modifier.focusRequester(focus).semantics { contentDescription = "Network name" }, capsule = true)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SetupAlertButton("Cancel", Modifier.weight(1f)) { otherNetwork = false }
                SetupAlertButton("Next", Modifier.weight(1f)) {
                    otherNetwork = false
                    val name = otherName.trim()
                    if (name.isNotEmpty()) open(SetupPage.Password(name))
                }
            }
        }
    }
}

internal fun validStationCredentials(ssid: String, password: String, hotspot: Boolean): Boolean =
    ssid.toByteArray(Charsets.UTF_8).size in 1..32 && password.toByteArray(Charsets.UTF_8).size <= 63 &&
        (password.length >= 8 || (!hotspot && password.isEmpty()))

/** iOS pins the dark elevated system background so portrait and landscape keep one page. */
private val SETUP_PAGE_BACKGROUND = Color(0xFF1C1C1E)
private val SETUP_ALERT_BACKGROUND = Color(0xFF2A2A2C)

/** Fixed height so paired columns keep their headings and card tops aligned. */
private val SETUP_HEADER_HEIGHT = 24.dp

private fun setupFont(size: Float, weight: FontWeight = FontWeight.Normal): TextStyle = MonitorTypography.text(size, weight)

private fun Modifier.setupClickable(enabled: Boolean, onClick: () -> Unit): Modifier =
    clickable(enabled = enabled, role = Role.Button, onClick = onClick)

/** Matches `monitorCardSurface()`. */
private fun Modifier.setupCard(): Modifier =
    clip(RoundedCornerShape(12.dp)).background(MonitorPalette.surface).border(1.dp, MonitorPalette.border, RoundedCornerShape(12.dp))

private enum class SetupBarAction { Cancel, Back }

/** iOS inline navigation bar: centered title, Cancel or back leading, Done trailing. */
@Composable
private fun SetupNavigationBar(
    title: String,
    leading: SetupBarAction?,
    trailingDone: Boolean,
    enabled: Boolean,
    onLeading: () -> Unit,
    onDone: () -> Unit,
) {
    // Measured from iOS 26: 44 dp glass controls 20 dp under the sheet top.
    Layout(
        content = {
            Text(title, Modifier.semantics { heading() }, maxLines = 1, overflow = TextOverflow.Ellipsis,
                style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = MonitorPalette.text))
            when (leading) {
                SetupBarAction.Cancel -> SetupBarButton("Cancel", enabled, Modifier, onLeading)
                SetupBarAction.Back -> SetupBarButton(null, enabled, Modifier, onLeading)
                null -> Box(Modifier)
            }
            if (trailingDone) SetupBarButton("Done", enabled, Modifier, onDone) else Box(Modifier)
        },
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 8.dp).height(44.dp),
    ) { measurables, constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val start = measurables[1].measure(loose)
        val end = measurables[2].measure(loose)
        val gap = 8.dp.roundToPx()
        val width = constraints.maxWidth
        val free = width - start.width - end.width - 2 * gap
        val title = measurables[0].measure(loose.copy(maxWidth = free.coerceAtLeast(0)))
        val lo = start.width + gap
        val hi = width - end.width - gap - title.width
        val x = ((width - title.width) / 2).coerceIn(lo, maxOf(lo, hi))
        val height = constraints.maxHeight
        layout(width, height) {
            start.place(0, (height - start.height) / 2)
            end.place(width - end.width, (height - end.height) / 2)
            title.place(x, (height - title.height) / 2)
        }
    }
}

@Composable
private fun SetupAlertButton(text: String, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier.height(44.dp).clip(CircleShape).background(Color.White.copy(alpha = .1f)).setupClickable(true, onClick),
        contentAlignment = Alignment.Center,
    ) { Text(text, style = TextStyle(fontSize = 17.sp, color = MonitorPalette.text)) }
}

@Composable
private fun SetupBarButton(text: String?, enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    // iOS 26 glass bar button: a faint fill and rim over the sheet.
    Box(
        modifier.height(44.dp).widthIn(min = 44.dp).alpha(if (enabled) 1f else .4f).clip(CircleShape)
            .background(Color.White.copy(alpha = .03f)).border(1.dp, Color.White.copy(alpha = .1f), CircleShape)
            .setupClickable(enabled, onClick)
            .semantics { if (text == null) contentDescription = "Back" }
            .padding(horizontal = if (text == null) 0.dp else 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (text == null) {
            OpcIcon(OpcIcon.CHEVRON_LEFT, null, Modifier.size(22.dp), MonitorPalette.text)
        } else {
            Text(text, style = TextStyle(fontSize = 17.sp, color = MonitorPalette.text))
        }
    }
}

/** The app's eyebrow (Settings cards, Cameras groups). */
@Composable
private fun SetupSection(text: String) {
    Text(text, Modifier.semantics { heading() }, color = MonitorPalette.faint,
        style = setupFont(8.5f, FontWeight.Bold).copy(letterSpacing = 1.7.sp))
}

@Composable
private fun SetupSectionHeader(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().height(SETUP_HEADER_HEIGHT), verticalAlignment = Alignment.CenterVertically) {
        SetupSection(text)
    }
}

@Composable
private fun SetupHint(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, color = MonitorPalette.muted, style = setupFont(11.5f))
}

@Composable
private fun SetupSpinner(size: Dp) {
    CircularProgressIndicator(Modifier.size(size), color = MonitorPalette.muted, strokeWidth = if (size < 16.dp) 1.5.dp else 2.dp)
}

@Composable
private fun SetupDivider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = .06f)))
}

@Composable
private fun SetupGroup(rows: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().setupCard()) { rows() }
}

@Composable
private fun SetupRow(
    icon: OpcIcon?,
    title: String,
    detail: String?,
    modifier: Modifier = Modifier,
    detailColor: Color? = null,
    lock: Boolean = false,
    progress: Boolean = false,
    chevron: Boolean = true,
) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        if (progress) SetupSpinner(17.dp)
        else icon?.let { OpcIcon(it, null, Modifier.size(17.dp), MonitorPalette.accent) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = setupFont(14.5f, FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
            detail?.let { Text(it, color = detailColor ?: MonitorPalette.muted, style = setupFont(11f)) }
        }
        if (lock) OpcIcon(OpcIcon.LOCK, null, Modifier.size(13.dp), MonitorPalette.faint)
        if (chevron) OpcIcon(OpcIcon.CHEVRON_RIGHT, null, Modifier.size(16.dp), MonitorPalette.faint)
    }
}

@Composable
private fun SetupCheck(title: String, detail: String?) {
    val good = MonitorLinkHealth.stable
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(20.dp).background(good.copy(alpha = .16f), CircleShape), contentAlignment = Alignment.Center) {
            OpcIcon(OpcIcon.CHECK, null, Modifier.size(12.dp), good)
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = setupFont(13f, FontWeight.Medium))
            detail?.let { SetupHint(it) }
        }
    }
}

@Composable
private fun SetupNumbered(number: Int, title: String, detail: String?) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(22.dp).background(MonitorPalette.accent.copy(alpha = .16f), CircleShape), contentAlignment = Alignment.Center) {
            Text("$number", color = MonitorPalette.accent, style = setupFont(11f, FontWeight.Bold))
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = setupFont(13f, FontWeight.Medium))
            detail?.let { SetupHint(it) }
        }
    }
}

/** iOS `InputStyle`: 48 dp raised field, 11 dp corners, 8% white stroke. */
@Composable
private fun SetupInput(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    secure: Boolean = false,
    reveal: Boolean = false,
    capsule: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
) {
    val shape = if (capsule) CircleShape else RoundedCornerShape(11.dp)
    BasicTextField(
        value = value, onValueChange = onValueChange, enabled = enabled, singleLine = true,
        textStyle = setupFont(15f),
        cursorBrush = SolidColor(MonitorPalette.accent),
        visualTransformation = if (secure && !reveal) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
            keyboardType = if (secure) KeyboardType.Password else KeyboardType.Text,
        ),
        modifier = modifier.fillMaxWidth(),
        decorationBox = { inner ->
            Row(
                Modifier.fillMaxWidth().heightIn(min = if (capsule) 44.dp else 48.dp)
                    .background(if (capsule) Color.White.copy(alpha = .08f) else MonitorPalette.tile, shape)
                    .border(1.dp, Color.White.copy(alpha = if (capsule) 0f else .08f), shape)
                    .padding(start = 14.dp, end = if (trailing != null) 2.dp else 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.weight(1f)) {
                    if (value.isEmpty()) Text(placeholder, color = SETUP_PLACEHOLDER, style = setupFont(15f))
                    inner()
                }
                trailing?.invoke()
            }
        },
    )
}

private val SETUP_PLACEHOLDER = Color(0x4DEBEBF5)

@Composable
private fun SetupSecureField(
    label: String,
    value: String,
    reveal: Boolean,
    enabled: Boolean,
    tag: String,
    onReveal: () -> Unit,
    onChange: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        SetupSectionHeader(label)
        SetupInput(
            value, onChange, "Password", enabled,
            Modifier.testTag(tag).semantics { contentDescription = label.lowercase().replaceFirstChar { it.uppercase() } },
            secure = true, reveal = reveal,
        ) {
            Box(
                Modifier.size(44.dp).setupClickable(enabled, onReveal)
                    .semantics { contentDescription = if (reveal) "Hide password" else "Show password" },
                contentAlignment = Alignment.Center,
            ) {
                OpcIcon(if (reveal) OpcIcon.EYE_OFF else OpcIcon.EYE, null, Modifier.size(18.dp), MonitorPalette.muted)
            }
        }
    }
}
