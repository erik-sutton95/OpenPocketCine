package com.opencapture.openpocketcine.lut

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LutExposureCompensationTest {
    @Test
    fun snapsHalfStopsAndClamps() {
        assertEquals(0.0, LutExposureCompensation.snap(0.0))
        assertEquals(0.0, LutExposureCompensation.snap(0.24))
        assertEquals(0.5, LutExposureCompensation.snap(0.26))
        assertEquals(1.0, LutExposureCompensation.snap(1.2))
        assertEquals(-1.5, LutExposureCompensation.snap(-1.26))
        assertEquals(3.0, LutExposureCompensation.snap(3.4))
        assertEquals(-3.0, LutExposureCompensation.snap(-4.0))
        assertEquals(0.0, LutExposureCompensation.snap(Double.NaN))
    }

    @Test
    fun labelsMatchIOS() {
        assertEquals("0.0", LutExposureCompensation.label(0.0))
        assertEquals("+0.5", LutExposureCompensation.label(0.5))
        assertEquals("+2.0", LutExposureCompensation.label(2.0))
        assertEquals("−1.5", LutExposureCompensation.label(-1.5))
        assertEquals("−3.0", LutExposureCompensation.label(-3.0))
        assertEquals("Exposure", LutExposureCompensation.TITLE)
        assertTrue(LutExposureCompensation.HELP.contains("ETTR"))
    }

    @Test
    fun stepperStopsAtTheRails() {
        assertFalse(LutExposureCompensation.canStep(-3.0, -0.5))
        assertTrue(LutExposureCompensation.canStep(-3.0, 0.5))
        assertFalse(LutExposureCompensation.canStep(3.0, 0.5))
        assertEquals(0.5, LutExposureCompensation.stepped(1.0, -0.5))
        assertEquals(3.0, LutExposureCompensation.stepped(3.0, 0.5))
        assertEquals(0.5, LutExposureCompensation.linearGain(-1.0), 0.0001)
        assertEquals(2.0, LutExposureCompensation.linearGain(1.0), 0.0001)
    }
}
