package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.*

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
            session.connectedCamera?.model?.name, labelProfile, send = ::setShootingMode)
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
    }
}

internal suspend fun AppModel.refreshForCaptureSheet(what: CaptureRefresh) {
    when (what) {
        CaptureRefresh.AUDIO -> audioService?.refresh?.invoke()
        CaptureRefresh.FOCUS_TRACK -> refreshFocusTrack()
        CaptureRefresh.ISO_LIMIT -> refreshIsoLimitNow()
    }
}

internal fun AppModel.captureAudioService(): CaptureAudioService? {
    if (!monitorLayout().audio) return null
    val owner = session.connectedCamera?.id ?: return null
    val snapshot = control.state.value.snapshot ?: return null
    val source = CaptureAudioSourceID(snapshot.session, snapshot.epoch)
    val status = session.status.value
    return CaptureAudioService(source, listOf(
        CaptureAudioField(CaptureAudioControl.CHANNEL, "Channel",
            CaptureAudioChannel.entries.map { CaptureAudioValue.Channel(it) },
            CaptureAudioChannel.entries.firstOrNull { it.raw == status.audioChannel }?.let { CaptureAudioValue.Channel(it) }),
        CaptureAudioField(CaptureAudioControl.WIND, "Wind",
            listOf(CaptureAudioValue.Wind(false), CaptureAudioValue.Wind(true)),
            status.windNr.takeIf { it in 0..1 }?.let { CaptureAudioValue.Wind(it == 1) }),
        CaptureAudioField(CaptureAudioControl.DIRECTION, "Direction",
            CaptureAudioDirection.entries.map { CaptureAudioValue.Direction(it) },
            CaptureAudioDirection.entries.firstOrNull { it.raw == status.directionalAudio }?.let { CaptureAudioValue.Direction(it) }),
        CaptureAudioField(CaptureAudioControl.VOCAL, "Vocal",
            listOf(CaptureAudioValue.Vocal(false), CaptureAudioValue.Vocal(true)),
            status.vocalBoost.takeIf { it in 0..1 }?.let { CaptureAudioValue.Vocal(it == 1) })
    ), commit = { value ->
        val current = control.state.value.snapshot
        if (session.connectedCamera?.id != owner || !monitorLayout().audio || current == null ||
            CaptureAudioSourceID(current.session, current.epoch) != source) CaptureAudioCommitResult.UNAVAILABLE
        else if (session.phase != com.opencapture.opencine.vocabulary.ConnectionPhase.LIVE || session.controlBusy.value) {
            session.presentControlNote("Audio control refused")
            CaptureAudioCommitResult.REFUSED
        } else {
            when (value) {
                is CaptureAudioValue.Channel -> setAudioChannel(value.value.raw)
                is CaptureAudioValue.Wind -> setWindNr(value.enabled)
                is CaptureAudioValue.Direction -> setDirectionalAudio(value.value.raw)
                is CaptureAudioValue.Vocal -> setVocalBoost(value.enabled)
            }
            CaptureAudioCommitResult.SUBMITTED
        }
    }, refresh = {
        val current = control.state.value.snapshot
        if (session.connectedCamera?.id == owner && current != null &&
            CaptureAudioSourceID(current.session, current.epoch) == source) refreshAudio()
    })
}
