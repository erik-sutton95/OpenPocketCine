package com.opencapture.openpocketcine.multiview

import com.opencapture.monitorui.MultiviewSafeArea
import com.opencapture.openpocketcine.LiveSheet
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MultiviewSettingsPolicyTest {
    @Test fun popupStaysInsideTheSafeViewportAcrossCutoutsAndResizedWindows() {
        for ((width, height) in listOf(375f to 667f, 667f to 375f, 393f to 852f,
            852f to 393f, 500f to 650f, 600f to 650f, 744f to 1133f, 1194f to 834f)) {
            for (safe in listOf(MultiviewSafeArea(top = 59f, bottom = 34f),
                MultiviewSafeArea(leading = 59f, bottom = 21f),
                MultiviewSafeArea(trailing = 59f, bottom = 21f))) {
                val panel = multiviewSettingsBounds(width, height, safe)
                assertTrue(panel.x >= safe.leading + 16f)
                assertTrue(panel.y >= safe.top + 16f)
                assertTrue(panel.maxX <= width - safe.trailing - 16f)
                assertTrue(panel.maxY <= height - safe.bottom - 16f)
                assertTrue(panel.width <= 560f && panel.height <= 520f)
            }
        }
    }

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
