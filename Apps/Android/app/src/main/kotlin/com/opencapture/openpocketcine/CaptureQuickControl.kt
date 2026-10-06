package com.opencapture.openpocketcine

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.opencapture.monitorui.MonitorQuickControl
import com.opencapture.opencine.appkit.MonitorCaptureField
import com.opencapture.opencine.appkit.captureField
import com.opencapture.opencine.appkit.commit
import com.opencapture.opencine.appkit.quickControl
import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.cameracontrols.CaptureQuickLifetime
import com.opencapture.opencine.cameracontrols.IsoSheetLogic
import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.cameracontrols.applyCaptureFocusChoice
import com.opencapture.opencine.cameracontrols.applyCaptureShootingMode
import com.opencapture.opencine.cameracontrols.captureQuickFocusControl
import com.opencapture.opencine.cameracontrols.commitCaptureQuickControl
import com.opencapture.opencine.cameracontrols.recordingCategoryQuickControl
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.vocabulary.ApertureStrategy
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.opencine.vocabulary.ShutterAngle
import com.opencapture.opencine.vocabulary.VideoFormat

/** Reuses the persistent picker's production choices and typed action methods. */
internal fun captureQuickControl(sheet: LiveSheet, status: CameraStatus, model: AppModel,
    context: Context, lifetime: CaptureQuickLifetime? = null): MonitorQuickControl? {
    val body = model.session.connectedCamera?.model?.name.orEmpty()
    fun chrome(control: MonitorQuickControl) = control.copy(identity = CaptureQuickSource(
        model.session, model.session.connectedCamera?.id, model.session.phase, lifetime, lifetime?.epoch ?: 0L,
        control.identity as? MonitorCaptureField ?: if (sheet == LiveSheet.FOCUS) model.control.captureField(SettingKey.FOCUS_MODE) else null,
    ))
    commonCaptureField(sheet, status, model)?.let { return chrome(it.quickControl().copy(
        enabled = it.isEditable && (sheet != LiveSheet.SHUTTER || status.expoMode != CameraCommands.EXPO_AUTO || !model.facePriorityExposureEnabled))) }
    return when (sheet) {
        LiveSheet.ISO -> {
            val seat = IsoSheetLogic.reseat(status, body)
            chrome(MonitorQuickControl(if (IsoSheetLogic.isAutoTab(status, seat.selectedMode))
                CaptureLists.isoAutoLabels(status, body) else CaptureLists.isoDrumLabels(status),
                seat.drumSelection, CaptureLists.isoMarkedLabels(status), context = "${status.colorMode}"))
        }
        LiveSheet.SHUTTER -> {
            val auto = CaptureLists.isEvSheet(sheet, status.expoMode)
            val angle = model.shutterUsesAngle && !auto && !CameraCommands.isPhotoMode(status.shootingMode)
            val selected = if (auto) CaptureLists.reseatEv(status).selection else
                CaptureLists.reseatShutter(status, if (angle) 1 else 0, false,
                    OperatorPrefs.shutterAngleDegrees(context)).selection
            chrome(MonitorQuickControl(if (auto) CaptureLists.evLabels else if (angle) ShutterAngle.labels else CaptureLists.shutterLabels(status),
                selected, enabled = !auto || !model.facePriorityExposureEnabled,
                context = "${status.fps}:${status.availableShutterDenoms}:${status.expoMode}:$angle:${status.shootingMode}"))
        }
        LiveSheet.WB -> {
            val awbLocked = model.session.awbLockKelvin.value != null
            chrome(
                if (status.wbMode == CameraCommands.WB_CUSTOM && !awbLocked)
                    MonitorQuickControl(CaptureLists.kelvinLabels, CaptureLists.wbDrumSelection(status), context = "${CaptureLists.currentTint(status)}")
                else MonitorQuickControl(
                    CaptureLists.wbModeRows(awbLocked || model.session.autoWhiteBalanceLock(status) != null),
                    CaptureLists.wbModeRowSelected(status, awbLocked),
                    context = "${status.wbMode}:${CaptureLists.currentKelvin(status)}:${CaptureLists.currentTint(status)}"))
        }
        LiveSheet.FOCUS -> if (!model.monitorLayout().focus) null else chrome(captureQuickFocusControl(status))
        LiveSheet.APERTURE -> if (!model.monitorLayout().iris) null else chrome(MonitorQuickControl(
            CaptureLists.apertureLabels(status), ApertureStrategy.label(status.apertureStrategy).orEmpty()))
        LiveSheet.EXPO -> {
            val aeLocked = model.session.aeLock.value != null
            chrome(MonitorQuickControl(CaptureLists.expoLabels(aeLocked),
                CaptureLists.expoSelectedLabel(status.expoMode, aeLocked) ?: CaptureLists.expoLabel(status.expoMode)))
        }
        LiveSheet.AUDIO -> {
            if (!model.showsAudio(status)) null
            else chrome(MonitorQuickControl(CaptureLists.audioChannelLabels, CaptureLists.audioChannelLabel(status.audioChannel).orEmpty()))
        }
        LiveSheet.FORMAT, LiveSheet.COLOR, LiveSheet.MODE -> {
            val family = model.session.connectedCamera?.model?.family ?: "pocket"
            recordingCategoryQuickControl(sheet, status, body, family)?.let(::chrome)
        }
    }
}

