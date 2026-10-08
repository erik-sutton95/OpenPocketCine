package com.opencapture.openpocketcine.assists

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.opencapture.monitorui.MonitorGuideMaskPolicy
import com.opencapture.monitorui.settings.MonitorSettingsColorDot
import com.opencapture.opencine.cameracontrols.AssistHost
import com.opencapture.opencine.cameracontrols.AssistLutPicker
import com.opencapture.opencine.cameracontrols.AssistOptionsPanel
import com.opencapture.opencine.media.MonitorTransfer
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.fromColorMode
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.lut.AppLutPickerCopy
import com.opencapture.openpocketcine.settings.SettingsPalette
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.appkit.MonitorAssistState

/** This app's assist values: its settings palettes, the envelope guide mask, and the calibration table before the first tap. */
internal val AppAssistHost = AssistHost(
    peakingColors = SettingsPalette.peaking.map { MonitorSettingsColorDot(it.name, it.color) },
    highlightColors = SettingsPalette.highlight.map { MonitorSettingsColorDot(it.name, it.color) },
    midtoneColors = SettingsPalette.midtone.map { MonitorSettingsColorDot(it.name, it.color) },
    guideMaskPolicy = MonitorGuideMaskPolicy.ENVELOPE,
    scopeCeiling = { it.scopeDisplayCeiling },
    rec709LookCurve = { com.opencapture.opencine.dji.DjiMonitorColorProfile.value.rec709LookCurves[it] },
)

/**
 * OpenZCine / iOS long-press tray: camera-controls' [AssistOptionsPanel] with this app's values.
 *
 * [model] owns the live LUT selection. When omitted (current live-view call
 * site), the picker writes [OperatorPrefs] so a later process still restores.
 */
@Composable
fun AssistOptionsPopup(
    tool: MonitorAssistTool,
    state: MonitorAssistState,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    model: AppModel? = null,
    maxHeightDp: Float? = null,
    colorMode: Int = CameraCommands.COLOR_NORMAL,
    embedded: Boolean = false,
    playback: Boolean = false,
    isPhoto: Boolean = false,
) {
    val context = LocalContext.current
    var fallbackLut by remember {
        mutableStateOf(model?.lutSelection ?: OperatorPrefs.lutSelection(context))
    }
    val lutSelection = model?.lutSelection ?: fallbackLut
    val lut = AssistLutPicker(
        copy = AppLutPickerCopy,
        selection = lutSelection,
        onSelect = { id ->
            if (model != null) {
                model.updateLutSelection(id)
            } else {
                fallbackLut = id
                OperatorPrefs.setLutSelection(context, id)
            }
        },
        profile = model?.session?.connectedCamera?.model?.captureProfile?.looks ?: com.opencapture.opencine.dji.DjiCameraLUTProfile.make("pocket", null),
        colorMode = colorMode,
    )
    AssistOptionsPanel(
        tool, state, onDismiss, AppAssistHost, lut, modifier, maxHeightDp, MonitorTransfer.fromColorMode(colorMode), embedded, playback, isPhoto,
        imagePreview = model?.let { { AssistInspectorImagePreview(tool, state, it, lutSelection, colorMode, playback) } },
    )
}
