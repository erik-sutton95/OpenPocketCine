package com.opencapture.openpocketcine

import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import com.opencapture.opencine.vocabulary.FocusTrackMode

/** AF-C must retain the native strategy reset when tracking is unknown or non-default. */
internal fun commonFocusValue(label: String, track: FocusTrackMode?): SettingValue? =
    com.opencapture.opencine.cameracontrols.captureFocusValue(label, track)

/** Cycle taps admit the target against the current described range. DJI owns continuous gesture completion. */
internal fun AppModel.commitZoomCycle(ratio: Double): Boolean {
    val editor = control.edit(SettingKey.ZOOM) ?: return false
    return control.commit(SettingValue.Zoom(ratio), editor, "Zoom $ratio")
}

internal fun AppModel.zoomCycleFrom(): Double =
    (control.state.value.pending[SettingKey.ZOOM] as? SettingValue.Zoom)?.ratio ?: session.zoomCycleFrom()

/** An operator target overlays the native readout without becoming a camera report. */
@Composable internal fun commonZoomReadout(model: AppModel, nativeFactor: Double): Double =
    (model.control.state.collectAsState().value.pending[SettingKey.ZOOM] as? SettingValue.Zoom)?.ratio ?: nativeFactor

/** Native continuous completion retains DJI color restoration, retiring only a pending common tap. */
internal fun AppModel.updateNativeZoomGesture(magnification: Double) {
    if (!session.zoomPinching.value) control.cancelEdit(SettingKey.ZOOM)
    session.updateZoomPinch(magnification)
}
