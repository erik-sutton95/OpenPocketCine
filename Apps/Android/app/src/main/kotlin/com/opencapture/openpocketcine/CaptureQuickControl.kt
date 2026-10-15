package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.MonitorCaptureField
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.cameracontrols.MonitorOperatorCaptureSource
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.vocabulary.ConnectionPhase

/** Native reports and typed setter routes over the common capture owner. */
internal fun AppModel.makeOperatorCaptureSource(): MonitorOperatorCaptureSource = MonitorOperatorCaptureSource(
    host = this, control = control, phaseEvents = session.phaseFlow,
    readStatus = { session.status.value }, readSessionState = {
        pocketCaptureSessionState({ session.aeLock.value }, { session.awbLockKelvin.value },
        { session.autoWhiteBalanceLock(session.status.value) != null }, { session.isFormatPinActive },
        { monitorLayout() }, { session.nativeISOCapabilities })
    }, ready = { session.phase == ConnectionPhase.LIVE }, busy = { session.controlBusy.value },
    confirmRecording = { recordConfirmationEnabled }, takePhoto = ::pressShutter,
)

internal fun capturePanelSettingKey(sheet: LiveSheet, expoMode: Int): SettingKey? = when (sheet) {
    LiveSheet.ISO -> SettingKey.ISO
    LiveSheet.SHUTTER -> if (expoMode == CameraCommands.EXPO_AUTO) SettingKey.EXPOSURE_COMPENSATION else SettingKey.SHUTTER
    LiveSheet.WB -> SettingKey.WHITE_BALANCE
    LiveSheet.FOCUS -> SettingKey.FOCUS_MODE
    else -> null
}

/** A panel keeps its captured approval; a mode change cannot reinterpret it as another setting. */
internal fun retainedCapturePanelField(captured: MonitorCaptureField?, sheet: LiveSheet, expoMode: Int): MonitorCaptureField? =
    captured?.takeIf { it.key == capturePanelSettingKey(sheet, expoMode) }

internal fun applyCaptureFocusChoice(label: String, status: CameraStatus, model: AppModel): Unit =
    com.opencapture.opencine.cameracontrols.applyCaptureFocusChoice(label, status, model::setFocusMode,
        model::setFocusTrack, model.labelProfile.focusLabels)