/** Compound automatic limits, angle preference and AWB lock remain explicit integration adapters. */
internal fun commonCaptureField(sheet: LiveSheet, status: CameraStatus, model: AppModel): MonitorCaptureField? {
    val key = when (sheet) {
        LiveSheet.ISO -> if (CaptureLists.shouldGetIsoLimit(status)) null else SettingKey.ISO
        LiveSheet.SHUTTER -> if (status.expoMode == CameraCommands.EXPO_AUTO) SettingKey.EXPOSURE_COMPENSATION
            else if (model.shutterUsesAngle && !CameraCommands.isPhotoMode(status.shootingMode)) null else SettingKey.SHUTTER
        LiveSheet.WB -> if (status.wbMode == CameraCommands.WB_CUSTOM && model.session.awbLockKelvin.value == null)
            SettingKey.WHITE_BALANCE else null
        else -> null
    } ?: return null
    return model.control.captureField(key) ?: MonitorCaptureField(key,
        com.opencapture.opencine.appkit.MonitorCapturePresentation.title(key).orEmpty(), null, emptyList(), null)
}

internal fun captureReadoutLabel(sheet: LiveSheet, status: CameraStatus, model: AppModel?, nativeLabel: String): String {
    val field = model?.let { commonCaptureField(sheet, status, it) } ?: return nativeLabel
    return field.label ?: "--"
}

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

