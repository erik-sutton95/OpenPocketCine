package com.opencapture.openpocketcine

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.opencapture.opencine.cameracontrols.MonitorOperatorLiveChromeSource
import com.opencapture.opencine.cameracontrols.MonitorOperatorStickActions
import com.opencapture.opencine.cameracontrols.MonitorOperatorZoomPresentation
import com.opencapture.opencine.vocabulary.CamFov
import com.opencapture.opencine.vocabulary.CameraStatus

/** Native optical reports and SDK movement ports; chrome and picker policy live in CameraControls. */
@Composable
internal fun rememberOperatorChromeSource(model: AppModel, status: CameraStatus): MonitorOperatorLiveChromeSource<AppModel> {
    val zoomReadout by model.session.zoomReadout.collectAsState()
    val dial by model.session.zoomDialReadout.collectAsState()
    val pinching by model.session.zoomPinching.collectAsState()
    val zoom = MonitorOperatorZoomPresentation(commonZoomReadout(model, zoomReadout), dial, pinching,
        CamFov.zoomNeedsColorHopWhileRecording(model.session.zoomNextJump(), status.colorMode, status.isRecording),
        model.session.zoomMax(), if (3.0 in model.session.zoomStops()) listOf(1.0, 3.0) else listOf(1.0),
        model.monitorZoomStops(), model::zoomCycleFrom, { model.commitZoomCycle(it); Unit },
        model::updateNativeZoomGesture, model.session::endZoomPinch)
    return MonitorOperatorLiveChromeSource(model, model.shell, model.operatorSession,
        model.operatorCaptureSource, OperatorPrefs, model.portraitFeedAspect, model::updatePortraitFeedAspect,
        zoom, MonitorOperatorStickActions(model::updateGimbalStick, model::endGimbalStick,
            model.session::performGimbalDoubleTap, model.session::flipGimbal), returnToStage = model.multiviewExit)
}
