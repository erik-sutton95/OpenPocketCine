package com.opencapture.openpocketcine

import android.content.Context
import com.opencapture.monitorui.MonitorQuickControl
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus

/** Reuses the persistent picker's production choices and typed action methods. */
internal fun captureQuickControl(sheet: LiveSheet, status: CameraStatus, model: AppModel,
    context: Context): MonitorQuickControl? {
    val body = model.session.connectedCamera?.model?.name.orEmpty()
    return when (sheet) {
        LiveSheet.ISO -> {
            val seat = IsoSheetLogic.reseat(status, body)
            MonitorQuickControl(if (IsoSheetLogic.isAutoTab(status, seat.selectedMode))
                CaptureLists.isoAutoLabels(status, body) else CaptureLists.isoDrumLabels(status),
                seat.drumSelection, CaptureLists.isoMarkedLabels(status), context = "${status.colorMode}")
        }
        LiveSheet.SHUTTER -> {
            val auto = CaptureLists.isEvSheet(sheet, status.expoMode)
            val angle = model.shutterUsesAngle && !auto
            val selected = if (auto) CaptureLists.reseatEv(status).selection else
                CaptureLists.reseatShutter(status, if (angle) 1 else 0, false,
                    OperatorPrefs.shutterAngleDegrees(context)).selection
            MonitorQuickControl(if (auto) CaptureLists.evLabels else if (angle) ShutterAngle.labels else CaptureLists.shutterLabels(status),
                selected, enabled = !auto || !model.facePriorityExposureEnabled,
                context = "${status.fps}:${status.availableShutterDenoms}:${status.expoMode}:$angle")
        }
        LiveSheet.WB -> if (status.wbMode == CameraCommands.WB_CUSTOM) {
            MonitorQuickControl(CaptureLists.kelvinLabels, CaptureLists.wbDrumSelection(status), context = "${CaptureLists.currentTint(status)}")
        } else MonitorQuickControl(CaptureLists.wbModeRows, CaptureLists.wbModeRowSelected(status))
        LiveSheet.FOCUS -> MonitorQuickControl(listOf("AF-S", "AF-C"),
            if (CaptureLists.focusIsContinuous(status)) "AF-C" else "AF-S", context = "${status.focusTrack}")
        LiveSheet.EXPO -> MonitorQuickControl(CaptureLists.expoLabels, CaptureLists.expoLabel(status.expoMode))
        LiveSheet.AUDIO -> MonitorQuickControl(CaptureLists.audioChannelLabels, CaptureLists.audioChannelLabel(status.audioChannel).orEmpty())
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
        LiveSheet.FOCUS -> model.setFocusMode(value == "AF-C")
        LiveSheet.EXPO -> CaptureLists.expoModeFromLabel(value)?.let(model::setExpoMode)
        LiveSheet.AUDIO -> CaptureLists.audioChannelValue(value)?.let(model::setAudioChannel)
        else -> Unit
    }
}
