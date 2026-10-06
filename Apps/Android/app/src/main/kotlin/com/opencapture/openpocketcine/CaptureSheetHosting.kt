package com.opencapture.openpocketcine

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.opencapture.opencine.appkit.MonitorCaptureDrum
import com.opencapture.opencine.appkit.MonitorCaptureField
import com.opencapture.opencine.appkit.captureField
import com.opencapture.opencine.appkit.commit
import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.CaptureRefresh
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.cameracontrols.applyCaptureShootingMode
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.MonitorLayoutCapabilities
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.WhiteBalanceValue
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.CaptureSessionState
import com.opencapture.opencine.vocabulary.CaptureSetting
import com.opencapture.opencine.vocabulary.FocusTrackMode

/**
 * Pocket's capture session state: the DJI session's AE/AWB locks and format pin, and the DJI
 * integration's layout for focus and iris. Every DJI body hops native ISO, so the toggle always shows.
 * Values are read when the sheet reads them (the format pin expires on time).
 */
internal fun pocketCaptureSessionState(
    aeLock: () -> Any?,
    awbLockKelvin: () -> Int?,
    awbLockOffered: () -> Boolean,
    formatPinned: () -> Boolean,
    layout: () -> MonitorLayoutCapabilities,
): CaptureSessionState = object : CaptureSessionState {
    override val aeLocked get() = aeLock() != null
    override val awbLockKelvin get() = awbLockKelvin()
    override val awbLockOffered get() = awbLockOffered()
    override val formatPinned get() = formatPinned()
    override val focusModeSupported get() = layout().focus
    override val irisSupported get() = layout().iris
    override val nativeIsoHopSupported get() = true
}

@Composable
internal fun AppModel.observedCaptureSessionState(status: CameraStatus): CaptureSessionState {
    val aeLock by session.aeLock.collectAsState()
    val awbLock by session.awbLockKelvin.collectAsState()
    return pocketCaptureSessionState({ aeLock }, { awbLock }, { session.autoWhiteBalanceLock(status) != null },
        { session.isFormatPinActive }, { monitorLayout() })
}

/** ISO, shutter and white balance Kelvin through the captured Core field; EV through Core too. */
@Composable
internal fun AppModel.PocketCommonDrum(sheet: LiveSheet, status: CameraStatus, field: MonitorCaptureField?, enabled: Boolean) {
    val retained = retainedCapturePanelField(field, sheet, status.expoMode)
    if (retained == null) {
        Text("Setting not available", color = LiveDesign.muted)
    } else {
        val choices = retained.choices.filter { choice -> when (val value = choice.value) {
            is SettingValue.Iso -> value.value is ISOValue.Manual
            is SettingValue.Shutter -> value.value is ShutterValue.Duration
            is SettingValue.WhiteBalance -> value.value is WhiteBalanceValue.Kelvin
            is SettingValue.ExposureCompensation -> true
            else -> false
        } }
        MonitorCaptureDrum(control, retained,
            enabled = enabled && (!CaptureLists.isEvSheet(sheet, status.expoMode) || !facePriorityExposureEnabled),
            choices = choices)
    }
}

/** Pocket's sheet commits: the typed DJI setters, and focus through the captured Core editor. */
internal fun AppModel.routeCaptureSetting(setting: CaptureSetting, field: MonitorCaptureField?, status: CameraStatus) {
    when (setting) {
        is CaptureSetting.IsoIndex -> setIsoIndex(setting.index)
        is CaptureSetting.IsoLimitRaw -> setIsoLimit(setting.raw)
        is CaptureSetting.Ev -> setEv(setting.thirds)
        is CaptureSetting.ShutterDenom -> setShutterDenom(setting.denom)
        is CaptureSetting.ShutterAngle -> session.setShutterAngle(setting.degrees)
        is CaptureSetting.WhiteBalance -> setWhiteBalance(setting.kelvin, setting.tint)
        CaptureSetting.WhiteBalanceAuto -> setWhiteBalanceAuto()
        is CaptureSetting.WhiteBalanceTint ->
            setting.kelvin?.let { setWhiteBalance(it, setting.tint) } ?: setWhiteBalanceAuto(setting.tint)
        CaptureSetting.AutoWhiteBalanceLock -> session.lockAutoWhiteBalance()
        is CaptureSetting.Format -> setVideoFormat(setting.format)
        is CaptureSetting.ColorMode -> setColorMode(setting.code)
        is CaptureSetting.ShootingMode -> applyCaptureShootingMode(setting.label, session.status.value,
            session.connectedCamera?.model?.name, send = ::setShootingMode)
        is CaptureSetting.Aperture -> setApertureStrategy(setting.raw)
        is CaptureSetting.ExpoMode -> setExpoMode(setting.mode)
        is CaptureSetting.Focus -> {
            val editor = field?.editor
            if (editor != null && control.isCurrent(editor)) {
                val value = commonFocusValue(setting.label, FocusTrackMode.fromRaw(status.focusTrack))
                if (value != null) control.commit(value, editor, "FOCUS ${setting.label}")
                else applyCaptureFocusChoice(setting.label, status, this)
            }
        }
        is CaptureSetting.AudioChannel -> setAudioChannel(setting.value)
        is CaptureSetting.DirectionalAudio -> setDirectionalAudio(setting.mode)
        is CaptureSetting.WindNoiseReduction -> setWindNr(setting.on)
        is CaptureSetting.VocalBoost -> setVocalBoost(setting.on)
    }
}

internal suspend fun AppModel.refreshForCaptureSheet(what: CaptureRefresh) {
    when (what) {
        CaptureRefresh.AUDIO -> refreshAudio()
        CaptureRefresh.FOCUS_TRACK -> refreshFocusTrack()
        CaptureRefresh.ISO_LIMIT -> refreshIsoLimitNow()
    }
}
