package com.opencapture.openpocketcine

import com.opencapture.monitorui.isRunning
import com.opencapture.opencine.appkit.VoiceCommand
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.appkit.VoiceControlTarget
import com.opencapture.opencine.appkit.executeVoiceCommand
import com.opencapture.opencine.core.CommandDispatchAdmission
import com.opencapture.opencine.dji.DjiCommandAdmission

internal fun AppModel.voiceControlAvailable(allowSettings: Boolean = false): Boolean {
    val cover = shell.state.value.cover
    return isLive && (cover == null || allowSettings && cover == ShellModel.Cover.SETTINGS) &&
        !operatorSession.locked && !session.browsingMedia &&
        liveStream?.coordinator?.state?.value?.phase?.isRunning != true
}

internal suspend fun AppModel.executePocketVoiceCommand(
    command: VoiceCommand, isCurrent: () -> Boolean, armedTarget: VoiceControlTarget,
): String {
    val source = session.control
    val target = VoiceControlTarget.from(source.snapshots.value)
    val owner = session.commandOwner
    if (target == null || target.session != armedTarget.session || target.epoch != armedTarget.epoch ||
        owner == null || control.state.value.session !== source || !isCurrent() ||
        !voiceControlAvailable() || session.controlBusy.value
    ) return "Camera control is unavailable."

    val lens = session.voiceOpticalLens
    if (command.changesSettings && session.hasDualOpticalLenses && lens == null) {
        return "The camera has not reported its active lens."
    }
    val native = DjiCommandAdmission(owner) {
        isCurrent() && voiceControlAvailable() && VoiceControlTarget.from(source.snapshots.value) == target &&
            (!command.changesSettings || (!control.state.value.recordPending &&
                (!session.hasDualOpticalLenses || session.voiceOpticalLens == lens)))
    }
    val admission = CommandDispatchAdmission(target.session, target.epoch, { native.isCurrent }) {
        source.submit(it, native)
    }
    return control.executeVoiceCommand(command, target, cameraPresets, admission)
}
