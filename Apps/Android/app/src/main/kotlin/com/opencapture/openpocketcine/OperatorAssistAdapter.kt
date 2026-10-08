package com.opencapture.openpocketcine

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.opencapture.opencine.cameracontrols.AssistLutPicker
import com.opencapture.opencine.cameracontrols.MonitorOperatorAssistSource
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.openpocketcine.assists.AppAssistHost
import com.opencapture.openpocketcine.assists.AssistInspectorImagePreview
import com.opencapture.openpocketcine.feed.GpuOverlayBus
import com.opencapture.openpocketcine.lut.AppLutPickerCopy
import kotlinx.coroutines.flow.map

/** Native scope publications and one bounded native preview. Common owners compose every assist. */
@Composable
internal fun rememberOperatorAssistSource(model: AppModel, status: CameraStatus): MonitorOperatorAssistSource {
    val publications = remember(model.scopeBus) { model.scopeBus.publications.map { it.bundle } }
    val selection = model.lutSelection
    val look = AssistLutPicker(AppLutPickerCopy, selection, model::updateLutSelection,
        profile = model.camera?.captureProfile?.looks ?: com.opencapture.opencine.dji.DjiCameraLUTProfile.make("pocket", null), colorMode = status.monitorColorMode)
    return MonitorOperatorAssistSource(AppAssistHost, publications, { GpuOverlayBus.onSlotsMoved?.invoke() }, look, preview = { tool ->
        AssistInspectorImagePreview(tool, model.assist, model, selection, status.monitorColorMode, false)
    })
}
