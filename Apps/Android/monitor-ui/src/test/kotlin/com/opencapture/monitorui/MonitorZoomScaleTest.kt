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
        val ticks = MonitorZoomScale.minorTickPositions()
        assertEquals(19, ticks.size)
        assertEquals(0.0, ticks.first(), 1e-9)
        assertEquals(1.0, ticks.last(), 1e-9)
        assertEquals(ticks[1] - ticks[0], ticks[2] - ticks[1], 1e-9)
    }

    @Test fun slowRotationSnapsToWholeStopsAndFastRotationDoesNot() {
        assertEquals(3.0, MonitorZoomScale.slowSnap(2.98, 2.97, maximum = 12.0), 1e-9)
        assertEquals(3.0, MonitorZoomScale.slowSnap(3.02, 3.00, maximum = 12.0), 1e-9)
        assertEquals(3.08, MonitorZoomScale.slowSnap(3.08, 3.00, maximum = 12.0), 1e-9)
        assertEquals(3.12, MonitorZoomScale.slowSnap(3.12, 3.00, maximum = 12.0), 1e-9)
        assertEquals(1.52, MonitorZoomScale.slowSnap(1.52, 1.51, maximum = 12.0), 1e-9)
        assertEquals(6.0, MonitorZoomScale.slowSnap(6.02, 6.00, maximum = 12.0), 1e-9)
    }
}
