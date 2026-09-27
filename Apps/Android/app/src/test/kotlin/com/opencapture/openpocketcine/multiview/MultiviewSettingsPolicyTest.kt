package com.opencapture.openpocketcine.multiview

import com.opencapture.openpocketcine.LiveSheet
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MultiviewSettingsPolicyTest {
    @Test fun nativeCategoriesFollowCameraCapabilitiesAndShootingMode() {
        val pocket = CameraModel("Osmo Pocket 4")
        val video = CameraStatus(shootingMode = CameraCommands.SHOOT_VIDEO)
        assertEquals(listOf(LiveSheet.ISO, LiveSheet.SHUTTER, LiveSheet.EXPO, LiveSheet.WB,
            LiveSheet.FOCUS, LiveSheet.FORMAT, LiveSheet.COLOR, LiveSheet.MODE, LiveSheet.AUDIO),
            multiviewSettingsCategories(pocket, video))
        val photo = multiviewSettingsCategories(pocket, video.copy(shootingMode = CameraCommands.SHOOT_PHOTO))
        assertTrue(photo.containsAll(listOf(LiveSheet.ISO, LiveSheet.WB, LiveSheet.MODE)))
        assertFalse(photo.any { it in listOf(LiveSheet.FORMAT, LiveSheet.COLOR, LiveSheet.AUDIO) })
        val nano = CameraModel("Osmo Nano", family = "nano", supportsFocusMode = false, supportsTapFocus = false)
        assertFalse(LiveSheet.FOCUS in multiviewSettingsCategories(nano, video))
        assertFalse(LiveSheet.APERTURE in multiviewSettingsCategories(pocket, video))
        assertTrue(LiveSheet.APERTURE in multiviewSettingsCategories(CameraModel("Osmo Action 6"), video))
    }

    @Test fun recordingLocksModeFormatAndColorButKeepsExposureControls() {
        for (sheet in LiveSheet.entries) {
            assertFalse(multiviewSettingsLocked(sheet, false))
            assertEquals(sheet in listOf(LiveSheet.MODE, LiveSheet.FORMAT, LiveSheet.COLOR),
                multiviewSettingsLocked(sheet, true))
        }
    }
}
