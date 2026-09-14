package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals

class MonitorExposureReadoutTest {
    @Test
    fun autoEvCaptionKeepsTheCameraChosenShutterReadable() {
        assertEquals("EV 1/200s", MonitorExposureReadout.autoEvCaption(200))
        assertEquals("EV 1/16000s", MonitorExposureReadout.autoEvCaption(16_000))
        assertEquals("EV", MonitorExposureReadout.autoEvCaption(0))
        assertEquals("EV", MonitorExposureReadout.autoEvCaption(-1))
    }
}
