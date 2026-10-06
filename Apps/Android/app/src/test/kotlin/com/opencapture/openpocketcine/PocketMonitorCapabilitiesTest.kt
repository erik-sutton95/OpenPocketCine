package com.opencapture.openpocketcine

import com.opencapture.opencine.core.CapabilitySnapshot
import com.opencapture.opencine.core.MonitorLayoutCapabilities
import com.opencapture.opencine.dji.DjiCameraSessionAdapter
import com.opencapture.opencine.vocabulary.CameraModel
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pocket main laid out the timecode and audio on every body (`PocketMonitorCapabilities` `timecode = true`, `audio = true`). */
class PocketMonitorCapabilitiesTest {
    private fun declared(model: CameraModel?) = MonitorLayoutCapabilities(
        CapabilitySnapshot(
            timecode = DjiCameraSessionAdapter.timecodeSupport(model),
            audioLevels = DjiCameraSessionAdapter.audioLevelsSupport(model),
        ),
        appLayoutBase,
    )

    @Test fun singleViewShowsTheTimecodeOnANano() {
        val nano = declared(CameraModel(name = "Osmo Nano", family = "nano", verified = true))
        // Multi View reads the declaration and hides the Nano clock, as main did.
        assertFalse(nano.timecode)
        assertTrue(singleViewLayout(nano).timecode)
        assertTrue(singleViewLayout(declared(CameraModel(name = "Osmo Pocket 3", verified = true))).timecode)
    }

    @Test fun audioPinAndTileStayOfferedBeforeTheBodyIsKnown() {
        assertTrue(singleViewLayout(declared(null)).audio)
        assertTrue(singleViewLayout(declared(null)).timecode)
    }
}
