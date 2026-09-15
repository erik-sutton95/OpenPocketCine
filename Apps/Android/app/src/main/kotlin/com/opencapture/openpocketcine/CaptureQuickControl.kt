package com.opencapture.openpocketcine

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.monitorui.MonitorQuickControl
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.VideoFormat

/** Reuses the persistent picker's production choices and typed action methods. */
internal fun captureQuickControl(sheet: LiveSheet, status: CameraStatus, model: AppModel,
    context: Context, lifetime: CaptureQuickLifetime? = null): MonitorQuickControl? {
    val body = model.session.connectedCamera?.model?.name.orEmpty()
    fun chrome(control: MonitorQuickControl) = control.copy(identity = CaptureQuickSource(
        model.session, model.session.connectedCamera?.id, model.session.phase, lifetime, lifetime?.epoch ?: 0L,
    ))
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
        LiveSheet.WB -> chrome(
            if (status.wbMode == CameraCommands.WB_CUSTOM)
                MonitorQuickControl(CaptureLists.kelvinLabels, CaptureLists.wbDrumSelection(status), context = "${CaptureLists.currentTint(status)}")
            else MonitorQuickControl(CaptureLists.wbModeRows, CaptureLists.wbModeRowSelected(status),
                context = "${status.wbMode}:${CaptureLists.currentKelvin(status)}:${CaptureLists.currentTint(status)}"))
        LiveSheet.FOCUS -> chrome(captureQuickFocusControl(status))
        LiveSheet.EXPO -> chrome(MonitorQuickControl(CaptureLists.expoLabels, CaptureLists.expoLabel(status.expoMode)))
        LiveSheet.AUDIO -> {
            if (CameraCommands.isPhotoMode(status.shootingMode)) null
            else chrome(MonitorQuickControl(CaptureLists.audioChannelLabels, CaptureLists.audioChannelLabel(status.audioChannel).orEmpty()))
        }
        LiveSheet.FORMAT, LiveSheet.COLOR, LiveSheet.MODE -> {
            val family = model.session.connectedCamera?.model?.family ?: "pocket"
            recordingCategoryQuickControl(sheet, status, body, family)?.let(::chrome)
        }
    }
}

/** Same primary drum the persistent FORMAT / COLOR / MODE pickers use. */
internal fun recordingCategoryQuickControl(
    sheet: LiveSheet,
    status: CameraStatus,
    bodyName: String = "",
    family: String = "pocket",
): MonitorQuickControl? =
    when (sheet) {
        LiveSheet.FORMAT -> {
            if (CameraCommands.isPhotoMode(status.shootingMode)) {
                MonitorQuickControl(
                    listOf(CaptureLists.PHOTO_FORMAT_READOUT),
                    CaptureLists.PHOTO_FORMAT_READOUT,
                    enabled = false,
                    context = "photo:${status.shootingMode}",
                )
            } else {
                val formatStatus = CaptureLists.withEffectiveVideoFormats(
                    status, bodyName.takeIf { it.isNotEmpty() }?.let { CameraModel(it) },
                )
                val format = VideoFormat.current(formatStatus)
                val aspect = format.resolution.aspect
                val tab = CaptureLists.formatResolutions(formatStatus, aspect).indexOf(format.resolution).coerceAtLeast(0)
                val options = CaptureLists.fpsDrumLabels(formatStatus, tab, aspect)
                if (options.isEmpty()) null
                else {
                    val live = format.frameRate.drumLabel
                    MonitorQuickControl(
                        options, if (live in options) live else "",
                        enabled = CaptureLists.formatPickerEditable(formatStatus),
                        context = "${format.resolution.rawValue}:${status.shootingMode}:${options.joinToString()}",
                    )
                }
            }
        }
        LiveSheet.COLOR -> {
            if (CameraCommands.isPhotoMode(status.shootingMode)) null
            else {
                val options = CaptureLists.colorWheelLabels(status, family, bodyName)
                if (options.isEmpty()) null
                else {
                    val live = CameraCommands.colorLabel(status.colorMode, family)
                    MonitorQuickControl(
                        options, if (live in options) live else "",
                        context = "$family:${options.joinToString()}:${status.isRecording}",
                    )
                }
            }
        }
        LiveSheet.MODE -> {
            val options = CaptureLists.shootingModeLabels(bodyName, status.shootingMode)
            val live = CameraCommands.shootingModeLabel(status.shootingMode, bodyName).orEmpty()
            MonitorQuickControl(options, if (live in options) live else "", enabled = !status.isRecording,
                context = "${status.shootingMode}:$bodyName:${status.isRecording}")
        }
        else -> null
    }

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
                OperatorPrefs.setShutterAngleDegrees(context, command.degrees)
                model.setShutterDenom(command.denom)
            }
            CaptureLists.ShutterDrumCommand.Ignored -> Unit
        }
        LiveSheet.WB -> {
            if (status.wbMode == CameraCommands.WB_CUSTOM) {
                CaptureLists.wbCustomFromKelvinLabel(value, status)?.let { model.setWhiteBalance(it.first, it.second) }
            } else if (CaptureLists.wbSendsAuto(value)) model.setWhiteBalanceAuto()
            else CaptureLists.wbCustomFromStatus(status).let { model.setWhiteBalance(it.first, it.second) }
        }
        LiveSheet.FOCUS -> applyCaptureFocusChoice(value, status, model)
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
            model.session.connectedCamera?.model?.name, model::setShootingMode)
    }
}

