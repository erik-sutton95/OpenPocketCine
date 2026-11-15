package com.opencapture.openpocketcine.multiview

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.remember
import com.opencapture.opencine.appkit.MultiviewSettingsCategory
import com.opencapture.opencine.cameracontrols.LiveControlSheet
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureShutterPolicy
import com.opencapture.opencine.vocabulary.ControlCapabilities
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType

/**
 * What the Multiview settings popup offers this camera now (OpenCine's shared order and lock):
 * focus mode and aperture where the model has them, audio where the editor offers it in a video mode.
 */
internal fun multiviewSettingsCategories(camera: CameraModel, status: CameraStatus,
    controls: ControlCapabilities): List<MultiviewSettingsCategory> = MultiviewSettingsCategory.offered(
    focus = camera.supportsFocusMode,
    aperture = camera.supportsAperture,
    photo = CameraCommands.isPhotoMode(status.shootingMode),
    audio = controls.audio.isOffered && CaptureShutterPolicy.showsAudioControls(status.shootingMode),
)

/** Pocket's Live View sheet for a shared settings category. */
internal val MultiviewSettingsCategory.liveSheet: LiveSheet
    get() = when (this) {
        MultiviewSettingsCategory.ISO -> LiveSheet.ISO
        MultiviewSettingsCategory.SHUTTER -> LiveSheet.SHUTTER
        MultiviewSettingsCategory.EXPOSURE -> LiveSheet.EXPO
        MultiviewSettingsCategory.WB -> LiveSheet.WB
        MultiviewSettingsCategory.FOCUS -> LiveSheet.FOCUS
        MultiviewSettingsCategory.APERTURE -> LiveSheet.APERTURE
        MultiviewSettingsCategory.MODE -> LiveSheet.MODE
        MultiviewSettingsCategory.RESOLUTION -> LiveSheet.FORMAT
        MultiviewSettingsCategory.COLOR -> LiveSheet.COLOR
        MultiviewSettingsCategory.AUDIO -> LiveSheet.AUDIO
    }

/**
 * The settings popup's controls on one tile: Live View's native pickers over the tile's open editor,
 * and the editor's last command note under them (the shared popup adds its own status lines).
 */
@Composable
internal fun MultiviewSettingsControls(
    tile: MultiviewSession.Tile,
    category: MultiviewSettingsCategory,
    locked: Boolean,
    maxHeight: Float,
    close: () -> Unit,
) {
    val controls = tile.controlsModel ?: return
    val status by controls.session.chromeStatus.collectAsState()
    // Changing camera, category, recording or mode retires any in-progress native drum gesture.
    key(controls, category, status.isRecording, status.shootingMode) {
        LiveControlSheet(
            category.liveSheet, controls, status, locked = locked,
            onDismiss = close, maxHeightDp = maxHeight, portrait = false, showsHeader = false,
        )
    }
    // Compact error line; it takes space only while present.
    val note by controls.session.controlNote.collectAsState()
    note?.let { Text(it, color = LiveDesign.amber, style = LiveType.text(11f), maxLines = 2) }
}

/** Tile source and native preview-owner facts for the common image-preview lifecycle. */
@Composable
internal fun MultiviewSettingsPreview(tile: MultiviewSession.Tile, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val client = remember(tile, context) {
        object : com.opencapture.opencine.appkit.MonitorInspectorPreviewClient<androidx.compose.ui.graphics.ImageBitmap> {
            override fun open(owner: Any, playback: Boolean,
                plan: com.opencapture.opencine.media.FeedEffectsRenderPlan,
                receive: (androidx.compose.ui.graphics.ImageBitmap?) -> Unit) {
                tile.inspectorPreview.open(owner, playback, context, plan) { receive(it?.asImageBitmap()) }
                tile.previewOwner = owner
            }
            override fun update(owner: Any, plan: com.opencapture.opencine.media.FeedEffectsRenderPlan) {
                tile.inspectorPreview.update(owner, plan)
            }
            override fun close(owner: Any) {
                if (tile.previewOwner === owner) tile.previewOwner = null
                tile.inspectorPreview.close(owner)
            }
        }
    }
    com.opencapture.opencine.cameracontrols.MonitorOperatorInspectorImagePreview(
        com.opencapture.monitorui.MonitorAssistTool.LUT, null, client, tile.plan,
        tile, null, false, modifier, "${tile.camera?.name ?: "Camera"} preview",
        com.opencapture.opencine.cameracontrols.MonitorInspectorPreviewLayout.SOURCE)
}
