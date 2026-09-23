package com.opencapture.openpocketcine.pairing

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorCameraCard
import com.opencapture.monitorui.MonitorCameraPage
import com.opencapture.monitorui.MonitorCameraSection
import com.opencapture.monitorui.MonitorPalette
import com.opencapture.monitorui.MonitorTypography
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.AppPanel
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.monitor.MonitorIconButton
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
    val latestId = model.savedCameras.maxByOrNull { it.lastConnectedAt }?.id
    val sections = listOf(
        MonitorCameraSection<HomeCamera>(
            title = "PAIRED",
            note = "tap to reconnect",
            cameras = model.savedCameras.map { HomeCamera.Paired(it) },
        ),
        MonitorCameraSection<HomeCamera>(
            title = "NEARBY",
            note = "announcing over Bluetooth",
            cameras = unsaved.map { HomeCamera.Nearby(it) },
        ),
    )
    MonitorCameraPage(
        brand = "OPENPOCKETCINE",
        sections = sections,
        key = { it.id },
        emptyMessage = "Pair a new camera to start monitoring.",
        scanning = phase == ConnectionPhase.SCANNING,
        actions = {
            MultiviewHeaderButton(enabled = !busy, onClick = model::openMultiview)
            MonitorIconButton(
                OpcIcon.FILM,
                "Media library",
                onClick = { model.homePanel = AppPanel.MEDIA },
            )
            MonitorIconButton(
                OpcIcon.SETTINGS,
                "Settings",
                onClick = { model.homePanel = AppPanel.SETTINGS },
            )
        },
        camera = { item ->
            when (item) {
                is HomeCamera.Paired ->
                    SavedCameraRow(
                        camera = item.camera,
                        nearby = found.firstOrNull { it.id == item.camera.id },
                        primary = item.camera.id == latestId,
                        phase = phase,
                        isBusy = busy,
                        connectionLabel = connectingLabel.takeIf { busy && targetId == item.camera.id },
                        onCancel = model::cancelPairing,
                        onConnect = { model.reconnect(item.camera) },
                        onRename = { model.rename(item.camera, it) },
                        onRemove = { model.forget(item.camera) },
                    )
                is HomeCamera.Nearby ->
                    NearbyCameraRow(
                        camera = item.camera,
                        phase = phase,
                        isBusy = busy,
                        connectionLabel = connectingLabel.takeIf { busy && targetId == item.camera.id },
                        onCancel = model::cancelPairing,
                        onConnect = { model.connectDiscovered(item.camera) },
                    )
            }
        },
        footer = {
            PairNewCameraFooter(enabled = !busy, onClick = model::pairNewCamera)
        },
    )
}

@Composable
private fun SavedCameraRow(
    camera: SavedCamera,
    nearby: FoundCamera?,
    primary: Boolean,
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
    val connecting = connectionLabel != null
    val connectLocked =
        phase == ConnectionPhase.JOINING_WIFI ||
            phase == ConnectionPhase.OPENING_DATALINK ||
            phase == ConnectionPhase.LIVE
    MonitorCameraCard(
        title = camera.displayName,
        detail = camera.modelName + (camera.lastSSID?.let { " · $it" } ?: ""),
        status = connectionLabel
            ?: if (online) "Nearby · ready to connect" else "Not found — power it on to reconnect",
        actionTitle = if (online) "Connect" else "Reconnect",
        enabled = !isBusy && !connectLocked,
        onOpen = onConnect,
        badge = when {
            connecting -> "CONNECTING"
            primary -> "LAST USED"
            online -> "PAIRED"
            else -> "OFFLINE"
        },
        primary = primary,
        busy = connecting,
        available = online,
        onCancel = onCancel,
        glyph = {
            OpcIcon(
                OpcIcon.CAMERA,
                contentDescription = null,
                tint = if (primary) MonitorPalette.accent else MonitorPalette.muted,
                modifier = Modifier.size(19.dp),
            )
        },
        options = {
            Box {
                Box(
                    Modifier.size(36.dp, 44.dp)
                        .clickable(enabled = !isBusy) { menu = true }
                        .semantics { contentDescription = "Options for ${camera.displayName}" },
                    contentAlignment = Alignment.Center,
                ) {
                    OpcIcon(
                        icon = OpcIcon.ELLIPSIS,
                        contentDescription = null,
                        tint = MonitorPalette.muted,
                        modifier = Modifier.size(15.dp),
                    )
                }
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
        },
    )
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
    val connecting = connectionLabel != null
    val connectLocked =
        phase == ConnectionPhase.JOINING_WIFI ||
            phase == ConnectionPhase.OPENING_DATALINK ||
            phase == ConnectionPhase.LIVE
    val unverified = if (camera.model.verified) "" else " · unverified"
    MonitorCameraCard(
        title = FoundCameraIdentity.listTitle(camera.name, camera.model.name),
        detail = FoundCameraIdentity.listSubtitle(camera.name, camera.model.name, camera.model.family) + unverified,
        status = connectionLabel ?: "Needs approval on the camera",
        actionTitle = "Pair",
        enabled = !isBusy && !connectLocked,
        onOpen = onConnect,
        badge = "NEW",
        primary = false,
        busy = connecting,
        available = true,
        onCancel = onCancel,
        glyph = {
            OpcIcon(
                OpcIcon.CAMERA,
                contentDescription = null,
                tint = MonitorPalette.muted,
                modifier = Modifier.size(19.dp),
            )
        },
    )
}

@Composable
private fun PairNewCameraFooter(enabled: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(11.dp)
    Row(
        Modifier.fillMaxWidth()
            .height(46.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.03f))
            .border(1.dp, MonitorPalette.secondary.copy(alpha = 0.22f), shape)
            .clickable(enabled = enabled, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        OpcIcon(OpcIcon.PLUS, contentDescription = null, tint = MonitorPalette.text, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(9.dp))
        Text(
            "Pair a new camera",
            color = MonitorPalette.text,
            style = MonitorTypography.text(13f, FontWeight.SemiBold),
            maxLines = 1,
        )
    }
}

/** iOS `CamerasPage` grid header action: accented, titled when the header has room. */
@Composable
private fun MultiviewHeaderButton(enabled: Boolean, onClick: () -> Unit) {
    val window = androidx.compose.ui.platform.LocalWindowInfo.current.containerSize
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    val width = window.width / density
    val height = window.height / density
    val tablet = minOf(width, height) >= 600f
    val fullLabels = tablet || width > height
    val shape = RoundedCornerShape(12.dp)
    Row(
        Modifier.height(if (tablet) 48.dp else 43.dp)
            .alpha(if (enabled) 1f else 0.38f)
            .clip(shape)
            .background(MonitorPalette.accent.copy(alpha = 0.12f))
            .border(1.dp, MonitorPalette.accent.copy(alpha = 0.3f), shape)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = "Open Multiview" }
            .padding(horizontal = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OpcIcon(
            OpcIcon.LAYOUT_GRID,
            contentDescription = null,
            tint = MonitorPalette.accent,
            modifier = Modifier.size(if (tablet) 26.dp else 23.dp),
        )
        if (fullLabels) {
            Text(
                "Multi-view",
                color = MonitorPalette.text,
                style = MonitorTypography.text(12.5f, FontWeight.SemiBold),
                maxLines = 1,
            )
        }
    }
}
