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
import com.opencapture.openpocketcine.session.CameraStatus

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
            val angle = model.shutterUsesAngle && !auto
            val selected = if (auto) CaptureLists.reseatEv(status).selection else
                CaptureLists.reseatShutter(status, if (angle) 1 else 0, false,
                    OperatorPrefs.shutterAngleDegrees(context)).selection
            chrome(MonitorQuickControl(if (auto) CaptureLists.evLabels else if (angle) ShutterAngle.labels else CaptureLists.shutterLabels(status),
                selected, enabled = !auto || !model.facePriorityExposureEnabled,
                context = "${status.fps}:${status.availableShutterDenoms}:${status.expoMode}:$angle"))
        }
        LiveSheet.WB -> chrome(
            if (status.wbMode == CameraCommands.WB_CUSTOM)
                MonitorQuickControl(CaptureLists.kelvinLabels, CaptureLists.wbDrumSelection(status), context = "${CaptureLists.currentTint(status)}")
            else MonitorQuickControl(CaptureLists.wbModeRows, CaptureLists.wbModeRowSelected(status),
                context = "${status.wbMode}:${CaptureLists.currentKelvin(status)}:${CaptureLists.currentTint(status)}"))
        LiveSheet.FOCUS -> chrome(captureQuickFocusControl(status))
        LiveSheet.EXPO -> chrome(MonitorQuickControl(CaptureLists.expoLabels, CaptureLists.expoLabel(status.expoMode)))
        LiveSheet.AUDIO -> chrome(MonitorQuickControl(CaptureLists.audioChannelLabels, CaptureLists.audioChannelLabel(status.audioChannel).orEmpty()))
        else -> null
    }
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
            CaptureLists.isEvSheet(sheet, status.expoMode), model.shutterUsesAngle && status.expoMode != CameraCommands.EXPO_AUTO,
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
        else -> Unit
    }
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