internal fun applyCaptureQuickControl(sheet: LiveSheet, value: String, status: CameraStatus,
    model: AppModel, context: Context) {
    val snapshot = captureQuickControl(sheet, status, model, context) ?: return
    if (!snapshot.enabled || value !in snapshot.options || value == snapshot.selection) return
    when (sheet) {
        LiveSheet.ISO -> {
            val body = model.session.connectedCamera?.model?.name.orEmpty()
            when (val command = IsoSheetLogic.applyDrum(value, status, IsoSheetLogic.reseat(status, body).selectedMode, body)) {
                is IsoSheetLogic.Command.SetIndex -> model.setIsoIndex(command.index)
                is IsoSheetLogic.Command.SetLimit -> model.setIsoLimit(command.raw)
                null -> Unit
            }
        }
        LiveSheet.SHUTTER -> when (val command = CaptureLists.applyShutterDrum(value,
            CaptureLists.isEvSheet(sheet, status.expoMode),
            model.shutterUsesAngle && status.expoMode != CameraCommands.EXPO_AUTO &&
                !CameraCommands.isPhotoMode(status.shootingMode),
            model.facePriorityExposureEnabled, status)) {
            is CaptureLists.ShutterDrumCommand.SetEv -> model.setEv(command.thirds)
            is CaptureLists.ShutterDrumCommand.SetShutter -> model.setShutterDenom(command.denom)
            is CaptureLists.ShutterDrumCommand.SetAngle -> {
                model.session.setShutterAngle(command.degrees)
            }
            CaptureLists.ShutterDrumCommand.Ignored -> Unit
        }
        LiveSheet.WB -> {
            if (value == CaptureLists.AWB_LOCK) model.session.lockAutoWhiteBalance()
            else if (status.wbMode == CameraCommands.WB_CUSTOM && model.session.awbLockKelvin.value == null) {
                CaptureLists.wbCustomFromKelvinLabel(value, status)?.let { model.setWhiteBalance(it.first, it.second) }
            } else if (CaptureLists.wbSendsAuto(value)) model.setWhiteBalanceAuto()
            else CaptureLists.wbCustomFromStatus(status).let { model.setWhiteBalance(it.first, it.second) }
        }
        LiveSheet.FOCUS -> applyCaptureFocusChoice(value, status, model)
        LiveSheet.APERTURE -> CaptureLists.apertureFromLabel(value)?.let(model::setApertureStrategy)
        LiveSheet.EXPO -> CaptureLists.expoModeFromLabel(value)?.let(model::setExpoMode)
        LiveSheet.AUDIO -> CaptureLists.audioChannelValue(value)?.let(model::setAudioChannel)
        LiveSheet.FORMAT -> {
            if (CameraCommands.isPhotoMode(status.shootingMode)) return
            val formatStatus = CaptureLists.withEffectiveVideoFormats(
                status, model.session.connectedCamera?.model,
            )
            val format = VideoFormat.current(formatStatus)
            val aspect = format.resolution.aspect
            val tab = CaptureLists.formatResolutions(formatStatus, aspect).indexOf(format.resolution).coerceAtLeast(0)
            CaptureLists.nextVideoFormat(formatStatus, tab, value, fromDrum = true, aspect)?.let(model::setVideoFormat)
        }
        LiveSheet.COLOR -> CaptureLists.applyColorDrum(
            label = value, family = model.session.connectedCamera?.model?.family ?: "pocket",
            status = status, hopEnabled = model.nativeISOHopEnabled,
            name = model.session.connectedCamera?.model?.name.orEmpty(),
        )?.let { model.setColorMode(it.colorMode) }
        LiveSheet.MODE -> applyCaptureShootingMode(value, model.session.status.value,
            model.session.connectedCamera?.model?.name, send = model::setShootingMode)
    }
}

internal fun applyCaptureFocusChoice(label: String, status: CameraStatus, model: AppModel) {
    applyCaptureFocusChoice(label, status, model::setFocusMode, model::setFocusTrack)
}

private data class CaptureQuickSource(
    val session: Any, val cameraID: String?, val phase: ConnectionPhase,
    val lifetime: CaptureQuickLifetime?, val epoch: Long, val commonField: MonitorCaptureField? = null,
)

@Composable
internal fun rememberCaptureQuickLifetime(model: AppModel?): CaptureQuickLifetime {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val lifetime = remember(model, lifecycle) { CaptureQuickLifetime() }
    DisposableEffect(lifetime, lifecycle) {
        val observer = LifecycleEventObserver { _, _ ->
            lifetime.update(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
        }
        lifecycle.addObserver(observer)
        lifetime.update(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
        onDispose { lifecycle.removeObserver(observer); lifetime.update(false); lifetime.invalidate() }
    }
    LaunchedEffect(model, lifetime) {
        model?.session?.phaseFlow?.collect { lifetime.invalidate() }
    }
    return lifetime
}

internal fun releaseCaptureQuickControl(sheet: LiveSheet, expected: MonitorQuickControl, value: String,
    model: AppModel, context: Context, lifetime: CaptureQuickLifetime, enabled: Boolean) {
    val currentStatus = model.session.status.value
    val current = captureQuickControl(sheet, currentStatus, model, context, lifetime)
    commitCaptureQuickControl(expected, current, value,
        enabled && lifetime.active && model.session.phase == ConnectionPhase.LIVE && !model.session.controlBusy.value) {
        val field = (expected.identity as? CaptureQuickSource)?.commonField
        if (field != null) {
            val editor = field.editor ?: return@commitCaptureQuickControl
            if (!model.control.isCurrent(editor)) return@commitCaptureQuickControl
            val choice = field.choices.firstOrNull { it.label == value &&
                (sheet != LiveSheet.FOCUS || it.value == commonFocusValue(value,
                    com.opencapture.opencine.vocabulary.FocusTrackMode.fromRaw(currentStatus.focusTrack))) }
            if (choice != null) { model.control.commit(choice, field); return@commitCaptureQuickControl }
            if (sheet != LiveSheet.FOCUS) return@commitCaptureQuickControl
        }
        applyCaptureQuickControl(sheet, value, currentStatus, model, context)
    }
}
