package com.opencapture.openpocketcine.pairing

import android.Manifest
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LiveTypeDesign
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.session.FoundCamera

private val prepareSteps =
    listOf(
        "Turn the camera on and wait until Bluetooth is up.",
        "Tap the camera in the list when it appears.",
        "If the Pocket asks you to Approve, tap it on the camera screen.",
        "Join the camera Wi-Fi when Android prompts, then we open the datalink.",
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
    val step = StartupConnectionCopy.wizardStep(phase)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val compact = maxWidth < 640.dp
        val twoColumn = maxWidth >= 640.dp
        val introWidth = maxOf(236.dp, maxWidth * 0.28f)
        if (twoColumn) {
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                IntroCard(model, step, Modifier.width(introWidth).fillMaxHeight())
                StepCard(
                    model,
                    phase,
                    failure,
                    found,
                    step,
                    compact,
                    permissionsGranted,
                    onRequestPermissions,
                    onEnableBluetooth,
                    Modifier.weight(1f).fillMaxHeight(),
                )
            }
        } else {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                PortraitIntroHeader(model)
                Text(
                    "We'll walk you through it — your camera is connected in about a minute.",
                    color = StartupColors.muted,
                    style = LiveType.ui(12f, design = LiveTypeDesign.Rounded).copy(lineHeight = 16.sp),
                )
                StartupWizardProgress(step, StartupConnectionCopy.WIZARD_STEP_COUNT)
                StepCard(
                    model,
                    phase,
                    failure,
                    found,
                    step,
                    true,
                    permissionsGranted,
                    onRequestPermissions,
                    onEnableBluetooth,
                    Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun PortraitIntroHeader(model: AppModel) {
    Row(verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
            Text(
                "FIRST RUN",
                color = StartupColors.muted,
                style = LiveType.ui(11f, FontWeight.SemiBold, LiveTypeDesign.Rounded).copy(letterSpacing = 1.4.sp),
            )
            Text(
                "Pair your camera.",
                color = StartupColors.ink,
                style = LiveType.ui(22f, FontWeight.Bold, LiveTypeDesign.Rounded),
                maxLines = 1,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        if (model.savedCameras.isNotEmpty()) {
            Spacer(Modifier.width(12.dp))
            StartupYourCamerasButton(onClick = model::cancelPairing)
        }
    }
}

@Composable
private fun IntroCard(model: AppModel, step: Int, modifier: Modifier) {
    Column(modifier.startupCard().padding(20.dp)) {
        Text(
            "FIRST RUN",
            color = StartupColors.muted,
            style = LiveType.ui(11f, FontWeight.SemiBold, LiveTypeDesign.Rounded).copy(letterSpacing = 1.4.sp),
        )
        Text(
            "Pair your camera.",
            color = StartupColors.ink,
            style = LiveType.ui(32f, FontWeight.Bold, LiveTypeDesign.Rounded),
            modifier = Modifier.padding(top = 10.dp),
        )
        Text(
            "We'll walk you through it — your camera is connected in about a minute.",
            color = StartupColors.muted,
            style = LiveType.ui(13f, design = LiveTypeDesign.Rounded).copy(lineHeight = 16.sp),
            modifier = Modifier.padding(top = 12.dp),
        )
        Spacer(Modifier.weight(1f))
        StartupWizardProgress(step, StartupConnectionCopy.WIZARD_STEP_COUNT)
        if (model.savedCameras.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            StartupYourCamerasButton(onClick = model::cancelPairing, modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun StepCard(
    model: AppModel,
    phase: ConnectionPhase,
    failure: String?,
    found: List<FoundCamera>,
    step: Int,
    tight: Boolean,
    permissionsGranted: Boolean,
    onRequestPermissions: () -> Unit,
    onEnableBluetooth: () -> Unit,
    modifier: Modifier,
) {
    val title =
        when (step) {
            2 -> "Approve on Pocket"
            3 -> "Join camera Wi-Fi"
            4 -> "Open datalink"
            else -> "Find your camera"
        }
    val scroll = rememberScrollState()
    Column(modifier.startupCard().padding(22.dp)) {
        Text(
            "STEP $step OF ${StartupConnectionCopy.WIZARD_STEP_COUNT}",
            color = StartupColors.muted,
            style = LiveType.ui(11f, FontWeight.SemiBold, LiveTypeDesign.Rounded).copy(letterSpacing = 1.4.sp),
        )
        Text(
            title,
            color = StartupColors.ink,
            style = LiveType.ui(if (tight) 22f else 25f, FontWeight.Bold, LiveTypeDesign.Rounded),
            modifier = Modifier.padding(top = 6.dp),
        )
        Column(
            Modifier.weight(1f).padding(top = 16.dp).fadeOverflowBottom(scroll).verticalScroll(scroll),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            when (step) {
                2 -> ApproveStep(phase, tight)
                3 -> JoinWifiStep(phase, tight)
                4 -> DatalinkStep(phase, tight)
                else ->
                    ScanStep(
                        model = model,
                        phase = phase,
                        failure = failure,
                        found = found,
                        tight = tight,
                        permissionsGranted = permissionsGranted,
                        onRequestPermissions = onRequestPermissions,
                        onEnableBluetooth = onEnableBluetooth,
                    )
            }
        }
        val busy = phase.isBusy()
        val showFooter =
            phase == ConnectionPhase.FAILED ||
                busy ||
                ((phase == ConnectionPhase.IDLE || phase == ConnectionPhase.SCANNING) &&
                    model.savedCameras.isNotEmpty())
        if (showFooter) {
            Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (model.savedCameras.isNotEmpty() || busy) {
                    StartupOutlineButton(
                        if (busy) "Cancel" else "Back",
                        onClick = model::cancelPairing,
                        leadingChevron = true,
                        modifier = Modifier.weight(1f),
                    )
                }
                if (phase == ConnectionPhase.FAILED) {
                    StartupFilledButton(
                        "Try again",
                        enabled = true,
                        onClick = { model.session.startScan() },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun ScanStep(
    model: AppModel,
    phase: ConnectionPhase,
    failure: String?,
    found: List<FoundCamera>,
    tight: Boolean,
    permissionsGranted: Boolean,
    onRequestPermissions: () -> Unit,
    onEnableBluetooth: () -> Unit,
) {
    val radioOn by model.session.radioOn.collectAsState()
    if (!radioOn || !permissionsGranted) {
        PermissionsCard(
            radioOn = radioOn,
            permissionsGranted = permissionsGranted,
            onEnableBluetooth = onEnableBluetooth,
            onRequestPermissions = onRequestPermissions,
        )
    }
    if (model.coreVersion == null) {
        StartupInfoBanner("Swift core isn't loaded. Build with `just android-core` on an arm64 device.", tight)
    }
    if (phase == ConnectionPhase.FAILED && !failure.isNullOrBlank()) {
        StartupInfoBanner(StartupConnectionCopy.friendly(failure), tight)
    }
    if (found.isEmpty() && radioOn && permissionsGranted) {
        StartupEmptyDiscoveryCard(
            title = if (phase == ConnectionPhase.SCANNING) "Looking for cameras" else "No cameras yet",
            hint = "Turn the camera on and keep the phone nearby. Pocket and Nano both appear — tap the one you want.",
            compact = tight,
            glyph = StartupGlyphKind.ANTENNA,
        )
    } else {
        found.forEach { camera ->
            DiscoveredCameraTile(
                camera = camera,
                tight = tight,
                enabled = !phase.isBusy(),
                onClick = { model.session.connect(camera) },
            )
        }
    }
    StartupPrepareCards(prepareSteps, tight)
}

@Composable
private fun PermissionsCard(
    radioOn: Boolean,
    permissionsGranted: Boolean,
    onEnableBluetooth: () -> Unit,
    onRequestPermissions: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().startupInstructionCard()) {
        Row(
            Modifier.padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            StartupGlyph(StartupGlyphKind.SHIELD, tint = StartupColors.accent, modifier = Modifier.size(13.dp))
            Text(
                "Permissions",
                color = StartupColors.muted,
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        StartupPermissionRow(
            glyph = StartupGlyphKind.PHONE_WAVES,
            title = "Bluetooth",
            detail = "Turn Bluetooth on so we can find your Pocket.",
            granted = radioOn,
            onRequest = onEnableBluetooth,
        )
        Box(
            Modifier.fillMaxWidth()
                .padding(start = 42.dp)
                .height(1.dp)
                .background(StartupColors.border.copy(alpha = 0.10f)),
        )
        StartupPermissionRow(
            glyph = StartupGlyphKind.WIFI,
            title = "Nearby devices",
            detail = "Allow Bluetooth and nearby devices so we can find your Pocket.",
            granted = permissionsGranted,
            onRequest = onRequestPermissions,
        )
    }
}

@Composable
private fun DiscoveredCameraTile(
    camera: FoundCamera,
    tight: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .startupTile(borderColor = StartupColors.ready.copy(alpha = 0.28f))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = if (tight) 12.dp else 16.dp)
            .height(if (tight) 64.dp else 84.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (tight) 10.dp else 14.dp),
    ) {
        StartupGlyphTile(
            StartupGlyphKind.CAMERA,
            size = if (tight) 36.dp else 48.dp,
        )
        Column(Modifier.weight(1f)) {
            Text(
                FoundCameraIdentity.listTitle(camera.name, camera.model.name),
                color = StartupColors.ink,
                fontSize = if (tight) 13.sp else 15.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                FoundCameraIdentity.listSubtitle(camera.name, camera.model.name, camera.model.family) +
                    if (camera.model.verified) "" else " · unverified",
                color = StartupColors.muted,
                fontSize = if (tight) 10.sp else 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        StartupGlyph(
            StartupGlyphKind.WIFI,
            tint = StartupColors.accent,
            modifier = Modifier.size(if (tight) 16.dp else 20.dp),
        )
    }
}

@Composable
private fun ApproveStep(phase: ConnectionPhase, tight: Boolean) {
    StartupInfoBanner(
        "If the camera shows Approve, tap it on that camera's screen. First-time pairing can wait up to 90 seconds.",
        tight,
    )
    StartupDeviceInstructionCard(
        "On the camera",
        listOf("Look for an Approve / pairing prompt", "Tap it on the camera screen"),
        tight,
        glyph = StartupGlyphKind.APERTURE,
    )
    StartupDeviceInstructionCard(
        "On this phone",
        listOf("Wait here — we keep the Bluetooth link alive", "Don't force-quit the app"),
        tight,
        glyph = StartupGlyphKind.PHONE,
    )
    StartupConnectionProgress(StartupConnectionCopy.phaseLabel(phase, null), tight = tight)
}

@Composable
private fun JoinWifiStep(phase: ConnectionPhase, tight: Boolean) {
    Text(
        "We read the camera's SSID and password over Bluetooth, then join its Wi-Fi for you.",
        color = StartupColors.muted,
        fontSize = if (tight) 12.sp else 13.sp,
        lineHeight = 18.sp,
    )
    StartupDeviceInstructionCard(
        "On the camera",
        listOf("Leave the camera on — it brings up its own Wi-Fi", "No menu tap needed on this path"),
        tight,
        glyph = StartupGlyphKind.APERTURE,
    )
    StartupDeviceInstructionCard(
        "On this phone",
        listOf("Tap Join when Android asks to join the camera network", "Stay on this screen until we open the datalink"),
        tight,
        glyph = StartupGlyphKind.PHONE,
    )
    StartupConnectionProgress(StartupConnectionCopy.phaseLabel(phase, null), tight = tight)
}

@Composable
private fun DatalinkStep(phase: ConnectionPhase, tight: Boolean) {
    StartupConnectionProgress(
        label = "Opening the video link…",
        detail = StartupConnectionCopy.phaseLabel(phase, null),
        glyph = StartupGlyphKind.APERTURE,
        tight = tight,
    )
}

/** Scan-row title/subtitle — first BLE advert is often nameless. */
private object FoundCameraIdentity {
    fun isGenericName(name: String): Boolean {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return true
        val compact = trimmed.lowercase()
        return compact == "dji camera" || compact == "dji osmo camera"
    }

    fun listTitle(advertisedName: String, modelName: String): String =
        if (isGenericName(advertisedName)) modelName else advertisedName

    fun listSubtitle(advertisedName: String, modelName: String, family: String): String {
        val kind =
            when (family.lowercase()) {
                "nano" -> "Nano"
                "other" -> modelName
                else -> "Pocket"
            }
        return if (isGenericName(advertisedName) || advertisedName == modelName) {
            "$kind · nearby"
        } else {
            "$kind · $modelName · nearby"
        }
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