/** Shared full-picker and quick-release boundary: never change shooting mode during a take. */
internal fun applyCaptureShootingMode(value: String, status: CameraStatus, bodyName: String?,
    send: (Int) -> Unit) {
    if (status.isRecording) return
    CaptureLists.shootingModeRaw(value, bodyName)?.let(send)
}

internal fun captureQuickFocusControl(status: CameraStatus) = MonitorQuickControl(
    CaptureFocusChoices.labels,
    CaptureFocusChoices.selection(status),
    context = "${status.focusMode}:${status.focusTrack}",
)

/** One native option list for the persistent picker and the readout preview. */
internal object CaptureFocusChoices {
    val labels = com.opencapture.openpocketcine.session.FocusOption.entries.map { it.chip }
    fun selection(status: CameraStatus): String = when (status.focusMode) {
        CameraCommands.FOCUS_SINGLE -> "AF-S"
        CameraCommands.FOCUS_CONTINUOUS -> labels.getOrNull(status.focusTrack + 1)
            ?.takeIf { status.focusTrack in 0..3 }.orEmpty()
        else -> ""
    }
    fun track(label: String): Int? = when (label) {
        "AF-C" -> 0
        "Showcase" -> 1
        "Lock" -> 2
        "Priority" -> 3
        else -> null
    }
}

internal fun applyCaptureFocusChoice(label: String, status: CameraStatus, model: AppModel) {
    applyCaptureFocusChoice(label, status, model::setFocusMode, model::setFocusTrack)
}

internal fun applyCaptureFocusChoice(label: String, status: CameraStatus,
    setFocusMode: (Boolean) -> Unit, setFocusTrack: (Int) -> Unit) {
    if (label !in CaptureFocusChoices.labels || label == CaptureFocusChoices.selection(status)) return
    if (label == "AF-S") setFocusMode(false)
    else CaptureFocusChoices.track(label)?.let { track ->
        if (!CaptureLists.focusIsContinuous(status)) setFocusMode(true)
        if (status.focusTrack != track) setFocusTrack(track)
    }
}

/** A remount, lifecycle interruption, or connection phase transition invalidates every old pointer. */
internal class CaptureQuickLifetime {
    var active by mutableStateOf(false)
        private set
    var epoch by mutableLongStateOf(0L)
        private set
    fun update(active: Boolean) {
        if (this.active != active) { this.active = active; invalidate() }
    }
    fun invalidate() { epoch++ }
}

private data class CaptureQuickSource(
    val session: Any, val cameraID: String?, val phase: ConnectionPhase,
    val lifetime: CaptureQuickLifetime?, val epoch: Long,
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

/** Last synchronous boundary before the existing setter; no delayed command can escape this check. */
internal fun commitCaptureQuickControl(expected: MonitorQuickControl, current: MonitorQuickControl?,
    value: String, enabled: Boolean, send: () -> Unit) {
    if (enabled && expected == current && expected.enabled && value in expected.options && value != expected.selection) send()
}

internal fun releaseCaptureQuickControl(sheet: LiveSheet, expected: MonitorQuickControl, value: String,
    model: AppModel, context: Context, lifetime: CaptureQuickLifetime, enabled: Boolean) {
    val currentStatus = model.session.status.value
    val current = captureQuickControl(sheet, currentStatus, model, context, lifetime)
    commitCaptureQuickControl(expected, current, value,
        enabled && lifetime.active && model.session.phase == ConnectionPhase.LIVE && !model.session.controlBusy.value) {
        applyCaptureQuickControl(sheet, value, currentStatus, model, context)
    }
}

/** Angle HUD: preferred only when it maps to live 1/N, else the nearest live label. */
internal fun captureShutterReadout(
    status: CameraStatus,
    shutterUsesAngle: Boolean,
    preferredAngle: Double,
): String {
    if (status.expoMode == CameraCommands.EXPO_AUTO) {
        return EvComp.fromRaw(status.evComp)?.label ?: "—"
    }
    if (shutterUsesAngle && !CameraCommands.isPhotoMode(status.shootingMode)) {
        if (status.shutterDenom <= 0) return "—"
        return GamepadShutterSync.angleLabel(
            status.shutterDenom,
            status.fps,
            CaptureLists.shutterDenoms(status),
            preferredAngle,
        )
    }
    return if (status.shutterDenom > 0) CaptureLists.shutterLabel(status.shutterDenom) else "—"
}
