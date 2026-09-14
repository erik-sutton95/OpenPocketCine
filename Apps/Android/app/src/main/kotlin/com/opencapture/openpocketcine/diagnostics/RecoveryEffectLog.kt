package com.opencapture.openpocketcine.diagnostics

/** Policy action versus committed effect. Does not own recovery. */
internal enum class RecoveryAction(val wire: String) {
    ENABLE("enable"),
    DECODER("decoder"),
    ENDPOINT("endpoint"),
    REJOIN("rejoin"),
    SESSION("session"),
}

internal enum class RecoveryEffect(val wire: String) {
    REQUESTED("requested"),
    BLOCKED("blocked"),
    SENT("sent"),
    FRESH_PICTURE("freshPicture"),
}

internal enum class RecoveryReason(val wire: String) {
    OUTPUT_SILENCE("outputSilence"),
    NOT_READY("notReady"),
    OVERLAP("overlap"),
    PLAYBACK("playback"),
    PATH("path"),
    SERIAL_GATE("serialGate"),
    MEDIA("media"),
    WATCHDOG("watchdog"),
    PICTURE_DEADLINE("pictureDeadline"),
    OUTPUT_RESUMED("outputResumed"),
    UDP_ALIVE("udpAlive"),
}

internal object RecoveryEffectLog {
    fun line(action: RecoveryAction, effect: RecoveryEffect, reason: RecoveryReason): String =
        "recovery: action=${action.wire} effect=${effect.wire} reason=${reason.wire}"
}
