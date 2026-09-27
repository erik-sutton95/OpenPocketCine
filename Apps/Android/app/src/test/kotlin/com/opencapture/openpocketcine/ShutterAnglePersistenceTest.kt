package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.FormatPin
import com.opencapture.openpocketcine.session.VideoFormat
import com.opencapture.openpocketcine.session.VideoFrameRate
import com.opencapture.openpocketcine.session.VideoResolution
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class ShutterAnglePersistenceTest {
    @Test fun dependentAngleHasABoundedConfirmationWindowAndDirectSpeedCancelsIt() {
        val expected = VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60)
        val previous = CameraStatus(resolutionCode = VideoResolution.P4K.rawValue,
            fpsIndex = VideoFrameRate.FPS24.rawValue, fps = 24)
        val pin = FormatPin(expected, deadlineElapsedRealtime = 2_000, shutterAngle = 180.0)
        assertNotNull(VideoFormat.absorbStale(previous, pin, 2_100).second)
        assertNotNull(VideoFormat.absorbStale(previous, pin, 7_999).second)
        assertNull(VideoFormat.absorbStale(previous, pin, 8_000).second)
        pin.shutterAngle = null
        assertNull(VideoFormat.absorbStale(previous, pin, 2_100).second)
    }

    @Test fun fpsTelemetryAndPickerReseatingCannotReplaceTheChosenAngle() {
        var preferred = 180.0
        for ((fps, shutter) in listOf(24 to 48, 60 to 48, 60 to 120, 30 to 120, 30 to 60)) {
            val status = CameraStatus(
                fps = fps, shutterDenom = shutter, expoMode = CameraCommands.EXPO_MANUAL,
                availableShutterDenoms = listOf(24, 48, 50, 60, 120),
            )
            val seat = CaptureLists.reseatShutterAngle(status, preferred)
            // This is the same assignment performed by LiveControlSheet.applySeat.
            preferred = seat.preferredAngle
            assertEquals(180.0, preferred, "FPS=$fps with delayed shutter=1/$shutter")
            assertFalse(seat.persistAngle, "Telemetry is not an operator preference edit")
        }
    }
}
