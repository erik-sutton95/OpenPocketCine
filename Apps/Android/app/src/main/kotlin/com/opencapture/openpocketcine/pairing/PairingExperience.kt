package com.opencapture.openpocketcine.pairing

import android.Manifest
import android.os.Build
import androidx.activity.compose.BackHandler
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
import com.opencapture.monitorui.MonitorPairCameraPage
import com.opencapture.monitorui.MonitorPairingCheck
import com.opencapture.monitorui.MonitorPairingCheckState
import com.opencapture.monitorui.MonitorPairingDevice
import com.opencapture.monitorui.MonitorPairingInstruction
import com.opencapture.monitorui.MonitorPairingInstructionIcon
import com.opencapture.monitorui.MonitorPairingPresentation
import com.opencapture.monitorui.MonitorPairingStep
import com.opencapture.monitorui.MonitorPalette
import com.opencapture.monitorui.MonitorTypography
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.session.FoundCamera
import com.opencapture.openpocketcine.session.LocalVPNFilter

private val pairingSteps = listOf(
    MonitorPairingStep("Find your camera", "Bluetooth scan"),
    MonitorPairingStep("Approve on the camera", "Camera prompt"),
    MonitorPairingStep("Join camera Wi-Fi", "Camera network"),
    MonitorPairingStep("Open video link", "Video link"),
)

private val pairingTitles = listOf(
    "Find your camera",
    "Approve on the camera",
    "Join camera Wi-Fi",
    "Open video link",
)

private val pairingBodies = listOf(
    "Turn the camera on and keep the phone nearby. Pocket and Nano both appear — choose the one you want.",
    "If the camera shows Approve, tap it on that camera's screen. First-time pairing can wait up to 90 seconds.",
    "We read the camera's network over Bluetooth, then join its Wi-Fi for you.",
    "Exposure, LUTs and scopes go live as soon as the video link is up.",
)

@Composable
fun PairingExperience(
    model: AppModel,
    permissionsGranted: Boolean,
    onRequestPermissions: () -> Unit,
    onEnableBluetooth: () -> Unit,
) {
    val phase by model.session.phaseFlow.collectAsState()
    val failure by model.session.failure.collectAsState()
    val found by model.session.found.collectAsState()
    val radioOn by model.session.radioOn.collectAsState()
    var selectedId by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val busy = phase.isBusy()
    val step = (StartupConnectionCopy.wizardStep(phase) - 1).coerceIn(0, pairingSteps.lastIndex)
    val scanning = step == 0
    val picked = found.firstOrNull { it.id == selectedId }
    val error = if (phase == ConnectionPhase.FAILED && !failure.isNullOrBlank()) {
        StartupConnectionCopy.friendly(failure.orEmpty())
    } else {
        null
    }
    val vpnActive = step == 3 && LocalVPNFilter.isActive(context)
    LaunchedEffect(phase) {
        if (phase == ConnectionPhase.OPENING_DATALINK) LocalVPNFilter.noteIfActive(context)
    }
    val presentation = pairingPresentation(
        phase = phase,
        step = step,
        scanning = scanning,
        busy = busy,
        error = error,
        found = found,
        picked = picked,
        radioReady = radioOn && permissionsGranted,
        connectedName = model.session.connectedCamera?.name,
        joinedSSID = model.session.joinedSSID,
        vpnActive = vpnActive,
        bluetoothOn = radioOn,
        permissionsGranted = permissionsGranted,
    )
    BackHandler(enabled = busy || model.savedCameras.isNotEmpty()) {
        model.cancelPairing()
    }
    MonitorPairCameraPage(
        presentation = presentation,
        onSelect = { id -> if (!busy) selectedId = id },
        onPrimary = {
            when {
                phase == ConnectionPhase.FAILED -> model.session.startScan()
                !radioOn -> onEnableBluetooth()
                !permissionsGranted -> onRequestPermissions()
                else -> {
                    val camera = found.firstOrNull { it.id == selectedId }
                    if (camera != null && !busy) model.session.connect(camera)
                }
            }
        },
        onBack = model::cancelPairing,
        onDiagnostics = { DiagnosticCenter.shareReport(context, model.session) },
        extra = {
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
                PairingCallout(
                    title = "Nearby devices",
                    body = "Allow Bluetooth and nearby devices so we can find your Pocket.",
                    icon = MonitorIcon.WIFI,
                    action = "Allow",
                    onAction = onRequestPermissions,
                )
            }
        },
    )
}

