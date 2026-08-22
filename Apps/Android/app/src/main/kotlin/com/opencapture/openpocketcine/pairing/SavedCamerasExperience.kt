package com.opencapture.openpocketcine.pairing

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.AppPanel
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.LiveTypeDesign
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.session.FoundCamera

@Composable
fun SavedCamerasExperience(model: AppModel) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val twoColumn = maxWidth >= 640.dp
        val introWidth = maxOf(288.dp, maxWidth * 0.36f)
        if (twoColumn) {
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                IntroCard(model, hugsContent = false, Modifier.width(introWidth).fillMaxHeight())
                CameraListCard(model, Modifier.weight(1f).fillMaxHeight())
            }
        } else {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                IntroCard(model, hugsContent = true, Modifier.fillMaxWidth())
                CameraListCard(model, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun IntroCard(model: AppModel, hugsContent: Boolean, modifier: Modifier) {
    val phase by model.session.phaseFlow.collectAsState()
    val reconnecting by model.session.isReconnecting.collectAsState()
    val busy = phase.isBusy() || reconnecting
    val connectingLabel =
        if (reconnecting && (phase == ConnectionPhase.SCANNING || phase == ConnectionPhase.IDLE)) {
            "Connecting…"
        } else {
            StartupConnectionCopy.phaseLabel(phase, null)
        }
    Column(modifier.startupCard().padding(20.dp)) {
        Text(
            "Your cameras.",
            color = StartupColors.ink,
            style = LiveType.ui(24f, FontWeight.Bold, LiveTypeDesign.Rounded),
            maxLines = 1,
        )
        Text(
            "Tap a saved camera to reconnect.",
            color = StartupColors.muted,
            style = LiveType.ui(13f, design = LiveTypeDesign.Rounded).copy(lineHeight = 16.sp),
            modifier = Modifier.padding(top = 10.dp),
        )
        if (hugsContent) Spacer(Modifier.height(16.dp)) else Spacer(Modifier.weight(1f))
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (busy) {
                StartupConnectionProgress(connectingLabel)
                StartupFilledButton(
                    "Cancel",
                    enabled = true,
                    onClick = model::cancelPairing,
                    modifier = Modifier.fillMaxWidth(),
                    large = true,
                )
            }
            StartupFilledButton(
                "Pair new camera",
                enabled = !busy,
                onClick = model::pairNewCamera,
                modifier = Modifier.fillMaxWidth(),
                large = true,
            )
            StartupQuietButton(
                "Media library",
                onClick = { model.homePanel = AppPanel.MEDIA },
                modifier = Modifier.fillMaxWidth(),
            )
            StartupQuietButton(
                "Settings",
                onClick = { model.homePanel = AppPanel.SETTINGS },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun CameraListCard(model: AppModel, modifier: Modifier) {
    val found by model.session.found.collectAsState()
    val phase by model.session.phaseFlow.collectAsState()
    val reconnecting by model.session.isReconnecting.collectAsState()
    val busy = phase.isBusy() || reconnecting
    val scroll = rememberScrollState()
    Column(modifier.startupCard().padding(22.dp)) {
        Text(
            "CAMERA LIST",
            color = StartupColors.muted,
            style = LiveType.ui(11f, FontWeight.SemiBold, LiveTypeDesign.Rounded).copy(letterSpacing = 1.4.sp),
        )
        Text(
            "Tap a camera to connect",
            color = StartupColors.ink,
            style = LiveType.ui(20f, FontWeight.Bold, LiveTypeDesign.Rounded),
            modifier = Modifier.padding(top = 6.dp),
        )
        Column(
            Modifier.weight(1f).padding(top = 16.dp).fadeOverflowBottom(scroll).verticalScroll(scroll),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            model.savedCameras.forEach { camera ->
                SavedCameraRow(
                    camera = camera,
                    nearby = found.firstOrNull { it.id == camera.id },
                    phase = phase,
                    isBusy = busy,
                    onConnect = { model.reconnect(camera) },
                    onRename = { model.rename(camera, it) },
                    onRemove = { model.forget(camera) },
                )
            }
            if (model.savedCameras.isEmpty()) {
                Text(
                    "No cameras saved yet — Pair new camera walks you through it.",
                    color = StartupColors.muted,
                    style = LiveType.ui(12f, design = LiveTypeDesign.Rounded),
                )
            }
        }
    }
}

@Composable
private fun SavedCameraRow(
    camera: SavedCamera,
    nearby: FoundCamera?,
    phase: ConnectionPhase,
    isBusy: Boolean,
    onConnect: () -> Unit,
    onRename: (String?) -> Unit,
    onRemove: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    var rename by remember { mutableStateOf(false) }
    var remove by remember { mutableStateOf(false) }
    var renameText by remember { mutableStateOf(camera.customName.orEmpty()) }
    val online = nearby != null
    val availability = if (online) StartupColors.ready else StartupColors.muted
    val connectLocked =
        phase == ConnectionPhase.JOINING_WIFI ||
            phase == ConnectionPhase.OPENING_DATALINK ||
            phase == ConnectionPhase.LIVE
    Column(
        Modifier.fillMaxWidth()
            .startupTile(borderColor = availability.copy(alpha = 0.28f))
            .clickable(enabled = !connectLocked, onClick = onConnect)
            .padding(horizontal = 16.dp, vertical = 16.dp)
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        camera.displayName,
                        color = StartupColors.ink,
                        style = LiveType.ui(16f, FontWeight.SemiBold, LiveTypeDesign.Rounded),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    StartupStatusPill(if (online) "Online" else "Offline", availability)
                    StartupConnectChrome(
                        text = if (online) "Connect" else "Reconnect",
                        filled = online,
                        enabled = !isBusy,
                    )
                }
                Text(
                    camera.modelName + (camera.lastSSID?.let { " · $it" } ?: ""),
                    color = StartupColors.muted,
                    style = LiveType.ui(13f, design = LiveTypeDesign.Rounded),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Box {
                OpcIcon(
                    icon = OpcIcon.ELLIPSIS,
                    contentDescription = "Camera options",
                    tint = StartupColors.muted,
                    modifier =
                        Modifier.clip(CircleShape)
                            .clickable(enabled = !isBusy) { menu = true }
                            .padding(horizontal = 8.dp, vertical = 8.dp)
                            .size(17.dp),
                )
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(
                        text = { Text("Rename") },
                        leadingIcon = {
                            OpcIcon(OpcIcon.PENCIL, contentDescription = null, modifier = Modifier.size(18.dp))
                        },
                        onClick = {
                            menu = false
                            renameText = camera.customName.orEmpty()
                            rename = true
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("Remove") },
                        leadingIcon = {
                            OpcIcon(OpcIcon.TRASH, contentDescription = null, modifier = Modifier.size(18.dp))
                        },
                        onClick = {
                            menu = false
                            remove = true
                        },
                    )
                }
            }
        }
    }
    if (rename) {
        AlertDialog(
            onDismissRequest = { rename = false },
            title = { Text("Rename camera") },
            text = {
                Column {
                    Text("Give this camera a name you'll recognize.")
                    OutlinedTextField(value = renameText, onValueChange = { renameText = it }, label = { Text("Name") })
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onRename(renameText)
                        rename = false
                    }
                ) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { rename = false }) { Text("Cancel") } },
        )
    }
    if (remove) {
        AlertDialog(
            onDismissRequest = { remove = false },
            title = { Text("Remove camera?") },
            text = { Text("This removes ${camera.displayName} from this phone. You can pair it again later.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        onRemove()
                        remove = false
                    }
                ) { Text("Remove") }
            },
            dismissButton = { TextButton(onClick = { remove = false }) { Text("Cancel") } },
        )
    }
}
