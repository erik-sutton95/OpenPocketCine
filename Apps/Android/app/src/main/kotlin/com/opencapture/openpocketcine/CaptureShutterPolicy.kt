package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel

/** Snapshot of the rec lamp when confirmation opened. Any field change dismisses it. */
internal data class RecordConfirmationRequest(
    val shootingMode: Int,
    val recording: Boolean,
    val locked: Boolean,
    val busy: Boolean,
    val phase: ConnectionPhase,
) {
    val canConfirm: Boolean
        get() = !locked && !busy && phase == ConnectionPhase.LIVE &&
            !CameraCommands.isPhotoMode(shootingMode)
}

/** Rec-lamp vs still, and confirmation that cannot fire a stale capture kind. */
internal object CaptureShutterPolicy {
    fun isStillCapture(shootingMode: Int): Boolean = CameraCommands.isPhotoMode(shootingMode)

    fun requiresRecordConfirmation(prefEnabled: Boolean, shootingMode: Int): Boolean =
        prefEnabled && !isStillCapture(shootingMode)

    fun request(
        shootingMode: Int,
        recording: Boolean,
        locked: Boolean,
        busy: Boolean,
        phase: ConnectionPhase,
    ): RecordConfirmationRequest =
        RecordConfirmationRequest(shootingMode, recording, locked, busy, phase)

    fun shouldDismiss(pending: RecordConfirmationRequest?, current: RecordConfirmationRequest): Boolean =
        pending != null && pending != current

    fun canCommit(pending: RecordConfirmationRequest?, current: RecordConfirmationRequest): Boolean =
        pending != null && pending == current && current.canConfirm

    /**
     * Pocket 3 and Action 6 TimeLapse start/stop is `0x02/0x01` `01`/`00`, not Video `0x02/0x02`.
     * Pocket 4 / 4 Pro TimeLapse stays Video record until a later survey.
     */
    fun usesShutterTriggerOnPocket3(shootingMode: Int, cameraName: String?): Boolean =
        shootingMode == CameraCommands.SHOOT_TIMELAPSE &&
            (CameraModel.looksLikePocket3(cameraName.orEmpty()) ||
                CameraModel.looksLikeAction6(cameraName.orEmpty()))

    /** JNI extra for command 36. Empty stays start `01` in the facade. */
    fun shootPhotoExtra(start: Boolean): String = if (start) "1" else "0"

    enum class CaptureKind { PHOTO, SHUTTER_TRIGGER, VIDEO_RECORD }

    fun captureKind(shootingMode: Int, cameraName: String?): CaptureKind =
        when {
            isStillCapture(shootingMode) -> CaptureKind.PHOTO
            usesShutterTriggerOnPocket3(shootingMode, cameraName) -> CaptureKind.SHUTTER_TRIGGER
            else -> CaptureKind.VIDEO_RECORD
        }

    fun portraitSetupOpensMode(shootingMode: Int): Boolean = isStillCapture(shootingMode)

    fun portraitSetupLabel(shootingMode: Int): String =
        if (portraitSetupOpensMode(shootingMode)) "MODE" else "REC SETUP"

    fun portraitSetupSheet(shootingMode: Int): LiveSheet =
        if (portraitSetupOpensMode(shootingMode)) LiveSheet.MODE else LiveSheet.FORMAT

    fun showsVideoTransport(shootingMode: Int): Boolean = !isStillCapture(shootingMode)

    fun showsColorReadout(shootingMode: Int): Boolean = !isStillCapture(shootingMode)

    fun showsAudioControls(shootingMode: Int): Boolean = !isStillCapture(shootingMode)

    fun opening(sheet: LiveSheet, shootingMode: Int): LiveSheet =
        if (!isStillCapture(shootingMode)) sheet
        else when (sheet) {
            LiveSheet.FORMAT, LiveSheet.COLOR -> LiveSheet.MODE
            else -> sheet
        }

    fun retainedSheet(sheet: LiveSheet?, shootingMode: Int): LiveSheet? {
        if (sheet == null || !isStillCapture(shootingMode)) return sheet
        return when (sheet) {
            LiveSheet.FORMAT, LiveSheet.COLOR -> LiveSheet.MODE
            LiveSheet.AUDIO -> null
            else -> sheet
        }
    }

    fun recordingCategoryTabs(shootingMode: Int): List<String> =
        if (isStillCapture(shootingMode)) listOf("Mode") else listOf("Format", "Color", "Mode")

    /** A FORMAT SET failure from a previous mode must not rewrite the new mode HUD. */
    fun canRevertFormatFailure(liveShootingMode: Int, modeAtSet: Int): Boolean =
        liveShootingMode == modeAtSet
}
