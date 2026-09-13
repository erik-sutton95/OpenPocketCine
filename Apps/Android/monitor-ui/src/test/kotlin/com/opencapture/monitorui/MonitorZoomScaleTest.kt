package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MonitorZoomScaleTest {
    @Test fun dialTicksAndLabelsUseHundredths() {
        assertEquals(1.53, MonitorZoomScale.quantized(1.534, maximum = 12.0), 1e-9)
        assertEquals(1.54, MonitorZoomScale.quantized(1.536, maximum = 12.0), 1e-9)
        assertEquals("1.53×", MonitorZoomScale.dialLabel(1.534, maximum = 12.0))
        assertEquals("1.00×", MonitorZoomScale.dialLabel(1.0, maximum = 12.0))
        assertTrue(MonitorZoomScale.isLabeledTick(1.5, maximum = 12.0))
        assertTrue(MonitorZoomScale.isLabeledTick(1.50, maximum = 12.0))
        assertFalse(MonitorZoomScale.isLabeledTick(1.53, maximum = 12.0))
    }
}