private fun pairingPresentation(
    phase: ConnectionPhase,
    step: Int,
    scanning: Boolean,
    busy: Boolean,
    error: String?,
    found: List<FoundCamera>,
    picked: FoundCamera?,
    radioReady: Boolean,
    connectedName: String?,
    joinedSSID: String?,
    vpnActive: Boolean,
    bluetoothOn: Boolean,
    permissionsGranted: Boolean,
): MonitorPairingPresentation {
    val instructions = when (step) {
        1 -> listOf(
            MonitorPairingInstruction(
                title = "On the camera",
                icon = MonitorPairingInstructionIcon.CAMERA,
                lines = listOf("Look for an Approve / pairing prompt", "Tap it on the camera screen"),
            ),
            MonitorPairingInstruction(
                title = "On this phone",
                icon = MonitorPairingInstructionIcon.PHONE,
                lines = listOf("Wait here — we keep the Bluetooth link alive", "Don't force-quit the app"),
            ),
        )
        2 -> listOf(
            MonitorPairingInstruction(
                title = "On the camera",
                icon = MonitorPairingInstructionIcon.CAMERA,
                lines = listOf(
                    "Leave the camera on — it brings up its own Wi-Fi",
                    "On 5.8 GHz that can take about a minute; we keep trying",
                ),
            ),
            MonitorPairingInstruction(
                title = "On this phone",
                icon = MonitorPairingInstructionIcon.PHONE,
                lines = listOf(
                    "Tap Join when Android asks to join the camera network",
                    LocalVPNFilter.JOIN_WIFI_PHONE_STEP,
                ),
            ),
        )
        3 -> if (vpnActive) {
            listOf(
                MonitorPairingInstruction(
                    title = "Check the connection",
                    icon = MonitorPairingInstructionIcon.PHONE,
                    lines = listOf(LocalVPNFilter.WIZARD_BANNER),
                ),
            )
        } else {
            emptyList()
        }
        else -> emptyList()
    }
    val checks = if (step >= 2) {
        listOf(
            MonitorPairingCheck(
                title = "Bluetooth link",
                subtitle = connectedName ?: "Camera connected",
                state = MonitorPairingCheckState.COMPLETE,
                stateLabel = "OK",
            ),
            MonitorPairingCheck(
                title = "Camera Wi-Fi",
                subtitle = joinedSSID ?: "Waiting for the camera network",
                state = if (step > 2) MonitorPairingCheckState.COMPLETE else MonitorPairingCheckState.ACTIVE,
                stateLabel = if (step > 2) "OK" else "JOINING",
            ),
            MonitorPairingCheck(
                title = "Live picture",
                subtitle = if (step > 2) "Opening the video link…" else "Starts after Wi-Fi joins",
                state = if (step > 2) MonitorPairingCheckState.ACTIVE else MonitorPairingCheckState.WAITING,
                stateLabel = "WAITING",
            ),
        )
    } else {
        emptyList()
    }
    val hint = when {
        scanning -> picked?.name?.let { "Selected $it" } ?: "Choose the camera that matches your screen"
        step == 1 -> "Nothing to type — approve it on the camera"
        step == 2 -> "Android asks to join the camera network"
        else -> "Monitoring opens when the picture is ready"
    }
    val (primary, primaryEnabled) = when {
        phase == ConnectionPhase.FAILED -> "Try again" to true
        !bluetoothOn -> "Turn Bluetooth on" to true
        !permissionsGranted -> "Allow nearby devices" to true
        scanning -> "Continue" to (picked != null && !busy)
        else -> null to false
    }
    return MonitorPairingPresentation(
        steps = pairingSteps,
        currentStep = step,
        title = pairingTitles[step],
        body = pairingBodies[step],
        target = (if (scanning) picked?.name else connectedName) ?: "Nothing selected yet",
        hint = hint,
        progress = if (phase != ConnectionPhase.FAILED && (busy || phase == ConnectionPhase.SCANNING)) {
            StartupConnectionCopy.phaseLabel(phase, null)
        } else {
            null
        },
        error = error,
        devices = if (scanning) found.map { device ->
            MonitorPairingDevice(
                id = device.id,
                name = FoundCameraIdentity.listTitle(device.name, device.model.name),
                subtitle = FoundCameraIdentity.listSubtitle(device.name, device.model.name, device.model.family) +
                    if (device.model.verified) "" else " · unverified",
                selected = picked?.id == device.id,
                busy = busy,
            )
        } else emptyList(),
        instructions = instructions,
        checks = checks,
        emptyTitle = if (scanning && radioReady && found.isEmpty()) {
            if (phase == ConnectionPhase.SCANNING) "Looking for cameras" else "No cameras yet"
        } else {
            null
        },
        primaryAction = primary,
        primaryActionEnabled = primaryEnabled,
        backAction = if (busy) "Cancel" else null,
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

fun pocketRuntimePermissions(): Array<String> {
    val perms = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)
    if (Build.VERSION.SDK_INT >= 31) {
        perms += Manifest.permission.BLUETOOTH_SCAN
        perms += Manifest.permission.BLUETOOTH_CONNECT
    }
    if (Build.VERSION.SDK_INT >= 33) {
        perms += Manifest.permission.NEARBY_WIFI_DEVICES
    }
    return perms.toTypedArray()
}
