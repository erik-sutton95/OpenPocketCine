package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.core.MonitorLayoutCapabilities
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.vocabulary.CameraCommands
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Pocket's capture sheet host values, as on main. */
class CaptureSheetHostTest {
    @Test fun isoShutterEvWhiteBalanceAndFocusOpenThroughCore() {
        val manual = CameraCommands.EXPO_MANUAL
        assertEquals(SettingKey.ISO, capturePanelSettingKey(LiveSheet.ISO, manual))
        assertEquals(SettingKey.SHUTTER, capturePanelSettingKey(LiveSheet.SHUTTER, manual))
        assertEquals(SettingKey.EXPOSURE_COMPENSATION, capturePanelSettingKey(LiveSheet.SHUTTER, CameraCommands.EXPO_AUTO))
        assertEquals(SettingKey.WHITE_BALANCE, capturePanelSettingKey(LiveSheet.WB, manual))
        assertEquals(SettingKey.FOCUS_MODE, capturePanelSettingKey(LiveSheet.FOCUS, manual))
        for (sheet in LiveSheet.entries - setOf(LiveSheet.ISO, LiveSheet.SHUTTER, LiveSheet.WB, LiveSheet.FOCUS)) {
            assertNull(capturePanelSettingKey(sheet, manual), "$sheet stays on the typed path")
        }
    }

    @Test fun locksFollowTheSessionAndTheFormatPinIsReadLive() {
        var aeLock: Any? = null
        var awbKelvin: Int? = null
        var pinned = true
        val state = pocketCaptureSessionState({ aeLock }, { awbKelvin }, { true }, { pinned }, { MonitorLayoutCapabilities() })
        assertFalse(state.aeLocked)
        assertNull(state.awbLockKelvin)
        assertTrue(state.awbLockOffered)
        assertTrue(state.formatPinned)
        aeLock = Any()
        awbKelvin = 5600
        pinned = false // the pin expired: the FORMAT sheet reseats again without a new state
        assertTrue(state.aeLocked)
        assertEquals(5600, state.awbLockKelvin)
        assertFalse(state.formatPinned)
    }

    @Test fun focusAndIrisFollowTheLayoutAndNativeIsoHopAlwaysShows() {
        val none = pocketCaptureSessionState({ null }, { null }, { false }, { false }, { MonitorLayoutCapabilities() })
        assertFalse(none.focusModeSupported)
        assertFalse(none.irisSupported)
        assertTrue(none.nativeIsoHopSupported, "Every DJI body hops native ISO, even before a body is known")
        val both = pocketCaptureSessionState({ null }, { null }, { false }, { false },
            { MonitorLayoutCapabilities(focus = true, iris = true) })
        assertTrue(both.focusModeSupported)
        assertTrue(both.irisSupported)
        assertTrue(both.nativeIsoHopSupported)
    }
}
