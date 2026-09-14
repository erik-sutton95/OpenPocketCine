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
import androidx.compose.foundation.layout.heightIn
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
    val found by model.session.found.collectAsState()
    val phase by model.session.phaseFlow.collectAsState()
    val reconnecting by model.session.isReconnecting.collectAsState()
    val targetId by model.session.connectionTargetId.collectAsState()
    val busy = phase.isBusy() || reconnecting
    val connectingLabel = if (reconnecting && phase == ConnectionPhase.SCANNING) {
        "Looking for camera…"
    } else StartupConnectionCopy.phaseLabel(phase, null)
    val savedIds = model.savedCameras.map { it.id }.toSet()
    val unsaved = found.filter { it.id !in savedIds }
    val sections = listOf(
        com.opencapture.monitorui.MonitorCameraSection<HomeCamera>(
            "PAIRED · ${model.savedCameras.size}",
            model.savedCameras.map { HomeCamera.Paired(it) }),
        com.opencapture.monitorui.MonitorCameraSection<HomeCamera>(
            "NEARBY · ${unsaved.size}",
            unsaved.map { HomeCamera.Nearby(it) }),
    )
    com.opencapture.monitorui.MonitorCameraPage<HomeCamera>(
        brand = "OPENPOCKETCINE", sections = sections, key = { it.id },
        emptyMessage = "Pair a camera to start monitoring.",
        actions = {
            if (phase == ConnectionPhase.SCANNING) StartupStatusPill("Scanning", StartupColors.accent, pulsing = true)
            com.opencapture.openpocketcine.monitor.MonitorIconButton(OpcIcon.FILM, "Media library",
                onClick = { model.homePanel = AppPanel.MEDIA })
            com.opencapture.openpocketcine.monitor.MonitorIconButton(OpcIcon.SETTINGS, "Settings",
                onClick = { model.homePanel = AppPanel.SETTINGS })
        }, camera = { item ->
            when (item) {
                is HomeCamera.Paired ->
                    SavedCameraRow(
                        item.camera, found.firstOrNull { it.id == item.camera.id }, phase, busy,
                        connectingLabel.takeIf { busy && targetId == item.camera.id },
                        model::cancelPairing, { model.reconnect(item.camera) },
                        { model.rename(item.camera, it) }, { model.forget(item.camera) })
                is HomeCamera.Nearby ->
                    NearbyCameraRow(
                        item.camera, phase, busy,
                        connectingLabel.takeIf { busy && targetId == item.camera.id },
                        model::cancelPairing, { model.connectDiscovered(item.camera) })
            }
        }, footer = {
            StartupQuietButton("+  Pair a new camera", enabled = !busy,
                onClick = model::pairNewCamera, modifier = Modifier.fillMaxWidth().height(46.dp))
        })
}

@Composable
private fun SavedCameraRow(
    camera: SavedCamera,
    nearby: FoundCamera?,
    phase: ConnectionPhase,
    isBusy: Boolean,
    connectionLabel: String?,
    onCancel: () -> Unit,
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
    com.opencapture.monitorui.MonitorCameraCard(
        title = camera.displayName,
        detail = camera.modelName + (camera.lastSSID?.let { " · $it" } ?: ""),
        enabled = !isBusy && !connectLocked, onOpen = onConnect,
        glyph = { OpcIcon(OpcIcon.CAMERA, contentDescription = null, tint = availability,
            modifier = Modifier.size(19.dp)) },
        options = {
            Box {
                OpcIcon(
                    icon = OpcIcon.ELLIPSIS,
                    contentDescription = "Camera options",
                    tint = StartupColors.muted,
                    modifier =
                        Modifier.clip(CircleShape)
                            .clickable(enabled = !isBusy) { menu = true }
                            .size(44.dp)
                            .padding(13.dp),
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
        }, status = {
            if (connectionLabel != null) {
                Box(Modifier.weight(1f)) { StartupConnectionProgress(connectionLabel) }
                StartupQuietButton("Cancel", onClick = onCancel, modifier = Modifier.height(44.dp))
            } else {
                StartupStatusPill(if (online) "Nearby" else "Saved", availability)
                Spacer(Modifier.weight(1f))
                Box(
                    Modifier.heightIn(min = 44.dp)
                        .clickable(enabled = !isBusy && !connectLocked, onClick = onConnect),
                    contentAlignment = Alignment.Center,
                ) {
                    StartupConnectChrome(
                        text = if (online) "Connect" else "Reconnect",
                        filled = online,
                        enabled = !isBusy && !connectLocked,
                    )
                }
            }
        })
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

private sealed class HomeCamera {
    abstract val id: String
    data class Paired(val camera: SavedCamera) : HomeCamera() {
        override val id: String get() = camera.id
    }
    data class Nearby(val camera: FoundCamera) : HomeCamera() {
        override val id: String get() = camera.id
    }
}

@Composable
private fun NearbyCameraRow(
    camera: FoundCamera,
    phase: ConnectionPhase,
    isBusy: Boolean,
    connectionLabel: String?,
    onCancel: () -> Unit,
    onConnect: () -> Unit,
) {
    val connectLocked =
        phase == ConnectionPhase.JOINING_WIFI ||
            phase == ConnectionPhase.OPENING_DATALINK ||
            phase == ConnectionPhase.LIVE
    com.opencapture.monitorui.MonitorCameraCard(
        title = camera.name,
        detail = camera.model.name,
        enabled = !isBusy && !connectLocked, onOpen = onConnect,
        glyph = {
            OpcIcon(OpcIcon.CAMERA, contentDescription = null, tint = StartupColors.ready,
                modifier = Modifier.size(19.dp))
        },
        options = {},
        status = {
            if (connectionLabel != null) {
                Box(Modifier.weight(1f)) { StartupConnectionProgress(connectionLabel) }
                StartupQuietButton("Cancel", onClick = onCancel, modifier = Modifier.height(44.dp))
            } else {
                StartupStatusPill("Announcing", StartupColors.ready)
                Spacer(Modifier.weight(1f))
                Box(
                    Modifier.heightIn(min = 44.dp)
                        .clickable(enabled = !isBusy && !connectLocked, onClick = onConnect),
                    contentAlignment = Alignment.Center,
                ) {
                    StartupConnectChrome(text = "Connect", filled = true, enabled = !isBusy && !connectLocked)
                }
            }
        },
    )
}
