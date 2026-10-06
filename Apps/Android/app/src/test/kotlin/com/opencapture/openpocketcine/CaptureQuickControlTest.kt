package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.LiveSheet
import com.opencapture.opencine.vocabulary.CameraCommands
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class CaptureQuickControlTest {
    @Test fun capturedEvPanelCannotBecomeAManualShutterEditor() {
        val captured = com.opencapture.opencine.appkit.MonitorCaptureField(
            com.opencapture.opencine.core.SettingKey.EXPOSURE_COMPENSATION, "EV", null, emptyList(), null)
        assertEquals(captured, retainedCapturePanelField(captured, LiveSheet.SHUTTER, CameraCommands.EXPO_AUTO))
        assertEquals(null, retainedCapturePanelField(captured, LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL))
        val manual = captured.copy(key = com.opencapture.opencine.core.SettingKey.SHUTTER, title = "SHUTTER")
        assertEquals(manual, retainedCapturePanelField(manual, LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL))
        assertEquals(null, retainedCapturePanelField(manual, LiveSheet.SHUTTER, CameraCommands.EXPO_AUTO))
    }

    @Test fun commonFocusKeepsUnknownAndTrackedAfCOnTheNativeStrategyPath() {
        assertEquals(com.opencapture.opencine.core.SettingValue.FocusMode(com.opencapture.opencine.core.FocusMode.SINGLE),
            commonFocusValue("AF-S", null))
        assertEquals(com.opencapture.opencine.core.SettingValue.FocusMode(com.opencapture.opencine.core.FocusMode.CONTINUOUS),
            commonFocusValue("AF-C", com.opencapture.opencine.vocabulary.FocusTrackMode.DEFAULT))
        assertNull(commonFocusValue("AF-C", null))
        assertNull(commonFocusValue("AF-C", com.opencapture.opencine.vocabulary.FocusTrackMode.PRODUCT_SHOWCASE))
        assertNull(commonFocusValue("Showcase", com.opencapture.opencine.vocabulary.FocusTrackMode.DEFAULT))
    }
}
