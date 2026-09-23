package com.opencapture.openpocketcine.session

/**
 * OpenPocketViewCore `LiveChromeThrottle`: camera telemetry invalidates the HUD at
 * 5 Hz. Operator-facing fields bypass, and control writes (optimistic SETs and their
 * rollbacks) are never delayed. Control code keeps reading the unthrottled status.
 */
internal object LiveChromeThrottle {
    const val STATUS_INTERVAL_MS = 200L

    /** How long to hold [next] before the HUD sees it. Zero publishes now. */
    fun holdMs(shown: CameraStatus, next: CameraStatus, fromTelemetry: Boolean, publishedAtMs: Long, nowMs: Long): Long =
        if (!fromTelemetry || isImmediate(shown, next)) 0L
        else (publishedAtMs + STATUS_INTERVAL_MS - nowMs).coerceAtLeast(0L)

    /** iOS list, plus Android settings that only move when the operator or a mode change moves them. */
    fun isImmediate(a: CameraStatus, b: CameraStatus): Boolean =
        a.isRecording != b.isRecording ||
            a.inPlayback != b.inPlayback ||
            a.colorMode != b.colorMode ||
            a.resolutionCode != b.resolutionCode ||
            a.fpsIndex != b.fpsIndex ||
            a.fps != b.fps ||
            a.expoMode != b.expoMode ||
            a.focusMode != b.focusMode ||
            a.focusTrack != b.focusTrack ||
            a.wbMode != b.wbMode ||
            a.wbKelvin != b.wbKelvin ||
            a.wbTint != b.wbTint ||
            a.shootingMode != b.shootingMode ||
            a.audioChannel != b.audioChannel ||
            a.vocalBoost != b.vocalBoost ||
            a.windNr != b.windNr ||
            a.directionalAudio != b.directionalAudio ||
            a.audioDspAt2 != b.audioDspAt2 ||
            a.selfieFlip != b.selfieFlip ||
            a.glamourEnabled != b.glamourEnabled ||
            a.evComp != b.evComp ||
            a.isoLimit != b.isoLimit ||
            a.apertureStrategy != b.apertureStrategy ||
            a.availableShutterDenoms != b.availableShutterDenoms ||
            a.availableIsoIndices != b.availableIsoIndices ||
            a.availableColorModes != b.availableColorModes ||
            a.availableVideoFormats != b.availableVideoFormats ||
            a.availableApertureStrategies != b.availableApertureStrategies ||
            a.zoomFactorRaw != b.zoomFactorRaw ||
            a.zoomFactor != b.zoomFactor ||
            a.zoomLens != b.zoomLens ||
            a.gimbalModeFamily != b.gimbalModeFamily ||
            a.gimbalTiltLock != b.gimbalTiltLock ||
            a.gimbalSpeed != b.gimbalSpeed ||
            a.gimbalFace != b.gimbalFace
}
